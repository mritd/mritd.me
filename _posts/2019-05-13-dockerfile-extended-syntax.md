---
layout: post
categories: Docker
title: Dockerfile 目前可扩展的语法
date: 2019-05-13 22:57:07 +0800
description: Dockerfile 目前可扩展的语法
keywords: dockerfile,multi-stage,buildkit
catalog: true
multilingual: false
tags: Docker
---

> 最近在调整公司项目的 CI，目前主要使用 GitLab CI，在尝试多阶段构建中踩了点坑，然后发现了一些有意思的玩意

本文参考:

- [Dockerfile frontend experimental syntaxes](https://github.com/moby/buildkit/blob/master/frontend/dockerfile/docs/experimental.md)
- [Advanced multi-stage build patterns](https://medium.com/@tonistiigi/advanced-multi-stage-build-patterns-6f741b852fae)
- [docker build Document](https://docs.docker.com/engine/reference/commandline/build/)

## 一、起因

公司目前主要使用 GitLab CI 作为主力 CI 构建工具，而且由于机器有限，我们对一些包管理器的本地 cache 直接持久化到了本机；比如 maven 的 `.m2` 目录，nodejs 的 `.npm` 目录等；虽然我们创建了对应的私服，但是在 build 时毕竟会下载，所以当时索性调整 GitLab Runner 在每个由 GitLab Runner 启动的容器中挂载这些缓存目录(GitLab CI 在 build 时会新启动容器运行 build 任务)；今天调整 nodejs 项目浪了一下，直接采用 Dockerfile 的 multi-stage build 功能进行 "Build => Package(docker image)" 的实现，基本 Dockerfile 如下

``` sh
FROM gozap/build as builder

COPY . /xxxx

WORKDIR /xxxx

RUN source ~/.bashrc \
    && cnpm install \
    && cnpm run build

FROM gozap/nginx-react:v1.0.0

LABEL maintainer="mritd <mritd@linux.com>"

COPY --from=builder /xxxx/public /usr/share/nginx/html

EXPOSE 80

STOPSIGNAL SIGTERM

CMD ["nginx", "-g", "daemon off;"]
```

本来这个 `cnpm` 命令是带有 cache 的([见这里](https://github.com/Gozap/dockerfile/blob/master/build/cnpm))，不过运行完 build 以后发现很慢，检查宿主机 cache 目录发现根本没有 cache...然后突然感觉

![事情并没有这么简单](https://cdn.oss.link/markdown/6ieh4.jpg)

仔细想想，情况应该是这样事儿的...

``` sh
+------------+                +-------------+            +----------------+
|            |                |             |            |                |
|            |                |    build    |            |   Multi-stage  |
|   Runner   +--------------->+  conatiner  +----------->+     Build      |
|            |                |             |            |                |
|            |                |             |            |                |
+------------+                +------+------+            +----------------+
                                     ^
                                     |
                                     |
                                     |
                                     |
                              +------+------+
                              |             |
                              |    Cache    |
                              |             |
                              +-------------+

```

![挂载不管用](https://cdn.oss.link/markdown/9ov8m.jpg)

后来经过查阅文档，发现 Dockerfile 是有扩展语法的(当然最终我还是没用)，具体请见~~下篇文章~~(我怕被打死)下面，**先说好，下面的内容无法完美的解决上面的问题，目前只是支持了一部分功能，当然未来很可能支持类似 `IF ELSE` 语法、直接挂载宿主机目录等功能**

## 二、开启 Dockerfile 扩展语法

### 2.1、开启实验性功能

目前这个扩展语法还处于实验性功能，所以需要配置 dockerd 守护进程，修改如下

``` sh
ExecStart=/usr/bin/dockerd  -H unix:// \
                            --init \
                            --live-restore \
                            --data-root=/data/docker \
                            --experimental \
                            --log-driver json-file \
                            --log-opt max-size=30m \
                            --log-opt max-file=3
```

主要是 `--experimental` 参数，参考[官方文档](https://docs.docker.com/engine/reference/commandline/dockerd/#description)；**同时在 build 前声明 `export DOCKER_BUILDKIT=1` 变量**

### 2.2、修改 Dockerfile

开启实验性功能后，只需要在 Dockerfile 头部增加 `# syntax=docker/dockerfile:experimental` 既可；为了保证稳定性，你也可以指定具体的版本号，类似这样

``` sh
# syntax=docker/dockerfile:1.1.1-experimental
FROM tomcat
```

### 2.3、可用的扩展语法

- `RUN --mount=type=bind`

这个是默认的挂载模式，这个允许将上下文或者镜像以可都可写/只读模式挂载到 build 容器中，可选参数如下(不翻译了)

|Option               |Description|
|---------------------|-----------|
|`target` (required)  | Mount path.|
|`source`             | Source path in the `from`. Defaults to the root of the `from`.|
|`from`               | Build stage or image name for the root of the source. Defaults to the build context.|
|`rw`,`readwrite`     | Allow writes on the mount. Written data will be discarded.|

- `RUN --mount=type=cache`

专用于作为 cache 的挂载位置，一般用于 cache 包管理器的下载等

|Option               |Description|
|---------------------|-----------|
|`id`                 | Optional ID to identify separate/different caches|
|`target` (required)  | Mount path.|
|`ro`,`readonly`      | Read-only if set.|
|`sharing`            | One of `shared`, `private`, or `locked`. Defaults to `shared`. A `shared` cache mount can be used concurrently by multiple writers. `private` creates a new mount if there are multiple writers. `locked` pauses the second writer until the first one releases the mount.|
|`from`               | Build stage to use as a base of the cache mount. Defaults to empty directory.|
|`source`             | Subpath in the `from` to mount. Defaults to the root of the `from`.|

**Example: cache Go packages**

``` sh
# syntax = docker/dockerfile:experimental
FROM golang
...
RUN --mount=type=cache,target=/root/.cache/go-build go build ...
```

**Example: cache apt packages**

``` sh
# syntax = docker/dockerfile:experimental
FROM ubuntu
RUN rm -f /etc/apt/apt.conf.d/docker-clean; echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/keep-cache
RUN --mount=type=cache,target=/var/cache/apt --mount=type=cache,target=/var/lib/apt \
  apt update && apt install -y gcc
```

- `RUN --mount=type=tmpfs`

专用于挂载 tmpfs 的选项

|Option               |Description|
|---------------------|-----------|
|`target` (required)  | Mount path.|

- `RUN --mount=type=secret`

这个类似 k8s 的 secret，用来挂载一些不想打入镜像，但是构建时想使用的密钥等，例如 docker 的 `config.json`，S3 的 `credentials`

|Option               |Description|
|---------------------|-----------|
|`id`                 | ID of the secret. Defaults to basename of the target path.|
|`target`             | Mount path. Defaults to `/run/secrets/` + `id`.|
|`required`           | If set to `true`, the instruction errors out when the secret is unavailable. Defaults to `false`.|
|`mode`               | File mode for secret file in octal. Default 0400.|
|`uid`                | User ID for secret file. Default 0.|
|`gid`                | Group ID for secret file. Default 0.|

**Example: access to S3**

``` sh
# syntax = docker/dockerfile:experimental
FROM python:3
RUN pip install awscli
RUN --mount=type=secret,id=aws,target=/root/.aws/credentials aws s3 cp s3://... ...
```

**注意: `buildctl` 是 BuildKit 的命令，你要测试的话自己换成 `docker build` 相关参数**

```console
$ buildctl build --frontend=dockerfile.v0 --local context=. --local dockerfile=. \
  --secret id=aws,src=$HOME/.aws/credentials
```

- `RUN --mount=type=ssh`

允许 build 容器通过 SSH agent 访问 SSH key，并且支持 `passphrases`

|Option               |Description|
|---------------------|-----------|
|`id`                 | ID of SSH agent socket or key. Defaults to "default".|
|`target`             | SSH agent socket path. Defaults to `/run/buildkit/ssh_agent.${N}`.|
|`required`           | If set to `true`, the instruction errors out when the key is unavailable. Defaults to `false`.|
|`mode`               | File mode for socket in octal. Default 0600.|
|`uid`                | User ID for socket. Default 0.|
|`gid`                | Group ID for socket. Default 0.|

**Example: access to Gitlab**

``` sh
# syntax = docker/dockerfile:experimental
FROM alpine
RUN apk add --no-cache openssh-client
RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan gitlab.com >> ~/.ssh/known_hosts
RUN --mount=type=ssh ssh -q -T git@gitlab.com 2>&1 | tee /hello
# "Welcome to GitLab, @GITLAB_USERNAME_ASSOCIATED_WITH_SSHKEY" should be printed here
# with the type of build progress is defined as `plain`.
```

``` sh
$ eval $(ssh-agent)
$ ssh-add ~/.ssh/id_rsa
(Input your passphrase here)
$ buildctl build --frontend=dockerfile.v0 --local context=. --local dockerfile=. \
  --ssh default=$SSH_AUTH_SOCK
```

你也可以直接使用宿主机目录的 pem 文件，但是带有密码的 pem 目前不支持

**目前根据文档测试，当前的挂载类型比如 `cache` 类型，仅用于 multi-stage 内的挂载，比如你有 2+ 个构建步骤，`cache` 挂载类型能帮你在各个阶段内共享文件；但是它目前无法解决直接将宿主机目录挂载到 multi-stage 的问题(可以采取些曲线救国方案，但是很不优雅)；但是未来还是很有展望的，可以关注一下**



转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
