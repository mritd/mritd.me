---
layout: post
categories: Kubernetes Docker
title: Consul 集群搭建
date: 2017-09-21 22:50:28 +0800
description: Consul 集群搭建
keywords: Consul,Etcd
catalog: true
multilingual: false
tags: Linux Docker Kubernetes
---

> 不知道 Consul 用的人多还是少，最近有人问怎么搭建 Consul 集群，这里顺手记录一下吧


### 一、简介

Consul 与 Etcd 一样，都属于分布式一致性数据库，其主要特性就是在分布式系统中出现意外情况如节点宕机的情况下保证数据的一致性；相对于 Etcd 来说，Consul 提供了更加实用的其他功能特性，如 DNS、健康检查、服务发现、多数据中心等，同时还有 web ui 界面，体验相对于更加友好

### 二、环境准备

同 Etcd 一样，Consul 最少也需要 3 台机器，这里测试实用 5 台机器进行部署集群，具体环境如下

|节点|IP|Version|
|----|---|------|
|server|192.168.1.11|v0.9.3|
|server|192.168.1.12|v0.9.3|
|server|192.168.1.13|v0.9.3|
|client|192.168.1.14|v0.9.3|
|client|192.168.1.15|v0.9.3|

其中 consul 采用 rpm 包的形式进行安装，这里并没有使用 docker 方式启动是因为个人习惯重要的数据存储服务交给 systemd管理；因为 docker 存在 docker daemon 的原因，如果用 docker 启动这种存储核心数据的组件，一但 daemon 出现问题那么所有容器都将出现问题；所以个人还是比较习惯将 etcd 和 consul 以二进制装在宿主机，由 systemd 直接管理。


### 三、部署集群

#### 3.1、Consul 集群模式

Consul 集群与 Etcd 略有区别，**Consul 在启动后分为两种模式:**

- Server 模式: 一个 Server 是一个有一组扩展功能的代理，这些功能包括参与 Raft 选举，维护集群状态，响应 RPC 查询，与其他数据中心交互 WAN gossip 和转发查询给 leader 或者远程数据中心。
- Client 模式: 一个 Client 是一个转发所有 RPC 到 Server 的代理。这个 Client 是相对无状态的；Client 唯一执行的后台活动是加入 LAN gossip 池，这有一个最低的资源开销并且仅消耗少量的网络带宽。

**其集群后如下所示:**

![Consul Cluster](https://mritd.b0.upaiyun.com/markdown/n4mdw.jpg)

#### 3.2、集群搭建

Consul 集群搭建时一般提供两种模式:

- **手动模式: 启动第一个节点后，此时此节点处于 bootstrap 模式，其节点手动执行加入**
- **自动模式: 启动第一个节点后，在其他节点配置好尝试加入的目标节点，然后等待其自动加入(不需要人为命令加入)**

这里采用自动加入模式，搭建过程如下:

**首先获取 Consul 的 rpm 包，鉴于官方并未提供 rpm 安装包，所以我自己造了一个轮子，打包脚本见 [Github](https://github.com/mritd/consul-rpm)，以下直接从我的 yum 源中安装**

``` sh
# 安装 yum 源
tee /etc/yum.repos.d/mritd.repo << EOF
[mritdrepo]
name=Mritd Repository
baseurl=https://yumrepo.b0.upaiyun.com/centos/7/x86_64
enabled=1
gpgcheck=1
gpgkey=https://mritd.b0.upaiyun.com/keys/rpm.public.key
EOF

# 安装 Consul，请不要在大规模部署时使用此 yum 源，CDN 流量不多请手下留情，
# 如需大规模部署 请使用 yumdonwloader 工具下载 rpm 后手动分发安装
yum install -y consul
```

**5 台机器安装好后修改其中三台为 Server 模式并启动**

``` sh
vim /etc/consul/consul.json

# 配置如下

{
    "datacenter": "dc1",                // 数据中心名称
    "data_dir": "/var/lib/consul",      // Server 节点数据目录
    "log_level": "INFO",                // 日志级别
    "node_name": "docker1.node",        // 当前节点名称
    "server": true,                     // 是否为 Server 模式，false 为 Client 模式
    "ui": true,                         // 是否开启 UI 访问
    "bootstrap_expect": 1,              // 启动时期望的就绪节点，1 代表启动为 bootstrap 模式，等待其他节点加入
    "bind_addr": "192.168.1.11",        // 绑定的 IP
    "client_addr": "192.168.1.11",      // 同时作为 Client 接受请求的绑定 IP
    "retry_join": ["192.168.1.12","192.168.1.13"],  // 尝试加入的其他节点
    "retry_interval": "3s",             // 每次尝试间隔
    "raft_protocol": 3,                 // Raft 协议版本
    "enable_debug": false,              // 是否开启 Debug 模式
    "rejoin_after_leave": true,         // 允许重新加入集群
    "enable_syslog": false              // 是否开启 syslog
}
```

**另外两个节点与以上配置大致相同，差别在于其他两个 Server 节点 `bootstrap_expect` 值为 2，即期望启动时已经有两个节点就绪；然后依次启动三个 Server 节点即可**

``` sh
systemctl start consul
systemctl enable consul
systemctl status consul
```

**此时可访问任意一台 Server 节点的 UI 界面，地址为 `http://serverIP:8500`，截图如下**

![Server Success](https://mritd.b0.upaiyun.com/markdown/t9cxf.jpg)


接下来修改其他两个节点配置，使其作为 Client 加入到集群即可，**注意的是当处于 Client 模式时，`bootstrap_expect` 必须为 0，即关闭状态；具体配置如下**

``` json
{
    "datacenter": "dc1",
    "data_dir": "/var/lib/consul",
    "log_level": "INFO",
    "node_name": "docker4.node",
    "server": false,
    "ui": true,
    "bootstrap_expect": 0,
    "bind_addr": "192.168.1.14",
    "client_addr": "192.168.1.14",
    "retry_join": ["192.168.1.11","192.168.1.12","192.168.1.13"],
    "retry_interval": "3s",
    "raft_protocol": 3,
    "enable_debug": false,
    "rejoin_after_leave": true,
    "enable_syslog": false
}
```

另外一个 Client 配置与以上相同，最终集群成功后如下所示

![Cluster ok](https://mritd.b0.upaiyun.com/markdown/j1zrc.jpg)

![Command Line](https://mritd.b0.upaiyun.com/markdown/kq4cz.jpg)


### 四、其他说明

关于 Consul 的其他各种参数说明，中文版可参考 [Consul集群部署](http://www.10tiao.com/html/357/201705/2247485185/1.html)；这个文章对大体上讲的基本很全了，但是随着版本变化，有些参数还是需要参考一下 [官方配置文档](https://www.consul.io/docs/agent/options.html)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
