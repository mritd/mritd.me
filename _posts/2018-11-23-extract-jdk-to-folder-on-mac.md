---
layout: post
categories: Java
title: Mac: Extract JDK to folder, without running installer
date: 2018-11-23 12:33:20 +0800
description: Mac: Extract JDK to folder, without running installer
keywords: jdk
catalog: true
multilingual: false
tags: Java
---

Mac: Extract JDK to folder, without running installer

> 重装了 mac 系统，由于一些公司项目必须使用 Oracle JDK(验证码等组件用了一些 Oracle 独有的 API) 所以又得重新安装；但是 Oracle 只提供了 pkg 的安装方式，研究半天找到了一个解包 pkg 的安装方式，这里记录一下


不使用 pkg 的原因是每次更新版本都要各种安装，最烦人的是 IDEA 选择 JDK 时候弹出的文件浏览器没法进入到这种方式安装的 JDK 的系统目录...mmp，后来从国外网站找到了一篇文章，基本套路如下

- 下载 Oracle JDK，从 dmg 中拷贝 pkg 到任意位置
- 解压 pkg 到任意位置 `pkgutil --expand your_jdk.pkg jdkdir`
- 进入到目录中，解压主文件 `cd jdkdir/jdk_version.pkg && cpio -idv < Payload`
- 移动 jdk 到任意位置 `mv Contents/Home ~/myjdk`

原文地址: [OS X: Extract JDK to folder, without running installer](https://augustl.com/blog/2014/extracting_java_to_folder_no_installer_osx/)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
