---
layout: post
title: ShadowSocks 多用户版搭建教程
categories: [Shadowsocks]
description: shadowsocks 多用户版搭建教程
keywords: ShadowSocks,翻墙
---

![ShadowSocks](https://mritd.b0.upaiyun.com/markdown/hexo_shadowsocks_logo.png)

> 众所周知，由于某种原因，大天朝的网络对外网(国际网路)的访问是封锁的，但作为搞IT的，个人感觉翻墙是必备的技能；因为很多东西(IT资料)谷歌出来的更准确一些，忍不住吐槽百度的垃圾搜索，我已经大约2年没用百度了，因为百度点东西你会发现很多情况都是 **一大片都一样的**，要不就是不同网站，但是内容一样......下面记录一下目前最屌的爬墙工具 **ShadowSocks** 简称 ss 的搭建过程。

<!--more-->

## 一、准备工作
1. 一台能连接公网的VPS( **VPS必须能访问Google等，一般是在国外购买**)
2. 一个自己的域名，可以到万网什么的购买
3. 会点Linux基础、会点Git基础
4. 没了。。。没了。。。真没了。。。

## 二、相关工具准备
1、 VPS安装CentOS系统，建议6版本(略过)
2、 获取 `ShadowSocks` 后端源码( **需要git，没有的话自行安装** )

> 克隆(拉取) `ShadowSocks` 源码到本地
> ssh 连接VPS，执行如下命令

``` sh
# 克隆后端代码(多用户版本)
git clone -b manyuser https://github.com/mengskysama/shadowsocks-rm.git
```

3、 下载前端代码( **需要wget `yum install wget` 安装** )

``` sh
wget https://github.com/orvice/ss-panel/archive/v2.4.7.tar.gz
```

也可下载到本地再上传 [下载地址](https://github.com/orvice/ss-panel/branches)

![hexo_ss-panel_download](https://mritd.b0.upaiyun.com/markdown/hexo_ss-panel_download.png)

## 三、安装LNMP环境
1. LNMP一键安装脚本地址 [点这里](http://lnmp.org/install.html)
2. 根据教程安装好LNMP环境
3. 创建一个域名映射(站点目录)，执行 `lnmp vhost add` ，然后根据提示操作即可
4. 完成后可在 `/home/wwwroot/` 下找到对应的域名目录

## 四、安装 ShadowSocks 后端
1、移动后端源码到任意目录，一般习惯 `/usr/local/`

``` sh
mv shadowsocks-rm/shadowsocks/ /usr/local/
```

2、创建数据库

``` sh
# 登录 mysql
mysql -uroot -p       # 然后输入安装lnmp时设置的mysql密码
# 创建数据库
create database shadowsocks;
# 切换数据库
use shadowsocks;
# 创建用户
insert into mysql.user(Host,User,Password) values("localhost","shadowsocks",password("密码"));
# 刷新权限表
flush privileges;
# 用户授权
grant all privileges on shadowsocks.* to 'shadowsocks'@'localhost' identified by '密码';
# 刷新权限表
flush privileges;
```

3、导入相关SQL，创建表结构

``` sh
# 解压前端代码(前端代码下载下来后应该是个 tar.gz 格式的压缩包，执行以下命令解压它)
tar -zxvf v2.4.7.tar.gz
# 进入解压后的 sql 存放目录
cd ss-panel-2.4.7/sql/
# 登录mysql 切换数据库
mysql -ushadowsocks -p
use shadowsocks;
# 设置编码
set names utf8;
# 执行导入
source invite_code.sql;
source ss_node.sql;
source ss_reset_pwd.sql;
source ss_user_admin.sql;
source user.sql;
```

4、安装相关工具

``` sh
# 安装 pip
yum install python-setuptools && easy_install pip
# 安装 cymysql
pip install cymysql
```

5、设置数据库配置

``` sh
# 安装 vim
yum install vim
# 编辑配置文件 vim使用方法自行谷歌
vim /usr/local/shadowsocks/config.py
```

> 样例配置文件如下，其中 **使用 `aes-256-cfb` 加密需要安装其他组件，自行Google**

``` sh
import logging

#Config
MYSQL_HOST = '127.0.0.1'
MYSQL_PORT = 3306
MYSQL_USER = 'shadowsocks'
MYSQL_PASS = 'mysql密码'
MYSQL_DB = 'shadowsocks'

#if you want manage in other server you should set this value to global ip
MANAGE_PASS = 'passwd'
MANAGE_BIND_IP = '127.0.0.1'
#make sure this port is idle
MANAGE_PORT = 23333
#BIND IP
#if you want bind ipv4 and ipv6 '[::]'
#if you want bind all of ipv4 if '0.0.0.0'
#if you want bind all of if only '4.4.4.4'
SS_BIND_IP = '0.0.0.0'
SS_METHOD = 'rc4-md5'
#
LOG_ENABLE = False
LOG_LEVEL = logging.WARNING
LOG_FILE = './shadowsocks.log'
```
6、启动后端

``` sh
# 切换目录
cd /usr/local/shadowsocks/
# 后台运行
nohup python /usr/local/shadowsocks/servers.py &
```

## 五、安装 ShadowSocks 前端
1、复制 `ss-panel` 文件到网站根目录

``` sh
mv ss-panel-2.4.7/* /home/wwwroot/网站名称/
```

2、修改相关配置文件

``` sh
vim /home/wwwroot/网站名称/lib/config-simple.php
```

``` php
/* 配置样例 */
<?php
/*
 * ss-panel配置文件
 * https://github.com/orvice/ss-panel
 * Author @orvice
 * https://orvice.org
 */

//定义流量
$tokb = 1024;
$tomb = 1024*1024;
$togb = $tomb*1024;
//Define DB Connection  数据库信息
define('DB_HOST','localhost');
define('DB_USER','shadowsocks');
define('DB_PWD','密码');
define('DB_DBNAME','shadowsocks');
define('DB_CHARSET','utf8');
define('DB_TYPE','mysql');
/*
 * 下面的东西根据需求修改
 */
//define Plan
//注册用户的初始化流量
//默认5GiB
$a_transfer = $togb*5;

//签到设置 签到活的的最低最高流量,单位MB
$check_min = 1;
$check_max = 100;

//name
$site_name = "Mritd-Shadowsocks";
$site_url  = "http://域名";
/**
 * 站点盐值，用于加密密码
 * 第一次安装请修改此值，安装后请勿修改！！否则会使所有密码失效，仅限加密方式不为1的时候有效
 */
$salt = "随便填";
/*
 * 剩下的省略......
 */
```

3、重命名配置文件

``` sh
mv config-simple.php config.php
```

4、更新管理员用户名密码等信息

> 注意：下面的pass字段是你登陆后台的密码，最新版的默认管理账户的默认密码我也不知道是多少，我的方案是在 config-simple.php 里使用md5加密，然后去 [在线md5加密](http://tool.chinaz.com/tools/md5.aspx) 随便写个密码，做一个32位小写的md5，用md5后的字符串覆盖默认用户的pass，这样就能改掉密码了。另一种方案是新注册一个账户，然后这个账户在user表中的uid应该是2；把他加入到 ss\_user\_admin 表中即可使其成为管理员，再把默认的管理员删了。

``` sh
# 登录数据库
mysql-ushadowsocks -p
# 切换数据库
use shadowsocks;
# 更新管理员信息
update user set user_name='用户名',email='登录邮箱', pass='密码', passwd='ss连接密码' where uid=1;
```

5、登录后台，测试ss连接

> 管理后台默认是 `http://域名/admin`，可用刚刚创建的管理员登录测试，关于具体使用过程不再详细叙述，如遇到网站可访问，但ss无法连接的情况，请查看防火墙相关设置和ss日志。本人使用的 **ConoHa VPS** 目前速度不错，这个VPS 还需要在控制面板中设置入站端口，否则关了防火墙也没用。

> **到此 ShadowSocks 搭建结束。**

---

如果购买 **ConoHa VPS** 的话可使用这个邀请链接 [ConoHa VPS](https://www.conoha.jp/referral/?token=pVMnGJDqY5jjnek.R4GhJnoqv7zaJ2PAMh5lvfWg9PKZ0PppokI-189) 注册有优惠。

#### 如果本文对你有帮助，可以考虑用支付宝请我喝杯咖啡  ( ^_^ )

![支付宝](https://mritd.b0.upaiyun.com/markdown/zhifubao.png)
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
