---
layout: post
categories: Kubernetes
title: Kubernetes TLS bootstrapping 那点事
date: 2018-01-07 18:06:06 +0800
description: Kubernetes TLS bootstrapping 那点事
keywords: tls-bootstrapping,kubernetes
catalog: true
multilingual: false
tags: Linux Docker Kubernetes
---

> 前段时间撸了一会 Kubernetes 官方文档，在查看 TLS bootstrapping 这块是发现已经跟 1.4 的时候完全不一样了；目前所有搭建文档也都保留着 1.4 时代的配置，在看完文档后发现目前配置有很多问题，同时也埋下了 **隐藏炸弹**，这个问题可能会在一年后爆发.....后果就是集群 node 全部掉线；所以仔细的撸了一下这个文档，从元旦到写此文章的时间都在测试这个 TLS bootstrapping，以下记录一下这次的成果

阅读本文章前，请先阅读一下本文参考的相关文档:

- [TLS bootstrapping](https://kubernetes.io/docs/admin/kubelet-tls-bootstrapping/)
- [Kubelet Server Certificate Bootstrap & Rotation](https://github.com/jcbsmpsn/community/blob/a843295a4f7594d41e66a8342e174f48d06b4f9f/contributors/design-proposals/kubelet-server-certificate-bootstrap-rotation.md)
- [Using RBAC Authorization](https://kubernetes.io/docs/admin/authorization/rbac/)

### 一、TLS bootstrapping 简介

Kubernetes 在 1.4 版本(我记着是)推出了 TLS bootstrapping 功能；这个功能主要解决了以下问题:

当集群开启了 TLS 认证后，每个节点的 kubelet 组件都要使用由 apiserver 使用的 CA 签发的有效证书才能与 apiserver 通讯；此时如果节点多起来，为每个节点单独签署证书将是一件非常繁琐的事情；TLS bootstrapping 功能就是让 kubelet 先使用一个预定的低权限用户连接到 apiserver，然后向 apiserver 申请证书，kubelet 的证书由 apiserver 动态签署；在配合 RBAC 授权模型下的工作流程大致如下所示(不完整，下面细说)

![tls_bootstrapping](https://mritd.b0.upaiyun.com/markdown/ixtwd.png)


### 二、TLS bootstrapping 相关术语

#### 2.1、kubelet server

在官方 TLS bootstrapping 文档中多次提到过 `kubelet server` 这个东西；在经过翻阅大量文档以及 TLS bootstrapping 设计文档后得出，**`kubelet server` 指的应该是 kubelet 的 10250 端口；**


**kubelet 组件在工作时，采用主动的查询机制，即定期请求 apiserver 获取自己所应当处理的任务，如哪些 pod 分配到了自己身上，从而去处理这些任务；同时 kubelet 自己还会暴露出两个本身 api 的端口，用于将自己本身的私有 api 暴露出去，这两个端口分别是 10250 与 10255；对于 10250 端口，kubelet 会在其上采用 TLS 加密以提供适当的鉴权功能；对于 10255 端口，kubelet 会以只读形式暴露组件本身的私有 api，并且不做鉴权处理**

**总结一下，就是说 kubelet 上实际上有两个地方用到证书，一个是用于与 API server 通讯所用到的证书，另一个是 kubelet 的 10250 私有 api 端口需要用到的证书**

#### 2.2、CSR 请求类型

kubelet 发起的 CSR 请求都是由 controller manager 来做实际签署的，对于 controller manager 来说，TLS bootstrapping 下 kubelet 发起的 CSR 请求大致分为以下三种

- nodeclient: kubelet 以 `O=system:nodes` 和 `CN=system:node:(node name)` 形式发起的 CSR 请求
- selfnodeclient: kubelet client renew 自己的证书发起的 CSR 请求(与上一个证书就有相同的 O 和 CN)
- selfnodeserver: kubelet server renew 自己的证书发起的 CSR 请求

**大白话加自己测试得出的结果: nodeclient 类型的 CSR 仅在第一次启动时会产生，selfnodeclient 类型的 CSR 请求实际上就是 kubelet renew 自己作为 client 跟 apiserver 通讯时使用的证书产生的，selfnodeserver 类型的 CSR 请求则是 kubelet 首次申请或后续 renew 自己的 10250 api 端口证书时产生的**


### 三、TLS bootstrapping 具体引导过程

#### 3.1、Kubernetes TLS 与 RBAC 认证

在说具体的引导过程之前先谈一下 TLS 和 RBAC，因为这两个事不整明白下面的都不用谈；

- TLS 作用

众所周知 TLS 的作用就是对通讯加密，防止中间人窃听；同时如果证书不信任的话根本就无法与 apiserver 建立连接，更不用提有没有权限向 apiserver 请求指定内容

- RBAC 作用

当 TLS 解决了通讯问题后，那么权限问题就应由 RBAC 解决(可以使用其他权限模型，如 ABAC)；RBAC 中规定了一个用户或者用户组(subject)具有请求哪些 api 的权限；**在配合 TLS 加密的时候，实际上 apiserver 读取客户端证书的 CN 字段作为用户名，读取 O 字段作为用户组**

从以上两点上可以总结出两点: 第一，想要与 apiserver 通讯就必须采用由 apiserver CA 签发的证书，这样才能形成信任关系，建立 TLS 连接；第二，可以通过证书的 CN、O 字段来提供 RBAC 所需的用户与用户组

#### 3.2、kubelet 首次启动流程

看完上面的介绍，不知道有没有人想过，既然 TLS bootstrapping 功能是让 kubelet 组件去 apiserver 申请证书，然后用于连接 apiserver；**那么第一次启动时没有证书如何连接 apiserver ?**

这个问题实际上可以去查看一下 `bootstrap.kubeconfig` 和 `token.csv` 得到答案: **在 apiserver 配置中指定了一个 `token.csv` 文件，该文件中是一个预设的用户配置；同时该用户的 Token 和 apiserver 的 CA 证书被写入了 kubelet 所使用的 `bootstrap.kubeconfig` 配置文件中；这样在首次请求时，kubelet 使用 `bootstrap.kubeconfig` 中的 apiserver CA 证书来与 apiserver 建立 TLS 通讯，使用 `bootstrap.kubeconfig` 中的用户 Token 来向 apiserver 声明自己的 RBAC 授权身份**，如下图所示

![first_request](https://mritd.b0.upaiyun.com/markdown/ji5ug.png)

在有些用户首次启动时，可能与遇到 kubelet 报 401 无权访问 apiserver 的错误；**这是因为在默认情况下，kubelet 通过 `bootstrap.kubeconfig` 中的预设用户 Token 声明了自己的身份，然后创建 CSR 请求；但是不要忘记这个用户在我们不处理的情况下他没任何权限的，包括创建 CSR 请求；所以需要如下命令创建一个 ClusterRoleBinding，将预设用户 `kubelet-bootstrap` 与内置的 ClusterRole `system:node-bootstrapper` 绑定到一起，使其能够发起 CSR 请求**

``` sh
kubectl create clusterrolebinding kubelet-bootstrap \
  --clusterrole=system:node-bootstrapper \
  --user=kubelet-bootstrap
```

#### 3.3、手动签发证书

在 kubelet 首次启动后，如果用户 Token 没问题，并且 RBAC 也做了相应的设置，那么此时在集群内应该能看到 kubelet 发起的 CSR 请求

![bootstrap_csr](https://mritd.b0.upaiyun.com/markdown/n9bbw.png)

出现 CSR 请求后，可以使用 kubectl 手动签发(允许) kubelet 的证书

![bootstrap_approve_crt](https://mritd.b0.upaiyun.com/markdown/5ssf8.png)

**当成功签发证书后，目标节点的 kubelet 会将证书写入到 `--cert-dir=` 选项指定的目录中；注意此时如果不做其他设置应当生成四个文件**

![bootstrap_crt](https://mritd.b0.upaiyun.com/markdown/a25ip.png)

**而 kubelet 与 apiserver 通讯所使用的证书为 `kubelet-client.crt`，剩下的 `kubelet.crt` 将会被用于 `kubelet server`(10250) 做鉴权使用；注意，此时 `kubelet.crt` 这个证书是个独立于 apiserver CA 的自签 CA，并且删除后 kubelet 组件会重新生成它**


### 四、TLS bootstrapping 证书自动续期

> 单独把这部分拿出来写，是因为个人觉得上面已经有点乱了；这部分实际上更复杂，只好单独写一下了，因为这部分涉及的东西比较多，所以也不想草率的几笔带过


#### 4.1、RBAC 授权

首先...首先好几次了...嗯，就是说 kubelet 所发起的 CSR 请求是由 controller manager 签署的；如果想要是实现自动续期，就需要让 controller manager 能够在 kubelet 发起证书请求的时候自动帮助其签署证书；那么 controller manager 不可能对所有的 CSR 证书申请都自动签署，这时候就需要配置 RBAC 规则，**保证 controller manager 只对 kubelet 发起的特定 CSR 请求自动批准即可**；在 TLS bootstrapping 官方文档中，针对上面 2.2 章节提出的 3 种 CSR 请求分别给出了 3 种对应的 ClusterRole，如下所示

``` yaml
# A ClusterRole which instructs the CSR approver to approve a user requesting
# node client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-client-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/nodeclient"]
  verbs: ["create"]
---
# A ClusterRole which instructs the CSR approver to approve a node renewing its
# own client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-client-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeclient"]
  verbs: ["create"]
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
```

RBAC 中 ClusterRole 只是描述或者说定义一种集群范围内的能力，这三个 ClusterRole 在 1.7 之前需要自己手动创建，在 1.8 后 apiserver 会自动创建前两个(1.8 以后名称有改变，自己查看文档)；以上三个 ClusterRole 含义如下

- approve-node-client-csr: 具有自动批准 nodeclient 类型 CSR 请求的能力
- approve-node-client-renewal-csr: 具有自动批准 selfnodeclient 类型 CSR 请求的能力
- approve-node-server-renewal-csr: 具有自动批准 selfnodeserver 类型 CSR 请求的能力

**所以，如果想要 kubelet 能够自动续期，那么就应当将适当的 ClusterRole 绑定到 kubelet 自动续期时所所采用的用户或者用户组身上**

#### 4.2、自动续期下的引导过程

在自动续期下引导过程与单纯的手动批准 CSR 有点差异，具体的引导流程地址如下

- kubelet 读取 bootstrap.kubeconfig，使用其 CA 与 Token 向 apiserver 发起第一次 CSR 请求(nodeclient)
- apiserver 根据 RBAC 规则自动批准首次 CSR 请求(approve-node-client-csr)，并下发证书(kubelet-client.crt)
- kubelet **使用刚刚签发的证书(O=system:nodes, CN=system:node:NODE_NAME)**与 apiserver 通讯，并发起申请 10250 server 所使用证书的 CSR 请求
- apiserver 根据 RBAC 规则自动批准 kubelet 为其 10250 端口申请的证书(kubelet-server-current.crt)
- 证书即将到期时，kubelet 自动向 apiserver 发起用于与 apiserver 通讯所用证书的 renew CSR 请求和 renew 本身 10250 端口所用证书的 CSR 请求
- apiserver 根据 RBAC 规则自动批准两个证书
- kubelet 拿到新证书后关闭所有连接，reload 新证书，以后便一直如此

**从以上流程我们可以看出，我们如果要创建 RBAC 规则，则至少能满足四种情况:**

- 自动批准 kubelet 首次用于与 apiserver 通讯证书的 CSR 请求(nodeclient)
- 自动批准 kubelet 首次用于 10250 端口鉴权的 CSR 请求(实际上这个请求走的也是 selfnodeserver 类型 CSR)
- 自动批准 kubelet 后续 renew 用于与 apiserver 通讯证书的 CSR 请求(selfnodeclient)
- 自动批准 kubelet 后续 renew 用于 10250 端口鉴权的 CSR 请求(selfnodeserver)

基于以上四种情况，我们需要创建 3 个 ClusterRoleBinding，创建如下

``` sh
# 自动批准 kubelet 的首次 CSR 请求(用于与 apiserver 通讯的证书)
kubectl create clusterrolebinding node-client-auto-approve-csr --clusterrole=approve-node-client-csr --group=system:bootstrappers

# 自动批准 kubelet 后续 renew 用于与 apiserver 通讯证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-renew-crt --clusterrole=approve-node-client-renewal-csr --group=system:nodes

# 自动批准 kubelet 发起的用于 10250 端口鉴权证书的 CSR 请求(包括后续 renew)
kubectl create clusterrolebinding node-server-auto-renew-crt --clusterrole=approve-node-server-renewal-csr --group=system:nodes
```

#### 4.3、开启自动续期

在 1.7 后，kubelet 启动时增加 `--feature-gates=RotateKubeletClientCertificate=true,RotateKubeletServerCertificate=true` 选项，则 kubelet 在证书即将到期时会自动发起一个 renew 自己证书的 CSR 请求；同时 controller manager 需要在启动时增加 `--feature-gates=RotateKubeletServerCertificate=true` 参数，再配合上面创建好的 ClusterRoleBinding，kubelet client 和 kubelet server 证才书会被自动签署；

**注意，1.7 版本设置自动续期参数后，新的 renew 请求不会立即开始，而是在证书总有效期的 `70%~90%` 的时间时发起；而且经测试 1.7 版本即使自动签发了证书，kubelet 在不重启的情况下不会重新应用新证书；在 1.8 后 kubelet 组件在增加一个 `--rotate-certificates` 参数后，kubelet 才会自动重载新证书**

#### 4.3、证书过期问题

需要重复强调一个问题是: **TLS bootstrapping 时的证书实际是由 kube-controller-manager 组件来签署的，也就是说证书有效期是 kube-controller-manager 组件控制的**；所以在 1.7 版本以后(我查文档发现的从1.7开始有) kube-controller-manager 组件提供了一个 `--experimental-cluster-signing-duration` 参数来设置签署的证书有效时间；默认为 `8760h0m0s`，将其改为 `87600h0m0s` 即 10 年后再进行 TLS bootstrapping 签署证书即可。

### 五、TLS bootstrapping 总结以及详细操作

#### 5.1、主要流程细节

kubelet 首次启动通过加载 `bootstrap.kubeconfig` 中的用户 Token 和 apiserver CA 证书发起首次 CSR 请求，这个 Token 被预先内置在 apiserver 节点的 token.csv 中，其身份为 `kubelet-bootstrap` 用户和 `system:bootstrappers` 用户组；想要首次 CSR 请求能成功(成功指的是不会被 apiserver 401 拒绝)，则需要先将 `kubelet-bootstrap` 用户和 `system:node-bootstrapper` 内置 ClusterRole 绑定；

对于首次 CSR 请求可以手动批准，也可以将 `system:bootstrappers` 用户组与 `approve-node-client-csr` ClusterRole 绑定实现自动批准(1.8 之前这个 ClusterRole 需要手动创建，1.8 后 apiserver 自动创建，并更名为 `system:certificates.k8s.io:certificatesigningrequests:nodeclient`)

默认签署的的证书只有 1 年有效期，如果想要调整证书有效期可以通过设置 kube-controller-manager 的 `--experimental-cluster-signing-duration` 参数实现，该参数默认值为 `8760h0m0s`

对于证书自动续签，需要通过协调两个方面实现；第一，想要 kubelet 在证书到期后自动发起续期请求，则需要在 kubelet 启动时增加 `--feature-gates=RotateKubeletClientCertificate=true,RotateKubeletServerCertificate=true` 来实现；第二，想要让 controller manager 自动批准续签的 CSR 请求需要在 controller manager 启动时增加 `--feature-gates=RotateKubeletServerCertificate=true` 参数，并绑定对应的 RBAC 规则；**同时需要注意的是 1.7 版本的 kubelet 自动续签后需要手动重启 kubelet 以使其重新加载新证书，而 1.8 后只需要在 kublet 启动时附带 `--rotate-certificates` 选项就会自动重新加载新证书**

#### 5.2、证书及配置文件作用

- token.csv

该文件为一个用户的描述文件，基本格式为 `Token,用户名,UID,用户组`；这个文件在 apiserver 启动时被 apiserver 加载，然后就相当于在集群内创建了一个这个用户；接下来就可以用 RBAC 给他授权；持有这个用户 Token 的组件访问 apiserver 的时候，apiserver 根据 RBAC 定义的该用户应当具有的权限来处理相应请求

- bootstarp.kubeconfig

该文件中内置了 token.csv 中用户的 Token，以及 apiserver CA 证书；kubelet 首次启动会加载此文件，使用 apiserver CA 证书建立与 apiserver 的 TLS 通讯，使用其中的用户 Token 作为身份标识像 apiserver 发起 CSR 请求

- kubelet-client.crt

该文件在 kubelet 完成 TLS bootstrapping 后生成，此证书是由 controller manager 签署的，此后 kubelet 将会加载该证书，用于与 apiserver 建立 TLS 通讯，同时使用该证书的 CN 字段作为用户名，O 字段作为用户组向 apiserver 发起其他请求

- kubelet.crt

该文件在 kubelet 完成 TLS bootstrapping 后并且**没有配置 `--feature-gates=RotateKubeletServerCertificate=true` 时才会生成**；这种情况下该文件为一个独立于 apiserver CA 的自签 CA 证书，有效期为 1 年；被用作 kubelet 10250 api 端口

- kubelet-server.crt

该文件在 kubelet 完成 TLS bootstrapping 后并且**配置了 `--feature-gates=RotateKubeletServerCertificate=true` 时才会生成**；这种情况下该证书由 apiserver CA 签署，默认有效期同样是 1 年，被用作 kubelet 10250 api 端口鉴权

- kubelet-client-current.pem

这是一个软连接文件，当 kubelet 配置了 `--feature-gates=RotateKubeletClientCertificate=true` 选项后，会在证书总有效期的 `70%~90%` 的时间内发起续期请求，请求被批准后会生成一个 `kubelet-client-时间戳.pem`；`kubelet-client-current.pem` 文件则始终软连接到最新的真实证书文件，除首次启动外，kubelet 一直会使用这个证书同  apiserver 通讯

- kubelet-server-current.pem

同样是一个软连接文件，当 kubelet 配置了 `--feature-gates=RotateKubeletServerCertificate=true` 选项后，会在证书总有效期的 `70%~90%` 的时间内发起续期请求，请求被批准后会生成一个 `kubelet-server-时间戳.pem`；`kubelet-server-current.pem` 文件则始终软连接到最新的真实证书文件，该文件将会一直被用于 kubelet 10250 api 端口鉴权

#### 5.3、1.7 TLS bootstrapping 配置

apiserver 预先放置 token.csv，内容样例如下

``` sh
6df3c701f979cee17732c30958745947,kubelet-bootstrap,10001,"system:bootstrappers"
```

允许 kubelet-bootstrap 用户创建首次启动的 CSR 请求

``` sh
kubectl create clusterrolebinding kubelet-bootstrap \
  --clusterrole=system:node-bootstrapper \
  --user=kubelet-bootstrap
```

配置 kubelet 自动续期，**RotateKubeletClientCertificate 用于自动续期 kubelet 连接 apiserver 所用的证书(kubelet-client-xxxx.pem)，RotateKubeletServerCertificate 用于自动续期 kubelet 10250 api 端口所使用的证书(kubelet-server-xxxx.pem)**

``` sh
KUBELET_ARGS="--cgroup-driver=cgroupfs \
              --cluster-dns=10.254.0.2 \
              --resolv-conf=/etc/resolv.conf \
              --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
              --feature-gates=RotateKubeletClientCertificate=true,RotateKubeletServerCertificate=true \
              --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
              --fail-swap-on=false \
              --cert-dir=/etc/kubernetes/ssl \
              --cluster-domain=cluster.local. \
              --hairpin-mode=promiscuous-bridge \
              --serialize-image-pulls=false \
              --pod-infra-container-image=gcr.io/google_containers/pause-amd64:3.0"
```

配置 controller manager 自动批准相关 CSR 请求，**如果不配置 `--feature-gates=RotateKubeletServerCertificate=true` 参数，则即使配置了相关的 RBAC 规则，也只会自动批准 kubelet client 的 renew 请求** 

``` sh
KUBE_CONTROLLER_MANAGER_ARGS="--address=0.0.0.0 \
                              --service-cluster-ip-range=10.254.0.0/16 \
                              --feature-gates=RotateKubeletServerCertificate=true \
                              --cluster-name=kubernetes \
                              --cluster-signing-cert-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                              --cluster-signing-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                              --service-account-private-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                              --root-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                              --leader-elect=true \
                              --node-monitor-grace-period=40s \
                              --node-monitor-period=5s \
                              --pod-eviction-timeout=5m0s"
```

创建自动批准相关 CSR 请求的 ClusterRole

``` yaml
# A ClusterRole which instructs the CSR approver to approve a user requesting
# node client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-client-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/nodeclient"]
  verbs: ["create"]
---
# A ClusterRole which instructs the CSR approver to approve a node renewing its
# own client credentials.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-client-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeclient"]
  verbs: ["create"]
---
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: approve-node-server-renewal-csr
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
```

将 ClusterRole 绑定到适当的用户组，以完成自动批准相关 CSR 请求

``` sh
# 自动批准 system:bootstrappers 组用户 TLS bootstrapping 首次申请证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-approve-csr --clusterrole=approve-node-client-csr --group=system:bootstrappers

# 自动批准 system:nodes 组用户更新 kubelet 自身与 apiserver 通讯证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-renew-crt --clusterrole=approve-node-client-renewal-csr --group=system:nodes

# 自动批准 system:nodes 组用户更新 kubelet 10250 api 端口证书的 CSR 请求
kubectl create clusterrolebinding node-server-auto-renew-crt --clusterrole=approve-node-server-renewal-csr --group=system:nodes
```

**一切就绪后启动 kubelet 组件即可，不过需要注意的是 1.7 版本 kubelet 不会自动重载 renew 的证书，需要自己手动重启**


#### 5.4、1.8 TLS bootstrapping 配置

apiserver 预先放置 token.csv，内容样例如下

``` sh
6df3c701f979cee17732c30958745947,kubelet-bootstrap,10001,"system:bootstrappers"
```

允许 kubelet-bootstrap 用户创建首次启动的 CSR 请求

``` sh
kubectl create clusterrolebinding kubelet-bootstrap \
  --clusterrole=system:node-bootstrapper \
  --user=kubelet-bootstrap
```

配置 kubelet 自动续期，**RotateKubeletClientCertificate 用于自动续期 kubelet 连接 apiserver 所用的证书(kubelet-client-xxxx.pem)，RotateKubeletServerCertificate 用于自动续期 kubelet 10250 api 端口所使用的证书(kubelet-server-xxxx.pem)，`--rotate-certificates` 选项使得 kubelet 能够自动重载新证书**

``` sh
KUBELET_ARGS="--cgroup-driver=cgroupfs \
              --cluster-dns=10.254.0.2 \
              --resolv-conf=/etc/resolv.conf \
              --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
              --feature-gates=RotateKubeletClientCertificate=true,RotateKubeletServerCertificate=true \
              --rotate-certificates \
              --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
              --fail-swap-on=false \
              --cert-dir=/etc/kubernetes/ssl \
              --cluster-domain=cluster.local. \
              --hairpin-mode=promiscuous-bridge \
              --serialize-image-pulls=false \
              --pod-infra-container-image=gcr.io/google_containers/pause-amd64:3.0"
```

配置 controller manager 自动批准相关 CSR 请求，**如果不配置 `--feature-gates=RotateKubeletServerCertificate=true` 参数，则即使配置了相关的 RBAC 规则，也只会自动批准 kubelet client 的 renew 请求** 

``` sh
KUBE_CONTROLLER_MANAGER_ARGS="--address=0.0.0.0 \
                              --service-cluster-ip-range=10.254.0.0/16 \
                              --cluster-name=kubernetes \
                              --cluster-signing-cert-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                              --cluster-signing-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                              --service-account-private-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                              --feature-gates=RotateKubeletServerCertificate=true \
                              --root-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                              --leader-elect=true \
                              --experimental-cluster-signing-duration 10m0s \
                              --node-monitor-grace-period=40s \
                              --node-monitor-period=5s \
                              --pod-eviction-timeout=5m0s"
```

创建自动批准相关 CSR 请求的 ClusterRole，相对于 1.7 版本，1.8 的 apiserver 自动创建了前两条 ClusterRole，所以只需要创建一条就行了

``` yaml
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeserver
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
```

将 ClusterRole 绑定到适当的用户组，以完成自动批准相关 CSR 请求

``` sh
# 自动批准 system:bootstrappers 组用户 TLS bootstrapping 首次申请证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-approve-csr --clusterrole=system:certificates.k8s.io:certificatesigningrequests:nodeclient --group=system:bootstrappers

# 自动批准 system:nodes 组用户更新 kubelet 自身与 apiserver 通讯证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-renew-crt --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeclient --group=system:nodes

# 自动批准 system:nodes 组用户更新 kubelet 10250 api 端口证书的 CSR 请求
kubectl create clusterrolebinding node-server-auto-renew-crt --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeserver --group=system:nodes
```

**一切就绪后启动 kubelet 组件即可，1.8 版本 kubelet 会自动重载证书，以下为 1.8 版本在运行一段时间后的相关证书截图**


![tls_bootstrapping_crts](https://mritd.b0.upaiyun.com/markdown/570wk.png)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
