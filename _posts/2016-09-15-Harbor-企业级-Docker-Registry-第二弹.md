---
layout: post
title: Harbor 企业级 Docker Registry 第二弹
categories: [Docker]
description: Harbor 企业级 Docker Registry 第二弹
keywords: Linux,Docker,registry,mirror,harbor
---



## 一、简介

Harbor 是 VMware 中国开发的一款 Dokcer Registry 工具，其主要致力于企业级的 Registry 管理，并提供了 LDAP 等高级权限认证功能，从第一次尝试到现在的版本已经有了很大变化，故决定重写一下 Harbor 的相关文章

## 二、Harbor 搭建私服

Harbor 最主要的功能就是搭建一个企业级的 Registry 私服，并对其进行完善的安全管理等，最新版本的 Harbor 已经支持 Dokcer 容器化的启动方式，各个组件使用 docker-compose 来进行编排，以下为搭建过程

<!--more-->

### 2.1、获取安装脚本

安装脚本在 Github 上，直接 wget 下来即可

``` sh
wget https://github.com/vmware/harbor/releases/download/0.3.5/harbor-installer.tgz
tar -zxvf harbor-installer.tgz
```

将其解压开后目录结构如下

![hexo_harbor_install_scripts](https://mritd.b0.upaiyun.com/markdown/hexo_harbor_install_scripts.png)

其中最外层有一个 `install.sh` 脚本，用于安装 Harbor，config 目录存放了一些配置信息，如 registry 和 ui 目录中存放了相关证书用于组件间加密通讯，`harbor.cfg` 是全局配置文件，里面主要包含了一些常用设置，比如是否启用 https 等，`prepare` 是一个 python 写的预处理脚本，主要负责初始化一些 `harbor.cfg` 的相关配置，`docker-compose.yml` 顾名思义，里面顶一个各个组件的依赖关系以及配置挂载、数据持久化等设置。

### 2.2、基础配置

修改配置直接编辑 `harbor.cfg` 即可

``` sh
vim harbor.cfg
# 其配置信息如下
hostname = registry.mritd.me                      # Harbor 服务器域名
ui_url_protocol = https                           # UI 组件访问协议
email_server = smtp.mydomain.com                  # email 服务器地址
email_server_port = 25                            # email 端口
email_username = sample_admin@mydomain.com        # email 账号
email_password = abc                              # email 密码
email_from = admin <sample_admin@mydomain.com>    # email 发件人
email_ssl = false                                 # 是否启用 SSL
harbor_admin_password = Harbor12345               # Harbor 初始化管理员(admin)密码
auth_mode = db_auth                               # 权限管理模型(db_auth/ldap_auth)
ldap_url = ldaps://ldap.mydomain.com              # ldap 地址
ldap_basedn = uid=%s,ou=people,dc=mydomain,dc=com # ldap 权限模型
db_password = root123                             # 数据库 管理员密码
self_registration = on                            # 是否打开自动注册
use_compressed_js = on                            # 是否启用压缩js
max_job_workers = 3                               # 最大任务数
token_expiration = 30                             # token 超时
verify_remote_cert = on                           # 是否验证远程证书
customize_crt = on                                # 是否启用自定义证书
# 以下为自定义证书信息
crt_country = CN
crt_state = State
crt_location = CN
crt_organization = organization
crt_organizationalunit = organizational unit
crt_commonname = example.com
crt_email = example@example.com
```

### 2.3、HTTPS 配置

基础配置中如果启用了 https 协议，那么需要手动生成 nginx 的证书，生成过程如下

**CentOS7 下首先需要修改 OpenSSL CA 工作目录**

``` sh
#  编辑 OpenSSL 配置
vim /etc/pki/tls/openssl.cnf
# 主要修改 CA_default 标签下的 dir 为 ./demoCA
[ CA_default ]
dir             = ./demoCA  
```

**创建 CA**

``` sh
openssl req \
    -newkey rsa:4096 -nodes -sha256 -keyout ca.key \
    -x509 -days 365 -out ca.crt
```

![hexo_harbor_createcacert](https://mritd.b0.upaiyun.com/markdown/hexo_harbor_createcacert.png)

**创建签名请求**

``` sh
openssl req \
    -newkey rsa:4096 -nodes -sha256 -keyout yourdomain.com.key \
    -out yourdomain.com.csr
```

![hexo_harbor_createcsr](https://mritd.b0.upaiyun.com/markdown/hexo_harbor_createcsr.png)

**初始化 CA 信息**

``` sh
mkdir demoCA
cd demoCA
touch index.txt
echo '01' > serial
cd ../
```

**签署证书**

``` sh
openssl ca -in yourdomain.com.csr -out yourdomain.com.crt -cert ca.crt -keyfile ca.key -outdir .
```

![hexo_harbor_signcrt](https://mritd.b0.upaiyun.com/markdown/hexo_harbor_signcrt.png)

**复制证书到配置目录，并修改 nginx 配置**

``` sh
# 复制证书
cp registry.mritd.me.crt config/nginx/cert
cp ca/registry.mritd.me.key config/nginx/cert
# 备份配置
mv config/nginx/nginx.conf config/nginx/nginx.conf.bak
# 使用模板文件
mv config/nginx/nginx.https.conf config/nginx/nginx.conf
# 编辑 Nginx 配置
vim config/nginx/nginx.conf
# 主要修改 监听域名 和 ssl 证书位置
server_name registry.mritd.me;
ssl_certificate /etc/nginx/cert/registry.mritd.me.crt;
ssl_certificate_key /etc/nginx/cert/registry.mritd.me.key;
```

**最后执行 install 访问域名即可**



## 三、Harbor 搭建镜像仓库

搭建镜像仓库只需要简单修改配置即可，不过镜像仓库不允许 push 操作，只作为官方仓库缓存

``` sh
vim templates/registry/config.yml
# 增加以下内容
proxy:
  remoteurl: https://registry-1.docker.io
# 然后重新部署即可
docker-compose down
rm -rf /data/*
docker up -d
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
