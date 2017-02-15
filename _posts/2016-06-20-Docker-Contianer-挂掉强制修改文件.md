---
layout: post
title: Docker Contianer 挂掉强制修改文件
categories: [Docker]
description: Docker Contianer 挂掉强制修改文件
keywords: Linux,Docker,Contianer
---

## 一、扯犊子

> 起因是为了装逼，想申请一个 StartSSL 证书给博客装下逼...... 目前博客全部采用 Dokcer 部署，前端一个 Nginx 的 Contianer 做反代，后端起了静态博客、WP老博客什么的一些东西；手残党开始肆无忌惮的改前端 Nginx Contianer 中的配置；发现 `service nginx reload` 没效果，这特么哪行，果断 `docker restart nginx`.....后面你懂的，`docker logs nginx` 发现配置报错了......所以就有了下文......

<!--more-->

## 二、Dokcer Contianer/Images 存储位置

### 2.1、images 存储(aufs) 摘自 [DockerOne](http://dockone.io/question/70)
- `/var/lib/graph/<image id>` 下面没有layer目录，只有每个镜像的json描述文件和layersize大小
- `/var/lib/docker/repositories-aufs` TagStore的存储地方，里面有image id与reponame ，tag之间的映射关系. aufs是driver名
- `/var/lib/docker/aufs/diff/<image id or container id>` 每层layer与其父layer之间的文件差异，有的为空，有的有一些文件(镜像实际存储的地方)
- `/var/lib/docker/aufs/layers/<image id or container id>` 每层layer一个文件，记录其父layer一直到根layer之间的ID，每个ID一行。大部分文件的最后一行都一样，表示继承自同一个layer.
- `/var/lib/docker/aufs/mnt/<image id or container id>` 有容器运行时里面有数据(容器数据实际存储的地方,包含整个文件系统数据)，退出时里面为空

### 2.2、Contianer 文件修改

所有 Contianer 文件存放于 `/var/lib/docker/aufs/mnt` 目录，改废掉的文件名为 `hexo.conf`，so  直接开搜 :

![hexo_docker_modify_contianerfile](https://mritd.b0.upaiyun.com/markdown/hexo_docker_modify_contianerfile.png)

然后直接修改保存即可，此时 Contianer 可恢复启动，此坑完结；目测企业级应用不会出现这种坑爹情况，一般都是编排工具......像我这么作死的应该没有

**做个安静的美男(dou)子(bi)**
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
