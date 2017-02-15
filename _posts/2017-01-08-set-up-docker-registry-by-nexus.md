---
layout: post
categories: Docker
title: 使用 Nexus 搭建 Docker 仓库
date: 2017-01-08 23:02:29 +0800
description: 使用 Nexus 搭建 Docker 仓库
keywords: Docker Nexus 私服
---

> nexus 最初用于搭建 maven 私服，提供企业级 maven jar 包管理等功能；2.x 后续支持了 npm、rpm 等包管理；最新版本 3.x 开始支持 Docker 仓库，以下为使用 neuxs 撸一个 docker 仓库的教程

### 一、环境准备

初始环境如下

- Centos 7 x86_64
- OpenJDK 8
- Nexus 3.2.0-01

安装 OpenJDK 命令如下

``` sh
yum install java-1.8.0-openjdk -y
```

安装完成后验证是否安装成功

``` sh
➜  ~ java -version
openjdk version "1.8.0_111"
OpenJDK Runtime Environment (build 1.8.0_111-b15)
OpenJDK 64-Bit Server VM (build 25.111-b15, mixed mode)
```

下载 neuxs3 安装包并解压

``` sh
wget --no-check-certificate https://download.sonatype.com/nexus/3/nexus-3.2.0-01-unix.tar.gz
tar -zxvf nexus-3.2.0-01-unix.tar.gz
```

### 二、安装 nexus

首先将 nexus 移动到任意位置

``` sh
 mv nexus-3.2.0-01 /usr/local
```

创建 nexus 用户

``` sh
adduser -r -s /sbin/nologin -d /data/nexus-data nexus
```

**默认 nexus 运行后会在同级目录下创建一个 `sonatype-work` 工作目录，并将其数据保存在此目录中，所以为了数据持久化先手动创建并设置其数据存储位置**

``` sh
# 创建基本目录结构
mkdir -p /usr/local/sonatype-work
# 创建建数据目录
mkdir -p /data/nexus-data/{etc,log,tmp}
# 将数据目录软连接到工作目录
ln -s /data/nexus-data /usr/local/sonatype-work/nexus3
# 更新所有目录权限
chmod -R 755 /usr/local/{sonatype-work,nexus-3.2.0-01} /data/nexus-data
chown -R nexus:nexus /usr/local/{sonatype-work,nexus-3.2.0-01} /data/nexus-data
```

最后启动 nexus 访问 8081 端口即可

``` sh
# 以前台方式运行
sudo -u nexus /usr/local/nexus-3.2.0-01/bin/nexus run
# 后台运行
sudo -u nexus /usr/local/nexus-3.2.0-01/bin/nexus start
```

默认账户 `admin` 密码 `admin123`，登录如下

![nexus_homepage](https://mritd.b0.upaiyun.com/markdown/sb9dw.jpg)

### 三、创建 docker 仓库

在设置 `Repositories` 选项卡中中选择 `Create repository`

![Create repository](https://mritd.b0.upaiyun.com/markdown/m7m53.jpg)

仓库类型有很多，docker 相关总共有三种类型，其秉承 maven 私服的概念

![repository type](https://mritd.b0.upaiyun.com/markdown/pm0r8.jpg)

- hosted: 本地存储，即同 docker 官方仓库一样提供本地私服功能
- proxy: 提供代理其他仓库的类型，如 docker 中央仓库
- group: 组类型，实质作用是组合多个仓库为一个地址

#### 3.1、创建一个私服

选择 `hosted` 类型仓库，然后输入一个仓库名，**并勾选 HTTP 选项，端口任意即可(下面截图失误，不补了)**

![create hosted repository](https://mritd.b0.upaiyun.com/markdown/972cl.jpg)

#### 3.2、测试私服

创建好以后更改 docker 参数，测试即可

``` sh
# 增加非安全仓库
vim /usr/lib/systemd/system/docker.service
# 在 ExecStart 后面增加(这里改了 host，上面端口用的 8800)
--insecure-registry registry.com:8800
# 重启 docker
systemctl daemon-reload
systemctl restart docker
```

测试 push 和 pull 镜像

``` sh
➜  ~ docker tag mritd/alpine registry.com:8800/alpine
➜  ~ docker push registry.com:8800/alpine
The push refers to a repository [registry.com:8800/alpine]
754684812d65: Pushed
60ab55d3379d: Pushed
latest: digest: sha256:28f397aca53eb3e8ea1627f4af9c262fca7db17f0c6db492b53adc7bca7d0f91 size: 739
➜  ~ docker rmi registry.com:8800/alpine
Untagged: registry.com:8800/alpine:latest
Untagged: registry.com:8800/alpine@sha256:28f397aca53eb3e8ea1627f4af9c262fca7db17f0c6db492b53adc7bca7d0f91
➜  ~ docker rmi mritd/alpine
Untagged: mritd/alpine:latest
Untagged: mritd/alpine@sha256:28f397aca53eb3e8ea1627f4af9c262fca7db17f0c6db492b53adc7bca7d0f91
Deleted: sha256:090c790ee6f28f495d92d5be43641573b0d1b5502b35f7662d88cdbf8d548afd
Deleted: sha256:378e2b887fcdffcbd113a7cf6f97e9f8a58851b0a205b31a93acdb887912850d
➜  ~ docker pull registry.com:8800/alpine
Using default tag: latest
latest: Pulling from alpine

0a8490d0dfd3: Already exists
8fb018fb4173: Pull complete
Digest: sha256:28f397aca53eb3e8ea1627f4af9c262fca7db17f0c6db492b53adc7bca7d0f91
Status: Downloaded newer image for registry.com:8800/alpine:latest
```

#### 3.2、创建代理仓库

代理仓库参考官方文档 [点这里](http://books.sonatype.com/nexus-book/reference3/docker.html#docker-introduction)，本人不才....没成功，有爱探索的可以尝试一下，如果成功可以探讨一下.....个人怀疑是 index 有问题
 
 根据官方文档的这段提示
 
 > Just to recap, in order to configure a proxy for Docker Hub you configure the Remote Storage URL to https://registry-1.docker.io, enable Docker V1 API support and for the choice of Docker Index select the Use Docker Hub option.
 
创建仓库类型选择 `proxy`，Remote storage 填写 `https://registry-1.docker.io`，Docker index 选择 `Use Docker Hub`，然后从 代理仓库地址 pull 就可以，但是本人百试不成功，截图如下

![proxy registry](https://mritd.b0.upaiyun.com/markdown/q350r.jpg)

#### 3.4、创建 group 仓库

group 不提供具体存储服务，其主要作用就是类似一个前端反代，可以把多个仓库(比如 hosted 私服和 proxy)组合成一个地址提供访问，创建方法基本相同，主要是添加多个 hosted 或者 proxy 类型的其他仓库即可，这里不再详细阐述，截图如下

![group registry](https://mritd.b0.upaiyun.com/markdown/2q1qv.jpg)

### 四、其他相关

由于 nexus 在 maven jar 管理方面已经是很成熟的产品，增加了 docker 等支持以后基本思想没有太大变化，所以关于其他仓库配置这里不再提及，具体可以参考[官方文档](http://books.sonatype.com/nexus-book/reference3/index.html)；2.x 可以通过图形界面上传 jar，3.x 目前只能通过 maven deploy 插件实现，可以参考[这里](https://maven.apache.org/guides/mini/guide-3rd-party-jars-remote.html)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
