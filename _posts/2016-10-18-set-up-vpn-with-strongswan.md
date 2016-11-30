---
layout: post
categories: Linux
title: StrongSwan 搭建 VPN
date: 2016-10-18 00:14:04 +0800
description: 记录使用 StrongSwan 创建 VPN 的过程
keywords: StrongSwan VPN
---

> 由于工作需要，记录一下使用 StrongSwan 搭建 VPN 的过程，支持 L2TP、IKEv2 PSK/CERT、IPsec 连接，基本上兼容大部分设备

### 一、环境准备

基本环境如下

- CentOS 7 X64
- StrongSwan 5.5

### 二、搭建 VPN

#### 2.1、安装依赖

以下采用源码编译安装，需要安装编译依赖环境

``` sh
yum install -y gmp-devel xl2tpd module-init-tools gcc openssl-devel
```

#### 2.2、编译安装

首先下载源码

``` sh
wget https://download.strongswan.org/strongswan-5.5.0.tar.gz -O /tmp/strongswan-5.5.0.tar.gz
```

解压并编译安装

``` sh
cd /tmp && tar -zxvf strongswan-5.5.0.tar.gz
cd /tmp/strongswan-5.5.0 && 
./configure --prefix=/usr --sysconfdir=/etc \
		--enable-eap-radius \
		--enable-eap-mschapv2 \
		--enable-eap-identity \
		--enable-eap-md5 \
		--enable-eap-mschapv2 \
		--enable-eap-tls \
		--enable-eap-ttls \
		--enable-eap-peap \
		--enable-eap-tnc \
		--enable-eap-dynamic \
		--enable-xauth-eap \
		--enable-openssl \
	&& make -j \
	&& make install
```

#### 2.3、基础配置

StrongSwan 的配置主要为 `ipsec.conf`、`strongswan.conf`、`xl2tpd.conf`、`options.xl2tpd` 这四个配置文件，以下为四个配置文件样例

##### 2.3.1、ipsec.conf

``` sh
# ipsec.conf - strongSwan IPsec configuration file

config setup
	uniqueids=no
	charondebug="cfg 2, dmn 2, ike 2, net 0"

conn %default
	dpdaction=clear
	dpddelay=300s
	rekey=no
	left=%defaultroute
	leftfirewall=yes
	right=%any
	ikelifetime=60m
	keylife=20m
	rekeymargin=3m
	keyingtries=1
	auto=add

#######################################
# L2TP Connections
#######################################

conn L2TP-IKEv1-PSK
	type=transport
	keyexchange=ikev1
	authby=secret
	leftprotoport=udp/l2tp
	left=%any
	right=%any
	rekey=no
	forceencaps=yes

#######################################
# Default non L2TP Connections
#######################################

conn Non-L2TP
	leftsubnet=0.0.0.0/0
	rightsubnet=10.0.0.0/24
	rightsourceip=10.0.0.0/24

#######################################
# EAP Connections
#######################################

# This detects a supported EAP method
conn IKEv2-EAP
	also=Non-L2TP
	keyexchange=ikev2
	eap_identity=%any
	rightauth=eap-dynamic

#######################################
# PSK Connections
#######################################

conn IKEv2-PSK
	also=Non-L2TP
	keyexchange=ikev2
	authby=secret

# Cisco IPSec
conn IKEv1-PSK-XAuth
	also=Non-L2TP
	keyexchange=ikev1
	leftauth=psk
	rightauth=psk
	rightauth2=xauth

#######################################
# Certificate Connections
#######################################

conn windows7
    keyexchange=ikev2
    ike=aes256-sha1-modp1024!
    rekey=no
    left=%defaultroute
    leftauth=pubkey
    leftsubnet=0.0.0.0/0
    leftcert=server.cert.pem
    right=%any
    rightauth=eap-mschapv2
    rightsourceip=10.0.0.0/24
    rightsendcert=never
    eap_identity=%any
    auto=add
```

##### 2.3.2、options.xl2tpd

``` sh
ipcp-accept-local
ipcp-accept-remote
ms-dns 8.8.8.8
ms-dns 8.8.4.4
noccp
auth
crtscts
idle 1800
mtu 1280
mru 1280
lock
lcp-echo-failure 10
lcp-echo-interval 60
connect-delay 5000
```

##### 2.3.3、strongswan.conf

``` sh
# /etc/strongswan.conf - strongSwan configuration file
# strongswan.conf - strongSwan configuration file
#
# Refer to the strongswan.conf(5) manpage for details

charon {
	load_modular = yes
	send_vendor_id = yes
	plugins {
		include strongswan.d/charon/*.conf
		attr {
			dns = 8.8.8.8, 8.8.4.4
		}
	}
}

include strongswan.d/*.conf
```

##### 2.3.4、xl2tpd.conf

``` sh
[global]
port = 1701
auth file = /etc/ppp/l2tp-secrets
debug avp = yes
debug network = yes
debug state = yes
debug tunnel = yes
[lns default]
ip range = 10.1.0.2-10.1.0.254
local ip = 10.1.0.1
require chap = yes
refuse pap = yes
require authentication = yes
name = l2tpd
;ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
```

**创建好四个配置文件后将其复制到指定位置即可**

``` sh
# Strongswan Configuration
cp ipsec.conf /etc/ipsec.conf
cp strongswan.conf /etc/strongswan.conf

# XL2TPD Configuration
cp xl2tpd.conf /etc/xl2tpd/xl2tpd.conf
cp options.xl2tpd /etc/ppp/options.xl2tpd
```

#### 2.4、创建证书

对于 Windows、Android 等设备可能不支持某些登录方式，比如 IKEv2 PSK，这是需要创建证书，以支持使用 IKEv2 证书登录

##### 2.4.1、自签 CA

``` sh
# create CA certificate
ipsec pki --gen --outform pem > ca.key.pem
ipsec pki --self --in ca.key.pem --dn "C=CN, O=StrongSwan, CN=StrongSwan CA" --ca --outform pem > ca.cert.pem
```

##### 2.4.2、创建服务器证书

**其中 `--san` 可以指定多个，但一般为一个是域名，一个是外网 IP，如果经过了路由，那么只需要写本机的对外暴露网卡的 IP 即可**

``` sh
# create server certificate
ipsec pki --gen --outform pem > server.key.pem
ipsec pki --pub --in server.key.pem | ipsec pki --issue --cacert ca.cert.pem \
  --cakey ca.key.pem --dn "C=CN, O=StrongSwan, CN=服务器域名" \
  --san="服务器域名" --san="网卡IP" --flag serverAuth --flag ikeIntermediate \
  --outform pem > server.cert.pem
```

##### 2.4.3、创建客户端证书

``` sh
ipsec pki --gen --outform pem > client.key.pem
ipsec pki --pub --in client.key.pem | ipsec pki --issue --cacert ca.cert.pem \
  --cakey ca.key.pem --dn "C=CN, O=StrongSwan, CN=Client" \
  --outform pem > client.cert.pem
```

##### 2.4.4、生成 p12

安卓等设备是不支持直接导入客户端证书的，需要转换成 p12 格式，转换过程中需要输入两次密码，该密码为证书使用密码，导入时需要输入

``` sh
openssl pkcs12 -export -inkey client.key.pem -in client.cert.pem -name "Client" \
  -certfile ca.cert.pem -caname "StrongSwan CA" -out client.cert.p12
```

##### 2.4.5、安装证书

创建完成后将证书复制到指定目录即可

``` sh
cp -r ca.cert.pem /etc/ipsec.d/cacerts/
cp -r server.cert.pem /etc/ipsec.d/certs/
cp -r server.key.pem /etc/ipsec.d/private/
cp -r client.cert.pem /etc/ipsec.d/certs/
cp -r client.key.pem /etc/ipsec.d/private/
```

#### 2.5、创建用户

关于用户的登陆模式，比如使用 L2TP、IPsec、IKEv2 等请自行 Google，以下提供了一个简单的创建用户的脚本

``` sh
#!/bin/sh

vpn_user=$1
vpn_password=$2

if [ -z ${vpn_user} ] || [ -z ${vpn_password} ]; then
	echo "Usage: $0 user password"
	exit 1
fi

vpn_deluser ${vpn_user}

cat >> /etc/ipsec.d/l2tp-secrets <<EOF
"${vpn_user}" "*" "${vpn_password}" "*"
EOF

cat >> /etc/ipsec.d/ipsec.secrets <<EOF
${vpn_user} : EAP "${vpn_password}"
${vpn_user} : XAUTH "${vpn_password}"
EOF
```

**将其保存为 `vpn_adduser.sh`，执行 `./vpn_adduser.sh USERNAME PASSWD` 即可添加用户**

#### 2.6、设置 PSK

同样 PSK 也用于登录，如 IKEv2 PSK 登录，使用同样自行 Google，以下为设置 PSK 的脚本

``` sh
#!/bin/sh

psk=$1

if [ -z ${psk} ]; then
	echo "Usage: $0 psk"
	exit 1
fi

vpn_unsetpsk

touch /etc/ipsec.d/ipsec.secrets
cat >> /etc/ipsec.d/ipsec.secrets <<EOF
: PSK "${psk}"
EOF
```

最后启动 VPN 连接即可

``` sh
 /usr/sbin/xl2tpd -c /etc/xl2tpd/xl2tpd.conf
 ipsec start
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
