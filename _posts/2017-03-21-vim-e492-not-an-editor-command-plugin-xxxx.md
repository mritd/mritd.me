---
layout: post
categories: Linux
title: vim E492 Not an editor command Plugin xxxx
date: 2017-03-21 20:26:37 +0800
description: vim E492 Not an editor command Plugin xxxx
keywords: vim E492
---

> 最近自用的 vim 装了不少插件，但是发现 `kubectl edit` 或者 `git merge` 时，调用 vim 总是会弹出各种错误，记录一下解决方法

**出现这个错误一开始以为是 vim 没走 `.vimrc` 配置；后来翻了一堆资料，发现 `kubectl edit` 或者 `git merge` 后并非直接调用 vim，而是调用的 `/usr/bin/view`，那么看一下这个文件**

![view](https://mritd.b0.upaiyun.com/markdown/9c646.png)


**这东西就是链接到了 vi，只要把它链接到 vim 就完了**


![relink view](https://mritd.b0.upaiyun.com/markdown/f0c4e.png)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
