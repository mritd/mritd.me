---
layout: post
categories: Docker
title: 樱花 Docker 免费高速翻墙教程
date: 2016-10-14 23:31:19 +0800
description: 利用免费的樱花 Docker 使用 shadowsocks 翻墙教程
keywords: shadowsocks Docker
---

> 免费梯子不多，且用亲珍惜，以下为利用樱花 Docker 翻墙教程

### 一、注册账号

首先在 [樱花 Docker 注册地址](https://app.arukas.io/) 注册一个账号

![crate_account](https://mritd.b0.upaiyun.com/markdown/xek39.jpg)

填写邮箱、账户名、密码后点击确认

![Fill_in_the_account](https://mritd.b0.upaiyun.com/markdown/jax98.jpg)

稍等片刻在邮箱中点击验证连接即可

![Verify_the_mailbox](https://mritd.b0.upaiyun.com/markdown/pewta.jpg)

### 二、创建容器

注册号账号以后，登录控制台，点击 `Create` 创建容器 

![login](https://mritd.b0.upaiyun.com/markdown/3ai5c.jpg)

然后填写相关信息，如下

![set_container](https://mritd.b0.upaiyun.com/markdown/0dkkc.jpg)

**其中 `Image` 填写 `mritd/shadowsocks`，表示使用哪个镜像模板创建容器，关于 Docker 镜像含义等请自行 Google，`mritd/shadowsocks` 这个镜像是我维护的一个 shadowsocks 镜像，如果想使用其他 shadowsocks 可从 [Docker Hub](https://hub.docker.com/) 上自行搜索**

**其他各选项含义如下:**

- Instances: 启动多少个实例，一般 1 个就够用
- Memory: 容器使用的内存大小，256 也可以
- Endpoint: 暴露端口，可不填
- Port: 容器对外提供服务的端口，默认为 5000
- ENV: 是否使用环境变量，`mritd/shadowsocks` 镜像支持使用环境变量设置 shadowsocks 相关参数，这里可以省略
- CMD: 要执行容器中的命令，**首部必须填写 `/root/entrypoint.sh`，后面其他参数可以省略，但是一般会加上 `-k` 设置 shadowsocks 的密码，关于都能用哪些参数和参数意义请看考 [Docker Hub](https://hub.docker.com/r/mritd/shadowsocks/) 上的说明(shadowsocks 默认加密方式为 aes-256-cfb)**

最后点击创建即可

![create_container](https://mritd.b0.upaiyun.com/markdown/e2d1j.jpg)

### 三、启动并连接

创建完成后会回到主页列表，在主页列表中可以看到刚刚创建的容器，此时容器还没有启动，点击启动按钮即可

![start_container](https://mritd.b0.upaiyun.com/markdown/b9nts.jpg)

创建时间稍稍有点长，此时列表中容器变为黄色，点击容器名称后可看到如下所示

![create_detail](https://mritd.b0.upaiyun.com/markdown/m093z.jpg)

稍等片刻后容器变为绿色，并为 `Running` 状态表示创建完成

![create_success](https://mritd.b0.upaiyun.com/markdown/ybwqj.jpg)

**容器运行成功后会显示如下信息，其中包含了 shadowsocks 链接地址**

![ss_detail](https://mritd.b0.upaiyun.com/markdown/czjyx.jpg)

最后使用客户端连接即可

### 四、高级扩展

樱花 Docker 提供了一个 CLI 命令行工具，可以通过相关 API Token 实现命令行下查询、创建 Docker 容器等操作，CLI 使用需要先创建 API Token，点击左侧按钮即可

![crate_api_token](https://mritd.b0.upaiyun.com/markdown/ol0lv.jpg)

创建成功后将 Token 声明道环境变量中，并使用 CLI 工具即可实现命令行下创建 shadowsocks 镜像，关于 CLI 使用说明和下载地址请移步 [Github](https://github.com/arukasio/cli) 查看

### 五、其他说明

关于镜像使用在 [Docker Hub](https://hub.docker.com/r/mritd/shadowsocks/) 页面详细描述了镜像参数，具体可以参考一下

**镜像可以理解为一个微型 Linux 系统，其中 CMD 选项代表要执行系统中的那个命令，填写 `/root/entrypoint.sh` 是因为制作镜像时指定了 shadowsocks 通过这个脚本启动，后面的 `-k` 等参数会被这个脚本执行，脚本支持哪些参数可以从上面的 Docker Hub 页面获取**

**镜像支持以环境变量的方式设置密码等，环境变量表现为一个 `key-value` (键值对) 形式，也就是说 CMD 其实可以只写 `/root/entrypoint.sh` 不加 `-k` 参数，而通过勾选 `ENV` 选项并添加一个 `PASSWORD=Your-PassWord` 环境变量来设置**

**目前镜像内集成了 kcptun，但是由于 kcptun 自定义设置需要挂载配置文件，所以在樱花 Docker 中还无法使用，后期准备支持环境变量设置**
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
