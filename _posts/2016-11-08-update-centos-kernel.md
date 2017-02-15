---
layout: post
categories: Linux
title: CentOS 升级 kernel
date: 2016-11-08 21:24:31 +0800
description: CentOS 升级 kernel
keywords: kernel
---

> 最紧要鼓捣 Dokcer Swarm，而 Swarm 的 overlay 网络需要 3.15 以上的 kernel，故记录一下升级内核的过程

### 一、手动档

手动档就是从源码开始编译内核安装，好处是可以自己选择任意版本的内核，缺点就是耗时长，编译安装消耗系统资源

#### 1.1、获取 kernel 源码

这世界上最伟大的 Linux 内核源码下载地址是 [kernel 官网](https://kernel.org)，选择一个稳定版本下载即可

![kernel homepage](https://mritd.b0.upaiyun.com/markdown/3se7u.jpg)

#### 1.2、解压并清理

官方要求将其解压到 `/usr/src` 目录，其实在哪都可以，为了规范一点索性也解压到此位置，然后为了防止编译残留先做一次清理动作

``` sh
# 下载内核源码
wget https://cdn.kernel.org/pub/linux/kernel/v4.x/linux-4.8.6.tar.xz
# 解压并移动到 /usr/src
tar -Jxvf linux-4.8.6.tar.xz
mv linux-4.8.6 /usr/src/kernels
# 执行清理(没 gcc 的要装一下)
cd /usr/src/kernels/linux-4.8.6
make mrproper && make clean
```

#### 1.3、生成编译配置表

kernel 在编译时需要一个配置文件(`.config`)，用于描述开启哪些特性等，该文件一般可通过一下四种途径获得:

- 复制当前系统编译配置表，即 `cp /boot/config-xxx .config`；如果系统有多个内核，那么根据版本号选择最新的即可
- 使用 `make defconfig` 命令获取当前系统编译配置表，该命令会自动写入到 `.config` 中
- 使用 `make localmodconfig` 命令开启交互模式，然后根据提示生成编译配置表
- 使用 `make oldconfig` 命令根据旧的编译配置表生成新的编译配置表，**刚方式会直接读取旧的便已配置表，并在以前没有设定过的配置时会自动开启交互模式**

这里采用最后一种方式生成

![create kernel compile param](https://mritd.b0.upaiyun.com/markdown/f9j5r.jpg)

#### 1.4、编译并安装

内核配置表生成完成后便可进行编译和安装(需要安装 bc、openssl-devel等)

``` sh
make
make modules
make modules_install
make install
```

**最后执行重启验证即可，验证成功后可删除旧的内核(`rpm -qa | grep kernel`)**


### 二、自动档

相对于手动档编译安装，CentOS 还可以通过使用 elrepo 源的方式直接安装最新稳定版 kernel，脚本如下

``` sh
# import key
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
# install elrepo repo
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
# install kernel
yum --enablerepo=elrepo-kernel install  kernel-ml-devel kernel-ml -y
# modify grub
grub2-set-default 0
# reboot
reboot
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
