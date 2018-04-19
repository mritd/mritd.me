---
layout: post
categories: Kubernetes
title: Kubernetes 1.10.1 集群搭建
date: 2018-04-19 16:19:08 +0800
description: Kubernetes 1.10.1 集群搭建
keywords: kubernetes,1.10,1.10.1,docker
catalog: true
multilingual: false
tags: Kubernetes
---

> 年后比较忙，所以 1.9 也没去折腾(其实就是懒)，最近刚有点时间凑巧 1.10 发布；所以就折腾一下 1.10，感觉搭建配置没有太大变化，折腾了 2 天基本算是搞定了，这里记录一下搭建过程；本文用到的被 block 镜像已经上传至 [百度云](https://pan.baidu.com/s/1waeoo8uXCW1hWNlOjePdGg) 密码: y739

### 一、环境准备

目前搭建仍然采用 5 台虚拟机测试，基本环境如下

| IP | Type | Docker | OS |
| --- | --- | --- | --- |
| 192.168.1.61 | master、node、etcd | 18.03.0-ce | ubuntu 16.04 |
| 192.168.1.62 | master、node、etcd | 18.03.0-ce | ubuntu 16.04 |
| 192.168.1.63 | master、node、etcd | 18.03.0-ce | ubuntu 16.04 |
| 192.168.1.64 | node | 18.03.0-ce | ubuntu 16.04 |
| 192.168.1.65 | node | 18.03.0-ce | ubuntu 16.04 |


**搭建前请看完整篇文章后再操作，一些变更说明我放到后面了；还有为了尽可能的懒，也不用什么 rpm、deb 了，直接 `hyperkube` + `service` 配置，布吉岛 `hyperkube` 的请看 [GitHub](https://github.com/kubernetes/kubernetes/blob/master/cluster/images/hyperkube/README.md)；本篇文章基于一些小脚本搭建(懒)，所以不会写太详细的步骤，具体请参考 [仓库脚本](https://github.com/mritd/ktool)，如果想看更详细的每一步的作用可以参考以前的 1.7、1.8 的搭建文档**

### 二、搭建 Etcd 集群

#### 2.1、安装 cfssl

说实话这个章节我不想写，但是考虑可能有人真的需要，所以还是写了一下；**这个安装脚本使用的是我私人的 cdn，文件可能随时删除，想使用最新版本请自行从 [Github](https://github.com/cloudflare/cfssl) clone 并编译**

``` sh
wget https://mritdftp.b0.upaiyun.com/cfssl/cfssl.tar.gz
tar -zxvf cfssl.tar.gz
mv cfssl cfssljson /usr/local/bin
chmod +x /usr/local/bin/cfssl /usr/local/bin/cfssljson
rm -f cfssl.tar.gz
```

#### 2.2、生成 Etcd 证书

##### etcd-csr.json

``` json
{
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "etcd",
      "OU": "etcd Security",
      "L": "Beijing",
      "ST": "Beijing",
      "C": "CN"
    }
  ],
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "localhost",
    "192.168.1.61",
    "192.168.1.62",
    "192.168.1.63"
  ]
}
```

##### etcd-gencert.json

``` json
{
  "signing": {
    "default": {
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ],
        "expiry": "87600h"
    }
  }
}
```

##### etcd-root-ca-csr.json

``` json
{
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "O": "etcd",
      "OU": "etcd Security",
      "L": "Beijing",
      "ST": "Beijing",
      "C": "CN"
    }
  ],
  "CN": "etcd-root-ca"
}
```

##### 生成证书

``` sh
cfssl gencert --initca=true etcd-root-ca-csr.json | cfssljson --bare etcd-root-ca
cfssl gencert --ca etcd-root-ca.pem --ca-key etcd-root-ca-key.pem --config etcd-gencert.json etcd-csr.json | cfssljson --bare etcd
```

生成后如下

![gen etcd certs](https://mritd.b0.upaiyun.com/markdown/81203.png)

#### 2.3、安装 Etcd

Etcd 这里采用最新的 3.2.18 版本，安装方式直接复制二进制文件、systemd service 配置即可，不过需要注意相关用户权限问题，以下脚本配置等参考了 etcd rpm 安装包

##### etcd.service

``` sh
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
EnvironmentFile=-/etc/etcd/etcd.conf
User=etcd
# set GOMAXPROCS to number of processors
ExecStart=/bin/bash -c "GOMAXPROCS=$(nproc) /usr/local/bin/etcd --name=\"${ETCD_NAME}\" --data-dir=\"${ETCD_DATA_DIR}\" --listen-client-urls=\"${ETCD_LISTEN_CLIENT_URLS}\""
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

##### etcd.conf

``` sh
# [member]
ETCD_NAME=etcd1
ETCD_DATA_DIR="/var/lib/etcd/etcd1.etcd"
ETCD_WAL_DIR="/var/lib/etcd/wal"
ETCD_SNAPSHOT_COUNT="100"
ETCD_HEARTBEAT_INTERVAL="100"
ETCD_ELECTION_TIMEOUT="1000"
ETCD_LISTEN_PEER_URLS="https://192.168.1.61:2380"
ETCD_LISTEN_CLIENT_URLS="https://192.168.1.61:2379,http://127.0.0.1:2379"
ETCD_MAX_SNAPSHOTS="5"
ETCD_MAX_WALS="5"
#ETCD_CORS=""

# [cluster]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.1.61:2380"
# if you use different ETCD_NAME (e.g. test), set ETCD_INITIAL_CLUSTER value for this name, i.e. "test=http://..."
ETCD_INITIAL_CLUSTER="etcd1=https://192.168.1.61:2380,etcd2=https://192.168.1.62:2380,etcd3=https://192.168.1.63:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_ADVERTISE_CLIENT_URLS="https://192.168.1.61:2379"
#ETCD_DISCOVERY=""
#ETCD_DISCOVERY_SRV=""
#ETCD_DISCOVERY_FALLBACK="proxy"
#ETCD_DISCOVERY_PROXY=""
#ETCD_STRICT_RECONFIG_CHECK="false"
#ETCD_AUTO_COMPACTION_RETENTION="0"

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
```

##### install.sh

``` sh
#!/bin/bash

set -e

ETCD_VERSION="3.2.18"

function download(){
    if [ ! -f "etcd-v${ETCD_VERSION}-linux-amd64.tar.gz" ]; then
        wget https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
        tar -zxvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
    fi
}

function preinstall(){
    getent group etcd >/dev/null || groupadd -r etcd
    getent passwd etcd >/dev/null || useradd -r -g etcd -d /var/lib/etcd -s /sbin/nologin -c "etcd user" etcd
}

function install(){
    echo -e "\033[32mINFO: Copy etcd...\033[0m"
    tar -zxvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
    cp etcd-v${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin
    rm -rf etcd-v${ETCD_VERSION}-linux-amd64

    echo -e "\033[32mINFO: Copy etcd config...\033[0m"
    cp -r conf /etc/etcd
    chown -R etcd:etcd /etc/etcd
    chmod -R 755 /etc/etcd/ssl

    echo -e "\033[32mINFO: Copy etcd systemd config...\033[0m"
    cp systemd/*.service /lib/systemd/system
    systemctl daemon-reload
}

function postinstall(){
    if [ ! -d "/var/lib/etcd" ]; then
        mkdir /var/lib/etcd
        chown -R etcd:etcd /var/lib/etcd
    fi
}


download
preinstall
install
postinstall
```

**脚本解释如下:**

- download: 从 Github 下载二进制文件并解压
- preinstall: 为 Etcd 安装做准备，创建 etcd 用户，并指定家目录登录 shell 等
- install: 将 etcd 二进制文件复制到安装目录(`/usr/local/bin`)，复制 conf 目录到 `/etc/etcd`
- postinstall: 安装后收尾工作，比如检测 `/var/lib/etcd` 是否存在，纠正权限等

整体目录结构如下

``` sh
etcd
├── conf
│   ├── etcd.conf
│   └── ssl
│       ├── etcd.csr
│       ├── etcd-csr.json
│       ├── etcd-gencert.json
│       ├── etcd-key.pem
│       ├── etcd.pem
│       ├── etcd-root-ca.csr
│       ├── etcd-root-ca-csr.json
│       ├── etcd-root-ca-key.pem
│       └── etcd-root-ca.pem
├── etcd.service
└── install.sh
```

**请自行创建 conf 目录等，并放置好相关文件，保存上面脚本为 `install.sh`，直接执行即可；在每台机器上更改好对应的配置，如 etcd 名称等，etcd 估计都是轻车熟路了，这里不做过多阐述；安装后启动即可**

``` sh
systemctl start etcd
systemctl enable etcd
```

**注意: 集群 etcd 要 3 个一起启动，集群模式下单个启动会卡半天最后失败，不要傻等；启动成功后测试如下**

``` sh
export ETCDCTL_API=3
etcdctl --cacert=/etc/etcd/ssl/etcd-root-ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem --endpoints=https://192.168.1.61:2379,https://192.168.1.62:2379,https://192.168.1.63:2379 endpoint health
```

![check etcd](https://mritd.b0.upaiyun.com/markdown/ji94m.png)

### 三、安装 Kubernets 集群组件

> **注意：与以前文档不同的是，这次不依赖 rpm 等特定安装包，而是基于 hyperkube 二进制手动安装，每个节点都会同时安装 Master 与 Node 配置文件，具体作为 Master 还是 Node 取决于服务开启情况**

#### 3.1、生成 Kubernetes 证书

由于 kubelet 和 kube-proxy 用到的 kubeconfig 配置文件需要借助 kubectl 来生成，所以需要先安装一下 kubectl

``` sh
wget https://storage.googleapis.com/kubernetes-release/release/v1.10.1/bin/linux/amd64/hyperkube -O hyperkube_1.10.1
chmod +x hyperkube_1.10.1
cp hyperkube_1.10.1 /usr/local/bin/hyperkube
ln -s /usr/local/bin/hyperkube /usr/local/bin/kubectl
```

##### admin-csr.json

``` json
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
```

##### k8s-gencert.json

``` json
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "87600h"
      }
    }
  }
}
```

##### k8s-root-ca-csr.json

``` json
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 4096
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
```

##### kube-apiserver-csr.json

**注意: 在以前的文档中这个配置叫 `kubernetes-csr.json`，为了明确划分职责，这个证书目前被重命名以表示其专属于 `apiserver` 使用；加了一个 `*.kubernetes.master` 域名以便内部私有 DNS 解析使用(可删除)；至于很多人问过 `kubernetes` 这几个能不能删掉，答案是不可以的；因为当集群创建好后，default namespace 下会创建一个叫 `kubenretes` 的 svc，有一些组件会直接连接这个 svc 来跟 api 通讯的，证书如果不包含可能会出现无法连接的情况；其他几个 `kubernetes` 开头的域名作用相同**

``` json
{
    "CN": "kubernetes",
    "hosts": [
        "127.0.0.1",
        "10.254.0.1",
        "192.168.1.61",
        "192.168.1.62",
        "192.168.1.63",
        "192.168.1.64",
        "192.168.1.65",
        "*.kubernetes.master",
        "localhost",
        "kubernetes",
        "kubernetes.default",
        "kubernetes.default.svc",
        "kubernetes.default.svc.cluster",
        "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "ST": "BeiJing",
            "L": "BeiJing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
```

##### kube-proxy-csr.json

``` json
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
```

##### 生成证书及配置

``` sh
# 生成 CA
cfssl gencert --initca=true k8s-root-ca-csr.json | cfssljson --bare k8s-root-ca

# 依次生成其他组件证书
for targetName in kube-apiserver admin kube-proxy; do
    cfssl gencert --ca k8s-root-ca.pem --ca-key k8s-root-ca-key.pem --config k8s-gencert.json --profile kubernetes $targetName-csr.json | cfssljson --bare $targetName
done

# 地址默认为 127.0.0.1:6443
# 如果在 master 上启用 kubelet 请在生成后的 kubeconfig 中
# 修改该地址为 当前MASTER_IP:6443
KUBE_APISERVER="https://127.0.0.1:6443"
BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
echo "Tokne: ${BOOTSTRAP_TOKEN}"

# 不要质疑 system:bootstrappers 用户组是否写错了，有疑问请参考官方文档
# https://kubernetes.io/docs/admin/kubelet-tls-bootstrapping/
cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:bootstrappers"
EOF

echo "Create kubelet bootstrapping kubeconfig..."
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

echo "Create kube-proxy kubeconfig..."
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

# 创建高级审计配置
cat >> audit-policy.yaml <<EOF
# Log all requests at the Metadata level.
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
- level: Metadata
EOF
```

生成后文件如下

![k8s certs](https://mritd.b0.upaiyun.com/markdown/xk8uj.png)

#### 3.2、准备 systemd 配置

所有组件的 `systemd` 配置如下

##### kube-apiserver.service

``` sh
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
After=etcd.service

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/apiserver
User=kube
ExecStart=/usr/local/bin/hyperkube apiserver \
            $KUBE_LOGTOSTDERR \
            $KUBE_LOG_LEVEL \
            $KUBE_ETCD_SERVERS \
            $KUBE_API_ADDRESS \
            $KUBE_API_PORT \
            $KUBELET_PORT \
            $KUBE_ALLOW_PRIV \
            $KUBE_SERVICE_ADDRESSES \
            $KUBE_ADMISSION_CONTROL \
            $KUBE_API_ARGS
Restart=on-failure
Type=notify
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

##### kube-controller-manager.service

``` sh
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/controller-manager
User=kube
ExecStart=/usr/local/bin/hyperkube controller-manager \
            $KUBE_LOGTOSTDERR \
            $KUBE_LOG_LEVEL \
            $KUBE_MASTER \
            $KUBE_CONTROLLER_MANAGER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

##### kubelet.service

``` sh
[Unit]
Description=Kubernetes Kubelet Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/kubelet
ExecStart=/usr/local/bin/hyperkube kubelet \
            $KUBE_LOGTOSTDERR \
            $KUBE_LOG_LEVEL \
            $KUBELET_API_SERVER \
            $KUBELET_ADDRESS \
            $KUBELET_PORT \
            $KUBELET_HOSTNAME \
            $KUBE_ALLOW_PRIV \
            $KUBELET_ARGS
Restart=on-failure
KillMode=process

[Install]
WantedBy=multi-user.target
```

##### kube-proxy.service

``` sh
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/proxy
ExecStart=/usr/local/bin/hyperkube proxy \
            $KUBE_LOGTOSTDERR \
            $KUBE_LOG_LEVEL \
            $KUBE_MASTER \
            $KUBE_PROXY_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

##### kube-scheduler.service

``` sh
[Unit]
Description=Kubernetes Scheduler Plugin
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/config
EnvironmentFile=-/etc/kubernetes/scheduler
User=kube
ExecStart=/usr/local/bin/hyperkube scheduler \
            $KUBE_LOGTOSTDERR \
            $KUBE_LOG_LEVEL \
            $KUBE_MASTER \
            $KUBE_SCHEDULER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

#### 3.3、Master 节点配置

Master 节点主要会运行 3 各组件: `kube-apiserver`、`kube-controller-manager`、`kube-scheduler`，其中用到的配置文件如下

##### config

**config 是一个通用配置文件，值得注意的是由于安装时对于 Node、Master 节点都会包含该文件，在 Node 节点上请注释掉 `KUBE_MASTER` 变量，因为 Node 节点需要做 HA，要连接本地的 6443 加密端口；而这个变量将会覆盖 `kubeconfig` 中指定的 `127.0.0.1:6443` 地址**

``` sh
###
# kubernetes system config
#
# The following values are used to configure various aspects of all
# kubernetes services, including
#
#   kube-apiserver.service
#   kube-controller-manager.service
#   kube-scheduler.service
#   kubelet.service
#   kube-proxy.service
# logging to stderr means we get it in the systemd journal
KUBE_LOGTOSTDERR="--logtostderr=true"

# journal message level, 0 is debug
KUBE_LOG_LEVEL="--v=2"

# Should this cluster be allowed to run privileged docker containers
KUBE_ALLOW_PRIV="--allow-privileged=true"

# How the controller-manager, scheduler, and proxy find the apiserver
KUBE_MASTER="--master=http://127.0.0.1:8080"
```

##### apiserver

apiserver 配置相对于 1.8 略有变动，其中准入控制器(`admission control`)选项名称变为了 `--enable-admission-plugins`，控制器列表也有相应变化，这里采用官方推荐配置，具体请参考 [官方文档](https://kubernetes.io/docs/admin/admission-controllers/#is-there-a-recommended-set-of-admission-controllers-to-use)

``` sh
###
# kubernetes system config
#
# The following values are used to configure the kube-apiserver
#

# The address on the local server to listen to.
KUBE_API_ADDRESS="--advertise-address=192.168.1.61 --bind-address=192.168.1.61"

# The port on the local server to listen on.
KUBE_API_PORT="--secure-port=6443"

# Port minions listen on
# KUBELET_PORT="--kubelet-port=10250"

# Comma separated list of nodes in the etcd cluster
KUBE_ETCD_SERVERS="--etcd-servers=https://192.168.1.61:2379,https://192.168.1.62:2379,https://192.168.1.63:2379"

# Address range to use for services
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"

# default admission control policies
KUBE_ADMISSION_CONTROL="--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,ResourceQuota,NodeRestriction"

# Add your own!
KUBE_API_ARGS=" --anonymous-auth=false \
                --apiserver-count=3 \
                --audit-log-maxage=30 \
                --audit-log-maxbackup=3 \
                --audit-log-maxsize=100 \
                --audit-log-path=/var/log/kube-audit/audit.log \
                --audit-policy-file=/etc/kubernetes/audit-policy.yaml \
                --authorization-mode=Node,RBAC \
                --client-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                --enable-bootstrap-token-auth \
                --enable-garbage-collector \
                --enable-logs-handler \
                --enable-swagger-ui \
                --etcd-cafile=/etc/etcd/ssl/etcd-root-ca.pem \
                --etcd-certfile=/etc/etcd/ssl/etcd.pem \
                --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem \
                --etcd-compaction-interval=5m0s \
                --etcd-count-metric-poll-period=1m0s \
                --event-ttl=48h0m0s \
                --kubelet-https=true \
                --kubelet-timeout=3s \
                --log-flush-frequency=5s \
                --token-auth-file=/etc/kubernetes/token.csv \
                --tls-cert-file=/etc/kubernetes/ssl/kube-apiserver.pem \
                --tls-private-key-file=/etc/kubernetes/ssl/kube-apiserver-key.pem \
                --service-node-port-range=30000-50000 \
                --service-account-key-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                --storage-backend=etcd3 \
                --enable-swagger-ui=true"
```

##### controller-manager

controller manager 配置默认开启了证书轮换能力用于自动签署 kueblet 证书，并且证书时间也设置了 10 年，可自行调整；增加了 `--controllers` 选项以指定开启全部控制器

``` sh
###
# The following values are used to configure the kubernetes controller-manager

# defaults from config and apiserver should be adequate

# Add your own!
KUBE_CONTROLLER_MANAGER_ARGS="  --bind-address=0.0.0.0 \
                                --cluster-name=kubernetes \
                                --cluster-signing-cert-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                                --cluster-signing-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                                --controllers=*,bootstrapsigner,tokencleaner \
                                --deployment-controller-sync-period=10s \
                                --experimental-cluster-signing-duration=86700h0m0s \
                                --leader-elect=true \
                                --node-monitor-grace-period=40s \
                                --node-monitor-period=5s \
                                --pod-eviction-timeout=5m0s \
                                --terminated-pod-gc-threshold=50 \
                                --root-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                                --service-account-private-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                                --feature-gates=RotateKubeletServerCertificate=true"
```

##### scheduler

``` sh
###
# kubernetes scheduler config

# default config should be adequate

# Add your own!
KUBE_SCHEDULER_ARGS="   --address=0.0.0.0 \
                        --leader-elect=true \
                        --algorithm-provider=DefaultProvider"
```

#### 3.4、Node 节点配置

Node 节点上主要有 `kubelet`、`kube-proxy` 组件，用到的配置如下

##### kubelet

kubeket 默认也开启了证书轮换能力以保证自动续签相关证书，同时增加了 `--node-labels` 选项为 node 打一个标签，关于这个标签最后部分会有讨论，**如果在 master 上启动 kubelet，请将 `node-role.kubernetes.io/k8s-node=true` 修改为 `node-role.kubernetes.io/k8s-master=true`**

``` sh
###
# kubernetes kubelet (minion) config

# The address for the info server to serve on (set to 0.0.0.0 or "" for all interfaces)
KUBELET_ADDRESS="--node-ip=192.168.1.61"

# The port for the info server to serve on
# KUBELET_PORT="--port=10250"

# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname-override=k1.node"

# location of the api-server
# KUBELET_API_SERVER=""

# Add your own!
KUBELET_ARGS="  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
                --cert-dir=/etc/kubernetes/ssl \
                --cgroup-driver=cgroupfs \
                --cluster-dns=10.254.0.2 \
                --cluster-domain=cluster.local. \
                --fail-swap-on=false \
                --feature-gates=RotateKubeletClientCertificate=true,RotateKubeletServerCertificate=true \
                --node-labels=node-role.kubernetes.io/k8s-node=true \
                --image-gc-high-threshold=70 \
                --image-gc-low-threshold=50 \
                --kube-reserved=cpu=500m,memory=512Mi,ephemeral-storage=1Gi \
                --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
                --system-reserved=cpu=1000m,memory=1024Mi,ephemeral-storage=1Gi \
                --serialize-image-pulls=false \
                --sync-frequency=30s \
                --pod-infra-container-image=k8s.gcr.io/pause-amd64:3.0 \
                --resolv-conf=/etc/resolv.conf \
                --rotate-certificates"
```

##### proxy

``` sh
###
# kubernetes proxy config
# default config should be adequate
# Add your own!
KUBE_PROXY_ARGS="--bind-address=0.0.0.0 \
                 --hostname-override=k1.node \
                 --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \
                 --cluster-cidr=10.254.0.0/16"
```

#### 3.5、安装集群组件

上面已经准备好了相关配置文件，接下来将这些配置文件组织成如下目录结构以便后续脚本安装

``` sh
k8s
├── conf
│   ├── apiserver
│   ├── audit-policy.yaml
│   ├── bootstrap.kubeconfig
│   ├── config
│   ├── controller-manager
│   ├── kubelet
│   ├── kube-proxy.kubeconfig
│   ├── proxy
│   ├── scheduler
│   ├── ssl
│   │   ├── admin.csr
│   │   ├── admin-csr.json
│   │   ├── admin-key.pem
│   │   ├── admin.pem
│   │   ├── k8s-gencert.json
│   │   ├── k8s-root-ca.csr
│   │   ├── k8s-root-ca-csr.json
│   │   ├── k8s-root-ca-key.pem
│   │   ├── k8s-root-ca.pem
│   │   ├── kube-apiserver.csr
│   │   ├── kube-apiserver-csr.json
│   │   ├── kube-apiserver-key.pem
│   │   ├── kube-apiserver.pem
│   │   ├── kube-proxy.csr
│   │   ├── kube-proxy-csr.json
│   │   ├── kube-proxy-key.pem
│   │   └── kube-proxy.pem
│   └── token.csv
├── hyperkube_1.10.1
├── install.sh
└── systemd
    ├── kube-apiserver.service
    ├── kube-controller-manager.service
    ├── kubelet.service
    ├── kube-proxy.service
    └── kube-scheduler.service
```

其中 `install.sh` 内容如下

``` sh
#!/bin/bash

set -e

KUBE_VERSION="1.10.1"

function download_k8s(){
    if [ ! -f "hyperkube_${KUBE_VERSION}" ]; then
        wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/hyperkube -O hyperkube_${KUBE_VERSION}
        chmod +x hyperkube_${KUBE_VERSION}
    fi
}

function preinstall(){
    getent group kube >/dev/null || groupadd -r kube
    getent passwd kube >/dev/null || useradd -r -g kube -d / -s /sbin/nologin -c "Kubernetes user" kube
}

function install_k8s(){
    echo -e "\033[32mINFO: Copy hyperkube...\033[0m"
    cp hyperkube_${KUBE_VERSION} /usr/local/bin/hyperkube

    echo -e "\033[32mINFO: Create symbolic link...\033[0m"
    ln -sf /usr/local/bin/hyperkube /usr/local/bin/kubectl

    echo -e "\033[32mINFO: Copy kubernetes config...\033[0m"
    cp -r conf /etc/kubernetes
    if [ -d "/etc/kubernetes/ssl" ]; then
        chown -R kube:kube /etc/kubernetes/ssl
    fi

    echo -e "\033[32mINFO: Copy kubernetes systemd config...\033[0m"
    cp systemd/*.service /lib/systemd/system
    systemctl daemon-reload
}

function postinstall(){
    if [ ! -d "/var/log/kube-audit" ]; then
        mkdir /var/log/kube-audit
    fi

    if [ ! -d "/var/lib/kubelet" ]; then
        mkdir /var/lib/kubelet
    fi

    if [ ! -d "/usr/libexec" ]; then
        mkdir /usr/libexec
    fi
    chown -R kube:kube /var/log/kube-audit /var/lib/kubelet /usr/libexec
}


download_k8s
preinstall
install_k8s
postinstall
```

**脚本解释如下:**

- download_k8s: 下载 hyperkube 二进制文件
- preinstall: 安装前处理，同 etcd 一样创建 kube 普通用户指定家目录、shell 等
- install_k8s: 复制 hyperkube 到安装目录，为 kubectl 创建软连接(为啥创建软连接就能执行请自行阅读 [源码](https://github.com/kubernetes/kubernetes/blob/cce67ed8e7d461657d350a1cdd55791d1637fc43/cmd/hyperkube/main.go#L69))，复制相关配置到对应目录，并处理权限
- postinstall: 收尾工作，创建日志目录等，并处理权限

最后执行此脚本安装即可，**此外，应确保每个节点安装了 `ipset`、`conntrack` 两个包，因为 kube-proxy 组件会使用其处理 iptables 规则等**

### 四、启动 Kubernetes Master 节点

对于 `master` 节点启动无需做过多处理，多个 `master` 只要保证 `apiserver` 等配置中的 ip 地址监听没问题后直接启动即可

``` sh
systemctl daemon-reload
systemctl start kube-apiserver
systemctl start kube-controller-manager
systemctl start kube-scheduler
systemctl enable kube-apiserver
systemctl enable kube-controller-manager
systemctl enable kube-scheduler
```

成功后截图如下

![Master success](https://mritd.b0.upaiyun.com/markdown/lqur1.png)


### 五、启动 Kubernetes Node 节点

由于 HA 等功能需要，对于 Node 需要做一些处理才能启动，主要有以下两个地方需要处理

#### 5.1、nginx-proxy

在启动 `kubelet`、`kube-proxy` 服务之前，需要在本地启动 `nginx` 来 tcp 负载均衡 `apiserver` 6443 端口，`nginx-proxy` 使用 `docker` + `systemd` 启动，配置如下

**注意: 对于在 master 节点启动 kubelet 来说，不需要 nginx 做负载均衡；可以跳过此步骤，并修改 `kubelet.kubeconfig`、`kube-proxy.kubeconfig` 中的 apiserver 地址为当前 master ip 6443 端口即可**

- nginx-proxy.service

``` sh
[Unit]
Description=kubernetes apiserver docker wrapper
Wants=docker.socket
After=docker.service

[Service]
User=root
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run -p 127.0.0.1:6443:6443 \
                              -v /etc/nginx:/etc/nginx \
                              --name nginx-proxy \
                              --net=host \
                              --restart=on-failure:5 \
                              --memory=512M \
                              nginx:1.13.12-alpine
ExecStartPre=-/usr/bin/docker rm -f nginx-proxy
ExecStop=/usr/bin/docker stop nginx-proxy
Restart=always
RestartSec=15s
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
```

- nginx.conf

``` sh
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
        server 192.168.1.61:6443;
        server 192.168.1.62:6443;
        server 192.168.1.63:6443;
    }

    server {
        listen        0.0.0.0:6443;
        proxy_pass    kube_apiserver;
        proxy_timeout 10m;
        proxy_connect_timeout 1s;
    }
}
```

**启动 apiserver 的本地负载均衡**

``` sh
mkdir /etc/nginx
cp nginx.conf /etc/nginx
cp nginx-proxy.service /lib/systemd/system

systemctl daemon-reload
systemctl start nginx-proxy
systemctl enable nginx-proxy
```

#### 5.2、TLS bootstrapping

创建好 `nginx-proxy` 后不要忘记为 `TLS Bootstrap` 创建相应的 `RBAC` 规则，这些规则能实现证自动签署 `TLS Bootstrap` 发出的 `CSR` 请求，从而实现证书轮换(创建一次即可)；详情请参考 [Kubernetes TLS bootstrapping 那点事](https://mritd.me/2018/01/07/kubernetes-tls-bootstrapping-note/)

- tls-bootstrapping-clusterrole.yaml(与 1.8 一样)

``` yaml
# A ClusterRole which instructs the CSR approver to approve a node requesting a
# serving cert matching its client cert.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeserver
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
```

**在 master 执行创建**

``` sh
# 给与 kubelet-bootstrap 用户进行 node-bootstrapper 的权限
kubectl create clusterrolebinding kubelet-bootstrap \
    --clusterrole=system:node-bootstrapper \
    --user=kubelet-bootstrap

kubectl create -f tls-bootstrapping-clusterrole.yaml

# 自动批准 system:bootstrappers 组用户 TLS bootstrapping 首次申请证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-approve-csr \
        --clusterrole=system:certificates.k8s.io:certificatesigningrequests:nodeclient \
        --group=system:bootstrappers

# 自动批准 system:nodes 组用户更新 kubelet 自身与 apiserver 通讯证书的 CSR 请求
kubectl create clusterrolebinding node-client-auto-renew-crt \
        --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeclient \
        --group=system:nodes

# 自动批准 system:nodes 组用户更新 kubelet 10250 api 端口证书的 CSR 请求
kubectl create clusterrolebinding node-server-auto-renew-crt \
        --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeserver \
        --group=system:nodes
```

#### 5.3、执行启动

多节点部署时先启动好 `nginx-proxy`，然后修改好相应配置的 ip 地址等配置，最终直接启动即可(master 上启动 kubelet 不要忘了修改 kubeconfig 中的 apiserver 地址，还有对应的 kubelet 的 node label)

``` sh
systemctl daemon-reload
systemctl start kubelet
systemctl start kube-proxy
systemctl enable kubelet
systemctl enable kube-proxy
```

最后启动成功后如下

![cluster started](https://mritd.b0.upaiyun.com/markdown/r4s34.png)


### 五、安装 Calico

Calico 安装仍然延续以前的方案，使用 Daemonset 安装 cni 组件，使用 systemd 控制 calico-node 以确保 calico-node 能正确的拿到主机名等

#### 5.1、修改 Calico 配置

``` sh
wget https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/hosted/calico.yaml -O calico.example.yaml

ETCD_CERT=`cat /etc/etcd/ssl/etcd.pem | base64 | tr -d '\n'`
ETCD_KEY=`cat /etc/etcd/ssl/etcd-key.pem | base64 | tr -d '\n'`
ETCD_CA=`cat /etc/etcd/ssl/etcd-root-ca.pem | base64 | tr -d '\n'`
ETCD_ENDPOINTS="https://192.168.1.61:2379,https://192.168.1.62:2379,https://192.168.1.63:2379"

cp calico.example.yaml calico.yaml

sed -i "s@.*etcd_endpoints:.*@\ \ etcd_endpoints:\ \"${ETCD_ENDPOINTS}\"@gi" calico.yaml

sed -i "s@.*etcd-cert:.*@\ \ etcd-cert:\ ${ETCD_CERT}@gi" calico.yaml
sed -i "s@.*etcd-key:.*@\ \ etcd-key:\ ${ETCD_KEY}@gi" calico.yaml
sed -i "s@.*etcd-ca:.*@\ \ etcd-ca:\ ${ETCD_CA}@gi" calico.yaml

sed -i 's@.*etcd_ca:.*@\ \ etcd_ca:\ "/calico-secrets/etcd-ca"@gi' calico.yaml
sed -i 's@.*etcd_cert:.*@\ \ etcd_cert:\ "/calico-secrets/etcd-cert"@gi' calico.yaml
sed -i 's@.*etcd_key:.*@\ \ etcd_key:\ "/calico-secrets/etcd-key"@gi' calico.yaml

# 注释掉 calico-node 部分(由 Systemd 接管)
sed -i '123,219s@.*@#&@gi' calico.yaml
```

#### 5.2、创建 Systemd 文件

**注意: 创建 systemd service 配置文件要在每个节点上都执行**

``` sh
K8S_MASTER_IP="192.168.1.61"
HOSTNAME=`cat /etc/hostname`
ETCD_ENDPOINTS="https://192.168.1.61:2379,https://192.168.1.62:2379,https://192.168.1.63:2379"

cat > /lib/systemd/system/calico-node.service <<EOF
[Unit]
Description=calico node
After=docker.service
Requires=docker.service

[Service]
User=root
Environment=ETCD_ENDPOINTS=${ETCD_ENDPOINTS}
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run   --net=host --privileged --name=calico-node \\
                                -e ETCD_ENDPOINTS=\${ETCD_ENDPOINTS} \\
                                -e ETCD_CA_CERT_FILE=/etc/etcd/ssl/etcd-root-ca.pem \\
                                -e ETCD_CERT_FILE=/etc/etcd/ssl/etcd.pem \\
                                -e ETCD_KEY_FILE=/etc/etcd/ssl/etcd-key.pem \\
                                -e NODENAME=${HOSTNAME} \\
                                -e IP= \\
                                -e IP_AUTODETECTION_METHOD=can-reach=${K8S_MASTER_IP} \\
                                -e AS=64512 \\
                                -e CLUSTER_TYPE=k8s,bgp \\
                                -e CALICO_IPV4POOL_CIDR=10.20.0.0/16 \\
                                -e CALICO_IPV4POOL_IPIP=always \\
                                -e CALICO_LIBNETWORK_ENABLED=true \\
                                -e CALICO_NETWORKING_BACKEND=bird \\
                                -e CALICO_DISABLE_FILE_LOGGING=true \\
                                -e FELIX_IPV6SUPPORT=false \\
                                -e FELIX_DEFAULTENDPOINTTOHOSTACTION=ACCEPT \\
                                -e FELIX_LOGSEVERITYSCREEN=info \\
                                -e FELIX_IPINIPMTU=1440 \\
                                -e FELIX_HEALTHENABLED=true \\
                                -e CALICO_K8S_NODE_REF=${HOSTNAME} \\
                                -v /etc/calico/etcd-root-ca.pem:/etc/etcd/ssl/etcd-root-ca.pem \\
                                -v /etc/calico/etcd.pem:/etc/etcd/ssl/etcd.pem \\
                                -v /etc/calico/etcd-key.pem:/etc/etcd/ssl/etcd-key.pem \\
                                -v /lib/modules:/lib/modules \\
                                -v /var/lib/calico:/var/lib/calico \\
                                -v /var/run/calico:/var/run/calico \\
                                quay.io/calico/node:v3.1.0
ExecStop=/usr/bin/docker rm -f calico-node
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```
**对于以上脚本中的 `K8S_MASTER_IP` 变量，只需要填写一个 master ip 即可，这个变量用于 calico 自动选择 IP 使用；在宿主机有多张网卡的情况下，calcio node 会自动获取一个 IP，获取原则就是尝试是否能够联通这个 master ip**

由于 calico 需要使用 etcd 存储数据，所以需要复制 etcd 证书到相关目录，**`/etc/calico` 需要在每个节点都有**

``` sh
cp -r /etc/etcd/ssl /etc/calico
```

#### 5.3、修改 kubelet 配置

使用 Calico 后需要修改 kubelet 配置增加 CNI 设置(`--network-plugin=cni`)，修改后配置如下

``` sh
###
# kubernetes kubelet (minion) config

# The address for the info server to serve on (set to 0.0.0.0 or "" for all interfaces)
KUBELET_ADDRESS="--node-ip=192.168.1.61"

# The port for the info server to serve on
# KUBELET_PORT="--port=10250"

# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname-override=k1.node"

# location of the api-server
# KUBELET_API_SERVER=""

# Add your own!
KUBELET_ARGS="  --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
                --cert-dir=/etc/kubernetes/ssl \
                --cgroup-driver=cgroupfs \
                --network-plugin=cni \
                --cluster-dns=10.254.0.2 \
                --cluster-domain=cluster.local. \
                --fail-swap-on=false \
                --feature-gates=RotateKubeletClientCertificate=true,RotateKubeletServerCertificate=true \
                --node-labels=node-role.kubernetes.io/k8s-master=true \
                --image-gc-high-threshold=70 \
                --image-gc-low-threshold=50 \
                --kube-reserved=cpu=500m,memory=512Mi,ephemeral-storage=1Gi \
                --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
                --system-reserved=cpu=1000m,memory=1024Mi,ephemeral-storage=1Gi \
                --serialize-image-pulls=false \
                --sync-frequency=30s \
                --pod-infra-container-image=k8s.gcr.io/pause-amd64:3.0 \
                --resolv-conf=/etc/resolv.conf \
                --rotate-certificates"
```


#### 5.4、创建 Calico Daemonset

``` sh
# 先创建 RBAC
kubectl apply -f \
https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/rbac.yaml

# 再创建 Calico Daemonset
kubectl create -f calico.yaml
```

#### 5.5、启动 Calico Node

``` sh
systemctl daemon-reload
systemctl restart calico-node
systemctl enable calico-node

# 等待 20s 拉取镜像
sleep 20
systemctl restart kubelet
```

#### 5.6、测试网络

网络测试与其他几篇文章一样，创建几个 pod 测试即可

``` sh
# 创建 deployment
cat << EOF >> demo.deploy.yml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-deployment
spec:
  replicas: 5
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - name: demo
        image: mritd/demo
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
EOF
kubectl create -f demo.deploy.yml
```

测试结果如图所示

![test calico](https://mritd.b0.upaiyun.com/markdown/u9j3v.png)

### 六、部署集群 DNS

#### 6.1、部署 CoreDNS

CoreDNS 给出了标准的 deployment 配置，如下

- coredns.yaml.sed

``` sh
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRole
metadata:
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
rules:
- apiGroups:
  - ""
  resources:
  - endpoints
  - services
  - pods
  - namespaces
  verbs:
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: system:coredns
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:coredns
subjects:
- kind: ServiceAccount
  name: coredns
  namespace: kube-system
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health
        kubernetes CLUSTER_DOMAIN REVERSE_CIDRS {
          pods insecure
          upstream
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        proxy . /etc/resolv.conf
        cache 30
    }
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    k8s-app: kube-dns
    kubernetes.io/name: "CoreDNS"
spec:
  replicas: 2
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  selector:
    matchLabels:
      k8s-app: kube-dns
  template:
    metadata:
      labels:
        k8s-app: kube-dns
    spec:
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      containers:
      - name: coredns
        image: coredns/coredns:1.1.1
        imagePullPolicy: IfNotPresent
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
---
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: CLUSTER_DNS_IP
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
```

然后直接使用脚本替换即可(脚本变量我已经修改了)

``` sh
#!/bin/bash

# Deploys CoreDNS to a cluster currently running Kube-DNS.

SERVICE_CIDR=${1:-10.254.0.0/16}
POD_CIDR=${2:-10.20.0.0/16}
CLUSTER_DNS_IP=${3:-10.254.0.2}
CLUSTER_DOMAIN=${4:-cluster.local}
YAML_TEMPLATE=${5:-`pwd`/coredns.yaml.sed}

sed -e s/CLUSTER_DNS_IP/$CLUSTER_DNS_IP/g -e s/CLUSTER_DOMAIN/$CLUSTER_DOMAIN/g -e s?SERVICE_CIDR?$SERVICE_CIDR?g -e s?POD_CIDR?$POD_CIDR?g $YAML_TEMPLATE > coredns.yaml
```

最后使用 `kubectl` 创建一下

``` sh
# 执行上面的替换脚本
./deploy.sh

# 创建 CoreDNS
kubectl create -f coredns.yaml
```

测试截图如下

![test dns](https://mritd.b0.upaiyun.com/markdown/v1jdc.png)

#### 6.2、部署 DNS 自动扩容

自动扩容跟以往一样，yaml 创建一下就行

- dns-horizontal-autoscaler.yaml

``` sh
# Copyright 2016 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

kind: ServiceAccount
apiVersion: v1
metadata:
  name: kube-dns-autoscaler
  namespace: kube-system
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
---
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:kube-dns-autoscaler
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
rules:
  - apiGroups: [""]
    resources: ["nodes"]
    verbs: ["list"]
  - apiGroups: [""]
    resources: ["replicationcontrollers/scale"]
    verbs: ["get", "update"]
  - apiGroups: ["extensions"]
    resources: ["deployments/scale", "replicasets/scale"]
    verbs: ["get", "update"]
# Remove the configmaps rule once below issue is fixed:
# kubernetes-incubator/cluster-proportional-autoscaler#16
  - apiGroups: [""]
    resources: ["configmaps"]
    verbs: ["get", "create"]
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:kube-dns-autoscaler
  labels:
    addonmanager.kubernetes.io/mode: Reconcile
subjects:
  - kind: ServiceAccount
    name: kube-dns-autoscaler
    namespace: kube-system
roleRef:
  kind: ClusterRole
  name: system:kube-dns-autoscaler
  apiGroup: rbac.authorization.k8s.io

---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kube-dns-autoscaler
  namespace: kube-system
  labels:
    k8s-app: kube-dns-autoscaler
    kubernetes.io/cluster-service: "true"
    addonmanager.kubernetes.io/mode: Reconcile
spec:
  selector:
    matchLabels:
      k8s-app: kube-dns-autoscaler
  template:
    metadata:
      labels:
        k8s-app: kube-dns-autoscaler
      annotations:
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      priorityClassName: system-cluster-critical
      containers:
      - name: autoscaler
        image: k8s.gcr.io/cluster-proportional-autoscaler-amd64:1.1.2-r2
        resources:
            requests:
                cpu: "20m"
                memory: "10Mi"
        command:
          - /cluster-proportional-autoscaler
          - --namespace=kube-system
          - --configmap=kube-dns-autoscaler
          # Should keep target in sync with cluster/addons/dns/kube-dns.yaml.base
          - --target=Deployment/kube-dns
          # When cluster is using large nodes(with more cores), "coresPerReplica" should dominate.
          # If using small nodes, "nodesPerReplica" should dominate.
          - --default-params={"linear":{"coresPerReplica":256,"nodesPerReplica":16,"preventSinglePointFailure":true}}
          - --logtostderr=true
          - --v=2
      tolerations:
      - key: "CriticalAddonsOnly"
        operator: "Exists"
      serviceAccountName: kube-dns-autoscaler
```

### 七、部署 heapster

heapster 部署相对简单的多，yaml 创建一下就可以了

``` sh
kubectl create -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/grafana.yaml
kubectl create -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml
kubectl create -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml
kubectl create -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml
```

### 八、部署 Dashboard

#### 8.1、部署 Dashboard

Dashboard 部署同 heapster 一样，不过为了方便访问，我设置了 NodePort，还注意到一点是 yaml 拉取策略已经没有比较傻的 `Always` 了

``` sh
wget https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml -O kubernetes-dashboard.yaml
```

将最后部分的端口暴露修改如下

``` yaml
# ------------------- Dashboard Service ------------------- #

kind: Service
apiVersion: v1
metadata:
  labels:
    k8s-app: kubernetes-dashboard
  name: kubernetes-dashboard
  namespace: kube-system
spec:
  type: NodePort
  ports:
    - name: dashboard-tls
      port: 443
      targetPort: 8443
      nodePort: 30000
      protocol: TCP
  selector:
    k8s-app: kubernetes-dashboard
```

然后执行 `kubectl create -f kubernetes-dashboard.yaml` 即可

#### 8.2、创建 admin 账户

默认情况下部署成功后可以直接访问 `https://NODE_IP:30000` 访问，但是想要登录进去查看的话需要使用 kubeconfig 或者 access token 的方式；实际上这个就是 RBAC 授权控制，以下提供一个创建 admin access token 的脚本，更细节的权限控制比如只读用户可以参考 [使用 RBAC 控制 kubectl 权限](https://mritd.me/2018/03/20/use-rbac-to-control-kubectl-permissions/)，RBAC 权限控制原理是一样的

``` sh
#!/bin/bash

if kubectl get sa dashboard-admin -n kube-system &> /dev/null;then
    echo -e "\033[33mWARNING: ServiceAccount dashboard-admin exist!\033[0m"
else
    kubectl create sa dashboard-admin -n kube-system
    kubectl create clusterrolebinding dashboard-admin --clusterrole=cluster-admin --serviceaccount=kube-system:dashboard-admin
fi

kubectl describe secret -n kube-system $(kubectl get secrets -n kube-system | grep dashboard-admin | cut -f1 -d ' ') | grep -E '^token'
```

将以上脚本保存为 `create_dashboard_sa.sh` 执行即可，成功后访问截图如下(**如果访问不了的话请检查下 iptable FORWARD 默认规则是否为 DROP，如果是将其改为 ACCEPT 即可**)

![create_dashboard_sa](https://mritd.b0.upaiyun.com/markdown/oxmms.png)

![dashboard](https://mritd.b0.upaiyun.com/markdown/pyplb.png)

### 九、其他说明

#### 9.1、选项 label 等说明

部署过程中注意到一些选项已经做了名称更改，比如 `--network-plugin-dir` 变更为 `--cni-bin-dir` 等，具体的那些选项做了变更请自行对比配置，以及查看官方文档；

对于 Node label `--node-labels=node-role.kubernetes.io/k8s-node=true` 这个选项，它的作用只是在 `kubectl get node` 时 ROLES 栏显示是什么节点；不过需要注意 **master 上的 kubelet 不要将 `node-role.kubernetes.io/k8s-master=true` 更改成 `node-role.kubernetes.io/master=xxxx`；后面这个 `node-role.kubernetes.io/master` 是 kubeadm 用的，这个 label 会告诉 k8s 调度器当前节点为 master，从而执行一些特定动作，比如 `node-role.kubernetes.io/master:NoSchedule` 此节点将不会被分配 pod；具体参见 [kubespray issue](https://github.com/kubernetes-incubator/kubespray/issues/2108) 以及 [官方设计文档](https://github.com/kubernetes/kubeadm/blob/master/docs/design/design_v1.9.md#mark-master)**

很多人可能会发现大约 1 小时候 `kubectl get csr` 看不到任何 csr 了，这是因为最新版本增加了 csr 清理功能，**默认对于 `approved` 和 `denied` 状态的 csr 一小时后会被清理，对于 `pending` 状态的 csr 24 小时后会被清理，想问时间从哪来的请看 [代码](https://github.com/kubernetes/kubernetes/blob/fa85bf7094a8a503fede964b7038eed51360ffc7/pkg/controller/certificates/cleaner/cleaner.go#L47)；PR issue 我忘记了，增加这个功能的起因大致就是因为当开启了证书轮换后，csr 会不断增加，所以需要增加一个清理功能**

#### 9.2、异常及警告说明

在部署过程中我记录了一些异常警告等，以下做一下统一说明

``` sh
# https://github.com/kubernetes/kubernetes/issues/42158
# 这个问题还没解决，PR 没有合并被关闭了，可以关注一下上面这个 issue，被关闭的 PR 在下面
# https://github.com/kubernetes/kubernetes/pull/49567
Failed to update statusUpdateNeeded field in actual state of world: Failed to set statusUpdateNeeded to needed true, because nodeName=...

# https://github.com/kubernetes/kubernetes/issues/59993
# 这个似乎已经解决了，没时间测试，PR 地址在下面，我大致 debug 一下 好像是 cAdvisor 的问题
# https://github.com/opencontainers/runc/pull/1722
Failed to get system container stats for "/kubepods": failed to get cgroup stats for "/kubepods": failed to get container info for "/kubepods": unknown containe "/kubepods"

# https://github.com/kubernetes/kubernetes/issues/58217
# 注意: 这个问题现在仍未解决，可关注上面的 issue，这个问题可能影响 node image gc
# 强烈依赖于 kubelet 做 宿主机 image gc 的需要注意一下
Image garbage collection failed once. Stats initialization may not have completed yet: failed to get imageFs info: unable to find data for container /

# 没找到太多资料，不过感觉跟上面问题类似
failed to construct signal: "allocatableMemory.available" error: system container "pods" not found in metrics
```


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
