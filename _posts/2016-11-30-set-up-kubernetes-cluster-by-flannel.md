---
layout: post
categories: Kubernetes Docker
title: Kubernetes 网络搭建-flannel
date: 2016-11-30 22:57:48 +0800
description: 记录一下 kubernetes 使用 flannel 搭建网络的过程
keywords: Kubernetes flannel
---

> 一直用 weave，本篇记录一下 kubernetes 使用 flannel 作为网络组件，flannel 以 pod 方式部署

### 一、环境准备

首先有个 kubernetes 集群，集群网络处于未部署状态，集群信息如下

|IP地址|节点|
|------|-----|
|192.168.1.101|master|
|192.168.1.102|node,etcd(单点)|
|192.168.1.103|node|

### 二、开搞

#### 2.1、创建 kubernetes 集群

具体各种注意细节这里不再阐述，请参考本博客其他文章，**唯一要注意一点是创建集群(init)时要增加 `--pod-network-cidr 10.244.0.0/16` 参数；**网段根据需要自己指定，如果不使用 `--pod-network-cidr`  参数，则 flannel pod 启动后会出现 `failed to register network: failed to acquire lease: node "xxxxxx" pod cidr not assigned` 错误，以下为部分样例命令

``` sh
# 安装 rpm
tee /etc/yum.repos.d/mritd.repo << EOF
[mritdrepo]
name=Mritd Repository
baseurl=https://rpm.mritd.me/centos/7/x86_64
enabled=1
gpgcheck=1
gpgkey=https://mritd.b0.upaiyun.com/keys/rpm.public.key
EOF
yum install -y kubelet kubectl kubernetes-cni kubeadm

# 处理 hostname
echo "192-168-1-101.master" > /etc/hostname
echo "127.0.0.1   192-168-1-101.master" >> /etc/hosts
sysctl kernel.hostname="192-168-1-101.master"

# load 镜像
images=(kube-proxy-amd64:v1.4.6 kube-discovery-amd64:1.0 kubedns-amd64:1.7 kube-scheduler-amd64:v1.4.6 kube-controller-manager-amd64:v1.4.6 kube-apiserver-amd64:v1.4.6 etcd-amd64:2.2.5 kube-dnsmasq-amd64:1.3 exechealthz-amd64:1.1 pause-amd64:3.0 kubernetes-dashboard-amd64:v1.4.1)
for imageName in ${images[@]} ; do
  docker pull mritd/$imageName
  docker tag mritd/$imageName gcr.io/google_containers/$imageName
  docker rmi mritd/$imageName
done

# 其他的什么 dns、etcd 搞完了直接初始化
kubeadm init --api-advertise-addresses 192.168.1.101 --external-etcd-endpoints http://192.168.1.102:2379 --use-kubernetes-version v1.4.6 --pod-network-cidr 10.244.0.0/16
```

#### 2.2、创建 flannel 网络

前面如果都设置好创建网络很简单，跟 weave 一样

``` sh
kubectl create -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```

有兴趣的可以把 yml 搞下来看下，由于他的镜像托管在 `quay.io`，所以没有墙的问题，也可以提前 load 进来；对于 yml 上面的 `ConfigMap` 中的 ip 段最好与 `--pod-network-cidr` 一致(不一致没测试，想作死自己试吧)，然后稍等片刻网络便创建成功，截图如下

![flannel](https://mritd.b0.upaiyun.com/markdown/fh723.jpg)

#### 2.3、网络测试

由于环境有限(virtualbox 虚拟机)，所以暂时只测试一下网络互通是否有问题，关于性能啥的由于本人对网络部分也一直是个短板，需要大神们自己来了，如果可以给篇测试报告我也看看 `:)`

**rc 如下**

``` sh
apiVersion: v1
kind: ReplicationController
metadata:
  name: alpine
  labels:
    name: alpine
spec:
  replicas: 2
  selector:
    name: alpine
  template:
    metadata:
      labels:
        name: alpine
    spec:
      containers:
        - image: mritd/alpine:3.4
          imagePullPolicy: Always
          name: alpine
          command: 
            - "bash" 
            - "-c"
            - "while true;do echo test;done"
          ports:
            - containerPort: 8080
              name: alpine
```

**去两个主机上分别进入容器，然后互 ping 集群 IP 可以 ping 通**；图2 ping 错了，不重新截图了，谅解

![cluster ip](https://mritd.b0.upaiyun.com/markdown/x4i0j.jpg)

![node2 ping](https://mritd.b0.upaiyun.com/markdown/v24ju.jpg)

![node3 ping](https://mritd.b0.upaiyun.com/markdown/iukrh.jpg)

**本文只是简单搭建，其他更高级的性能测试交给各位玩网络的大神吧**


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权

