---
layout: post
categories: Linux
title: 利用 frp 进行内网穿透
date: 2017-01-21 14:45:42 +0800
description: 记录使用 frp 工具进行内网穿透的过程
keywords: Linux frp
---

> 最近新入了一台小主机，家里还有个树莓派，索性想通过小主机跑点东西，然后通过外网访问家里的设备；不过鉴于大天朝内网环境，没有公网 IP 并且多层路由的情况下只能选择使用内网穿透方案，以下记录了一下使用 frp 进行内网穿透的过程

### 一、内网穿透原理

简单地说，内网穿透依赖于 NAT 原理，根据 NAT 设备不同大致可分为以下 4 大类(前3种NAT类型可统称为cone类型)：

- 全克隆(Full Cone)：NAT 把所有来自相同内部 IP 地址和端口的请求映射到相同的外部 IP 地址和端口上，任何一个外部主机均可通过该映射反向发送 IP 包到该内部主机
- 限制性克隆(Restricted Cone)：NAT 把所有来自相同内部 IP 地址和端口的请求映射到相同的外部 IP 地址和端口；但是，只有当内部主机先给 IP 地址为 X 的外部主机发送 IP 包时，该外部主机才能向该内部主机发送 IP 包
- 端口限制性克隆(Port Restricted Cone)：端口限制性克隆与限制性克隆类似，只是多了端口号的限制，即只有内部主机先向 IP 地址为 X，端口号为 P 的外部主机发送1个 IP 包,该外部主机才能够把源端口号为 P 的 IP 包发送给该内部主机
- 对称式NAT(Symmetric NAT)：这种类型的 NAT 与上述3种类型的不同，在于当同一内部主机使用相同的端口与不同地址的外部主机进行通信时， NAT 对该内部主机的映射会有所不同；对称式 NAT 不保证所有会话中的私有地址和公开 IP 之间绑定的一致性；相反，它为每个新的会话分配一个新的端口号；导致此种 NAT 根本没法穿透

内网穿透的作用就是利用以上规则，创建一条从外部服务器到内部设备的 "隧道"，具体的 NAT 原理等可参考 [内网打洞](http://www.cnblogs.com/eyye/archive/2012/10/23/2734807.html)、[网络地址转换NAT原理](http://blog.csdn.net/hzhsan/article/details/45038265)

### 二、环境准备

实际上根据以上 NAT 规则，基本上大部分家用设备和运营商上级路由等都在前三种规则之中，所以只需要借助成熟的内网穿透工具即可，以下为本次穿透环境

- 最新版本 frp
- 一台公网 VPS 服务器
- 内网一台服务器，最好 Linux 系统


### 三、服务端搭建

服务器作为公网访问唯一的固定地址，即作为 server 端；内网客户端作为 client 端，会主动向 server 端创建连接，此时再从 server 端反向发送数据即可实现内网穿透

``` sh
# 下载 frp 并解压
wget https://github.com/fatedier/frp/releases/download/v0.9.3/frp_0.9.3_linux_amd64.tar.gz
tar -zxvf frp_0.9.3_linux_amd64.tar.gz
cd frp_0.9.3_linux_amd64
```

编辑 `frps.ini` 如下

``` sh
# 通用配置段
[common]
# frp 监听地址
bind_addr = 0.0.0.0
bind_port = 7000

# 如果需要代理 web(http) 服务，则开启此端口
vhost_http_port = 4080
vhost_https_port = 4443

# frp 控制面板
dashboard_port = 7500
dashboard_user = admin
dashboard_pwd = admin

# 默认日志输出位置(这里输出到标准输出)
log_file = /dev/stdout
# 日志级别，支持: debug, info, warn, error
log_level = info
log_max_days = 3

# 是否开启特权模式(特权模式下，客户端更改配置无需更新服务端)
privilege_mode = true
# 授权 token 建议随机生成
privilege_token = HE7qTtW8Lg83UDKY
# 特权模式下允许分配的端口(避免端口滥用)
privilege_allow_ports = 4000-50000

# 心跳检测超时
# heartbeat_timeout = 30

# 后端连接池最大连接数量
max_pool_count = 100

# 口令超时时间
authentication_timeout = 900

# 子域名(特权模式需下将 *.domain.com 解析到公网服务器)
subdomain_host = domain.com

# 开启 ssh 穿透(可通过外网链接内网 ssh)
[ssh]
type = tcp
auth_token = M4P2xsH6RuUkbP9d
bind_addr = 0.0.0.0
listen_port = 6000

# 开启 dns 查询穿透(个人用不上)
#[dns]
#type = udp
#auth_token = M4P2xsH6RuUkbP9d
#bind_addr = 0.0.0.0
#listen_port = 5353
```

**其他具体配置说明请参考frp [ README](https://github.com/fatedier/frp/blob/master/README_zh.md) 文档**

设置完成后执行 `./frps -c frps.ini` 启动即可

### 四、客户端配置

客户端作为发起链接的主动方，只需要正确配置服务器地址，以及要映射客户端的哪些服务端口等即可

``` sh
# 下载 frp 并解压
wget https://github.com/fatedier/frp/releases/download/v0.9.3/frp_0.9.3_linux_amd64.tar.gz
tar -zxvf frp_0.9.3_linux_amd64.tar.gz
cd frp_0.9.3_linux_amd64
```

编辑 `frpc.ini` 文件

``` sh
# 通用配置
[common]
# 服务端地址及端口
server_addr = domain.com
server_port = 7000


log_file = /dev/stdout
log_level = info
log_max_days = 3

# 授权 token，必须与服务端保持一致方可实现映射
auth_token = ouRRXE4tk69oNZ6f

# 特权模式 token，同样要与服务端一致
privilege_token = VfJiyhDVJ38t7Qu6

# 心跳检测
# heartbeat_interval = 10
# heartbeat_timeout = 30

# 将本地 ssh 映射到服务器
[ssh]
type = tcp
local_ip = 127.0.0.1
local_port = 22
# 是否开启加密(流量加密，应对防火墙)
use_encryption = true
# 是否开启压缩
use_gzip = true

# dns 用不到
#[dns]
#type = udp
#local_ip = 114.114.114.114
#local_port = 53

# 发布本地 web 服务
[web01]
type = http
local_ip = 127.0.0.1
local_port = 8000
# 是否启用特权模式(特权模式下服务端无需配置)
privilege_mode = true
use_encryption = true
use_gzip = true
# 连接数量
pool_count = 20
# 是否开启密码访问
#http_user = admin
#http_pwd = admin

# 子域名，当服务端开启特权模式，并且将 "*.domain.com" 解析到服务端 IP后，
# 客户端在选项(privilege_mode)中声明当前映射为特权模式时，服务器端就会
# 给于一个 "subdomain.domain.com" 映射，此示例将在服务端开一个
# "http://test.domain.com/:4080" 的服务映射到内网 8000 端口上
subdomain = test
```

最后使用 `./frpc -c frpc.ini` 启动即可

### 五、测试

服务端和客户端同时开启完成后，即可访问 `http://domain.com:7500` 进入 frp 控制面板，如下

![dashboard](https://mritd.b0.upaiyun.com/markdown/1d8pq.jpg)

此时通过 `ssh root@domain.com -p 6000` 即可连接到内网服务器，通过访问 `http://test.domain.com:4080` 即可访问内网发布的位于 `8000` 端口服务

### 六、Systemd 管理

在较新的 Linux 系统中一经采用 Systemd 作为系统服务管理工具，以下为服务端作为服务方式运行的方式

``` sh
# 复制文件
cp frps /usr/local/bin/frps
mkdir /etc/frp
cp frps.ini /etc/frp/frps.ini

# 编写 frp service 文件，以 centos7 为例
vim /usr/lib/systemd/system/frps.service
# 内容如下
[Unit]
Description=frps
After=network.target

[Service]
TimeoutStartSec=30
ExecStart=/usr/local/bin/frps -c /etc/frp/frps.ini
ExecStop=/bin/kill $MAINPID

[Install]
WantedBy=multi-user.target

# 启动 frp 并设置开机启动
systemctl enable frps
systemctl start frps
systemctl status frps
```

客户端与此类似，这里不再重复编写，更多详细设置(如代理 https 等)请参考 frp 官方文档



转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
