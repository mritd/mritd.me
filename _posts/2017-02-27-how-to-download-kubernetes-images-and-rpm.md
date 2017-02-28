---
layout: post
categories: Kubernetes
title: 如何下载 Kubernetes 镜像和 rpm
date: 2017-02-27 22:02:48 +0800
description: 如何下载 Kubernetes 镜像和 rpm
keywords: Kubernetes gcr.io rpm
---

> 随着 kubernetes 容器化部署逐渐推进，gcr.io 镜像、kubernetes rpm 下载由于 "伟大的" 墙的原因成为阻碍玩 kubernetes 第一道屏障，以下记录了个人维护的 yum 仓库和 gcr.io 反代仓库使用


### 一、yum 源

目前个人维护了一个 kubernetes 的 yum 源，目前 yum 源包含 rpm 如下

|rpm 包|版本|
|------|----|
|etcd|3.1.0-1.x86_64|
|flannel|0.7.0-1.x86_64|
|kubernetes|1.5.3-1.x86_64|
|kubeadm|1.6.0-0.alpha.0.2074.a092d8e0f95f52.x86_64|
|kubectl|1.5.3-0.x86_64|
|kubelet|1.5.3-0.x86_64|
|kubernetes-cni|0.3.0.1-0.07a8a2.x86_64|

使用方法如下

``` sh
# 添加 yum 源
tee /etc/yum.repos.d/mritd.repo << EOF
[mritd]
name=Mritd Repository
baseurl=https://yum.mritd.me/centos/7/x86_64
enabled=1
gpgcheck=1
gpgkey=https://mritd.b0.upaiyun.com/keys/rpm.public.key
EOF
# 刷新cache
yum makecache
# 安装 yum-utils
yum install -y yum-utils socat 
# 下载 rpm 到本地
yumdownloader kubelet kubectl kubernetes-cni kubeadm
# 安装 rpm
rpm -ivh kube*.rpm
```

**所有关于 yum 源地址变更等都将在 [https://yum.mritd.me](https://yum.mritd.me) 页面公告，如出现不能使用请访问此页面查看相关原因**；**如果实在下载过慢可以将 `yum.mritd.me` 替换成 `yumrepo.b0.upaiyun.com`，此域名 yum 源在 CDN 上，由于流量有限，请使用 yumdownloader 工具下载到本地分发安装，谢谢**

### 二、kubernetes 镜像

关于 kubernetes 镜像下载，一般有三种方式：

- 直接从国外服务器 pull 然后 save 出来传到本地
- 通过第三方仓库做中转，如 Docker hub
- 在本地/国外能访问的服务器通过官方 registry 加代理反代 gcr.io

**个人在国外服务器上维护了一个 gcr.io 的反代仓库，使用方式如下**

``` sh
docker pull gcr.mritd.me/google_containers/kube-apiserver-amd64:v1.5.3
```

如果对于 gcr.mritd.me 访问过慢可参考 [gcr.io 仓库代理](https://mritd.me/2017/02/09/gcr.io-registy-proxy/) 使用带有梯子的本地私服，如果使用 Docker Hub 等中转可参考 [kubeadm 搭建 kubernetes 集群](https://mritd.me/2016/10/29/set-up-kubernetes-cluster-by-kubeadm/#22%E9%95%9C%E5%83%8F%E4%BB%8E%E5%93%AA%E6%9D%A5)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
