---
layout: post
title: Can't connect to MySQL server on 'xxxx' (61)
categories: [MySQL]
description: Can't connect to MySQL server on 'xxxx' (61)
keywords: Linux,MySQL
---

**记录一下 Ubuntu 下安装 MySql 踩得坑；刚刚安装完 MySQL，连接时始终报 `Can't connect to MySQL server on '10.211.55.14' (61)`；后来查询此错误的原因就是网络不通，于是检查 ufw 防火墙、本机杀软、MySql远程访问开启情况...发现没问题以后，最终找到了答案：**

<!--more-->

**MySql 默认 监听 127.0.0.1，也就是说只有本地可以连接，需要将其改为 0.0.0.0 即可，更改方法如下：**

``` sh
vim /etc/mysql/my.cnf
```

**找到 bind-address 选项，将后面的 IP 改为 0.0.0.0，然后 执行重启 `service mysql restart`，截图如下:**

![hexo_mysql_modify_listen_port](https://mritd.b0.upaiyun.com/markdown/hexo_mysql_modify_listen_port.png)
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
