---
layout: post
categories: Kubernetes
title: 使用 etcdadm 三分钟搭建 etcd 集群
date: 2020-08-19 13:47:08 +0800
description: 使用 etcdadm 三分钟搭建 etcd 集群
keywords: etcd,etcdadm
catalog: true
multilingual: false
tags: Kubernetes
---

> 本文介绍一下 etcd 宿主机部署的新玩具 etcdadm，类似 kubeadm 一样可以快速的在宿主机搭建 Etcd 集群。

## 一、介绍

在搭建 Kubernetes 集群的过程中首先要搞定 Etcd 集群，虽然说 kubeadm 工具已经提供了默认和 master 节点绑定的 Etcd 集群自动搭建方式，但是我个人一直是手动将 Etcd 集群搭建在宿主机；**因为这个玩意太重要了，毫不夸张的说 kubernetes 所有组件崩溃我们都能在一定时间以后排查问题恢复，但是一旦 Etcd 集群没了那么 Kubernetes 集群也就真没了。**

在很久以前我创建了 [edep](https://github.com/Gozap/edep) 工具来实现 Etcd 集群的辅助部署，再后来由于我们的底层系统偶合了 Ubuntu，所以创建了 [etcd-deb](https://github.com/mritd/etcd-deb) 项目来自动打 deb 包来直接安装；最近逛了一下 Kubernetes 的相关项目，发现跟我的 edep 差不多的项目 [etcdadm](https://github.com/kubernetes-sigs/etcdadm)，试了一下 "真香"。

## 二、安装

[etcdadm](https://github.com/kubernetes-sigs/etcdadm) 项目是使用 go 编写的，所以很明显只有一个二进制下载下来就能用:

``` sh
wget https://github.com/kubernetes-sigs/etcdadm/releases/download/v0.1.3/etcdadm-linux-amd64
chmod +x etcdadm-linux-amd64
```

## 三、使用

### 3.1、启动引导节点

类似 kubeadm 一样，etcdadm 也是先启动第一个节点，然后后续节点直接 join 即可；第一个节点启动只需要执行 `etcdadm init` 命令即可:

``` sh
k1.node ➜  ~ ./etcdadm-linux-amd64 init
INFO[0000] [install] extracting etcd archive /var/cache/etcdadm/etcd/v3.3.8/etcd-v3.3.8-linux-amd64.tar.gz to /tmp/etcd664686683
INFO[0001] [install] verifying etcd 3.3.8 is installed in /opt/bin/
INFO[0001] [certificates] creating PKI assets
INFO[0001] creating a self signed etcd CA certificate and key files
[certificates] Generated ca certificate and key.
INFO[0001] creating a new server certificate and key files for etcd
[certificates] Generated server certificate and key.
[certificates] server serving cert is signed for DNS names [k1.node] and IPs [127.0.0.1 172.16.10.21]
INFO[0002] creating a new certificate and key files for etcd peering
[certificates] Generated peer certificate and key.
[certificates] peer serving cert is signed for DNS names [k1.node] and IPs [172.16.10.21]
INFO[0002] creating a new client certificate for the etcdctl
[certificates] Generated etcdctl-etcd-client certificate and key.
INFO[0002] creating a new client certificate for the apiserver calling etcd
[certificates] Generated apiserver-etcd-client certificate and key.
[certificates] valid certificates and keys now exist in "/etc/etcd/pki"
INFO[0006] [health] Checking local etcd endpoint health
INFO[0006] [health] Local etcd endpoint is healthy
INFO[0006] To add another member to the cluster, copy the CA cert/key to its certificate dir and run:
INFO[0006]      etcdadm join https://172.16.10.21:2379
```

从命令行输出可以看到不同阶段 etcdadm 的相关日志输出；在 `init` 命令时可以指定一些特定参数来覆盖默认行为，比如版本号、安装目录等:

``` sh
k1.node ➜  ~ ./etcdadm-linux-amd64 init --help
Initialize a new etcd cluster

Usage:
  etcdadm init [flags]

Flags:
      --certs-dir string                    certificates directory (default "/etc/etcd/pki")
      --disk-priorities stringArray         Setting etcd disk priority (default [Nice=-10,IOSchedulingClass=best-effort,IOSchedulingPriority=2])
      --download-connect-timeout duration   Maximum time in seconds that you allow the connection to the server to take. (default 10s)
  -h, --help                                help for init
      --install-dir string                  install directory (default "/opt/bin/")
      --name string                         etcd member name
      --release-url string                  URL used to download etcd (default "https://github.com/coreos/etcd/releases/download")
      --server-cert-extra-sans strings      optional extra Subject Alternative Names for the etcd server signing cert, can be multiple comma separated DNS names or IPs
      --skip-hash-check                     Ignore snapshot integrity hash value (required if copied from data directory)
      --snapshot string                     Etcd v3 snapshot file used to initialize member
      --version string                      etcd version (default "3.3.8")

Global Flags:
  -l, --log-level string   set log level for output, permitted values debug, info, warn, error, fatal and panic (default "info")
```

### 3.2、其他节点加入

在首个节点启动完成后，将集群 ca 证书复制到其他节点然后执行 `etcdadm join ENDPOINT_ADDRESS` 即可:

``` sh
# 复制 ca 证书
k1.node ➜  ~ rsync -avR /etc/etcd/pki/ca.* 172.16.10.22:/
root@172.16.10.22's password:
sending incremental file list
/etc/etcd/
/etc/etcd/pki/
/etc/etcd/pki/ca.crt
/etc/etcd/pki/ca.key

sent 2,932 bytes  received 67 bytes  856.86 bytes/sec
total size is 2,684  speedup is 0.89

# 执行 join
k2.node ➜  ~ ./etcdadm-linux-amd64 join https://172.16.10.21:2379
INFO[0000] [certificates] creating PKI assets
INFO[0000] creating a self signed etcd CA certificate and key files
[certificates] Using the existing ca certificate and key.
INFO[0000] creating a new server certificate and key files for etcd
[certificates] Generated server certificate and key.
[certificates] server serving cert is signed for DNS names [k2.node] and IPs [172.16.10.22 127.0.0.1]
INFO[0000] creating a new certificate and key files for etcd peering
[certificates] Generated peer certificate and key.
[certificates] peer serving cert is signed for DNS names [k2.node] and IPs [172.16.10.22]
INFO[0000] creating a new client certificate for the etcdctl
[certificates] Generated etcdctl-etcd-client certificate and key.
INFO[0001] creating a new client certificate for the apiserver calling etcd
[certificates] Generated apiserver-etcd-client certificate and key.
[certificates] valid certificates and keys now exist in "/etc/etcd/pki"
INFO[0001] [membership] Checking if this member was added
INFO[0001] [membership] Member was not added
INFO[0001] Removing existing data dir "/var/lib/etcd"
INFO[0001] [membership] Adding member
INFO[0001] [membership] Checking if member was started
INFO[0001] [membership] Member was not started
INFO[0001] [membership] Removing existing data dir "/var/lib/etcd"
INFO[0001] [install] extracting etcd archive /var/cache/etcdadm/etcd/v3.3.8/etcd-v3.3.8-linux-amd64.tar.gz to /tmp/etcd315786364
INFO[0003] [install] verifying etcd 3.3.8 is installed in /opt/bin/
INFO[0006] [health] Checking local etcd endpoint health
INFO[0006] [health] Local etcd endpoint is healthy
```

## 四、细节分析

### 4.1、默认配置

在目前 etcdadm 尚未支持配置文件，目前所有默认配置存放在 [constants.go](https://github.com/kubernetes-sigs/etcdadm/blob/master/constants/constants.go#L22) 中，这里面包含了默认安装位置、systemd 配置、环境变量配置等，限于篇幅请自行查看代码；下面简单介绍一些一些刚须的配置:

#### 4.1.1、etcdctl

etcdctl 默认安装在 `/opt/bin` 目录下，同时你会发现该目录下还存在一个 `etcdctl.sh` 脚本，**这个脚本将会自动读取 etcdctl 配置文件(`/etc/etcd/etcdctl.env`)，所以推荐使用这个脚本来替代 etcdctl 命令。**

#### 4.1.2、数据目录

默认的数据目录存储在 `/var/lib/etcd` 目录，目前 etcdadm 尚未提供任何可配置方式，当然你可以自己改源码。

#### 4.2.3、配置文件

配置文件总共有两个，一个是 `/etc/etcd/etcdctl.env` 用于 `/opt/bin/etcdctl.sh` 读取；另一个是 `/etc/etcd/etcd.env` 用于 systemd 读取并启动 etcd server。

### 4.2、Join 流程

> 其实很久以前由于我自己部署方式导致了我一直以来理解的一个错误，我一直以为 etcd server 证书要包含所有 server 地址，当然这个想法是怎么来的我也不知道，但是当我看了以下 Join 操作源码以后突然意识到 "为什么要包含所有？包含当前 server 不就行了么。"；当然对于 HTTPS 证书的理解一直是明白的，但是很奇怪就是不知道怎么就产生了这个想法(哈哈，我自己都觉的不可思议)...

- 由于预先拷贝了 ca 证书，所以 join 开始前 etcdadm 使用这个 ca 证书会签发自己需要的所有证书。
- 接下来 etcdadmin 通过 etcdctl-etcd-client 证书创建 client，然后调用 `MemberAdd` 添加新集群
- 最后老套路下载安装+启动就完成了

### 4.3、目前不足

目前 etcdadm 虽然已经基本生产可用，但是仍有些不足的地方:

- 不支持配置文件，很多东西无法定制
- join 加入集群是在内部 api 完成，并未持久化到物理配置文件，后续重建可能忘记节点 ip
- 集群证书目前不支持自动续期，默认证书为 1 年很容易过期
- 下载动作调用了系统命令(curl)依赖性有点强
- 日志格式有点不友好，比如 level 和日期

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
