---
layout: post
categories: Kubernetes
title: 阿里云部署 Kubernetes
date: 2017-09-20 11:02:24 +0800
description: 记录阿里云部署 Kubernetes 踩坑
keywords: Kubernetes,Flannel,阿里云,aliyun
catalog: true
multilingual: false
tags: Linux Docker Kubernetes
---

> 公司有点小需求，在阿里云上开了几台机器，然后部署了一个 Kubernetes 集群，以下记录一下阿里云踩坑问题，主要是网络组件的坑。


### 一、部署环境

部署时开启了 4 台 ECS 实例，基本部署环境与裸机部署相似，其中区别是，阿里云网络采用 VPC 网络，不过以下流程适用于经典网络；以下为各个组件版本:

- OS CentOS
- Kernel 4.4.88-1.el7.elrepo.x86_64
- docker 1.13.1
- Kubernetes 1.7.5
- flannel v0.8.0-amd64

flannel 采用 vxlan 模式，虽然性能不太好，但是兼容度高一点；在阿里云上 flannel 可以采用 vpc 方式，具体可参考 [官方文档](https://coreos.com/flannel/docs/latest/alicloud-vpc-backend.html)(这个文档中描述的方法应该更适合 CNM 方式，我用的是 CNI，所以没去折腾他)


### 二、基本部署流程

关于 Master HA 等基本部署流程可以参考 [手动档搭建 Kubernetes HA 集群](https://mritd.me/2017/07/21/set-up-kubernetes-ha-cluster-by-binary/) 这篇文章，在部署网络组件之前的流程是相同的，这里不再阐述

### 三、Flannel 部署

关于 Flannel 部署，基本上有两种模式，一种是 vxlan，一种是采用 VPC，VPC 相关的部署上面已经提了，可以参考官方文档；以下说一下 Flannel 的 vxlan 部署方式:

#### 3.1、CNI 配置

首先保证集群在不开启 CNI 插件的情况下所有 Node Ready 状态，然后修改 `/etc/kubernetes/kubelet` 配置文件，加入 CNI 支持( `--network-plugin` )，配置如下

``` sh
# kubernetes kubelet (minion) config

# The address for the info server to serve on (set to 0.0.0.0 or "" for all interfaces)
KUBELET_ADDRESS="--address=192.168.1.77"

# The port for the info server to serve on
# KUBELET_PORT="--port=10250"

# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname-override=docker77.node"

# location of the api-server
# KUBELET_API_SERVER=""

# Add your own!
KUBELET_ARGS="--cgroup-driver=cgroupfs \
              --cluster-dns=10.254.0.2 \
              --network-plugin=cni \
              --resolv-conf=/etc/resolv.conf \
              --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
              --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
              --require-kubeconfig \
              --cert-dir=/etc/kubernetes/ssl \
              --cluster-domain=cluster.local. \
              --hairpin-mode promiscuous-bridge \
              --serialize-image-pulls=false \
              --pod-infra-container-image=gcr.io/google_containers/pause-amd64:3.0"
```

#### 3.2、Cluster CIDR 配置

**在开启 CNI 时使用 Flannel，要设置 `--allocate-node-cidrs` 和 `--cluster-cidr` 以保证 Flannel 能正确进行 IP 分配，这两个配置需要加入到 `/etc/kubernetes/controller-manager` 配置中，完整配置如下**

``` sh
###
# The following values are used to configure the kubernetes controller-manager

# defaults from config and apiserver should be adequate

# Add your own!
KUBE_CONTROLLER_MANAGER_ARGS="--address=192.168.1.77 \
                              --allocate-node-cidrs=true \
                              --cluster-cidr=10.244.0.0/16 \
                              --service-cluster-ip-range=10.254.0.0/16 \
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

#### 3.3、CNI 插件配置

开启 CNI 后，kubelet 创建的 POD 则需要 CNI 插件支持，这里让我感觉奇怪的是 Flannel 的 yaml 中对于 `install-cni` 这个容器只进行了配置复制，没有做插件复制；所以我们需要手动安装 CNI 插件，CNI 插件最新版本请留意 [Github](https://github.com/containernetworking/plugins/releases)；安装过程如下:

``` sh
# 创建 CNI 目录
mkdir -p /opt/cni/bin
# 下载 CNI 插件
wget https://github.com/containernetworking/plugins/releases/download/v0.6.0/cni-plugins-amd64-v0.6.0.tgz
tar -zxvf cni-plugins-amd64-v0.6.0.tgz
# 移动 CNI 插件
mv bridge flannel host-local loopback /opt/cni/bin
```

#### 3.4、安装 Flannel

当上面所有配置和 CNI 插件安装完成后，应当重启 kube-controller-manager 和 kubelet

``` sh
systemctl daemon-reload
systemctl restart kube-controller-manager kubelet
```

然后安装 Flannel 并配置 RBAC 即可

``` sh
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel-rbac.yml
```

**其他部署如 dns 等与原流程相同，不在阐述**

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
