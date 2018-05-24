---
layout: post
categories: Kubernetes
title: Traefik 另类的服务暴露方式
date: 2018-05-24 23:53:09 +0800
description: 介绍一种 Traefik 另类的服务暴露方式
keywords: kubernetes,traefik
catalog: true
multilingual: false
tags: Kubernetes
---

> 最近准备重新折腾一下 Kubernetes 的服务暴露方式，以前的方式是彻底剥离 Kubenretes 本身的服务发现，然后改动应用实现 应用+Consul+Fabio 的服务暴露方式；总感觉这种方式不算优雅，所以折腾了一下 Traefik，试了下效果还不错，以下记录了使用 Traefik 的新的服务暴露方式(本文仅针对 HTTP 协议)；

## 一、Traefik 服务暴露方案

### 1.1、以前的 Consul+Fabio 方案

以前的服务暴露方案是修改应用代码，使其能对接 Consul，然后 Consul 负责健康监测，检测通过后 Fabio 负责读取，最终上层 Nginx 将流量打到 Fabio 上，Fabio 再将流量路由到健康的 Pod 上；总体架构如下

![consul+fabio](https://mritd.b0.upaiyun.com/markdown/hkwp3.png)

这种架构目前有几点不太好的地方，首先是必须应用能成功集成 Consul，需要动应用代码不通用；其次组件过多增加维护成本，尤其是调用链日志不好追踪；这里面需要吐槽下 Consul 和 Fabio，Consul 的集群设计模式要想做到完全的 HA 那么需要在每个 pod 中启动一个 agent，因为只要这个 agent 挂了那么集群认为其上所有注册服务都挂了，这点很恶心人；而 Fabio 的日志目前好像还是不支持合理的输出，好像只能 stdout；目前来看不论是组件复杂度还是维护成本都不怎么友好

### 1.2、新的 Traefik 方案

使用 Traefik 首先想到就是直接怼 Ingress，这个确实方便也简单；但是在集群 kube-proxy 不走 ipvs 的情况下 iptables 性能确实堪忧；虽说 Traefik 会直连 Pod，但是你 Ingress 暴露 80、443 端口在本机没有对应 Ingress Controller 的情况下还是会走一下 iptables；**不论是换 kube-router、kube-proxy 走 ipvs 都不是我想要的，我们需要一种完全远离 Kubernetes Service 的新路子**；在看 Traefik 文档的时候，其中说明了 Traefik 只利用 Kubernetes 的 API 来读取相关后端数据，那么我们就可以以此来使用如下的套路


![traefik](https://mritd.b0.upaiyun.com/markdown/tfo2f.png)

这个套路的方案很简单，**将 Traefik 部署在物理机上，让其直连 Kubernets api 以读取 Ingress 配置和 Pod IP 等信息，然后在这几台物理机上部署好 Kubernetes 的网络组件使其能直连 Pod IP**；这种方案能够让流量经过 Traefik 直接路由到后端 Pod，健康检测还是由集群来做；**由于 Traefik 连接 Kubernetes api 需要获取一些数据；所以在集群内还是像往常一样创建 Ingress，只不过此时我们并没有 Ingress Controller；这样避免了经过 iptables 转发，不占用全部集群机器的 80、443 端口，同时还能做到高可控**


## 二、Traefik 部署

部署之前首先需要有一个正常访问的集群，然后在另外几台机器上部署 Kubernetes 的网络组件；最终要保证另外几台机器能够直接连通 Pod 的 IP，我这里偷懒直接在 Kubernetes 的其中几个 Node 上部署 Traefik

### 2.1、Docker Compose

Traefik 的 Docker Compose 如下

``` yml
version: '3.5'

services:
  traefik:
    image: traefik:v1.6.1-alpine
    container_name: traefik
    command: --configFile=/etc/traefik.toml
    ports:
      - "2080:2080"
      - "2180:2180"
    volumes:
      - ./traefik.toml:/etc/traefik.toml
      - ./k8s-root-ca.pem:/etc/kubernetes/ssl/k8s-root-ca.pem
      - ./log:/var/log/traefik
```

由于 Kubernetes 集群开启了 RBAC 认证同时采用 TLS 通讯，所以需要挂载 Kubernetes CA 证书，还需要为 Traefik 创建对应的 RBAC 账户以使其能够访问 Kubernetes API

### 2.2、创建 RBAC 账户

Traefik 连接 Kubernetes API 时需要使用 Service Account 的 Token，Service Account 以及 ClusterRole 等配置具体见 [官方文档](https://docs.traefik.io/user-guide/kubernetes/)，下面是我从当前版本的文档中 Copy 出来的

``` yml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: traefik-ingress-controller
  namespace: kube-system
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller
rules:
  - apiGroups:
      - ""
    resources:
      - services
      - endpoints
      - secrets
    verbs:
      - get
      - list
      - watch
  - apiGroups:
      - extensions
    resources:
      - ingresses
    verbs:
      - get
      - list
      - watch
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: traefik-ingress-controller
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: traefik-ingress-controller
subjects:
- kind: ServiceAccount
  name: traefik-ingress-controller
  namespace: kube-system
```

创建好以后需要提取 Service Account 的 Token 方便下面使用，提取命令如下

``` sh
kubectl describe secret -n kube-system $(kubectl get secrets -n kube-system | grep traefik-ingress-controller | cut -f1 -d ' ') | grep -E '^token'
```

### 2.3、创建 Traefik 配置

Traefik 的具体配置细节请参考 [官方文档](https://docs.traefik.io/configuration/commons/)，以下仅给出一个样例配置

``` toml
# DEPRECATED - for general usage instruction see [lifeCycle.graceTimeOut].
#
# If both the deprecated option and the new one are given, the deprecated one
# takes precedence.
# A value of zero is equivalent to omitting the parameter, causing
# [lifeCycle.graceTimeOut] to be effective. Pass zero to the new option in
# order to disable the grace period.
#
# Optional
# Default: "0s"
#
# graceTimeOut = "10s"

# Enable debug mode.
# This will install HTTP handlers to expose Go expvars under /debug/vars and
# pprof profiling data under /debug/pprof.
# The log level will be set to DEBUG unless `logLevel` is specified.
#
# Optional
# Default: false
#
# debug = true

# Periodically check if a new version has been released.
#
# Optional
# Default: true
#
checkNewVersion = false

# Backends throttle duration.
#
# Optional
# Default: "2s"
#
# providersThrottleDuration = "2s"

# Controls the maximum idle (keep-alive) connections to keep per-host.
#
# Optional
# Default: 200
#
# maxIdleConnsPerHost = 200

# If set to true invalid SSL certificates are accepted for backends.
# This disables detection of man-in-the-middle attacks so should only be used on secure backend networks.
#
# Optional
# Default: false
#
# insecureSkipVerify = true

# Register Certificates in the rootCA.
#
# Optional
# Default: []
#
# rootCAs = [ "/mycert.cert" ]

# Entrypoints to be used by frontends that do not specify any entrypoint.
# Each frontend can specify its own entrypoints.
#
# Optional
# Default: ["http"]
#
# defaultEntryPoints = ["http", "https"]

# Allow the use of 0 as server weight.
# - false: a weight 0 means internally a weight of 1.
# - true: a weight 0 means internally a weight of 0 (a server with a weight of 0 is removed from the available servers).
#
# Optional
# Default: false
#
# AllowMinWeightZero = true

logLevel = "INFO"

[traefikLog]
  filePath = "/var/log/traefik/traefik.log"
  format   = "json"

[accessLog]
  filePath = "/var/log/traefik/access.log"
  format = "json"

  [accessLog.filters]
    statusCodes = ["200-511"]
    retryAttempts = true

#  [accessLog.fields]
#    defaultMode = "keep"
#    [accessLog.fields.names]
#      "ClientUsername" = "drop"
#      # ...
#
#    [accessLog.fields.headers]
#      defaultMode = "keep"
#      [accessLog.fields.headers.names]
#        "User-Agent" = "redact"
#        "Authorization" = "drop"
#        "Content-Type" = "keep"
#        # ...


[entryPoints]
  [entryPoints.http]
    address = ":2080"
    compress = true
  [entryPoints.traefik]
    address = ":2180"
    compress = true

#    [entryPoints.http.whitelist]
#      sourceRange = ["192.168.1.0/24"]
#      useXForwardedFor = true

#    [entryPoints.http.tls]
#      minVersion = "VersionTLS12"
#      cipherSuites = [
#        "TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256",
#        "TLS_RSA_WITH_AES_256_GCM_SHA384"
#       ]
#      [[entryPoints.http.tls.certificates]]
#        certFile = "path/to/my.cert"
#        keyFile = "path/to/my.key"
#      [[entryPoints.http.tls.certificates]]
#        certFile = "path/to/other.cert"
#        keyFile = "path/to/other.key"
#      # ...
#      [entryPoints.http.tls.clientCA]
#        files = ["path/to/ca1.crt", "path/to/ca2.crt"]
#        optional = false
#
#    [entryPoints.http.redirect]
#      entryPoint = "https"
#      regex = "^http://localhost/(.*)"
#      replacement = "http://mydomain/$1"
#      permanent = true
#
#    [entryPoints.http.auth]
#      headerField = "X-WebAuth-User"
#      [entryPoints.http.auth.basic]
#        users = [
#          "test:$apr1$H6uskkkW$IgXLP6ewTrSuBkTrqE8wj/",
#          "test2:$apr1$d9hr9HBB$4HxwgUir3HP4EsggP/QNo0",
#        ]
#        usersFile = "/path/to/.htpasswd"
#      [entryPoints.http.auth.digest]
#        users = [
#          "test:traefik:a2688e031edb4be6a3797f3882655c05",
#          "test2:traefik:518845800f9e2bfb1f1f740ec24f074e",
#        ]
#        usersFile = "/path/to/.htdigest"
#      [entryPoints.http.auth.forward]
#        address = "https://authserver.com/auth"
#        trustForwardHeader = true
#        [entryPoints.http.auth.forward.tls]
#          ca =  [ "path/to/local.crt"]
#          caOptional = true
#          cert = "path/to/foo.cert"
#          key = "path/to/foo.key"
#          insecureSkipVerify = true
#
#    [entryPoints.http.proxyProtocol]
#      insecure = true
#      trustedIPs = ["10.10.10.1", "10.10.10.2"]
#
#    [entryPoints.http.forwardedHeaders]
#      trustedIPs = ["10.10.10.1", "10.10.10.2"]
#
#  [entryPoints.https]
#    # ...

################################################################
# Kubernetes Ingress configuration backend
################################################################

# Enable Kubernetes Ingress configuration backend.
[kubernetes]

# Kubernetes server endpoint.
#
# Optional for in-cluster configuration, required otherwise.
# Default: empty
#
endpoint = "https://172.16.0.36:6443"

# Bearer token used for the Kubernetes client configuration.
#
# Optional
# Default: empty
#
token = "eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJrdWJlLXN5c3RlbSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VjcmV0Lm5hbWUiOiJ0cmFlZmlrLWluZ3Jlc3MtY29udHJvbGxlci10b2tlbi1zbm5iNSIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJ0cmFlZmlrLWlyZ3Jlc3MtY29udHJvbGxlciIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50LnVpZCI6ImE4NmI3YWEzLTVmNjQtMTFlOC1hZjYxLWM4MWY2NmUwMzRhNyIsInN1YiI6InN5c3RlbTpxZXJ2aWNlYWNjb3VudDPrdWJlLXN5c3RlbTp0cmFlZmlrLWluZ3Jlc3MtY29udHJvbGxlciJ9.vOFEITuANWGnkER8gukWkTs54BmHXqNpzM55bOb5qXPmI3pZsbei3gtE6tZoqME9P5Lb85cav-8mGZJcoQqqxNBkZJ1YRqy_1O9Apkxa4jA68ipe_NB3L5-exH5cEIrU8iql_r7ycDaKwzsMnAWGPolp1dRkF31u5u8g68oLwF3GR8Z5g4_tLJlTvA53doX7k6Wd6vUygTS3EaQ_qvfXwbcIeaSdWWo2Mym6O0CvIap4jH2w21MbredGURqkRlXEPezKAgRVkr75CdvuvwORnT8YxFLVwuAJs70V-13Ib9v6HAK64GmzcqkAuJtZT8NZKl8Y4TfRGl2_RMq2tk86gD4ShDMedcrto44ZUYHQccsSlpaW5PsN2KBBNPN0-6ca3jIpOmnJojAFUYGM42Wymnx9_4XwHUeeA18-RrercmOaRMdlNq8BzBomAxQB99TqUzRIqpe6m5OotXvouCUnE7qjMwRWmQ5LHjqUGEw_A1pHcalFXQZK0sOCaJOJZIJbc_8rVX-4uxkCBxoIXmzjq8x5a_xPsN4L0aWifkP6co--agw3kOT0O6my8T_CbcZGO9e3OqYPdT4FSl92XlXW8EXHdDpCUJ10aoqJGG2vZSud7IoDxkcScpkj3n6TvyvSRVtk3CtYiIYBpgi7-X2JKkun1a7yFpLogyazz9VlUE4"

# Path to the certificate authority file.
# Used for the Kubernetes client configuration.
#
# Optional
# Default: empty
#
certAuthFilePath = "/etc/kubernetes/ssl/k8s-root-ca.pem"

# Array of namespaces to watch.
#
# Optional
# Default: all namespaces (empty array).
#
namespaces = ["default"]

# Ingress label selector to filter Ingress objects that should be processed.
#
# Optional
# Default: empty (process all Ingresses)
#
# labelselector = "A and not B"

# Value of `kubernetes.io/ingress.class` annotation that identifies Ingress objects to be processed.
# If the parameter is non-empty, only Ingresses containing an annotation with the same value are processed.
# Otherwise, Ingresses missing the annotation, having an empty value, or the value `traefik` are processed.
#
# Note : `ingressClass` option must begin with the "traefik" prefix.
#
# Optional
# Default: empty
#
# ingressClass = "traefik-internal"

# Disable PassHost Headers.
#
# Optional
# Default: false
#
# disablePassHostHeaders = true

# Enable PassTLSCert Headers.
#
# Optional
# Default: false
#
# enablePassTLSCert = true

# Override default configuration template.
#
# Optional
# Default: <built-in template>
#
# filename = "kubernetes.tmpl"


# API definition
[api]
  # Name of the related entry point
  #
  # Optional
  # Default: "traefik"
  #
  entryPoint = "traefik"

  # Enabled Dashboard
  #
  # Optional
  # Default: true
  #
  dashboard = true

  # Enable debug mode.
  # This will install HTTP handlers to expose Go expvars under /debug/vars and
  # pprof profiling data under /debug/pprof.
  # Additionally, the log level will be set to DEBUG.
  #
  # Optional
  # Default: false
  #
  debug = false

# Ping definition
#[ping]
#  # Name of the related entry point
#  #
#  # Optional
#  # Default: "traefik"
#  #
#  entryPoint = "traefik"
```

### 2.4、启动 Traefik

所有文件准备好以后直接执行 `docker-compose up -d` 启动即可，所有文件目录结构如下

``` sh
traefik
├── docker-compose.yaml
├── k8s-root-ca.pem
├── log
│   ├── access.log
│   └── traefik.log
├── rbac.yaml
└── traefik.toml
```

启动成功后可以访问 `http://IP:2180` 查看 Traefik 的控制面板

![dashboard](https://mritd.b0.upaiyun.com/markdown/phrps.png)

## 三、增加 Ingress 配置并测试

### 3.1、增加 Ingress 配置

虽然这种部署方式脱离了 Kubernetes 的 Service 与 Ingress 负载，但是 Traefik 还是需要通过 Kubernetes 的 Ingress 配置来确定后端负载规则，所以 Ingress 对象我们仍需照常创建；以下为一个 Demo 项目的 deployment、service、ingress 配置示例

- demo.deploy.yaml

``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo
spec:
  replicas: 5
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - name: demo
        image: mritd/demo
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
```

- demo.svc.yaml

``` yaml
apiVersion: v1
kind: Service
metadata:
  name: demo
  labels:
    svc: demo
spec:
  ports:
  - port: 8080
    name: http
    targetPort: 80
  selector:
    app: demo
```

- demo.ing.yaml

``` yaml
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: demo
  annotations:
    traefik.ingress.kubernetes.io/preserve-host: "true"
spec:
  rules:
  - host: demo.mritd.me
    http:
      paths:
      - backend:
          serviceName: demo
          servicePort: 8080
```

### 3.2、测试访问

部署好后应当能从 Traefik 的 Dashboard 中看到新增的 demo ingress，如下所示

![dashboard-demo](https://mritd.b0.upaiyun.com/markdown/zociy.png)

最后我们使用 curl 测试即可

``` sh
# 在不使用 Host 头的情况下 Traefik 会返 404(Traefik 根据 Host 路由后端，具体配置参考官方文档)
test36.node ➜  ~ curl http://172.16.0.36:2080
404 page not found

# 指定 Host 头来路由到 demo 的相关 Pod
test36.node ➜  ~ curl -H "Host: demo.mritd.me" http://172.16.0.36:2080
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <title>Running!</title>
    <style type="text/css">
        body {
            width: 100%;
            min-height: 100%;
            background: linear-gradient(to bottom, #fff 0, #b8edff 50%, #83dfff 100%);
            background-attachment: fixed;
        }
    </style>
</head>
<body class=" hasGoogleVoiceExt">
<div align="center">
    <h1>Your container is running!</h1>
    <img src="./docker.png" alt="docker">
</div>
</body>
</html>#
```

## 四、其他说明

写这篇文章的目的是给予一种新的服务暴露思路，这篇文章的某些配置并不适合生产使用；**生产环境尽量使用独立的机器部署 Traefik，同时最好宿主机二进制方式部署；应用的 Deployment 也应当加入健康检测以防止错误的流量路由**；至于 Traefik 的具体细节配置，比如访问日志、Entrypoints 配置、如何连接 Kubernets HA api 等不在本文范畴内，请自行查阅文档；

最后说一下，关于 Traefik 的 HA 只需要部署多个实例即可，还有 Traefik 本身不做日志滚动等，需要自行处理一下日志。

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
