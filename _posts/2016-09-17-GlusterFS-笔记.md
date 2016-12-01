---
layout: post
title: GlusterFS 笔记
categories: [Linux]
description: GlusterFS 笔记
keywords: Linux,GlusterFS
---



## 一、简介

GlusterFS 是近年兴起的一个高性能开源分布式文件系统，其目标是全局命名空间、分布式前端的高性能文件系统，目前已被 RedHat 看中，GlusterFS 具有高扩展、高可性、高性能、可横向扩展等特点，并且 GlusterFS 没有元数据服务器的设计，使其没有单点故障问题。

## 二、GlusterFS 集群搭建

### 2.1、环境准备

由于资源有限，所以以虚拟机测试，故性能上无法体现，毕竟是一块硬盘，搭建环境如下

<!--more-->

|主机|域名|磁盘|大小|
|----|----|----|----|
|192.168.1.100|gfs-server1|/dev/sdb| 50G|
|192.168.1.107|gfs-server2|/dev/sdb| 50G|
|192.168.1.126|gfs-server3|/dev/sdb| 50G|
|192.168.1.217|gfs-server4|/dev/sdb| 50G|

### 2.2、安装 GlusterFS

CentOS7 默认官方 yum 源中有 GlusterFS 相关的 rpm 包，但是发现没有 server 端的，官方给出的安装命令如下

``` sh
# 安装 GlusterFS yum 源
yum install -y centos-release-gluster && yum update -y
# 安装 GlusterFS 以及客户端
yum install -y glusterfs glusterfs-fuse glusterfs-cli glusterfs-server glusterfs-api
```

### 2.3、基础环境配置

#### 2.3.1、ntp 时钟同步

由于 GlusterFS 需要进行节点间同步，所以各节点时间要保证一致性，故需要安装 ntp 时钟同步工具

``` sh
# 安装 ntp
yum install -y ntp
```

安装完成后应进行时钟同步，这里暂时使用 windows 的时钟授权服务器，也可以选择其他时钟授权服务器，安装时测试国内的清华大等全部超时......

``` sh
# 同步时钟
ntpdate time.windows.com
```

同步完成后最好设置定时同步，以下为每天 0 时开始没 3 小时进行一次时钟同步

``` sh
# 增加 当前用户 cron 任务
crontab -e
# 写入如下任务
* 0-23/3 * * * root  /usr/sbin/ntpdate time.windows.com &> /dev/null; /usr/sbin/clock -w
```

#### 2.3.2、host 定义

由于使用域名方式访问，所以需要修改本地 hosts 文件，也可以通过自建 dns 服务器来解决，不过据说 dns 服务器方式会有一点点延迟，所以推荐修改本地 hosts(没证明过)

``` sh
# 修改 hosts
vim /etc/hosts
# 增加如下
192.168.1.100 gfs-server1
192.168.1.107 gfs-server2
192.168.1.126 gfs-server3
192.168.1.217 gfs-server4
```

### 2.4、启动并加入节点

GlusterFS 安装完成后可直接通过 systemd 启动

``` sh
systemctl enable glusterd
systemctl start glusterd
```

启动完成后便可在任意节点上将其他节点加入进来，组建集群

``` sh
for gfs_host in gfs-server1 gfs-server2 gfs-server3 gfs-server4;do
  gluster peer probe $gfs_host
done
```

### 2.5、磁盘预处理

GlusterFS 集群服务启动并加入其他节点后，就需要为下一步创建卷(volume)准备磁盘，以下以一块 50G 的磁盘为例，在每个节点上执行如下

``` sh
# 首先创建分区
fdisk /dev/sdb
# 然后输入 n 创建新分区，再输入 p 选择主分区
# 最后输入 w 保存分区表，如下所示

欢迎使用 fdisk (util-linux 2.23.2)。

更改将停留在内存中，直到您决定将更改写入磁盘。
使用写入命令前请三思。

Device does not contain a recognized partition table
使用磁盘标识符 0x445cdbb5 创建新的 DOS 磁盘标签。

命令(输入 m 获取帮助)：n
Partition type:
   p   primary (0 primary, 0 extended, 4 free)
   e   extended
Select (default p): p
分区号 (1-4，默认 1)：
起始 扇区 (2048-104857599，默认为 2048)：
将使用默认值 2048
Last 扇区, +扇区 or +size{K,M,G} (2048-104857599，默认为 104857599)：
将使用默认值 104857599
分区 1 已设置为 Linux 类型，大小设为 50 GiB

命令(输入 m 获取帮助)：w
The partition table has been altered!

Calling ioctl() to re-read partition table.
正在同步磁盘。
```

分区创建完成后需要对其进行格式化

``` sh
mkfs.ext4 /dev/sdb
```

最后准备接下来要使用的相关挂载目录

``` sh
# 创建磁盘挂载目录
mkdir -p /data/gfs
# 挂载硬盘
mount -t ext4 /dev/sdb /data/gfs
# 创建 GlusterFS 卷目录
mkdir -p /data/gfs/brick0
```

为了保证磁盘一直挂载，最好设置一下开机自动挂载

``` sh
# 后面三个选项，defaults 表示使用默认挂载参数，
# 第一个 1 代表 允许 demp
# 第二个 1 代表 开机执行挂载分区检查
echo "/dev/sdb /data/gfs ext4 defaults 1 1" >> /etc/fstab
```

到此集群基本部署完成

## 三、GlusterFS 存储卷设置

GlusterFS 集群搭建完成后，便需要创建存储卷(volume)来整合各个集群磁盘存储资源，以便后面进行挂载和使用

### 3.1、创建分布式 Hash 卷

分布式 Hash 卷其原理是当向 GlusterFS 写入一个文件时，GlusterFS 通过弹性 Hash 算法对文件名进行计算，然后将其均匀的分布到各个节点上，**因此分布式 Hash 卷没有数据冗余**，创建分布式 Hash 卷命令如下

``` sh
gluster volume create gfs_disk\
  gfs-server1:/data/gfs/brick0 \
  gfs-server2:/data/gfs/brick0 \
  gfs-server3:/data/gfs/brick0 \
  gfs-server4:/data/gfs/brick0
```

### 3.2、创建复制卷

复制卷相当于 RAID1，在向 GlusterFS 中存储文件时，GlusterFS 将其拷贝到所有节点，并且是同步的，这会极大降低磁盘性能，并呈线性降低，**但是复制卷随着节点数量增加，起数据冗余能力也在增加，因为每个节点上都有一份数据的完全拷贝**，创建复制卷命令如下

``` sh
# replica 参数用于指定数据拷贝有多少份
# 注意: replica 数量必须与指定的 GlusterFS 集群 brick 数量保持一致
gluster volume create gfs_disk replica 4 transport tcp \
  gfs-server1:/data/gfs/brick0 \
  gfs-server2:/data/gfs/brick0 \
  gfs-server3:/data/gfs/brick0 \
  gfs-server4:/data/gfs/brick0
```

### 3.3、创建分布式 Hash 复制卷

顾名思义，分布式 Hash 复制卷就是将 Hash 卷与复制卷整合一下，通过 replica 参数指定复制份数，以下例子为使用4个节点创建，每两个节点组成一个复制卷，然后两对节点再组成 Hash 卷

``` sh
# 创建 分布式 Hash 复制卷时，只需要保证集群数量是 replica 数量的整数倍即可
gluster volume create gfs_disk replica 2 transport tcp \
  gfs-server1:/data/gfs/brick0 \
  gfs-server2:/data/gfs/brick0 \
  gfs-server3:/data/gfs/brick0 \
  gfs-server4:/data/gfs/brick0
```

### 3.4、其他卷

- 条带卷: 条带卷既将文件切分成块，分布存放在各个节点，将 `replica` 替换成 `stripe` 即可
- 分布式 Hash 条带卷: 同分布式 Hash 复制卷一样，保证节点数量是 `stripe` 的整数倍即可

由于条带卷使用并不多，所以不做演示，一般条带卷适用于单个大文件超过磁盘大小时使用

## 四、GlusterFS 挂载及测试

无论创建的哪种卷，最终创建完成后都可以通过如下命令查看

``` sh
gluster volume info
```

### 4.1、GlusterFS 卷挂载

卷创建完成后，只需要像正常磁盘一样挂载即可使用，**不同的是文件系统类型指定为 `glusterfs` 而已**，操作如下

``` sh
# mount 时指定任意一个节点即可
mount -t glusterfs gfs-server1:gfs_disk /mnt/gfs
```

为保证一直可用，同样最好设置开机自动挂载

``` sh
echo "gfs-server1:gfs_disk /mnt/gfs glusterfs defaults 0 1" >> /etc/fstab
```

### 4.2、测试 GlusterFS

以下以分布式 Hash 卷为例，由于准备了 4 各节点，并且 replica 为 2，所以理论上向 GlusterFS 写入一个文件应该会在任意两个节点上都有一份

``` sh
# 在 gfs-server1 上执行
cp test.tar.gz /mnt.gfs
# 最后可以在 gfs-server3、gfs-server4 的磁盘目录中看到
ls /data/gfs/brick0
```

## 五、其他相关

没有任何通用的文件系统，通用意味着通通不能用，关于 GlusterFS 适用场景以及缺点可参考 [换个角度看GlusterFS分布式文件系统](http://blog.sae.sina.com.cn/archives/5141) 文章，关于 GlusterFS 性能与监控可参考 [GlusterFS性能监控&配额](https://github.com/jiobxn/one/wiki/00086_GlusterFS%E6%80%A7%E8%83%BD%E7%9B%91%E6%8E%A7&%E9%85%8D%E9%A2%9D)
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
