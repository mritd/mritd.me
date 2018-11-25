---
layout: post
categories: Golang Kubenretes
title: 远程 Debug kubeadm
date: 2018-11-25 11:11:28 +0800
description: 远程 Debug kubeadm
keywords: kubeadm,debug
catalog: true
multilingual: false
tags: Golang Kubernetes
---

> 最近在看 kubeadm 的源码，不过有些东西光看代码还是没法太清楚，还是需要实际运行才能看到具体代码怎么跑的，还得打断点 debug；无奈的是本机是 mac，debug 得在 Linux 下，so 研究了一下 remote debug

## 一、环境准备

- GoLand 2018.2.4
- Golang 1.11.2
- delve v1.1.0
- Kubernetest master
- Ubuntu 18.04
- 能够高速访问外网(自行理解)

**这里不会详细写如何安装 Go 开发环境以及 GoLand 安装，本文默认读者已经至少已经对 Go 开发环境以及代码有一定了解；顺便提一下 GoLand，这玩意属于 jetbrains 系列 IDE，在大约 2018.1 版本后在线激活服务器已经全部失效，不过网上还有其他本地离线激活工具，具体请自行 Google，如果后续工资能支撑得起，请补票支持正版(感恩节全家桶半价真香😂)**

### 1.1、获取源码

需要注意的是 Kubernetes 源码虽然托管在 Github，但是在使用 `go get` 的时候要使用 `k8s.io` 域名

``` sh
go get -d k8s.io/kubernetes
```

`go get` 命令是接受标准的 http 代理的，这个源码下载会非常慢，源码大约 1G 左右，所以最好使用加速工具下载

``` sh
➜  ~ which proxy
/usr/local/bin/proxy
➜  ~ cat /usr/local/bin/proxy
#!/bin/bash
http_proxy=http://127.0.0.1:8123 https_proxy=http://127.0.0.1:8123 $*
➜  ~ proxy go get -d k8s.io/kubernetes
```

### 1.2、安装 delve

delve 是一个 Golang 的 debug 工具，有点类似 gdb，不过是专门针对 Golang 的，GoLand 的 debug 实际上就是使用的这个开源工具；为了进行远程 debug，运行 kubeadm 的机器必须安装 delve，从而进行远程连接

``` sh
# 同样这里省略在 Linux 安装 go 环境操作
go get -u github.com/derekparker/delve/cmd/dlv
```

## 二、远程 Debug

### 2.1、重新编译 kubeadm

默认情况下直接编译出的 kubeadm 是无法进行 debug 的，因为 Golang 的编译器会进行编译优化，比如进行内联等；所以要关闭编译优化和内联，方便 debug

``` sh
cd ${GOPATH}/src/k8s.io/kubernetes/cmd/kubeadm
GOOS="linux" GOARCH="amd64" go build -gcflags "all=-N -l"
```

### 2.2、远程运行 kubeadm

将编译好的 kubeadm 复制到远程，并且使用 delve 启动它，此时 delve 会监听 api 端口，GoLand 就可以远程连接过来了

``` sh
dlv --listen=192.168.1.61:2345 --headless=true --api-version=2 exec ./kubeadm init
```

**注意: 要指定需要 debug 的 kubeadm 的子命令，否则可能出现连接上以后 GoLand 无反应的情况**

### 2.3、运行 GoLand

在 GoLand 中打开 kubernetes 源码，在需要 debug 的代码中打上断点，这里以 init 子命令为例

首先新建一个远程 debug configuration

![create configuration](https://mritd.b0.upaiyun.com/markdown/i6oed.png)

名字可以随便写，主要是地址和端口

![conifg delve](https://mritd.b0.upaiyun.com/markdown/rmczj.png)

接下来在目标源码位置打断点，以下为 init 子命令的源码位置

![create breakpoint](https://mritd.b0.upaiyun.com/markdown/ylf97.png)

最后只需要点击 debug 按钮即可

![debug](https://mritd.b0.upaiyun.com/markdown/ns2yw.png)

**在没有运行 GoLand debug 之前，目标机器的实际指令是不会运行的，也就是说在 GoLand 没有连接到远程 delve 启动的 `kubeadm init` 命令之前，`kubeadm init` 并不会真正运行；当点击 GoLand 的终止 debug 按钮后，远程的 delve 也会随之退出**

![stop](https://mritd.b0.upaiyun.com/markdown/lmdke.png)


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
