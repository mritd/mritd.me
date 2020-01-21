---
layout: post
categories: Linux
title: 云服务器下 Ubuntu 18 正确的 DNS 修改
date: 2020-01-21 21:20:08 +0800
description: 云服务器下 Ubuntu 18 正确的 DNS 修改
keywords: linux,ubuntu,dns,netplan
catalog: true
multilingual: false
tags: Linux
---

> 最近博客服务器换成了阿里云香港，个人还偶尔看美剧，所以做了一下 Netflix 分流；分流过程主要是做 DNS 解析 SNI 代理，调了半天记录一下

## 一、起因

Netflix DNS 分流实际上我目前的方案是通过 CoreDNS 作为主 DNS Server，然后在 CoreDNS 上针对 Netflix 全部域名解析 forward 到一台国外可以解锁 Netflix 机器上；如果直接将 CoreDNS 暴露在公网，那么无疑是在作死，为 DNS 反射 DDos 提供肉鸡；所以想到的方案是自己编写一个不可描述的工具，本地 Client 到 Server 端以后，Server 端再去设置到 CoreDNS 做分流；其中不可避免的需要调整 Server 端默认 DNS。

## 二、已废弃修改方式

目前大部份人还是习惯修改 `/etc/resolv.conf` 配置文件，这个配置文件上面已经明确标注了不要去修改它；**因为自 Systemd 一统江山以后，系统 DNS 已经被 `systemd-resolved` 服务接管；一但修改了 `/etc/resolv.conf`，机器重启后就会被恢复；**所以根源解决方案还是需要修改 `systemd-resolved` 的配置。

## 三、netplan 的调整

在调整完 `systemd-resolved` 配置后其实有些地方仍然是不生效的；**原因是 Ubuntu 18 开始网络已经被 netplan 接管，所以问题又回到了如何修改 netplan；**由于云服务器初始化全部是由 cloud-init 完成的，netplan 配置里 IP 全部是由 DHCP 完成；那么直接修改 netplan 为 static IP 理论上可行，但是事实上还是不够优雅；后来研究了一下其实更优雅的方式是覆盖掉 DHCP 的某些配置，比如 DNS 配置；在阿里云上配置如下(`/etc/netplan/99-netcfg.yaml`)

``` yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: yes
      dhcp4-overrides:
        use-dns: no
      dhcp6: no
      nameservers:
        search: [local,node]
        # 我自己的 CoreDNS 服务器
        addresses: [172.17.3.17]
```

修改完成后执行 `netplan try` 等待几秒钟，如果屏幕的读秒倒计时一直在动，说明修改没问题，接着回车既可(尽量不要 `netplan apply`，一旦修改错误你就再也连不上了...)

## 四、DNS 分流

顺便贴一下 CoreDNS 配置吧，可能有些人也需要；第一部分的域名是目前我整理的 Netflix 全部访问域名，针对这些域名的流量转发到自己其他可解锁 Netflix 的机器既可

```sh
netflix.com nflxext.com nflximg.net nflxso.net nflxvideo.net {
    bind 172.17.3.17

    cache 30 . {
        success 4096
    }

    forward . 158.1.1.1 {
        max_fails 2
        prefer_udp
        expire 20s
        policy random
        health_check 0.2s
    }

    errors
    log . "{remote}:{port} - {>id} \"{type} {class} {name} {proto} {size} {>do} {>bufsize}\" {rcode} {>rflags} {rsize} {duration}"
}

.:53 {
    bind 172.17.3.17

    cache 30 . {
        success 4096
    }

    forward . 8.8.8.8 1.1.1.1 {
        except netflix.com nflxext.com nflximg.net nflxso.net nflxvideo.net
        max_fails 2
        expire 20s
        policy random
        health_check 0.2s
    }

    errors
    log . "{remote}:{port} - {>id} \"{type} {class} {name} {proto} {size} {>do} {>bufsize}\" {rcode} {>rflags} {rsize} {duration}"
```

## 五、关于 docker

当 netplan 修改完成后，只需要重启 docker 既可保证 docker 内所有容器 DNS 请求全部发送到自己定义的 DNS 服务器上；**请不要尝试将自己的 CoreDNS 监听到 `127.*` 或者 `::1` 上，这两个地址会导致 docker 中的 DNS 无效**，因为在 [libnetwork](https://github.com/docker/libnetwork/blob/fec6476dfa21380bf8ee4d74048515d968c1ee63/resolvconf/resolvconf.go#L148) 中针对这两个地址做了过滤，并且 `FilterResolvDNS` 方法在剔除这两种地址时不会给予任何警告日志


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
