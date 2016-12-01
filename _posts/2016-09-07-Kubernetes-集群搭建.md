---
layout: post
title: Kubernetes 集群搭建
categories: [Docker, Kubernetes]
description: Kubernetes 集群搭建
keywords: Kubernetes,k8s,Docker,Etcd,Flannel,Linux
---



## 一、简介

kubernetes 是 Google 内部使用的 Borg 容器调度框架的开源实现，其凝聚了 Google 十几年容器经验的最佳实践，其支持 Dokcer 和 Rkt 容器的编排功能，以下记录一下 Kubernetes 集群搭建过程。

## 二、环境准备

kubernetes 搭建集群环境推荐至少3个节点，1个 master 和2个 slave 节点，所以至少三台服务器(虚拟机)；容器间通讯采用 flannel 实现跨主机通讯，具体参考 [Dokcer 使用 Flannel 跨主机通讯](http://mritd.me/2016/09/03/Dokcer-%E4%BD%BF%E7%94%A8-Flannel-%E8%B7%A8%E4%B8%BB%E6%9C%BA%E9%80%9A%E8%AE%AF/) 文章，同时 kubernetes 本身的服务发现机制依赖于 etcd，etcd 可使用单机模式，也可以构建高可用集群，集群搭建可参考 [Etcd 集群搭建](http://mritd.me/2016/09/01/Etcd-%E9%9B%86%E7%BE%A4%E6%90%AD%E5%BB%BA/) 文章；最后总体环境如下:

<!--more-->

- 3台虚拟机
- 每台安装好 Docker
- 配置好 Docker 使用 Flannel 跨主机通讯

**主机列表如下**

|主机|环境配置|
|----|--------|
|192.168.1.108|k8s master、etcd|
|192.168.1.139|k8s node1|
|192.168.1.215|k8s node2|

## 三、搭建示例

> 以下安装全部基于 rpm 包方式，关于 falnnel、etcd、kubernetes 的 rpm 包可通过 [build\_rpm\_tool.sh](https://github.com/mritd/shell_scripts/blob/master/build_rpm_tool.sh) 脚本工具创建指定版本的 rpm 包，下载脚本使用 `./build_rpm_tool.sh k8s 1.3.6` 命令即可创建一个 k8s 的 rpm，**如需多次使用，请将脚本第 181 行 k8s rpm 地址替换为已经自己编译好的 k8s rpm 地址(cdn 流量不多)**


### 3.1、安装 Etcd

首先安装 etcd rpm 包

``` sh
rpm -ivh etcd-2.3.7-1.x86_64.rpm
```

然后修改 etcd 配置

``` sh
# 编辑配置文件
vim /etc/etcd/etcd.conf
# 修改后内容如下
ETCD_NAME=default
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_CLIENT_URLS="http://192.168.1.108:2379"
ETCD_ADVERTISE_CLIENT_URLS="http://192.168.1.108:2379"
```

最后启动并测试

``` sh
# 启动
systemctl enable etcd
systemctl start etcd
# 连接测试
etcdctl --endpoints http://192.168.1.108:2379 member list
# 返回结果如下
ce2a822cea30bfca: name=default peerURLs=http://localhost:2380,http://localhost:7001 clientURLs=http://192.168.1.108:2379 isLeader=true
```

### 3.2、安装 flannel

安装过程如下，三台虚拟机都要安装

``` sh
# 安装
rpm -ivh flannel-0.6.1-1.x86_64.rpm
# 设置 IP 段
etcdctl --endpoints http://192.168.1.108:2379 set /coreos.com/network/config '{"NetWork":"10.0.0.0/16"}'
# 修改配置
vim /etc/sysconfig/flanneld
# 配置如下 enp0s3 为监听网卡
FLANNEL_ETCD="http://192.168.1.108:2379"
FLANNEL_ETCD_KEY="/coreos.com/network"
FLANNEL_OPTIONS="--iface=enp0s3"
# 启动
systemctl enable flanneld
systemctl start flanneld
# 修改 docker 配置
vim /usr/lib/systemd/system/docker.service
# 在 ExecStart 后增加 $DOCKER_NETWORK_OPTIONS 参数
ExecStart=/usr/bin/dockerd $DOCKER_NETWORK_OPTIONS
# 重启 docker
systemctl daemon-reload
systemctl restart docker
```

### 3.3、安装 master

kubernetes master 安装在 108 上，与etcd 在同一台主机，安装 kubernetes rpm 包命令如下

``` sh
rpm -ivh kubernetes-1.3.6-1.x86_64.rpm
```

**配置 apiserver**

``` sh
# 编辑配置文件
vim /etc/kubernetes/apiserver
# 配置信息如下
KUBE_API_ADDRESS="--insecure-bind-address=192.168.1.108"
# The port on the local server to listen on.
KUBE_API_PORT="--insecure-port=8080"
# Port minions listen on
KUBELET_PORT="--kubelet_port=10250"
# Comma separated list of nodes in the etcd cluster
KUBE_ETCD_SERVERS="--etcd_servers=http://192.168.1.108:2379"
# Address range to use for services
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"
# default admission control policies
KUBE_ADMISSION_CONTROL="--admission_control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota"
# Add your own!
KUBE_API_ARGS=""
```


**启动 master**

``` sh
systemctl start kube-apiserver
systemctl start kube-controller-manager
systemctl start kube-scheduler
systemctl enable kube-apiserver
systemctl enable kube-controller-manager
systemctl enable kube-scheduler
systemctl status kube-apiserver
systemctl status kube-controller-manager
systemctl status kube-scheduler
```

### 3.4、安装 slave

其余两台虚拟机需要安装成 slave 节点，首先配置好 docker 和flannel，参考 3.1，安装过程如下

首先安装 kubernetes

``` sh
rpm -ivh kubernetes-1.3.6-1.x86_64.rpm
```

配置 kubelet

``` sh
# 编辑配置文件
vim /etc/kubernetes/kubelet
# 配置如下
KUBELET_ADDRESS="--address=192.168.1.139"
# The port for the info server to serve on
KUBELET_PORT="--port=10250"
# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname_override=192-168-1-139"
# location of the api-server
KUBELET_API_SERVER="--api_servers=http://192.168.1.108:8080"
# Add your own!
KUBELET_ARGS="--pod-infra-container-image=docker.io/kubernetes/pause:latest"
```

**`KUBELET_HOSTNAME` 参数用于指定 slave 在 master 中显示的名字，一般为了便于区分会自定义名字，但是自定义的名字必须在 hosts 文件中存在，所以还要修改 hosts 文件**

``` sh
echo "127.0.0.1 192-168-1-139" >> /etc/hosts
```

接着修改主配置文件

``` sh
# 编辑配置文件
vim /etc/kubernetes/config
# 配置样例如下
KUBE_LOGTOSTDERR="--logtostderr=true"
# journal message level, 0 is debug
KUBE_LOG_LEVEL="--v=0"
# Should this cluster be allowed to run privileged docker containers
KUBE_ALLOW_PRIV="--allow_privileged=false"
# How the controller-manager, scheduler, and proxy find the apiserver
KUBE_MASTER="--master=http://192.168.1.108:8080"
```

**最后启动测试**

``` sh
# 启动
systemctl start kubelet
systemctl start kube-proxy
systemctl enable kubelet
systemctl enable kube-proxy
systemctl status kubelet
systemctl status kube-proxy
# 回到 108 master 测试
kubectl --server="http://192.168.1.108:8080" get node
# 显示如下
NAME            STATUS    AGE
192-168-1-139   Ready     53s
```

另外一台同理，到此 集群搭建完成

## 四、其他相关

- kubernetes、etcd 等监听端口最好指定为内网IP，尽量不要监听 `0.0.0.0`，监听公网很容易被黑
- kubernetes 通讯最好开启 SSL，尤其是使用 "联邦模式" 时(跨级群调度)
- etcd 最好搭建集群解决单点问题，同时最好准备2台dns服务器，用于服务发现等
- kubernetes 如果启用了 skydns 则最好在 `KUBELET_ARGS` 参数中加入 `--cluster_dns=x.x.x.x` 为 skydns，这样在每个 pod 启动后默认 dns 都会指向 skydns
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
