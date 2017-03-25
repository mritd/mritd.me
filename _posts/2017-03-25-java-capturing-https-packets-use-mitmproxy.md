---
layout: post
categories: Java Linux
title: Java 配合 mitmproxy HTTPS 抓包调试
date: 2017-03-25 12:42:21 +0800
description: Java 配合 mitmproxy HTTPS 抓包调试
keywords: Java 抓包 mitmproxy
---

> 今天对接接口，对方给的 Demo 和已有项目用的 HTTP 工具不是一个；后来出现人家的好使，我的死活不通的情况；无奈之下开始研究 Java 抓包，所以怕忘了记录一下......

### 一、mitmproxy 简介

mitmproxy 是一个命令行下的强大抓包工具，可以在命令行下抓取 HTTP(S) 数据包并加以分析；对于 HTTPS 抓包，首先要在本地添加 mitmproxy 的根证书，然后 mitmproxy 通过以下方式进行抓包：

![mitmproxy1](https://mritd.b0.upaiyun.com/markdown/x7lir.jpg)

- 1、客户端发起一个到 mitmproxy 的连接，并且发出HTTP CONNECT 请求
- 2、mitmproxy作出响应(200)，模拟已经建立了CONNECT通信管道
- 3、客户端确信它正在和远端服务器会话，然后启动SSL连接。在SSL连接中指明了它正在连接的主机名(SNI)
- 4、mitmproxy连接服务器，然后使用客户端发出的SNI指示的主机名建立SSL连接
- 5、服务器以匹配的SSL证书作出响应，这个SSL证书里包含生成的拦截证书所必须的通用名(CN)和服务器备用名(SAN)
- 6、mitmproxy生成拦截证书，然后继续进行与第３步暂停的客户端SSL握手
- 7、客户端通过已经建立的SSL连接发送请求，
- 8、mitmproxy通过第４步建立的SSL连接传递这个请求给服务器

### 二、抓包配置

#### 2.1、安装 mitmproxy

mitmproxy 是由  python 编写的，所以直接通过 pip 即可安装，mac 下也可使用 brew 工具安装

``` sh
# mac
brew install mitmproxy
# Linux
pip install mitmproxy
# CentOS 安装时可能会出现 "致命错误：libxml/xmlversion.h：没有那个文件或目录"
# 需要安装如下软件包即可解决
yum install libxml2 libxml2-devel libxslt libxslt-devel -y
```

#### 2.2、HTTPS 证书配置

首先由于 HTTPS 的安全性，直接抓包是什么也看不到的；所以需要先在本地配置 mitmproxy 的根证书，使其能够解密 HTTPS 流量完成一个中间人的角色；证书下载方式需要先在本地启动 mitmproxy，然后通过设置本地连接代理到 mitmproxy 端口，访问 `mitm.it` 即可，具体可查看 [官方文档](https://mitmproxy.org/doc/certinstall.html)

**首先启动 mitmproxy**

``` sh
mitmproxy -p 4000 --no-mouse
```

**浏览器通过设置代理访问 mitm.it**

![access](https://mritd.b0.upaiyun.com/markdown/unrnc.jpg)


选择对应平台并将其证书加入到系统信任根证书列表即可；对于 Java 程序来说可能有时候并不会生效，所以必须 **修改 keystore**，修改如下


``` sh
# Linux 一般在 JAVA_HOME/jre/lib/security/cacerts 下
# Mac 在 /Library/Java/JavaVirtualMachines/JAVA_HOME/Contents/Home/jre/lib/security/cacerts
sudo keytool -importcert -alias mitmproxy -keystore /Library/Java/JavaVirtualMachines/jdk1.8.0_77.jdk/Contents/Home/jre/lib/security/cacerts -storepass changeit -trustcacerts -file ~/.mitmproxy/mitmproxy-ca-cert.pem
```

#### 2.4、Java 抓包调试

JVM 本身在启动时就可以设置代理参数，也可以通过代码层设置；以下为代码层设置代理方式

``` sh
public void beforeTest(){
    logger.info("设置抓包代理......");
    System.setProperty("https.proxyHost", "127.0.0.1");
    System.setProperty("https.proxyPort", "4000");
}
```

**然后保证在发送 HTTPS 请求之前此代码执行即可，以下为抓包示例**

![zhuabao](https://mritd.b0.upaiyun.com/markdown/kuzhd.jpg)

通过方向键+回车即可选择某个请求查看报文信息

![detail](https://mritd.b0.upaiyun.com/markdown/vfifu.jpg)

### 三、Java 其他代理设置

Java 代理一般可以通过 2 种方式设置，一种是通过代码层，如下

``` sh
// HTTP 代理，只能代理 HTTP 请求
System.setProperty("http.proxyHost", "127.0.0.1");
System.setProperty("http.proxyPort", "9876");
 
// HTTPS 代理，只能代理 HTTPS 请求
System.setProperty("https.proxyHost", "127.0.0.1");
System.setProperty("https.proxyPort", "9876");

// 同时支持代理 HTTP/HTTPS 请求
System.setProperty("proxyHost", "127.0.0.1");
System.setProperty("proxyPort", "9876");
 
// SOCKS 代理，支持 HTTP 和 HTTPS 请求
// 注意：如果设置了 SOCKS 代理就不要设 HTTP/HTTPS 代理
System.setProperty("socksProxyHost", "127.0.0.1");
System.setProperty("socksProxyPort", "1080");
```

另一种还可以通过 JVM 启动参数设置

``` sh
-DproxyHost=127.0.0.1 -DproxyPort=9876
```

本文参考：

- [Java 和 HTTP 的那些事](http://www.aneasystone.com/archives/2015/12/java-and-http-using-proxy.html)
- [一步一步教你https抓包](http://blog.csdn.net/qq_30513483/article/details/53258637)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
