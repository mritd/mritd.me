---
layout: post
categories: Docker
title: Docker 分配宿主机网段 IP
date: 2017-05-12 22:42:00 +0800
description: Docker 分配宿主机网段 IP
keywords: Docker 宿主机 IP
---

> 工作需要临时启动一个 gitlab,无奈 gitlab 需要 ssh 的 22 端口;而使用传统网桥方式映射端口则 clone 等都需要输入端口号,很麻烦;22 端口宿主机又有 sshd 监听;研究了下 docker 网络,记录一下如何分配宿主机网段 IP


### 创建 macvlan 网络

关于 Docker 网络模式这里不再细说;由于默认的网桥方式无法满足需要,所以需要创建一个 macvlan 网络

``` sh
docker network create -d macvlan  --subnet=172.16.0.0/19 --gateway=172.16.0.1 -o parent=eth0 gitlab-net
```

- `--subnet`: 指定网段(宿主机)
- `--gateway`: 指定网关(宿主机)
- `parent`: 注定父网卡(宿主机)

创建以后可以使用 `docker network ls` 查看

``` sh
➜  ~  docker network ls
NETWORK ID          NAME                    DRIVER              SCOPE
a4a2980c9165        agent_default           bridge              local               
a0f29102b413        bridge                  bridge              local               
2f46dc70b763        gitlab-net              macvlan             local               
51bd6222530f        host                    host                local               
7a14a09c3cfc        none                    null                local
```

### 创建使用容器

接下来创建容器指定网络即可

``` sh
docker run --net=gitlab-net --ip=172.16.0.170  -dt --name test centos:7
```

**`--net` 指定使用的网络,`--ip` 用于指定网段内 IP**;启动后只需要在容器内启动程序测试即可

``` sh
# 启动一个 nginx
yum install nginx
nginx
```

启动后在局域网内能直接通过 IP:80 访问,而且宿主机 80 不受影响

### docker-compose 测试

docker-compose 示例如下

``` sh
version: '2'
services:
  centos:
    image: centos:7
    restart: always
    command: /bin/bash -c "sleep 999999"
    networks:
      app_net:
        ipv4_address: 10.10.1.34
networks:
  app_net:
    driver: macvlan
    driver_opts:
      parent: enp3s0
    ipam:
      config:
      - subnet: 10.10.1.0/24
        gateway: 10.10.1.2
#        ip_range: 10.25.87.32/28
```

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
