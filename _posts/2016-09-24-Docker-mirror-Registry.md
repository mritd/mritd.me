---
layout: post
title: Docker mirror Registry
categories: [Docker]
description: Docker mirror Registry
keywords: Linux,Docker,mirror.registry
---


## 一、扯淡

撸 Dokcer 这么长时间以来，由于国内众所周知的网络原因，Docker pull 镜像会非常慢，慢到你怀疑这个世界，甚至怀疑你来到这个世界的正确性与合理性，为了为了让自己不怀疑世界，记录一下如何撸一个 docker mirror registry

## 二、动手撸一个

### 2.1、基本环境

以下操作基本环境如下

- Docker 1.12.1
- registry 2.5.1
- nginx 1.10.1

<!--more-->

### 2.2、导出 registry 配置

Docker 官方提供了一个 registry，Github 地址 [点这里](https://github.com/docker/distribution)，而大部分能找到的资料都是如何撸一个 private registry，就是启动一下这个官方 registry container 即可，然后就可以 docker push 什么的；而 mirror registry 其实也很简单，就是增加一个配置即可

**首先把官方 registry 中的配置文件导出**

``` sh
docker run -it --rm --entrypoint cat registry:2.5.1 \
/etc/docker/registry/config.yml > config.yml
```

**registry 的配置文件内容如下**

``` yml
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
```

### 2.3、修改 registry 配置

**上一步已经将配置导出了，接下来如果想使用 mirror 功能只需在下面增加 proxy 选项即可**

``` yml
version: 0.1
log:
  fields:
    service: registry
storage:
  cache:
    blobdescriptor: inmemory
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: :5000
  headers:
    X-Content-Type-Options: [nosniff]
health:
  storagedriver:
    enabled: true
    interval: 10s
    threshold: 3
proxy:
  remoteurl: https://registry-1.docker.io
  username: [username]
  password: [password]

```

**username 与 password 是可选项，当填写 username 与 password 以后就可以从 hub pull 私有镜像**

### 2.4、启动 mirror registry

**最后只需要在启动 registry 时候将配置塞回去即可**

``` sh
docker run -dt --name v2-mirror \
-v /data/registry:/var/lib/registry \
-v /etc/registry/config.yml:/etc/docker/registry/config.yml \
-p 5000:5000 registry:2.5.1
```

**以上命令将启动一个 mirror registry，并且数据持久化到 `/data/registry`**

### 2.5、nginx 配置 ssl

当然此时直接在 docker 启动参数总增加 `--registry-mirror=http://IP:5000`，然后重启 docker 再进行 pull 即可生效，但是 5000 端口外加 http 总有点那么不装逼，所以最好增加一个 nginx 做反向代理，同时可以使用 ssl 加密，以下是一个 nginx 配置仅供参考，ssl 证书可采用 [StartSSL](https://www.startssl.com) 免费一年的 DV 证书

**nginx.conf**

``` sh
# worker 运行用户组
user  nginx nginx;

# worker 进程自动
worker_processes  auto;

# 单个 worker 进程能打开的最大文件描述符数量
worker_rlimit_nofile  51200;

# 指定每个用户能够发往 worker 的信号数量(rtsig)
# worker_rlimit_sigpending

# CPU 亲源性，用于将具体的 worker 绑定到 CPU 核心
# worker_cpu_affinity 0001 0010 0100 1000

# 指定 worker 优先级
# worker_priority

# 是否以守护进程方式启动 nginx
# daemon off|on

# 是否以 master/worker 方式运行
# master_process

# 错误日志文件及级别
error_log  /var/log/nginx/error.log  info;

pid        /var/run/nginx/nginx.pid;


events {
    # 每个 worker 进程所能响应的最大并发连接数
    worker_connections  51200;

    # 指明使用的事件模型 一般自动选择
    # use [epoll|rgsig|select|poll]
    use epoll;

    # 定义内部各请求调用 worker 时使用的 负载均衡锁
    # on: 能够让多个 worker 轮流的序列化的响应新请求，会有一定性能损失
    # off:
    # accept_mutex [on|off]

    # 定义锁文件位置
    # lock_file /PATH/TO/LOCK_FILE

    multi_accept on;


}


http {
    include       mime.types;
    default_type  application/octet-stream;

    log_format    main  '$server_name $remote_addr - $remote_user [$time_local] "$request" - $request_body '
                        '$status $body_bytes_sent "$http_referer" '
                        '"$http_user_agent" "$http_x_forwarded_for" '
                        '$ssl_protocol $ssl_cipher $request_time ';

    server_names_hash_bucket_size 128;
    client_header_buffer_size 32k;
    large_client_header_buffers 4 32k;
    client_max_body_size 1024m;
    sendfile on;
    tcp_nopush on;
    keepalive_timeout 120;
    server_tokens off;
    tcp_nodelay on;


    gzip  on;
    gzip_buffers 16 8k;
    gzip_comp_level 6;
    gzip_http_version 1.1;
    gzip_min_length 256;
    gzip_proxied any;
    gzip_vary on;
    gzip_types
        text/xml application/xml application/atom+xml application/rss+xml application/xhtml+xml image/svg+xml
        text/javascript application/javascript application/x-javascript
        text/x-json application/json application/x-web-app-manifest+json
        text/css text/plain text/x-component
        font/opentype application/x-font-ttf application/vnd.ms-fontobject
        image/x-icon;
    gzip_disable "MSIE [1-6]\.(?!.*SV1)";

    open_file_cache max=1000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;

    include /etc/nginx/conf.d/*.conf;
}
```

**mirror.conf**

``` sh
server {
  listen 80;
  server_name your-domain;
  rewrite ^(.*) https://$server_name$1 permanent;
}

server {
  listen 443;
  server_name your-domain;
  access_log /var/log/nginx/your-domain.log main;

  ssl on;
  ssl_certificate      /etc/nginx/ssl/your-domain.crt;
  ssl_certificate_key  /etc/nginx/ssl/your-domain.key;

  location / {

    log_not_found on;

    proxy_pass http://mirror:5000;
    proxy_read_timeout 300;
    proxy_connect_timeout 300;
    proxy_redirect off;

    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Host              $http_host;
    proxy_set_header X-Real-IP         $remote_addr;
  }
}
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
