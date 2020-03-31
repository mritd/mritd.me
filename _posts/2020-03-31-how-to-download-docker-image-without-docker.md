---
layout: post
categories: Docker
title: 如何不通过 docker 下载 docker image
date: 2020-03-31 23:07:34 +0800
description: 如何不通过 docker 下载 docker image
keywords: docker,skopeo
catalog: true
multilingual: false
tags: Docker
---

> 这是一个比较骚的动作，但是事实上确实有这个需求，折腾半天找工具看源码，这里记录一下(不想看源码分析啥的请直接跳转到第五部份)。

## 一、起因

由于最近某个爬虫业务需要抓取微信公众号的一些文章，某开发小伙伴想到了通过启动安卓虚拟机然后抓包的方式实现；经过几番寻找最终我们选择采用 docker 的方式启动安卓虚拟机，docker 里安卓虚拟机比较成熟的项目我们找到了 [https://github.com/budtmo/docker-android](https://github.com/budtmo/docker-android) 这个项目；但是由于众所周知的原因这个 2G+ 的镜像国内拉取是非常慢的，于是我想到了通过国外 VPS 拉取然后 scp 回来... 由于贫穷的原因，当我实际操作的时候遇到了比较尴尬的问题: **VPS 磁盘空间 25G，镜像拉取后解压接近 10G，我需要 `docker save` 成 tar 包再进行打包成 `tar.gz` 格式 scp 回来，这个时候空间不够用了...**所以我当时就在想有没有办法让 docker daemon 拉取镜像时不解压？或者说自己通过 HTTP 下载镜像直接存储为 tar？

## 二、尝试造轮子

当出现了上面的问题后，我第一反应就是:

- 1、docker 拆分为 moby
- 2、moby 模块化，大部份开源到 [containers](https://github.com/containers)
- 3、[containers/image](https://github.com/containers/image) 项目是镜像部份源码
- 4、看 [containers/image](https://github.com/containers/image) 源码造轮子
- 5、不确定是否需要 [containers/storage](https://github.com/containers/storage) 做存储

## 三、猜测源码

当我查看 [containers/image](https://github.com/containers/image) README 文档时发现其提到了 [skopeo](https://github.com/containers/skopeo) 项目，并且很明确的说了

> The containers/image project is only a library with no user interface; you can either incorporate it into your Go programs, or use the skopeo tool:
The skopeo tool uses the containers/image library and takes advantage of many of its features, e.g. skopeo copy exposes the containers/image/copy.Image functionality.

那么也就是说镜像下载这块很大可能应该调用 `containers/image/copy.Image` 完成，随即就看了下源码文档

![](https://cdn.oss.link/markdown/tv7iy.png)

很明显，`types.ImageReference`、`Options` 里面的属性啥的我完全看不懂... 😂😂😂

## 四、看 skopeo 源码

当 [containers/image](https://github.com/containers/image) 源码看不懂时，突然想到 [skopeo](https://github.com/containers/skopeo) 调用的是这个玩意，那么依葫芦画瓢看 [skopeo](https://github.com/containers/skopeo) 源码应该能行；接下来常规操作 clone skopeo 源码然后编译运行测试；编译后 skopeo 支持命令如下

```sh
NAME:
   skopeo - Various operations with container images and container image registries

USAGE:
   skopeo [global options] command [command options] [arguments...]

VERSION:
   0.1.42-dev commit: 018a0108b103341526b41289c434b59d65783f6f

COMMANDS:
   copy               Copy an IMAGE-NAME from one location to another
   inspect            Inspect image IMAGE-NAME
   delete             Delete image IMAGE-NAME
   manifest-digest    Compute a manifest digest of a file
   sync               Synchronize one or more images from one location to another
   standalone-sign    Create a signature using local files
   standalone-verify  Verify a signature using local files
   list-tags          List tags in the transport/repository specified by the REPOSITORY-NAME
   help, h            Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --debug                     enable debug output
   --policy value              Path to a trust policy file
   --insecure-policy           run the tool without any policy check
   --registries.d DIR          use registry configuration files in DIR (e.g. for container signature storage)
   --override-arch ARCH        use ARCH instead of the architecture of the machine for choosing images
   --override-os OS            use OS instead of the running OS for choosing images
   --override-variant VARIANT  use VARIANT instead of the running architecture variant for choosing images
   --command-timeout value     timeout for the command execution (default: 0s)
   --help, -h                  show help
   --version, -v               print the version
```

**我掐指一算调用 copy 命令应该是我要找的那个它**，所以常规操作打开源码直接看

![copy_cmd](https://cdn.oss.link/markdown/urn3l.png)

通过继续追踪 `alltransports.ParseImageName` 方法最终可以得知 copy 命令的 `SOURCE-IMAGE` 和 `DESTINATION-IMAGE` 都支持哪些写法

![tp_register](https://cdn.oss.link/markdown/ush4t.png)

**每一个 Transport 的实现都提供了 Name 方法，其名称即为 src 或 dest 镜像名称的前缀，例如 `docker://nginx:1.17.6`**

![tp_docker](https://cdn.oss.link/markdown/7fpap.png)

**经过测试不同的 Transport 格式并不完全一致(具体看源码)，比如 `docker://nginx:1.17.6` 和 `dir:/tmp/nginx`；同时这些 Transport 并非完全都适用与 src 与 dest，比如 `tarball:/tmp/nginx.tar` 支持 src 而不支持 dest；**其判断核心依据为 `ImageReference.NewImageSource` 和 `ImageReference.NewImageDestination` 方法实现是否返回 error

![NewImageDestination](https://cdn.oss.link/markdown/jb087.png)

当我看了一会各种 Transport 源码后我发现一件事: **这特么不就是我要造的轮子么！😱😱😱**

## 五、skopeo copy 使用

### 5.1、不借助 docker 下载镜像

```sh
skopeo --insecure-policy copy docker://nginx:1.17.6 docker-archive:/tmp/nginx.tar
```

`--insecure-policy` 选项用于忽略安全策略配置文件，该命令将会直接通过 http 下载目标镜像并存储为 `/tmp/nginx.tar`，此文件可以直接通过 `docker load` 命令导入

### 5.2、从 docker daemon 导出镜像

```sh
skopeo --insecure-policy copy docker-daemon:nginx:1.17.6 docker-archive:/tmp/nginx.tar
```

该命令将会从 docker daemon 导出镜像到 `/tmp/nginx.tar`；为什么不用 `docker save`？因为我是偷懒 dest 也是 docker-archive，实际上 skopeo 可以导出为其他格式比如 `oci`、`oci-archive`、`ostree` 等

### 5.3、其他命令

skopeo 还有一些其他的实用命令，比如 `sync` 可以在两个位置之间同步镜像(😂早知道我还写个鸡儿 gcrsync)，`inspect` 可以查看镜像信息等，迫于本人太懒，剩下的请自行查阅文档、`--help` 以及源码(没错，整篇文章都没写 skopeo 怎么安装)。



转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
