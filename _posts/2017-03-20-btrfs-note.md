---
layout: post
categories: Linux
title: Btrfs 笔记
date: 2017-03-20 21:27:19 +0800
description: Btrfs 笔记
keywords: Btrfs
---

> btrfs 是 Oracle 07 年基于 GPL 协议开源的 Linux 文件系统，其目的是替换传统的 Ext3、Ext4 系列文件系统；Ext 系列文件系统存在着诸多问题，比如反删除能力有限等；而 btrfs 在解决问题同时提供了更加强大的高级特性

### 一、Btrfs 特性

btrfs 在文件系统级别支持写时复制(cow)机制，并且支持快照(增量快照)、支持对单个文件快照；同时支持单个超大文件、文件检查、内建 RAID；支持 B 树子卷(组合多个物理卷，多卷支持)等，具体如下

**btrfs 核心特性：**

- 多物理卷支持：btrfs 可有多个物理卷组成(类似 LVM)；支持 RAID 以及联机 添加、删除、修改
- 写时复制更新机制(cow)：复制、更新、替换指针，而非传统意义上的覆盖
- 支持数据及元数据校验码：checksum 机制
- 支持创建子卷：sub_volume 机制，同时可多层创建
- 支持快照：基于 cow 实现快照，并且相对于 LVM 可以实快照的快照(增量快照)
- 支持透明压缩：后台自动压缩文件(消耗一定 CPU)，对前端程序透明

### 二、btrfs 常用命令

#### 2.1、创建文件系统

同传统的 ext 系列文件系统一样，btrfs 文件系统格式化同样采用 `mkfs` 系列命令 `mkfs.btrfs`，其常用选项如下：

- `-L` 指定卷标
- `-m` 指明元数据存放机制(RAID)
- `-d` 指明数据存放机制(RAID)
- `-O` 格式化时指定文件系统开启那些特性(不一定所有内核支持)，如果需要查看支持那些特性可使用 `mkfs.btrfs -O list-all`

#### 2.2、挂载 btrfs

同 ext 系列一样，仍然使用 `mount` 命令，基本挂载如下：

``` sh
mount -t brtfs DEVICE MOUNT_POINT
```

在挂载时也可以直接开启文件系统一些特性，如**透明压缩**

``` sh
 mount -t btrfs -o compress={lzo|zlib} DEVICE MOUNT_POINT
```

同时 btrfs 支持子卷，也可以单独挂载子卷

``` sh
mount -t btrfs -o subvol=SUBVOL_NAME DEVICE
```

#### 2.3、btrfs 相关命令

管理 btrfs 使用 `btrfs` 命令，该命令包含诸多子命令已完成不同的功能管理，常用命令如下

- **btrfs 文件系统属性查看：** `btrfs filesystem show`
- **调整文件系统大小：** `btrfs filesystem resize +10g MOUNT_POINT`
- **添加硬件设备：** `btrfs filesystem add DEVICE MOUNT_POINT`
- **均衡文件负载：** `btrfs blance status|start|pause|resume|cancel MOUNT_POINT`
- **移除物理卷(联机、自动移动)：** `btrfs device delete DEVICE MOUNT_POINT`
- **动态调整数据存放机制：** `btrfs balance start -dconvert=RAID MOUNT_POINT`
- **动态调整元数据存放机制：** `btrfs balance start -mconvert=RAID MOUNT_POINT`
- **动态调整文件系统数据数据存放机制：** `btrfs balance start -sconvert=RAID MOUNT_POINT`
- **创建子卷：** `btrfs subvolume create MOUNT_POINT/DIR`
- **列出所有子卷：** `btrfs subvolume list MOUNT_POINT`
- **显示子卷详细信息：** `btrfs subvolume show MOUNT_POINT`
- **删除子卷：** `btrfs subvolume delete MOUNT_POIN/DIR`
- **创建子卷快照(子卷快照必须存放与当前子卷的同一父卷中)：** `btrfs subvolume snapshot SUBVOL PARVOL`
- **删除快照同删除子卷一样：** `btrfs subvolume delete MOUNT_POIN/DIR`

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
