---
layout: post
categories: Kubernetes
title: How to build Kubernetes RPM
date: 2017-07-12 22:52:38 +0800
description: 记录 build kubernetes 的过程
keywords: kubernetes
catalog: true
multilingual: false
tags: Linux Docker Kubernetes
---

> 一直使用 Centos 运行 Kubernetes,有些时候基于二进制部署的情况下,手动复制二进制文件和创建 Systemd service 配置略显繁琐;最近找了一下 Kubernetes RPM 的 build 方式,以下记录一下 build 过程


### 一、RPM build 方式选择

目前我所知道的 build kubernetes RPM 的方式(测试过)总共 3 种,大致分为 2 类

- 基于源码 build
- 基于已有 rpm 替换

第一种方案的好处就是配置文件等能始终保持最新的,编译版本等不受限制;但是从源码 build 非常耗时,尤其是网络环境复杂的情况下,没有高配置国外服务器很难完成 build,而且要维护 build 所需 spec 文件等,自己维护这些未必能够尽善尽美;

第二种方式是创建速度快,build 方式简单可靠,但是由于是替换方式,所以 rpm 中的配置不一定能够即使更新,而且只能基于官方build 好以后的二进制文件进行替换,如果想要尝试 master 最新代码则无法实现

### 二、基于源码 Build

对于 Centos RPM build 原理方式这里不再细说，基于源码 build 的关键就在于 spec 文件，我尝试过自己去写，后来对比一些开源项目的感觉 low 得很，所以以前一直采用一个国外哥们写的脚本 build(参见 [这里](https://github.com/mritd/kubernetes-rpm-builder))；这个脚本不太好的地方是作者已经停止了维护；经过不懈努力，找到了 Fedora 系统的 rpm 仓库，鼓捣了一阵摸清了套路；以下主要以 Fedora 仓库为例进行 build

**以下 Build 在一台 Do 8核心 16G VPS 上进行，由于众所周知的原因，国内 Build 很费劲，一般国外 VPS 都是按小时收费，有个 2 块钱就够了**

#### 2.1、安装 build 所需依赖

**由于 spec 文件中定义了依赖于 golang 这个包，所以如果不装的话会报错；事实上如果使用刚刚安装的这个 golang 去 build 还是会挂掉，因为实际编译要求 golang > 1.7，直接 yum 装的是 1.6，故下面又使用 gvm 装了一个 1.8 的 golang，上面的 golang 安装只是为了通过 spec 检查**

``` sh
# EPEL
yum install epel-release -y
# update 系统组件
yum update -y && yum upgrade -y
# 安装基本的编译依赖
yum install golang go-md2man go-bindata gcc bison git rpm-build vim -y
# 安装 gvm(用于 golang 版本管理)
bash < <(curl -s -S -L https://raw.githubusercontent.com/moovweb/gvm/master/binscripts/gvm-installer)
source /root/.gvm/scripts/gvm
# 安装 1.8 之前需要先安装 1.4
gvm install go1.4 -B
gvm use go1.4
# 使用 golang 1.8 版本 build
gvm install go1.8
gvm use go1.8
```
#### 2.2、克隆 build 仓库

**Fedora 官方 Kubernetes 仓库地址在 [这里](https://src.fedoraproject.org/cgit/rpms/kubernetes.git/)，如果有版本选择请自行区分**

``` sh
git clone https://src.fedoraproject.org/git/rpms/kubernetes.git
```

#### 2.3、从 spec 获取所需文件

克隆好 build 仓库后首先查看 kubernetes.spec 文件，确定 build 所需文件，spec 文件如下

``` sh
# 省略...

%global provider                github
%global provider_tld            com
%global project                 kubernetes
%global repo                    kubernetes
# https://github.com/kubernetes/kubernetes

%global provider_prefix         %{provider}.%{provider_tld}/%{project}/%{repo}
%global import_path             k8s.io/kubernetes
%global commit                  095136c3078ccf887b9034b7ce598a0a1faff769
%global shortcommit              %(c=%{commit}; echo ${c:0:7})

%global con_provider            github
%global con_provider_tld        com
%global con_project             kubernetes
%global con_repo                contrib
# https://github.com/kubernetes/contrib
%global con_provider_prefix     %{con_provider}.%{con_provider_tld}/%{con_project}/%{con_repo}
%global con_commit              0f5b210313371ff769da24d8264f5a7869c5a3f3
%global con_shortcommit         %(c=%{con_commit}; echo ${c:0:7})

%global kube_version            1.6.7
%global kube_git_version        v%{kube_version}

# 省略...
```

**从 spec 文件中可以看到 build 主要需要两个仓库的源码，一个是 kubernetes 主仓库，存放着主要的 build 源码；另一个是 contrib 仓库，存放着一些配置文件，如 systemd 配置等**

**接下来从 spec 文件的 source 段中可以解读到(source0、source1)最终所需的两个仓库压缩文件名为 `kubernetes-SHORTCOMMIT`、`contrib-SHORTCOMIT`，source 段如下**

``` sh
Name:           kubernetes
Version:        %{kube_version}
Release:        1%{?dist}
Summary:        Container cluster management
License:        ASL 2.0
URL:            https://%{import_path}
ExclusiveArch:  x86_64 aarch64 ppc64le s390x
Source0:        https://%{provider_prefix}/archive/%{commit}/%{repo}-%{shortcommit}.tar.gz
Source1:        https://%{con_provider_prefix}/archive/%{con_commit}/%{con_repo}-%{con_shortcommit}.tar.gz
Source3:        kubernetes-accounting.conf
Source4:        kubeadm.conf
Source33:       genmanpages.sh
```

**我们准备 build 一个最新的 1.7.0 的 rpm，所以从 github 获取到 commitID 为 `d3ada0119e776222f11ec7945e6d860061339aad`，contrib 仓库同理，不过 contrib 一般直接取 master 即可 `7d344989fe6a3f11a6d84104b024a50960b021db`；接下来首要任务是替换 spec 中原有的 版本号和 commitID 如下**

``` sh
%global kube_version            1.7.0
%global con_commit              7d344989fe6a3f11a6d84104b024a50960b021db
%global commit                  d3ada0119e776222f11ec7945e6d860061339aad
```

#### 2.4、准备源码

修改好文件以后，就可以下载源码文件了，源码下载不必去克隆 github 项目，直接从 spec 中给出的地址下载即可

``` sh
cd kubernetes
wget https://github.com/kubernetes/kubernetes/archive/d3ada0119e776222f11ec7945e6d860061339aad/kubernetes-d3ada01.tar.gz
wget https://github.com/kubernetes/contrib/archive/7d344989fe6a3f11a6d84104b024a50960b021db/contrib-7d34498.tar.gz
```

#### 2.5、build rpm

在正式开始 build 之前，还有一点需要注意的是 **默认的 `kubernetes.spec` 文件中指定了该 rpm 依赖于 docker 这个包，在 CentOS 上可能我们会安装 docker-engine 或者 docker-ce，此时安装 kubernetes rpm 是无法安装的，因为他以来的包不存在，解决的办法就是编译之前删除 spec 文件中的 `Requires: docker` 即可**，最后创建好 build 目录，并放置好源码文件开始 build 即可，当然 build 可以有不同选择

``` sh
# 由于我是 root 用户，所以目录位置在这
# 实际生产 强烈不推荐使用 root build(操作失误会损毁宿主机)
# 我的是一台临时 vps，所以无所谓了
mkdir -p /root/rpmbuild/SOURCES/
mv ~/kubernetes/* /root/rpmbuild/SOURCES/
cd /root/rpmbuild/SOURCES/
# 执行 build
rpmbuild -ba kubernetes.spec
```

**注意，由于我们选择的版本已经超出了仓库所支持的最大版本，所以有些 Patch 已经不再适用，如 spec 中的 `Patch12`、`Patch19` 会出错，所需要注释掉(%prep 段中也有一个)**


**`rpmbuild 可选项有很多，常用的 3 个，可以根据自己实际需要进行 build:`**

- `-ba` : build 源码包+二进制包
- `-bb` : 只 build 二进制包
- `-bs` : 只 build 源码包

最后 build 完成后如下

![rpms](https://mritd.b0.upaiyun.com/markdown/7tn2a.jpg)


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
