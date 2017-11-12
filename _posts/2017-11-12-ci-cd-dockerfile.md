---
layout: post
categories: CI/CD
title: CI/CD 之 Dockerfile
date: 2017-11-12 22:46:53 +0800
description: CI/CD 之 Dockerfile
keywords: CI/CD Dockerfile
---

> 最近准备整理一下关于 CI/CD 的相关文档，写一个关于 CI/CD 的系列文章，这篇先从最基本的 Dockerfile 书写开始，本系列文章默认读者已经熟悉 Docker、Kubernetes 相关工具


### 一、基础镜像选择

这里的基础镜像指的是实际项目运行时的基础环境镜像，比如 Java 的 JDK 基础镜像、Nodejs 的基础镜像等；在制作项目的基础镜像时，我个人认为应当考虑一下几点因素:

#### 1.1、可维护性

可维护性应当放在首要位置，如果在制作基础镜像时，选择了一个你根本不熟悉的基础镜像，或者说你完全不知道这个基础镜像里有哪些环境变量、Entrypoint 脚本做了什么时，请果断放弃这个基础镜像，选择一个你自己更加熟悉的基础镜像，不要为以后挖坑；还有就是如果对应的应用已经有官方镜像，那么尽量采用官方的，因为你可以省去维护 **自己造的轮子** 的精力，**除非你对基础镜像制作已经得心应手，否则请不要造轮子**

#### 1.2、稳定性

基础镜像稳定性实际上是个很微妙的话题，因为普遍来说成熟的 Linux 发行版都很稳定；但是对于不同发行版镜像之间还是存在差异的，比如 alpine 的镜像用的是 musl libc，而 debian 用的是 glibc，某些依赖 glibc 的程序可能无法在 alpine 上工作；alpine 版本的 nginx 能使用 http2，debian 版本 nginx 则不行，因为 openssl 版本不同；甚至在相同发行版不同版本之间也会有差异，譬如 openjdk alpine 3.6 版本 java 某些图形库无法工作，在 alpine edge 上安装最新的 openjdk 却没问题等；所以稳定性这个话题对于基础镜像自己来说，他永远稳定，但是对于你的应用来说，则不同基础镜像会产生不同的稳定性；**最后，如果你完全熟悉你的应用，甚至应用层代码也是你写的，那么你可以根据你的习惯和喜好去选择基础镜像，因为你能把控应用运行时依赖；否则的话，请尽量选择 debian 这种比较成熟的发行版作为基础镜像，因为它在普遍上兼容性更好一点；还有尽量不要使用 CentOS 作为基础镜像，因为他的体积将会成为大规模网络分发瓶颈**


#### 1.3、易用性

易用性简单地说就是是否可调试，因为有些极端情况下，并不是应用只要运行起来就没事了；可能出现一些很棘手的问题需要你进入容器进行调试，此时你的镜像易用性就会体现出来；譬如一个 Java 项目你的基础镜像是 JRE，那么 JDK 的调试工具将完全不可用，还有就是如果你的基础镜像选择了 alpine，那么它默认没有 bash，可能你的脚本无法在里面工作；**所有在选择基础镜像的时候最好也考虑一下未来极端情况的可调试性**


### 二、格式化及注意事项

#### 2.1、书写格式

Dockerfile 类似一堆 shell 命令的堆砌，实际上在构建阶段也可以简单的看做是一个 shell 脚本；但是为了更高效的利用缓存层，通常都会在一个 RUN 命令中连续书写大量的脚本命令，这时候一个良好的书写格式可以使 Dockerfile 看起来更加清晰易懂，也方便以后维护；我个人比较推崇的格式是按照 [nginx-alpine官方 Dockerfile](https://github.com/nginxinc/docker-nginx/blob/master/mainline/alpine/Dockerfile) 的样式来书写，这个 Dockerfile 大致包括了以下规则:

- 换行以 `&&` 开头保持每行对齐，看起来干净又舒服
- 安装大量软件包时，每个包一行并添加换行符，虽然会造成很多行，但是看起来很清晰；也可根据实际需要增加每行软件包个数，但是建议不要超过 5 个
- configure 的配置尽量放在统一的变量里，并做好合理换行，方便以后集中化修改
- 注释同样和对应命令对齐，并保持单行长度不超出视野，即不能造成拉动滚动条才能看完你的注释
- alpine 作为基础镜像的话，必要时可以使用 scanelf 来减少安装依赖

除了以上规则，说下我个人的一些小习惯，仅供参考:

- 当需要编译时，尽量避免多次 `cd` 目录，必须进入目录编译时可以开启子 shell 使其完成后还停留但在当前目录，避免 `cd` 进去再 `cd` 回来，如

``` sh
cd xxxx \
&& ./configure \
&& make \
&& make install \
&& cd ../
```
可以变为

``` sh
(cd xxx \
&& ./configure \
&& make \
&& make install)
```

- 同样意义的操作统一放在相邻行处理，比如镜像需要安装两个软件，做两次 `wget`，那么没必要安装完一个删除一个安装包，可以在最后统一的进行清理动作，简而言之是 **合并具有相同目的的命令**
- 尽量使用网络资源，也就是说尽量不要在当前目录下放置那种二进制文件，然后进行 `ADD`/`COPY` 操作，因为一般 Dockerfile 都是存放到 git 仓库的，同目录下的二进制变动会给 git 仓库带来很大负担
- 调整好镜像时区，最好内置一下 bash，可能以后临时进入容器会处理一些东西
- `FROM` 时指定具体的版本号，防止后续升级或者更换主机 build 造成不可预知的结果

#### 2.2、合理利用缓存

Docker 在 build 或者说是拉取镜像时是以层为单位作为缓存的；通俗的讲，一个 Dockerfile 命令就会形成一个镜像层(不绝对)，尤其是 `RUN` 命令形成的镜像层可能会很大；此时应当合理组织 Dockerfile，以便每次拉取或者 build 时高效的利用缓存层

- 重复 build 的缓存利用

Docker 在进行 build 操作时，对于同一个 Dockerfile 来说，**只要执行过一次 build，那么下次 build 将从命令更改处开始**；简单的例子如下

``` sh
FROM alpine:3.6

COPY test.jar /test.jar

RUN apk add openjdk8 --no-cache

CMD ["java","-jar","/test.tar"]
```

假设我们的项目发布物为 `test.jar`，那么以上 Dockerfile 放到 CI 里每次 build 都会相当慢，原因就是 **每次更改的发布物为 `test.jar`，那么也就是相当于每次 build 失效位置从 `COPY` 命令开始，这将导致下面的 `RUN` 命令每次都会不走缓存重复执行，当 `RUN` 命令涉及网络下载等复杂动作时这会极大拖慢 build 进度**，解决方案很简单，移动一下 `COPY` 命令即可

``` sh
FROM alpine:3.6

RUN apk add openjdk8 --no-cache

COPY test.jar /test.jar

CMD ["java","-jar","/test.tar"]
```

此时每次 build 失效位置仍然是 `COPY` 命令，但是上面的 `RUN` 命令层已经被 build 过，而且无任何改变，那么每次 build 时 `RUN` 命令都会命中缓存层从而秒过

- 多次拉取的缓存利用

同上面的 build 一个原理，在 Docker 进行 pull 操作时，也是按照镜像层来进行缓存；当项目进行更新版本，那么只要当前主机 pull 过一次上一个版本的项目，那么下一次将会直接 pull 变更的层，也就是说上面安装 openjdk 的层将会复用；这种情况为了看起来清晰一点也可以将 Dockerfile 拆分成两个

**OpenJDK8 base**

``` sh
FROM alpine:3.6

RUN RUN apk add openjdk8 --no-cache
```

**Java Web image**

``` sh
FROM xxx.com/base/openjdk8

COPY test.jar /test.jar

CMD ["java","-jar","/test.tar"]
```

### 三、镜像安全

#### 3.1、用户切换

当我们不在 Dockerfile 中指定内部用户时，那么默认以 root 用户运行；由于 Linux 系统权限判定是根据 UID、GID 来进行的，也就是说 **容器里面的 root 用户有权限访问宿主机 root 用户的东西；所以一旦挂载错误(比如将 `/root/.ssh` 目录挂载进去)，并且里面的用户具有高权限那么就很危险**；通常习惯是遵从最小权限原则，也就是说尽量保证容器里的程序以低权限运行，此时可以在 Dockerfile 中通过 `USER` 命令指定后续运行命令所使用的账户，通过 `WORKDIR` 指定后续命令在那个目录下执行

``` sh
FROM alpine:3.6

RUN apk add openjdk8 --no-cache

COPY test.jar /test.jar

USER testuser:testuser

WORKDIR /tmp

CMD ["java","-jar","/test.tar"]
```

有时直接使用 `USER` 指令来切换用户并不算方便，比如你的镜像需要挂载外部存储，如果外部存储中文件权限被意外修改，你的程序接下来可能就会启动失败；此时可以使用一下两个小工具来动态切换用户，巧妙的做法是 **在正式运行程序之前先使用 root 用户进行权限修复，然后使用以下工具切换到具体用户运行**

- [gosu](https://github.com/tianon/gosu) Golang 实现的一个切换用户身份执行其他程序的小工具
- [su-exec](https://github.com/hlovdal/su-exec) C 实现的一个更轻量级的用户切换工具

具体的 Dockerfile 可以参见我写的 elasticsearch 的 [entrypoint 脚本](https://github.com/mritd/dockerfile/blob/master/elasticsearch/docker-entrypoint.sh)

#### 3.2、容器运行时

并不是每个容器都一定能切换到低权限用户来运行的，可能某些程序就希望在 root 下运行，此时一定要确认好容器是否需要 **特权模式** 运行；因为一旦开启了特权模式运行的容器将有能力修改宿主机内核参数等重要设置；具体的 Docker 容器运行设置前请参考 [官方文档](https://docs.docker.com/engine/reference/run/#runtime-privilege-and-linux-capabilities)


关于 Dockerfile 方面暂时总结出这些，可能也会有遗漏，待后续补充吧；同时欢迎各位提出相关修改意见 😊


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
