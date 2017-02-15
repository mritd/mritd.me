---
layout: post
title: Dokcer 使用 Flannel 跨主机通讯
categories: [Docker]
description: Dokcer 使用 Flannel 跨主机通讯
keywords: Linux,Docker,Flannel
---

## 一、简介

Flannel 是 CoreOS 提供用于解决 Dokcer 集群跨主机通讯的覆盖网络工具，Flannel 跨主机通讯在分配网络时，依赖于 Etcd，Etcd可参考 [Etcd 集群搭建](http://mritd.me/2016/09/01/Etcd-%E9%9B%86%E7%BE%A4%E6%90%AD%E5%BB%BA/)

## 二、二进制文件安装

### 2.1、环境准备

以下环境为 3 台虚拟机，同时 Etcd 集群已经配置好，同样安装在 3 台虚拟机上，节点 IP 如下

|节点|地址|
|----|----|
|etcd0|192.168.1.154|
|etcd1|192.168.1.156|
|etcd2|192.168.1.249|

<!--more-->

### 2.2、安装 Flannel

首先现在 Flannel 编译好的二进制文件 [Github 下载地址](https://github.com/coreos/flannel/releases)

``` sh
# 首先下载压缩包(可能需要自备梯子)
wget https://github.com/coreos/flannel/releases/download/v0.6.1/flannel-v0.6.1-linux-amd64.tar.gz
# 解压
tar -zxvf flannel-v0.6.1-linux-amd64.tar.gz
```

解压后的到 `flanneld`、`mk-docker-opts.sh` 两个文件，其中 `flanneld` 为主要的执行文件，sh 脚本用于生成 Docker 启动参数

### 2.3、配置 Flannel

解压好 Flannel 后将其复制到可执行目录

``` sh
cp flanneld /usr/local/bin/
```

由于 Flannel 需要依赖 Etcd 来保证集群 IP 分配不冲突的问题，所以首先要在 Etcd 中设置 Flannel 节点所使用的 IP 段

``` sh
etcdctl --endpoints http://etcd1.mritd.me:4001 \
set /coreos.com/network/config '{"NetWork":"10.0.0.0/16"}'
```

接下来启动 Flannel，并指定 Etcd 的集群位置即可，Etcd 集群前端可使用 nginx 或 haproxy 反向代理

``` sh
flanneld --etcd-endpoints="http://etcd1.mritd.me:2379" --ip-masq=true >> /var/log/flanneld.log 2>&1 &
```

![hexo_flannel_start](https://mritd.b0.upaiyun.com/markdown/hexo_flannel_start.png)

### 2.4、配置 Docker

在各个节点安装好以后最后要更改 Docker 的启动参数，使其能够使用 Flannel 进行 IP 分配，以及网络通讯

**Flannel 运行后会生成一个环境环境变量文件，包含了当前主机要使用 Flannel 通讯的相关参数**

``` sh
# 查看 Flannel 分配的网络参数
cat /run/flannel/subnet.env
# 相关网络参数如下
FLANNEL_NETWORK=10.0.0.0/16
FLANNEL_SUBNET=10.0.72.1/24
FLANNEL_MTU=1472
FLANNEL_IPMASQ=true
```

**修改 docker0 网卡参数**

``` sh
source /run/flannel/subnet.env
ifconfig docker0 ${FLANNEL_SUBNET}
```

此时可以看到 docker0 的网卡 ip 地址已经处于 Flannel 网卡网段之内

![hexo_flannel_modifydocker0](https://mritd.b0.upaiyun.com/markdown/hexo_flannel_modifydocker0.png)

**创建 Docker 运行变量**

接下来使用 Flannel 提供方的脚本创建 Docker 启动参数，创建好的启动参数位于 `/run/docker_opts.env ` 文件中

``` sh
./mk-docker-opts.sh -d /run/docker_opts.env -c
```

**修改 Docker 启动参数**

将 docker0 与 flannel0 绑定后，还需要修改 docker 的启动参数，并使其启动后使用由 Flannel 生成的配置参数，修改如下

``` sh
# 编辑 systemd service 配置文件
vim /usr/lib/systemd/system/docker.service
# 在启动时增加 Flannel 提供的启动参数
ExecStart=/usr/bin/dockerd $DOCKER_OPTS
# 指定这些启动参数所在的文件位置(这个配置是新增的，同样放在 Service标签下)
EnvironmentFile=/run/docker_opts.env
```

然后重新加载 systemd 配置，并重启 Docker 即可

``` sh
systemctl daemon-reload
systemctl restart docker
```

**整个完成流程截图如下**

![hexo_flannel_configall](https://mritd.b0.upaiyun.com/markdown/hexo_flannel_configall.png)

### 2.5、测试

每个节点分别启动一个 Contianer ，并相互 ping 测试即可

## 三、rpm 安装

CentOS 官方已经提供了 flannel 的 rpm 包，使用 rpm 包安装的好处是会自动创建一些配置文件，同时方便管理。

**目前官方提供的 rpm 包一般版本都会低一些，可以使用 [shell_scripts](https://github.com/mritd/shell_scripts) 中的 `build-flannel-rpm.sh` 脚本创建指定版本的 rpm 包，以下基于我创建好的 0.6.1 版本的 flannel rpm 安装**

### 3.1、安装 flannel

首先使用脚本创建一个 0.6.1 版本的 rpm

``` sh
git clone https://github.com/mritd/shell_scripts.git
cd shell_script
./build-flannel-rpm.sh 0.6.1
```

创建好以后可以直接进行安装

``` sh
rpm -ivh flannel-0.6.1-1.x86_64.rpm
```

### 3.2、配置 flannel

rpm 安装的 flannel 已经做了很多自动配置，我们只需要修改一下 flannel 的配置即可

``` sh
# 同样先在 etcd 中放入 flannel ip 分配地址
etcdctl --endpoints http://etcd1.mritd.me:4001 \
set /coreos.com/network/config '{"NetWork":"10.0.0.0/16"}'
# 然后编辑 flannel 配置文件
vim /etc/sysconfig/flanneld
# 修改 Etcd 地址和 Etcd 中 flannel ip 分配地址的目录即可
FLANNEL_ETCD="http://etcd1.mritd.me:2379"
FLANNEL_ETCD_KEY="/coreos.com/network"
# 最后重启 flannel 和 docker
systemctl restart flannel
systemctl restart docker
```

**测试同样创建两个 Contianer 相互ping即可**
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
