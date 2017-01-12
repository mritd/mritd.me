---
layout: post
categories: Linux Git
title: Git 使用 socks5 代理
date: 2017-01-12 23:03:30 +0800
description: 记录各平台下 git 使用 socks5 代理的方法
keywords: git socks5
---

> Fuck GFW! 最近伟大的墙又开始搞事情，导致 gayhub 访问奇慢，没办法研究一下 socks5 代理 git，效果还不错

### 一、Mac & Ubuntu 下代理 git

git 目前支持 4 种协议: `https`、`ssh`、`git`、本地文件；其中 `git`协议与 `ssh` 协议及其类似，暂不清楚底层实现，不过目前发现只需要成功代理 `ssh` 协议就可以实现代理 `git`；不清楚两者有什么基情，根据官方描述，`git` 协议传输非常快，验证基于 `ssh` 协议，详见 [服务器上的 Git - 协议](https://git-scm.com/book/zh/v2/%E6%9C%8D%E5%8A%A1%E5%99%A8%E4%B8%8A%E7%9A%84-Git-%E5%8D%8F%E8%AE%AE)

代理 `ssh` 协议在 Mac 和 Ubuntu 上可以使用 `netcat-openbsd` 包中的 `nc` 命令，这里由于梯子工具问题，所以仅讨论如何使用 `nc` 代理 `ssh` 协议到 `socks5` 上

Mac 默认就有 `nc` 命令， Ubuntu 新版本也有，如果较老版本可使用 `apt-get install -y netcat-openbsd` 安装

#### 1.1、创建代理命令工具

首先创建一个代理脚本即可，`socks5` 地址根据需要更改

``` sh
tee /usr/local/bin/proxy-wrapper <<EOF
#!/bin/bash
nc -x127.0.0.1:1080 -X5 \$*
EOF
chmod +x /usr/local/bin/proxy-wrapper
```

#### 1.2、增加 ssh 配置

代理 `git` 协议只需要代理 `ssh` 即可，其中 `Host` 后可以跟多个想要被代理的域名，由于代理的是 `ssh` 协议，所以 **使用 `ssh` 连接服务器也会根据域名选择是否走代理**

``` sh
tee ~/.ssh/config <<EOF
Host github github.com mritd.me
#Hostname github.com
#User git
ProxyCommand /usr/local/bin/proxy-wrapper '%h %p'
EOF
```

#### 1.3、测试

配置好以后，保证你得 `socks5` 代理无问题的情况下，使用 `git clone git@github.com:xxxxx/xxxxx.git` 克隆一个项目即可验证是否成功


### 二、CentOS 下代理 git

默认的 CentOS 下是没有 `netcat-openbsd` 的，CentOS 下的 netcat 并非 openbsd 版本，所以会出现 `nc: invalid option -- 'X'` 错误；so，用不了 `nc` 了，不过 Linux 下还有另一款软件可以实现代理 `ssh` 协议到 `socks5`

#### 2.1、安装 connect-proxy

没有 `netcat-openbsd` 可以安装 `connect-proxy`

``` sh
yum install connect-proxy -y
```

#### 2.2、创建代理脚本

同上面一样，也最好搞一个脚本

``` sh
tee /usr/local/bin/proxy-wrapper <<EOF
#!/bin/bash
connect-proxy -S 192.168.1.120:1083 $*
EOF
chmod +x /usr/local/bin/proxy-wrapper
```

#### 2.3、增加 ssh 配置

ssh 配置同上面一样

``` sh
tee ~/.ssh/config <<EOF
Host github github.com mritd.me
#Hostname github.com
#User git
ProxyCommand /usr/local/bin/proxy-wrapper '%h %p'
EOF
```

#### 2.3、测试

测试掠过......

### 三、其他

对于 `https` 协议的代理可以参考 [Linux 命令行下使用 Shadowsocks 代理](https://mritd.me/2016/07/22/Linux-%E5%91%BD%E4%BB%A4%E8%A1%8C%E4%B8%8B%E4%BD%BF%E7%94%A8-Shadowsocks-%E4%BB%A3%E7%90%86/)


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
