---
layout: post
categories: Docker
title: 个人维护的 Docker 加速仓库
date: 2017-03-21 22:38:03 +0800
description: 个人维护的 Docker 加速仓库
keywords: Docker mirror registry
---

> 最近看着很多人下载镜像都很费劲，可能是网络环境越来越坑的原因吧；这里开放一个个人维护的 Docker 加速仓库，帮助扶墙下载 Docker 相关镜像

**该镜像基于 Docker 官方 Registry，在其基础上套了一个梯子，可以实现反代主流的三大墙外仓库(Docker Hub、Gcr.io、quay.io)；理论速度可以达到 10MB/S 的加速效果，使用方式如下**

### 一、确定要反代的仓库

首先确定你要反代的墙外仓库，目前仓库支持 `https://gcr.io`、`https://quay.io`、`https://registry-1.docker.io(Docker Hub)`；以 `gcr.io` 为例，启动本地私服并设置需要反代的仓库地址，如下：

``` sh
docker run -dt --privileged --restart always --name registry-mirror -p 5000:5000 mritd/registry-mirror https://gcr.io
```

**此命令执行后将在本地启动一个带有梯子的 registry，并且私服默认设置的反代地址为 `https://gcr.io`；启动成功日志如下，如出现错误可能由于网络原因，请重新尝试几次(几率很小)；默认镜像已经上传了 Docker Hub，如果无法下载请访问 [百度云](https://pan.baidu.com/s/1o7Wye8M)**

![start up](https://mritd.b0.upaiyun.com/markdown/gwfeo.jpg)

### 二、设置 docker 非安全仓库

docker 默认情况下对于 http 类型的私服是不信任的，如果有证书可以在外面套个 nginx；如果没有则需要修改 docker 启动参数，增加非安全仓库设置(CentOS)

``` sh
vim /usr/lib/systemd/system/docker.service

# ExecStart 增加 --insecure-registry 选项，
# 地址为刚刚启动的反代仓库地址
ExecStart=/usr/bin/dockerd --insecure-registry 192.168.1.110:5000
```

然后 reload systemd service 配置，重启 docker

``` sh
systemctl daemon-reload
systemctl restart docker
```

### 三、使用反代私服下载镜像

重启后就可以通过该私服下载 gcr.io 相关镜像，以下以下载 `gcr.io/google_containers/kube-apiserver-amd64:v1.5.4` 镜像为例

``` sh
➜  ~ docker pull 192.168.1.110:5000/google_containers/kube-apiserver-amd64:v1.5.4
v1.5.4: Pulling from google_containers/kube-apiserver-amd64
4b0bc1c4050b: Pull complete
3f39da6bdf32: Pull complete
Digest: sha256:2c27af79f314a9a030b4f3d1787bcd1b931779bcc3d229c7fc3fa83df0bbd7b1
Status: Downloaded newer image for 192.168.1.110:5000/google_containers/kube-apiserver-amd64:v1.5.4
```

最后自己将刚刚下载的镜像 tag 回正常名称即可使用

``` sh
➜  ~ docker tag 192.168.1.110:5000/google_containers/kube-apiserver-amd64:v1.5.4 gcr.io/google_containers/kube-apiserver-amd64:v1.5.4
➜  ~ docker images
REPOSITORY                                                  TAG                 IMAGE ID            CREATED             SIZE
mritd/registry-mirror                                       1.0.0               18312490a135        6 hours ago         120.4 MB
192.168.1.110:5000/google_containers/kube-apiserver-amd64   v1.5.4              b951e253e3cd        13 days ago         125.9 MB
gcr.io/google_containers/kube-apiserver-amd64               v1.5.4              b951e253e3cd        13 days ago         125.9 MB
```

### 四、其他说明(重要)

**由于 docker 在 1.13 版本做了一些变动(没去看)，经测试使用 1.13 以上版本通过该仓库下载 `gcr.io` 镜像会出现多层镜像只能下载一层的问题；所以要使用本仓库必须使用 docker 1.13 以下版本，如 1.12.6；此篇文章发布时，将会弃用原本维护的专用于反代 `gcr.io` 的私服( `mritd/gcr-registry` )；本仓库由个人维护，内置梯子走的是我个人的服务器，所以流量有限(500GB/月)，所以请大家珍惜使用，不要大批量部署时拿来开怼；由于不确定因素太多，所以不承诺永久维护。**

---

**仓库镜像是一个黑盒镜像，担心安全的朋友可以不用，我也不会开放源码(为了防止梯子被滥用)；同时镜像内部也做了处理，防止有心人搞我...希望大家可以利用此仓库将镜像下载下来，然后自己传到百度云等网盘互助分享，随手之劳帮助别人也能减轻服务器压力；同时由于资金有限，如果感觉这个仓库对你有点帮助，欢迎捐助杯咖啡钱**

![alipay](https://mritd.b0.upaiyun.com/markdown/zhifubao.png)


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
