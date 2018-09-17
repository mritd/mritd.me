---
layout: post
categories: Kubernetes
title: Google container registry 同步
date: 2018-09-17 21:19:40 +0800
description: Google container registry 同步
keywords: gcr.io,kubernetes,docker
catalog: true
multilingual: false
tags: Kubernetes Docker
---

## 一、起因

玩 Kubenretes 的基本都很清楚，Kubernetes 很多组件的镜像全部托管在 `gcr.io` 这个域名下(现在换成了 `k8s.gcr.io`)；由于众所周知的原因，这个网站在国内是不可达的；当时由于 Docker Hub 提供了 `Auto Build` 功能，机智的想到一个解决办法；就是利用 Docker Hub 的 `Auto Build`，创建只有一行的 Dockerfile，里面就一句 `FROM gcr.io/xxxx`，然后让 Docker Hub 帮你构建完成后拉取即可

这种套路的基本方案就是利用一个第三方公共仓库，这个仓库可以访问不可达的 `gcr.io`，然后生成镜像，我们再从这个仓库 pull 即可；为此我创建了一个 Github 仓库([docker-library](https://github.com/mritd/docker-library))；时隔这么久以后，我猜想大家都已经有了这种自己的仓库...不过最近发现这个仓库仍然在有人 fork...

为了一劳永逸的解决这个问题，只能撸点代码解决这个问题了

## 二、仓库使用

为了解决上述问题，我写了一个 [gcrsync](https://github.com/mritd/gcrsync) 工具，并且借助 [Travis CI](https://travis-ci.org/mritd/gcrsync) 让其每天自动运行，将所有用得到的 `gcr.io` 下的镜像同步到了 Docker Hub

**目前对于一个 `gcr.io` 下的镜像，可以直接替换为 `gcrxio` 用户名，然后从 Docker Hub 直接拉取**，以下为一个示例:

``` sh
# 原始命令
docker pull k8s.gcr.io/kubernetes-dashboard-amd64:v1.10.0

# 使用同步仓库
docker pull gcrxio/kubernetes-dashboard-amd64:v1.10.0
```

## 三、同步细节说明

为了保证同步镜像的安全性，同步工具已经开源在 [gcrsync](https://github.com/mritd/gcrsync) 仓库，同步细节如下:

- 工具每天由 [Travis CI](https://travis-ci.org/mritd/gcrsync) 自动进行一次 build，然后进行推送
- 工具每次推送前首先 clone 元数据仓库 [gcr](https://github.com/mritd/gcr)
- 工具每次推送首先获取 `gcr.io` 指定 `namespace` 下的所有镜像(`namesapce` 由 [.travis.yml](https://github.com/mritd/gcrsync/blob/master/.travis.yml) `script` 段定义)
- 获取 `gcr.io` 镜像后，再读取元数据仓库([gcr](https://github.com/mritd/gcr)) 中与 `namesapce` 同名文件(实际是个 json)
- 接着对比双方差异，得出需要同步的镜像
- 最后通过 API 调用本地的 docker 进行 `pull`、`tag`、`push` 操作，完成镜像推送
- 所有镜像推送成功后，更新元数据仓库内 `namespace` 对应的 json 文件，最后在生成 [CHANGELOG](https://github.com/mritd/gcr/blob/master/CHANGELOG.md)，执行 `git push` 到远程元数据仓库

综上所述，如果想得知**具体 `gcrxio` 用户下都有那些镜像，可直接访问 [gcr](https://github.com/mritd/gcr) 元数据仓库，查看对应 `namesapce` 同名的 json 文件即可；每天增量同步的信息会追加到 [gcr](https://github.com/mritd/gcr) 仓库的 `CHANGELOG.md` 文件中**

## 四、gcrsync

为方便审查镜像安全性，以下为 [gcrsync](https://github.com/mritd/gcrsync) 工具的代码简介，代码仓库文件如下:

``` sh
➜  gcrsync git:(master) tree -I vendor
.
├── CHANGELOG.md
├── Gopkg.lock
├── Gopkg.toml
├── LICENSE
├── README.md
├── cmd
│   ├── compare.go
│   ├── monitor.go
│   ├── root.go
│   ├── sync.go
│   └── test.go
├── dist
│   ├── gcrsync_darwin_amd64
│   ├── gcrsync_linux_386
│   └── gcrsync_linux_amd64
├── main.go
└── pkg
    ├── gcrsync
    │   ├── docker.go
    │   ├── gcr.go
    │   ├── git.go
    │   ├── registry.go
    │   └── sync.go
    └── utils
        └── common.go
```

cmd 目录下为标准的 `cobra` 框架生成的子命令文件，其中每个命令包含了对应的 flag 设置，如 `namesapce`、`proxy` 等；`pkg/gcrsync` 目录下的文件为核心代码:

- `docker.go` 包含了对本地 docker daemon API 调用，包括 `pull`、`tag`、`push` 操作
- `gcr.go` 包含了对 `gcr.io` 指定 `namespace` 下镜像列表获取操作
- `registry.go` 包含了对 Docker Hub 下指定用户(默认 `gcrxio`)的镜像列表获取操作(其主要用于首次执行 `compare` 命令生成 json 文件)
- `sync.go` 为主要的程序入口，其中包含了对其他文件内方法的调用，设置并发池等

## 五、其他说明

该仓库不保证镜像实时同步，默认每天同步一次(由 [Travis CI](https://travis-ci.org/mritd/gcrsync) 执行)，如有特殊需求，如增加 `namesapce` 等请开启 issue；最后，请不要再 fork [docker-library](https://github.com/mritd/docker-library) 这个仓库了

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
