---
layout: post
title: Harbor 企业级 Docker Registry 初试
categories: [Docker]
description: Harbor 企业级 Docker Registry 初试
keywords: Docker,Linux,Harbor,Registry
---


## 一、介绍

> Project Harbor is an enterprise-class registry server, which extends the open source Docker Registry server by adding the functionality usually required by an enterprise, such as security, control, and management. Harbor is primarily designed to be a private registry - providing the needed security and control that enterprises require. It also helps minimize bandwidth usage, which is helpful to both improve productivity (local network access) as well as performance (for those with poor internet connectivity).

简单的说，Harbor 是一个企业级的 Docker Registry，可以实现 images 的私有存储和日志统计权限控制等功能，并支持创建多项目(Harbor 提出的概念)，基于官方 Registry V2 实现。

<!--more-->

## 二、环境准备

本文所使用的环境如下 :

- Ubuntu 14.04
- Docker 1.11.2
- docker-compose 1.6.2

### 2.1、安装 Docker

执行以下命令安装 Docker

``` sh
curl -fsSL https://get.docker.io | bash
```

### 2.2、安装 docker-compose

默认的 [官方文档](https://docs.docker.com/compose/install/) 安装命令如下 :

``` sh
curl -L https://github.com/docker/compose/releases/download/1.6.2/docker-compose-`uname -s`-`uname -m` > /usr/local/bin/docker-compose
```

**经过本人测试，其文件托管在亚马逊上，伟大的防火墙成功阻止下载......**

**有能力的童鞋可以使用梯子，我已经下载好了一个 [点击下载](https://mritd.b0.upaiyun.com/files/docker-compose)**；下载后直接 cp 到 `/usr/local/bin` 下并给与可执行权限即可。

## 三、搭建 Harbor

### 3.1、克隆源码

``` sh
git clone https://github.com/vmware/harbor
```

### 3.2、修改配置

``` sh
cd harbor/Deploy/
vim harbor.cfg
```

配置样例如下 :

``` sh
## Configuration file of Harbor

#The IP address or hostname to access admin UI and registry service.
#DO NOT use localhost or 127.0.0.1, because Harbor needs to be accessed by external clients.
# 指定 hostname，一般为IP，或者域名，用于登录 Web UI 界面
hostname = 10.211.55.17

#The protocol for accessing the UI and token/notification service, by default it is http.
#It can be set to https if ssl is enabled on nginx.
# URL 访问方式，SSL 需要配置 nginx
ui_url_protocol = http

#Email account settings for sending out password resetting emails.
# 邮件相关信息配置，如忘记密码发送邮件
email_server = smtp.xxxxxx.com
email_server_port = 465
email_username = reg@mritd.me
email_password = xxxxxx
email_from = docker <reg@mritd.me>
email_ssl = true

##The password of Harbor admin, change this before any production use.
# 默认的 Harbor 的管理员密码，管理员用户名默认 admin
harbor_admin_password = Harbor12345

##By default the auth mode is db_auth, i.e. the credentials are stored in a local database.
#Set it to ldap_auth if you want to verify a user's credentials against an LDAP server.
# 指定 Harbor 的权限验证方式，Harbor 支持本地的 mysql 数据存储密码，同时也支持 LDAP
auth_mode = db_auth

#The url for an ldap endpoint.
# 如果采用了 LDAP，此处填写 LDAP 地址
ldap_url = ldaps://ldap.mydomain.com

#The basedn template to look up a user in LDAP and verify the user's password.
# LADP 验证密码的方式(我特么没用过这么高级的玩意)
ldap_basedn = uid=%s,ou=people,dc=mydomain,dc=com

#The password for the root user of mysql db, change this before any production use.
# mysql 数据库 root 账户密码
db_password = root123

#Turn on or off the self-registration feature
# 是否允许开放注册
self_registration = on

#Turn on or off the customize your certicate
# 允许自签名证书
customize_crt = on

#fill in your certicate message
# 自签名证书信息
crt_country = CN
crt_state = State
crt_location = CN
crt_organization = mritd
crt_organizationalunit = mritd
crt_commonname = mritd.me
crt_email = reg.mritd.me
#####
```

### 3.3、生成相关配置

``` sh
cd harbor/Deploy/
./prepare
```

![hexo_docker_harbor_prepare](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_prepare.png)

### 3.4、编译 image 并启动

``` sh
cd harbor/Deploy/
docker-compose up -d
```

![hexo_docker_harbor_up](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_up.png)

### 3.5、启动后相关容器

**正常启动成功后会有 5 个 Contianer :**

- Proxy : 由Nginx 服务器构成的反向代理
- Registry : 由Docker官方的开源registry 镜像构成的容器实例
- UI : 即架构中的core services, 构成此容器的代码是Harbor项目的主体
- Mysql : 由官方MySql镜像构成的数据库容器
- Log : 运行着rsyslogd的容器，通过log-driver的形式收集其他容器的日志

**这几个 Contianer 通过 Docker link 的形式连接在一起，在容器之间通过容器名字互相访问。对终端用户而言，只需要暴露 proxy（即Nginx）的服务端口**

![hexo_docker_harbor_contianer](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_contianer.png)

## 四、访问 Web UI 并测试

### 4.1、主页

**默认的访问地址即为 `harbor.cfg` 中 `hostname` 地址，直接访问即可，如下**

![hexo_docker_harbor_homepage](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_homepage.png)

**如果 `harbor.cfg` 中 `self_registration` 属性设置为 `off`，那么普通用户将无法自己实现注册，只能由管理员创建用户，主页右上角的注册按钮也会消失。**

### 4.2、登录

**Harbor 默认管理员用户为 `admin`，密码在 `harbor.cfg` 中设置过，默认的是 `Harbor12345`，可直接登陆**

![hexo_docker_harbor_userspace](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_userspace.png)

### 4.3、创建私有项目

**Harbor 有一个项目的概念，项目名可以理解为 Docker Hub 的用户名，其下可以后很多 images，Harbor 的项目必须登录后方可 push，公有项目和私有项目的区别是对其他用户是否可见**

![hexo_docker_harbor_createproject](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_createproject.png)

### 4.4、push 镜像

#### 4.4.1、设置 http 仓库地址

由于采用了默认的 http 方式连接，而 Docker 认为这是不安全的，所以在 push 之前需要调整一下 docker 配置，编辑 `/etc/default/docker` 增加如下内容

``` sh
DOCKER_OPTS="$DOCKER_OPTS --insecure-registry 10.211.55.17"
```

**其中 IP 地址要指向 `harbor.cfg` 中的 `hostname`**，然后执行 `docker-compose stop` 停掉所有 Contianer，再执行 `service docker restart` 重启 Dokcer 服务，最后执行 `docker-compose start` 即可。

**注意 : Docker 服务重启后，执行 `docker-compose start` 时有一定几率出现如下错误(或者目录已存在等错误)，此时在 `docker-compose stop` 一下然后在启动即可，实在不行再次重启 Dokcer 服务，千万不要手贱的去删文件(别问我怎么知道的)**

![hexo_docker_harbor_composeerror](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_composeerror.jpeg)

#### 4.4.2、Harbor 项目和权限(角色)

**用户本身拥有的项目，登陆后可直接 push，其他的用户创建的项目取决于项目是否添加了对应用户和权限，**

**也就是说用户是否可以向一个项目 push 镜像，取决于权限(角色)设置，如下所示，在项目中可以设置成员和其权限**

![hexo_docker_harbor_projectuser](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_projectuser.png)

![hexo_docker_harbor_projectuserrole](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_projectuserrole.png)

**对于权限(角色)，`Project Admin` 和 `Developer` 可以有 push 的权限，而 `Guest` 只能查看和 pull**


#### 4.4.3、push 镜像

首先使用一个对目标项目具有 push 权限的用户登录，以下 push 的目标是 mritd 项目，test1 用户在项目里定义为 `Developer`，所以登录后 push 即可

![hexo_docker_harbor_loginmritd](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_loginmritd.png)

然后 `tag` 一个 image，名称一定要标准( `registryAddress[:端口]/项目/imageName[:tag]` )，最后将其 push 即可

![hexo_docker_harbor_pushmritdimages](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_pushmritdimages.png)

最后可在 Web UI 中查看刚刚 push 的 image

![hexo_docker_harbor_mritdshow](https://mritd.b0.upaiyun.com/markdown/hexo_docker_harbor_mritdshow.png)


**到此结束 Thanks**
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
