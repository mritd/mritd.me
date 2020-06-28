---
layout: post
categories: Linux
title: 树莓派4 Manjaro 系统定制
date: 2020-06-28 21:59:15 +0800
description: 树莓派4 Manjaro 系统定制
keywords: linux,raspberry4,manjaro
catalog: true
multilingual: false
tags: Linux
---

> 最近入手了新玩具 "吹灰派4"，这一代性能提升真的很大，所以买回来是真的没办法 "吃灰" 了；但是由于目前 64bit 系统比较难产，所以只能自己定义一下 Manjaro 了。

## 一、目前的系统现状

截止本文编写时间，树莓派4 官方系统仍然不支持 64bit；但是当我在 3b+ 上使用 arch 64bit 以后我发现 32bit 系统和 64bit 系统装在同一个树莓派上在使用时那就是两个完全不一样的树莓派...所以对于这个新的 rpi4 那么必需要用 64bit 的系统；而当前我大致查看到支持 64bit 的系统只有 Ubuntu20、Manjaro 两个，Ubuntu 对我来说太重了(虽然服务器上我一直是 Ubuntu，但是 rpi 上我选择说 "不")，Manjaro 基于 Arch 这种非常轻量的系统非常适合树莓派这种开发板，所以最终我选择了 Manjaro。但是万万没想到的是 Manjaro 都是带 KDE 什么的图形化的，而我的树莓派只想仍在角落里跑东西，所以说图形化这东西对我来说也没啥用，最后迫于无奈只能自己通过 Manjaro 的工具自己定制了。

## 二、manjaro-arm-tools

经过几经查找各种 Google，发现了 Manjaro 官方提供了自定义创建 arm 镜像的工具 [manjaro-arm-tools](https://gitlab.manjaro.org/manjaro-arm/applications/manjaro-arm-tools)，这个工具简单使用如下:

- 首先准备一个 Manjaro 系统(虚拟机 x86 即可)
- 然后安装 manjaro-arm-tool 所需[依赖工具](https://gitlab.manjaro.org/manjaro-arm/applications/manjaro-arm-tools#dependencies)
- 添加 Manjaro 的[软件源](https://gitlab.manjaro.org/manjaro-arm/applications/manjaro-arm-tools#git-version-from-manjaro-strit-repo)
- 安装 manjaro-arm-tool `sudo pacman -Syyu manjaro-strit-keyring && sudo pacman -S manjaro-arm-tools-git`

当工具都准备完成后，只需要执行 `sudo buildarmimg -d rpi4 -e minimal` 即可创建 manjaro 的 rpi4 最小镜像。

## 三、系统定制

在使用 manjaro-arm-tool 创建系统以后发现一些细微的东西需要自己调整，比如网络设置常用软件包等，而 manjaro-arm-tool 工具又没有提供太好的自定义处理的一些 hook，所以最后萌生了自己根据 manjaro-arm-tool 来创建自己的 rpi4 系统定制工具的想法。

### 3.1、常用软件包安装

在查看了 manjaro-arm-tool 的源码后可以看到实际上软件安装就是利用 systemd-nspawn 进入到 arm 系统执行 pacman 安装，自己依葫芦画瓢增加一些常用的软件包安装:

```sh
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${ROOTFS_DIR} pacman -Syyu zsh htop vim wget which git make net-tools dnsutils inetutils iproute2 sysstat nload lsof --noconfirm
```

### 3.2、pacman 镜像

在安装软件包时发现安装速读奇慢，研究以后发现是没有使用国内的镜像源，故增加了国内镜像源的处理:

```sh
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${ROOTFS_DIR} pacman-mirrors -c China
```

### 3.3、网络处理

#### 3.3.1、有线连接

默认的 manjaro-arm-tool 创建的系统网络部分采用 dhspcd 做 dhcp 处理，但是我个人感觉一切尽量精简统一还是比较好的；所以准备网络部分完全由 systemd 接管处理，即直接使用 systemd-networkd 和 systemd-resolved；systemd-networkd 处理相对简单，编写一个配置文件然后 enable systemd-networkd 服务即可:

**/etc/systemd/network/10-eth-dhcp.network**

```sh
[Match]
Name=eth*

[Network]
DHCP=yes
```

**让 systemd-networkd 开机自启动**

```sh
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${ROOTFS_DIR} systemctl enable systemd-networkd.service
```

一开始以为 systemd-resolved 同样 enable 一下就行，后来发现每次开机初始化以后 systemd-resolved 都会被莫明其妙的 disable 掉；经过几经寻找和开 issue 问作者，发现这个操作是被 manjaro-arm-oem-install 包下的脚本执行的，作者的回复意思是大部分带有图形化的版本网络管理工具都会与 systemd-resolved 冲突，所以默认关闭了，这时候我们就要针对 manjaro-arm-oem-install 单独处理一下:

```sh
systemd-nspawn -q --resolv-conf=copy-host --timezone=off -D ${ROOTFS_DIR} systemctl enable systemd-resolved.service
sed -i 's@systemctl disable systemd-resolved.service 1> /dev/null 2>&1@@g' ${ROOTFS_DIR}/usr/share/manjaro-arm-oem-install/manjaro-arm-oem-install
```

#### 3.3.2、无限连接

有线连接只要 systemd-networkd 处理好就能很好的工作，而无线连接目前有很多方案，我一开始想用 [netctl](https://wiki.archlinux.org/index.php/Netctl_(%E7%AE%80%E4%BD%93%E4%B8%AD%E6%96%87))，后来发现这东西虽然是 Arch 亲儿子，但是在系统定制时采用 systemd-nspawn 调用不兼容(因为里面调用了 systemd 的一些命令，这些命令一般只有在开机时才可用)，而且只用 netctl 来管理 wifi 还感觉怪怪的，后来我的想法是要么用就全都用，要么就纯手动不要用这些东西，所以最后的方案是 wpa_supplicant + systemd-networkd 一把梭:

**/etc/systemd/network/10-wlan-dhcp.network.example**

```sh
# 1. Generate wifi configuration (don't modify the name of wpa_supplicant-wlan0.conf file)
# $ wpa_passphrase MyNetwork SuperSecretPassphrase > /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
#
# 2. Connect to wifi automatically after booting
# $ systemctl enable wpa_supplicant@wlan0
#
# 3.Systemd automatically makes dhcp request
# $ cp /etc/systemd/network/10-wlan-dhcp.network.example /etc/systemd/network/10-wlan-dhcp.network

[Match]
Name=wlan*

[Network]
DHCP=yes
```

### 3.4、内核调整

在上面的一些调整完成后我就启动系统实体机测试了，测试过程中发现安装 docker 以后会有两个警告，大致意思就是不支持 swap limit 和 cpu limit；查询资料以后发现是内核有两个参数没开启(`CONFIG_MEMCG_SWAP`、`CONFIG_CFS_BANDWIDTH`)...当然我这种强迫症是不能忍的，没办法就自己在 rpi4 上重新编译了内核(后来我想想还不如用 arch 32bit 然后自己编译 64bit 内核了):

```sh
git clone https://github.com/mritd/linux-rpi4.git
cd linux-rpi4
MAKEFLAGS='-j4' makepkg
```

### 3.5、外壳驱动

由于我的 rpi4 配的是 ARGON ONE 的外壳，所以电源按钮还有风扇需要驱动才能完美工作，没办法我又编译了 ARGON ONE 外壳的驱动:

```sh
git clone https://github.com/mritd/argonone.git
cd argonone
makepkg
```

## 四、定制脚本

综合以上的各种修改以后，我从 manjaro-arm-tool 提取出了定制化的 rpi4 的编译脚本，该脚本目前存放在 [mritd/manjaro-rpi4](https://github.com/mritd/manjaro-rpi4) 仓库中；目前使用此脚本编译的系统镜像默认进行了以下处理:

- 调整 pacman mirror 为中国
- 安装常用软件包(zsh htop vim wget which...)
- 有线网络完全的 systemd-networkd 接管，resolv.conf 由 systemd-resolved 接管
- 无线网络由 wpa_supplicant 和 systemd-networkd 接管
- 安装自行编译的内核以消除 docker 警告(**自编译内核不影响升级，升级/覆盖安装后自动恢复**)

至于 ARGON ONE 的外壳驱动只在 resources 目录下提供了安装包，并未默认安装到系统。

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
