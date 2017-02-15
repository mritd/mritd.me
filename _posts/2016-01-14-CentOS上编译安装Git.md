---
layout: post
title: CentOS 上编译安装 Git
categories: [Git, Linux]
description: CentOS上编译安装Git
keywords: Git,CentOS
---

![hexo_git_install_logo](https://mritd.b0.upaiyun.com/markdown/hexo_git_install_logo.png)

## 一、概述

> Git是目前世界上最先进的分布式版本控制系统(没有之一)，高端大气上档次的 Git 值得我们去学习，由于CentOS本身的Git版本太低，所以这里记录一下CentOS下编译安装Git的过程。

<!--more-->

## 二、安装前准备工作

1. 下载 git 源码 [下载地址](https://github.com/git/git/releases)
2. 上传到 CentOS (略过)
3. 解压文件 执行 `tar -zxvf git-2.7.0.tar.gz`

## 三、编译安装

### 1、安装编译所需的依赖环境

``` sh
yum -y install curl-devel expat-devel gettext-devel openssl-devel zlib-devel perl-ExtUtils-MakeMaker
```

### 2、配置安装目录

> git 默认编译安装会安装到当前用户目录下，所以需要配置安装目录

``` sh
cd git-2.7.0
autoconf
./configure --prefix=/usr/local
```

### 3、编译并安装

``` sh
make && make install
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
