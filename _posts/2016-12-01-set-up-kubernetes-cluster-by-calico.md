---
layout: post
categories: Kubernetes Docker
title: Kubernetes 网络搭建-Calico
date: 2016-12-01 07:58:30 +0800
description: 记录 kubernetes 使用 calico 教程
keywords: kubernetes calico
---

> 接上一篇，大早上试下 Calico，从目前的各种评论上来看 Calico 的性能要更好些，不过由于是纯三层的解决方案，某些用到二层的应用可能无法使用，不过目前还没遇到过，个人理解这种情况应该不多

### 一、环境准备

首先有个 kubernetes 集群，集群网络处于未部署状态，集群信息如下

|IP地址|节点|
|------|-----|
|192.168.1.101|master|
|192.168.1.102|node,etcd(单点)|
|192.168.1.103|node|

### 二、开搞

至于 kubernetes 集群创建实在不想啰嗦，具体参考上一篇博客

Calico 官方提供了很好的文档支持，[在这里](http://docs.projectcalico.org/v1.6/getting-started/kubernetes/) 基本能找到所有的参考教程，以下直接照着官方文档来

首先把 Calico 的 yaml 下载下来，这里采用官方文档 kubernetes 页面的 yaml，**非 kubeadm 的**，kubeadm 页面的 yaml 里面 多了创建 etcd 集群信息啥的，没什么卵用

``` sh
wget http://docs.projectcalico.org/v1.6/getting-started/kubernetes/installation/hosted/calico.yaml
```

编辑 `calico.yaml`，修改 etcd 地址

``` sh
vim calico.yaml
# 将 etcd_endpoints 修改掉即可
etcd_endpoints: "http://192.168.1.102:2379"
```

然后创建网络

``` sh
kubectl create -f calico.yaml
```

创建完成后如下

![Calico](https://mritd.b0.upaiyun.com/markdown/ub8yg.jpg)

节点测试如下

![all node](https://mritd.b0.upaiyun.com/markdown/p7zlt.jpg)

![node2](https://mritd.b0.upaiyun.com/markdown/ybdw5.jpg)

![node3](https://mritd.b0.upaiyun.com/markdown/3qm8t.jpg)

**更细节的性能体现等可参考 [将Docker网络方案进行到底](http://blog.dataman-inc.com/shurenyun-docker-133/)**


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
