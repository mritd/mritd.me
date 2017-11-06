---
layout: post
categories: Kubernetes
title: Kubernetes 1.8 集群搭建
date: 2017-10-09 22:48:03 +0800
description: Kubernetes 1.8 集群搭建
keywords: Kubernetes 1.8 1.8.0 HA
---

> 目前 Kubernetes 1.8.0 已经发布，1.8.0增加了很多新特性，比如 kube-proxy 组建的 ipvs 模式等，同时 RBAC 授权也做了一些调整，国庆没事干，所以试了一下；以下记录了 Kubernetes 1.8.0 的搭建过程


### 一、环境准备

目前测试为 5 台虚拟机，etcd、kubernetes 全部采用 rpm 安装，使用 systemd 来做管理，网络组件采用 calico，Master 实现了 HA；基本环境如下

|IP|组件|
|---|---|
|10.10.1.5|Master、Node、etcd|
|10.10.1.6|Master、Node、etcd|
|10.10.1.7|Master、Node、etcd|
|10.10.1.8|Node|
|10.10.1.9|Node|

**本文尽量以实际操作为主，因为写过一篇 [Kubernetes 1.7 搭建文档](https://mritd.me/2017/07/21/set-up-kubernetes-ha-cluster-by-binary/)，所以以下细节部分不在详细阐述，不懂得可以参考上一篇文章；本文所有安装工具均已打包上传到了 [百度云](https://pan.baidu.com/s/1nvwZCfv) 密码: `4zaz`，可直接下载重复搭建过程，搭建前请自行 load 好 images 目录下的相关 docker 镜像**

### 二、搭建 Etcd 集群

#### 2.1、生成 Etcd 证书

同样证书工具仍使用的是 [cfssl](https://pkg.cfssl.org/)，百度云的压缩包里已经包含了，下面直接上配置(**注意，所有证书生成只需要在任意一台主机上生成一遍即可，我这里在 Master 上操作的**)

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
    "10.10.1.5",
    "10.10.1.6",
    "10.10.1.7",
    "10.10.1.8",
    "10.10.1.9"
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

**最后生成证书**

``` sh
cfssl gencert --initca=true etcd-root-ca-csr.json | cfssljson --bare etcd-root-ca
cfssl gencert --ca etcd-root-ca.pem --ca-key etcd-root-ca-key.pem --config etcd-gencert.json etcd-csr.json | cfssljson --bare etcd
```

证书生成后截图如下

![Gen Etcd Cert](https://mritd.b0.upaiyun.com/markdown/6mn6y.jpg)


#### 2.2、搭建集群

首先分发证书及 rpm 包

``` sh
# 分发 rpm
for IP in `seq 5 7`; do
    scp etcd-3.2.7-1.fc28.x86_64.rpm root@10.10.1.$IP:~
    ssh root@10.10.1.$IP rpm -ivh etcd-3.2.7-1.fc28.x86_64.rpm
done

# 分发证书
for IP in `seq 5 7`;do
    ssh root@10.10.1.$IP mkdir /etc/etcd/ssl
    scp *.pem root@10.10.1.$IP:/etc/etcd/ssl
    ssh root@10.10.1.$IP chown -R etcd:etcd /etc/etcd/ssl
    ssh root@10.10.1.$IP chmod -R 644 /etc/etcd/ssl/*
    ssh root@10.10.1.$IP chmod 755 /etc/etcd/ssl
done
```

```sh
# 修改 etcd 数据目录权限组
for IP in `seq 5 7`;do
    ssh root@10.10.1.$IP chown -R etcd:etcd /var/lib/etcd
done
```

**然后修改配置如下(其他两个节点类似，只需要改监听地址和 Etcd Name 即可)**

``` sh
docker1.node ➜  ~ cat /etc/etcd/etcd.conf

# [member]
ETCD_NAME=etcd1
ETCD_DATA_DIR="/var/lib/etcd/etcd1.etcd"
ETCD_WAL_DIR="/var/lib/etcd/wal"
ETCD_SNAPSHOT_COUNT="100"
ETCD_HEARTBEAT_INTERVAL="100"
ETCD_ELECTION_TIMEOUT="1000"
ETCD_LISTEN_PEER_URLS="https://10.10.1.5:2380"
ETCD_LISTEN_CLIENT_URLS="https://10.10.1.5:2379,http://127.0.0.1:2379"
ETCD_MAX_SNAPSHOTS="5"
ETCD_MAX_WALS="5"
#ETCD_CORS=""

# [cluster]
ETCD_INITIAL_ADVERTISE_PEER_URLS="https://10.10.1.5:2380"
# if you use different ETCD_NAME (e.g. test), set ETCD_INITIAL_CLUSTER value for this name, i.e. "test=http://..."
ETCD_INITIAL_CLUSTER="etcd1=https://10.10.1.5:2380,etcd2=https://10.10.1.6:2380,etcd3=https://10.10.1.7:2380"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
ETCD_ADVERTISE_CLIENT_URLS="https://10.10.1.5:2379"
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

最后启动集群并测试如下

``` sh
systemctl daemon-reload
systemctl start etcd
systemctl enable etcd

export ETCDCTL_API=3
etcdctl --cacert=/etc/etcd/ssl/etcd-root-ca.pem --cert=/etc/etcd/ssl/etcd.pem --key=/etc/etcd/ssl/etcd-key.pem --endpoints=https://10.10.1.5:2379,https://10.10.1.6:2379,https://10.10.1.7:2379 endpoint health
```

![check etcd](https://mritd.b0.upaiyun.com/markdown/ecrgr.jpg)

### 三、搭建 Master 节点

#### 3.1、生成 Kubernetes 证书

**生成证书配置文件需要借助 kubectl，所以先要安装一下 kubernetes-client 包**

``` sh
rpm -ivh kubernetes-client-1.8.0-1.el7.centos.x86_64.rpm
```

生成证书配置如下

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

##### kubernetes-csr.json

``` json
{
    "CN": "kubernetes",
    "hosts": [
        "127.0.0.1",
        "10.254.0.1",
        "10.10.1.5",
        "10.10.1.6",
        "10.10.1.7",
        "10.10.1.8",
        "10.10.1.9",
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

最后生成证书及配置文件

``` sh
# 生成证书
cfssl gencert --initca=true k8s-root-ca-csr.json | cfssljson --bare k8s-root-ca

for targetName in kubernetes admin kube-proxy; do
    cfssl gencert --ca k8s-root-ca.pem --ca-key k8s-root-ca-key.pem --config k8s-gencert.json --profile kubernetes $targetName-csr.json | cfssljson --bare $targetName
done

# 生成配置
export KUBE_APISERVER="https://127.0.0.1:6443"
export BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
echo "Tokne: ${BOOTSTRAP_TOKEN}"

cat > token.csv <<EOF
${BOOTSTRAP_TOKEN},kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF

echo "Create kubelet bootstrapping kubeconfig..."
kubectl config set-cluster kubernetes \
  --certificate-authority=k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=bootstrap.kubeconfig
kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=bootstrap.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=bootstrap.kubeconfig
kubectl config use-context default --kubeconfig=bootstrap.kubeconfig

echo "Create kube-proxy kubeconfig..."
kubectl config set-cluster kubernetes \
  --certificate-authority=k8s-root-ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=kube-proxy.kubeconfig
kubectl config use-context default --kubeconfig=kube-proxy.kubeconfig

# 生成高级审计配置
cat >> audit-policy.yaml <<EOF
# Log all requests at the Metadata level.
apiVersion: audit.k8s.io/v1beta1
kind: Policy
rules:
- level: Metadata
EOF
```


#### 3.2、分发 rpm 及证书

创建好证书以后就要进行分发，同时由于 Master 也作为 Node 使用，所以以下命令中在 Master 上也安装了 kubelet、kube-proxy 组件

``` sh
# 分发并安装 rpm
for IP in `seq 5 7`; do
    scp kubernetes*.rpm root@10.10.1.$IP:~; 
    ssh root@10.10.1.$IP yum install -y kubernetes*.rpm
done

# 分发证书
for IP in `seq 5 7`;do
    ssh root@10.10.1.$IP mkdir /etc/kubernetes/ssl
    scp *.pem root@10.10.1.$IP:/etc/kubernetes/ssl
    scp *.kubeconfig token.csv audit-policy.yaml root@10.10.1.$IP:/etc/kubernetes
    ssh root@10.10.1.$IP chown -R kube:kube /etc/kubernetes/ssl
done

# 设置 log 目录权限
for IP in `seq 5 7`;do
    ssh root@10.10.1.$IP mkdir -p /var/log/kube-audit /usr/libexec/kubernetes
    ssh root@10.10.1.$IP chown -R kube:kube /var/log/kube-audit /usr/libexec/kubernetes
    ssh root@10.10.1.$IP chmod -R 755 /var/log/kube-audit /usr/libexec/kubernetes
done
```

#### 3.3、 搭建 Master 节点

证书与 rpm 都安装完成后，只需要修改配置(配置位于 `/etc/kubernetes` 目录)后启动相关组件即可

- config 通用配置

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

##### apiserver 配置

``` sh
###
# kubernetes system config
#
# The following values are used to configure the kube-apiserver
#

# The address on the local server to listen to.
KUBE_API_ADDRESS="--advertise-address=10.10.1.5 --insecure-bind-address=127.0.0.1 --bind-address=10.10.1.5"

# The port on the local server to listen on.
KUBE_API_PORT="--insecure-port=8080 --secure-port=6443"

# Port minions listen on
# KUBELET_PORT="--kubelet-port=10250"

# Comma separated list of nodes in the etcd cluster
KUBE_ETCD_SERVERS="--etcd-servers=https://10.10.1.5:2379,https://10.10.1.6:2379,https://10.10.1.7:2379"

# Address range to use for services
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"

# default admission control policies
KUBE_ADMISSION_CONTROL="--admission-control=NamespaceLifecycle,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota,NodeRestriction"

# Add your own!
KUBE_API_ARGS="--authorization-mode=RBAC,Node \
               --anonymous-auth=false \
               --kubelet-https=true \
               --enable-bootstrap-token-auth \
               --token-auth-file=/etc/kubernetes/token.csv \
               --service-node-port-range=30000-50000 \
               --tls-cert-file=/etc/kubernetes/ssl/kubernetes.pem \
               --tls-private-key-file=/etc/kubernetes/ssl/kubernetes-key.pem \
               --client-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
               --service-account-key-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
               --etcd-quorum-read=true \
               --storage-backend=etcd3 \
               --etcd-cafile=/etc/etcd/ssl/etcd-root-ca.pem \
               --etcd-certfile=/etc/etcd/ssl/etcd.pem \
               --etcd-keyfile=/etc/etcd/ssl/etcd-key.pem \
               --enable-swagger-ui=true \
               --apiserver-count=3 \
               --audit-policy-file=/etc/kubernetes/audit-policy.yaml \
               --audit-log-maxage=30 \
               --audit-log-maxbackup=3 \
               --audit-log-maxsize=100 \
               --audit-log-path=/var/log/kube-audit/audit.log \
               --event-ttl=1h"
```


**注意：API SERVER 对比 1.7 配置出现几项变动:**

- 移除了 `--runtime-config=rbac.authorization.k8s.io/v1beta1` 配置，因为 RBAC 已经稳定，被纳入了 v1 api，不再需要指定开启
- `--authorization-mode` 授权模型增加了 `Node` 参数，因为 1.8 后默认 `system:node` role 不会自动授予 `system:nodes` 组，具体请参看 [CHANGELOG](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md#before-upgrading)(before-upgrading 段最后一条说明)
- 由于以上原因，`--admission-control` 同时增加了 `NodeRestriction` 参数，关于关于节点授权器请参考 [Using Node Authorization](https://kubernetes.io/docs/admin/authorization/node/)
- 增加 `--audit-policy-file` 参数用于指定高级审计配置，具体可参考 [CHANGELOG](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md#before-upgrading)(before-upgrading 第四条)、[Advanced audit](https://kubernetes.io/docs/tasks/debug-application-cluster/audit/#advanced-audit)
- 移除 `--experimental-bootstrap-token-auth` 参数，更换为 `--enable-bootstrap-token-auth`，详情参考 [CHANGELOG](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md#auth)(Auth 第二条)

##### controller-manager 配置

``` sh
###
# The following values are used to configure the kubernetes controller-manager

# defaults from config and apiserver should be adequate

# Add your own!
KUBE_CONTROLLER_MANAGER_ARGS="--address=0.0.0.0 \
                              --service-cluster-ip-range=10.254.0.0/16 \
                              --cluster-name=kubernetes \
                              --cluster-signing-cert-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                              --cluster-signing-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                              --service-account-private-key-file=/etc/kubernetes/ssl/k8s-root-ca-key.pem \
                              --root-ca-file=/etc/kubernetes/ssl/k8s-root-ca.pem \
                              --leader-elect=true \
                              --node-monitor-grace-period=40s \
                              --node-monitor-period=5s \
                              --pod-eviction-timeout=5m0s"
```

##### scheduler 配置

``` sh
###
# kubernetes scheduler config

# default config should be adequate

# Add your own!
KUBE_SCHEDULER_ARGS="--leader-elect=true --address=0.0.0.0"
```

最后启动 Master 相关组件并验证

``` sh
systemctl daemon-reload
systemctl start kube-apiserver
systemctl start kube-controller-manager
systemctl start kube-scheduler
systemctl enable kube-apiserver
systemctl enable kube-controller-manager
systemctl enable kube-scheduler
```

![Master Success](https://mritd.b0.upaiyun.com/markdown/klnwa.jpg)


### 四、搭建 Node 节点

#### 4.1、分发 rpm 及证书

对于 Node 节点，只需要安装 `kubernetes-node` 即可，同时为了方便使用，这里也安装了 `kubernetes-client`，如下

``` sh
for IP in `seq 8 9`;do
    scp kubernetes-node-1.8.0-1.el7.centos.x86_64.rpm kubernetes-client-1.8.0-1.el7.centos.x86_64.rpm root@10.10.1.$IP:~
    ssh root@10.10.1.$IP yum install -y kubernetes-node-1.8.0-1.el7.centos.x86_64.rpm kubernetes-client-1.8.0-1.el7.centos.x86_64.rpm
done
```

同时还要分发相关证书；这里将 Etcd 证书已进行了分发，是因为 **虽然 Node 节点上没有 Etcd，但是如果部署网络组件，如 calico、flannel 等时，网络组件需要联通 Etcd 就会用到 Etcd 的相关证书。**

``` sh
# 分发 Kubernetes 证书
for IP in `seq 8 9`;do
    ssh root@10.10.1.$IP mkdir /etc/kubernetes/ssl
    scp *.pem root@10.10.1.$IP:/etc/kubernetes/ssl
    scp *.kubeconfig token.csv audit-policy.yaml root@10.10.1.$IP:/etc/kubernetes
    ssh root@10.10.1.$IP chown -R kube:kube /etc/kubernetes/ssl
done

# 分发 Etcd 证书
for IP in `seq 8 9`;do
    ssh root@10.10.1.$IP mkdir -p /etc/etcd/ssl
    scp *.pem root@10.10.1.$IP:/etc/etcd/ssl
    ssh root@10.10.1.$IP chmod -R 644 /etc/etcd/ssl/*
    ssh root@10.10.1.$IP chmod 755 /etc/etcd/ssl
done
```

#### 4.2、修改 Node 配置

Node 上只需要修改 kubelet 和 kube-proxy 的配置即可

##### config 通用配置

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
# KUBE_MASTER="--master=http://127.0.0.1:8080"
```

##### kubelet 配置

``` sh
###
# kubernetes kubelet (minion) config

# The address for the info server to serve on (set to 0.0.0.0 or "" for all interfaces)
KUBELET_ADDRESS="--address=10.10.1.8"

# The port for the info server to serve on
# KUBELET_PORT="--port=10250"

# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname-override=docker4.node"

# location of the api-server
# KUBELET_API_SERVER=""

# Add your own!
KUBELET_ARGS="--cgroup-driver=cgroupfs \
              --cluster-dns=10.254.0.2 \
              --resolv-conf=/etc/resolv.conf \
              --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
              --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
              --fail-swap-on=false \
              --cert-dir=/etc/kubernetes/ssl \
              --cluster-domain=cluster.local. \
              --hairpin-mode=promiscuous-bridge \
              --serialize-image-pulls=false \
              --pod-infra-container-image=gcr.io/google_containers/pause-amd64:3.0"
```

**注意: kubelet 配置与 1.7 版本有一定改动**

- 增加 `--fail-swap-on=false` 选项，否则可能导致在开启 swap 分区的机器上无法启动 kubelet，详细可参考 [CHANGELOG](https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG.md#before-upgrading)(before-upgrading 第一条)
- 移除 `--require-kubeconfig` 选项，已经过时废弃


##### proxy 配置

``` sh
###
# kubernetes proxy config
# default config should be adequate
# Add your own!
KUBE_PROXY_ARGS="--bind-address=10.10.1.8 \
                 --hostname-override=docker4.node \
                 --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \
                 --cluster-cidr=10.254.0.0/16"
```

**kube-proxy 配置与 1.7 并无改变，最新 1.8 的 ipvs 模式将单独写一篇文章，这里不做介绍**



#### 4.3、创建 Nginx 代理

由于 HA 方案基于 Nginx 反代实现，所以每个 Node 要启动一个 Nginx 负载均衡 Master，具体参考 [HA Master 简述](https://mritd.me/2017/07/21/set-up-kubernetes-ha-cluster-by-binary/#41ha-master-%E7%AE%80%E8%BF%B0)

##### nginx.conf

``` sh
# 创建配置目录
mkdir -p /etc/nginx

# 写入代理配置
cat << EOF >> /etc/nginx/nginx.conf
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
        server 10.10.1.5:6443;
        server 10.10.1.6:6443;
        server 10.10.1.7:6443;
    }

    server {
        listen        0.0.0.0:6443;
        proxy_pass    kube_apiserver;
        proxy_timeout 10m;
        proxy_connect_timeout 1s;
    }
}
EOF

# 更新权限
chmod +r /etc/nginx/nginx.conf
```

##### nginx-proxy.service

``` sh
cat << EOF >> /etc/systemd/system/nginx-proxy.service
[Unit]
Description=kubernetes apiserver docker wrapper
Wants=docker.socket
After=docker.service

[Service]
User=root
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run -p 127.0.0.1:6443:6443 \\
                              -v /etc/nginx:/etc/nginx \\
                              --name nginx-proxy \\
                              --net=host \\
                              --restart=on-failure:5 \\
                              --memory=512M \\
                              nginx:1.13.5-alpine
ExecStartPre=-/usr/bin/docker rm -f nginx-proxy
ExecStop=/usr/bin/docker stop nginx-proxy
Restart=always
RestartSec=15s
TimeoutStartSec=30s

[Install]
WantedBy=multi-user.target
EOF
```

**最后启动 Nginx 代理即可**

``` sh
systemctl daemon-reload
systemctl start nginx-proxy
systemctl enable nginx-proxy
```

#### 4.4、添加 Node

一切准备就绪后就可以添加 Node 了，首先由于我们采用了 [TLS Bootstrapping](https://kubernetes.io/docs/admin/kubelet-tls-bootstrapping/)，所以需要先创建一个 ClusterRoleBinding

``` sh
# 在任意 master 执行即可
kubectl create clusterrolebinding kubelet-bootstrap \
  --clusterrole=system:node-bootstrapper \
  --user=kubelet-bootstrap
```

然后启动 kubelet

``` sh
systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet
```

由于采用了 TLS Bootstrapping，所以 kubelet 启动后不会立即加入集群，而是进行证书申请，从日志中可以看到如下输出

``` sh
10月 06 19:53:23 docker4.node kubelet[3797]: I1006 19:53:23.917261    3797 bootstrap.go:57] Using bootstrap kubeconfig to generate TLS client cert, key and kubeconfig file
```

此时只需要在 master 允许其证书申请即可

``` sh
kubectl get csr | grep Pending | awk '{print $1}' | xargs kubectl certificate approve
```

此时可以看到 Node 已经加入了

``` sh
docker1.node ➜  ~ kubectl get node
NAME           STATUS    ROLES     AGE       VERSION
docker4.node   Ready     <none>    14m       v1.8.0
docker5.node   Ready     <none>    3m        v1.8.0
```

最后再启动 kube-proxy 即可

``` sh
systemctl start kube-proxy
systemctl enable kube-proxy
```


**再次提醒: 如果 kubelet 启动出现了类似 `system:node:xxxx` 用户没有权限访问 API 的 RBAC 错误，那么一定是 API Server 授权控制器、准入控制配置有问题，请仔细阅读上面的文档进行更改**

#### 4.5、Master 作为 Node

如果想讲 Master 也作为 Node 的话，请在 Master 上安装 kubernete-node rpm 包，配置与上面基本一致；**区别于 Master 上不需要启动 nginx 做负载均衡，同时 `bootstrap.kubeconfig`、`kube-proxy.kubeconfig` 中的 API Server 地址改成当前 Master IP 即可。**

最终成功后如下图所示

![cluster success](https://mritd.b0.upaiyun.com/markdown/c4dde.jpg)


### 五、部署 Calico

#### 5.1、修改 Calico 配置

Calico 部署仍然采用 "混搭" 方式，即 Systemd 控制 calico node，cni 等由 kubernetes daemonset 安装，具体请参考 [Calico 部署踩坑记录](https://mritd.me/2017/07/31/calico-yml-bug/)，以下直接上代码

``` sh
# 获取 calico.yaml
wget https://docs.projectcalico.org/v2.6/getting-started/kubernetes/installation/hosted/calico.yaml

# 替换 Etcd 地址
sed -i 's@.*etcd_endpoints:.*@\ \ etcd_endpoints:\ \"https://10.10.1.5:2379,https://10.10.1.6:2379,https://10.10.1.7:2379\"@gi' calico.yaml

# 替换 Etcd 证书
export ETCD_CERT=`cat /etc/etcd/ssl/etcd.pem | base64 | tr -d '\n'`
export ETCD_KEY=`cat /etc/etcd/ssl/etcd-key.pem | base64 | tr -d '\n'`
export ETCD_CA=`cat /etc/etcd/ssl/etcd-root-ca.pem | base64 | tr -d '\n'`

sed -i "s@.*etcd-cert:.*@\ \ etcd-cert:\ ${ETCD_CERT}@gi" calico.yaml
sed -i "s@.*etcd-key:.*@\ \ etcd-key:\ ${ETCD_KEY}@gi" calico.yaml
sed -i "s@.*etcd-ca:.*@\ \ etcd-ca:\ ${ETCD_CA}@gi" calico.yaml

sed -i 's@.*etcd_ca:.*@\ \ etcd_ca:\ "/calico-secrets/etcd-ca"@gi' calico.yaml
sed -i 's@.*etcd_cert:.*@\ \ etcd_cert:\ "/calico-secrets/etcd-cert"@gi' calico.yaml
sed -i 's@.*etcd_key:.*@\ \ etcd_key:\ "/calico-secrets/etcd-key"@gi' calico.yaml

# 注释掉 calico-node 部分(由 Systemd 接管)
sed -i '103,189s@.*@#&@gi' calico.yaml
```

#### 5.2、创建 Systemd 文件

上一步注释了 `calico.yaml` 中 Calico Node 相关内容，为了防止自动获取 IP 出现问题，将其移动到 Systemd，Systemd service 配置如下，**每个节点都要安装 calico-node 的 Service**，其他节点请自行修改 ip(被问我为啥是两个反引号 `\\`，自己试就知道了)

``` sh
cat > /usr/lib/systemd/system/calico-node.service <<EOF
[Unit]
Description=calico node
After=docker.service
Requires=docker.service

[Service]
User=root
PermissionsStartOnly=true
ExecStart=/usr/bin/docker run   --net=host --privileged --name=calico-node \\
                                -e ETCD_ENDPOINTS=https://10.10.1.5:2379,https://10.10.1.6:2379,https://10.10.1.7:2379 \\
                                -e ETCD_CA_CERT_FILE=/etc/etcd/ssl/etcd-root-ca.pem \\
                                -e ETCD_CERT_FILE=/etc/etcd/ssl/etcd.pem \\
                                -e ETCD_KEY_FILE=/etc/etcd/ssl/etcd-key.pem \\
                                -e NODENAME=docker1.node \\
                                -e IP=10.10.1.5 \\
                                -e IP6= \\
                                -e AS= \\
                                -e CALICO_IPV4POOL_CIDR=10.20.0.0/16 \\
                                -e CALICO_IPV4POOL_IPIP=always \\
                                -e CALICO_LIBNETWORK_ENABLED=true \\
                                -e CALICO_NETWORKING_BACKEND=bird \\
                                -e CALICO_DISABLE_FILE_LOGGING=true \\
                                -e FELIX_IPV6SUPPORT=false \\
                                -e FELIX_DEFAULTENDPOINTTOHOSTACTION=ACCEPT \\
                                -e FELIX_LOGSEVERITYSCREEN=info \\
                                -v /etc/etcd/ssl/etcd-root-ca.pem:/etc/etcd/ssl/etcd-root-ca.pem \\
                                -v /etc/etcd/ssl/etcd.pem:/etc/etcd/ssl/etcd.pem \\
                                -v /etc/etcd/ssl/etcd-key.pem:/etc/etcd/ssl/etcd-key.pem \\
                                -v /var/run/calico:/var/run/calico \\
                                -v /lib/modules:/lib/modules \\
                                -v /run/docker/plugins:/run/docker/plugins \\
                                -v /var/run/docker.sock:/var/run/docker.sock \\
                                -v /var/log/calico:/var/log/calico \\
                                quay.io/calico/node:v2.6.1
ExecStop=/usr/bin/docker rm -f calico-node
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
```

#### 5.3、修改 kubelet 配置

根据官方文档要求 `kubelet` 配置必须增加 `--network-plugin=cni` 选项，所以需要修改 kubelet 配置

``` sh
###
# kubernetes kubelet (minion) config
# The address for the info server to serve on (set to 0.0.0.0 or "" for all interfaces)
KUBELET_ADDRESS="--address=10.10.1.5"
# The port for the info server to serve on
# KUBELET_PORT="--port=10250"
# You may leave this blank to use the actual hostname
KUBELET_HOSTNAME="--hostname-override=docker1.node"
# location of the api-server
# KUBELET_API_SERVER=""
# Add your own!
KUBELET_ARGS="--cgroup-driver=cgroupfs \
              --network-plugin=cni \
              --cluster-dns=10.254.0.2 \
              --resolv-conf=/etc/resolv.conf \
              --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \
              --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \
              --fail-swap-on=false \
              --cert-dir=/etc/kubernetes/ssl \
              --cluster-domain=cluster.local. \
              --hairpin-mode=promiscuous-bridge \
              --serialize-image-pulls=false \
              --pod-infra-container-image=gcr.io/google_containers/pause-amd64:3.0"
```

然后重启即可

``` sh
systemctl daemon-reload
systemctl restart kubelet
```

此时执行 `kubectl get node` 会看到 Node 为 `NotReady` 状态，属于正常情况


#### 5.4、创建 Calico Daemonset

``` sh
# 先创建 RBAC
kubectl apply -f https://docs.projectcalico.org/v2.6/getting-started/kubernetes/installation/rbac.yaml

# 再创建 Calico Daemonset
kubectl create -f calico.yaml
```

#### 5.5、创建 Calico Node

Calico Node 采用 Systemd 方式启动，在每个节点配置好 Systemd service后，**每个节点修改对应的 `calico-node.service` 中的 IP 和节点名称，然后启动即可**

``` sh
systemctl daemon-reload
systemctl restart calico-node
sleep 5
systemctl restart kubelet
```

此时检查 Node 应该都处于 Ready 状态

![Node Ready](https://mritd.b0.upaiyun.com/markdown/agxp3.jpg)

**最后测试一下跨主机通讯**

``` sh
# 创建 deployment
cat << EOF >> demo.deploy.yml
apiVersion: apps/v1beta2
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

**进入其中一个 Pod，ping 另一个 Pod 的 IP 测试即可**

![Test Calico](https://mritd.b0.upaiyun.com/markdown/00krx.jpg)


### 六、部署 DNS

#### 6.1、部署集群 DNS

DNS 组件部署非常简单，直接创建相应的 deployment 等即可；但是有一个事得说一嘴，Kubernets 一直在推那个 `Addon Manager` 的工具来管理 DNS 啥的，文档说的条条是道，就是不希望我们手动搞这些东西，防止意外修改云云... 但问题是关于那个 `Addon Manager` 咋用一句没提，虽然说里面就一个小脚本，看看也能懂；但是我还是选择手动 😌... 还有这个 DNS 配置文件好像又挪地方了，以前在 `contrib` 项目下的...

``` sh
# 获取文件
wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns/kube-dns.yaml.sed
mv kube-dns.yaml.sed kube-dns.yaml

# 修改配置
sed -i 's/$DNS_DOMAIN/cluster.local/gi' kube-dns.yaml
sed -i 's/$DNS_SERVER_IP/10.254.0.2/gi' kube-dns.yaml

# 创建
kubectl create -f kube-dns.yaml
```

创建好以后如下所示

![DNS](https://mritd.b0.upaiyun.com/markdown/vg95n.jpg)

然后创建两组 Pod 和 Service，进入 Pod 中 curl 另一个 Service 名称看看是否能解析；同时还要测试一下外网能否解析

![Test DNS1](https://mritd.b0.upaiyun.com/markdown/x185c.jpg)

测试外网

![Test DNS2](https://mritd.b0.upaiyun.com/markdown/3k9gz.jpg)


#### 6.2、部署 DNS 自动扩容部署

这个同样下载 yaml，然后创建一下即可，不需要修改任何配置

``` sh
wget https://raw.githubusercontent.com/kubernetes/kubernetes/master/cluster/addons/dns-horizontal-autoscaler/dns-horizontal-autoscaler.yaml
kubectl create -f dns-horizontal-autoscaler.yaml
```

部署完成后如下

![DNS autoscaler](https://mritd.b0.upaiyun.com/markdown/mid1u.jpg)

自动扩容这里不做测试了，虚拟机吃不消了，详情自己参考 [Autoscale the DNS Service in a Cluster](https://kubernetes.io/docs/tasks/administer-cluster/dns-horizontal-autoscaling/)

**kube-proxy ipvs 下一篇写，坑有点多，虽然搞定了，但是一篇写有点囫囵吞枣，后来想一想还是分开吧**

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
