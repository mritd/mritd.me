---
layout: post
title: CentOS 6.7_x64 minimal 网络初始化配置
categories: [Linux]
description: CentOS 6.7_x64 minimal 网络初始化配置
keywords: CentOS,CentOS6,Linux,网络配置
---

![centos6](https://mritd.b0.upaiyun.com/markdown/centos6.png)

### CentOS 6.7_x64 网络初始化配置

> 最近准备折腾折腾Maven，想在本地CentOS下搭个Nexus私服，无奈CentOS LiveCD 版太大，很多功能也没啥用；so 搞了个minimal版本…..结果安装上无法联网，现记录一下初始化的网络配置。

<!--more-->

- /etc/sysconfig/network-scripts/ifcfg-eth0

> 这个文件主要是基本的配置文件，详细信息如下

``` bash
DEVICE="eth0"             #启动的网卡
MM_Controlled="no"        #没搞太明白，好像修改是实时生效的意思
ONBOOT="yes"              #启动自动联网
BOOTPROTO="static"        #ip获取方式 三个值 static、dhcp、none
IPADDR="192.168.1.60"     #ip地址
IPV6INIT=no               #ipv6支持
IPV6_AUTOCONF=no          #ipv6自动配置
NETMASK=255.255.255.0     #子网掩码
GATEWAY=192.168.1.1       #网关 一般指向路由
BROADCAST=192.168.1.255   #没太懂
```

- /etc/sysconfig/network

``` bash
NETWORKING=yes                        #网络是否可用
NETWORKING_IPV6=yes
HOSTNAME=localhost.localdomain        #主机名，主机名在/etc/hosts里面配置
```

- /etc/resolv.conf

``` bash
nameserver 192.168.10.1              #DNS服务器对应的IP
search localdomain                   #搜索要找的域名，在/etc/hosts里面设定的有
```

- 最后重启网络

``` bash
service network restart
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
