---
layout: post
categories: Docker Kubernetes
title: kubernetes 1.4 集群搭建
date: 2016-10-09 23:35:34 +0800
description: 记录一下 kubernetes 使用 kubeadm 搭建集群的方法
keywords: kubernetes kubeadm
---

> 距离 kubernetes 1.4 发布已经有段时间，1.4 版本新增了很多新特性，其中一个比较实用的功能就是增加了集群的快速创建，基本只需要 2 条命令就能搭建成功；但由于众所周知的原因(fuck GFW)，导致 kuadm 命令无法工作，以下记录了一下解决方案

### 一、环境准备

基本环境为 3 台虚拟机，虚拟机信息如下

|IP 地址|节点|
|-------|----|
|192.168.1.107|master|
|192.168.1.126|node1|
|192.168.1.217|node2|

#### 1.1、安装 docker

docker 这里使用的是 1.12.1 版本，安装直接根据官方教程来，如果网速较慢可切换国内源，如清华大 docker 源，具体请 Google

``` sh
tee /etc/yum.repos.d/docker.repo <<-'EOF'
[dockerrepo]
name=Docker Repository
baseurl=https://yum.dockerproject.org/repo/main/centos/7/
enabled=1
gpgcheck=1
gpgkey=https://yum.dockerproject.org/gpg
EOF

yum install docker-engine -y

systemctl enable docker
systemctl start docker
systemctl status docker
```

#### 1.2、修改主机名

由于 3 台虚拟机是从一个基础虚拟机复制而来，为了不影响 `kubectl get nodes` 查询，需要更改 3 台虚拟机的主机名，以下为 master 节点示例，其他节点对应修改即可

``` sh
echo "master" > /etc/hostname
# 替换一下 hosts 中的 localhost 等
vim /etc/hosts
# 修改后内容如下
127.0.0.1   master
::1         master
192.168.1.107 master
192.168.1.126 node1
192.168.1.217 node2
```

### 二、搭建 kubernetes 集群

#### 2.1、安装基本组件

**根据 [官方文档教程](http://kubernetes.io/docs/getting-started-guides/kubeadm/) 需要先安装 `kubelet`、`kubeadm`、`kubectl`、 `kubernetes-cni` 这四个 rpm 包，但是由于 GFW 原因实际上 Google 的 rpm 源无法下载，以下是我通过梯子下载到本地的，rpm 下载方法 可借助 yumdownloader 工具，具体请 Google**

``` sh
# 首先安装 socat
yum install -y socat
# 然后下载相关 rpm，我已经放到了 cdn 里
rpms=(5ce829590fb4d5c860b80e73d4483b8545496a13f68ff3033ba76fa72632a3b6-kubernetes-cni-0.3.0.1-0.07a8a2.x86_64.rpm \
     bbad6f8b76467d0a5c40fe0f5a1d92500baef49dedff2944e317936b110524eb-kubeadm-1.5.0-0.alpha.0.1534.gcf7301f.x86_64.rpm \
     c37966352c9d394bf2cc1f755938dfb679aa45ac866d3eb1775d9c9b87d5e177-kubelet-1.4.0-0.x86_64.rpm \
     fac5b4cd036d76764306bd1df7258394b200be4c11f4e3fdd100bfb25a403ed4-kubectl-1.4.0-0.x86_64.rpm)
for rpmName in ${rpms[@]}; do
  wget http://upyun.mritd.me/kubernetes/$rpmName
done
# 最后安装即可
rpm -ivh *.rpm
```

#### 2.2、启动相关组件

接下来启动 docker 和 kubelet 

``` sh
systemctl enable docker
systemctl enable kubelet
systemctl start docker
systemctl start kubelet
```

此时查看 kubelet 其实是启动失败的，因为缺少相关配置，以下一部部署以后便会自动重启成功

**在正式使用 kubeadm 创建集群以前还需要关闭 selinux，在下一个版本这个问题已经被解决**

``` sh
# 关闭 selinux
setenforce 0
```

#### 2.3、导入相关 image

kubeadm 会 pull 相关的 image，由于 GFW 的原因会造成无法下载最终失败，所以最好的办法是先用梯子 pull 下来，再 load 进去即可，以下为需要 load 进的镜像

|镜像名称|版本号|
|--------|------|
|gcr.io/google_containers/kube-proxy-amd64               | v1.4.0 |
|gcr.io/google_containers/kube-discovery-amd64           | 1.0    |
|gcr.io/google_containers/kubedns-amd64                  | 1.7    |
|gcr.io/google_containers/kube-scheduler-amd64           | v1.4.0 |
|gcr.io/google_containers/kube-controller-manager-amd64  | v1.4.0 |
|gcr.io/google_containers/kube-apiserver-amd64           | v1.4.0 |
|gcr.io/google_containers/etcd-amd64                     | 2.2.5  |
|gcr.io/google_containers/kube-dnsmasq-amd64             | 1.3    |
|gcr.io/google_containers/exechealthz-amd64              | 1.1    |
|gcr.io/google_containers/pause-amd64                    | 3.0    |

**实际上不用梯子可以借助于 DockerHub 的自动构建功能，实现代理下载，如下所示**

``` sh
images=(kube-proxy-amd64:v1.4.0 kube-discovery-amd64:1.0 kubedns-amd64:1.7 kube-scheduler-amd64:v1.4.0 kube-controller-manager-amd64:v1.4.0 kube-apiserver-amd64:v1.4.0 etcd-amd64:2.2.5 kube-dnsmasq-amd64:1.3 exechealthz-amd64:1.1 pause-amd64:3.0 kubernetes-dashboard-amd64:v1.4.0)
for imageName in ${images[@]} ; do
  docker pull mritd/$imageName
  docker tag mritd/$imageName gcr.io/google_containers/$imageName
  docker rmi mritd/$imageName
done
```

#### 2.4、创建集群

首先在 master 上执行 init 操作

``` sh
kubeadm init --api-advertise-addresses=192.168.1.107
```

此时显示信息如下表示创建完成

``` sh
➜  ~ kubeadm init --api-advertise-addresses=192.168.1.107
<master/tokens> generated token: "42354d.e1fb733ed0c9a932"
<master/pki> created keys and certificates in "/etc/kubernetes/pki"
<util/kubeconfig> created "/etc/kubernetes/kubelet.conf"
<util/kubeconfig> created "/etc/kubernetes/admin.conf"
<master/apiclient> created API client configuration
<master/apiclient> created API client, waiting for the control plane to become ready
<master/apiclient> all control plane components are healthy after 18.921781 seconds
<master/apiclient> waiting for at least one node to register and become ready
<master/apiclient> first node is ready after 2.014976 seconds
<master/discovery> created essential addon: kube-discovery, waiting for it to become ready
<master/discovery> kube-discovery is ready after 3.505092 seconds
<master/addons> created essential addon: kube-proxy
<master/addons> created essential addon: kube-dns

Kubernetes master initialised successfully!

You can now join any number of machines by running the following on each node:

kubeadm join --token 42354d.e1fb733ed0c9a932 192.168.1.107
```

然后在子节点上使用 join 命令加入集群即可

``` sh
kubeadm join --token 42354d.e1fb733ed0c9a932 192.168.1.107
```

最后稍等片刻在 master 上 get nodes 即可查看，**如果想让 master 也运行 pod，只需在 master 上运行 `kubectl taint nodes --all dedicated-` 即可**

``` sh
➜  ~ kubectl get nodes                                   
NAME      STATUS    AGE
master    Ready     1m
node1     Ready     1m
node2     Ready     1m
```

#### 2.5、创建 Pod 网络

创建好集群后，为了能让容器进行跨主机通讯还要部署 Pod 网络，这里使用官方推荐的 weave 方式，也可以采用 flannel，以下为 weave 示例

``` sh
# 在 master 上执行
kubectl apply -f https://git.io/weave-kube
```

到此搭建完成

**本文参考 [来自天国的 kubernetes](https://segmentfault.com/a/1190000007074726)、[Installing Kubernetes on Linux with kubeadm](http://kubernetes.io/docs/getting-started-guides/kubeadm)**

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
