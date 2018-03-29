---
layout: post
title: Unix 平台下各种加速配置
date: 2018-03-28 22:09:57 +0800
categories: Linux
description: Unix 平台下各种加速配置
keywords: Unix,proxy,socks5,gcr.io,docker,SwitchyOmega,proxychains-ng
catalog: true
multilingual: false
tags: Linux
---

> 本文主要阐述在 \*Uinx 平台下，各种常用开发工具的加速配置，**加速前提是你需要有一个能够加速的 socks5 端口，常用工具请自行搭建**；本文档包括 docker、terminal、git、chrome 常用加速配置，其他工具可能后续补充

### 一、加速类型

目前大部分工具在原始版本都是只提供 socks5 加速，常用平台一些工具已经支持手动设置加速端口，如 telegram、mega 同步客户端等等；但是某些工具并不支持 socks5，通用的加速目前各个平台只支持 http、https 设置(包括 terminal 下)；**综上所述，在设置之前你至少需要保证有一个 socks5 端口能够进行加速，然后根据以下教程将 socks5 转换成 http，最后配置各个软件或系统的加速方式为 http，这也是我们常用的某些带有图形化客户端实际的背后实现**

### 二、socks5 to http

sock5 转 http 这里采用 privoxy 进行转换，根据各个平台不同，安装方式可能不同，主要就是包管理器的区别，以下只列举 Ubuntu、Mac 下的命令，其他平台自行 Google

- Mac: `brew install privoxy`
- Ubuntu: `apt-get -y install privoxy`

安装成功后，需要修改配置以指定 socks5 端口以及不代理的白名单，配置文件位置如下:

- Mac: `/usr/local/etc/privoxy/config`
- Ubuntu: `/etc/privoxy/config`

在修改之前请备份默认配置文件，这是个好习惯，备份后修改内容如下:

``` sh
# 转发地址
forward-socks5   /               127.0.0.1:1080 .
# 监听地址
listen-address  localhost:8118
# local network do not use proxy
forward         192.168.*.*/     .
forward            10.*.*.*/     .
forward           127.*.*.*/     .
```

**其中 `127.0.0.1:1080` 为你的 socks5 ip 及 端口，`localhost:8118` 为你转换后的 http 监听地址和端口**；配置完成后启动 privoxy 即可，启动命令如下:

- Mac: `brew services start privoxy`
- Ubuntu: `systemctl start privoxy`

### 三、Docker 加速拉取 gcr.io 镜像

对于 docker 来说，terminal 下执行 `docker pull` 等命令实质上都是通过调用 docker daemon 操作的；而 docker daemon 是由 systemd 启动的(就目前来讲，别跟我掰什么 service start...)；对于 docker daemon 来说，一旦它启动以后就不会再接受加速设置，所以我们需要在 systemd 的 service 配置中配置它的加速。

目前 docker daemon 接受标准的终端加速设置(读取 `http_proxy`、`https_proxy`)，同时也支持 socks5 加速；为了保证配置清晰方便修改，这里采用创建单独配置文件的方式来配置 daemon 的 socks5 加速，配置脚本如下(Ubuntu、CentOS):

``` sh
#!/bin/bash

set -e

OS_TYPE=$1
PROXY_ADDRESS=$2

if [ "${PROXY_ADDRESS}" == "" ]; then
    echo -e "\033[31mError: PROXY_ADDRESS is blank!\033[0m"
    echo -e "\033[32mUse: sudo $0 centos|ubuntu 1.2.3.4:1080\033[0m"
    exit 1
fi

if [ "${OS_TYPE}" == "" ];then
    echo -e "\033[31mError: OS_TYPE is blank!\033[0m"
    echo -e "\033[32mUse: sudo $0 centos|ubuntu\033[0m"
    exit 1
elif [ "${OS_TYPE}" == "centos" ];then
    mkdir /etc/systemd/system/docker.service.d || true
    tee /etc/systemd/system/docker.service.d/socks5-proxy.conf <<-EOF
[Service]
Environment="ALL_PROXY=socks5://${PROXY_ADDRESS}"
EOF
elif [ "${OS_TYPE}" == "ubuntu" ];then
    mkdir /lib/systemd/system/docker.service.d || true
    tee /lib/systemd/system/docker.service.d/socks5-proxy.conf <<-EOF
[Service]
Environment="ALL_PROXY=socks5://${PROXY_ADDRESS}"
EOF
fi

systemctl daemon-reload
systemctl restart docker
systemctl show docker --property Environment
```

将该脚本内容保存为 `docker_proxy.sh`，终端执行 `bash docker_proxy.sh ubuntu 1.2.3.4:1080` 即可(自行替换 socks5 地址)；脚本实际上很简单，就是创建一个与 `docker.service` 文件同级的 `docker.service.d` 目录，然后在里面写入一个 `socks5-proxy.conf`，配置内容只有两行:

``` sh
[Service]
Environment="ALL_PROXY=socks5://1.2.3.4:1080
```

这样 systemd 会自动读取，只需要 reload 一下，然后 restart docker daemon 即可，此后  docker 就可以通过加速端口直接 pull `gcr.io` 的镜像；**注意: 配置加速后，docker 将无法 pull 私服镜像(一般私服都是内网 DNS 解析)，但是不会影响容器启动以及启动后的容器中的网络**

### 四、Chrome 加速访问

对于 Chrome 浏览器来说，目前有比较好的插件实现用来配置根据策略的加速访问；这里使用的插件为 `SwitchyOmega`

#### 4.1、SwitchyOmega 下载

默认情况下 `SwitchyOmega` 可以通过 Chrome 进行在线安装，但是众所周知的原因这是不可能的，不过国内有一些网站提供代理下载 Chrome 扩展的服务，如 `https://chrome-extension-downloader.com`、`http://yurl.sinaapp.com/crx.php`，这些网站只需要提供插件 ID 即可帮你下载下来；**`SwitchyOmega` 插件的 ID 为 `padekgcemlokbadohgkifijomclgjgif`，注意下载时不要使用 chrome 下载，因为他自身的防护机制会阻止你下载扩展程序**；下载后打开 chrome 的扩展设置页，将 crx 文件拖入安装即可，如下所示:

![install chrome plugin](https://mritd.b0.upaiyun.com/markdown/zruoq.png)

#### 4.2、SwitchyOmega 配置

SwitchyOmega 安装成功后在 Chrome 右上角有显示，右键点击该图标，进入选项设置后如下所示:

![SwitchyOmega detail](https://mritd.b0.upaiyun.com/markdown/ouh48.png)

默认情况下左侧只有两个加速模式，一个叫做 `proxy` 另一个叫做 `autoproxy`；根据加速模式不同 SwitchyOmega 在浏览网页时选择的加速通道也不同，不同的加速方式可以通过点击 **新建情景模式** 按钮创建，下面介绍一下常用的两种情景模式:

**代理服务器:** 这种情景模式创建后需要填写一个代理地址，该地址可以是 http(s)/socks5(4) 类型；创建成功后，浏览器右上角切换到该情景模式，**浏览器访问所有网页的流量全部通过该代理地址发出**，不论你是访问百度还是 Google
 
 ![create test proxy1](https://mritd.b0.upaiyun.com/markdown/idbi4.png)
 
 ![create test proxy2](https://mritd.b0.upaiyun.com/markdown/52m7b.png)
 
**自动切换模式:** 这种情景模式并不需要填写实际的代理地址，而是需要填写一些规则；创建完成后插件中选择此种情景模式时，浏览器访问所有网页流量会根据填写的规则自动路由，然后选择合适的代理情景模式；可以实现智能切换代理
 
 ![create test auto proxy1](https://mritd.b0.upaiyun.com/markdown/7u6mv.png)
 
 ![create test auto proxy2](https://mritd.b0.upaiyun.com/markdown/m5x36.png)
 
 
综上所述，首先应该创建(或者修改默认的 proxy 情景模式)一个代理服务器的情景模式，然后填写好你的加速 IP 和对应的协议端口；接下来在浏览器中切换到该情景模式尝试访问 kubenretes.io 等网站测试加速效果；成功后再次新建一个自动切换情景模式，**保证 `规则列表规则` 一栏后面的下拉列表对应到你刚刚创建的代理服务器情景模式，`默认情景模式` 后面的下拉列表对应到直接连接情景模式，然后点击下面的 `添加规则列表` 按钮，选择 `AutoProxy` 单选框，`规则列表网址` 填写 `https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt`(这是一个开源项目收集的需要加速的网址列表)**；最后在浏览器中切换到自动切换情景模式，然后访问 kubernetes.io、baidu.com 等网站测试是否能自动切换情景模式

### 五、Terminal 加速

#### 5.1、脚本方式

对于终端下的应用程序，百分之九十的程序都会识别 `http_proxy` 和 `https_proxy` 两个变量；所以终端加速最简单的方式就是在执行命令前声明这两个变量即可，为了方便起见也可以写个小脚本，示例如下:

``` sh
sudo tee /usr/local/bin/proxy <<-EOF
#!/bin/bash
http_proxy=http://1.2.3.4:8118 https_proxy=http://1.2.3.4:8118 \$*
EOF

sudo chmod +x /usr/local/bin/proxy
```

将上面的地址自行更换成你的 http 加速地址后，终端运行 `proxy curl ip.cn` 即可测试加速效果

#### 5.2、proxychains-ng

proxychains-ng 是一个终端下的工具，它可以 hook libc 下的网络相关方法实现加速效果；目前支持后端为 http(s)/socks5(4a)，前段协议仅支持对 TCP 加速；

Mac 下安装方式:

``` sh
brew install proxychains-ng
```

Ubuntu 等平台下需要手动编译安装:

``` sh
# 安装编译依赖
apt-get -y install gcc make git

# 下载源码
git clone https://github.com/rofl0r/proxychains-ng.git

# 编译安装
cd /proxychains-ng
./configure --prefix=/usr --sysconfdir=/etc
sudo make install
sudo make install-config
```

安装完成后编辑配置使用即可，Mac 下配置位于 `/usr/local/etc/proxychains.conf`，Ubuntu 下配置位于 `/etc/proxychains.conf`；配置修改如下:

``` sh
# 主要修改 [ProxyList] 下的加速地址
[ProxyList]
socks5 1.2.3.4 1080
```

然后命令行使用 `proxychains4 curl ip.cn` 测试即可

### 六、Git 加速

目前 Git 的协议大致上只有三种 `https`、`ssh` 和 `git`，对于使用 `https` 方式进行 clone 和 push 操作时，可以使用第五部分 Terminal 加速方案即可实现对 Git 的加速；对于 `ssh`、`git` 协议，实际上都在调用 ssh 协议相关进行通讯(具体细节请 Google，这里的描述可能不精准)，此时同样可以使用 `proxychains-ng` 进行加速，**不过需要注意 `proxychains-ng` 要自行编译安装，同时 `./configure` 增加 `--fat-binary` 选项，具体参考 [GitHub Issue](https://github.com/rofl0r/proxychains-ng/issues/109)**；`ssh`、`git` 由于都在调用 ssh 协议进行通讯，所以实际上还可以通过设置 ssh 的 `ProxyCommand` 来实现，具体操作如下:

``` sh
sudo tee /usr/local/bin/proxy-wrapper <<-EOF
#!/bin/bash
nc -x1.2.3.4:1080 -X5 \$*
#connect-proxy -S 1.2.3.4:1080 \$*
EOF

sudo chmod +x /usr/local/bin/proxy-wrapper

sudo tee ~/.ssh/config <<-EOF
Host github.com
    ProxyCommand /usr/local/bin/proxy-wrapper '%h %p'
EOF
```

需要注意: **nc 命令是 netcat-openbsd 版本，Mac 下默认提供，Ubuntu 下需要使用 `apt-get install -y netcat-openbsd` 安装；CentOS 没有 netcat-openbsd，需要安装 EPEL 源，然后安装 connect-proxy 包，使用 connect-proxy 命令替代**




转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
