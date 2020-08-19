---
layout: post
categories: Kubernetes Golang
title: 编写一个动态准入控制来实现自动化
date: 2020-08-19 13:44:20 +0800
description: 编写一个动态准入控制来实现自动化
keywords: 准入控制,kubernetes
catalog: true
multilingual: false
tags: Kubernetes Golang
---

> 前段时间弄了一个 imgsync 的工具把 gcr.io 的镜像搬运到了 Docker Hub，但是即使这样我每次还是需要编辑 yaml 配置手动改镜像名称；所以我萌生了一个想法: 能不能自动化这个过程？

## 一、准入控制介绍

在 Kubernetes 整个请求链路中，请求通过认证和授权之后、对象被持久化之前需要通过一连串的 "准入控制拦截器"；这些准入控制器负载验证请求的合法性，必要情况下也可以对请求进行修改；默认准入控制器编写在 kube-apiserver 的代码中，针对于当前 kube-apiserver 默认启用的准入控制器你可以通过以下命令查看:

``` sh
kube-apiserver -h | grep enable-admission-plugins
```

具体每个准入控制器的作用可以通过 [Using Admission Controllers](https://kubernetes.io/zh/docs/reference/access-authn-authz/admission-controllers/) 文档查看。在这些准入控制器中有两个特殊的准入控制器 `MutatingAdmissionWebhook` 和 `ValidatingAdmissionWebhook`。**这两个准入控制器以 WebHook 的方式提供扩展能力，从而我们可以实现自定义的一些功能。当我们在集群中创建相关 WebHook 配置后，我们配置中描述的想要关注的资源在集群中创建、修改等都会触发 WebHook，我们再编写具体的应用来响应 WebHook 即可完成特定功能。**

## 二、动态准入控制

动态准入控制实际上指的就是上面所说的两个 WebHook，在使用动态准入控制时需要一些先决条件:

- 确保 Kubernetes 集群版本至少为 v1.16 (以便使用 `admissionregistration.k8s.io/v1 API`)或者 v1.9 (以便使用 `admissionregistration.k8s.io/v1beta1` API)。
- 确保启用 MutatingAdmissionWebhook 和 ValidatingAdmissionWebhook 控制器。 
- 确保启用 `admissionregistration.k8s.io/v1` 或 `admissionregistration.k8s.io/v1beta1` API。

如果要使用 Mutating Admission Webhook，在满足先决条件后，需要在系统中 create 一个 MutatingWebhookConfiguration:

``` yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: "mutating-webhook.mritd.me"
  namespace: kube-addons
webhooks:
  - name: "mutating-webhook.mritd.me"
    rules:
      - apiGroups:   [""]
        apiVersions: ["v1"]
        operations:  ["CREATE","UPDATE"]
        resources:   ["pods"]
        scope:       "Namespaced"
    clientConfig:
      service:
        name: "mutating-webhook"
        namespace: "kube-addons"
        path: /print
      caBundle: ${CA_BUNDLE}
    admissionReviewVersions: ["v1", "v1beta1"]
    sideEffects: None
    timeoutSeconds: 5
    failurePolicy: Ignore
    namespaceSelector:
      matchLabels:
        mutating-webhook.mritd.me: "true"
```

同样要使用 Validating Admission Webhook 也需要类似的配置:

``` yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: "validating-webhook.mritd.me"
webhooks:
  - name: "validating-webhook.mritd.me"
    rules:
      - apiGroups:   [""]
        apiVersions: ["v1"]
        operations:  ["CREATE","UPDATE"]
        resources:   ["pods"]
        scope:       "Namespaced"
    clientConfig:
      service:
        name: "validating-webhook"
        namespace: "kube-addons"
        path: /print
      caBundle: ${CA_BUNDLE}
    admissionReviewVersions: ["v1", "v1beta1"]
    sideEffects: None
    timeoutSeconds: 5
    failurePolicy: Ignore
    namespaceSelector:
      matchLabels:
        validating-webhook.mritd.me: "true"
```


从配置文件中可以看到，`webhooks.rules` 段落中具体指定了我们想要关注的资源及其行为，`webhooks.clientConfig` 中指定了 webhook 触发后将其发送到那个地址以及证书配置等，这些具体字段的含义可以通过官方文档 [Dynamic Admission Control](https://kubernetes.io/zh/docs/reference/access-authn-authz/extensible-admission-controllers/) 来查看。

**值得注意的是 Mutating Admission Webhook 会在 Validating Admission Webhook 之前触发；Mutating Admission Webhook 可以修改用户的请求，比如自动调整镜像名称、增加注解等，而 Validating Admission Webhook 只能做校验(true or false)，不可以进行修改操作。**

## 三、编写一个 WebHook

> **郑重提示: 本部分文章请结合 [goadmission](https://github.com/mritd/goadmission) 框架源码进行阅读。**

### 3.1、大体思路

在编写之前一般我们先大体了解一下流程并制订方案再去实现，边写边思考适合在细节实现上，对于整体的把控需要提前作好预习。针对于这个准入控制的 WebHook 来说，根据其官方文档大致总结重点如下:

- WebHook 接收者就是一个标准的 HTTP Server，请求方式是 POST + JSON
- 请求响应都是一个 AdmissionReview 对象
- 响应时需要请求时的 UID(`request.uid`)
- 响应时 Mutating Admission Webhook 可以包含对请求的修改信息，格式为 JSONPatch

有了以上信息以后便可以知道编写 WebHook 需要的东西，根据这些信息目前我作出的大体方案如下:

- 最起码我们要有个 HTTP Server，考虑到后续可能会同时处理多种 WebHook，所以需要一个带有路径匹配的 HTTP 框架，Gin 什么的虽然不错但是太重，最终选择简单轻量的 `gorilla/mux`。
- 应该做好适当的抽象，因为对于响应需要包含的 UID 等限制在每个请求都有可以提取出来自动化完成。
- 针对于 Mutating Admission Webhook 响应的 JSONPatch 可以弄个结构体然后直接反序列化。

### 3.2、AdmissionReview 对象

基于 3.1 部分的分析可以知道，WebHook 接收和响应都是一个 AdmissionReview 对象，在查看源码以后可以看到 AdmissionReview 结构如下:

![AdmissionReview](https://cdn.oss.link/markdown/jro62.png)

从代码的命名中可以很清晰的看出，在请求发送到 WebHook 时我们只需要关注内部的 AdmissionRequest(实际入参)，在我们编写的 WebHook 处理完成后只需要返回包含有 AdmissionResponse(实际返回体) 的 AdmissionReview 对象即可；总的来说 **AdmissionReview 对象是个套壳，请求是里面的 AdmissionRequest，响应是里面的 AdmissionResponse**。

### 3.3、Hello World

有了上面的一些基础知识，我们就可以简单的实行一个什么也不干的 WebHook 方法(本地无法直接运行，重点在于思路):

``` go
// printRequest 接收 AdmissionRequest 对象并将其打印到到控制台，接着不做任何处理直接返回一个 AdmissionResponse 对象
func printRequest(request *admissionv1.AdmissionRequest) (*admissionv1.AdmissionResponse, error) {
	bs, err := jsoniter.MarshalIndent(request, "", "    ")
	if err != nil {
		return nil, err
	}
	logger.Infof("print request: %s", string(bs))

	return &admissionv1.AdmissionResponse{
		Allowed: true,
		Result: &metav1.Status{
			Code:    http.StatusOK,
			Message: "Hello World",
		},
	}, nil
}
```

上面这个 `printRequest` 方法最细粒度的控制到只面向我们的实际请求和响应；而对于 WebHook Server 来说其接到的是 http 请求，**所以我们还需要在外面包装一下，将 http 请求转换为 AdmissionReview 并提取 AdmissionRequest 再调用上面的 `printRequest` 来处理，最后将返回结果重新包装为 AdmissionReview 重新返回；整体的代码如下**

``` go
// 通用的错误返回方法
func responseErr(handlePath, msg string, httpCode int, w http.ResponseWriter) {
	logger.Errorf("handle func [%s] response err: %s", handlePath, msg)
	review := &admissionv1.AdmissionReview{
		Response: &admissionv1.AdmissionResponse{
			Allowed: false,
			Result: &metav1.Status{
				Message: msg,
			},
		},
	}
	bs, err := jsoniter.Marshal(review)
	if err != nil {
		logger.Errorf("failed to marshal response: %v", err)
		w.WriteHeader(http.StatusInternalServerError)
		_, _ = w.Write([]byte(fmt.Sprintf("failed to marshal response: %s", err)))
	}

	w.WriteHeader(httpCode)
	_, err = w.Write(bs)
	logger.Debugf("write err response: %d: %v: %v", httpCode, review, err)
}

// printRequest 接收 AdmissionRequest 对象并将其打印到到控制台，接着不做任何处理直接返回一个 AdmissionResponse 对象
func printRequest(request *admissionv1.AdmissionRequest) (*admissionv1.AdmissionResponse, error) {
	bs, err := jsoniter.MarshalIndent(request, "", "    ")
	if err != nil {
		return nil, err
	}
	logger.Infof("print request: %s", string(bs))

	return &admissionv1.AdmissionResponse{
		Allowed: true,
		Result: &metav1.Status{
			Code:    http.StatusOK,
			Message: "Hello World",
		},
	}, nil
}

// http server 的处理方法
func headler(w http.ResponseWriter, r *http.Request) {
			defer func() { _ = r.Body.Close() }()
			w.Header().Set("Content-Type", "application/json")

			// 读取 body，出错直接返回
			reqBs, err := ioutil.ReadAll(r.Body)
			if err != nil {
				responseErr(handlePath, err.Error(), http.StatusInternalServerError, w)
				return
			}
			if reqBs == nil || len(reqBs) == 0 {
				responseErr(handlePath, "request body is empty", http.StatusBadRequest, w)
				return
			}
			logger.Debugf("request body: %s", string(reqBs))

			// 将 body 反序列化为 AdmissionReview
			reqReview := admissionv1.AdmissionReview{}
			if _, _, err := deserializer.Decode(reqBs, nil, &reqReview); err != nil {
				responseErr(handlePath, fmt.Sprintf("failed to decode req: %s", err), http.StatusInternalServerError, w)
				return
			}
			if reqReview.Request == nil {
				responseErr(handlePath, "admission review request is empty", http.StatusBadRequest, w)
				return
			}

			// 提取 AdmissionRequest 并调用 printRequest 处理
			resp, err := printRequest(reqReview.Request)
			if err != nil {
				responseErr(handlePath, fmt.Sprintf("admission func response: %s", err), http.StatusForbidden, w)
				return
			}
			if resp == nil {
				responseErr(handlePath, "admission func response is empty", http.StatusInternalServerError, w)
				return
			}
			
			// 复制 AdmissionRequest 中的 UID 到 AdmissionResponse 中(必须进行，否则会导致响应无效)
			resp.UID = reqReview.Request.UID
			// 复制 reqReview.TypeMeta 到新的响应 AdmissionReview 中
			respReview := admissionv1.AdmissionReview{
				TypeMeta: reqReview.TypeMeta,
				Response: resp,
			}
			
			// 重新序列化响应并返回
			respBs, err := jsoniter.Marshal(respReview)
			if err != nil {
				responseErr(handlePath, fmt.Sprintf("failed to marshal response: %s", err), http.StatusInternalServerError, w)
				logger.Errorf("the expected response is: %v", respReview)
				return
			}
			w.WriteHeader(http.StatusOK)
			_, err = w.Write(respBs)
			logger.Debugf("write response: %d: %s: %v", http.StatusOK, string(respBs), err)
		}
```

### 3.4、抽象出框架

编写了简单的 Hello World 以后可以看出，真正在编写时我们需要实现的都是处理 AdmissionRequest 并返回 AdmissionResponse 这部份(printRequest)；外部的包装为 AdmissionReview、复制 UID、复制 TypeMeta 等都是通用的方法，所以基于这一点我们可以进行适当的抽象:

#### 3.4.1、AdmissionFunc

针对每一个贴合业务的 WebHook 来说，其大致有三大属性:

- WebHook 的类型(Mutating/Validating)
- WebHook 拦截的 URL 路径(/print_request)
- WebHook 核心的处理逻辑(处理 Request 和返回 Response)

我们将其抽象为 AdmissionFunc 结构体以后如下所示

``` go
// WebHook 类型
const (
	Mutating   AdmissionFuncType = "Mutating"
	Validating AdmissionFuncType = "Validating"
)

// 每一个对应到我们业务的 WebHook 抽象的 struct
type AdmissionFunc struct {
	Type AdmissionFuncType
	Path string
	Func func(request *admissionv1.AdmissionRequest) (*admissionv1.AdmissionResponse, error)
}
```

#### 3.4.2、HandleFunc

我们知道 WebHook 是基于 HTTP 的，所以上面抽象出的 AdmissionFunc 还不能直接用在 HTTP 请求代码中；如果直接偶合到 HTTP 请求代码中，我们就没法为 HTTP 代码再增加其他拦截路径等等特殊的底层设置；**所以站在 HTTP 层面来说还需要抽象一个 "更高层面的且包含 AdmissionFunc 全部能力的 HandleFunc" 来使用；HandleFunc 抽象 HTTP 层面的需求:**

- HTTP 请求方法
- HTTP 请求路径
- HTTP 处理方法

以下为 HandleFunc 的抽象:


``` go
type HandleFunc struct {
	Path   string
	Method string
	Func   func(w http.ResponseWriter, r *http.Request)
}
```

### 3.5、goadmission 框架

有了以上两个角度的抽象，再结合 命令行参数解析、日志处理、配置文件读取等等，我揉合出了一个 [goadmission](https://github.com/mritd/goadmission) 框架，以方便动态准入控制的快速开发。

#### 3.5.1、基本结构

``` sh
.
├── main.go
└── pkg
    ├── adfunc
    │   ├── adfuncs.go
    │   ├── adfuncs_json.go
    │   ├── func_check_deploy_time.go
    │   ├── func_disable_service_links.go
    │   ├── func_image_rename.go
    │   └── func_print_request.go
    ├── conf
    │   └── conf.go
    ├── route
    │   ├── route_available.go
    │   ├── route_health.go
    │   └── router.go
    └── zaplogger
        ├── config.go
        └── logger.go

5 directories, 13 files
```

- main.go 为程序运行入口，在此设置命令行 flag 参数等
- pkg/conf 为框架配置包，所有的配置读取只读取这个包即可
- pkg/zaplogger zap log 库的日志抽象和处理(copy 自 operator-sdk)
- pkg/route http 级别的路由抽象(HandleFunc)
- pkg/adfunc 动态准入控制 WebHook 级别的抽(AdmissionFunc)

#### 3.5.2、增加动态准入控制

由于框架已经作好了路由注册等相关抽象，所以只需要新建 go 文件，然后通过 init 方法注册到全局 WebHook 组中即可，新编写的 WebHook 对已有代码不会有任何侵入:

![add_adfunc](https://cdn.oss.link/markdown/lg6zc.png)

**需要注意的是所有 validating 类型的 WebHook 会在 URL 路径前自动拼接 `/validating` 路径，mutating 类型的 WebHook 会在 URL 路径前自动拼接 `/mutating` 路径；**这么做是为了避免在更高层级的 HTTP Route 上添加冲突的路由。

![auto_fix_url](https://cdn.oss.link/markdown/nd5ez.png)

#### 3.5.3、实现 image 自动修改

所以一切准备就绪以后，就需要 "不忘初心"，撸一个自动修改镜像名称的 WebHook:


``` go
package adfunc

import (
	"fmt"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/mritd/goadmission/pkg/conf"

	jsoniter "github.com/json-iterator/go"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	"github.com/mritd/goadmission/pkg/route"
	admissionv1 "k8s.io/api/admission/v1"
)

// 只初始化一次 renameMap
var renameOnce sync.Once
// renameMap 保存镜像名称的替换规则，目前粗略实现为纯文本替换
var renameMap map[string]string

func init() {
	route.Register(route.AdmissionFunc{
		Type: route.Mutating,
		Path: "/rename",
		Func: func(request *admissionv1.AdmissionRequest) (*admissionv1.AdmissionResponse, error) {
			// init rename rules map
			renameOnce.Do(func() {
				renameMap = make(map[string]string, 10)
				// 将镜像重命名规则初始化到 renameMap 中，方便后续读取
				// rename rule example: k8s.gcr.io/=gcrxio/k8s.gcr.io_
				for _, s := range conf.ImageRename {
					ss := strings.Split(s, "=")
					if len(ss) != 2 {
						logger.Fatalf("failed to parse image name rename rules: %s", s)
					}
					renameMap[ss[0]] = ss[1]
				}
			})

			// 这个准入控制的 WebHook 只针对 Pod 处理，非 Pod 类请求直接返回错误
			switch request.Kind.Kind {
			case "Pod":
				// 从 request 中反序列化出 Pod 实例
				var pod corev1.Pod
				err := jsoniter.Unmarshal(request.Object.Raw, &pod)
				if err != nil {
					errMsg := fmt.Sprintf("[route.Mutating] /rename: failed to unmarshal object: %v", err)
					logger.Error(errMsg)
					return &admissionv1.AdmissionResponse{
						Allowed: false,
						Result: &metav1.Status{
							Code:    http.StatusBadRequest,
							Message: errMsg,
						},
					}, nil
				}

				// 后来我发现带有下面这个注解的 Pod 是没法更改成功的，这种 Pod 是由 kubelet 直接
				// 启动的 static pod，在 api server 中只能看到它的 "mirror"，不能改的
				// skip static pod
				for k := range pod.Annotations {
					if k == "kubernetes.io/config.mirror" {
						errMsg := fmt.Sprintf("[route.Mutating] /rename: pod %s has kubernetes.io/config.mirror annotation, skip image rename", pod.Name)
						logger.Warn(errMsg)
						return &admissionv1.AdmissionResponse{
							Allowed: true,
							Result: &metav1.Status{
								Code:    http.StatusOK,
								Message: errMsg,
							},
						}, nil
					}
				}

				// 遍历所有 Pod，然后生成 JSONPatch
				// 注意: 返回结果必须是 JSONPatch，k8s api server 再将 JSONPatch 应用到 Pod 上 
				
				// 由于有多个 Pod，所以最终会产生一个补丁数组
				var patches []Patch
				for i, c := range pod.Spec.Containers {
					for s, t := range renameMap {
						if strings.HasPrefix(c.Image, s) {
							patches = append(patches, Patch{
								// 指定 JSONPatch 动作为 replace 
								Option: PatchOptionReplace,
								// 打补丁的绝对位置
								Path:   fmt.Sprintf("/spec/containers/%d/image", i),
								// replace 为处理过的镜像名
								Value:  strings.Replace(c.Image, s, t, 1),
							})

							// 为了后期调试和留存历史，我们再为修改过的 Pod 加个注解
							patches = append(patches, Patch{
								Option: PatchOptionAdd,
								Path:   "/metadata/annotations",
								Value: map[string]string{
									fmt.Sprintf("rename-mutatingwebhook-%d.mritd.me", time.Now().Unix()): fmt.Sprintf("%d-%s-%s", i, strings.ReplaceAll(s, "/", "_"), strings.ReplaceAll(t, "/", "_")),
								},
							})
							break
						}
					}
				}

				// 将所有 JSONPatch 序列化成 json，然后返回即可
				patch, err := jsoniter.Marshal(patches)
				if err != nil {
					errMsg := fmt.Sprintf("[route.Mutating] /rename: failed to marshal patch: %v", err)
					logger.Error(errMsg)
					return &admissionv1.AdmissionResponse{
						Allowed: false,
						Result: &metav1.Status{
							Code:    http.StatusInternalServerError,
							Message: errMsg,
						},
					}, nil
				}

				logger.Infof("[route.Mutating] /rename: patches: %s", string(patch))
				return &admissionv1.AdmissionResponse{
					Allowed:   true,
					Patch:     patch,
					PatchType: JSONPatch(),
					Result: &metav1.Status{
						Code:    http.StatusOK,
						Message: "success",
					},
				}, nil
			default:
				errMsg := fmt.Sprintf("[route.Mutating] /rename: received wrong kind request: %s, Only support Kind: Pod", request.Kind.Kind)
				logger.Error(errMsg)
				return &admissionv1.AdmissionResponse{
					Allowed: false,
					Result: &metav1.Status{
						Code:    http.StatusForbidden,
						Message: errMsg,
					},
				}, nil
			}
		},
	})
}
```

## 四、总结

- 动态准入控制其实就是个 WebHook，我们弄个 HTTP Server 接收 AdmissionRequest 响应 AdmissionResponse 就行。
- Request、Response 会包装到 AdmissionReview 中，我们还需要做一些边缘处理，比如复制 UID、TypeMeta 等
- MutatingWebHook 想要修改东西时，要返回描述修改操作的 JSONPatch 补丁
- 单个 WebHook 很简单，写多个的时候要自己抽好框架，尽量优雅的作好复用和封装

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
