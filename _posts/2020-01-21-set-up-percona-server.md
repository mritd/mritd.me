---
layout: post
categories: Linux
title: Percona MySQL 搭建
date: 2020-01-21 20:41:22 +0800
description: Percona MySQL 搭建
keywords: percona,mysql
catalog: true
multilingual: false
tags: Linux
---

> 最近被拉去折腾 MySQL 了，Kuberntes 相关的文章停更了好久... MySQL 折腾完了顺便记录一下折腾过程，值得注意的是本篇文章从实际生产环境文档中摘录，部分日志和数据库敏感信息已被胡乱替换，所以不要盲目复制粘贴。

## 一、版本信息

目前采用 MySQL fork 版本 Percona Server 5.7.28，监控方面选择 Percona Monitoring and Management 2.1.0，对应监控 Client 版本为 2.1.0

## 二、Percona Server 安装

为保证兼容以及稳定性，MySQL 宿主机系统选择 CentOS 7，Percona Server 安装方式为 rpm 包，安装后由 Systemd 守护

### 2.1、下载安装包

安装包下载地址为 [https://www.percona.com/downloads/Percona-Server-5.7/LATEST/](https://www.percona.com/downloads/Percona-Server-5.7/LATEST/)，下载时选择 `Download All Packages Together`，下载后是所有组件全量的压缩 tar 包。

### 2.2、安装前准备

针对 CentOS 7 系统，安装前升级所有系统组件库，执行 `yum update` 既可；大部份 **CentOS 7 安装后可能会附带 `mariadb-libs` 包，这个包会默认创建一些配置文件，导致后面的 Percona Server 无法覆盖它(例如 `/etc/my.cnf`)，所以安装 Percona Server 之前需要卸载它 `yum remove mariadb-libs`**

针对于数据存储硬盘，目前统一为 SSD 硬盘，挂载点为 `/data`，挂载方式可以采用 `fstab`、`systemd-mount`，分区格式目前采用 `xfs` 格式。

**SSD 优化有待补充...**

### 2.3、安装 Percona Server

Percona Server tar 包解压后会有 9 个 rpm 包，实际安装时只需要安装其中 4 个既可

```sh
yum install Percona-Server-client-57-5.7.28-31.1.el7.x86_64.rpm Percona-Server-server-57-5.7.28-31.1.el7.x86_64.rpm Percona-Server-shared-57-5.7.28-31.1.el7.x86_64.rpm Percona-Server-shared-compat-57-5.7.28-31.1.el7.x86_64.rpm
```

### 2.4、安装后调整

#### 2.4.1、硬盘调整

目前 MySQL 数据会统一存放到 `/data` 目录下，所以需要将单独的数据盘挂载到 `/data` 目录；**如果是 SSD 硬盘还需要调整系统 I/O 调度器等其他优化。**

#### 2.4.2、目录预创建

Percona Server 安装完成后，由于配置调整原因，还会用到一些其他的数据目录，这些目录可以预先创建并授权

``` sh
mkdir -p /var/log/mysql /data/mysql_tmp
chown -R mysql:mysql /var/log/mysql /data/mysql_tmp
```

`/var/log/mysql` 目录用来存放 MySQL 相关的日志(不包括 binlog)，`/data/mysql_tmp` 用来存放 MySQL 运行时产生的缓存文件。

#### 2.4.3、文件描述符调整

由于 rpm 安装的 Percona Server 会采用 Systemd 守护，所以如果想修改文件描述符配置应当调整 Systemd 配置文件

```sh
vim /usr/lib/systemd/system/mysqld.service

# Sets open_files_limit
# 注意 infinity = 65536
LimitCORE = infinity
LimitNOFILE = infinity
LimitNPROC = infinity
```

然后执行 `systemctl daemon-reload` 重载既可。

#### 2.4.4、配置文件调整

Percona Server 安装完成后也会生成 `/etc/my.cnf` 配置文件，不过不建议直接修改该文件；修改配置文件需要进入到 `/etc/percona-server.conf.d/` 目录调整相应配置；以下为配置样例(**生产环境 mysqld 配置需要优化调整**)

**mysql.cnf**

```ini
[mysql]
auto-rehash
default_character_set=utf8mb4
```

**mysqld.cnf**

```ini
# Percona Server template configuration

[mysqld]
#
# Remove leading # and set to the amount of RAM for the most important data
# cache in MySQL. Start at 70% of total RAM for dedicated server, else 10%.
# innodb_buffer_pool_size = 128M
#
# Remove leading # to turn on a very important data integrity option: logging
# changes to the binary log between backups.
# log_bin
#
# Remove leading # to set options mainly useful for reporting servers.
# The server defaults are faster for transactions and fast SELECTs.
# Adjust sizes as needed, experiment to find the optimal values.
# join_buffer_size = 128M
# sort_buffer_size = 2M
# read_rnd_buffer_size = 2M
port=3306
datadir=/data/mysql
socket=/data/mysql/mysql.sock
pid_file=/data/mysql/mysqld.pid

# 服务端编码
character_set_server=utf8mb4
# 服务端排序
collation_server=utf8mb4_general_ci
# 强制使用 utf8mb4 编码集，忽略客户端设置
skip_character_set_client_handshake=1
# 日志输出到文件
log_output=FILE
# 开启常规日志输出
general_log=1
# 常规日志输出文件位置
general_log_file=/var/log/mysql/mysqld.log
# 错误日志位置
log_error=/var/log/mysql/mysqld-error.log
# 记录慢查询
slow_query_log=1
# 慢查询时间(大于 1s 被视为慢查询)
long_query_time=1
# 慢查询日志文件位置
slow_query_log_file=/var/log/mysql/mysqld-slow.log
# 临时文件位置
tmpdir=/data/mysql_tmp
# 线程池缓存(refs https://my.oschina.net/realfighter/blog/363853)
thread_cache_size=30
# The number of open tables for all threads.(refs https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_table_open_cache)
table_open_cache=16384
# 文件描述符(此处修改不生效，请修改 systemd service 配置) 
# refs https://www.percona.com/blog/2017/10/12/open_files_limit-mystery/
# refs https://www.cnblogs.com/wxxjianchi/p/10370419.html
#open_files_limit=65535
# 表定义缓存(5.7 以后自动调整)
# refs https://dev.mysql.com/doc/refman/5.6/en/server-system-variables.html#sysvar_table_definition_cache
# refs http://mysql.taobao.org/monthly/2015/08/10/
#table_definition_cache=16384
sort_buffer_size=1M
join_buffer_size=1M
# MyiSAM 引擎专用(内部临时磁盘表可能会用)
read_buffer_size=1M
read_rnd_buffer_size=1M
# MyiSAM 引擎专用(内部临时磁盘表可能会用)
key_buffer_size=32M
# MyiSAM 引擎专用(内部临时磁盘表可能会用)
bulk_insert_buffer_size=16M
# myisam_sort_buffer_size 与 sort_buffer_size 区别请参考(https://stackoverflow.com/questions/7871027/myisam-sort-buffer-size-vs-sort-buffer-size)
myisam_sort_buffer_size=64M
# 内部内存临时表大小
tmp_table_size=32M
# 用户创建的 MEMORY 表最大大小(tmp_table_size 受此值影响)
max_heap_table_size=32M
# 开启查询缓存
query_cache_type=1
# 查询缓存大小
query_cache_size=32M
# sql mode
sql_mode='STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'

########### Network ###########
# 最大连接数(该参数受到最大文件描述符影响，如果不生效请检查最大文件描述符设置)
# refs https://stackoverflow.com/questions/39976756/the-max-connections-in-mysql-5-7
max_connections=1500
# mysql 堆栈内暂存的链接数量
# 当短时间内链接数量超过 max_connections 时，部分链接会存储在堆栈内，存储数量受此参数控制
back_log=256
# 最大链接错误，针对于 client 主机，超过此数量的链接错误将会导致 mysql server 针对此主机执行锁定(禁止链接 ERROR 1129 )
# 此错误计数仅在 mysql 链接握手失败才会计算，一般出现问题时都是网络故障
# refs https://www.cnblogs.com/kerrycode/p/8405862.html
max_connect_errors=100000
# mysql server 允许的最大数据包大小
max_allowed_packet=64M
# 交互式客户端链接超时(30分钟自动断开)
interactive_timeout=1800
# 非交互式链接超时时间(10分钟)
# 如果客户端有连接池，则需要协商此参数(refs https://database.51cto.com/art/201909/603519.htm)
wait_timeout=600
# 跳过外部文件系统锁定
# If you run multiple servers that use the same database directory (not recommended), 
# each server must have external locking enabled.
# refs https://dev.mysql.com/doc/refman/5.7/en/external-locking.html
skip_external_locking=1
# 跳过链接的域名解析(开启此选项后 mysql 用户授权的 host 方式失效)
skip_name_resolve=0
# 禁用主机名缓存，每次都会走 DNS
host_cache_size=0

########### REPL ###########
# 开启 binlog
log_bin=mysql-bin
# 作为从库时，同步信息依然写入 binlog，方便此从库再作为其他从库的主库
log_slave_updates=1
# server id，默认为 ipv4 地址去除第一段
# eg: 172.16.10.11 => 161011
server_id=161011
# 每次次事务 binlog 刷新到磁盘
# refs http://liyangliang.me/posts/2014/03/innodb_flush_log_at_trx_commit-and-sync_binlog/
sync_binlog=100
# binlog 格式(refs https://zhuanlan.zhihu.com/p/33504555)
binlog_format=row
# binlog 自动清理时间
expire_logs_days=10
# 开启 relay-log，一般作为 slave 时开启
relay_log=mysql-replay
# 主从复制时跳过 test 库
replicate_ignore_db=test
# 每个 session binlog 缓存
binlog_cache_size=4M
# binlog 滚动大小
max_binlog_size=1024M
# GTID 相关(refs https://keithlan.github.io/2016/06/23/gtid/)
#gtid_mode=1
#enforce_gtid_consistency=1

########### InnoDB ###########
# 永久表默认存储引擎
default_storage_engine=InnoDB
# 系统表空间数据文件大小(初始化为 1G，并且自动增长)
innodb_data_file_path=ibdata1:1G:autoextend
# InnoDB 缓存池大小
# innodb_buffer_pool_size 必须等于 innodb_buffer_pool_chunk_size*innodb_buffer_pool_instances，或者是其整数倍
# refs https://dev.mysql.com/doc/refman/5.7/en/innodb-buffer-pool-resize.html
# refs https://zhuanlan.zhihu.com/p/60089484
innodb_buffer_pool_size=7680M
innodb_buffer_pool_instances=10
innodb_buffer_pool_chunk_size=128M
# InnoDB 强制恢复(refs https://www.askmaclean.com/archives/mysql-innodb-innodb_force_recovery.html)
innodb_force_recovery=0
# InnoDB buffer 预热(refs http://www.dbhelp.net/2017/01/12/mysql-innodb-buffer-pool-warmup.html)
innodb_buffer_pool_dump_at_shutdown=1
innodb_buffer_pool_load_at_startup=1
# InnoDB 日志组中的日志文件数
innodb_log_files_in_group=2
# InnoDB redo 日志大小
# refs https://www.percona.com/blog/2017/10/18/chose-mysql-innodb_log_file_size/
innodb_log_file_size=256MB
# 缓存还未提交的事务的缓冲区大小
innodb_log_buffer_size=16M
# InnoDB 在事务提交后的日志写入频率
# refs http://liyangliang.me/posts/2014/03/innodb_flush_log_at_trx_commit-and-sync_binlog/
innodb_flush_log_at_trx_commit=2
# InnoDB DML 操作行级锁等待时间
# 超时返回 ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction
# refs https://ningyu1.github.io/site/post/75-mysql-lock-wait-timeout-exceeded/
innodb_lock_wait_timeout=30
# InnoDB 行级锁超时是否回滚整个事务，默认为 OFF 仅回滚上一条语句
# 此时应用程序可以接受到错误后选择是否继续提交事务(并没有违反 ACID 原子性)
# refs https://www.cnblogs.com/hustcat/archive/2012/11/18/2775487.html
#innodb_rollback_on_timeout=ON
# InnoDB 数据写入磁盘的方式，具体见博客文章
# refs https://www.cnblogs.com/gomysql/p/3595806.html
innodb_flush_method=O_DIRECT
# InnoDB 缓冲池脏页刷新百分比
# refs https://dbarobin.com/2015/08/29/mysql-optimization-under-ssd
innodb_max_dirty_pages_pct=50
# InnoDB 每秒执行的写IO量
# refs https://www.centos.bz/2016/11/mysql-performance-tuning-15-config-item/#10.INNODB_IO_CAPACITY,%20INNODB_IO_CAPACITY_MAX
innodb_io_capacity=500
innodb_io_capacity_max=1000
# 请求并发 InnoDB 线程数
# refs https://www.cnblogs.com/xinysu/p/6439715.html#_lab2_1_0
innodb_thread_concurrency=60
# 再使用多个 InnoDB 表空间时，允许打开的最大 ".ibd" 文件个数，不设置默认 300，
# 并且取与 table_open_cache 相比较大的一个，此选项独立于 open_files_limit
# refs https://dev.mysql.com/doc/refman/5.7/en/innodb-parameters.html#sysvar_innodb_open_files
innodb_open_files=65535
# 每个 InnoDB 表都存储在独立的表空间(.ibd)中
innodb_file_per_table=1
# 事务级别(可重复读，会出幻读)
transaction_isolation=REPEATABLE-READ
# 是否在搜索和索引扫描中使用间隙锁(gap locking)，不建议使用未来将删除
innodb_locks_unsafe_for_binlog=0
# InnoDB 后台清理线程数，更大的值有助于 DML 执行性能，>= 5.7.8 默认为 4
innodb_purge_threads=4
```

**mysqld_safe.cnf**

```ini
#
# The Percona Server 5.7 configuration file.
#
# One can use all long options that the program supports.
# Run program with --help to get a list of available options and with
# --print-defaults to see which it would actually understand and use.
#
# For explanations see
# http://dev.mysql.com/doc/mysql/en/server-system-variables.html

[mysqld_safe]
pid-file = /var/run/mysqld/mysqld.pid
socket   = /var/run/mysqld/mysqld.sock
nice     = 0
```

**mysqldump.cnf**

```ini
[mysqldump]
quick
default-character-set=utf8mb4
max_allowed_packet=256M
```

### 2.5、启动

配置文件调整完成后启动既可

```sh
systemctl start mysqld
```

启动完成后默认 root 密码会自动生成，通过 `grep 'temporary password' /var/log/mysql/*` 查看默认密码；获得默认密码后可以通过 `mysqladmin -S /data/mysql/mysql.sock -u root -p password` 修改 root 密码。

## 三、Percona Monitoring and Management

数据库创建成功后需要增加 pmm 监控，后续将会通过监控信息来调优数据库，所以数据库监控必不可少。

### 3.1、安装前准备

pmm 监控需要使用特定用户来监控数据信息，所以需要预先为 pmm 创建用户

```sql
USE mysql;
GRANT ALL PRIVILEGES ON *.* TO 'pmm'@'%' IDENTIFIED BY 'pmm12345' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

### 3.2、安装 PMM Server

pmm server 端推荐直接使用 docker 启动，以下为样例 docker compose

```yaml
version: '3.7'
services:
  pmm:
    image: percona/pmm-server:2.1.0
    container_name: pmm
    restart: always
    volumes:
      - data:/srv
    ports:
      - "80:80"
      - "443:443"
volumes:
  data:
```

**如果想要自定义证书，请将证书复制到 volume 内的 nginx 目录下，自定义证书需要以下证书文件**

```sh
pmmserver.node ➜ tree
.
├── ca-certs.pem
├── certificate.conf  # 此文件是 pmm 默认生成自签证书的配置文件，不需要关注
├── certificate.crt
├── certificate.key
└── dhparam.pem
```

**pmm server 启动后访问 `http(s)://IP_ADDRESS` 既可进入 granafa 面板，默认账户名和密码都是 `admin`**

### 3.3、安装 PMM Client

PMM Client 同样采用 rpm 安装，下载地址 [https://www.percona.com/downloads/pmm2/](https://www.percona.com/downloads/pmm2/)，当前采用最新的 2.1.0 版本；rpm 下载完成后直接 `yum install` 既可。

rpm 安装完成后使用 `pmm-admin` 命令配置服务端地址，并添加当前 mysql 实例监控

```sh
# 配置服务端地址
pmm-admin config --server-url https://admin:admin@pmm.mysql.node 172.16.0.11 generic mysql
# 配置当前 mysql 实例
pmm-admin add mysql --username=pmm --password=pmm12345 mysql 172.16.0.11:3306
```

完成后稍等片刻既可在 pmm server 端的 granafa 中看到相关数据。

## 四、数据导入

从原始数据库 dump 相关库，并导入到新数据库既可

```sh
# dump
mysqldump -h 172.16.1.10 -u root -p --master-data=2 --routines --triggers --single_transaction --databases DATABASE_NAME > dump.sql
# load
mysql -S /data/mysql/mysql.sock -u root -p < dump.sql
```

数据导入后重建业务用户既可

```sql
USE mysql;
GRANT ALL PRIVILEGES ON *.* TO 'test_user'@'%' IDENTIFIED BY 'test_user' WITH GRANT OPTION;
FLUSH PRIVILEGES;
```

## 五、数据备份

### 5.1、安装 xtrabackup

目前数据备份采用 Perconra xtrabackup 工具，xtrabackup 可以实现高速、压缩带增量的备份；xtrabackup 安装同样采用 rpm 方式，下载地址为 [https://www.percona.com/downloads/Percona-XtraBackup-2.4/LATEST/](https://www.percona.com/downloads/Percona-XtraBackup-2.4/LATEST/)，下载完成后执行 `yum install` 既可

### 5.2、备份工具

目前备份工具开源在 [GitHub](https://github.com/gozap/mybak) 上，每次全量备份会写入 `.full-backup` 文件，增量备份会写入 `.inc-backup` 文件

### 5.3、配置 systemd

为了使备份自动运行，目前将定时任务配置到 systemd 中，由 systemd 调度并执行；以下为相关 systemd 配置文件

**mysql-backup-full.service**

```sh
[Unit]
Description=mysql full backup
After=network.target

[Service]
Type=simple
Restart=on-failure
ExecStart=/usr/local/bin/mybak --backup-dir /data/mysql_backup --prefix mysql full

[Install]
WantedBy=multi-user.target
```

**mysql-backup-inc.service**

```sh
[Unit]
Description=mysql incremental backup
After=network.target

[Service]
Type=simple
Restart=on-failure
ExecStart=/usr/local/bin/mybak --backup-dir /data/mysql_backup --prefix mysql inc

[Install]
WantedBy=multi-user.target
```

**mysql-backup-compress.service**

```sh
[Unit]
Description=mysql backup compress
After=network.target

[Service]
Type=simple
Restart=on-failure
ExecStart=/usr/local/bin/mybak --backup-dir /data/mysql_backup --prefix mysql compress --clean

[Install]
WantedBy=multi-user.target
```

**mysql-backup-full.timer**

```sh
[Unit]
Description=mysql weekly full backup
# 备份之前依赖相关目录的挂载
After=data.mount
After=data-mysql_backup.mount

[Timer]
# 目前每周日一个全量备份
OnCalendar=Sun *-*-* 3:00
Persistent=true

[Install]
WantedBy=timers.target
```

**mysql-backup-inc.timer**

```sh
[Unit]
Description=mysql weekly full backup
After=data.mount
After=data-mysql_backup.mount

[Timer]
# 每天三个增量备份
OnCalendar=*-*-* 9:00
OnCalendar=*-*-* 13:00
OnCalendar=*-*-* 18:00
Persistent=true

[Install]
WantedBy=timers.target
```

**mysql-backup-compress.timer**

```sh
[Unit]
Description=mysql weekly backup compress
# 备份之前依赖相关目录的挂载
After=data.mount
After=data-mysql_backup.mount

[Timer]
# 目前每周日一个全量备份，自动压缩后同时完成清理
OnCalendar=Sun *-*-* 5:00
Persistent=true

[Install]
WantedBy=timers.target
```

创建好相关文件后启动相关定时器既可

```sh
cp *.timer *.service /lib/systemd/system
systemctl daemon-reload
systemctl start mysql-backup-full.timer mysql-backup-inc.timer mysql-backup-compress.timer
systemctl enable mysql-backup-full.timer mysql-backup-inc.timer mysql-backup-compress.timer
```

## 六、数据恢复

### 6.1、全量备份恢复

针对于全量备份，只需要按照官方文档的还原顺序进行还原既可

```sh
# 由于备份时进行了压缩，所以先解压备份文件
xtrabackup --decompress --parallel 4 --target-dir /data/mysql_backup/mysql-20191205230502
# 执行预处理
xtrabackup --prepare --target-dir /data/mysql_backup/mysql-20191205230502
# 执行恢复(恢复时自动根据 my.cnf 将数据覆盖到 data 数据目录)
xtrabackup --copy-back --target-dir /data/mysql_backup/mysql-20191205230502
# 修复数据目录权限
chown -R mysql:mysql /data/mysql
# 启动 mysql
systemctl start mysqld
```

### 6.2、增量备份恢复

对于增量备份恢复，其与全量备份恢复的根本区别在于: **对于非最后一个增量文件的预处理必须使用 `--apply-log-only` 选项防止运行回滚阶段的处理**

```sh
# 对所有备份文件进行解压处理
for dir in `ls`; do xtrabackup --decompress --parallel 4 --target-dir $dir; done
# 对全量备份文件执行预处理(注意增加 --apply-log-only 选项)
xtrabackup --prepare --apply-log-only --target-dir /data/mysql_backup/mysql-20191205230502
# 对非最后一个增量备份执行预处理
xtrabackup --prepare --apply-log-only --target-dir /data/mysql_backup/mysql-20191205230502 --incremental-dir /data/mysql_backup/mysql-inc-20191206230802
# 对最后一个增量备份执行预处理(不需要 --apply-log-only)
xtrabackup --prepare --target-dir /data/mysql_backup/mysql-20191205230502 --incremental-dir /data/mysql_backup/mysql-inc-20191207031005
# 执行恢复(恢复时自动根据 my.cnf 将数据覆盖到 data 数据目录)
xtrabackup --copy-back --target-dir /data/mysql_backup/mysql-20191205230502
# 修复数据目录权限
chown -R mysql:mysql /data/mysql
# 启动 mysql
systemctl start mysqld
```

### 6.3、创建 slave

针对 xtrabackup 备份的数据可以直接恢复成 slave 节点，具体步骤如下:

首先将备份文件复制到目标机器，然后执行解压(默认备份工具采用 lz4 压缩)

``` sh
xtrabackup --decompress --target-dir=xxxxxx
```

解压完成后执行预处理操作(**在执行预处理之前请确保 slave 机器上相关配置文件与 master 相同，并且处理好数据目录存放等**)

```sh
xtrabackup --user=root --password=xxxxxxx --prepare --target-dir=xxxx
```

预处理成功后便可执行恢复，以下命令将自动读取 `my.cnf` 配置，自动识别数据目录位置并将数据文件移动到该位置

```sh
xtrabackup --move-back --target-dir=xxxxx
```

所由准备就绪后需要进行权限修复

```sh
chown -R mysql:mysql MYSQL_DATA_DIR
```

最后在 mysql 内启动 slave 既可，slave 信息可通过从数据备份目录的 `xtrabackup_binlog_info` 中获取

``` sh
# 获取备份 POS 信息
cat xxxxxx/xtrabackup_binlog_info

# 创建 slave 节点
CHANGE MASTER TO
    MASTER_HOST='192.168.2.48',
    MASTER_USER='repl',
    MASTER_PASSWORD='xxxxxxx',
    MASTER_LOG_FILE='mysql-bin.000005',
    MASTER_LOG_POS=52500595;

# 启动 slave
start slave;
show slave status \G;
```

## 七、生产处理

### 7.1、数据目录

目前生产环境数据目录位置调整到 `/home/mysql`，所以目录权限处理也要做对应调整

```sh
mkdir -p /var/log/mysql /home/mysql_tmp
chown -R mysql:mysql /var/log/mysql /home/mysql_tmp
```

### 7.2、配置文件

生产环境目前节点配置如下

- CPU: `Intel(R) Xeon(R) CPU E5-2620 v4 @ 2.10GHz`
- RAM: `128G`

所以配置文件也需要做相应的优化调整

**mysql.cnf**

```ini
[mysql]
auto-rehash
default_character_set=utf8mb4
```

**mysqld.cnf**

```ini
# Percona Server template configuration

[mysqld]
#
# Remove leading # and set to the amount of RAM for the most important data
# cache in MySQL. Start at 70% of total RAM for dedicated server, else 10%.
# innodb_buffer_pool_size = 128M
#
# Remove leading # to turn on a very important data integrity option: logging
# changes to the binary log between backups.
# log_bin
#
# Remove leading # to set options mainly useful for reporting servers.
# The server defaults are faster for transactions and fast SELECTs.
# Adjust sizes as needed, experiment to find the optimal values.
# join_buffer_size = 128M
# sort_buffer_size = 2M
# read_rnd_buffer_size = 2M
port=3306
datadir=/home/mysql/mysql
socket=/home/mysql/mysql/mysql.sock
pid_file=/home/mysql/mysql/mysqld.pid

# 服务端编码
character_set_server=utf8mb4
# 服务端排序
collation_server=utf8mb4_general_ci
# 强制使用 utf8mb4 编码集，忽略客户端设置
skip_character_set_client_handshake=1
# 日志输出到文件
log_output=FILE
# 开启常规日志输出
general_log=1
# 常规日志输出文件位置
general_log_file=/var/log/mysql/mysqld.log
# 错误日志位置
log_error=/var/log/mysql/mysqld-error.log
# 记录慢查询
slow_query_log=1
# 慢查询时间(大于 1s 被视为慢查询)
long_query_time=1
# 慢查询日志文件位置
slow_query_log_file=/var/log/mysql/mysqld-slow.log
# 临时文件位置
tmpdir=/home/mysql/mysql_tmp
# The number of open tables for all threads.(refs https://dev.mysql.com/doc/refman/5.7/en/server-system-variables.html#sysvar_table_open_cache)
table_open_cache=16384
# 文件描述符(此处修改不生效，请修改 systemd service 配置) 
# refs https://www.percona.com/blog/2017/10/12/open_files_limit-mystery/
# refs https://www.cnblogs.com/wxxjianchi/p/10370419.html
#open_files_limit=65535
# 表定义缓存(5.7 以后自动调整)
# refs https://dev.mysql.com/doc/refman/5.6/en/server-system-variables.html#sysvar_table_definition_cache
# refs http://mysql.taobao.org/monthly/2015/08/10/
#table_definition_cache=16384
sort_buffer_size=1M
join_buffer_size=1M
# MyiSAM 引擎专用(内部临时磁盘表可能会用)
read_buffer_size=1M
read_rnd_buffer_size=1M
# MyiSAM 引擎专用(内部临时磁盘表可能会用)
key_buffer_size=32M
# MyiSAM 引擎专用(内部临时磁盘表可能会用)
bulk_insert_buffer_size=16M
# myisam_sort_buffer_size 与 sort_buffer_size 区别请参考(https://stackoverflow.com/questions/7871027/myisam-sort-buffer-size-vs-sort-buffer-size)
myisam_sort_buffer_size=64M
# 内部内存临时表大小
tmp_table_size=32M
# 用户创建的 MEMORY 表最大大小(tmp_table_size 受此值影响)
max_heap_table_size=32M
# 开启查询缓存
query_cache_type=1
# 查询缓存大小
query_cache_size=32M
# sql mode
sql_mode='STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION'

########### Network ###########
# 最大连接数(该参数受到最大文件描述符影响，如果不生效请检查最大文件描述符设置)
# refs https://stackoverflow.com/questions/39976756/the-max-connections-in-mysql-5-7
max_connections=1500
# mysql 堆栈内暂存的链接数量
# 当短时间内链接数量超过 max_connections 时，部分链接会存储在堆栈内，存储数量受此参数控制
back_log=256
# 最大链接错误，针对于 client 主机，超过此数量的链接错误将会导致 mysql server 针对此主机执行锁定(禁止链接 ERROR 1129 )
# 此错误计数仅在 mysql 链接握手失败才会计算，一般出现问题时都是网络故障
# refs https://www.cnblogs.com/kerrycode/p/8405862.html
max_connect_errors=100000
# mysql server 允许的最大数据包大小
max_allowed_packet=64M
# 交互式客户端链接超时(30分钟自动断开)
interactive_timeout=1800
# 非交互式链接超时时间(10分钟)
# 如果客户端有连接池，则需要协商此参数(refs https://database.51cto.com/art/201909/603519.htm)
wait_timeout=28800
# 跳过外部文件系统锁定
# If you run multiple servers that use the same database directory (not recommended), 
# each server must have external locking enabled.
# refs https://dev.mysql.com/doc/refman/5.7/en/external-locking.html
skip_external_locking=1
# 跳过链接的域名解析(开启此选项后 mysql 用户授权的 host 方式失效)
skip_name_resolve=0
# 禁用主机名缓存，每次都会走 DNS
host_cache_size=0

########### REPL ###########
# 开启 binlog
log_bin=mysql-bin
# 作为从库时，同步信息依然写入 binlog，方便此从库再作为其他从库的主库
log_slave_updates=1
# server id，默认为 ipv4 地址去除第一段
# eg: 192.168.2.48 => 168248
server_id=168248
# 每 n 次事务 binlog 刷新到磁盘
# refs http://liyangliang.me/posts/2014/03/innodb_flush_log_at_trx_commit-and-sync_binlog/
sync_binlog=100
# binlog 格式(refs https://zhuanlan.zhihu.com/p/33504555)
binlog_format=row
# binlog 自动清理时间
expire_logs_days=20
# 开启 relay-log，一般作为 slave 时开启
relay_log=mysql-replay
# 主从复制时跳过 test 库
replicate_ignore_db=test
# 每个 session binlog 缓存
binlog_cache_size=4M
# binlog 滚动大小
max_binlog_size=1024M
# GTID 相关(refs https://keithlan.github.io/2016/06/23/gtid/)
#gtid_mode=1
#enforce_gtid_consistency=1

########### InnoDB ###########
# 永久表默认存储引擎
default_storage_engine=InnoDB
# 系统表空间数据文件大小(初始化为 1G，并且自动增长)
innodb_data_file_path=ibdata1:1G:autoextend
# InnoDB 缓存池大小(资源充足，为所欲为)
# innodb_buffer_pool_size 必须等于 innodb_buffer_pool_chunk_size*innodb_buffer_pool_instances，或者是其整数倍
# refs https://dev.mysql.com/doc/refman/5.7/en/innodb-buffer-pool-resize.html
# refs https://zhuanlan.zhihu.com/p/60089484
innodb_buffer_pool_size=61440M
innodb_buffer_pool_instances=16
# 默认 128M
innodb_buffer_pool_chunk_size=128M
# InnoDB 强制恢复(refs https://www.askmaclean.com/archives/mysql-innodb-innodb_force_recovery.html)
innodb_force_recovery=0
# InnoDB buffer 预热(refs http://www.dbhelp.net/2017/01/12/mysql-innodb-buffer-pool-warmup.html)
innodb_buffer_pool_dump_at_shutdown=1
innodb_buffer_pool_load_at_startup=1
# InnoDB 日志组中的日志文件数
innodb_log_files_in_group=2
# InnoDB redo 日志大小
# refs https://www.percona.com/blog/2017/10/18/chose-mysql-innodb_log_file_size/
innodb_log_file_size=256MB
# 缓存还未提交的事务的缓冲区大小
innodb_log_buffer_size=16M
# InnoDB 在事务提交后的日志写入频率
# refs http://liyangliang.me/posts/2014/03/innodb_flush_log_at_trx_commit-and-sync_binlog/
innodb_flush_log_at_trx_commit=2
# InnoDB DML 操作行级锁等待时间
# 超时返回 ERROR 1205 (HY000): Lock wait timeout exceeded; try restarting transaction
# refs https://ningyu1.github.io/site/post/75-mysql-lock-wait-timeout-exceeded/
innodb_lock_wait_timeout=30
# InnoDB 行级锁超时是否回滚整个事务，默认为 OFF 仅回滚上一条语句
# 此时应用程序可以接受到错误后选择是否继续提交事务(并没有违反 ACID 原子性)
# refs https://www.cnblogs.com/hustcat/archive/2012/11/18/2775487.html
#innodb_rollback_on_timeout=ON
# InnoDB 数据写入磁盘的方式，具体见博客文章
# refs https://www.cnblogs.com/gomysql/p/3595806.html
innodb_flush_method=O_DIRECT
# InnoDB 缓冲池脏页刷新百分比
# refs https://dbarobin.com/2015/08/29/mysql-optimization-under-ssd
innodb_max_dirty_pages_pct=50
# InnoDB 每秒执行的写IO量
# refs https://www.centos.bz/2016/11/mysql-performance-tuning-15-config-item/#10.INNODB_IO_CAPACITY,%20INNODB_IO_CAPACITY_MAX
# refs https://www.alibabacloud.com/blog/testing-io-performance-with-sysbench_594709
innodb_io_capacity=8000
innodb_io_capacity_max=16000
# 请求并发 InnoDB 线程数
# refs https://www.cnblogs.com/xinysu/p/6439715.html#_lab2_1_0
innodb_thread_concurrency=0
# 再使用多个 InnoDB 表空间时，允许打开的最大 ".ibd" 文件个数，不设置默认 300，
# 并且取与 table_open_cache 相比较大的一个，此选项独立于 open_files_limit
# refs https://dev.mysql.com/doc/refman/5.7/en/innodb-parameters.html#sysvar_innodb_open_files
innodb_open_files=65535
# 每个 InnoDB 表都存储在独立的表空间(.ibd)中
innodb_file_per_table=1
# 事务级别(可重复读，会出幻读)
transaction_isolation=REPEATABLE-READ
# 是否在搜索和索引扫描中使用间隙锁(gap locking)，不建议使用未来将删除
innodb_locks_unsafe_for_binlog=0
# InnoDB 后台清理线程数，更大的值有助于 DML 执行性能，>= 5.7.8 默认为 4
innodb_purge_threads=4
```

**mysqld_safe.cnf**

```ini
#
# The Percona Server 5.7 configuration file.
#
# One can use all long options that the program supports.
# Run program with --help to get a list of available options and with
# --print-defaults to see which it would actually understand and use.
#
# For explanations see
# http://dev.mysql.com/doc/mysql/en/server-system-variables.html

[mysqld_safe]
pid-file = /var/run/mysqld/mysqld.pid
socket   = /var/run/mysqld/mysqld.sock
nice     = 0
```

**mysqldump.cnf**

```ini
[mysqldump]
quick
default-character-set=utf8mb4
max_allowed_packet=256M
```

## 八、常用诊断

### 8.1、动态配置 diff

mysql 默认允许在实例运行后使用 `set global VARIABLES=VALUE` 的方式动态调整一些配置，这可能导致在运行一段时间后(运维动态修改)实例运行配置和配置文件中配置不一致；所以**建议定期 diff 运行时配置与配置文件配置差异，防制特殊情况下 mysql 重启后运行期配置丢失**

``` sh
pt-config-diff /etc/percona-server.conf.d/mysqld.cnf h=127.0.0.1 --user root --ask-pass --report-width 100
Enter MySQL password:
2 config differences
Variable                  /etc/percona-server.conf.d/mysqld.cnf mysql47.test.com
========================= ===================================== ==================
innodb_max_dirty_pages... 50                                    50.000000
skip_name_resolve         0                                     ON
```

### 8.2、配置优化建议

Percona Toolkit 提供了一个诊断工具，用于对 mysql 内的配置进行扫描并给出优化建议，在初始化时可以使用此工具评估 mysql 当前配置的具体情况

``` sh
pt-variable-advisor 127.0.0.1 --user root --ask-pass | grep -v '^$'
Enter password: 

# WARN delay_key_write: MyISAM index blocks are never flushed until necessary.
# WARN innodb_flush_log_at_trx_commit-1: InnoDB is not configured in strictly ACID mode.
# NOTE innodb_max_dirty_pages_pct: The innodb_max_dirty_pages_pct is lower than the default.
# WARN max_connections: If the server ever really has more than a thousand threads running, then the system is likely to spend more time scheduling threads than really doing useful work.
# NOTE read_buffer_size-1: The read_buffer_size variable should generally be left at its default unless an expert determines it is necessary to change it.
# NOTE read_rnd_buffer_size-1: The read_rnd_buffer_size variable should generally be left at its default unless an expert determines it is necessary to change it.
# NOTE sort_buffer_size-1: The sort_buffer_size variable should generally be left at its default unless an expert determines it is necessary to change it.
# NOTE innodb_data_file_path: Auto-extending InnoDB files can consume a lot of disk space that is very difficult to reclaim later.
# WARN myisam_recover_options: myisam_recover_options should be set to some value such as BACKUP,FORCE to ensure that table corruption is noticed.
# WARN sync_binlog: Binary logging is enabled, but sync_binlog isn't configured so that every transaction is flushed to the binary log for durability.
```

### 8.3、死锁诊断

使用 pt-deadlock-logger 工具可以诊断当前的死锁状态，以下为对死锁检测的测试

首先创建测试数据库和表

``` sql
# 创建测试库
CREATE DATABASE dbatest CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
# 切换到测试库并建立测试表
USE dbatest;
CREATE TABLE IF NOT EXISTS test (id INT AUTO_INCREMENT PRIMARY KEY, value VARCHAR(255), createtime TIMESTAMP DEFAULT CURRENT_TIMESTAMP) ENGINE=INNODB;
```

在一个其他终端上开启 pt-deadlock-logger 检测

``` sh
pt-deadlock-logger 127.0.0.1 --user root --ask-pass --tab
```

检测开启后进行死锁测试

``` sql
# 插入两条测试数据
INSERT INTO test(value) VALUES('test1');
INSERT INTO test(value) VALUES('test2');
# 在两个终端下进行交叉事务

# 统一关闭自动提交
terminal_1 # SET AUTOCOMMIT = 0;
terminal_2 # SET AUTOCOMMIT = 0;

# 交叉事务，终端 1 先更新第一条数据，终端 2 先更新第二条数据
terminal_1 # BEGIN;
terminal_1 # UPDATE test set value='x1' where id=1;
terminal_2 # BEGIN;
terminal_2 # UPDATE test set value='x2' where id=2;

# 此后终端 1 再尝试更新第二条数据，终端 2 再尝试更新第一条数据；造成等待互向释放锁的死锁
terminal_1 # UPDATE test set value='lock2' where id=2;
terminal_2 # UPDATE test set value='lock1' where id=1;

# 此时由于开启了 mysql innodb 的死锁自动检测机制，会导致终端 2 弹出错误
ERROR 1213 (40001): Deadlock found when trying to get lock; try restarting transaction

# 同时 pt-deadlock-logger 有日志输出
server  ts      thread  txn_id  txn_time        user    hostname    ip      db      tbl     idx     lock_type       lock_mode       wait_hold       victim  query
127.0.0.1       2019-12-24T14:57:10     87      0       52      root            127.0.0.1       dbatest test    PRIMARY RECORD  X       w       0       UPDATE test set value='lock2' where id=2
127.0.0.1       2019-12-24T14:57:10     89      0       41      root            127.0.0.1       dbatest test    PRIMARY RECORD  X       w       1       UPDATE test set value='lock1' where id=1
```

### 8.4、查看 IO 详情

不同于 `iostat`，`pt-diskstats` 提供了更加详细的 IO 详情统计，并且据有交互式处理，执行一下命令将会实时检测 IO 状态

```sh
pt-diskstats --show-timestamps
```

其中几个关键值含义如下(更详细的请参考官方文档 [https://www.percona.com/doc/percona-toolkit/LATEST/pt-diskstats.html#output](https://www.percona.com/doc/percona-toolkit/LATEST/pt-diskstats.html#output))

- rd_s: 每秒平均读取次数。这是发送到基础设备的 IO 请求数。通常，此数量少于应用程序发出的逻辑IO请求的数量。更多请求可能已排队到块设备，但是其中一些请求通常在发送到磁盘之前先进行合并。
- rd_avkb: 读取的平均大小，以千字节为单位。
- rd_mb_s: 每秒读取的平均兆字节数。
- rd_mrg: 在发送到物理设备之前在队列调度程序中合并在一起的读取请求的百分比。
- rd_rt: 读取操作的平均响应时间(以毫秒为单位)；这是端到端响应时间，包括在队列中花费的时间。这是发出 IO 请求的应用程序看到的响应时间，而不是块设备下的物理磁盘的响应时间。
- busy: 设备至少有一个请求 wall-clock 时间的比例；等同于 `iostat` 的 `％util`。
- in_prg: 正在进行的请求数。与读写并发是从可靠数字中生成的平均值不同，该数字是一个时样本，您可以看到它可能表示请求峰值，而不是真正的长期平均值。如果此数字很大，则从本质上讲意味着设备高负载运行。
- ios_s: 物理设备的平均吞吐量，以每秒 IO 操作(IOPS)为单位。此列显示基础设备正在处理的总 IOPS；它是 rd_s 和 wr_s 的总和。
- qtime: 平均排队时间；也就是说，请求在发送到物理设备之前在设备调度程序队列中花费的时间。
- stime: 平均服务时间；也就是说，请求完成在队列中的等待之后，物理设备处理请求的时间。

### 8.5、重复索引优化

pt-duplicate-key-checker 工具提供了对数据库重复索引和外键的自动查找功能，工具使用如下

``` sh
pt-duplicate-key-checker 127.0.0.1 --user root --ask-pass
Enter password:

# A software update is available:
# ########################################################################
# aaaaaa.aaaaaa_audit
# ########################################################################

# index_linkId is a duplicate of unique_linkId
# Key definitions:
#   KEY `index_linkId` (`link_id`)
#   UNIQUE KEY `unique_linkId` (`link_id`),
# Column types:
#         `link_id` bigint(20) not null comment 'bdid'
# To remove this duplicate index, execute:
ALTER TABLE `aaaaaa.aaaaaa_audit` DROP INDEX `index_linkId`;

# ########################################################################
# Summary of indexes
# ########################################################################

# Size Duplicate Indexes   927420
# Total Duplicate Indexes  3
# Total Indexes            847
```

### 8.6、表统计

pt-find 是一个很方便的表查找统计工具，默认的一些选项可以实现批量查找符合条件的表，甚至执行一些 SQL 处理命令

``` sh
# 批量查找大于 5G 的表，并排序
pt-find --host 127.0.0.1 --user root --ask-pass --tablesize +5G | sort -rn
Enter password: 

`rss_service`.`test_feed_news`
`db_log_history`.`test_mobile_click_201912`
`db_log_history`.`test_mobile_click_201911`
`db_log_history`.`test_mobile_click_201910`
`test_dix`.`test_user_messages`
`test_dix`.`test_user_link_history`
`test_dix`.`test_mobile_click`
`test_dix`.`test_message`
`test_dix`.`test_link_votes`
`test_dix`.`test_links_mobile_content`
`test_dix`.`test_links`
`test_dix`.`test_comment_votes`
`test_dix`.`test_comments`
```

如果想要定制输出可以采用 `--printf` 选项

``` sh
pt-find --host 127.0.0.1 --user root --ask-pass --tablesize +5G --printf "%T\t%D.%N\n" | sort -rn
Enter password: 

13918404608     `test_dix`.`test_links_mobile_content`
13735231488     `test_dix`.`test_comment_votes`
12633227264     `test_dix`.`test_user_messages`
12610174976     `test_dix`.`test_user_link_history`
10506305536     `test_dix`.`test_links`
9686745088      `test_dix`.`test_message`
9603907584      `rss_service`.`test_feed_news`
9004122112      `db_log_history`.`test_mobile_click_201910`
8919007232      `test_dix`.`test_comments`
8045707264      `db_log_history`.`test_mobile_click_201912`
7855915008      `db_log_history`.`test_mobile_click_201911`
6099566592      `test_dix`.`test_mobile_click`
5892898816      `test_dix`.`test_link_votes`
```

**遗憾的是目前 `printf` 格式来源与 Perl 的 `sprintf` 函数，所以支持格式有限，不过简单的格式定制已经基本实现，复杂的建议通过 awk 处理**；其他的可选参数具体参考官方文档 [https://www.percona.com/doc/percona-toolkit/LATEST/pt-find.html](https://www.percona.com/doc/percona-toolkit/LATEST/pt-find.html)

### 8.7、其他命令

迫于篇幅，其他更多的高级命令请自行查阅官方文档 [https://www.percona.com/doc/percona-toolkit/LATEST/index.html](https://www.percona.com/doc/percona-toolkit/LATEST/index.html)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
