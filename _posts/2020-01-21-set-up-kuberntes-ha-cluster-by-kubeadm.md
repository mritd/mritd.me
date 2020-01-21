---
layout: post
categories: Kubernetes
title: kubeadm 搭建 HA kubernetes 集群
date: 2020-01-21 21:31:39 +0800
description: kubeadm 搭建 HA kubernetes 集群
keywords: kuberntes,kubeadm,ha
catalog: true
multilingual: false
tags: Kubernetes
---

> 距离上一次折腾 kubeadm 大约已经一两年了(记不太清了)，在很久一段时间内一直采用二进制部署的方式来部署 kubernetes 集群，随着 kubeadm 的不断稳定，目前终于可以重新试试这个不错的工具了

## 一、环境准备

搭建环境为 5 台虚拟机，每台虚拟机配置为 4 核心 8G 内存，虚拟机 IP 范围为 `172.16.10.21~25`，其他软件配置如下

- os version: ubuntu 18.04
- kubeadm version: 1.17.0
- kubernetes version: 1.17.0
- etcd version: 3.3.18
- docker version: 19.03.5

## 二、HA 方案

目前的 HA 方案与官方的不同，官方 HA 方案推荐使用类似 haproxy 等工具进行 4 层代理 apiserver，但是同样会有一个问题就是我们还需要对这个 haproxy 做 HA；由于目前我们实际生产环境都是多个独立的小集群，所以单独弄 2 台 haproxy + keeplived 去维持这个 apiserver LB 的 HA 有点不划算；所以还是准备延续老的 HA 方案，将外部 apiserver 的 4 层 LB 前置到每个 node 节点上；**目前是采用在每个 node 节点上部署 nginx 4 层代理所有 apiserver，nginx 本身资源消耗低而且请求量不大，综合来说对宿主机影响很小；**以下为 HA 的大致方案图

![ha](https://cdn.oss.link/markdown/mktld.png)

## 三、环境初始化

### 3.1、系统环境

由于个人操作习惯原因，目前已经将常用的初始化环境整理到一个小脚本里了，脚本具体参见 [mritd/shell_scripts](https://github.com/mritd/shell_scripts/blob/master/init_ubuntu.sh) 仓库，基本上常用的初始化内容为: 

- 设置 locale(en_US.UTF-8)
- 设置时区(Asia/Shanghai)
- 更新所有系统软件包(system update)
- 配置 vim(vim8 + 常用插件、配色)
- ohmyzsh(别跟我说不兼容 bash 脚本，我就是喜欢)
- docker
- ctop(一个 docker 的辅助工具)
- docker-compose

**在以上初始化中，实际对 kubernetes 安装产生影响的主要有三个地方:**

- **docker 的 cgroup driver 调整为 systemd，具体参考 [docker.service](https://github.com/mritd/config/blob/master/docker/docker.service)**
- **docker 一定要限制 conatiner 日志大小，防止 apiserver 等日志大量输出导致磁盘占用过大**
- **安装 `conntrack` 和 `ipvsadm`，后面可能需要借助其排查问题**

### 3.2、配置 ipvs

由于后面 kube-proxy 需要使用 ipvs 模式，所以需要对内核参数、模块做一些调整，调整命令如下:

```sh
cat >> /etc/sysctl.conf <<EOF
net.ipv4.ip_forward=1
net.bridge.bridge-nf-call-iptables=1
net.bridge.bridge-nf-call-ip6tables=1
EOF

sysctl -p

cat >> /etc/modules <<EOF
ip_vs
ip_vs_lc
ip_vs_wlc
ip_vs_rr
ip_vs_wrr
ip_vs_lblc
ip_vs_lblcr
ip_vs_dh
ip_vs_sh
ip_vs_fo
ip_vs_nq
ip_vs_sed
ip_vs_ftp
EOF
```

**配置完成后切记需要重启，重启完成后使用 `lsmod | grep ip_vs` 验证相关 ipvs 模块加载是否正常，本文将主要使用 `ip_vs_wrr`，所以目前只关注这个模块既可。**

![ipvs_mode](https://cdn.oss.link/markdown/4irz1.png)

## 四、安装 Etcd

### 4.1、方案选择

官方对于集群 HA 给出了两种有关于 Etcd 的部署方案: 

- 一种是深度耦合到 `control plane` 上，即每个 `control plane` 一个 etcd
- 另一种是使用外部的 Etcd 集群，通过在配置中指定外部集群让 apiserver 等组件连接

在测试深度耦合 `control plane` 方案后，发现一些比较恶心的问题；比如说开始创建第二个 `control plane` 时配置写错了需要重建，此时你一旦删除第二个 `control plane` 会导致第一个 `control plane` 也会失败，原因是**创建第二个 `control plane` 时 kubeadm 已经自动完成了 etcd 的集群模式，当删除第二个 `control plane` 的时候由于集群可用原因会导致第一个 `control plane` 下的 etcd 发现节点失联从而也不提供服务；**所以综合考虑到后续迁移、灾备等因素，这里选择了将 etcd 放置在外部集群中；同样也方便我以后各种折腾应对一些极端情况啥的。

### 4.2、部署 Etcd

确定了需要在外部部署 etcd 集群后，只需要开干就完事了；查了一下 ubuntu 官方源已经有了 etcd 安装包，但是版本比较老，测试了一下 golang 的 build 版本是 1.10；所以我还是选择了从官方 release 下载最新的版本安装；当然最后还是因为懒，我自己打了一个 deb 包... deb 包可以从这个项目 [mritd/etcd-deb](https://github.com/mritd/etcd-deb/releases) 下载，担心安全性的可以利用项目脚本自己打包，以下是安装过程:

```sh
# 下载软件包
wget https://github.com/mritd/etcd-deb/releases/download/v3.3.18/etcd_3.3.18_amd64.deb
wget https://github.com/mritd/etcd-deb/releases/download/v3.3.18/cfssl_1.4.1_amd64.deb
# 安装 etcd(至少在 3 台节点上执行)
dpkg -i etcd_3.3.18_amd64.deb cfssl_1.4.1_amd64.deb
```

**既然自己部署 etcd，那么证书签署啥的还得自己来了，证书签署这里借助 cfssl 工具，cfssl 目前提供了 deb 的 make target，但是没找到 deb 包，所以也自己 build 了(担心安全性的可自行去官方下载)；**接着编辑一下 `/etc/etcd/cfssl/etcd-csr.json` 文件，用 `/etc/etcd/cfssl/create.sh` 脚本创建证书，并将证书复制到指定目录

```sh
# 创建证书
cd /etc/etcd/cfssl && ./create.sh
# 复制证书
mv /etc/etcd/cfssl/*.pem /etc/etcd/ssl
```

最后在 3 台节点上修改配置，并将刚刚创建的证书同步到其他两台节点启动既可；下面是单台节点的配置样例

```sh
# /etc/etcd/etcd.conf
# [member]
ETCD_NAME=etcd1
ETCD_DATA_DIR="/var/lib/etcd/data"
ETCD_WAL_DIR="/var/lib/etcd/wal"
ETCD_SNAPSHOT_COUNT="100"
ETCD_HEARTBEAT_INTERVAL="100"
ETCD_ELECTION_TIMEOUT="1000"
ETCD_LISTEN_PEER_URLS="https://172.16.10.21:2380"
ETCD_LISTEN_CLIENT_URLS="https://172.16.10.21:2379,http://127.0.0.1:2379"
ETCD_MAX_SNAPSHOTS="5"
ETCD_MAX_WALS="5"
#ETCD_CORS=""

# [cluster]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://172.16.10.21:2380"
# if you use different ETCD_NAME (e.g. test), set ETCD_INITIAL_CLUSTER value for this name, i.e. "test=http://..."
ETCD_INITIAL_CLUSTER="etcd1=https://172.16.10.21:2380,etcd2=https://172.16.10.22:2380,etcd3=https://172.16.10.23:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_ADVERTISE_CLIENT_URLS="https://172.16.10.21:2379"
#ETCD_DISCOVERY=""
#ETCD_DISCOVERY_SRV=""
#ETCD_DISCOVERY_FALLBACK="proxy"
#ETCD_DISCOVERY_PROXY=""
#ETCD_STRICT_RECONFIG_CHECK="false"
ETCD_AUTO_COMPACTION_RETENTION="24"

# [proxy]
#ETCD_PROXY="off"
#ETCD_PROXY_FAILURE_WAIT="5000"
#ETCD_PROXY_REFRESH_INTERVAL="30000"
#ETCD_PROXY_DIAL_TIMEOUT="1000"
#ETCD_PROXY_WRITE_TIMEOUT="5000"
#ETCD_PROXY_READ_TIMEOUT="0"

# [security]
ETCD_CERT_FILE="/etc/etcd/ssl/etcd.pem"
ETCD_KEY_FILE="/etc/etcd/ssl/etcd-key.pem"
ETCD_CLIENT_CERT_AUTH="true"
ETCD_TRUSTED_CA_FILE="/etc/etcd/ssl/etcd-root-ca.pem"
ETCD_AUTO_TLS="true"
ETCD_PEER_CERT_FILE="/etc/etcd/ssl/etcd.pem"
ETCD_PEER_KEY_FILE="/etc/etcd/ssl/etcd-key.pem"
ETCD_PEER_CLIENT_CERT_AUTH="true"
ETCD_PEER_TRUSTED_CA_FILE="/etc/etcd/ssl/etcd-root-ca.pem"
ETCD_PEER_AUTO_TLS="true"

# [logging]
#ETCD_DEBUG="false"
# examples for -log-package-levels etcdserver=WARNING,security=DEBUG
#ETCD_LOG_PACKAGE_LEVELS=""

# [performance]
ETCD_QUOTA_BACKEND_BYTES="5368709120"
ETCD_AUTO_COMPACTION_RETENTION="3"
```

**注意: 其他两台节点请调整 `ETCD_NAME` 为不重复的其他名称，调整 `ETCD_LISTEN_PEER_URLS`、`ETCD_LISTEN_CLIENT_URLS`、`ETCD_INITIAL_ADVERTISE_PEER_URLS`、`ETCD_ADVERTISE_CLIENT_URLS` 为其他节点对应的 IP；同时生产环境请将 `ETCD_INITIAL_CLUSTER_TOKEN` 替换为复杂的 token**

```sh
# 同步证书
scp -r /etc/etcd/ssl 172.16.10.22:/etc/etcd/ssl
scp -r /etc/etcd/ssl 172.16.10.23:/etc/etcd/ssl
# 修复权限(3台节点都要执行)
chown -R etcd:etcd /etc/etcd
# 最后每个节点依次启动既可
systemctl start etcd
```

启动完成后可以通过以下命令测试是否正常

```sh
# 查看集群成员
k1.node ➜ etcdctl member list

3cbbaf77904c6153, started, etcd2, https://172.16.10.22:2380, https://172.16.10.22:2379
8eb7652b6bd99c30, started, etcd1, https://172.16.10.21:2380, https://172.16.10.21:2379
91f4e10726460d8c, started, etcd3, https://172.16.10.23:2380, https://172.16.10.23:2379

# 检测集群健康状态
k1.node ➜ etcdctl endpoint health --cacert /etc/etcd/ssl/etcd-root-ca.pem --cert /etc/etcd/ssl/etcd.pem --key /etc/etcd/ssl/etcd-key.pem --endpoints https://172.16.10.21:2379,https://172.16.10.22:2379,https://172.16.10.23:2379

https://172.16.10.21:2379 is healthy: successfully committed proposal: took = 16.632246ms
https://172.16.10.23:2379 is healthy: successfully committed proposal: took = 21.122603ms
https://172.16.10.22:2379 is healthy: successfully committed proposal: took = 22.592005ms
```

## 五、部署 Kubernetes

### 5.1、安装 kueadm

安装 kubeadm 没什么好说的，国内被墙用阿里的源既可

```sh
apt-get install -y apt-transport-https
curl https://mirrors.aliyun.com/kubernetes/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb https://mirrors.aliyun.com/kubernetes/apt/ kubernetes-xenial main
EOF
apt update

# ebtables、ethtool kubelet 可能会用，具体忘了，反正从官方文档上看到的
apt install kubelet kubeadm kubectl ebtables ethtool -y
```

### 5.2、部署 Nginx

从上面的 HA 架构图上可以看到，为了维持 apiserver 的 HA，需要在每个机器上部署一个 nginx 做 4 层的 LB；为保证后续的 node 节点正常加入，需要首先行部署 nginx；nginx 安装同样喜欢偷懒，直接 docker 跑了...毕竟都开始 kubeadm 了，那么也没必要去纠结 docker 是否稳定的问题了；以下为 nginx 相关配置

**apiserver-proxy.conf**

```sh
error_log stderr notice;

worker_processes auto;
events {
	multi_accept on;
	use epoll;
	worker_connections 1024;
}

stream {
    upstream kube_apiserver {
        least_conn;
        # 后端为三台 master 节点的 apiserver 地址
        server 172.16.10.21:5443;
        server 172.16.10.22:5443;
        server 172.16.10.23:5443;
    }
    
    server {
        listen        0.0.0.0:6443;
        proxy_pass    kube_apiserver;
        proxy_timeout 10m;
        proxy_connect_timeout 1s;
    }
}
```

**kube-apiserver-proxy.service**

```sh
[Unit]
Description=kubernetes apiserver docker wrapper
Wants=docker.socket
After=docker.service

[Service]
User=root
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run -p 6443:6443 \
                          -v /etc/kubernetes/apiserver-proxy.conf:/etc/nginx/nginx.conf \
                          --name kube-apiserver-proxy \
                          --net=host \
                          --restart=on-failure:5 \
                          --memory=512M \
                          nginx:1.17.6-alpine
ExecStartPre=-/usr/bin/docker rm -f kube-apiserver-proxy
ExecStop=/usr/bin/docker rm -rf kube-apiserver-proxy
Restart=always
RestartSec=15s
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
```

启动 nginx 代理(每台机器都要启动，包括 master 节点)

```sh
cp apiserver-proxy.conf /etc/kubernetes
cp kube-apiserver-proxy.service /lib/systemd/system
systemctl daemon-reload
systemctl enable kube-apiserver-proxy.service && systemctl start kube-apiserver-proxy.service
```

### 5.3、启动 control plane

#### 5.3.1、关于 Swap

目前 kubelet 为了保证内存 limit，需要在每个节点上关闭 swap；但是说实话我看了这篇文章 [In defence of swap: common misconceptions](https://chrisdown.name/2018/01/02/in-defence-of-swap.html) 以后还是不想关闭 swap；更确切的说其实我们生产环境比较 "富"，pod 都不 limit 内存，所以下面的部署我忽略了 swap 错误检测

#### 5.3.2、kubeadm 配置

当前版本的 kubeadm 已经支持了完善的配置管理(当然细节部分还有待支持)，以下为我目前使用的配置，相关位置已经做了注释，更具体的配置自行查阅官方文档

**kubeadm.yaml**

```yaml
apiVersion: kubeadm.k8s.io/v1beta2
kind: InitConfiguration
localAPIEndpoint:
  # 第一个 master 节点 IP
  advertiseAddress: "172.16.10.21"
  # 6443 留给了 nginx，apiserver 换到 5443
  bindPort: 5443
# 这个 token 使用以下命令生成
# kubeadm alpha certs certificate-key
certificateKey: 7373f829c733b46fb78f0069f90185e0f00254381641d8d5a7c5984b2cf17cd3 
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
# 使用外部 etcd 配置
etcd:
  external:
    endpoints:
    - "https://172.16.10.21:2379"
    - "https://172.16.10.22:2379"
    - "https://172.16.10.23:2379"
    caFile: "/etc/etcd/ssl/etcd-root-ca.pem"
    certFile: "/etc/etcd/ssl/etcd.pem"
    keyFile: "/etc/etcd/ssl/etcd-key.pem"
# 网络配置
networking:
  serviceSubnet: "10.25.0.0/16"
  podSubnet: "10.30.0.1/16"
  dnsDomain: "cluster.local"
kubernetesVersion: "v1.17.0"
# 全局 apiserver LB 地址，由于采用了 nginx 负载，所以直接指向本地既可
controlPlaneEndpoint: "127.0.0.1:6443"
apiServer:
  # apiserver 的自定义扩展参数
  extraArgs:
    v: "4"
    alsologtostderr: "true"
    # 审计日志相关配置
    audit-log-maxage: "20"
    audit-log-maxbackup: "10"
    audit-log-maxsize: "100"
    audit-log-path: "/var/log/kube-audit/audit.log"
    audit-policy-file: "/etc/kubernetes/audit-policy.yaml"
    authorization-mode: "Node,RBAC"
    event-ttl: "720h"
    runtime-config: "api/all=true"
    service-node-port-range: "30000-50000"
    service-cluster-ip-range: "10.25.0.0/16"
  # 由于自行定义了审计日志配置，所以需要将宿主机上的审计配置
  # 挂载到 kube-apiserver 的 pod 容器中
  extraVolumes:
  - name: "audit-config"
    hostPath: "/etc/kubernetes/audit-policy.yaml"
    mountPath: "/etc/kubernetes/audit-policy.yaml"
    readOnly: true
    pathType: "File"
  - name: "audit-log"
    hostPath: "/var/log/kube-audit"
    mountPath: "/var/log/kube-audit"
    pathType: "DirectoryOrCreate"
  # 这里是 apiserver 的证书地址配置
  # 为了防止以后出特殊情况，我增加了一个泛域名
  certSANs:
  - "*.kubernetes.node"
  - "172.16.10.21"
  - "172.16.10.22"
  - "172.16.10.23"
  timeoutForControlPlane: 5m
controllerManager:
  extraArgs:
    v: "4"
    # 宿主机 ip 掩码
    node-cidr-mask-size: "19"
    deployment-controller-sync-period: "10s"
    experimental-cluster-signing-duration: "87600h"
    node-monitor-grace-period: "20s"
    pod-eviction-timeout: "2m"
    terminated-pod-gc-threshold: "30"
scheduler:
  extraArgs:
    v: "4"
certificatesDir: "/etc/kubernetes/pki"
# gcr.io 被墙，换成微软的镜像地址
imageRepository: "gcr.azk8s.cn/google_containers"
clusterName: "kuberentes"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
# kubelet specific options here
# 此配置保证了 kubelet 能在 swap 开启的情况下启动
failSwapOn: false
nodeStatusUpdateFrequency: 5s
# 一些驱逐阀值，具体自行查文档修改
evictionSoft:
  "imagefs.available": "15%"
  "memory.available": "512Mi"
  "nodefs.available": "15%"
  "nodefs.inodesFree": "10%"
evictionSoftGracePeriod:
  "imagefs.available": "3m"
  "memory.available": "1m"
  "nodefs.available": "3m"
  "nodefs.inodesFree": "1m"
evictionHard:
  "imagefs.available": "10%"
  "memory.available": "256Mi"
  "nodefs.available": "10%"
  "nodefs.inodesFree": "5%"
evictionMaxPodGracePeriod: 30
imageGCLowThresholdPercent: 70
imageGCHighThresholdPercent: 80
kubeReserved:
  "cpu": "500m"
  "memory": "512Mi"
  "ephemeral-storage": "1Gi"
rotateCertificates: true
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
# kube-proxy specific options here
clusterCIDR: "10.30.0.1/16"
# 启用 ipvs 模式
mode: "ipvs"
ipvs:
  minSyncPeriod: 5s
  syncPeriod: 5s
  # ipvs 负载策略
  scheduler: "wrr"
```

**关于这个配置配置文件的文档还是很不完善，对于不懂 golang 的人来说很难知道具体怎么配置，以下做一下简要说明(请确保你已经拉取了 kubernetes 源码和安装了 Goland)**

**kubeadm 配置中每个配置段都会有个 `kind` 字段，`kind` 实际上对应了 go 代码中的 `struct` 结构体；同时从 `apiVersion` 字段中能够看到具体的版本，比如 `v1alpha1` 等；有了这两个信息事实上你就可以直接在源码中去找到对应的结构体**

![struct_search](https://cdn.oss.link/markdown/dwo5h.png)

在结构体中所有的配置便可以一目了然

![struct_detail](https://cdn.oss.link/markdown/0jc9b.png)

关于数据类型，如果是 `string` 的类型，那么意味着你要在 yaml 里写 `"xxxx"` 带引号这种，当然有些时候不写能兼容，有些时候不行比如 `extraArgs` 字段是一个 `map[string]string` 如果 value 不带引号就报错；**如果数据类型为 `metav1.Duration`(实际上就是 `time.Duration`)，那么你看着它是个 `int64` 但实际上你要写 `1h2m3s` 这种人类可读的格式，这是 go 的特色...**

**audit-policy.yaml**

```yaml
# Log all requests at the Metadata level.
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
```

可能 `Metadata` 级别的审计日志比较多，想自行调整审计日志级别的可以参考[官方文档](https://kubernetes.io/docs/tasks/debug-application-cluster/audit/#audit-policy)

#### 5.3.3、拉起 control plane

有了完整的 `kubeadm.yaml` 和 `audit-policy.yaml` 配置后，直接一条命令拉起 control plane 既可

```sh
# 先将审计配置放到目标位置(3 台 master 都要执行)
cp audit-policy.yaml /etc/kubernetes
# 拉起 control plane
kubeadm init --config kubeadm.yaml --upload-certs --ignore-preflight-errors=Swap
```

**control plane 拉起以后注意要保存屏幕输出，方便后续添加其他集群节点**

```sh
Your Kubernetes control-plane has initialized successfully!

To start using your cluster, you need to run the following as a regular user:

  mkdir -p $HOME/.kube
  sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
  sudo chown $(id -u):$(id -g) $HOME/.kube/config

You should now deploy a pod network to the cluster.
Run "kubectl apply -f [podnetwork].yaml" with one of the options listed at:
  https://kubernetes.io/docs/concepts/cluster-administration/addons/

You can now join any number of the control-plane node running the following command on each as root:

  kubeadm join 127.0.0.1:6443 --token r4t3l3.14mmuivm7xbtaeoj \
    --discovery-token-ca-cert-hash sha256:06f49f1f29d08b797fbf04d87b9b0fd6095a4693e9b1d59c429745cfa082b31d \
    --control-plane --certificate-key 7373f829c733b46fb78f0069f90185e0f00254381641d8d5a7c5984b2cf17cd3

Please note that the certificate-key gives access to cluster sensitive data, keep it secret!
As a safeguard, uploaded-certs will be deleted in two hours; If necessary, you can use
"kubeadm init phase upload-certs --upload-certs" to reload certs afterward.

Then you can join any number of worker nodes by running the following on each as root:

kubeadm join 127.0.0.1:6443 --token r4t3l3.14mmuivm7xbtaeoj \
    --discovery-token-ca-cert-hash sha256:06f49f1f29d08b797fbf04d87b9b0fd6095a4693e9b1d59c429745cfa082b31d
```

**根据屏幕提示配置 kubectl**

```sh
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

### 5.4、部署 CNI

关于网络插件的选择，以前一直喜欢 Calico，因为其性能确实好；到后来 flannel 出了 `host-gw` 以后现在两者性能也差不多了；但是 **flannel 好处是一个工具通吃所有环境(云环境+裸机2层直通)，坏处是 flannel 缺乏比较好的策略管理(当然可以使用两者结合的 Canal)；**后来思来想去其实我们生产倒是很少需要策略管理，所以这回怂回到 flannel 了(逃...)

Flannel 部署非常简单，根据官方文档下载配置，根据情况调整 `backend` 和 pod 的 CIDR，然后 apply 一下既可

```sh
# 下载配置文件
wget https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml

# 调整 backend 为 host-gw(测试环境 2 层直连)
k1.node ➜  grep -A 35 ConfigMap kube-flannel.yml
kind: ConfigMap
apiVersion: v1
metadata:
  name: kube-flannel-cfg
  namespace: kube-system
  labels:
    tier: node
    app: flannel
data:
  cni-conf.json: |
    {
      "name": "cbr0",
      "cniVersion": "0.3.1",
      "plugins": [
        {
          "type": "flannel",
          "delegate": {
            "hairpinMode": true,
            "isDefaultGateway": true
          }
        },
        {
          "type": "portmap",
          "capabilities": {
            "portMappings": true
          }
        }
      ]
    }
  net-conf.json: |
    {
      "Network": "10.30.0.0/16",
      "Backend": {
        "Type": "host-gw"
      }
    }

# 调整完成后 apply 一下
kubectl apply -f kube-flannel.yml
```

### 5.5、启动其他 control plane

为了保证 HA 架构，还需要在另外两台 master 上启动 control plane；**在启动之前请确保另外两台 master 节点节点上 `/etc/kubernetes/audit-policy.yaml` 审计配置已经分发完成，确保 `127.0.0.1:6443` 上监听的 4 层 LB 工作正常(可尝试使用 `curl -k https://127.0.0.1:6443` 测试)；**根据第一个 control plane 终端输出，其他 control plane 加入命令如下

```sh
kubeadm join 127.0.0.1:6443 --token r4t3l3.14mmuivm7xbtaeoj \
    --discovery-token-ca-cert-hash sha256:06f49f1f29d08b797fbf04d87b9b0fd6095a4693e9b1d59c429745cfa082b31d \
    --control-plane --certificate-key 7373f829c733b46fb78f0069f90185e0f00254381641d8d5a7c5984b2cf17cd3
```

**由于在使用 `kubeadm join` 时相关选项(`--discovery-token-ca-cert-hash`、`--control-plane`)无法与 `--config` 一起使用，这也就意味着我们必须增加一些附加指令来提供 `kubeadm.yaml` 配置文件中的一些属性**；最终完整的 control plane 加入命令如下，在其他 master 直接执行既可(**`--apiserver-advertise-address` 的 IP 地址是目标 master 的 IP**)

```sh
kubeadm join 127.0.0.1:6443 --token r4t3l3.14mmuivm7xbtaeoj \
    --discovery-token-ca-cert-hash sha256:06f49f1f29d08b797fbf04d87b9b0fd6095a4693e9b1d59c429745cfa082b31d \
    --control-plane --certificate-key 7373f829c733b46fb78f0069f90185e0f00254381641d8d5a7c5984b2cf17cd3 \
    --apiserver-advertise-address 172.16.10.22 \
    --apiserver-bind-port 5443 \
    --ignore-preflight-errors=Swap 
```

**所有 control plane 启动完成后应当通过在每个节点上运行 `kubectl get cs` 验证各个组件运行状态**

```sh
k2.node ➜ kubectl get cs
NAME                 STATUS    MESSAGE             ERROR
scheduler            Healthy   ok
controller-manager   Healthy   ok
etcd-1               Healthy   {"health":"true"}
etcd-0               Healthy   {"health":"true"}
etcd-2               Healthy   {"health":"true"}

k2.node ➜ kubectl get node -o wide
NAME      STATUS   ROLES    AGE   VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
k1.node   Ready    master   28m   v1.17.0   172.16.10.21   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   docker://19.3.5
k2.node   Ready    master   10m   v1.17.0   172.16.10.22   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   docker://19.3.5
k3.node   Ready    master   3m    v1.17.0   172.16.10.23   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   docker://19.3.5
```

### 5.6、启动 Node

node 节点的启动相较于 master 来说要简单得多，只需要增加一个防止 `swap` 开启拒绝启动的参数既可

```sh
kubeadm join 127.0.0.1:6443 --token r4t3l3.14mmuivm7xbtaeoj \
    --discovery-token-ca-cert-hash sha256:06f49f1f29d08b797fbf04d87b9b0fd6095a4693e9b1d59c429745cfa082b31d \
    --ignore-preflight-errors=Swap
```

启动成功后在 master 上可以看到所有 node 信息

```sh
k1.node ➜ kubectl get node -o wide
NAME      STATUS   ROLES    AGE     VERSION   INTERNAL-IP    EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
k1.node   Ready    master   32m     v1.17.0   172.16.10.21   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   docker://19.3.5
k2.node   Ready    master   14m     v1.17.0   172.16.10.22   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   docker://19.3.5
k3.node   Ready    master   6m35s   v1.17.0   172.16.10.23   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   docker://19.3.5
k4.node   Ready    <none>   72s     v1.17.0   172.16.10.24   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   docker://19.3.5
k5.node   Ready    <none>   66s     v1.17.0   172.16.10.25   <none>        Ubuntu 18.04.3 LTS   4.15.0-74-generic   docker://19.3.5
```

### 5.7、调整及测试

集群搭建好以后，如果想让 master 节点也参与调度任务，需要在任意一台 master 节点执行以下命令

```sh
# node 节点报错属于正常情况
k1.node ➜ kubectl taint nodes --all node-role.kubernetes.io/master-
node/k1.node untainted
node/k2.node untainted
node/k3.node untainted
taint "node-role.kubernetes.io/master" not found
taint "node-role.kubernetes.io/master" not found
```

最后创建一个 deployment 和一个 service，并在不同主机上 ping pod IP 测试网络联通性，在 pod 内直接 curl service 名称测试 dns 解析既可

**test-nginx.deploy.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-nginx
  labels:
    app: test-nginx
spec:
  replicas: 3
  selector:
    matchLabels:
      app: test-nginx
  template:
    metadata:
      labels:
        app: test-nginx
    spec:
      containers:
      - name: test-nginx
        image: nginx:1.17.6-alpine
        ports:
        - containerPort: 80
```

**test-nginx.svc.yaml**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: test-nginx
spec:
  selector:
    app: test-nginx
  ports:
    - protocol: TCP
      port: 80
      targetPort: 80
```

## 六、后续处理

> 说实话使用 kubeadm 后，我更关注的是集群后续的扩展性调整是否能达到目标；搭建其实很简单，大部份时间都在测试后续调整上

### 6.1、Etcd 迁移

由于我们采用的是外部的 Etcd，所以迁移起来比较简单怎么折腾都行；需要注意的是换 IP 的时候注意保证老的 3 个节点至少有一个可用，否则可能导致集群崩溃；调整完成后记得分发相关 Etcd 节点的证书，重启时顺序一个一个重启，不要并行操作

### 6.2、Master 配置修改

如果需要修改 conrol plane 上 apiserver、scheduler 等配置，直接修改 `kubeadm.yaml` 配置文件(**所以集群搭建好后务必保存好**)，然后执行 `kubeadm upgrade apply --config kubeadm.yaml` 升级集群既可，升级前一定作好相关备份工作；我只在测试环境测试这个命令工作还可以，生产环境还是需要谨慎

### 6.3、证书续期

目前根据我测试的结果，controller manager 的 **experimental-cluster-signing-duration** 参数在 init 的签发证书阶段似乎并未生效；**目前根据文档描述 `kubelet` client 的证书会自动滚动，其他证书默认 1 年有效期，需要自己使用命令续签；**续签命令如下

```sh
# 查看证书过期时间
k1.node ➜ kubeadm alpha certs check-expiration
[check-expiration] Reading configuration from the cluster...
[check-expiration] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -oyaml'

CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Jan 11, 2021 10:06 UTC   364d                                    no
apiserver                  Jan 11, 2021 10:06 UTC   364d            ca                      no
apiserver-kubelet-client   Jan 11, 2021 10:06 UTC   364d            ca                      no
controller-manager.conf    Jan 11, 2021 10:06 UTC   364d                                    no
front-proxy-client         Jan 11, 2021 10:06 UTC   364d            front-proxy-ca          no
scheduler.conf             Jan 11, 2021 10:06 UTC   364d                                    no

CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Jan 09, 2030 10:06 UTC   9y              no
front-proxy-ca          Jan 09, 2030 10:06 UTC   9y              no

# 续签证书
k1.node ➜ kubeadm alpha certs renew all
[renew] Reading configuration from the cluster...
[renew] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -oyaml'

certificate embedded in the kubeconfig file for the admin to use and for kubeadm itself renewed
certificate for serving the Kubernetes API renewed
certificate for the API server to connect to kubelet renewed
certificate embedded in the kubeconfig file for the controller manager to use renewed
certificate for the front proxy client renewed
certificate embedded in the kubeconfig file for the scheduler manager to use renewed
```

### 6.4、Node 重加入

默认的 bootstrap token 会在 24h 后失效，所以后续增加新节点需要重新创建 token，重新创建 token 可以通过以下命令完成

```sh
# 列出 token
k1.node ➜ kubeadm token list
TOKEN                     TTL         EXPIRES                     USAGES                   DESCRIPTION                                                EXTRA GROUPS
r4t3l3.14mmuivm7xbtaeoj   22h         2020-01-13T18:06:54+08:00   authentication,signing   <none>                                                     system:bootstrappers:kubeadm:default-node-token
zady4i.57f9i2o6zl9vf9hy   45m         2020-01-12T20:06:53+08:00   <none>                   Proxy for managing TTL for the kubeadm-certs secret        <none>

# 创建新 token
k1.node ➜ kubeadm token create --print-join-command
W0112 19:21:15.174765   26626 validation.go:28] Cannot validate kube-proxy config - no validator is available
W0112 19:21:15.174836   26626 validation.go:28] Cannot validate kubelet config - no validator is available
kubeadm join 127.0.0.1:6443 --token 2dz4dc.mobzgjbvu0bkxz7j     --discovery-token-ca-cert-hash sha256:06f49f1f29d08b797fbf04d87b9b0fd6095a4693e9b1d59c429745cfa082b31d
```

如果忘记了 certificate-key 可以通过一下命令重新 upload 并查看

```sh
k1.node ➜ kubeadm init --config kubeadm.yaml phase upload-certs --upload-certs
W0112 19:23:06.466711   28637 validation.go:28] Cannot validate kubelet config - no validator is available
W0112 19:23:06.466778   28637 validation.go:28] Cannot validate kube-proxy config - no validator is available
[upload-certs] Storing the certificates in Secret "kubeadm-certs" in the "kube-system" Namespace
[upload-certs] Using certificate key:
7373f829c733b46fb78f0069f90185e0f00254381641d8d5a7c5984b2cf17cd3
```

### 6.5、调整 kubelet

node 节点一旦启动完成后，kubelet 配置便不可再修改；如果想要修改 kubelet 配置，可以通过调整 `/etc/systemd/system/kubelet.service.d/10-kubeadm.conf` 配置文件完成

## 七、其他

本文参考了许多官方文档，以下是一些个人认为比较有价值并且在使用 kubeadm 后应该阅读的文档

- [Implementation details](https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details)
- [Configuring each kubelet in your cluster using kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/kubelet-integration/)
- [Customizing control plane configuration with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/control-plane-flags/)
- [Creating Highly Available clusters with kubeadm](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/)
- [Certificate Management with kubeadm](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-certs/)
- [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade/)
- [Reconfigure a Node's Kubelet in a Live Cluster](https://kubernetes.io/docs/tasks/administer-cluster/reconfigure-kubelet/)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
