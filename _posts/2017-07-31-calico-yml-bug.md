---
layout: post
categories: Kubernetes Calico
title: Calico 部署踩坑记录
date: 2017-07-31 15:39:23 +0800
description: Calico 部署踩坑记录
keywords: Kubernetes,Calico
catalog: true
multilingual: false
tags: Linux Docker Kubernetes
---

> 自从上次在虚拟机中手动了部署了 Kubernetes 1.7.2 以后，自己在测试环境就来了一下，结果网络组件死活起不来，最后找到原因记录一下

### 一、Calico 部署注意事项

在使用 Calico 前当然最好撸一下官方文档，地址在这里 [Calico 官方文档](http://docs.projectcalico.org/v2.3/getting-started/kubernetes/installation/)，其中部署前需要注意以下几点

- **官方文档中要求 `kubelet` 配置必须增加 `--network-plugin=cni` 选项**
- **`kube-proxy` 组件必须采用 `iptables` proxy mode 模式(1.2 以后是默认模式)**
- **`kubec-proxy` 组件不能采用 `--masquerade-all` 启动，因为会与 Calico policy 冲突**
- **`NetworkPolicy API` 只要需要 Kubernetes 1.3 以上**
- **启用 RBAC 后需要设置对应的 RoleBinding，参考 [官方文档 RBAC 部分](http://docs.projectcalico.org/v2.3/getting-started/kubernetes/installation/hosted/)**

### 二、Calico 官方部署方式

在已经有了一个 Kubernetes 集群的情况下，官方部署方式描述的很简单，只需要改一改 yml 配置，然后 create 一下即可，具体描述见 [官方文档](http://docs.projectcalico.org/v2.3/getting-started/kubernetes/installation/hosted/)

官方文档中大致给出了三种部署方案: 

- **Standard Hosted Install:** 修改 calico.yml etcd 相关配置，直接创建，证书配置等参考 [手动部署 Kubernetes 文档](https://mritd.me/2017/07/21/set-up-kubernetes-ha-cluster-by-binary/#%E5%85%AD%E9%83%A8%E7%BD%B2-calico)
- **Kubeadm Hosted Install:** 根据 `1.6 or high` 和 `1.5` 区分两个 yml 配置，直接创建即可
- **Kubernetes Datastore:** 不使用 Etcd 存储数据，不推荐，这里也不做说明

### 三、Standard Hosted Install 的坑

当我从虚拟机中测试完全没问题以后，就在测试环境尝试创建 Calico 网络，结果出现的问题是**某个(几个) Calico 节点无法启动，同时创建 deployment 后，执行 `route -n` 会发现每个 node 只有自己节点 Pod 的路由，正常每个 node 上会有所有 node 上 Pod 网段的路由，如下(正常情况)**

![calico route](https://mritd.b0.upaiyun.com/markdown/c44e7.jpg)

此时观察每个 node 上 Calico Pod 日志，会有提示 **未知节点 xxxx** 等错误日志，大体意思就是 **未知的一个(几个)节点在进行 BGP 协议时被拒绝**，偶尔某些 node 上还可能出现 **IP 已经被占用** 的神奇错误提示

后来经过翻查 [Calico 自定义部署文档](http://docs.projectcalico.org/v2.3/getting-started/kubernetes/installation/integration) 和 [Kargo 项目源码](https://github.com/kubernetes-incubator/kubespray) 发现了主要问题在于 **官方文档中直接创建的 calico.yml 文件中，使用 DaemonSet 方式启动 calico-node，同时 calico-node 的 IP 设置和 NODENAME 设置均为空，此时 calico-node 会进行自动获取，网络复杂情况下获取会出现问题；比如 IP 拿到了 docker 网桥的 IP，NODENAME 获取不正确等，最终导致出现很奇怪的错误**

### 四、解决方案

一开始想到的解决方案很简单，直接照着 Kargo 抄，使用 Systemd 来启动 calico-node，然后在拆分过程中需要各种配置信息直接也根据 Kargo 的做法生成；当然鼓捣了 1/3 的时候就炸了，Kargo 是 ansible 批量部署的，有些变量找起来要人命；最后选择了一个折中(偷懒)的方案: **使用官方的 calico.yml 创建相关组件，这样 ConfigMap、Etcd 配置、Calico policy 啥的直接创建好，然后把 DaemonSet 中 calico-node 容器单独搞出来，使用 Systemd 启动，这样就即方便又简单(我真特么机智)；最终操作如下:**

#### 4.1、首先修改 calico.yml

在进行网络组件部署前，请确保集群已经满足 Calico 部署要求(本文第一部分)；然后获取 calico.yml，注释掉 DaemonSet 中 calico-node 部分，如下所示

``` yml
# Calico Version v2.3.0
# http://docs.projectcalico.org/v2.3/releases#v2.3.0
# This manifest includes the following component versions:
#   calico/node:v1.3.0
#   calico/cni:v1.9.1
#   calico/kube-policy-controller:v0.6.0

# This ConfigMap is used to configure a self-hosted Calico installation.
kind: ConfigMap
apiVersion: v1
metadata:
  name: calico-config
  namespace: kube-system
data:
  # Configure this with the location of your etcd cluster.
  etcd_endpoints: "https://192.168.1.11:2379,https://192.168.1.12:2379,https://192.168.1.13:2379"

  # Configure the Calico backend to use.
  calico_backend: "bird"

  # The CNI network configuration to install on each node.
  cni_network_config: |-
    {
        "name": "k8s-pod-network",
        "cniVersion": "0.1.0",
        "type": "calico",
        "etcd_endpoints": "__ETCD_ENDPOINTS__",
        "etcd_key_file": "__ETCD_KEY_FILE__",
        "etcd_cert_file": "__ETCD_CERT_FILE__",
        "etcd_ca_cert_file": "__ETCD_CA_CERT_FILE__",
        "log_level": "info",
        "ipam": {
            "type": "calico-ipam"
        },
        "policy": {
            "type": "k8s",
            "k8s_api_root": "https://__KUBERNETES_SERVICE_HOST__:__KUBERNETES_SERVICE_PORT__",
            "k8s_auth_token": "__SERVICEACCOUNT_TOKEN__"
        },
        "kubernetes": {
            "kubeconfig": "__KUBECONFIG_FILEPATH__"
        }
    }

  # If you're using TLS enabled etcd uncomment the following.
  # You must also populate the Secret below with these files.
  etcd_ca: "/calico-secrets/etcd-ca"
  etcd_cert: "/calico-secrets/etcd-cert"
  etcd_key: "/calico-secrets/etcd-key"

---

# The following contains k8s Secrets for use with a TLS enabled etcd cluster.
# For information on populating Secrets, see http://kubernetes.io/docs/user-guide/secrets/
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: calico-etcd-secrets
  namespace: kube-system
data:
  # Populate the following files with etcd TLS configuration if desired, but leave blank if
  # not using TLS for etcd.
  # This self-hosted install expects three files with the following names.  The values
  # should be base64 encoded strings of the entire contents of each file.
  etcd-key: 这块自己对 etcd 相关证书做 base64
  etcd-cert: 这块自己对 etcd 相关证书做 base64
  etcd-ca: 这块自己对 etcd 相关证书做 base64

---

# This manifest installs the calico/node container, as well
# as the Calico CNI plugins and network config on
# each master and worker node in a Kubernetes cluster.
kind: DaemonSet
apiVersion: extensions/v1beta1
metadata:
  name: calico-node
  namespace: kube-system
  labels:
    k8s-app: calico-node
spec:
  selector:
    matchLabels:
      k8s-app: calico-node
  template:
    metadata:
      labels:
        k8s-app: calico-node
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
        scheduler.alpha.kubernetes.io/tolerations: |
          [{"key": "dedicated", "value": "master", "effect": "NoSchedule" },
           {"key":"CriticalAddonsOnly", "operator":"Exists"}]
    spec:
      hostNetwork: true
      serviceAccountName: calico-node
      containers:
        # Runs calico/node container on each Kubernetes node.  This
        # container programs network policy and routes on each
        # host.
# calico-node 注释掉，移动到 Systemd 中
#        - name: calico-node
#          image: quay.io/calico/node:v1.3.0
#          env:
#            # The location of the Calico etcd cluster.
#            - name: ETCD_ENDPOINTS
#              valueFrom:
#                configMapKeyRef:
#                  name: calico-config
#                  key: etcd_endpoints
#            # Choose the backend to use.
#            - name: CALICO_NETWORKING_BACKEND
#              valueFrom:
#                configMapKeyRef:
#                  name: calico-config
#                  key: calico_backend
#            # Disable file logging so `kubectl logs` works.
#            - name: CALICO_DISABLE_FILE_LOGGING
#              value: "true"
#            # Set Felix endpoint to host default action to ACCEPT.
#            - name: FELIX_DEFAULTENDPOINTTOHOSTACTION
#              value: "ACCEPT"
#            # Configure the IP Pool from which Pod IPs will be chosen.
#            - name: CALICO_IPV4POOL_CIDR
#              value: "10.254.64.0/18"
#            - name: CALICO_IPV4POOL_IPIP
#              value: "always"
#            # Disable IPv6 on Kubernetes.
#            - name: FELIX_IPV6SUPPORT
#              value: "false"
#            # Set Felix logging to "info"
#            - name: FELIX_LOGSEVERITYSCREEN
#              value: "info"
#            # Location of the CA certificate for etcd.
#            - name: ETCD_CA_CERT_FILE
#              valueFrom:
#                configMapKeyRef:
#                  name: calico-config
#                  key: etcd_ca
#            # Location of the client key for etcd.
#            - name: ETCD_KEY_FILE
#              valueFrom:
#                configMapKeyRef:
#                  name: calico-config
#                  key: etcd_key
#            # Location of the client certificate for etcd.
#            - name: ETCD_CERT_FILE
#              valueFrom:
#                configMapKeyRef:
#                  name: calico-config
#                  key: etcd_cert
#            # Auto-detect the BGP IP address.
#            - name: IP
#              value: ""
#          securityContext:
#            privileged: true
#          resources:
#            requests:
#              cpu: 250m
#          volumeMounts:
#            - mountPath: /lib/modules
#              name: lib-modules
#              readOnly: true
#            - mountPath: /var/run/calico
#              name: var-run-calico
#              readOnly: false
#            - mountPath: /calico-secrets
#              name: etcd-certs
#        # This container installs the Calico CNI binaries
#        # and CNI network config file on each node.
        - name: install-cni
          image: quay.io/calico/cni:v1.9.1
          command: ["/install-cni.sh"]
          env:
            # The location of the Calico etcd cluster.
            - name: ETCD_ENDPOINTS
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_endpoints
            # The CNI network config to install on each node.
            - name: CNI_NETWORK_CONFIG
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: cni_network_config
          volumeMounts:
            - mountPath: /host/opt/cni/bin
              name: cni-bin-dir
            - mountPath: /host/etc/cni/net.d
              name: cni-net-dir
            - mountPath: /calico-secrets
              name: etcd-certs
      volumes:
        # Used by calico/node.
        - name: lib-modules
          hostPath:
            path: /lib/modules
        - name: var-run-calico
          hostPath:
            path: /var/run/calico
        # Used to install CNI.
        - name: cni-bin-dir
          hostPath:
            path: /opt/cni/bin
        - name: cni-net-dir
          hostPath:
            path: /etc/cni/net.d
        # Mount in the etcd TLS secrets.
        - name: etcd-certs
          secret:
            secretName: calico-etcd-secrets

---

# This manifest deploys the Calico policy controller on Kubernetes.
# See https://github.com/projectcalico/k8s-policy
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: calico-policy-controller
  namespace: kube-system
  labels:
    k8s-app: calico-policy
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ''
    scheduler.alpha.kubernetes.io/tolerations: |
      [{"key": "dedicated", "value": "master", "effect": "NoSchedule" },
       {"key":"CriticalAddonsOnly", "operator":"Exists"}]
spec:
  # The policy controller can only have a single active instance.
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      name: calico-policy-controller
      namespace: kube-system
      labels:
        k8s-app: calico-policy
    spec:
      # The policy controller must run in the host network namespace so that
      # it isn't governed by policy that would prevent it from working.
      hostNetwork: true
      serviceAccountName: calico-policy-controller
      containers:
        - name: calico-policy-controller
          image: quay.io/calico/kube-policy-controller:v0.6.0
          env:
            # The location of the Calico etcd cluster.
            - name: ETCD_ENDPOINTS
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_endpoints
            # Location of the CA certificate for etcd.
            - name: ETCD_CA_CERT_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_ca
            # Location of the client key for etcd.
            - name: ETCD_KEY_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_key
            # Location of the client certificate for etcd.
            - name: ETCD_CERT_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_cert
            # The location of the Kubernetes API.  Use the default Kubernetes
            # service for API access.
            - name: K8S_API
              value: "https://kubernetes.default:443"
            # Since we're running in the host namespace and might not have KubeDNS
            # access, configure the container's /etc/hosts to resolve
            # kubernetes.default to the correct service clusterIP.
            - name: CONFIGURE_ETC_HOSTS
              value: "true"
          volumeMounts:
            # Mount in the etcd TLS secrets.
            - mountPath: /calico-secrets
              name: etcd-certs
      volumes:
        # Mount in the etcd TLS secrets.
        - name: etcd-certs
          secret:
            secretName: calico-etcd-secrets

---

apiVersion: v1
kind: ServiceAccount
metadata:
  name: calico-policy-controller
  namespace: kube-system

---

apiVersion: v1
kind: ServiceAccount
metadata:
  name: calico-node
  namespace: kube-system

```

**修改完成后直接 create 即可**

#### 4.2、增加 calico-node Systemd 配置

最后写一个 service 文件(我放到了 `/etc/systemd/system/calico-node.service`)，使用 Systemd 启动即可；**注意以下配置中 `IP`、`NODENAME` 是自己手动定义的，IP 为宿主机 IP，NODENAME 最好与 hostname 相同**

``` sh
[Unit]
Description=calico node
After=docker.service
Requires=docker.service

[Service]
User=root
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run   --net=host --privileged --name=calico-node \
                                -e ETCD_ENDPOINTS=https://192.168.1.11:2379,https://192.168.1.12:2379,https://192.168.1.13:2379 \
                                -e ETCD_CA_CERT_FILE=/etc/etcd/ssl/etcd-root-ca.pem \
                                -e ETCD_CERT_FILE=/etc/etcd/ssl/etcd.pem \
                                -e ETCD_KEY_FILE=/etc/etcd/ssl/etcd-key.pem \
                                -e NODENAME=docker1.node \
                                -e IP=192.168.1.11 \
                                -e IP6= \
                                -e AS= \
                                -e CALICO_IPV4POOL_CIDR=10.20.0.0/16 \
                                -e CALICO_IPV4POOL_IPIP=always \
                                -e CALICO_LIBNETWORK_ENABLED=true \
                                -e CALICO_NETWORKING_BACKEND=bird \
                                -e CALICO_DISABLE_FILE_LOGGING=true \
                                -e FELIX_IPV6SUPPORT=false \
                                -e FELIX_DEFAULTENDPOINTTOHOSTACTION=ACCEPT \
                                -e FELIX_LOGSEVERITYSCREEN=info \
                                -v /etc/etcd/ssl/etcd-root-ca.pem:/etc/etcd/ssl/etcd-root-ca.pem \
                                -v /etc/etcd/ssl/etcd.pem:/etc/etcd/ssl/etcd.pem \
                                -v /etc/etcd/ssl/etcd-key.pem:/etc/etcd/ssl/etcd-key.pem \
                                -v /var/run/calico:/var/run/calico \
                                -v /lib/modules:/lib/modules \
                                -v /run/docker/plugins:/run/docker/plugins \
                                -v /var/run/docker.sock:/var/run/docker.sock \
                                -v /var/log/calico:/var/log/calico \
                                quay.io/calico/node:v1.3.0
ExecStop=/usr/bin/docker rm -f calico-node
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
