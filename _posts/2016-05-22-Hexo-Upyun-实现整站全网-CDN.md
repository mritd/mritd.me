---
layout: post
title: Hexo+Upyun 实现整站全网 CDN
categories: [Hexo]
description: Hexo+Upyun 实现整站全网 CDN
keywords: Hexo,CDN,upyun,整站,全网
---

## 一、upyun 设置

upyun 提供存储型服务，即将任意文件放置 CDN 中，通过其进行全网加速；既然 Hexo 为静态博客，那么理所当然可以将整站文件放入 upyun CDN，同时 upyun  CDN 支持绑定自定义 CNAME 域名，结合两者即可实现无服务器的整站全网 CDN 加速；以下为 upyun 相关设置。

### 1、创建服务

创建 upyun 账号，以及充值省略，首先自定义一个服务名

![hexo_upyun_createservice1](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_createservice1.png)

<!--more-->

**服务类型一定要选择存储型服务，否则将无法访问域名自动返回根目录下的 index.html**

![hexo_upyun_createservice2](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_createservice2.png)

授权账户可任意设置，最后完成即可

### 2、上传文件到 upyun

copy hexo 网站的 `public` 目录下所有文件到新创建的空间，**upyun 新建服务后会给你一个 FTP 地址，根据提示使用 FTP 工具登录即可**

**FTP 连接地址如下**
![hexo_upyun_uploadfile1.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_uploadfile1.jpg)

**文件上传截图如下**
![hexo_upyun_uploadfile3.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_uploadfile2.jpg)

## 二、域名绑定

### 1、测试部署是否成功

上传文件后即可通过 upyun 默认提供的域名测试网站是否布置成功，默认域名查看如下

![hexo_upyun_testhexocdn1.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_testhexocdn1.png)


**访问域名测试是否成功**
![hexo_upyun_testhexocdn2.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_testhexocdn2.jpg)


### 2、绑定自定义域名

首先选择功能配置中的域名绑定

![hexo_upyun_binding_domainname1.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_binding_domainname1.png)

![hexo_upyun_binding_domainname2.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_binding_domainname2.png)

然后填入想要绑定的域名，并获取该域名需要解析的 CNAME 地址

![hexo_upyun_binding_domainname3.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_binding_domainname3.png)

最后在域名提供商处设置 CNAME 解析到该给定的域名

![hexo_upyun_binding_domainname4.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_binding_domainname4.png)

**到此，便实现了整站的全网 CDN 加速，最后要注意，天朝你懂的，域名必须备案，否则就会像我这样(fuck GFW)**

![hexo_upyun_website_gfw.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_website_gfw.png)

**最后给一张全网测试访问速度图，来自奇云测**

![hexo_upyun_testwebsite.png](https://mritd.b0.upaiyun.com/markdown/hexo_upyun_testwebsite.png)
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
