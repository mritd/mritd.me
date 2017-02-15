---
layout: post
title: kubernetes 双向 TLS 配置
categories: [Docker, Kubernetes]
description: kubernetes 双向 TLS 配置
keywords: kubernetes,Docker,Linux
---


> 本文参考 《kubernetes 实战》、《kubernetes 权威指南》、[CoreOS Getting-Started](https://coreos.com/kubernetes/docs/latest/getting-started.html)

## 一、简介

kubernetes 提供了多种安全认证机制，其中对于集群通讯间可采用 TLS(https) 双向认证机制，也可采用基于 Token 或用户名密码的单向 tls 认证，由于 kubernetes 某些组件只支持双向 TLS 认证，所以本文主要记录 kubernetes 双向认证配置。

## 二、签发证书

其中 TLS 双向认证需要预先自建 CA 签发证书，权威 CA 机构的证书应该不可用，因为大部分 kubernetes 应该基于内网部署，而内网应该都会采用私有 IP 地址通讯，权威 CA 好像只能签署域名证书，对于签署到 IP 可能无法实现。

<!--more-->

### 2.1、自签 CA

对于私有证书签发首先要自签署 一个 CA 根证书，关于 OpenSSL 使用等相关可参考 [互联网加密及OpenSSL介绍和简单使用](http://mritd.me/2016/07/02/%E4%BA%92%E8%81%94%E7%BD%91%E5%8A%A0%E5%AF%86%E5%8F%8AOpenSSL%E4%BB%8B%E7%BB%8D%E5%92%8C%E7%AE%80%E5%8D%95%E4%BD%BF%E7%94%A8/)

``` sh
# 创建证书存放目录
mkdir cert && cd cert
# 创建 CA 私钥
openssl genrsa -out ca-key.pem 2048
# 自签 CA
openssl req -x509 -new -nodes -key ca-key.pem -days 10000 -out ca.pem -subj "/CN=kube-ca"
```

### 2.2、签署 apiserver 证书

自签 CA 后就需要使用这个根 CA 签署 apiserver 相关的证书了，首先先修改 openssl 的配置

``` sh
# 复制 openssl 配置文件
cp /etc/pki/tls/openssl.cnf .
# 编辑 openssl 配置使其支持 IP 认证
vim openssl.cnf
# 主要修改内容如下
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster.local
IP.1 = ${K8S_SERVICE_IP}  # kubernetes server ip
IP.2 = ${MASTER_HOST}     # master ip(如果都在一台机器上写一个就行)
```

然后开始签署 apiserver 相关的证书

``` sh
# 生成 apiserver 私钥
openssl genrsa -out apiserver-key.pem 2048
# 生成签署请求
openssl req -new -key apiserver-key.pem -out apiserver.csr -subj "/CN=kube-apiserver" -config openssl.cnf
# 使用自建 CA 签署
openssl x509 -req -in apiserver.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out apiserver.pem -days 365 -extensions v3_req -extfile openssl.cnf
```

### 2.3、签署 node 证书

apiserver 证书签署完成后还需要签署每个节点 node 的证书，同样需要先修改一下 openssl 配置

``` sh
# copy master 的 openssl 配置
cp openssl.cnf worker-openssl.cnf
# 修改 worker-openssl 配置
vim worker-openssl.cnf
# 修改内容如下，主要是去掉 DNS 同时增加节点 IP
[req]
req_extensions = v3_req
distinguished_name = req_distinguished_name
[req_distinguished_name]
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
IP.1 = NODE1-IP # 此处填写 node 的内网 ip，多个 node ip 地址以此类推 IP.2 = NODE2-IP
```

接下来签署 node 的证书，以 node1 IP为 192.168.1.142 为例

``` sh
# 先声明两个变量方便引用
WORKER_FQDN=node1          # node 昵称
WORKER_IP=192.168.1.142    # node IP
# 生成 node 私钥
openssl genrsa -out ${WORKER_FQDN}-worker-key.pem 2048
# 生成 签署请求
openssl req -new -key ${WORKER_FQDN}-worker-key.pem -out ${WORKER_FQDN}-worker.csr -subj "/CN=${WORKER_FQDN}" -config worker-openssl.cnf
# 使用自建 CA 签署
openssl x509 -req -in ${WORKER_FQDN}-worker.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out ${WORKER_FQDN}-worker.pem -days 365 -extensions v3_req -extfile worker-openssl.cnf
```

### 2.4、生成集群管理证书

在 master(apiserver) 和 node 的证书签署完成后还需要签署一个集群管理证书

``` sh
openssl genrsa -out admin-key.pem 2048
openssl req -new -key admin-key.pem -out admin.csr -subj "/CN=kube-admin"
openssl x509 -req -in admin.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out admin.pem -days 365
```

**最终生成的文件清单如下**

![hexo_kubernetes_tls_certs](https://mritd.b0.upaiyun.com/markdown/hexo_kubernetes_tls_certs.png)

## 三、配置 kubernetes

### 3.1、配置 master

相关证书全部准备好以后，开始配置 master，首先复制证书

```sh
# 先把证书 copy 到配置目录
mkdir -p /etc/kubernetes/ssl
cp cert/ca.pem cert/apiserver.pem cert/apiserver-key.pem /etc/kubernetes/ssl
# rpm 安装的 kubernetes 默认使用 kube 用户，需要更改权限
chown kube:kube -R /etc/kubernetes/ssl
```
**然后编辑 master 的 apiserver 配置**

``` sh
# 编辑 master apiserver 配置文件
vim /etc/kubernetes/apiserver
# 配置如下
KUBE_API_ADDRESS="--bind-address=192.168.1.142 --insecure-bind-address=127.0.0.1 "
KUBE_API_PORT="--secure-port=6443 --insecure-port=8080"
KUBE_ETCD_SERVERS="--etcd-servers=http://192.168.1.100:2379"
KUBE_SERVICE_ADDRESSES="--service-cluster-ip-range=10.254.0.0/16"
KUBE_ADMISSION_CONTROL="--admission-control=NamespaceLifecycle,NamespaceExists,LimitRanger,SecurityContextDeny,ServiceAccount,ResourceQuota"
KUBE_API_ARGS="--tls-cert-file=/etc/kubernetes/ssl/apiserver.pem --tls-private-key-file=/etc/kubernetes/ssl/apiserver-key.pem --client-ca-file=/etc/kubernetes/ssl/ca.pem --service-account-key-file=/etc/kubernetes/ssl/apiserver-key.pem "
```

**接着编辑 controller manager 的配置**

``` sh
# 编辑 controller manager 配置
vim /etc/kubernetes/controller-manager
# 配置如下
KUBE_CONTROLLER_MANAGER_ARGS="--service-account-private-key-file=/etc/kubernetes/ssl/apiserver-key.pem  --root-ca-file=/etc/kubernetes/ssl/ca.pem --master=http://127.0.0.1:8080"
```

**最后启动 apiserver 、controller manager 和 scheduler**

``` sh
systemctl start kube-apiserver
systemctl start kube-controller-manager
systemctl start kube-scheduler
systemctl enable kube-apiserver
systemctl enable kube-controller-manager
systemctl enable kube-scheduler
systemctl status kube-apiserver
systemctl status kube-controller-manager
systemctl status kube-scheduler
```

### 3.2、配置 node

**由于是测试，所以 node1 和 master 启动在同一台机器上，配置时同样先 copy 配置文件**

``` sh
cp cert/node1-worker-key.pem cert/node1-worker.pem /etc/kubernetes/ssl
chown kube:kube -R /etc/kubernetes/ssl
```

**修改 kubelet 配置**

``` sh
vim /etc/kubernetes/kubelet
# 配置如下
KUBELET_ADDRESS="--address=192.168.1.142"
KUBELET_HOSTNAME="--hostname-override=192-168-1-142"
KUBELET_API_SERVER="--api-servers=https://192.168.1.142:6443"
KUBELET_ARGS="--tls-cert-file=/etc/kubernetes/ssl/node1-worker.pem --tls-private-key-file=/etc/kubernetes/ssl/node1-worker-key.pem --kubeconfig=/etc/kubernetes/worker-kubeconfig.yaml"
```

**如果使用了 `KUBELET_HOSTNAME`，那么 hostname 必须在本地 hosts 存在，所以还需要修改一下 hosts 文件**

``` sh
echo "127.0.0.1 192-168-1-142" >> /etc/hosts
```

**修改 config 配置**

``` sh
vim /etc/kubernetes/config
# 配置如下
KUBE_LOGTOSTDERR="--logtostderr=true"
KUBE_LOG_LEVEL="--v=0"
KUBE_ALLOW_PRIV="--allow-privileged=false"
apiserver
KUBE_MASTER="--master=https://192.168.1.142:6443"
```

**创建 kube-proxy 配置文件**

``` sh
vim /etc/kubernetes/worker-kubeconfig.yaml
# 内容如下
apiVersion: v1
kind: Config
clusters:
- name: local
  cluster:
    certificate-authority: /etc/kubernetes/ssl/ca.pem
users:
- name: kubelet
  user:
    client-certificate: /etc/kubernetes/ssl/node1-worker.pem
    client-key: /etc/kubernetes/ssl/node1-worker-key.pem
contexts:
- context:
    cluster: local
    user: kubelet
  name: kubelet-context
current-context: kubelet-context
```

**配置 kube-proxy 使其使用证书**

``` sh
vim /etc/kubernetes/proxy
# 配置如下
KUBE_PROXY_ARGS="--master=https://192.168.1.100:6443 --kubeconfig=/etc/kubernetes/worker-kubeconfig.yaml"
```

**最后启动并测试**

``` sh
# 启动
systemctl start kubelet
systemctl start kube-proxy
systemctl enable kubelet
systemctl enable kube-proxy
systemctl status kubelet
systemctl status kube-proxy
# 测试
kubectl get node
# 显示如下
NAME            STATUS    AGE
192-168-1-142   Ready     13s
```

## 四、其他相关

master 启动后发现一个错误，大致意思是内核版本过低，但是 CentOS 已经 upgrade 到官方最新稳定版了。。。无奈换了下内核好了，以下为记录升级到最新内核的方法

``` rpm
# 导入 elrepo 的key
rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
# 安装 elrepo 源
rpm -Uvh http://www.elrepo.org/elrepo-release-7.0-2.el7.elrepo.noarch.rpm
# 在yum的ELRepo源中，mainline 为最新版本的内核，so 安装 ml 的内核
yum --enablerepo=elrepo-kernel install  kernel-ml-devel kernel-ml -y
# 切换 grub 引导，默认启动的顺序应该为1,升级以后内核是往前面插入，为0
grub2-set-default 0
# 最后重启
reboot
# 再看下检查下内核版本已经是 4.7.3-1.el7.elrepo.x86_64
uname -r
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
