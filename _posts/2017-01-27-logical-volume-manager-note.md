---
layout: post
categories: Linux
title: Logical Volume Manager 笔记
date: 2017-01-27 10:05:26 +0800
description: LVM 笔记
keywords: LVM
---

> Logical Volume Manager 简称 LVM，LVM 是一种可用在Linux内核的逻辑分卷管理器；可用于管理磁盘驱动器或其他类似的大容量存储设备；LVM 依赖于 内核 device mapper 机制，可以实现动态伸缩逻辑卷大小，而屏蔽底层硬件变化，为后期磁盘扩展提供便利

### 一、LVM 简介

LVM 技术依据底层内核的 device mapper 机制，聚合底层硬件存储设备存储空间，在上层抽象出可扩展的逻辑分区；LVM 主要术语(磁盘术语)如下

- `PV` : 底层物理存储设备，如 `/dev/sda`
- `VG` : 卷组，意将多个 `PV` 组合后的抽象存储介质统称
- `PE` : `VG` 将 `PV` 聚合后，需向上层提供存储能力，而 `PE` 即为 `VG` 中最小的存储单位，**一般默认为 4MB**
- `LV` : 在 `VG` 之上划分一定量的存储空间，形成逻辑分区，即为 `LV`
- `LE` : `LV` 从 `VG` 之上划分，即 `LV` 实质上有 `VG` 上最小存储单位 `PE` 构成；但是 `PE` 构成 `LV` 之后，又称作 `LE`

**以上各术语(定义)之间关系如下图所示**

![PV_VG_LV](https://mritd.b0.upaiyun.com/markdown/mbzrv.jpg)

### 二、LVM 相关命令

#### 2.1、PV 管理工具

- pvs : 简要显示 pv 信息
- pvdisplay : 详细显示 pv 信息
- pvcreate : 创建 pv
- pvmove : 移动 pv (再删除 vg 前必须移动有数据的 pv)
- pvremove : 删除 pv

#### 2.2、VG 管理命令

- vgs : 简要显示 vg 信息
- vgdisplay : 详细显示 vg 信息
- vgcreate : 创建 vg
- vgrename : 重命名 vg
- vgremove : 删除 vg
- vgscan : 扫描 vg
- vgextend : 扩展 vg
- vgsplit : 切割 vg (将 vg 中 pv 移动到已存在 vg 中)
- vgreduce : 缩减 vg (删除 vg 内指定 pv)

#### 2.3、LV 管理命令

- lvs : 简要显示 lv 信息
- lvdisplay : 详细显示 lv 信息
- lvcreate : 创建逻辑卷
- lvextend : 扩展逻辑卷
- lvreduce : 缩减逻辑分区
- lvremove : 删除逻辑卷

##### 2.3.1、lvcreate

lvcreate 用于从 vg 上创建 lv 逻辑分区，基本命令格式如下 :

``` sh
lvcreate -L #[mMgGtT] -n NAME VolumeGroup
```

其常用选项如下 : 

- -L | --size : 指定要创建的 lv 大小，采用 `+5G` 这种方式
- -l | --extents : 指定大小范围，类似于 fdisk 分区时选择盘区范围
- -s | --snapshot : 创建一个快照卷，创建快照卷时后面必须跟快照卷名称
- p : 权限(r、rw)


##### 2.3.2、lvextend

lvextend 支持在线扩展扩展逻辑分区大小，命令格式如下 : 

``` sh
lvextend -L [+]#[mMgGtT] /dev/VG_NAME/LV_NAME
```

**注意 -L 选项后 + 可以省略，但是省略后代表总容量，如当前 LV 2G，需扩展 3G，则不写 + 需要输入 5G**

**lv 扩展后并不能立即体现在 df 等命令上，因为虽然逻辑卷已经扩展，但是文件系统尚未扩展，对于 ext 系列的文件系统可采用 `resize2fs /dev/VG_NAME/LV_NAME` 的方式刷新文件系统，其他分区格式需采用其他工具**

##### 2.3.3、lvreduce

**在缩减 lv 时，必须先卸载文件系统，然后缩减文件系统，并且缩减文件系统后要强制做文件系统检测，以防止发生损坏，操作命令及顺序如下 :**

- umount /dev/VG_NAME/LV_NAME
- e2fsck -f /dev/VG_NAME/LV_NAME
- resize2fs /dev/VG_NAME/LV_NAME #[mMgGtT]
- lvreduce [-]#[mMgGtT] /dev/VG_NAME/LV_NAME
- mount /dev/VG_NAME/LV_NAME DIR

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
