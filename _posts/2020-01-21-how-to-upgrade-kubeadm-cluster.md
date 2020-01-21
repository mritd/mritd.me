---
layout: post
categories: Kubernetes
title: kubeadm 集群升级
date: 2020-01-21 21:34:38 +0800
description: kubeadm 集群升级
keywords: kubernetes,kubeadm,upgrade
catalog: true
multilingual: false
tags: Kubernetes
---

> 真是不巧，刚折腾完 kubeadm 搭建集群(v1.17.0)，第二天早上醒来特么的 v1.17.1 发布了；这我能忍么，肯定不能忍，然后就开始了集群升级之路...

## 一、升级前准备

- 确保你的集群是 kubeadm 搭建的(等同于废话)
- 确保当前集群已经完成 HA(多个 master 节点)
- 确保在夜深人静的时候(无大量业务流量)
- 确保集群版本大于 v1.16.0
- 确保已经仔细阅读了目标版本 CHANGELOG
- 确保做好了完整地集群备份

## 二、升级注意事项

- 升级后所有集群组件 Pod 会重启(hash 变更)
- **升级时 `kubeadm` 版本必须大于或等于目标版本**
- **升级期间所有 `kube-proxy` 组件会有一次全节点滚动更新**
- **升级只支持顺次进行，不支持跨版本升级(You only can upgrade from one MINOR version to the next MINOR version, or between PATCH versions of the same MINOR. That is, you cannot skip MINOR versions when you upgrade. For example, you can upgrade from 1.y to 1.y+1, but not from 1.y to 1.y+2.)**

关于升级版本问题...虽然是这么说的，但是官方文档样例代码里是从 `v1.16.0` 升级到 `v1.17.0`；可能是我理解有误，跨大版本升级好像官方没提，具体啥后果不清楚...

## 三、升级 Master

> 事实上所有升级工作主要是针对 master 节点做的，所以整个升级流程中最重要的是如何把 master 升级好。

### 3.1、升级 kubeadm、kubectl

首先由于升级限制，必须先将 `kubeadm` 和 `kubectl` 升级到大于等于目标版本

```sh
# replace x in 1.17.x-00 with the latest patch version
apt-mark unhold kubeadm kubectl
apt-get update
apt-get install -y kubeadm=1.17.x-00 kubectl=1.17.x-00
apt-mark hold kubeadm kubectl
```

当然如果你之前没有 `hold` 住这几个软件包的版本，那么就不需要 `unhold`；我的做法可能比较极端...一般为了防止后面的误升级安装完成后我会直接 `rename` 掉相关软件包的 `apt source` 配置(从根本上防止手贱)。

### 3.2、升级前准备

#### 3.2.1、配置修改

对于高级玩家一般安装集群时都会自定义很多组件参数，此时不可避免的会采用配置文件；所以安装完新版本的 `kubeadm` 后就要着手修改配置文件中的 `kubernetesVersion` 字段为目标集群版本，当然有其他变更也可以一起修改。

#### 3.2.2、节点驱逐

如果你的 master 节点也当作 node 在跑一些工作负载，则需要执行以下命令驱逐这些 pod 并使节点进入维护模式(禁止调度)。

```sh
# 将 NODE_NAME 换成 Master 节点名称
kubectl drain NODE_NAME --ignore-daemonsets
```

#### 3.2.3、查看升级计划

完成节点驱逐以后，可以通过以下命令查看升级计划；**升级计划中列出了升级期间要执行的所有步骤以及相关警告，一定要仔细查看。**

```sh
k8s16.node ➜  ~ kubeadm upgrade plan --config /etc/kubernetes/kubeadm.yaml
W0115 10:59:52.586204     983 validation.go:28] Cannot validate kube-proxy config - no validator is available
W0115 10:59:52.586241     983 validation.go:28] Cannot validate kubelet config - no validator is available
[upgrade/config] Making sure the configuration is correct:
W0115 10:59:52.605458     983 common.go:94] WARNING: Usage of the --config flag for reconfiguring the cluster during upgrade is not recommended!
W0115 10:59:52.607258     983 validation.go:28] Cannot validate kube-proxy config - no validator is available
W0115 10:59:52.607274     983 validation.go:28] Cannot validate kubelet config - no validator is available
[preflight] Running pre-flight checks.
[upgrade] Making sure the cluster is healthy:
[upgrade] Fetching available versions to upgrade to
[upgrade/versions] Cluster version: v1.17.0
[upgrade/versions] kubeadm version: v1.17.1

External components that should be upgraded manually before you upgrade the control plane with 'kubeadm upgrade apply':
COMPONENT   CURRENT   AVAILABLE
Etcd        3.3.18    3.4.3-0

Components that must be upgraded manually after you have upgraded the control plane with 'kubeadm upgrade apply':
COMPONENT   CURRENT       AVAILABLE
Kubelet     5 x v1.17.0   v1.17.1

Upgrade to the latest version in the v1.17 series:

COMPONENT            CURRENT   AVAILABLE
API Server           v1.17.0   v1.17.1
Controller Manager   v1.17.0   v1.17.1
Scheduler            v1.17.0   v1.17.1
Kube Proxy           v1.17.0   v1.17.1
CoreDNS              1.6.5     1.6.5

You can now apply the upgrade by executing the following command:

        kubeadm upgrade apply v1.17.1

_____________________________________________________________________
```

### 3.3、执行升级

确认好升级计划以后，只需要一条命令既可将当前 master 节点升级到目标版本

```sh
kubeadm upgrade apply v1.17.1 --config /etc/kubernetes/kubeadm.yaml
```

升级期间会打印很详细的日志，在日志中可以实时观察到升级流程，建议仔细关注升级流程；**在最后一步会有一条日志 `[addons] Applied essential addon: kube-proxy`，这意味着集群开始更新 `kube-proxy` 组件，该组件目前是通过 `daemonset` 方式启动的；这会意味着此时会造成全节点的 `kube-proxy` 更新；**理论上不会有很大影响，但是升级是还是需要注意一下这一步操作，在我的观察中似乎 `kube-proxy` 也是通过滚动更新完成的，所以问题应该不大。

### 3.4、升级 kubelet

在单个 master 上升级完成后，**只会升级本节点的 master 相关组件和全节点的 `kube-proxy` 组件；**由于 kubelet 是在宿主机安装的，所以需要通过包管理器手动升级 kubelet

```sh
# replace x in 1.17.x-00 with the latest patch version
apt-mark unhold kubelet
apt-get install -y kubelet=1.17.x-00
apt-mark hold kubelet
```

更新完成后执行 `systemctl restart kubelet` 重启，并等待启动成功既可；最后不要忘记解除当前节点的维护模式(`uncordon`)。

### 3.5、升级其他 Master

当其中一个 master 节点升级完成后，其他的 master 升级就会相对简单的多；**首先国际惯例升级一下 `kubeadm` 和 `kubectl` 软件包，然后直接在其他 master 节点执行 `kubeadm upgrade node` 既可。**由于 apiserver 等组件配置已经在升级第一个 master 时上传到了集群的 configMap 中，所以事实上其他 master 节点只是正常拉取然后重启相关组件既可；这一步同样会输出详细日志，可以仔细观察进度，**最后不要忘记升级之前先进入维护模式，升级完成后重新安装 `kubelet` 并关闭节点维护模式。**

## 四、升级 Node

node 节点的升级实际上在升级完 master 节点以后不需要什么特殊操作，node 节点唯一需要升级的就是 `kubelet` 组件；**首先在 node 节点执行 `kubeadm upgrade node` 命令，该命令会拉取集群内的 `kubelet` 配置文件，然后重新安装 `kubelet` 重启既可；**同样升级 node 节点时不要忘记开启维护模式。针对于 CNI 组件请按需手动升级，并且确认好 CNI 组件的兼容版本。

## 五、验证集群

所有组件升级完成后，可以通过 `kubectl describe POD_NAME` 的方式验证 master 组件是否都升级到了最新版本；通过 `kuebctl version` 命令验证 api 相关信息(HA rr 轮训模式下可以多执行几遍)；还有就是通过 `kubectl get node -o wide` 查看相关 node 的信息，确保 `kubelet` 都升级成功，同时全部节点维护模式都已经关闭，其他细节可以参考[官方文档](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade)。


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
