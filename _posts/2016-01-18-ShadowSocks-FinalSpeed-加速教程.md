---
layout: post
title: ShadowSocks FinalSpeed 加速教程
categories: [Shadowsocks]
description: ShadowSocks FinalSpeed 加速教程
keywords: ShadowSocks,FinalSpeed
---

![ShadowSocks](https://mritd.b0.upaiyun.com/markdown/hexo_shadowsocks_logo.png)

## 一、闲聊

> 由于工作需要，爬墙是必须的，目前比较好的方式就是 `ShadowSocks`；本人也测试自己搭建过 `ShadowSocks` 服务器，但是速度并不理想；由于本身不是搞运维的，也不会玩一些高端的内核优化；所以即使用DO的服务器(以前托管个人博客的)依然很慢；最初还买了一个搬瓦工的，速度更垃圾，就一直闲置着给别人用。今天偶尔发现了这个 `FinalSpeed` 大法，测试了一下瞬间泪奔，搬瓦工 1080P 完全毫无压力啊，下面记录一下搭建教程。

---

> 项目开源地址 [Github](https://github.com/d1sm/finalspeed)，论坛地址 [第一数码](http://www.d1sm.net/)  **如有更新请及时关注**

<!--more-->

## 二、环境准备

- 1、一台能翻墙的VPS，比如搬瓦工VPS；服务器建议至少256M内存。
- 2、服务器端安装好了 SS 服务，没有请参考 [这里](http://mritd.me/2016/01/10/ShadowSocks-%E5%A4%9A%E7%94%A8%E6%88%B7%E7%89%88%E6%90%AD%E5%BB%BA%E6%95%99%E7%A8%8B/)
- 3、openvz架构只支持udp协议。服务端可以和锐速共存,互不影响。

## 三、服务器端搭建(CentOS)

> 其他系统和注意事项请参考 [http://www.d1sm.net/thread-8-1-1.html](http://www.d1sm.net/thread-8-1-1.html)

- 1、下载安装脚本

``` sh
# 安装wget
yum -y install wget
# 下载安装脚本
wget http://fs.d1sm.net/finalspeed/install_fs.sh
```

- 2、赋予可执行权限


``` sh
chmod +x install_fs.sh
```

- 3、执行安装

``` sh
./install_fs.sh
```

- 4、安装成功后如下图(自己的忘记截图了，引自论坛)

![hexo_finalspeed_install_success.jpg](https://mritd.b0.upaiyun.com/markdown/hexo_finalspeed_install_success.jpg)

## 四、客户端安装&连接

- 1、安装客户端程序 [下载地址](http://fs.d1sm.net/finalspeed/finalspeed_install1.0.exe)

> 会自动安装 Winpcap

- 2、根据实际情况设置相关参数

**设置带宽(搬瓦工测试512内存的可设置50)**

---

![hexo_finalspeed_set_bandwidth.png](https://mritd.b0.upaiyun.com/markdown/hexo_finalspeed_set_bandwidth.png)

**设置IP和加速方式(openvz只支持UPD，搬瓦工就是)**

---

![hexo_finalspeed_set_udp.png](https://mritd.b0.upaiyun.com/markdown/hexo_finalspeed_set_udp.png)

**设置加速服务器**

---

> 加速端口根据实际情况添加，加速端口即为 ss 连接的服务器端口；本地端口随便填，一般为 2000。

![hexo_finalspeed_set_server.png](https://mritd.b0.upaiyun.com/markdown/hexo_finalspeed_set_server.png)

**设置 SS 客户端**

---

> SS客户端新建一个服务器，地址为127.0.0.1，端口为你设置的本地端口，一般为2000，密码为原来账号的密码。

![hexo_finalspeed_set_ssclient.png](https://mritd.b0.upaiyun.com/markdown/hexo_finalspeed_set_ssclient.png)

- 3、切换到此服务器即可，以下为搬瓦工512，北京联通50M测试截图(以前720p卡成翔，500K顶天)。

![hexo_finalspeed_video_test.png](https://mritd.b0.upaiyun.com/markdown/hexo_finalspeed_video_test.png)
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
