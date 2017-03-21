---
layout: post
categories: Kubernetes Docker
title: 快速部署 kubernetes 高可用集群
date: 2017-03-03 23:16:04 +0800
description: 记录使用 kargo 快速部署 Kubernetes 高可用集群
keywords: Kubernetes Docker kargo HA 高可用
---

> 鼓捣 kubernetes 好长一段时间了，kubernetes 1.5 后新增了 kubeadm 工具用于快速部署 kubernetes 集群，不过该工具尚未稳定，无法自动部署高可用集群，而且还存在一些 BUG，所以生产环境还无法使用；本文基于 kargo 工具实现一键部署 kubernetes 容器化(可选) 高可用集群

### 一、基本环境准备

本文基本环境如下:

**五台虚拟机，基于 vagrant 启动(穷)，vagrant 配置文件参考 [这里](https://github.com/mritd/config/tree/master/vagrant)**

|主机地址|节点角色|
|--------|--------|
|192.168.1.11|master|
|192.168.1.12|master|
|192.168.1.13|node|
|192.168.1.14|node|
|192.168.1.15|node|

同时保证部署机器对集群内节点拥有 root 免密登录权限，**由于墙的原因，部署所需镜像已经全部打包到百度云，点击 [这里](https://pan.baidu.com/s/1jHMvMn0) 下载，然后进行 load 即可；注意: 直接使用我的 `vagrant` 文件时，请删除我在 `init.sh` 脚本里对 docker 设置的本地代理，直接使用可能导致 docker 无法 pull 任何镜像；vagrant 可能需要执行 `vagrant plugin install vagrant-hosts` 安装插件以支持自动设置 host；如果自己采用其他虚拟机请保证单台虚拟机最低 1.5G 内存，否则会导致安装失败，别问我怎么知道的**

**最新更新：经过测试，请使用 pip 安装 ansible，保证 `ansible >= 2.2.1` && `jinja2 >= 2.8,< 2.9`；否则可能出现安装时校验失败问题**

### 二、搭建集群

#### 2.1、获取源码

**kargo 是基于 ansible 的 Playbooks 的，其官方推荐的 kargo-cli 目前只适用于各种云平台部署安装，所以我们需要手动使用 Playbooks 部署，当然第一步先把源码搞下来**

``` sh
git clone https://github.com/kubernetes-incubator/kargo.git
```

#### 2.2、安装 ansible

既然 kargo 是基于 ansible 的(实际上就是 Playbooks)，那么自然要先安装 ansible，同时下面配置生成会用到 python3，所以也一并安装

``` sh
# 安装 python 及 epel
yum install -y epel-release python-pip python34 python34-pip
# 安装 ansible(必须先安装 epel 源再安装 ansible)
yum install -y ansible
```

#### 2.3、编辑配置文件

**注意：以下配置段中，所有双大括号 `{ {` 、`} }`，中间全部加了空格，因为双大括号会跟主题模板引擎产生冲突，默认应该是没有的，请自行 vim 替换**

首先根据自己需要更改 kargo 的配置，配置文件位于 `inventory/group_vars/k8s-cluster.yml`，**最新稳定版本版本(2.1.0) 配置文件还未更名，全部在 `inventory/group_vars/all.yml` 中，这里采用最新版本的原因是...借着写博客我也看看更新了啥(偷笑...)**

``` sh
vim inventory/group_vars/k8s-cluster.yml

# 配置文件如下
# 启动集群的基础系统
bootstrap_os: centos

# etcd 数据存放位置
etcd_data_dir: /var/lib/etcd

# 二进制文件将要安装的位置
bin_dir: /usr/local/bin

# Kubernetes 配置文件存放目录以及命名空间
kube_config_dir: /etc/kubernetes
kube_script_dir: "{ { bin_dir } }/kubernetes-scripts"
kube_manifest_dir: "{ { kube_config_dir } }/manifests"
system_namespace: kube-system

# 日志存放位置
kube_log_dir: "/var/log/kubernetes"

# kubernetes 证书存放位置
kube_cert_dir: "{ { kube_config_dir } }/ssl"

# token存放位置
kube_token_dir: "{ { kube_config_dir } }/tokens"

# basic auth 认证文件存放位置
kube_users_dir: "{ { kube_config_dir } }/users"

# 关闭匿名授权
kube_api_anonymous_auth: false

## 使用的 kubernetes 版本
kube_version: v1.5.3

# 安装过程中缓存文件下载位置(最少 1G)
local_release_dir: "/tmp/releases"
# 重试次数，比如下载失败等情况
retry_stagger: 5

# 证书组
kube_cert_group: kube-cert

# 集群日志等级
kube_log_level: 2

# HTTP 下 api server 密码及用户
kube_api_pwd: "changeme"
kube_users:
  kube:
    pass: "{ {kube_api_pwd} }"
    role: admin
  root:
    pass: "{ {kube_api_pwd} }"
    role: admin

# 网络 CNI 组件 (calico, weave or flannel)
kube_network_plugin: calico

# 服务地址分配
kube_service_addresses: 10.233.0.0/18

# pod 地址分配
kube_pods_subnet: 10.233.64.0/18

# 网络节点大小分配
kube_network_node_prefix: 24

# api server 监听地址及端口
kube_apiserver_ip: "{ { kube_service_addresses|ipaddr('net')|ipaddr(1)|ipaddr('address') } }"
kube_apiserver_port: 6443 # (https)
kube_apiserver_insecure_port: 8080 # (http)

# 默认 dns 后缀
cluster_name: cluster.local
# Subdomains of DNS domain to be resolved via /etc/resolv.conf for hostnet pods
ndots: 2
# DNS 组件 dnsmasq_kubedns/kubedns
dns_mode: dnsmasq_kubedns
# Can be docker_dns, host_resolvconf or none
resolvconf_mode: docker_dns
# 部署 netchecker 来检测 DNS 和 HTTP 状态
deploy_netchecker: false
# skydns service IP 配置
skydns_server: "{ { kube_service_addresses|ipaddr('net')|ipaddr(3)|ipaddr('address') } }"
dns_server: "{ { kube_service_addresses|ipaddr('net')|ipaddr(2)|ipaddr('address') } }"
dns_domain: "{ { cluster_name } }"

# docker 存储目录
docker_daemon_graph: "/var/lib/docker"

# docker 的额外配置参数，默认会在 /etc/systemd/system/docker.service.d/ 创建相关配置，如果节点已经安装了 docker，并且做了自己的配置，比如启用了 devicemapper ，那么要更改这里，并把自己的 devicemapper 参数加到这里，因为 kargo 会复写 systemd service 文件，会导致自己在 service 中配置的参数被清空，最后 docker 将无法启动
## A string of extra options to pass to the docker daemon.
## This string should be exactly as you wish it to appear.
## An obvious use case is allowing insecure-registry access
## to self hosted registries like so:
docker_options: "--insecure-registry={ { kube_service_addresses } } --graph={ { docker_daemon_graph } } --iptables=false"
docker_bin_dir: "/usr/bin"

# 组件部署方式
# Settings for containerized control plane (etcd/kubelet/secrets)
etcd_deployment_type: docker
kubelet_deployment_type: docker
cert_management: script
vault_deployment_type: docker

# K8s image pull policy (imagePullPolicy)
k8s_image_pull_policy: IfNotPresent

# Monitoring apps for k8s
efk_enabled: false
```

#### 2.4、生成集群配置

配置完基本集群参数后，还需要生成一个集群配置文件，用于指定需要在哪几台服务器安装，和指定 master、node 节点分布，以及 etcd 集群等安装在那几台机器上

``` sh
# 定义集群 IP
IPS=(192.168.1.11 192.168.1.12 192.168.1.13 192.168.1.14 192.168.1.15)
# 生成配置
cd kargo
CONFIG_FILE=inventory/inventory.cfg python3 contrib/inventory_builder/inventory.py ${IPS}
```

生成的配置如下，已经很简单了，怎么改动相信猜也能猜到

``` sh
vim inventory/inventory.cfg

[all]
node1    ansible_host=192.168.1.11 ip=192.168.1.11
node2    ansible_host=192.168.1.12 ip=192.168.1.12
node3    ansible_host=192.168.1.13 ip=192.168.1.13
node4    ansible_host=192.168.1.14 ip=192.168.1.14
node5    ansible_host=192.168.1.15 ip=192.168.1.15

[kube-master]
node1
node2

[kube-node]
node1
node2
node3
node4
node5

[etcd]
node1
node2
node3

[k8s-cluster:children]
kube-node
kube-master

[calico-rr]
```

#### 2.5、一键部署

首先启动 vagrant 虚拟机，**不过注意的是本文提供的 vagrant 文件默认安装了 docker，并配置了 devicemapper 和docker 代理，所以使用时上面的 docker 参数需要替换成自己的，因为默认 kargo 会覆盖 docker 的 service 文件；会导致我已经配置完的 docker devicemapper 参数失效，所以要把自己配置的参数加到配置文件中，如下**

``` sh
docker_options: "--insecure-registry={ { kube_service_addresses } } --graph={ { docker_daemon_graph } } --iptables=false --storage-driver=devicemapper --storage-opt=dm.thinpooldev=/dev/mapper/docker-thinpool --storage-opt dm.use_deferred_removal=true --storage-opt=dm.use_deferred_deletion=true"
```

**这个 vagrant 配置文件自动设置了主机名、host、ssh 密钥，实际生产环境仍需自己处理**

**每个虚拟机需要自己登陆并生成 ssh-key(ssh-keygen)，因为 ansible 会用到**

``` sh
# 启动虚拟机
cd vagrant && vagrant up
# 走你(没梯子先 load 好镜像)
cd kargo 
# 私钥指定的是每个虚拟机 ssh 目录下的私钥
ansible-playbook -i inventory/inventory.cfg cluster.yml -b -v --private-key=~/.ssh/id_rsa
```

部署成功后截图如下

![deploy success](https://mritd.b0.upaiyun.com/markdown/ksgtg.jpg)

相关 pod 启动情况如下 

![deploy pods](https://mritd.b0.upaiyun.com/markdown/c7zaz.jpg)


**最后附上我部署是的 kargo 配置**

``` sh
# 启动集群的基础系统
bootstrap_os: centos

# etcd 数据存放位置
etcd_data_dir: /var/lib/etcd

# 二进制文件将要安装的位置
bin_dir: /usr/local/bin

# Kubernetes 配置文件存放目录以及命名空间
kube_config_dir: /etc/kubernetes
kube_script_dir: "{ { bin_dir } }/kubernetes-scripts"
kube_manifest_dir: "{ { kube_config_dir } }/manifests"
system_namespace: kube-system

# 日志存放位置
kube_log_dir: "/var/log/kubernetes"

# kubernetes 证书存放位置
kube_cert_dir: "{ { kube_config_dir } }/ssl"

# token存放位置
kube_token_dir: "{ { kube_config_dir } }/tokens"

# basic auth 认证文件存放位置
kube_users_dir: "{ { kube_config_dir } }/users"

# 关闭匿名授权
kube_api_anonymous_auth: false

## 使用的 kubernetes 版本
kube_version: v1.5.3

# 安装过程中缓存文件下载位置(最少 1G)
local_release_dir: "/tmp/releases"
# 重试次数，比如下载失败等情况
retry_stagger: 5

# 证书组
kube_cert_group: kube-cert

# 集群日志等级
kube_log_level: 2

# HTTP 下 api server 密码及用户
kube_api_pwd: "test123"
kube_users:
  kube:
    pass: "{ {kube_api_pwd} }"
    role: admin
  root:
    pass: "{ {kube_api_pwd} }"
    role: admin

# 网络 CNI 组件 (calico, weave or flannel)
kube_network_plugin: calico

# 服务地址分配
kube_service_addresses: 10.233.0.0/18

# pod 地址分配
kube_pods_subnet: 10.233.64.0/18

# 网络节点大小分配
kube_network_node_prefix: 24

# api server 监听地址及端口
kube_apiserver_ip: "{ { kube_service_addresses|ipaddr('net')|ipaddr(1)|ipaddr('address') } }"
kube_apiserver_port: 6443 # (https)
kube_apiserver_insecure_port: 8080 # (http)

# 默认 dns 后缀
cluster_name: cluster.local
# Subdomains of DNS domain to be resolved via /etc/resolv.conf for hostnet pods
ndots: 2
# DNS 组件 dnsmasq_kubedns/kubedns
dns_mode: dnsmasq_kubedns
# Can be docker_dns, host_resolvconf or none
resolvconf_mode: docker_dns
# 部署 netchecker 来检测 DNS 和 HTTP 状态
deploy_netchecker: true 
# skydns service IP 配置
skydns_server: "{ { kube_service_addresses|ipaddr('net')|ipaddr(3)|ipaddr('address') } }"
dns_server: "{ { kube_service_addresses|ipaddr('net')|ipaddr(2)|ipaddr('address') } }"
dns_domain: "{ { cluster_name } }"

# docker 存储目录
docker_daemon_graph: "/var/lib/docker"

# docker 的额外配置参数，默认会在 /etc/systemd/system/docker.service.d/ 创建相关配置，如果节点已经安装了 docker，并且做了自己的配置，比如启用的 device mapper ，那么要删除/更改这里，防止冲突导致 docker 无法启动
## A string of extra options to pass to the docker daemon.
## This string should be exactly as you wish it to appear.
## An obvious use case is allowing insecure-registry access
## to self hosted registries like so:
docker_options: "--insecure-registry={ { kube_service_addresses } } --graph={ { docker_daemon_graph } } --iptables=false --storage-driver=devicemapper --storage-opt=dm.thinpooldev=/dev/mapper/docker-thinpool --storage-opt dm.use_deferred_removal=true --storage-opt=dm.use_deferred_deletion=true"
docker_bin_dir: "/usr/bin"

# 组件部署方式
# Settings for containerized control plane (etcd/kubelet/secrets)
etcd_deployment_type: docker
kubelet_deployment_type: docker
cert_management: script
vault_deployment_type: docker

# K8s image pull policy (imagePullPolicy)
k8s_image_pull_policy: IfNotPresent

# Monitoring apps for k8s
efk_enabled: true 
```



转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
