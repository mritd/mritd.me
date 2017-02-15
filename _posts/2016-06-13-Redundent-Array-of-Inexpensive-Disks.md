---
layout: post
title: Redundent Array of Inexpensive Disks
categories: [Linux]
description: Redundent Array of Inexpensive Disks
keywords: RAID,Linux
---


## 一、简介

> Redundent Array of Inexpensive/Indepedent Disks 简称 RAID 廉价(独立)冗余磁盘技术，早起由美国加州大学伯克利分校发明，用于使用廉价磁盘替代 SCSI 硬盘而设计，后经过发展成为 Linux 服务器构建高可用磁盘阵列技术；RAID 能够将多块硬盘组合成磁盘阵列，使其具备高速读写、数据冗余备份功能，对于 Host OS 来说，RAID 相当于一块高性能并有高可靠数据存储的硬盘。

## 二、RAID 分级

### 1、RAID 级别

常用的 RAID 级别分别为 **RAID0、RAID1、RAID5、RAID10、RAID50、JBOD。**

<!--more-->

### 2、RAID0

RAID0 至少需要两块硬盘，其主要工作逻辑是将一个文件分片存放到多块硬盘，**无冗余备份**，理论上此时相对于单个磁盘的读写性能将提升 2倍或者更高(取决于硬盘块数)，磁盘利用率为100%；当然由于没有冗余备份，此时**将会放大数据损坏概率(每块磁盘损坏概率假设10%，多块相乘)**；通常将需要高速读写，并且数据损坏无实际影响的数据存放与此，如 swap 交换分区、tmp缓存分区等。

### 3、RAID1

RAID1 通常称之为镜像盘，同样 RAID1 至少需要两块磁盘，其工作逻辑是将一个文件分片，但会同时存储到两块硬盘上，相当于一个文件存2份，对于高可靠性数据则需要使用 RAID1，RAID1会降低磁盘存储性能 n 倍，具体取决于磁盘数量，磁盘利用率为 1/n；但每块磁盘上都有完整的磁盘数据，此时相当于完全冗余，会提升读取性能。

### 4、RAID4

为了既能够冗余备份，又能提升性能，则需要 RAID4，RAID4至少需要3块硬盘，其工作逻辑为 **对于一个文件，首先将其分片存储进前两块硬盘，然后对于两个数据片做亦或运算生成校验码存储到第三块硬盘，第三块硬盘只存校验码，不存储真正的文件数据；**此时前两块硬盘相当于 RAID0 的性能，当其中一块损坏后，可通过第三块硬盘与第一块硬盘做反向运算得出第二块硬盘内的数据，达到数据冗余的效果；**但当前两块硬盘某一硬盘损坏后，剩下的两块硬盘将产生巨大压力，同时半损巨大的性能降低，**因为每次读取存储文件都需要两块硬盘参与并完成数据计算。RAID1 下一旦磁盘出现损坏必须第一时间更换，否则剩下的两块磁盘一旦在此损坏数据将完全丢失，此种存储方式磁盘利用率为 (n-1)/n，下图为 RAID4 示意图 :

![hexo_raid4](https://mritd.b0.upaiyun.com/markdown/hexo_raid4.png)


### 5、RAID5

RAID5 与 RAID4 基本一致，区别在于 **RAID4 将所有数据的校验码存放于最后一块磁盘上，当有磁盘损坏时，虽然能通过计算恢复数据，但此时如果校验盘再出现问题那么将导致全部数据丢失，RAID5 在此基础上将校验码分别存储于每个磁盘之上，从而降低了数据损毁风险。**

### 6、RAID6

RAID6 同 RAID5 基本一致，不过 RAID6至少需要4块硬盘，并且允许同时有两块硬盘损坏；

### 7、RAID10

RAID10 基于 RAID1 和 RAID0，RAID10 需要至少4块磁盘，空间利用率为50%，首先使用2块磁盘一组做 RAID1 镜像盘，保证数据完全备份，然后使用2块磁盘作为一个磁盘组，用这些磁盘组组件 RAID0 提高读写性能，此阵列允许同一组 RAID1 内有一块硬盘损坏，但不能同时损坏，同时损坏则会造成数据丢失，其示意图如下 :

![hexo_raid10](https://mritd.b0.upaiyun.com/markdown/hexo_raid10.png)

### 8、JBOD

JBOD 并非为了高可用数据冗余而设计，其主要作用是提高空间利用率，工作逻辑只是简单地将多块硬盘连接为一块使用，也不会为文件做自动的分片处理，常常用于类似 Hadoop 集群等应用，因为 Hadoop HDFS 等有其本身的容错机制。

## 三、RAID 实现方式

### 1、硬件实现

硬件一般有两种实现方案，一种是板载集成，其性能一般较差，另一种是采用 PCI-E 插槽等接口的外置设备，通常称为 HBA 卡；此种阵列卡要求 Linux 内核能够驱动，其 RAID 级别在 BIOS 中便可完成设置。

### 2、软件实现

在硬件成本无法负担的情况下，Linux 内核提供一种组织机制(md模块)，可以在内核级别将多块硬盘组合成一块硬盘来使用，此时组件的 RAID 基于软件实现，此种操作需要浪费大量 CPU 性能。

### 3、mdadm 命令

mdadm 命令用于与内核的 md 模块通讯，设置软件模式的 RAID；mdadm 类似 vim 是一个模式化的工具，其配置文件在 `/etc/mdadm.conf`，具体模式如下(用的很少) :

- `-A` : Assemble 装配模式
- `-C` : Create 创建模式
  - `-n #` : 用于创建RAID设备的个数
  - `-x #` : 热备磁盘的个数
  - `-l` : 指定RAID级别
  - `-a` : =yes（自动为创建的RAID设备创建设备文件） md mdp part p 如何创建设备文件
  - `-c` :指定块的大小，默认为512KB
- `-F` : FOLLOW 监控
- `-S` : 停止RAID
- `-D`、`--detail` : 显示阵列详细信息
- Manage 管理模式专用项
  - `-f` : 模拟损害
  - `-r` : 模拟移除设备
  - `-a` : 模拟添加新设备
- `/proc/mdstat` : 内核 md 模块配置
- 创建一个大小为12G的RAID0：2*6G，3*4G 4*3G 6*2G : `mdadm -C /dev/md0 -a yes -l 0 -n 2 /dev/sdb{1,2}`


<audio autoplay="autoplay">
<source src="https://mritd.b0.upaiyun.com/markdown/Cake-By-The Ocean.mp3" type="audio/mpeg" />
Your browser does not support the audio element.
</audio>
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
