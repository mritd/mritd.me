---
layout: post
categories: Kubernetes
title: Kubernetes 1.13.4 搭建
date: 2019-03-16 17:36:52 +0800
description: Kubernetes 1.13.4 搭建
keywords: kubernetes,docker,calico
catalog: true
multilingual: false
tags: Kubernetes
---

> 年后回来有点懒，也有点忙；1.13 出来好久了，周末还是决定折腾一下吧

## 一、环境准备

老样子，安装环境为 5 台 Ubuntu 18.04.2 LTS 虚拟机，其他详细信息如下

|System OS|IP Address|Docker|Kernel|Application|
|---------|----------|-----|------|-----------|
|Ubuntu 18.04.2 LTS|192.168.1.51|18.09.2|4.15.0-46-generic|k8s-master、etcd|
|Ubuntu 18.04.2 LTS|192.168.1.52|18.09.2|4.15.0-46-generic|k8s-master、etcd|
|Ubuntu 18.04.2 LTS|192.168.1.53|18.09.2|4.15.0-46-generic|k8s-master、etcd|
|Ubuntu 18.04.2 LTS|192.168.1.54|18.09.2|4.15.0-46-generic|k8s-node|
|Ubuntu 18.04.2 LTS|192.168.1.55|18.09.2|4.15.0-46-generic|k8s-node|

**所有配置生成将在第一个节点上完成，第一个节点与其他节点 root 用户免密码登录，用于分发文件；为了方便搭建弄了一点小脚本，仓库地址 [ktool](https://github.com/mritd/ktool)，本文后续所有脚本、配置都可以在此仓库找到；关于 [cfssl](https://github.com/cloudflare/cfssl) 等基本工具使用，本文不再阐述**

## 二、安装 Etcd

### 2.1、生成证书

Etcd 仍然开启 TLS 认证，所以先使用 cfssl 生成相关证书

- etcd-root-ca-csr.json

``` json
{
    "CN": "etcd-root-ca",
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
    "ca": {
        "expiry": "87600h"
    }
}
```

- etcd-gencert.json

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

- etcd-csr.json

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
        "192.168.1.51",
        "192.168.1.52",
        "192.168.1.53"
    ]
}
```

接下来执行生成即可；**我建议在生产环境在证书内预留几个 IP，已防止意外故障迁移时还需要重新生成证书；证书默认期限为 10 年(包括 CA 证书)，有需要加强安全性的可以适当减小**

``` sh
cfssl gencert --initca=true etcd-root-ca-csr.json | cfssljson --bare etcd-root-ca
cfssl gencert --ca etcd-root-ca.pem --ca-key etcd-root-ca-key.pem --config etcd-gencert.json etcd-csr.json | cfssljson --bare etcd
```

### 2.2、安装 Etcd

#### 2.2.1、安装脚本

安装 Etcd 只需要将二进制文件放在可执行目录下，然后修改配置增加 systemd service 配置文件即可；为了安全性起见最好使用单独的用户启动 Etcd

``` sh
#!/bin/bash

set -e

ETCD_DEFAULT_VERSION="3.3.12"

if [ "$1" != "" ]; then
  ETCD_VERSION=$1
else
  echo -e "\033[33mWARNING: ETCD_VERSION is blank,use default version: ${ETCD_DEFAULT_VERSION}\033[0m"
  ETCD_VERSION=${ETCD_DEFAULT_VERSION}
fi

# 下载 Etcd 二进制文件
function download(){
    if [ ! -f "etcd-v${ETCD_VERSION}-linux-amd64.tar.gz" ]; then
        wget https://github.com/coreos/etcd/releases/download/v${ETCD_VERSION}/etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
        tar -zxvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
    fi
}

# 为 Etcd 创建单独的用户
function preinstall(){
	getent group etcd >/dev/null || groupadd -r etcd
	getent passwd etcd >/dev/null || useradd -r -g etcd -d /var/lib/etcd -s /sbin/nologin -c "etcd user" etcd
}

# 安装(复制文件)
function install(){

    # 释放 Etcd 二进制文件
    echo -e "\033[32mINFO: Copy etcd...\033[0m"
    tar -zxvf etcd-v${ETCD_VERSION}-linux-amd64.tar.gz
    cp etcd-v${ETCD_VERSION}-linux-amd64/etcd* /usr/local/bin
    rm -rf etcd-v${ETCD_VERSION}-linux-amd64

    # 复制 配置文件 到 /etc/etcd(目录内文件结构在下面)
    echo -e "\033[32mINFO: Copy etcd config...\033[0m"
    cp -r conf /etc/etcd
    chown -R etcd:etcd /etc/etcd
    chmod -R 755 /etc/etcd/ssl

    # 复制 systemd service 配置
    echo -e "\033[32mINFO: Copy etcd systemd config...\033[0m"
    cp systemd/*.service /lib/systemd/system
    systemctl daemon-reload
}

# 创建 Etcd 存储目录(如需要更改，请求改 /etc/etcd/etcd.conf 配置文件)
function postinstall(){
    if [ ! -d "/var/lib/etcd" ]; then
        mkdir /var/lib/etcd
        chown -R etcd:etcd /var/lib/etcd
    fi

}

# 依次执行
download
preinstall
install
postinstall
```

#### 2.2.2、配置文件

**关于配置文件目录结构如下(请自行复制证书)**

``` sh
conf
├── etcd.conf
├── etcd.conf.cluster.example
├── etcd.conf.single.example
└── ssl
    ├── etcd-key.pem
    ├── etcd.pem
    ├── etcd-root-ca-key.pem
    └── etcd-root-ca.pem

1 directory, 7 files
```

- etcd.conf

``` sh
# [member]
ETCD_NAME=etcd1
ETCD_DATA_DIR="/var/lib/etcd/data"
ETCD_WAL_DIR="/var/lib/etcd/wal"
ETCD_SNAPSHOT_COUNT="100"
ETCD_HEARTBEAT_INTERVAL="100"
ETCD_ELECTION_TIMEOUT="1000"
ETCD_LISTEN_PEER_URLS="https://192.168.1.51:2380"
ETCD_LISTEN_CLIENT_URLS="https://192.168.1.51:2379,http://127.0.0.1:2379"
ETCD_MAX_SNAPSHOTS="5"
ETCD_MAX_WALS="5"
#ETCD_CORS=""

# [cluster]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://192.168.1.51:2380"
# if you use different ETCD_NAME (e.g. test), set ETCD_INITIAL_CLUSTER value for this name, i.e. "test=http://..."
ETCD_INITIAL_CLUSTER="etcd1=https://192.168.1.51:2380,etcd2=https://192.168.1.52:2380,etcd3=https://192.168.1.53:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_ADVERTISE_CLIENT_URLS="https://192.168.1.51:2379"
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

- etcd.service

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

最后三台机器依次修改 `IP`、`ETCD_NAME` 然后启动即可，**生产环境请不要忘记修改集群 Token 为真实随机字符串 (`ETCD_INITIAL_CLUSTER_TOKEN` 变量)**启动后可以通过以下命令测试集群联通性

``` sh
docker1.node ➜  ~ export ETCDCTL_API=3
docker1.node ➜  ~ etcdctl member list
238b72cdd26e304f, started, etcd2, https://192.168.1.52:2380, https://192.168.1.52:2379
8034142cf01c5d1c, started, etcd3, https://192.168.1.53:2380, https://192.168.1.53:2379
8da171dbef9ded69, started, etcd1, https://192.168.1.51:2380, https://192.168.1.51:2379
```

## 三、安装 Kubernetes

### 3.1、生成证书及配置

#### 3.1.1、生成证书

新版本已经越来越趋近全面 TLS + RBAC 配置，**所以本次安装将会启动大部分 TLS + RBAC 配置，包括 `kube-controler-manager`、`kube-scheduler` 组件不再连接本地 `kube-apiserver` 的 8080 非认证端口，`kubelet` 等组件 API 端点关闭匿名访问，启动 RBAC 认证等**；为了满足这些认证，需要签署以下证书

- k8s-root-ca-csr.json 集群 CA 根证书

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
            "O": "kubernetes",
            "OU": "System"
        }
    ],
    "ca": {
        "expiry": "87600h"
    }
}
```

- k8s-gencert.json 用于生成其他证书的标准配置

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

- kube-apiserver-csr.json apiserver TLS 认证端口需要的证书

``` json
{
    "CN": "kubernetes",
    "hosts": [
        "127.0.0.1",
        "10.254.0.1",
        "localhost",
        "*.master.kubernetes.node",
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
            "O": "kubernetes",
            "OU": "System"
        }
    ]
}
```

- kube-controller-manager-csr.json controller manager 连接 apiserver 需要使用的证书，同时本身 `10257` 端口也会使用此证书

``` json
{
  "CN": "system:kube-controller-manager",
  "hosts": [
    "127.0.0.1",
    "localhost",
    "*.master.kubernetes.node"
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
      "O": "system:kube-controller-manager",
      "OU": "System"
    }
  ]
}
```

- kube-scheduler-csr.json scheduler 连接 apiserver 需要使用的证书，同时本身 `10259` 端口也会使用此证书

``` json
{
  "CN": "system:kube-scheduler",
  "hosts": [
    "127.0.0.1",
    "localhost",
    "*.master.kubernetes.node"
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
      "O": "system:kube-scheduler",
      "OU": "System"
    }
  ]
}
```

- kube-proxy-csr.json proxy 组件连接 apiserver 需要使用的证书

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
            "O": "system:kube-proxy",
            "OU": "System"
        }
    ]
}
```

- kubelet-api-admin-csr.json apiserver 反向连接 kubelet 组件 `10250` 端口需要使用的证书(例如执行 `kubectl logs`)

``` json
{
    "CN": "system:kubelet-api-admin",
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
            "O": "system:kubelet-api-admin",
            "OU": "System"
        }
    ]
}
```

- admin-csr.json 集群管理员(kubectl)连接 apiserver 需要使用的证书

``` json
{
    "CN": "system:masters",
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

**注意: 请不要修改证书配置的 `CN`、`O` 字段，这两个字段名称比较特殊，大多数为 `system:` 开头，实际上是为了匹配 RBAC 规则，具体请参考 [Default Roles and Role Bindings](https://kubernetes.io/docs/reference/access-authn-authz/rbac/#default-roles-and-role-bindings)**

最后使用如下命令生成即可:

``` sh
cfssl gencert --initca=true k8s-root-ca-csr.json | cfssljson --bare k8s-root-ca

for targetName in kube-apiserver kube-controller-manager kube-scheduler kube-proxy kubelet-api-admin admin; do
    cfssl gencert --ca k8s-root-ca.pem --ca-key k8s-root-ca-key.pem --config k8s-gencert.json --profile kubernetes $targetName-csr.json | cfssljson --
bare $targetName
done
```

#### 3.1.2、生成配置文件

集群搭建需要预先生成一系列配置文件，生成配置需要预先安装 `kubectl` 命令，请自行根据文档安装 [Install kubectl binary using curl](https://kubernetes.io/docs/tasks/tools/install-kubectl/#install-kubectl-binary-using-curl)；其中配置文件及其作用如下:

- `bootstrap.kubeconfig` kubelet TLS Bootstarp 引导阶段需要使用的配置文件
- `kube-controller-manager.kubeconfig` controller manager 组件开启安全端口及 RBAC 认证所需配置
- `kube-scheduler.kubeconfig` scheduler 组件开启安全端口及 RBAC 认证所需配置
- `kube-proxy.kubeconfig` proxy 组件连接 apiserver 所需配置文件
- `audit-policy.yaml` apiserver RBAC 审计日志配置文件
- `bootstrap.secret.yaml` kubelet TLS Bootstarp 引导阶段使用 Bootstrap Token 方式引导，需要预先创建此 Token

生成这些配置文件的脚本如下

``` sh
# 指定 apiserver 地址
KUBE_APISERVER="https://127.0.0.1:6443"

# 生成 Bootstrap Token
BOOTSTRAP_TOKEN_ID=$(head -c 6 /dev/urandom | md5sum | head -c 6)
BOOTSTRAP_TOKEN_SECRET=$(head -c 16 /dev/urandom | md5sum | head -c 16)
BOOTSTRAP_TOKEN="${BOOTSTRAP_TOKEN_ID}.${BOOTSTRAP_TOKEN_SECRET}"
echo "Bootstrap Tokne: ${BOOTSTRAP_TOKEN}"

# 生成 kubelet tls bootstrap 配置
echo "Create kubelet bootstrapping kubeconfig..."
kubectl config set-cluster kubernetes \
  --certificate-authority=k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig
kubectl config set-credentials "system:bootstrap:${BOOTSTRAP_TOKEN_ID}" \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user="system:bootstrap:${BOOTSTRAP_TOKEN_ID}" \
  --kubeconfig=bootstrap.kubeconfig
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

# 生成 kube-controller-manager 配置文件
echo "Create kube-controller-manager kubeconfig..."
kubectl config set-cluster kubernetes \
  --certificate-authority=k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-controller-manager.kubeconfig
kubectl config set-credentials "system:kube-controller-manager" \
  --client-certificate=kube-controller-manager.pem \
  --client-key=kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-controller-manager.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=system:kube-controller-manager \
  --kubeconfig=kube-controller-manager.kubeconfig
kubectl config use-context default --kubeconfig=kube-controller-manager.kubeconfig 

# 生成 kube-scheduler 配置文件
echo "Create kube-scheduler kubeconfig..."
kubectl config set-cluster kubernetes \
  --certificate-authority=k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-scheduler.kubeconfig
kubectl config set-credentials "system:kube-scheduler" \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-scheduler.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=system:kube-scheduler \
  --kubeconfig=kube-scheduler.kubeconfig
kubectl config use-context default --kubeconfig=kube-scheduler.kubeconfig 

# 生成 kube-proxy 配置文件
echo "Create kube-proxy kubeconfig..."
kubectl config set-cluster kubernetes \
  --certificate-authority=k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-credentials "system:kube-proxy" \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=system:kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig 

# 生成 apiserver RBAC 审计配置文件 
cat >> audit-policy.yaml <<EOF
# Log all requests at the Metadata level.
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
EOF

# 生成 tls bootstrap token secret 配置文件
cat >> bootstrap.secret.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  # Name MUST be of form "bootstrap-token-<token id>"
  name: bootstrap-token-${BOOTSTRAP_TOKEN_ID}
  namespace: kube-system
# Type MUST be 'bootstrap.kubernetes.io/token'
type: bootstrap.kubernetes.io/token
stringData:
  # Human readable description. Optional.
  description: "The default bootstrap token."
  # Token ID and secret. Required.
  token-id: ${BOOTSTRAP_TOKEN_ID}
  token-secret: ${BOOTSTRAP_TOKEN_SECRET}
  # Expiration. Optional.
  expiration: $(date -d'+2 day' -u +"%Y-%m-%dT%H:%M:%SZ")
  # Allowed usages.
  usage-bootstrap-authentication: "true"
  usage-bootstrap-signing: "true"
  # Extra groups to authenticate the token as. Must start with "system:bootstrappers:"
#  auth-extra-groups: system:bootstrappers:worker,system:bootstrappers:ingress
EOF
```

### 3.2、处理 ipvs 及依赖

新版本目前 `kube-proxy` 组件全部采用 ipvs 方式负载，所以为了 `kube-proxy` 能正常工作需要预先处理一下 ipvs 配置以及相关依赖(每台 node 都要处理)

``` sh
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

apt install -y conntrack ipvsadm
```


### 3.3、部署 Master

#### 3.3.1、安装脚本

master 节点上需要三个组件: `kube-apiserver`、`kube-controller-manager`、`kube-scheduler`

**安装流程整体为以下几步**

- **创建单独的 `kube` 用户**
- **复制相关二进制文件到 `/usr/bin`，可以采用 `all in one` 的 `hyperkube`**
- **复制配置文件到 `/etc/kubernetes`**
- **复制证书文件到 `/etc/kubernetes/ssl`**
- **修改配置并启动**

安装脚本如下所示:

``` sh
KUBE_DEFAULT_VERSION="1.13.4"

if [ "$1" != "" ]; then
  KUBE_VERSION=$1
else
  echo -e "\033[33mWARNING: KUBE_VERSION is blank,use default version: ${KUBE_DEFAULT_VERSION}\033[0m"
  KUBE_VERSION=${KUBE_DEFAULT_VERSION}
fi

# 下载 hyperkube
function download_k8s(){
    if [ ! -f "hyperkube_v${KUBE_VERSION}" ]; then
        wget https://storage.googleapis.com/kubernetes-release/release/v${KUBE_VERSION}/bin/linux/amd64/hyperkube -O hyperkube_v${KUBE_VERSION}
        chmod +x hyperkube_v${KUBE_VERSION}
    fi
}

# 创建专用用户 kube
function preinstall(){
    getent group kube >/dev/null || groupadd -r kube
    getent passwd kube >/dev/null || useradd -r -g kube -d / -s /sbin/nologin -c "Kubernetes user" kube
}

# 复制可执行文件和配置以及证书
function install_k8s(){
    echo -e "\033[32mINFO: Copy hyperkube...\033[0m"
    cp hyperkube_v${KUBE_VERSION} /usr/bin/hyperkube

    echo -e "\033[32mINFO: Create symbolic link...\033[0m"
    (cd /usr/bin && hyperkube --make-symlinks)

    echo -e "\033[32mINFO: Copy kubernetes config...\033[0m"
    cp -r conf /etc/kubernetes
    if [ -d "/etc/kubernetes/ssl" ]; then
        chown -R kube:kube /etc/kubernetes/ssl
    fi

    echo -e "\033[32mINFO: Copy kubernetes systemd config...\033[0m"
    cp systemd/*.service /lib/systemd/system
    systemctl daemon-reload
}

# 创建必要的目录并修改权限
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
    chown -R kube:kube /etc/kubernetes /var/log/kube-audit /var/lib/kubelet /usr/libexec
}

# 执行
download_k8s
preinstall
install_k8s
postinstall
```

**hyperkube 是一个多合一的可执行文件，通过 `--make-symlinks` 会在当前目录生成 kubernetes 各个组件的软连接**

被复制的 conf 目录结构如下(最终被复制到 `/etc/kubernetes`)

``` sh
.
├── apiserver
├── audit-policy.yaml
├── bootstrap.kubeconfig
├── bootstrap.secret.yaml
├── controller-manager
├── kube-controller-manager.kubeconfig
├── kubelet
├── kube-proxy.kubeconfig
├── kube-scheduler.kubeconfig
├── proxy
├── scheduler
└── ssl
    ├── admin-key.pem
    ├── admin.pem
    ├── k8s-root-ca-key.pem
    ├── k8s-root-ca.pem
    ├── kube-apiserver-key.pem
    ├── kube-apiserver.pem
    ├── kube-controller-manager-key.pem
    ├── kube-controller-manager.pem
    ├── kubelet-api-admin-key.pem
    ├── kubelet-api-admin.pem
    ├── kube-proxy-key.pem
    ├── kube-proxy.pem
    ├── kube-scheduler-key.pem
    └── kube-scheduler.pem

1 directory, 25 files
```

#### 3.3.2、配置文件

以下为相关配置文件内容

**systemd 配置如下**

- kube-apiserver.service

``` sh
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
After=etcd.service

[Service]
EnvironmentFile=-/etc/kubernetes/apiserver
User=kube
ExecStart=/usr/bin/kube-apiserver \
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

- kube-controller-manager.service

``` sh
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/controller-manager
User=kube
ExecStart=/usr/bin/kube-controller-manager \
	    $KUBE_LOGTOSTDERR \
	    $KUBE_LOG_LEVEL \
	    $KUBE_MASTER \
	    $KUBE_CONTROLLER_MANAGER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

- kube-scheduler.service

``` sh
[Unit]
Description=Kubernetes Scheduler Plugin
Documentation=https://github.com/GoogleCloudPlatform/kubernetes

[Service]
EnvironmentFile=-/etc/kubernetes/scheduler
User=kube
ExecStart=/usr/bin/kube-scheduler \
	    $KUBE_LOGTOSTDERR \
	    $KUBE_LOG_LEVEL \
	    $KUBE_MASTER \
	    $KUBE_SCHEDULER_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```



**核心配置文件**

- apiserver

``` sh
###
# kubernetes system config
#
# The following values are used to configure the kube-apiserver
#

# The address on the local server to listen to.
KUBE_API_ADDRESS="--advertise-address=192.168.1.51 --bind-address=0.0.0.0"

# The port on the local server to listen on.
KUBE_API_PORT="--secure-port=6443"

# Port minions listen on
# KUBELET_PORT="--kubelet-port=10250"

# Comma separated list of nodes in the etcd cluster
KUBE_ETCD_SERVERS="--etcd-servers=https://192.168.1.51:2379,https://192.168.1.52:2379,https://192.168.1.53:2379"

# Address range to use for services
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"

# default admission control policies
KUBE_ADMISSION_CONTROL="--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,DefaultStorageClass,DefaultTolerationSeconds,MutatingAdmissionWebhook,ValidatingAdmissionWebhook,Priority,ResourceQuota"

# Add your own!
KUBE_API_ARGS=" --allow-privileged=true \
                --anonymous-auth=false \
                --alsologtostderr \
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
                --endpoint-reconciler-type=lease \
                --etcd-cafile=/etc/etcd/ssl/etcd-root-ca.pem \
                --etcd-certfile=/etc/etcd/ssl/etcd.pem \
                --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem \
                --etcd-compaction-interval=0s \
                --event-ttl=168h0m0s \
                --kubelet-https=true \
                --kubelet-certificate-authority=/etc/kubernetes/ssl/k8s-root-ca.pem \
                --kubelet-client-certificate=/etc/kubernetes/ssl/kubelet-api-admin.pem \
                --kubelet-client-key=/etc/kubernetes/ssl/kubelet-api-admin-key.pem \
                --kubelet-timeout=3s \
                --runtime-config=api/all=true \
                --service-node-port-range=30000-50000 \
                --service-account-key-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                --tls-cert-file=/etc/kubernetes/ssl/kube-apiserver.pem \
                --tls-private-key-file=/etc/kubernetes/ssl/kube-apiserver-key.pem \
                --v=2"
```

配置解释:

|选项|作用|
|---|----|
|`--client-ca-file`|定义客户端 CA|
|`--endpoint-reconciler-type`|master endpoint 策略|
|`--kubelet-client-certificate`、`--kubelet-client-key`|master 反向连接 kubelet 使用的证书|
|`--service-account-key-file`|service account 签名 key(用于有效性验证)|
|`--tls-cert-file`、`--tls-private-key-file`|master apiserver `6443` 端口证书|

- controller-manager

``` sh
###
# The following values are used to configure the kubernetes controller-manager

# defaults from config and apiserver should be adequate

# Add your own!
KUBE_CONTROLLER_MANAGER_ARGS="  --address=127.0.0.1 \
                                --authentication-kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
                                --authorization-kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
                                --bind-address=0.0.0.0 \
                                --cluster-name=kubernetes \
                                --cluster-signing-cert-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                                --cluster-signing-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                                --client-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                                --controllers=*,bootstrapsigner,tokencleaner \
                                --deployment-controller-sync-period=10s \
                                --experimental-cluster-signing-duration=87600h0m0s \
                                --enable-garbage-collector=true \
                                --kubeconfig=/etc/kubernetes/kube-controller-manager.kubeconfig \
                                --leader-elect=true \
                                --node-monitor-grace-period=20s \
                                --node-monitor-period=5s \
                                --port=10252 \
                                --pod-eviction-timeout=2m0s \
                                --requestheader-client-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                                --terminated-pod-gc-threshold=50 \
                                --tls-cert-file=/etc/kubernetes/ssl/kube-controller-manager.pem \
                                --tls-private-key-file=/etc/kubernetes/ssl/kube-controller-manager-key.pem \
                                --root-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                                --secure-port=10257 \
                                --service-cluster-ip-range=10.254.0.0/16 \
                                --service-account-private-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                                --use-service-account-credentials=true \
                                --v=2"
```

controller manager 将不安全端口 `10252` 绑定到 127.0.0.1 确保 `kuebctl get cs` 有正确返回；将安全端口 `10257` 绑定到 0.0.0.0 公开，提供服务调用；**由于 controller manager 开始连接 apiserver 的 `6443` 认证端口，所以需要 `--use-service-account-credentials` 选项来让 controller manager 创建单独的 service account(默认 `system:kube-controller-manager` 用户没有那么高权限)**

- scheduler

``` sh
###
# kubernetes scheduler config

# default config should be adequate

# Add your own!
KUBE_SCHEDULER_ARGS="   --address=127.0.0.1 \
                        --authentication-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
                        --authorization-kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
                        --bind-address=0.0.0.0 \
                        --client-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                        --kubeconfig=/etc/kubernetes/kube-scheduler.kubeconfig \
                        --requestheader-client-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                        --secure-port=10259 \
                        --leader-elect=true \
                        --port=10251 \
                        --tls-cert-file=/etc/kubernetes/ssl/kube-scheduler.pem \
                        --tls-private-key-file=/etc/kubernetes/ssl/kube-scheduler-key.pem \
```

shceduler 同  controller manager 一样将不安全端口绑定在本地，安全端口对外公开


**最后在三台节点上调整一下 IP 配置，启动即可**

### 3.4、部署 Node

#### 3.4.1、安装脚本

node 安装与 master 安装过程一致，这里不再阐述

#### 3.4.2、配置文件

**systemd 配置文件**

- kubelet.service

``` sh
[Unit]
Description=Kubernetes Kubelet Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service

[Service]
WorkingDirectory=/var/lib/kubelet
EnvironmentFile=-/etc/kubernetes/kubelet
ExecStart=/usr/bin/kubelet \
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

- kube-proxy.service

``` sh
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target

[Service]
EnvironmentFile=-/etc/kubernetes/proxy
ExecStart=/usr/bin/kube-proxy \
	    $KUBE_LOGTOSTDERR \
	    $KUBE_LOG_LEVEL \
	    $KUBE_MASTER \
	    $KUBE_PROXY_ARGS
Restart=on-failure
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
```

**核心配置文件**

- kubelet

``` sh
###
# kubernetes kubelet (minion) config

# The address for the info server to serve on (set to 0.0.0.0 or "" for all interfaces)
KUBELET_ADDRESS="--node-ip=192.168.1.54"

# The port for the info server to serve on
# KUBELET_PORT="--port=10250"

# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname-override=docker4.node"

# location of the api-server
# KUBELET_API_SERVER=""

# Add your own!
KUBELET_ARGS="  --address=0.0.0.0 \
                --allow-privileged \
                --anonymous-auth=false \
                --authorization-mode=Webhook \
                --bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
                --client-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                --network-plugin=cni \
                --cgroup-driver=cgroupfs \
                --cert-dir=/etc/kubernetes/ssl \
                --cluster-dns=10.254.0.2 \
                --cluster-domain=cluster.local \
                --cni-conf-dir=/etc/cni/net.d \
                --eviction-soft=imagefs.available<15%,memory.available<512Mi,nodefs.available<15%,nodefs.inodesFree<10% \
                --eviction-soft-grace-period=imagefs.available=3m,memory.available=1m,nodefs.available=3m,nodefs.inodesFree=1m \
                --eviction-hard=imagefs.available<10%,memory.available<256Mi,nodefs.available<10%,nodefs.inodesFree<5% \
                --eviction-max-pod-grace-period=30 \
                --image-gc-high-threshold=80 \
                --image-gc-low-threshold=70 \
                --image-pull-progress-deadline=30s \
                --kube-reserved=cpu=500m,memory=512Mi,ephemeral-storage=1Gi \
                --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
                --max-pods=100 \
                --minimum-image-ttl-duration=720h0m0s \
                --node-labels=node.kubernetes.io/k8s-node=true \
                --pod-infra-container-image=gcr.azk8s.cn/google_containers/pause-amd64:3.1 \
                --port=10250 \
                --read-only-port=0 \
                --rotate-certificates \
                --rotate-server-certificates \
                --resolv-conf=/run/systemd/resolve/resolv.conf \
                --system-reserved=cpu=500m,memory=512Mi,ephemeral-storage=1Gi \
                --fail-swap-on=false \
                --v=2"
```

**当 kubelet 组件设置了 `--rotate-certificates`，`--rotate-server-certificates` 后会自动更新其使用的相关证书，同时指定 `--authorization-mode=Webhook` 后 `10250` 端口 RBAC 授权将会委托给 apiserver**

- proxy

``` sh
###
# kubernetes proxy config
# default config should be adequate
# Add your own!
KUBE_PROXY_ARGS="   --bind-address=0.0.0.0 \
                    --cleanup-ipvs=true \
                    --cluster-cidr=10.254.0.0/16 \
                    --hostname-override=docker4.node \
                    --healthz-bind-address=0.0.0.0 \
                    --healthz-port=10256 \
                    --masquerade-all=true \
                    --proxy-mode=ipvs \
                    --ipvs-min-sync-period=5s \
                    --ipvs-sync-period=5s \
                    --ipvs-scheduler=wrr \
                    --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \
                    --logtostderr=true \
                    --v=2"
```

由于 `kubelet` 组件是采用 TLS Bootstrap 启动，所以需要预先创建相关配置

``` sh
# 创建用于 tls bootstrap 的 token secret
kubectl create -f bootstrap.secret.yaml

# 为了能让 kubelet 实现自动更新证书，需要配置相关 clusterrolebinding

# 允许 kubelet tls bootstrap 创建 csr 请求
kubectl create clusterrolebinding create-csrs-for-bootstrapping \
    --clusterrole=system:node-bootstrapper \
    --group=system:bootstrappers

# 自动批准 system:bootstrappers 组用户 TLS bootstrapping 首次申请证书的 CSR 请求
kubectl create clusterrolebinding auto-approve-csrs-for-group \
    --clusterrole=system:certificates.k8s.io:certificatesigningrequests:nodeclient \
    --group=system:bootstrappers

# 自动批准 system:nodes 组用户更新 kubelet 自身与 apiserver 通讯证书的 CSR 请求
kubectl create clusterrolebinding auto-approve-renewals-for-nodes \
    --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeclient \
    --group=system:nodes

# 在 kubelet server 开启 api 认证的情况下，apiserver 反向访问 kubelet 10250 需要此授权(eg: kubectl logs)
kubectl create clusterrolebinding system:kubelet-api-admin \
    --clusterrole=system:kubelet-api-admin \
    --user=system:kubelet-api-admin
```

#### 3.4.3、Nginx 代理

为了保证 apiserver 的 HA，需要在每个 node 上部署 nginx 来反向代理(tcp)所有 apiserver；然后 kubelet、kube-proxy 组件连接本地 `127.0.0.1:6443` 访问 apiserver，以确保任何 master 挂掉以后 node 都不会受到影响

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
        server 192.168.1.51:6443;
        server 192.168.1.52:6443;
        server 192.168.1.53:6443;
    }

    server {
        listen        0.0.0.0:6443;
        proxy_pass    kube_apiserver;
        proxy_timeout 10m;
        proxy_connect_timeout 1s;
    }
}
```

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
                              nginx:1.14.2-alpine
ExecStartPre=-/usr/bin/docker rm -f nginx-proxy
ExecStop=/usr/bin/docker stop nginx-proxy
Restart=always
RestartSec=15s
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
```

然后在每个 node 上先启动 nginx-proxy，接着启动 kubelet 与 kube-proxy 即可(master 上的 kubelet、kube-proxy 只需要修改 ip 和 node name)

#### 3.4.4、kubelet server 证书

**注意: 新版本 kubelet server 的证书自动签发已经被关闭(看 issue 好像是由于安全原因)，所以对于 kubelet server 的证书仍需要手动签署**

``` sh
docker1.node ➜  ~ kubectl get csr
NAME                                                   AGE   REQUESTOR                  CONDITION
csr-99l77                                              10s   system:node:docker4.node   Pending
node-csr-aGwaNKorMc0MZBYOuJsJGCB8Bg8ds97rmE3oKBTV-_E   11s   system:bootstrap:5d820b    Approved,Issued
docker1.node ➜  ~ kubectl certificate approve csr-99l77
certificatesigningrequest.certificates.k8s.io/csr-99l77 approved
```

### 3.5、部署 Calico

当 node 全部启动后，由于网络组件(CNI)未安装会显示为 NotReady 状态；下面将部署 Calico 作为网络组件，完成跨节点网络通讯；具体安装文档可以参考 [Installing with the etcd datastore](https://docs.projectcalico.org/v3.6/getting-started/kubernetes/installation/calico#installing-with-the-etcd-datastore)

以下为 calico 的配置文件

- calico.yaml

``` yaml
---
# Source: calico/templates/calico-etcd-secrets.yaml
# The following contains k8s Secrets for use with a TLS enabled etcd cluster.
# For information on populating Secrets, see http://kubernetes.io/docs/user-guide/secrets/
apiVersion: v1
kind: Secret
type: Opaque
metadata:
  name: calico-etcd-secrets
  namespace: kube-system
data:
  # Populate the following with etcd TLS configuration if desired, but leave blank if
  # not using TLS for etcd.
  # The keys below should be uncommented and the values populated with the base64
  # encoded contents of each file that would be associated with the TLS data.
  # Example command for encoding a file contents: cat <file> | base64 -w 0
  etcd-key: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFb3dJQkFBS0NBUUVBdGtOVlV5QWtOOWxDKy9EbzlCRkt0em5IZlFJKzJMK2crclkwLzNoOExJTEFoWUtXCm1XdVNNQUFjbyt4clVtaTFlUGIzcmRKR0p1NEhmRXFmalYvakhvN0haOGxteXd0S29Ed254aU9jZDRlRXltcXEKTEFVYzZ5RWU4dXFGZ2pLVHE4SjV2Z1F1cGp0ZlZnZXRPdVVsWWtWbUNKMWtpUW0yVk5WRnRWZ0Fqck1xSy9POApJTXN6RWRYU3BDc1Zwb0kzaUpoVHJSRng4ZzRXc2hwNG1XMzhMWDVJYVVoMWZaSGVMWm1sRURpclBWMGRTNmFWCmJscUk2aUFwanVBc3hYWjFlVTdmOVZWK01PVmNVc3A4cDAxNmJzS3R6VTJGSnB6ZlM3c1BlbGpKZGgzZmVOdk8KRVl1aDlsU0c1VGNKUHBuTTZ0R0ppaHpEWCt4dnNGa3d5MVJSVlFJREFRQUJBb0lCQUYwRXVqd2xVRGFzakJJVwpubDFKb2U4bTd0ZXUyTEk0QW9sUmluVERZZVE1aXRYWWt0R1Q0OVRaaWNSak9WYWlsOU0zZjZwWGdYUUcwUTB1CjdJVHpaZTlIZ1I5SDIwMU80dlFxSDBaeEVENjBqQ0hlRkNGSkxyd1ZlRDBUVWJYajZCZWx0Z296Q2pmT1gxYUIKcm5nN1VEdjZIUnZTYitlOGJEQ1pjKzBjRDVURG4vUWV0R1dtUmpJZ1FhMmlUT2MzSzFiaHo2RTl5Nk9qWkFTMQpiai9NL1dOd20yNHRxQTJEeWdjcGVmUGFnTWtFNm9uYXBFVHhZdi83QmNqcUhtdVd6WE1wMzd6VGpPckwxVDdmClhrbHdFMUYrMDRhRDR6dDZycEdmN0lqSUdvRkEvT2ZrRGZiYkRjN2NsaDJ1SkNMTVE5MGpuSkxMTGRSV3dQRW4KMkkyY3IvVUNnWUVBN3BjT29VV3RwdDJjWGIzSnl3Tkh4aXl1bEc4V1JENjBlQ1MrUXFnQUZndU5JWFJlMEREUwovSWY0M1BhaVB3TjhBS216ZTRKbGsxM3Rnd29qdi9RWVFVblJzZi9PbnpUUlFoWVJXT2lxSE5lSmFvOUxFU0VDClcxNXNmUjhnYzd0dFdPZ0loZkhudmdCR0QvYmUzS1NWVjdUY0lndVVjV3RzeHhLdjZ4LzJNdHNDZ1lFQXc1QVIKWk9HNUp4UGVNV3FVRUR3QjJuQmt6WEtGblpNSEJXV2FOeHpEaTI0NmZEVWM2T1hSTTJJanh2cmVkc3JKQjBXMwovelNDeFdUbkRmL3RJY1lKMjRuTmNsMUNDS2hTNVE5bVZxanZ3dE1SaEF1Uk5VSFJSVjZLNS91V1hHQzAzekR3CkEvMUFSd3lZSHNHTlJVOFRNNnpNRFcxL0x5djZNZ2pnOFBIamk0OENnWUVBa3JwelZOcjFJRm5KZ0J6bnJPSW4Ka2NpSTFPQThZVnZ1d0xSWURjWWp4MnJ6TUUvUXYxaEhhT1oyTmUyM2VlazZxVzJ6NDVFZHhyTk5EZmwrWXQ1Swp6RndKaWQ0M3c5RkhuOHpTZmtzWDB3VDZqWDN5UEdhQWZKQmxSODJNdDUvY2I0RERQUnkzMkRGeTVQNTlzRlBIClJGa0Z5Q28yOEVtUWJCMGg4d2VFOFdFQ2dZQm1IeUptS3RWVUNiVDYyeXZzZWxtQlp6WE1ieVJGRDlVWHhXSE4KcTlDVlMvOXdndy9Rc3NvVzZnWEN6NWhDTWt6ZDVsTmFDbUxMajVCMHFCTjlrbnZ0VDcyZ0hnRHdvbTEvUGhaego1STRuajY3UzVITjBleVU3ODAzWUxISHRWWGErSWtFRDVFaWZrWDBTZW9JNkVqdjF2U05sVTZ1WngzNUVpSXhtClpmb3NFd0tCZ0dQMmpsK0lPcFV5Y2NEL25EbUJWa05CWHoydWhncU8yYjE4d0hSOGdiSXoyVTRBZnpreXVkWUcKZzQvRjJZZVdCSEdNeTc5N0I2c0hjQTdQUWNNdUFuRk11MG9UNkMvanpDSHpoK2VaaS8wdHJRTHJGeWFFaGVuWgpnazduUTdHNHhROWZLZmVTeFcyUlNNUUR0MTZULzNOTitTOEZCTjJmZEliY3V4QWs0WjVHCi0tLS0tRU5EIFJTQSBQUklWQVRFIEtFWS0tLS0tCg==
  etcd-cert: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUZFekNDQXZ1Z0F3SUJBZ0lVRGJqcTdVc2ViY2toZXRZb1RPNnRsc1N1c1k0d0RRWUpLb1pJaHZjTkFRRU4KQlFBd2J6RUxNQWtHQTFVRUJoTUNRMDR4RURBT0JnTlZCQWdUQjBKbGFXcHBibWN4RURBT0JnTlZCQWNUQjBKbAphV3BwYm1jeERUQUxCZ05WQkFvVEJHVjBZMlF4RmpBVUJnTlZCQXNURFdWMFkyUWdVMlZqZFhKcGRIa3hGVEFUCkJnTlZCQU1UREdWMFkyUXRjbTl2ZEMxallUQWVGdzB4T1RBek1UWXdNelV4TURCYUZ3MHlPVEF6TVRNd016VXgKTURCYU1HY3hDekFKQmdOVkJBWVRBa05PTVJBd0RnWURWUVFJRXdkQ1pXbHFhVzVuTVJBd0RnWURWUVFIRXdkQwpaV2xxYVc1bk1RMHdDd1lEVlFRS0V3UmxkR05rTVJZd0ZBWURWUVFMRXcxbGRHTmtJRk5sWTNWeWFYUjVNUTB3CkN3WURWUVFERXdSbGRHTmtNSUlCSWpBTkJna3Foa2lHOXcwQkFRRUZBQU9DQVE4QU1JSUJDZ0tDQVFFQXRrTlYKVXlBa045bEMrL0RvOUJGS3R6bkhmUUkrMkwrZytyWTAvM2g4TElMQWhZS1dtV3VTTUFBY28reHJVbWkxZVBiMwpyZEpHSnU0SGZFcWZqVi9qSG83SFo4bG15d3RLb0R3bnhpT2NkNGVFeW1xcUxBVWM2eUVlOHVxRmdqS1RxOEo1CnZnUXVwanRmVmdldE91VWxZa1ZtQ0oxa2lRbTJWTlZGdFZnQWpyTXFLL084SU1zekVkWFNwQ3NWcG9JM2lKaFQKclJGeDhnNFdzaHA0bVczOExYNUlhVWgxZlpIZUxabWxFRGlyUFYwZFM2YVZibHFJNmlBcGp1QXN4WFoxZVU3Zgo5VlYrTU9WY1VzcDhwMDE2YnNLdHpVMkZKcHpmUzdzUGVsakpkaDNmZU52T0VZdWg5bFNHNVRjSlBwbk02dEdKCmloekRYK3h2c0Zrd3kxUlJWUUlEQVFBQm80R3VNSUdyTUE0R0ExVWREd0VCL3dRRUF3SUZvREFkQmdOVkhTVUUKRmpBVUJnZ3JCZ0VGQlFjREFRWUlLd1lCQlFVSEF3SXdEQVlEVlIwVEFRSC9CQUl3QURBZEJnTlZIUTRFRmdRVQpFKzVsWWN1LzhieHJ2WjNvUnRSMmEvOVBJRkF3SHdZRFZSMGpCQmd3Rm9BVTJaVWM3R2hGaG1PQXhzRlZ3VEEyCm5lZFJIdmN3TEFZRFZSMFJCQ1V3STRJSmJHOWpZV3hvYjNOMGh3Ui9BQUFCaHdUQXFBRXpod1RBcUFFMGh3VEEKcUFFMU1BMEdDU3FHU0liM0RRRUJEUVVBQTRJQ0FRQUx3Vkc2QW93cklwZzQvYlRwWndWL0pBUWNLSnJGdm52VApabDVDdzIzNDI4UzJLLzIwaXphaStEWUR1SXIwQ0ZCa2xGOXVsK05ROXZMZ1lqcE0rOTNOY3I0dXhUTVZsRUdZCjloc3NyT1FZZVBGUHhBS1k3RGd0K2RWUGwrWlg4MXNWRzJkU3ZBbm9Kd3dEVWt5U0VUY0g5NkszSlNKS2dXZGsKaTYxN21GYnMrTlcxdngrL0JNN2pVU3ZRUzhRb3JGQVE3SlcwYzZ3R2V4RFEzZExvTXJuR3Vocjd0V0E0WjhwawpPaE12cWdhWUZYSThNUm4yemlLV0R6QXNsa0hGd1RZdWhCNURMSEt0RUVwcWhxbGh1RThwTkZMaVVSV2xQWWhlCmpDNnVKZ0hBZDltcSswd2pyTmxqKzlWaDJoZUJWNldXZEROVTZaR2tpR003RW9YbDM1OWdUTzJPUkNLUk5vZ0YKRVplR25HcjJQNDhKbnZjTnFmZzNPdUtYd24wRDVYYllSWjFuYnR5WG9mMFByUUhEU21wUFVPMWNiZUJjSWVtcQpEVWozK0MrRzBRS1FLQlZDTXJzNXJIVlVWVkJZZzk5ZW1sRE1zUE5TZm9JWDQwTVFCeTdKMnpxRVV5M0sxcGlaCkhwT0lZT1RrWDRhczhqcGYxMnkxSXoxRVZydE1xek83d294VmMwdHRZYWN5NzUrVzZuS1hlWjBaand5aTVYSzUKZGduSVhmZW51RUNlWFNDdWZCSmUxVklzaXVWZ3cyRjlUNk5zRDhnQ3A5SlhTamJ1SXpiM3ArNU9uZzM2ZnBRdQpXZVBCY0dQVXE5cGEwZUtOUGJXNjlDUHdtUTQ2cjg0T3hTTURHWC9CMElqNUtNUnZUMmhPUXBqTVpSblc5OUxFCjRMbUJuUTg1Wmc9PQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
  etcd-ca: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUZyakNDQTVhZ0F3SUJBZ0lVWXVIKzIxYlNaU2hncVYxWkx3a2o4RmpZbUl3d0RRWUpLb1pJaHZjTkFRRU4KQlFBd2J6RUxNQWtHQTFVRUJoTUNRMDR4RURBT0JnTlZCQWdUQjBKbGFXcHBibWN4RURBT0JnTlZCQWNUQjBKbAphV3BwYm1jeERUQUxCZ05WQkFvVEJHVjBZMlF4RmpBVUJnTlZCQXNURFdWMFkyUWdVMlZqZFhKcGRIa3hGVEFUCkJnTlZCQU1UREdWMFkyUXRjbTl2ZEMxallUQWVGdzB4T1RBek1UWXdNelV4TURCYUZ3MHlPVEF6TVRNd016VXgKTURCYU1HOHhDekFKQmdOVkJBWVRBa05PTVJBd0RnWURWUVFJRXdkQ1pXbHFhVzVuTVJBd0RnWURWUVFIRXdkQwpaV2xxYVc1bk1RMHdDd1lEVlFRS0V3UmxkR05rTVJZd0ZBWURWUVFMRXcxbGRHTmtJRk5sWTNWeWFYUjVNUlV3CkV3WURWUVFERXd4bGRHTmtMWEp2YjNRdFkyRXdnZ0lpTUEwR0NTcUdTSWIzRFFFQkFRVUFBNElDRHdBd2dnSUsKQW9JQ0FRRGFLK0s4WStqZkdOY2pOeUloeUhXSE5adWxVZzVKZFpOVU9GOHFXbXJMa0NuY2ZWdVF3dmI4cDFwLwpSSjBFOWo0OFBhZ1RJT3U2TU81R24zejFrZGpHRk9jOVZwMlZjYWJEQzJLWWJvRzdVQ0RmTWkzR1MzUnhUejVkCnh0MG1Ya2liVkMvc01NU2RrRm1mU2FCSXBoKzAyTnMwZURyMzNtUWxTdURlTWozNHJaTkVwMzRnUUk0eElTejAKbXhXR0dWNzcwUE9ScVgrZUthTEpiclp3anFFcnpHMEtEVUlBM0ZuTFdRMnp4b0VwN3JZby9LaGRiOHdETE1kbQp6VXNOZHI0T1F4MFBVRXA4akRUU2lFODkydDQ4KytsOHJ0MW4vTHFRc1FhVncrQlQrMTRvRHdIVkFaRXZ2ZnMwCmZkZ0QvU2RINGJRdHNhT21BdFByQldseU5aMUxIZkR2djMraXFzNk83UXpWUTFCK1c5cFRxdUZ2YUxWN3R1S3UKSXNlUFlseFdjV2E2M0hGbFkxVVJ6M0owaGtrZEZ1dkhUc0dhZDVpaWVrb0dUcFdTN2dVdCtTeWVJT2FhMldHLwp4Y1NiUWE0Y2xiZThuUHV2c1ZFVDhqZ0d0NGVLT25yRVJId0hMb2VleEpsSjdUdnhHNHpOTHZsc2FOL29iRzFDClUzMXczZ2d1SXpzRk5yallsUFdSZ0hSdXdPTlE5anlkM2dqVmNYUFdHTFJISUdYbjNhUDluT3A0OE9WWDhzbXoKOGIwS0V4UVpEQWUyS0tjWEg5a1ZiUFJQSWlLeGpXelV5aDMzQlRNejlPczZHcWM0Zk05c1hxbGRhVzBGd3g4MQpJaklScWx5a3VOSXNDWGhMUzhlNmVtdUNYMTVDZGNKb0ZmdXRuTENvV1B4Umg5OEF4UUlEQVFBQm8wSXdRREFPCkJnTlZIUThCQWY4RUJBTUNBUVl3RHdZRFZSMFRBUUgvQkFVd0F3RUIvekFkQmdOVkhRNEVGZ1FVMlpVYzdHaEYKaG1PQXhzRlZ3VEEybmVkUkh2Y3dEUVlKS29aSWh2Y05BUUVOQlFBRGdnSUJBSjh3bVNJMVBsQm8zcE1RWC9DOQpRS1RrR0xvVUhGdWprdFoxM1FYeXQ1LzFSeVB2WG1lLy90N3FHR2I5RmJZSm9BYTRTd3JSZkYzZmh3UDZaS0FnCnNYSEliR2gwc014UTdqVmQwMUNMWkoxQmZFNGZtTVlaQUlEWGpTcTNqbHJXZWcxL2hWTFN2dXRuUEFWSXc1SWwKZUdXRTMyOVJ2b2d2dXV6dUsxY2xwZFpIL2p3UlZjUUFUK0xvT2xFZ3Rkd293c0xpaWx3WE95eEZLZDd1UDk3bgozTFZUekFNN3Flell4SUVMQVlUUUN5eTdpeEIxNXlJV1UrUWhreUFtWXJoNEN6VUNNUjQreDlpaGZ6UnlOQkxLCmRBRTdwcjdyUEM4WFQ0YWh2SkJCZTg1THViTVdVRmprcEF5cklQODYyYkFCOCtKSXNFdXNZVGdQakUrMGhteTkKT0NIU2x4Q25GQVdPUXcwQ05Kb3AxWGpHU0RZOXlXL1NNWS83T3B0QlBhT3VWTzVwZTg3VmVXRFFtYmlpdnc3MQo4cFhDQnN6ZWNsdjJZKzdscTRnL0FaQkViVXRvLzV4UXJCbmZGKy9hZFFOQzY4aG4yYzZWa3czYTVDR0ZMN0p2CjhWdFNmeFEzZnFUci9TdzlJbkVKVWpuc0Y3R0xINzZMWXZIU05WeldhMkhiVFNlTnQ0RUlpdlEwb2d0b2hzY0kKSHlrZlpRQ3Z6ZnBSZi9TODFiRDNnU29jQ3NzR2crdVpVU0FMdVhBRDE4RkRXNzg2LzRCckcrMzVLOVBLNktUZwpoWGN4WmRHd3V1RWx0aTRBNWx4OHNrZExPSkZ6TUJPWFJNU2Jsc0dna3pGK2JNRkMrMHV3WW1WK0VTRUdwdy9NCm93WUN1dHh2a3ltL2NOcEk1bjFhanpEcQotLS0tLUVORCBDRVJUSUZJQ0FURS0tLS0tCg==
---
# Source: calico/templates/calico-config.yaml
# This ConfigMap is used to configure a self-hosted Calico installation.
kind: ConfigMap
apiVersion: v1
metadata:
  name: calico-config
  namespace: kube-system
data:
  # Configure this with the location of your etcd cluster.
  etcd_endpoints: "https://192.168.1.51:2379,https://192.168.1.52:2379,https://192.168.1.53:2379"

  # If you're using TLS enabled etcd uncomment the following.
  # You must also populate the Secret below with these files.
  etcd_ca: "/calico-secrets/etcd-ca"
  etcd_cert: "/calico-secrets/etcd-cert"
  etcd_key: "/calico-secrets/etcd-key"
  # Typha is disabled.
  typha_service_name: "none"
  # Configure the Calico backend to use.
  calico_backend: "bird"

  # Configure the MTU to use
  veth_mtu: "1440"

  # The CNI network configuration to install on each node.  The special
  # values in this config will be automatically populated.
  cni_network_config: |-
    {
      "name": "k8s-pod-network",
      "cniVersion": "0.3.0",
      "plugins": [
        {
          "type": "calico",
          "log_level": "info",
          "etcd_endpoints": "__ETCD_ENDPOINTS__",
          "etcd_key_file": "__ETCD_KEY_FILE__",
          "etcd_cert_file": "__ETCD_CERT_FILE__",
          "etcd_ca_cert_file": "__ETCD_CA_CERT_FILE__",
          "mtu": __CNI_MTU__,
          "ipam": {
              "type": "calico-ipam"
          },
          "policy": {
              "type": "k8s"
          },
          "kubernetes": {
              "kubeconfig": "__KUBECONFIG_FILEPATH__"
          }
        },
        {
          "type": "portmap",
          "snat": true,
          "capabilities": {"portMappings": true}
        }
      ]
    }

---
# Source: calico/templates/rbac.yaml

# Include a clusterrole for the kube-controllers component,
# and bind it to the calico-kube-controllers serviceaccount.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: calico-kube-controllers
rules:
  # Pods are monitored for changing labels.
  # The node controller monitors Kubernetes nodes.
  # Namespace and serviceaccount labels are used for policy.
  - apiGroups: [""]
    resources:
      - pods
      - nodes
      - namespaces
      - serviceaccounts
    verbs:
      - watch
      - list
  # Watch for changes to Kubernetes NetworkPolicies.
  - apiGroups: ["networking.k8s.io"]
    resources:
      - networkpolicies
    verbs:
      - watch
      - list
---
kind: ClusterRoleBinding
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: calico-kube-controllers
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: calico-kube-controllers
subjects:
- kind: ServiceAccount
  name: calico-kube-controllers
  namespace: kube-system
---
# Include a clusterrole for the calico-node DaemonSet,
# and bind it to the calico-node serviceaccount.
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1beta1
metadata:
  name: calico-node
rules:
  # The CNI plugin needs to get pods, nodes, and namespaces.
  - apiGroups: [""]
    resources:
      - pods
      - nodes
      - namespaces
    verbs:
      - get
  - apiGroups: [""]
    resources:
      - endpoints
      - services
    verbs:
      # Used to discover service IPs for advertisement.
      - watch
      - list
  - apiGroups: [""]
    resources:
      - nodes/status
    verbs:
      # Needed for clearing NodeNetworkUnavailable flag.
      - patch
---
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: calico-node
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: calico-node
subjects:
- kind: ServiceAccount
  name: calico-node
  namespace: kube-system
---

---
# Source: calico/templates/calico-node.yaml
# This manifest installs the calico/node container, as well
# as the Calico CNI plugins and network config on
# each master and worker node in a Kubernetes cluster.
kind: DaemonSet
apiVersion: extensions/v1beta1
metadata:
  name: calico-node
  namespace: kube-system
  labels:
    k8s-app: calico-node
spec:
  selector:
    matchLabels:
      k8s-app: calico-node
  updateStrategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        k8s-app: calico-node
      annotations:
        # This, along with the CriticalAddonsOnly toleration below,
        # marks the pod as a critical add-on, ensuring it gets
        # priority scheduling and that its resources are reserved
        # if it ever gets evicted.
        scheduler.alpha.kubernetes.io/critical-pod: ''
    spec:
      nodeSelector:
        beta.kubernetes.io/os: linux
      hostNetwork: true
      tolerations:
        # Make sure calico-node gets scheduled on all nodes.
        - effect: NoSchedule
          operator: Exists
        # Mark the pod as a critical add-on for rescheduling.
        - key: CriticalAddonsOnly
          operator: Exists
        - effect: NoExecute
          operator: Exists
      serviceAccountName: calico-node
      # Minimize downtime during a rolling upgrade or deletion; tell Kubernetes to do a "force
      # deletion": https://kubernetes.io/docs/concepts/workloads/pods/pod/#termination-of-pods.
      terminationGracePeriodSeconds: 0
      initContainers:
        # This container installs the Calico CNI binaries
        # and CNI network config file on each node.
        - name: install-cni
          image: calico/cni:v3.6.0
          command: ["/install-cni.sh"]
          env:
            # Name of the CNI config file to create.
            - name: CNI_CONF_NAME
              value: "10-calico.conflist"
            # The CNI network config to install on each node.
            - name: CNI_NETWORK_CONFIG
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: cni_network_config
            # The location of the Calico etcd cluster.
            - name: ETCD_ENDPOINTS
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_endpoints
            # CNI MTU Config variable
            - name: CNI_MTU
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: veth_mtu
            # Prevents the container from sleeping forever.
            - name: SLEEP
              value: "false"
          volumeMounts:
            - mountPath: /host/opt/cni/bin
              name: cni-bin-dir
            - mountPath: /host/etc/cni/net.d
              name: cni-net-dir
            - mountPath: /calico-secrets
              name: etcd-certs
      containers:
        # Runs calico/node container on each Kubernetes node.  This
        # container programs network policy and routes on each
        # host.
        - name: calico-node
          image: calico/node:v3.6.0
          env:
            # The location of the Calico etcd cluster.
            - name: ETCD_ENDPOINTS
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_endpoints
            # Location of the CA certificate for etcd.
            - name: ETCD_CA_CERT_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_ca
            # Location of the client key for etcd.
            - name: ETCD_KEY_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_key
            # Location of the client certificate for etcd.
            - name: ETCD_CERT_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_cert
            # Set noderef for node controller.
            - name: CALICO_K8S_NODE_REF
              valueFrom:
                fieldRef:
                  fieldPath: spec.nodeName
            # Choose the backend to use.
            - name: CALICO_NETWORKING_BACKEND
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: calico_backend
            # Cluster type to identify the deployment type
            - name: CLUSTER_TYPE
              value: "k8s,bgp"
            # Auto-detect the BGP IP address.
            - name: IP
              value: "autodetect"
            # Enable IPIP
            - name: CALICO_IPV4POOL_IPIP
              value: "Always"
            # Set MTU for tunnel device used if ipip is enabled
            - name: FELIX_IPINIPMTU
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: veth_mtu
            # The default IPv4 pool to create on startup if none exists. Pod IPs will be
            # chosen from this range. Changing this value after installation will have
            # no effect. This should fall within `--cluster-cidr`.
            - name: CALICO_IPV4POOL_CIDR
              value: "10.20.0.0/16"
            # Disable file logging so `kubectl logs` works.
            - name: CALICO_DISABLE_FILE_LOGGING
              value: "true"
            # Set Felix endpoint to host default action to ACCEPT.
            - name: FELIX_DEFAULTENDPOINTTOHOSTACTION
              value: "ACCEPT"
            # Disable IPv6 on Kubernetes.
            - name: FELIX_IPV6SUPPORT
              value: "false"
            # Set Felix logging to "info"
            - name: FELIX_LOGSEVERITYSCREEN
              value: "info"
            - name: FELIX_HEALTHENABLED
              value: "true"
            - name: IP_AUTODETECTION_METHOD
              value: can-reach=192.168.1.51
          securityContext:
            privileged: true
          resources:
            requests:
              cpu: 250m
          livenessProbe:
            httpGet:
              path: /liveness
              port: 9099
              host: localhost
            periodSeconds: 10
            initialDelaySeconds: 10
            failureThreshold: 6
          readinessProbe:
            exec:
              command:
              - /bin/calico-node
              - -bird-ready
              - -felix-ready
            periodSeconds: 10
          volumeMounts:
            - mountPath: /lib/modules
              name: lib-modules
              readOnly: true
            - mountPath: /run/xtables.lock
              name: xtables-lock
              readOnly: false
            - mountPath: /var/run/calico
              name: var-run-calico
              readOnly: false
            - mountPath: /var/lib/calico
              name: var-lib-calico
              readOnly: false
            - mountPath: /calico-secrets
              name: etcd-certs
      volumes:
        # Used by calico/node.
        - name: lib-modules
          hostPath:
            path: /lib/modules
        - name: var-run-calico
          hostPath:
            path: /var/run/calico
        - name: var-lib-calico
          hostPath:
            path: /var/lib/calico
        - name: xtables-lock
          hostPath:
            path: /run/xtables.lock
            type: FileOrCreate
        # Used to install CNI.
        - name: cni-bin-dir
          hostPath:
            path: /opt/cni/bin
        - name: cni-net-dir
          hostPath:
            path: /etc/cni/net.d
        # Mount in the etcd TLS secrets with mode 400.
        # See https://kubernetes.io/docs/concepts/configuration/secret/
        - name: etcd-certs
          secret:
            secretName: calico-etcd-secrets
            defaultMode: 0400
---

apiVersion: v1
kind: ServiceAccount
metadata:
  name: calico-node
  namespace: kube-system

---
# Source: calico/templates/calico-kube-controllers.yaml
# This manifest deploys the Calico Kubernetes controllers.
# See https://github.com/projectcalico/kube-controllers
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: calico-kube-controllers
  namespace: kube-system
  labels:
    k8s-app: calico-kube-controllers
  annotations:
    scheduler.alpha.kubernetes.io/critical-pod: ''
spec:
  # The controllers can only have a single active instance.
  replicas: 1
  strategy:
    type: Recreate
  template:
    metadata:
      name: calico-kube-controllers
      namespace: kube-system
      labels:
        k8s-app: calico-kube-controllers
    spec:
      nodeSelector:
        beta.kubernetes.io/os: linux
      # The controllers must run in the host network namespace so that
      # it isn't governed by policy that would prevent it from working.
      hostNetwork: true
      tolerations:
        # Mark the pod as a critical add-on for rescheduling.
        - key: CriticalAddonsOnly
          operator: Exists
        - key: node-role.kubernetes.io/master
          effect: NoSchedule
      serviceAccountName: calico-kube-controllers
      containers:
        - name: calico-kube-controllers
          image: calico/kube-controllers:v3.6.0
          env:
            # The location of the Calico etcd cluster.
            - name: ETCD_ENDPOINTS
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_endpoints
            # Location of the CA certificate for etcd.
            - name: ETCD_CA_CERT_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_ca
            # Location of the client key for etcd.
            - name: ETCD_KEY_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_key
            # Location of the client certificate for etcd.
            - name: ETCD_CERT_FILE
              valueFrom:
                configMapKeyRef:
                  name: calico-config
                  key: etcd_cert
            # Choose which controllers to run.
            - name: ENABLED_CONTROLLERS
              value: policy,namespace,serviceaccount,workloadendpoint,node
          volumeMounts:
            # Mount in the etcd TLS secrets.
            - mountPath: /calico-secrets
              name: etcd-certs
          readinessProbe:
            exec:
              command:
              - /usr/bin/check-status
              - -r
      volumes:
        # Mount in the etcd TLS secrets with mode 400.
        # See https://kubernetes.io/docs/concepts/configuration/secret/
        - name: etcd-certs
          secret:
            secretName: calico-etcd-secrets
            defaultMode: 0400

---

apiVersion: v1
kind: ServiceAccount
metadata:
  name: calico-kube-controllers
  namespace: kube-system
```

**需要注意的是我们添加了 `IP_AUTODETECTION_METHOD` 变量，这个变量会设置 calcio 获取 node ip 的方式；默认情况下采用 [first-found](https://docs.projectcalico.org/v3.6/reference/node/configuration#ip-autodetection-methods) 方式获取，即获取第一个有效网卡的 IP 作为 node ip；在某些多网卡机器上可能会出现问题；这里将值设置为 `can-reach=192.168.1.51`，即使用第一个能够访问 master `192.168.1.51` 的网卡地址作为 node ip**

最后执行创建即可，创建成功后如下所示

``` sh
docker1.node ➜  ~ kubectl get pod -o wide -n kube-system
NAME                                      READY   STATUS    RESTARTS   AGE   IP             NODE           NOMINATED NODE   READINESS GATES
calico-kube-controllers-65bc6b9f9-cn27f   1/1     Running   0          85s   192.168.1.53   docker3.node   <none>           <none>
calico-node-c5nl8                         1/1     Running   0          85s   192.168.1.53   docker3.node   <none>           <none>
calico-node-fqknv                         1/1     Running   0          85s   192.168.1.51   docker1.node   <none>           <none>
calico-node-ldfzs                         1/1     Running   0          85s   192.168.1.55   docker5.node   <none>           <none>
calico-node-ngjxc                         1/1     Running   0          85s   192.168.1.52   docker2.node   <none>           <none>
calico-node-vj8np                         1/1     Running   0          85s   192.168.1.54   docker4.node   <none>           <none>
```

此时所有 node 应当变为 Ready 状态

### 3.5、部署 DNS

其他组件全部完成后我们应当部署集群 DNS 使 service 等能够正常解析；集群 DNS 这里采用 coredns，具体安装文档参考 [coredns/deployment](https://github.com/coredns/deployment/tree/master/kubernetes)；coredns 完整配置如下

- coredns.yaml

``` yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: coredns
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
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
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
---
apiVersion: rbac.authorization.k8s.io/v1
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
        kubernetes cluster.local in-addr.arpa ip6.arpa {
          pods insecure
          upstream
          fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
---
apiVersion: apps/v1
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
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      nodeSelector:
        beta.kubernetes.io/os: linux
      containers:
      - name: coredns
        image: coredns/coredns:1.3.1
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
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
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
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
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: "CoreDNS"
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.254.0.2
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  - name: metrics
    port: 9153
    protocol: TCP
```

### 3.5、部署 DNS 自动扩容

在大规模集群的情况下，可能需要集群 DNS 自动扩容，具体文档请参考 [DNS Horizontal Autoscaler](https://github.com/kubernetes/kubernetes/tree/master/cluster/addons/dns-horizontal-autoscaler)，DNS 扩容算法可参考 [Github](https://github.com/kubernetes-incubator/cluster-proportional-autoscaler/)，如有需要请自行修改；以下为具体配置

- dns-horizontal-autoscaler.yaml

``` yaml
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
        image: gcr.azk8s.cn/google_containers/cluster-proportional-autoscaler-amd64:1.1.2-r2
        resources:
            requests:
                cpu: "20m"
                memory: "10Mi"
        command:
          - /cluster-proportional-autoscaler
          - --namespace=kube-system
          - --configmap=kube-dns-autoscaler
          # Should keep target in sync with cluster/addons/dns/kube-dns.yaml.base
          - --target=Deployment/coredns
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

## 四、其他

### 4.1、集群测试

为测试集群工作正常，我们创建一个 deployment 和一个 service，用于测试联通性和 DNS 工作是否正常；测试配置如下

- test.yaml

``` yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test
  labels:
    app: test
spec:
  replicas: 5
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      containers:
      - name: test
        image: nginx:1.14.2-alpine
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: test-service
spec:
  selector:
    app: test
  ports:
  - name: nginx
    port: 80
    nodePort: 30001
    targetPort: 80
    protocol: TCP
  type: NodePort
```

测试方式很简单，进入某一个 pod ping 其他 pod ip 确认网络是否正常，直接访问 service 名称测试 DNS 是否工作正常，这里不再演示

### 4.2、其他说明

此次搭建开启了大部分认证，限于篇幅原因没有将每个选项作用做完整解释，推荐搭建完成后仔细阅读以下 `--help` 中的描述(官方文档页面有时候更新不完整)；目前 apiserver 仍然保留了 8080 端口(因为直接使用 kubectl 方便)，但是在高安全性环境请关闭 8080 端口，因为即使绑定在 127.0.0.1 上，对于任何能够登录 master 机器的用户仍然能够不经验证操作整个集群

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
