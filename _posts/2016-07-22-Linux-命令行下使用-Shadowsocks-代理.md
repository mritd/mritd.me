---
layout: post
title: Linux 命令行下使用 Shadowsocks 代理
categories: [Shadowsocks]
description: Linux 命令行下使用 Shadowsocks 代理
keywords: Linux,Shadowsocks,Privoxy
---


## 一、安装 Shadowsocks

Ubuntu 使用如下命令安装即可，其他系统可使用 python 安装，具体请自行 Google

``` sh
apt-get install shadowsocks -y
```

安装完成后编辑配置文件，填写对应服务器地址

``` sh
vim /etc/shadowsocks.json
```

服务器配置样例如下

``` sh
{
    "server":"1.1.1.1",
    "server_port":8383,
    "local_address": "127.0.0.1",
    "local_port":1080,
    "password":"passwd",
    "timeout":300,
    "method":"aes-256-cfb",
    "fast_open": true,
    "workers": 1
}
```

<!--more-->

最后启动代理

``` sh
nohup sslocal -c /etc/shadowsocks.json &
```

## 二、将 Socks5 代理转化为 http 代理


socks5 代理转换成 http 代理需要借助第三方软件完成，这里使用 **privoxy**，Ubuntu 下使用如下命令安装 **privoxy**

``` sh
apt-get install privoxy -y
```

编辑配置文件

``` sh
# 先备份原配置文件
mv /etc/privoxy/config /etc/privoxy/config.bak
# 在新建一个配置文件
vim /etc/privoxy/config
```

**privoxy 配置样例如下**

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

**最后启动 privoxy，Ubuntu 16 启动命令如下**

``` sh
# 启动
systemctl start privoxy
# 查看状态
systemctl status privoxy
```

## 三、创建快捷代理命令

完成上两步配置后，即可将需要代理的软件指向 `127.0.0.1:8118` 端口即可，但是有些命令行操作并无法设置，只能通过全局代理变量 `http_proxy` 等设置，此时设置后全局都受影响，为此可以写一个代理脚本，如下

``` sh
vim /usr/local/bin/proxy
```

**脚本内容如下**

``` sh
#!/bin/bash
http_proxy=http://127.0.0.1:8118 https_proxy=http://127.0.0.1:8118 $*
```

**赋予可执行权限**

``` sh
chmod +x /usr/local/bin/proxy
```

**最后，对任何想要走代理的命令，只需要在前面加上 `proxy` 即可，样例如下**

``` sh
proxy gvm install go1.6.3
```

## 四、快速配置脚本

**最后写了一个快速设置脚本，比较简陋.....**

``` sh
#!/bin/bash

# 更新软件源
apt-get update && apt-get upgrade -y
# 安装 pip 和 privoxy
apt-get install python-pip privoxy -y
#  安装 shadowsocks
pip install shadowsocks

# 相关配置文件
sscfg="/etc/ss.json"
privoxycfg="/etc/privoxy/config"
proxycmd="/usr/local/bin/proxy"

# 创建 shadowsocks 配置样例
cat >"$sscfg"<<EOF
{
    "server":"1.1.1.1",
    "server_port":8383,
    "local_address": "127.0.0.1",
    "local_port":1080,
    "password":"passwd",
    "timeout":300,
    "method":"aes-256-cfb",
    "fast_open": true,
    "workers": 1
}
EOF

# 备份 privoxy 配置
mv $privoxycfg /etc/privoxy/config.bak

# 创建 privoxy 配置
cat >"$privoxycfg"<<EOF
# 转发地址
forward-socks5   /               127.0.0.1:1080 .
# 监听地址
listen-address  localhost:8118
# local network do not use proxy
forward         192.168.*.*/     .
forward            10.*.*.*/     .
forward           127.*.*.*/     .
EOF

# 创建代理脚本
cat >"$proxycmd"<<EOF
#!/bin/bash
http_proxy=http://127.0.0.1:8118 https_proxy=http://127.0.0.1:8118 \$*
EOF

# 增加执行权限
chmod +x $proxycmd

echo "安装完成!"
echo "shadowsocks 配置请修改 /etc/ss.json!"
echo "使用 nohup sslocal -c /etc/ss.json & 后台运行 shadowsocks!"
echo "使用 systemctl start privoxy 启动privoxy!"
echo "使用 proxy xxxx 代理指定应用!"
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
