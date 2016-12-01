---
layout: post
title: Raspberry Pi2 折腾
categories: [Linux, Raspberry Pi2]
description: Raspberry Pi2 折腾
keywords: Linux,Raspberry Pi2
---

### 开启Root用户

> 初次使用pi用户登录后，默认密码为 raspberry，然后应该搞开Root用户，和Debian系列一样(我特么只用过基于Debian的，如Ubuntu，还没玩过纯血统Debian)，默认树莓派Root用户是未启用的，密码每次开机都变，执行以下命令开启Root用户，并更改密码:

```sh
sudo passwd root
# 然后输两次密码，可以su过去了，不过这时你会发现
# 仍然无法远程以root登录，修改如下配置中的 PermitRootLogin 参数即可
vi /etc/ssh/sshd_config
# 该参数码值如下

# 允许root用户以任何认证方式登录
PermitRootLogin yes  

# 只允许root用public key认证方式登录
PermitRootLogin without-password      

# 不允许root远程登录
PermitRootLogin no  
```

---
> 以下相关设置大部分在root权限下进行

---

### 解决vi方向/删除失灵

```sh
# 直接编辑vim配置文件，注意先调整到要改的位置，再编辑
# 因为一旦进入Insert模式 方向键是不好使的
vi /etc/vim/vimrc.tiny

# 修改后如下
set nocompatible
set backspace=2
```

### less语法高亮

> 1. 执行命令 `apt-get install source-highlight`
> 2. 加入环境变量(更详细参考 [这里](http://leonyoung.sinaapp.com/blog/2013/10/syntax-highlight-in-less/))


```sh
export LESSOPEN='| /usr/share/source-highlight/src-hilite-lesspipe.sh %s'
export LESS=' -R -N '
```
### 设置自动连接 WiFi

- 编辑 /etc/network/interfaces 文件

> 一般只有一个无线网卡的话默认为 wlan0，修改 `iface wlan0 inet manual` 为 `iface wlan0 inet dhcp`，因为考虑到网络环境，频繁切换网络不适合设置静态IP，所以使用 DHCP 分配，样例配置文件如下:

```sh
# Please note that this file is written to be used with dhcpcd.
# For static IP, consult /etc/dhcpcd.conf and 'man dhcpcd.conf'.

auto lo
iface lo inet loopback

# 自动连接有线网卡
auto eth0
allow-hotplug eth0
iface eth0 inet manual

# 自动连接 无线网卡
auto wlan0
# 允许热插拔
allow-hotplug wlan0
# IP采用 DHCP 分配
iface wlan0 inet dhcp
# SSID 等相关设置(wifi密码啥的)
wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf

auto wlan1
allow-hotplug wlan1
iface wlan1 inet dhcp
wpa-conf /etc/wpa_supplicant/wpa_supplicant.conf
```

- 编辑 /etc/wpa_supplicant/wpa_supplicant.conf 文件

> 该文件主要存储无线网络连接的相关设置，包括SSID、密码、加密方式等，配置样例如下

```sh
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1

network={
  # Wifi SSID
  ssid="mritd"
  # Wifi Password
  psk="12345678"
  # 网络优先级， network块可以有多个，也就是可以设置多个无线链接及密码，
  # 当有多个Wifi都存在时，根据这个值选择优先链接，越大优先级越高，不可为负数
  priority=5
}
```

**其中 network 部分最好使用工具生成，命令如下 `wpa_passphrase SSID PASSWD`**

- 启用网卡链接

> 执行 `ifup wlan0` 启动 wlan0 并连接，执行 `ifdown wlan0` 关闭并断开链接，如下图:
![ifup_wlan0](http://7xoixd.com1.z0.glb.clouddn.com/raspberry_ifup_wlan0.png)
>
链接成功后可执行 `ifconfig` 或 `iwconfig`查看网络连接状况，如下图:
![iwconfig](http://7xoixd.com1.z0.glb.clouddn.com/raspberry_iwconfig_wlan0.png)
>
![ifconfig](http://7xoixd.com1.z0.glb.clouddn.com/raspberry_ifconfig_wlan0.png)

### 关闭 WiFi 休眠

默认情况下树莓派的 wifi 时会自动休眠的，使用如下命令关闭网卡休眠

``` sh
# 检测网卡休眠状态 1 代表会自动休眠 0 反之
cat /sys/module/8192cu/parameters/rtw_power_mgnt
# 如果为1 编辑 8192cu.conf 文件关闭休眠(此文件没有可新建)
vim /etc/modprobe.d/8192cu.conf
# 内容如下

# Disable power saving
options 8192cu rtw_power_mgnt=0
```

修改配置后重启即可

### 设置命令提示符风格

- 命令提示相关设置

> Linxu命令提示符由 PS1变量控制，所以更改命令提示符样式也就是更改PS1变量，以下为相关码值:

```
\d ：#代表日期，格式为weekday month date，例如："Mon Aug 1"   
\H ：#完整的主机名称。   
\h ：#仅取主机的第一个名字，如上例，则为fc4，.linux则被省略   
\t ：#显示时间为24小时格式，如：HH：MM：SS   
\T ：#显示时间为12小时格式   
\A ：#显示时间为24小时格式：HH：MM   
\u ：#当前用户的账号名称   
\v ：#BASH的版本信息   
\w ：#完整的工作目录名称。家目录会以 ~代替   
\W ：#利用basename取得工作目录名称，所以只会列出最后一个目录   
\# ：#下达的第几个命令   
\$ ：#提示字符，如果是root时，提示符为：# ，普通用户则为：$
```

> 颜色及效果控制码值

```
 前景    背景     颜色
------------------------
  30      40      黑色   
  31      41      红色   
　32      42      绿色   
　33      43      黄色   
　34      44      蓝色   
　35      45      紫红色   
　36      46      青蓝色   
　37      47      白色  
　
 代码          意义   
-------------------------   
  0            OFF   
  1            高亮显示   
  4            underline   
  5            闪烁   
  7            反白显示   
  8            不可见  
```

> 设置PS1变量时，`\[\e[F;Bm]` 代表颜色开始，F为前景色，B为背景色，`\e[m]` 为颜色结束符，不写的话会造成整个命令行都是最后一种颜色，以下为我的PS1样式

```sh
PS1='\[\e[1;32m\][\u@\h\[\e[m\] \[\e[1;34m\]\W\[\e[m\]\[\e[1;32m\]]$\[\e[m\] '
```

### 设置开机自动同步时间

> 众所周知树莓派不加扩展板的情况下 没有硬件RTC时钟，也就意味着每次开机都要设置时钟，这特么可万万不能够啊，以下为设置开机自动同步时间的方法：

- 安装ntp

```sh
apt-get install ntpdate
```

- 设置时区

```sh
# 执行如下命令
dpkg-reconfigure tzdata
# 选择 Asia(亚洲) 然后选择 ShanHai(上海)
```

- 手动校对时间

```sh
# 一般上面设置完市区就应该已经自动同步时间了
# 执行以下命令可能会报socket占用，可忽略
# 210.72.145.44 国家授时中心服务器IP
ntpdate 210.72.145.44
```

- 设置开机自动校对时间

> 编辑 `/ect/rc.local` 文件 执行 `vim /etc/rc.local`，加入 `htpdate -t -s 210.72.145.44` 这条命令，注意要放在 `exit 0` 前面，样例配置如下:

```sh
#!/bin/sh -e

# 此处省略1000行注释.....

# Sync Time
htpdate -t -s 210.72.145.44

# Print the IP address
_IP=$(hostname -I) || true
if [ "$_IP" ]; then
  printf "My IP address is %s\n" "$_IP"
fi

exit 0
```

### 合并剩余分区空间

> 默认树莓派安装系统后并不会占用所有SD卡空间，一般只会使用4G左右，对于大内存卡来说剩下的空间属于未分配状态，即未分区无法使用，我们可以使用 `fdisk` 来合并后面的分区加以利用

#### 使用 raspi-config(2016-08-13 更新)

推荐直接使用树莓派提供的工具，执行 `raspi-config`，然后选择第一项，提示选择 OK ，最终 Finish 即可。

#### 使用 分区工具

- 查看分区及起始参数

```sh
# 进入fdisk
fdisk /dev/mmcblk0
# 按 P 显示分区信息，并记录 Type 为Linux的分区起始柱面(122880)，打印如下:
Device         Boot  Start     End Sectors Size Id Type
/dev/mmcblk0p1        8192  122879  114688  56M  c W95 FAT32 (LBA)
/dev/mmcblk0p2      122880 8447999 8325120   4G 83 Linux
```

- 删除 主分区(Linux分区)

```sh
# 按D 并选择删除分区2，再按P 查看分区信息，打印如下:
Command (m for help): d
Partition number (1,2, default 2): 2

Partition 2 has been deleted.

Command (m for help): p
Disk /dev/mmcblk0: 28.8 GiB, 30908350464 bytes, 60367872 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0xba2edfb9

Device         Boot Start    End Sectors Size Id Type
/dev/mmcblk0p1       8192 122879  114688  56M  c W95 FAT32 (LBA)
```

- 增加新分区

```sh
# 按N 执行新建分区，再按P 选择增加主分区，并输入起始柱面(122880)，打印如下:
Command (m for help): n
Partition type
   p   primary (1 primary, 0 extended, 3 free)
   e   extended (container for logical partitions)
Select (default p): p
Partition number (2-4, default 2): 2
First sector (2048-60367871, default 2048): 122880
Last sector, +sectors or +size{K,M,G,T,P} (122880-60367871, default 60367871):

Created a new partition 2 of type 'Linux' and of size 28.7 GiB.
```

- 执行增加分区操作

```sh
# 首先按P 查看一下，确认分区增加无误，然后按W 执行分区操作，打印如下:
Command (m for help): p
Disk /dev/mmcblk0: 28.8 GiB, 30908350464 bytes, 60367872 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: dos
Disk identifier: 0xba2edfb9

Device         Boot  Start      End  Sectors  Size Id Type
/dev/mmcblk0p1        8192   122879   114688   56M  c W95 FAT32 (LBA)
/dev/mmcblk0p2      122880 60367871 60244992 28.7G 83 Linux


Command (m for help): w
The partition table has been altered.
# 此处说明 设备忙碌，新的分区表将在下次重启生效
Calling ioctl() to re-read partition table.
Re-reading the partition table failed.: Device or resource busy

The kernel still uses the old table. The new table will be used at the next reboot or after you run partprobe(8) or kpartx(8).
```

- 重启并执行分区修复

```sh
# 由于上面已经提示了重启生效，所以执行重启命令
reboot
# 重启后需要进行一次分区修复，否则df查看磁盘占用是不变的，执行如下命令修复分区
resize2fs /dev/mmcblk0p2
# 执行成功后使用df查看分区占用情况，打印如下:
[root@raspberrypi ~]# df
Filesystem     1K-blocks    Used Available Use% Mounted on
/dev/root       29586708 3255252  25069844  12% /
devtmpfs          469756       0    469756   0% /dev
tmpfs             474060       0    474060   0% /dev/shm
tmpfs             474060    6412    467648   2% /run
tmpfs               5120       4      5116   1% /run/lock
tmpfs             474060       0    474060   0% /sys/fs/cgroup
/dev/mmcblk0p1     57288   20232     37056  36% /boot
tmpfs              94812       0     94812   0% /run/user/1000
```


### 安装lrzsz(快捷上传下载)

> 操作简单，但大有用处，执行一条命令 `apt-get install lrzsz` 就安装成功了；作用就是在使用xShell通过ssh连接到树莓派后，上传文件只需要敲 `rz` 命令就会弹出文件选择对话框，选择文件后就直接上传到当前shell显示的目录下了，也可以直接将文件拖向命令行，也会直接将文件上传到当前目录；下载的话直接敲 `sz FILENAME` 就会马上弹出下载选择框，选择到哪就会下载到那个目录，奏是这么吊！

### 切换国内源

默认树莓派连接的源是官方源，其服务器在美国，然后你懂得......编辑 `/etc/apt/sources.list` 注释掉其他源，从 [树莓派源列表](http://www.raspbian.org/RaspbianMirrors) 中选择一个填入，然后 `apt-get update` 即可，以下为 `/etc/apt/sources.lis` 文件参考(清华大学源)

``` sh
#deb http://mirrordirector.raspbian.org/raspbian/ jessie main contrib non-free rpi
# Uncomment line below then 'apt-get update' to enable 'apt-get source'
#deb-src http://archive.raspbian.org/raspbian/ jessie main contrib non-free rpi
deb http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ jessie main non-free contrib
deb-src http://mirrors.tuna.tsinghua.edu.cn/raspbian/raspbian/ jessie main non-free contrib
```

### 编译并安装Nginx

> 由于做J2EE开发，想搞个Nginx，so 鼓捣吧......

- 下载相关组件源码

> Nginx 编译安装需要 如下支持
> gcc pcre pcre-devel zlib zlib-devel openssl openssl-devel
> 默认gcc树莓派已经自带了，剩下的 pcre、zlib、openssl 需要自己下载，下载地址: [pcre](http://www.pcre.org/)、[zlib](http://www.zlib.net/)、[openssl](https://www.openssl.org/source/)、[Nginx](http://nginx.org/en/download.html)

- 解压相关组件

```sh
# 下载下来想办法搞到树莓派上，然后解压
tar -zxvf openssl-1.0.2d.tar.gz
tar -zxvf pcre-8.37.tar.gz
tar -zxvf zlib-1.2.8.tar.gz
tar -zxvf nginx-1.8.0.tar.gz
```

- 执行编译安装

```sh
# 首先进入到 nginx目录
cd nginx-1.8.0
# 执行编译，编译参数如下:
./configure
--sbin-path=/usr/local/nginx/nginx
--conf-path=/usr/local/nginx/nginx.conf
--pid-path=/usr/local/nginx/nginx.pid
--with-http_ssl_module
--with-pcre=../pcre-8.37
--with-zlib=../zlib-1.2.8
--with-openssl=../openssl-1.0.2d
# 最后安装(时间有点长......)
make && make install
```

### 安装花生壳(内网穿透)

> 作为一名 Java Web狗，Nginx、Tomcat已经搞起了，只能内网访问怎么可以；所以必须搞一个 花生壳做内网映射，使之通过域名可直接从外网访问到内网下的树莓派中部署的项目。

- 下载花生壳并解压

> 花生壳树莓派版下载地址: [点击下载](http://hsk.oray.com/download/#type=http|shumeipai)
> 下载后上传到树莓派，执行 `tar -zxvf phddns_raspberry.tgz` 解压文件

- 安装并运行花生壳

> 解压后会生成 `phddns2` 目录，`cd` 进去，执行 `./oraynewph start` 命令进行安装，安装完成后屏幕上会显示几行信息，其中一个是 __SN码__，记录下这个 __SN码__，一般是一串复杂的类似于md5的字符串
> 然后进入 [b.oray.com](http://b.oray.com) ，选择使用 __SN码__ 登录，默认密码是admin，***注意：此时树莓派必须成功连接外网，否则无法登陆***，登录如下图所示:

> ![登录](http://7xoixd.com1.z0.glb.clouddn.com/raspberry_oray_login.png)

> 登陆后首先选择 ***动态域名解析*** ，然后 ***注册一个壳域名*** ，再回到首页选择 ***内网映射*** ，配置一个域名内网映射即可，映射配置如下图:

> ![内网映射配置](http://7xoixd.com1.z0.glb.clouddn.com/raspberry_oray_netmapper.png)

> 其他关于更详细的花生壳使用教程请谷歌，安装教程参考 [这里](http://service.oray.com/question/2680.html)，最后附上一张装好逼的截图:

> ![动态域名访问树莓派Nginx](http://7xoixd.com1.z0.glb.clouddn.com/raspberry_oray_netmapperopen.png)

### 编译安装Nexus

> 由于现在项目都使用Maven，所以也想搞一个私服Nexus，无奈Nexus官方二进制包中并不提供 arm平台支持，主要是wrapper 没有arm平台的可执行文件和动态链接库，故需要自己编译wrapper，所以有了 "编译安装Nexus" 这一说法。

- 下载 Nexus

> 登录 [Nexus官网](http://www.sonatype.org/nexus/go/) 选择 TGZ 格式下载，上传到 树莓派并解压，然后 mv 到你想要放置的目录。配置一个环境变量，样例如下 : `export NEXUS_HOME='/usr/local/java/nexus/nexus-2.11.4-01'`，并将 `$NEXUS_HOME/bin` 加入到 `PATH` 中。

- 下载wrapper

> 为何需要下载 `wrapper` : `nexus` 本身确实自带了 `wrapper`，但 `wrapper` 这玩意是跟平台结合的，目前 `Nexus` 不支持 `arm` 平台，所以需要我们手动编译一个替换 `Nexu` 中的 `wrapper`。
> ****
> 1. 目前下载的最新版 Nexus-2.11.4-01 依赖的是 wrapper3.2.3，下载地址 [点这里](http://wrapper.tanukisoftware.com/download/3.5.9/wrapper_3.5.9_src.tar.gz?mode=html) ***(注意我们下载的事3.5.9版本)***。
> 2. 下载完 src 源码包后上传到树莓派并解压，在开始编译前，需要正确的配置`JAVA_HOME` 和 `PATH`，这里有个小问题，树莓派2自带了JDK8，但 `JAVA_HOME` 啥的没配置，所以会有问题；但直接卸载的话 `apt-get` 会自动给你安装 `open-jdk7`，可执行 `apt-cache rdepends oracle-java8-jdk` 查看依赖 `jdk` 的相关软件包，并执行 `apt-get purge xxxxx` 卸载他们，基本这些软件包都是教学用的，可以删掉；然后自己下载 `arm` 平台的 `jdk7` (感觉8太新了怕不稳定) 安装、配置环境。

- 编译 wrapper

> 1. 配置完 `JAVA_HOME`、`PATH` 变量以后还需要下载一个 `Ant`，因为 `wrapper` 是基于 `Ant` 构建的，基本步骤也是。 [下载Ant](http://ant.apache.org/bindownload.cgi) 然后解压到指定目录，配置一下 `ANT_HOME`，方法自查。
> 2. 在正式编译前需要 `cp src/c/Makefile-linux-x86-32.make` to `src/c/Makefile-linux-arm-32.make` (老外的原文，说来了就是 `copy` 一份到当前目录并重命名一下)。
> 3. 进入到 `wrapper` 解压后的目录执行 `./build32.sh` 进行编译，如果 `JAVA_HOME`、`PATH`、`Ant`、`.make 文件` 没问题的话编译一般不会出错。
> 4. 编译完成后在 `nexus-2.11.4-01/bin/jsw` 下新建一个 `linux-armv7l-32` 文件夹，复制编译好的 `wrapper_3.5.9_src/bin/wrapper` 文件到 刚刚新建的 `linux-armv7l-32` 目录下，由于***使用了高版本*** `wrapper`，`wrapper.jar` 复制过去后需要先删掉原来的 `wrapper-3.2.3.jar` 并将 `wrapper.jar` 重命名为 `wrapper-3.2.3.jar`。

- 配置并启动 Nexus

> - 新建用户 `nexus` : `adduser nexus` (别用 `useradd` 我一直以为这两个命令一样，但你在树莓派2下可以试试)
> - 改密码 : `passwd nexus`
> - 改两个配置文件 : `nexus-2.11.4-01/bin/nexus`、`nexus-2.11.4-01/bin/jsw/conf/wrapper.conf`，两个配置要改的地方贴出来如下 (更详细的参见 [Nexus 2.11 CentOS搭建教程](http://mritd.me/archives/2024)) :

```sh
###############################
## nexus-2.11.4-01/bin/nexus ##
###############################
#
# Set the JVM executable
# (modify this to absolute path if you need a Java that is not on the OS path)
# 配置 jdk中 java 可执行文件的位置(其实我感觉jre就可以，没测试，有兴趣的测试一下)
wrapper.java.command=/usr/local/java/jdk1.7.0_79/bin/java
```

```sh
##############################################
## nexus-2.11.4-01/bin/jsw/conf/wrapper.con ##
##############################################
#
# Set this to the root of the Nexus installation
# 设置 nexus 主目录，就是解压后的那个 nexus目录绝对路径
NEXUS_HOME="/usr/local/java/nexus-2.11.4-01"
```

> -  先切换到 `nexus` 用户，因为官方不推荐以 `root` 用户运行，执行 : `su - nexus`，然后启动 `nexus`，执行 `nexus start` 启动，时间比较长，大约2分钟，使用 `tail -f nexus-2.11.4-01/logs/wrapper.log` 查看进度，启动成功后访问 `IP:8081/nexus` 即可，默认用户 `admin`，密码 `admin123`；到此结束。

### 编译安装MySQL

- 安装Screen

> 执行 `apt-get install screen` 安装screen，用于后台运行编译任务，防止断网等原因造成的编译失败。

- 下载MySQL5.6源码

> 可去官网下载，百度云分享 [点击这里]( http://pan.baidu.com/s/1dDwPxRV) 密码: g2ab
> 下载完成后上传到树莓派并解压

- 系统设置初始化

> 编译前需要做以下操作:

```sh
# 新建mysql用户
adduser mysql
# 创建MySQL安装目录
cd /usr/local
mkdir mysql
cd /usr/local/mysql
mkdir data
```

- 安装依赖包

```sh
# 首先升级软件源(如果改过非官方源必须改回来)
apt-get update
# 升级已安装软件包
apt-get upgrade
# 安装mysql编译时依赖
apt-get isntall cmake make bison bzr libncurses5-dev g++ libtinfo5 ncurses-bin libncurses5 libtinfo-dev
```
- 开始编译MySQL

```sh
# 进入源码目录
cd mysql-5.6.27/
# 开启screen session 防止断网等造成的免疫中断
screen -S mysqlinstall
# 执行 cmake 预编译(最少一小时)
cmake -DCMAKE_INSTALL_PREFIX=/usr/local/mysql -DMYSQL_UNIX_ADDR=/usr/local/mysql/data/mysql.sock -DDEFAULT_CHARSET=utf8 -DDEFAULT_COLLATION=utf8_general_ci -DEXTRA_CHARSETS=all -DWITH_MYISAM_STORAGE_ENGINE=1 -DWITH_INNOBASE_STORAGE_ENGINE=1 -DWITH_MEMORY_STORAGE_ENGINE=1 -DWITH_READLINE=1 -DENABLED_LOCAL_INFILE=1 -DMYSQL_DATADIR=/usr/local/mysql/data -DMYSQL_USER=mysql -DWITH_DEBUG=0
```

> 关于cmake预编译参数设置参考 [这里](http://ohgenlong16300.blog.51cto.com/499130/1264096)

- 执行安装

```sh
make && make install
```

- 后续操作

```sh
# 更改所有者
cd /usr/local/
chown -R mysql.mysql mysql
# 创建配置文件
cd /usr/local/mysql/support-files  
cp my-default.cnf  /etc/my.cnf
# 初始化数据库
cd /usr/local/mysql
./scripts/mysql_install_db --user=mysql
# 安全启动(后台)
/usr/local/mysql/bin/mysqld_safe --user=mysql --port=3306 --sock=/usr/local/mysql/data/mysql.sock &
# 开机自启动
cp /usr/local/mysql/support-files/mysql.server /etc/init.d/mysql
chkconfig --add mysql
```

> mysql5.6的默认参数设置问题，更改my.cnf，调整以下参数
`performance_schema_max_table_instances=600`
`table_definition_cache=400`
`table_open_cache=256`
这时mysql启动后内存就只占用40--60M内存了

### 安装 xrdp远程桌面

> 其实树莓派感觉没必要买显示器，因为直接可以安装远程桌面，执行 `apt-get install xrdp` 安装，在 `Windows` 下可直接使用远程桌面连接，按 `Win+R` 键输入 `mstsc`，再输入树莓派地址和用户名密码   就可以，截图如下:
![远程桌面](http://7xoixd.com1.z0.glb.clouddn.com/raspberry_xrdp.png)
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
