---
layout: post
categories: Docker
title: ohmydocker 镜像加速
date: 2017-11-14 14:43:30 +0800
description: ohmydocker 镜像加速
keywords: docker 镜像加速
---

> 国外一直有台服务器闲置，准备用来做 Docker 镜像下载加速，写了个小工具打成了镜像放了出来 😀

ohmydocker 镜像基于 `docker:dind`，也就是所谓的 **Dcoker in Docker** 俄罗斯套娃镜像，使用方法如下:

#### 1、启动镜像

镜像启动后相当于镜像里运行了一个 Docker daemon 进程，**Docker in Docker 需要使用 privileged 启动，如果觉得不安全请不要使用本镜像(拒绝喷子)**

``` sh
docker run --privileged -d --name ohmydocker -p 1028:1028 mritd/ohmydocker
```

#### 2、拉取镜像

ohmydocker 启动后将会暴露一个 `1028` 的 docker api 端口(tcp)，此时直接通过该端口连接容器内的 Docker daemon 进行 pull 镜像即可

``` sh
docker -H LOCAL_IP:1028 pull gcr.io/google_containers/kubernetes-dashboard-init-amd64:v1.0.1
```

镜像 pull 完成后会保存在容器里，并不会直接保存到宿主机，所以还要 save 出来

``` sh
docker -H LOCAL_IP:1028 save gcr.io/google_containers/kubernetes-dashboard-init-amd64:v1.0.1 > kubernetes-dashboard-init-amd64.tar
```

镜像 save 成 tar 文件后复制到其他主机进行 load 即可

**如果你感觉该镜像对你有所帮助，欢迎请我喝杯咖啡**

![支付宝](https://mritd.b0.upaiyun.com/markdown/zhifubao.png)


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
