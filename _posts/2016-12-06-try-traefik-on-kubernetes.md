---
layout: post
categories: Kubernetes Docker
title: Traefik-kubernetes 初试
date: 2016-12-06 22:38:22 +0800
description: Traefik-kubernetes 初试
keywords: Traefik Kubernetes
---

> traefik 是一个前端负载均衡器，对于微服务架构尤其是 kubernetes 等编排工具具有良好的支持；同 nginx 等相比，traefik 能够自动感知后端容器变化，从而实现自动服务发现；今天小试了一下，在此记录一下使用过程

### 一、Kubernetes 服务暴露介绍

从 kubernetes 1.2 版本开始，kubernetes提供了 Ingress 对象来实现对外暴露服务；到目前为止 kubernetes 总共有三种暴露服务的方式:

- LoadBlancer Service
- NodePort Service
- Ingress

#### 1.1、LoadBlancer Service

LoadBlancer Service 是 kubernetes 深度结合云平台的一个组件；当使用 LoadBlancer Service 暴露服务时，实际上是通过**向底层云平台申请创建一个负载均衡器**来向外暴露服务；目前 LoadBlancer Service 支持的云平台已经相对完善，比如国外的 GCE、DigitalOcean，国内的 阿里云，私有云 Openstack 等等，由于 LoadBlancer Service 深度结合了云平台，所以只能在一些云平台上来使用

#### 1.2、NodePort Service

NodePort Service 顾名思义，实质上就是通过在集群的每个 node 上暴露一个端口，然后将这个端口映射到某个具体的 service 来实现的，虽然每个 node 的端口有很多(0~65535)，但是由于安全性和易用性(服务多了就乱了，还有端口冲突问题)实际使用可能并不多

#### 1.3、Ingress

Ingress 这个东西是 1.2 后才出现的，通过 Ingress 用户可以实现使用 nginx 等开源的反向代理负载均衡器实现对外暴露服务，以下详细说一下 Ingress，毕竟 traefik 用的就是 Ingress

**使用 Ingress 时一般会有三个组件:**

- 反向代理负载均衡器
- Ingress Controller
- Ingress

##### 1.3.1、反向代理负载均衡器

反向代理负载均衡器很简单，说白了就是 nginx、apache 什么的；在集群中反向代理负载均衡器可以自由部署，可以使用 Replication Controller、Deployment、DaemonSet 等等，不过个人喜欢以 DaemonSet 的方式部署，感觉比较方便

##### 1.3.2、Ingress Controller

Ingress Controller 实质上可以理解为是个监视器，Ingress Controller 通过不断地跟 kubernetes API 打交道，实时的感知后端 service、pod 等变化，比如新增和减少 pod，service 增加与减少等；当得到这些变化信息后，Ingress Controller 再结合下文的 Ingress 生成配置，然后更新反向代理负载均衡器，并刷新其配置，达到服务发现的作用

##### 1.3.3、Ingress

Ingress 简单理解就是个规则定义；比如说某个域名对应某个 service，即当某个域名的请求进来时转发给某个 service;这个规则将与 Ingress Controller 结合，然后 Ingress Controller 将其动态写入到负载均衡器配置中，从而实现整体的服务发现和负载均衡


**有点懵逼，那就看图**

![Ingress](https://mritd.b0.upaiyun.com/markdown/qflqj.jpg)


**从上图中可以很清晰的看到，实际上请求进来还是被负载均衡器拦截，比如 nginx，然后 Ingress Controller 通过跟 Ingress 交互得知某个域名对应哪个 service，再通过跟 kubernetes API 交互得知 service 地址等信息；综合以后生成配置文件实时写入负载均衡器，然后负载均衡器 reload 该规则便可实现服务发现，即动态映射**

**了解了以上内容以后，这也就很好的说明了我为什么喜欢把负载均衡器部署为 Daemon Set；因为无论如何请求首先是被负载均衡器拦截的，所以在每个 node 上都部署一下，同时 hostport 方式监听 80 端口；那么就解决了其他方式部署不确定 负载均衡器在哪的问题，同时访问每个 node 的 80 都能正确解析请求；如果前端再 放个 nginx 就又实现了一层负载均衡**

### 二、Traefik 使用

由于微服务架构以及 Docker 技术和 kubernetes 编排工具最近几年才开始逐渐流行，所以一开始的反向代理服务器比如 nginx、apache 并未提供其支持，毕竟他们也不是先知；所以才会出现 Ingress Controller 这种东西来做 kubernetes 和前端负载均衡器如 nginx 之间做衔接；**即 Ingress Controller 的存在就是为了能跟 kubernetes 交互，又能写 nginx 配置，还能 reload 它，这是一种折中方案**；而最近开始出现的 traefik 天生就是提供了对 kubernetes 的支持，**也就是说 traefik 本身就能跟 kubernetes API 交互，感知后端变化，因此可以得知: 在使用 traefik 时，Ingress Controller 已经无卵用了，所以整体架构如下**

![traefik](https://mritd.b0.upaiyun.com/markdown/pot7r.jpg)

#### 2.1、部署 Traefik

已经从大体上搞懂了 Ingress 和 traefik，那么部署起来就很简单

##### 2.1.1、部署 Daemon Set

**首先以 Daemon Set 的方式在每个 node 上启动一个 traefik，并使用 hostPort 的方式让其监听每个 node 的 80 端口(有没有感觉这就是个 NodePort? 不过区别就是这个 Port 后面有负载均衡器 -->手动微笑)**

``` sh
kubectl create -f traefik.ds.yanl

# Daemon set 文件如下
apiVersion: extensions/v1beta1
kind: DaemonSet
metadata:
  name: traefik-ingress-lb
  namespace: kube-system
  labels:
    k8s-app: traefik-ingress-lb
spec:
  template:
    metadata:
      labels:
        k8s-app: traefik-ingress-lb
        name: traefik-ingress-lb
    spec:
      terminationGracePeriodSeconds: 60
      hostNetwork: true
      restartPolicy: Always
      containers:
      - image: traefik
        name: traefik-ingress-lb
        resources:
          limits:
            cpu: 200m
            memory: 30Mi
          requests:
            cpu: 100m
            memory: 20Mi
        ports:
        - name: http
          containerPort: 80
          hostPort: 80
        - name: admin
          containerPort: 8580
        args:
        - --web
        - --web.address=:8580
        - --kubernetes
```

**其中 traefik 监听 node 的 80 和 8580 端口，80 提供正常服务，8580 是其自带的 UI 界面，原本默认是 8080，因为环境里端口冲突了，所以这里临时改一下**

##### 2.1.2、部署 Ingress

从上面的长篇大论已经得知了 Ingress Controller 是无需部署的，所以直接部署 Ingress 即可

``` sh
kubectl create -f traefik.ing.yaml

# Ingress 文件如下
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: traefik-ingress
spec:
  rules:
  - host: traefik.www.test.com
    http:
      paths:
      - path: /
        backend:
          serviceName: test-www
          servicePort: 8080
  - host: traefik.api.test.com
    http:
      paths:
      - path: /
        backend:
          serviceName: test-api
          servicePort: 8080
```

**实际上事先集群中已经存在了相应的名为 test-www 和 test-api 的 service，对应的 service 后端也有很多 pod；所以这里就不在具体写部署实际业务容器(test-www、test-api)的过程了，各位测试时，只需要把这个 test 的 service 替换成自己业务的 service 即可**

##### 2.1.3、部署 Traefik UI

traefik 本身还提供了一套 UI 供我们使用，其同样以 Ingress 方式暴露，只需要创建一下即可

``` sh
kubectl create -f ui.yaml

# ui yaml 如下
---
apiVersion: v1
kind: Service
metadata:
  name: traefik-web-ui
  namespace: kube-system
spec:
  selector:
    k8s-app: traefik-ingress-lb
  ports:
  - name: web
    port: 80
    targetPort: 8580
---
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: traefik-web-ui
  namespace: kube-system
spec:
  rules:
  - host: traefik-ui.local
    http:
      paths:
      - path: /
        backend:
          serviceName: traefik-web-ui
          servicePort: web
```

##### 2.1.4、访问测试

都创建无误以后，只需要将待测试的域名解析到任意一台 node 上即可，页面就不截图了，截图就暴露了.....下面来两张 ui 的

![traefik ui](https://mritd.b0.upaiyun.com/markdown/i32ab.jpg)

![traefik ui health](https://mritd.b0.upaiyun.com/markdown/1qtmb.jpg)

#### 2.2、健康检查

关于健康检查，测试可以使用 kubernetes 的 Liveness Probe 实现，如果 Liveness Probe检查失败，则 traefik 会自动移除该 pod，以下是一个 示例

**test 的 deployment，健康检查方式是 `cat /tmp/health`，容器启动 2 分钟后会删掉这个文件，模拟健康检查失败**

``` sh
apiVersion: v1
kind: Deployment
apiVersion: extensions/v1beta1
metadata:
  name: test
  namespace: default
  labels:
    test: alpine
spec:
  replicas: 1
  selector:
    matchLabels:
      test: alpine
  template:
    metadata:
      labels:
        test: alpine
        name: test
    spec:
      containers:
      - image: mritd/alpine:3.4
        name: alpine
        resources:
          limits:
            cpu: 200m
            memory: 30Mi
          requests:
            cpu: 100m
            memory: 20Mi
        ports:
        - name: http
          containerPort: 80
        args:
        command:
        - "bash"
        - "-c"
        - "echo ok > /tmp/health;sleep 120;rm -f /tmp/health"
        livenessProbe:
          exec:
            command:
            - cat
            - /tmp/health
          initialDelaySeconds: 20
```

**test 的 service**

``` sh
apiVersion: v1
kind: Service
metadata:
  name: test 
  labels:
    name: test
spec:
  ports:
  - port: 8123
    targetPort: 80
  selector:
    name: test
```

**test 的 Ingress**

``` sh
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: test
spec:
  rules:
  - host: test.com
    http:
      paths:
      - path: /
        backend:
          serviceName: test
          servicePort: 8123
```

**全部创建好以后，进入 traefik ui 界面，可以观察到每隔 2 分钟健康检查失败后，kubernetes 重建 pod，同时 traefik 会从后端列表中移除这个 pod**

**其他更多玩法请参考 [官方文档](https://docs.traefik.io/)(我发现他居然支持 Let's Entrypt，个人博客福音啊)，如有错误欢迎指正**

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
