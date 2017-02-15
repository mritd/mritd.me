---
layout: post
title: JetBrains 系列激活教程(离线 Server)
categories: [JetBrains]
description: JetBrains 系列激活教程(离线 Server)
keywords: JetBrains,IDEA
---

![JetBrains_logo](https://mritd.b0.upaiyun.com/markdown/JetBrains_Drive_to_develop.png)

## 一、前言
> 激活采用离线服务器激活方式，如有网的情况下可直接采用 [http://idea.lanyus.com/](http://idea.lanyus.com/) 的激活方法。经济许可的情况下请购买正版 [https://www.jetbrains.com/idea/buy/](https://www.jetbrains.com/idea/buy/)。

<!--more-->

## 二、激活教程

### 工具下载

首先下载激活工具，地址：[百度网盘](http://pan.baidu.com/s/1dDYCB5n)  密码：ns3u 然后解压的任意目录

### Windows 下激活

复制解压后的 `windows` 文件夹到任意目录，以管理员身份运行 CMD 执行以下命令(文件位置自己改)：

``` sh
sc create idea_license_server binPath="D:\Work\windows\jetbrains_license_server\jetbrains_license_server.exe runserver localhost:9123" start=auto
```

此时在系统服务列表中应该存在名称为 `idea_license_server` 的服务；然后重启电脑。

最后激活时选择服务器激活，地址填写 `http://127.0.0.1:9123`，到此激活完成。

![hexo_idea_license_server_win](https://mritd.b0.upaiyun.com/markdown/hexo_idea_license_server_win.png)


### Linux/Mac 下激活

复制解压后的 `linux-mac` 文件夹到任意目录，执行以下命令(**系统需要安装 Python**)：

``` sh
cd linux-mac
# 木有pip 的自己安装
pip install -r requirements.txt
# 开启服务器
python ./jetbrains_license_server/manage.py runserver localhost:9123
```

激活时同上，不做阐述。

## 三、说明

**Windows 执行 sc 那条命令后已经将其安装为系统服务，开机默认就会启动，所以可以保持激活。Linux/Mac 直接开启的服务器，并未设置开机启动和后台运行，可能造成一段时间需要重复激活。**

**Linux/Mac 解决办法：将那条启动服务器的命令改成后台启动，如下：**

``` sh
nohup python ./jetbrains_license_server/manage.py runserver localhost:9123 &
```

**这时可以保持激活服务器后台一直运行，但无法开机启动，设置开机启动的办法有很多，最简单的就是将这条命令写到 `~/.bashrc` 等配置文件中，路子多的是，也很野.....自己找吧，我比较穷，买不起Mac......**
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
