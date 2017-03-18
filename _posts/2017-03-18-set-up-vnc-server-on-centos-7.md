---
layout: post
categories: Linux
title: CentOS 7 配置 VNC Server
date: 2017-03-18 21:53:07 +0800
description: CentOS 7 配置 VNC Server
keywords: VNC
---

> 最近决定把小主机扔到客厅跟路由器放在一起(远程开机 666），因为本来就跑的是 Linux，平时图形化需求也不多；但是为了保险起见准备搞一个 VNC，以便必要时图形化上去，比如强制删除一些 Virtual Box 虚拟机等，记录一下安装过程

#### 安装 VNC Server

VNC Server 软件有很多，这里使用 `tigervnc-server`

``` sh
yum install epel-release -y
yum makecache
yum install tigervnc-server -y
```

#### 开机自启动

这地方踩了很多坑，网上不少帖子都是写的先测试 VNC Server，执行 `vncserver` 命令，然后云云；查设置开机自启动也是五花八门，大部分人的路子就是自己写一个 init 脚本，让系统开机时候执行它...... 从职业踩坑经验来看，这东西绝对有更有逼格的 Systemd 的打开方式；果不其然翻了一下 rpm 包 发现了一个 Systemd 模板 Service

``` sh
[root@mritd ~]# rpm -ql  tigervnc-server
/etc/sysconfig/vncservers
/usr/bin/vncserver
/usr/bin/x0vncserver
/usr/lib/systemd/system/vncserver@.service
/usr/share/man/man1/vncserver.1.gz
/usr/share/man/man1/x0vncserver.1.gz
```

由于好奇心作祟，先 `systemctl enable vncserver@:1.service` 了一下，后来发现起不来，所以 vim 看了一下原模板 Service，里面想写描述了如何设置开机启动

``` sh
# Quick HowTo:
# 1. Copy this file to /etc/systemd/system/vncserver@.service
# 2. Edit /etc/systemd/system/vncserver@.service, replacing <USER>
#    with the actual user name. Leave the remaining lines of the file unmodified
#    (ExecStart=/usr/sbin/runuser -l <USER> -c "/usr/bin/vncserver %i"
#     PIDFile=/home/<USER>/.vnc/%H%i.pid)
# 3. Run `systemctl daemon-reload`
# 4. Run `systemctl enable vncserver@:<display>.service`
```

也就是说把这个模板文件 cp 到 `/etc/systemd/system/vncserver@.service` 然后替换用户名，执行两条命令，最后执行 `vncserver` 用于初始化密码和配置文件就行了

重装了一天系统，有点烦躁，听首歌安静一下...

<div style="position:relative;height:0;padding-bottom:56.25%"><iframe src="https://www.youtube.com/embed/AsC0CN2eGkY?rel=0?ecver=2" width="640" height="360" frameborder="0" style="position:absolute;width:100%;height:100%;left:0" allowfullscreen></iframe></div>

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
