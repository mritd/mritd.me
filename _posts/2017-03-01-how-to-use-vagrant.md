---
layout: post
categories: Linux
title: Vagrant 使用
date: 2017-03-01 22:07:59 +0800
description: 记录下 Vagrant 使用教程
keywords: Vagrant
---

> Vagrant 是一个开源的 基于 ruby 的开源虚拟机管理工具；最近在鼓捣 kubernetes ，常常需要做集群部署测试，由于比较穷 😂😂😂；所以日常测试全部是自己开虚拟机；每次使用 VirtualBox开5个虚拟机很烦，而且为了保证环境干净不受其他因素影响，所以每次测试都是新开.....每次都会有种 WTF 的感觉，所以研究了一下 Vagrant 这个工具，发现很好用，一下记录一下简单的使用

### 一、Vagrant 介绍

上面已经简单的说了一下 Vagrant，Vagrant 定位为一个虚拟机管理工具；它能够以脚本化的方式启动、停止、和和删除虚拟机，当然这些手动也没费劲；更重要的是它能够自己定义网络分配、初始化执行的脚本、添加硬盘等各种复杂的动作；最重要的是 Vagrant 提供了类似于 docker image 的 box；Vagrant Box 就是一个完整的虚拟机分发包，可以自己制作也可以从网络下载；并且 Vagrant 开源特性使得各路大神开发了很多 Vagrant 插件方便我们使用，基于以上这些特点，我们可以实现:

- 一个脚本定义好虚拟机的数量
- 一个脚本定义好虚拟机初始化工作，比如装 docker
- 一个脚本完成多台虚拟机网络配置
- 一条命令启动、停止、删除多个虚拟机
- 更多玩法自行摸索.....

### 二、Vagrant 使用

#### 2.1、Vagrant 安装

Vagrant 安装极其简单，目前官方已经打包好了各个平台的安装包文件，地址访问 [Vagrant 官方下载地址](https://www.vagrantup.com/downloads.html)；截图如下

![vagrant download](https://mritd.b0.upaiyun.com/markdown/m46fa.jpg)

以下为 CentOS 上的安装命令

``` sh
wget https://releases.hashicorp.com/vagrant/1.9.2/vagrant_1.9.2_x86_64.rpm
rpm -ivh vagrant_1.9.2_x86_64.rpm
```

#### 2.2、Vagrant Box 下载

装虚拟机大家都不陌生，首先应该搞个系统镜像；同样 Vagrant 也需要先搞一个 Vagrant Box，Vagrant Box 是一个已经预装好操作系统的虚拟机打包文件；根据不同系统可以选择不同的 Vagrant Box，官方维护了一个 Vagrant Box 仓库，地址 [点这里](https://atlas.hashicorp.com/boxes/search)，截图如下

![vagrant boxes](https://mritd.b0.upaiyun.com/markdown/2duz7.jpg)

点击对应的系统后可以看到如下界面

![box detail](https://mritd.b0.upaiyun.com/markdown/kiohr.jpg)

该页面罗列出了使用不同虚拟机时应当使用扥添加明令；当然执行这些命令后 vagrant 将会从网络下载这个 box 文件并添加到本地 box 仓库；**不过众所周知的原因，这个下载速度会让你怀疑人生，所有简单的办法是执行以下这条命令，然后会显示 box 的实际下载地址；拿到地址以后用梯子先把文件下载下来，然后使用 vagrant 导入也可以(centos7 本地已经有了一下以 ubuntu 为例)**

![box download url](https://mritd.b0.upaiyun.com/markdown/p36th.jpg)
下载后使用 `vagrant box add xxxx.box` 即可将 box 导入到本地仓库

#### 2.3、启动一个虚拟机

万事俱备只差东风，在上一步执行 `vagrant init ubuntu/trusty64; vagrant up --provider virtualbox` 命令获取 box 下载地址时，已经在当前目录下生成了一个 Vagrantfile 文件，这个文件其实就是虚拟机配置文件，具体下面再说；box 导入以后先启动一下再说，执行 `vagrnat up` 即可


其他几个常用命令如下

- `vagrant box [list|add|remove]` 查看添加删除 box 等
- `vagrant up` 启动虚拟机
- `vagrant halt` 关闭虚拟机
- `vagrant init` 初始化一个指定系统的 Vagrantfile 文件
- `vagrant destroy` 删除虚拟机
- `vagrant ssh` ssh 到虚拟机里

**特别说明一下 ssh 这个命令，一般默认的规范是 `vagrant ssh VM_NAME` 后，会以 vagrant 用户身份登录到目标虚拟机，如果当前目录的 Vagrantfile 中只有一个虚拟机那么无需指定虚拟机名称(init 后默认就是)；虚拟机内(box 封装时)vagrant这个用户拥有全局免密码 sudo 权限；root 用户一般密码为 vagrant**

### 三、Vagrantfile

> 我发现基本国内所有的 Vagrant 教程都是简单的提了一嘴那几个常用命令；包括我上面也写了点，估计可能到这已经被喷了("妈的那几个命令老子 help 一下就出来了，一看一猜就知道啥意思 用得着你讲？")；个人觉得 Vagrant 最复杂的是这个配置文件，以下直接上一个目前仓库里的做示例，仓库地址 [戳这里](https://github.com/mritd/config/tree/master/vagrant)

**直接贴 Vagrantfile，以下配置在进行 `vagrant up` 之前可能需要使用 `vagrant plugin install vagrant-host` 插件，以支持自动在各节点之间添加 host**

``` sh
Vagrant.configure("2") do |config|
    # 定义虚拟机数量
    vms = Array(1..5)
    # 数据盘存放目录
    $data_base_dir = "/data/vm/disk"
    vms.each do |i|
        config.vm.define "docker#{i}" do |docker|
            # 设置虚拟机的Box
            docker.vm.box = "centos/7"
            # 不检查 box 更新
            docker.vm.box_check_update = false 
            # 设置虚拟机的主机名
            docker.vm.hostname="docker#{i}.node"
            # 设置虚拟机的IP (wlp2s0 为桥接本机的网卡)
            docker.vm.network "public_network", ip: "192.168.1.1#{i}", bridge: "wlp2s0"
            # 设置主机与虚拟机的共享目录
            #docker.vm.synced_folder "~/Desktop/share", "/home/vagrant/share"
            # VirtaulBox相关配置
            docker.vm.provider "virtualbox" do |v|
                # 设置虚拟机的名称
                v.name = "docker#{i}"
                # 设置虚拟机的内存大小  
                v.memory = 1536 
                # 设置虚拟机的CPU个数
                v.cpus = 1
                # 增加磁盘
                docker_disk = "#$data_base_dir/docker-disk#{i}.vdi"
                data_disk = "#$data_base_dir/data-disk#{i}.vdi"
                # 判断虚拟机启动后
                if ARGV[0] == "up"
                    # 如果两个文件都不存在 则创建 SATA 控制器(这里调用的是 Virtual Box 的命令)
                    if ! File.exist?(docker_disk) && ! File.exist?(data_disk)
                        v.customize [
                            'storagectl', :id,
                            '--name', 'SATA Controller',
                            '--add', 'sata',
                            '--portcount', '5',
                            '--controller', 'IntelAhci',
                            '--bootable', 'on'
                        ]
                    end
                    # 创建磁盘文件
                    if ! File.exist?(docker_disk)
                        v.customize [
                            'createhd', 
                            '--filename', docker_disk, 
                            '--format', 'VDI', 
                            '--size', 10 * 1024 # 10 GB
                        ] 
                    end
                    if ! File.exist?(data_disk)
                        v.customize [
                            'createhd', 
                            '--filename', data_disk, 
                            '--format', 'VDI', 
                            '--size', 10 * 1024 # 10 GB
                        ] 
                    end
                    # 连接到 SATA 控制器
                    v.customize [
                        'storageattach', :id, 
                        '--storagectl', 'SATA Controller', 
                        '--port', 1, '--device', 0, 
                        '--type', 'hdd', '--medium', 
                        docker_disk
                    ]
                    v.customize [
                        'storageattach', :id, 
                        '--storagectl', 'SATA Controller', 
                        '--port', 2, '--device', 0, 
                        '--type', 'hdd', '--medium', 
                        data_disk
                    ]
                end
            end
            # 增加各节点 host 配置
            config.vm.provision :hosts do |provisioner|
                vms.each do |x|
                    provisioner.add_host "192.168.1.1#{x}", ["docker#{x}.node"]
                end
            end
            # 自定义执行脚本
            docker.vm.provision "shell", path: "init.sh"
            # 每次开机后重启 network 和 ssh，解决公网网卡不启动问题 
            docker.vm.provision "shell", run: "always", inline: <<-SHELL
                systemctl restart network
                systemctl restart sshd
                echo -e "\033[32mvirtual machine docker#{i} init success!\033[0m"
            SHELL
        end
    end
end
```

以上基本都加了注释，所以大致应该很清晰，至于第一行那个 `Vagrant.configure("2")` 代表调用第二版 API，不能改动，其他的可参考注释同时综合仓库中的其他配置文件即可

**Vagrantfile 实质上就是一个 ruby 文件，可以自己在里面定义变量等，可以在里面按照 ruby 的语法进行各种复杂的操作；具体 ruby 语法可以参考相关文档学习一下**


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
