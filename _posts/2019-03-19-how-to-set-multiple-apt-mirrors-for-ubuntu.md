---
layout: post
categories: Linux
title: Ubuntu 设置多个源
date: 2019-03-19 21:43:23 +0800
description: Ubuntu 设置多个源
keywords: ubuntu,apt,mirror
catalog: true
multilingual: false
tags: Linux
---

## 一、源起

使用 Ubuntu 作为生产容器系统好久了，但是 apt 源问题一致有点困扰: **由于众所周知的原因，官方源执行 `apt update` 等命令会非常慢；而国内有很多镜像服务，但是某些偶尔也会抽风(比如清华大源)，最后的结果就是日常修改 apt 源...**Google 查了了好久发现事实上 apt 源是支持 `mirror` 协议的，从而自动选择可用的一个

## 二、使用 mirror 协议

废话不说多直接上代码，编辑 `/etc/apt/sources.list`，替换为如下内容

``` sh
#------------------------------------------------------------------------------#
#                            OFFICIAL UBUNTU REPOS                             #
#------------------------------------------------------------------------------#


###### Ubuntu Main Repos
deb mirror://mirrors.ubuntu.com/mirrors.txt bionic main restricted universe multiverse
deb-src mirror://mirrors.ubuntu.com/mirrors.txt bionic main restricted universe multiverse

###### Ubuntu Update Repos
deb mirror://mirrors.ubuntu.com/mirrors.txt bionic-security main restricted universe multiverse
deb mirror://mirrors.ubuntu.com/mirrors.txt bionic-updates main restricted universe multiverse
deb mirror://mirrors.ubuntu.com/mirrors.txt bionic-backports main restricted universe multiverse
deb-src mirror://mirrors.ubuntu.com/mirrors.txt bionic-security main restricted universe multiverse
deb-src mirror://mirrors.ubuntu.com/mirrors.txt bionic-updates main restricted universe multiverse
deb-src mirror://mirrors.ubuntu.com/mirrors.txt bionic-backports main restricted universe multiverse
```

当使用 `mirror` 协议后，执行 `apt update` 时会首先**通过 http 访问** `mirrors.ubuntu.com/mirrors.txt` 文本；文本内容实际上就是当前可用的镜像源列表，如下所示

``` sh
http://ftp.sjtu.edu.cn/ubuntu/
http://mirrors.nju.edu.cn/ubuntu/
http://mirrors.nwafu.edu.cn/ubuntu/
http://mirrors.sohu.com/ubuntu/
http://mirrors.aliyun.com/ubuntu/
http://mirrors.shu.edu.cn/ubuntu/
http://mirrors.cqu.edu.cn/ubuntu/
http://mirrors.huaweicloud.com/repository/ubuntu/
http://mirrors.cn99.com/ubuntu/
http://mirrors.yun-idc.com/ubuntu/
http://mirrors.tuna.tsinghua.edu.cn/ubuntu/
http://mirrors.ustc.edu.cn/ubuntu/
http://mirrors.njupt.edu.cn/ubuntu/
http://mirror.lzu.edu.cn/ubuntu/
http://archive.ubuntu.com/ubuntu/
```

得到列表后 apt 会自动选择一个(选择规则暂不清楚，国外有文章说是选择最快的，但是不清楚这个最快是延迟还是网速)进行下载；**同时根据地区不通，官方也提供指定国家的 `mirror.txt`**，比如中国的实际上可以设置为 `mirrors.ubuntu.com/CN.txt`(我测试跟官方一样，推测可能是使用了类似 DNS 选优的策略)

## 三、自定义 mirror 地址

现在已经解决了能同时使用多个源的问题，但是有些时候你会发现源的可用性检测并不是很精准，比如某个源只有 40k 的下载速度...不巧你某个下载还命中了，这就很尴尬；**所以有时候我们可能需要自定义 `mirror.txt` 这个源列表**，经过测试证明**只需要开启一个标准的 `http server` 能返回一个文本即可，不过需要注意只能是 `http`，而不是 `https`**；所以我们首先下载一下这个文本，把不想要的删掉；然后弄个 nginx，甚至 `python -m http.server` 把文本文件暴露出去就可以；我比较懒...扔 CDN 上了: http://oss.link/config/apt-mirrors.txt

关于源的精简，我建议将一些 `edu` 的删掉，因为敏感时期他们很不稳定；优选阿里云、网易、华为这种大公司的，比较有名的清华大的什么的可以留着，其他的可以考虑都删掉

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
