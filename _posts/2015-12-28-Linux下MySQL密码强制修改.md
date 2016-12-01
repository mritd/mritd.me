---
layout: post
title: Linux 下 MySQL 密码强制修改
categories: [Linux, MySQL]
description: 记录一下 Linux 下 MySQL 密码强制修改过程
keywords: Linux,MySQL
---

> 好吧好吧，这事不怨我，二逼同事打扰我，就输错了......

### 一、停掉mysql服务

``` bash
#单独安装的mysql
service mysqld stop
#其他如lnmp脚本安装的
lnmp mysql stop
```

<!--more-->

### 二、启动mysql，禁止权限验证

``` bash
#在mysql安装目录的bin目录下执行(&后台执行)
/usr/local/mysql/bin/mysqld_safe --skip-grant-tables &
```

### 三、本地登录，更改密码

``` bash
#本地 localhost登录无需密码
mysql -u root
#切换数据库
mysql>use mysql;
#更改密码
mysql>update user set password=password("newpasswd") where user="root";
#刷新权限
mysql>flush privileges;
#退出
mysql>\q
```

### 四、启动mysql

- 先停掉已经跳过权限的mysql启动进程

``` bash
#查询mysql是否启动
ps aux | grep "mysql"
#如果发现 有  --skip-grant-tables  类似的进程 找到其 PID kill掉
#然后在 kill掉其他进程
#PID : 用户名后面的 数字为PID
kill -9 PID
```

- 正常启动mysql

``` bash
#普通直接安装
service mysqld start
#lnmp脚本安装
lnmp mysql start
```

- 登录测试

``` bash
#输入密码
mysql -uroot -p
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
