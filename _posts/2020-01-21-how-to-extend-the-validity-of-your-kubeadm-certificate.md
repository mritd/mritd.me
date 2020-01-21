---
layout: post
categories: Kubernetes
title: kubeadm 证书期限调整
date: 2020-01-21 21:38:01 +0800
description: kubeadm 证书期限调整
keywords: kubernetes,kubeadm,certificate
catalog: true
multilingual: false
tags: Kubernetes
---

> 最近 kubeadm HA 的集群折腾完了，发现集群证书始终是 1 年有效期，然后自己还有点子担心；无奈只能研究一下源码一探究竟了...

## 一、证书管理

kubeadm 集群安装完成后，证书管理上实际上大致是两大类型:

- 自动滚动续期
- 手动定期续期

自动滚动续期类型的证书目前从我所阅读文档和实际测试中目前只有 kubelet 的 client 证书；kubelet client 证书自动滚动涉及到了 [TLS bootstrapping](https://kubernetes.io/docs/reference/command-line-tools-reference/kubelet-tls-bootstrapping/) 部份，**其核心由两个 ClusterRole 完成(`system:certificates.k8s.io:certificatesigningrequests:nodeclient` 和 `system:certificates.k8s.io:certificatesigningrequests:selfnodeclient`)，针对这两个 ClusterRole kubeadm 在引导期间创建了 [bootstrap token](https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details/#create-a-bootstrap-token) 来完成引导期间证书签发(该 Token 24h 失效)，后续通过预先创建的 ClusterRoleBinding(`kubeadm:node-autoapprove-bootstrap` 和 `kubeadm:node-autoapprove-certificate-rotation`) 完成自动的 node 证书续期；**kubelet client 证书续期部份涉及到 TLS bootstrapping 太多了，有兴趣的可以仔细查看(最后还是友情提醒: **用 kubeadm 一定要看看 [Implementation details](https://kubernetes.io/docs/reference/setup-tools/kubeadm/implementation-details)**)。

手动续期的证书目前需要在到期前使用 kubeadm 命令自行续期，这些证书目前可以通过以下命令列出

```sh
# 不要在意我的证书过期时间是 10 年，下面会说
k1.node ➜ kubeadm alpha certs check-expiration
[check-expiration] Reading configuration from the cluster...
[check-expiration] FYI: You can look at this config file with 'kubectl -n kube-system get cm kubeadm-config -oyaml'

CERTIFICATE                EXPIRES                  RESIDUAL TIME   CERTIFICATE AUTHORITY   EXTERNALLY MANAGED
admin.conf                 Dec 06, 2029 20:58 UTC   9y                                      no
apiserver                  Dec 06, 2029 20:59 UTC   9y              ca                      no
apiserver-kubelet-client   Dec 06, 2029 20:59 UTC   9y              ca                      no
controller-manager.conf    Dec 06, 2029 20:59 UTC   9y                                      no
front-proxy-client         Dec 06, 2029 20:59 UTC   9y              front-proxy-ca          no
scheduler.conf             Dec 06, 2029 20:59 UTC   9y                                      no

CERTIFICATE AUTHORITY   EXPIRES                  RESIDUAL TIME   EXTERNALLY MANAGED
ca                      Jan 13, 2030 08:45 UTC   9y              no
front-proxy-ca          Jan 13, 2030 08:45 UTC   9y              no
```

## 二、证书期限调整

上面已经提到了，手动管理部份的证书需要自己用命令续签(`kubeadm alpha certs renew all`)，而且你会发现续签以后有效期还是 1 年；kubeadm 的初衷是 **"为快速创建 kubernetes 集群的最佳实践"**，当然最佳实践包含确保证书安全性，毕竟 Let's Encrypt 的证书有效期只有 3 个月的情况下 kubeadm 有效期有 1 年已经很不错了；但是对于最佳实践来说，我们公司的集群安全性并不需要那么高，一年续期一次无疑在增加运维人员心智负担(它并不最佳)，所以我们迫切需要一种 "一劳永逸" 的解决方案；当然我目前能想到的就是找到证书签发时在哪设置的有效期，然后想办法改掉它。

### 2.1、源码分析

目前通过宏观角度看整个 kubeadm 集群搭建过程，其中涉及到证书签署大致有两大部份: init  阶段和后期 renew，下面开始分析两个阶段的源码

#### 2.1.1、init 阶段

由于 kubernetes 整个命令行都是通过 cobra 库构建的，那么根据这个库的习惯首先直接从 `cmd` 包开始翻，而 kubernetes 源码组织的又比较清晰进而直接定位到 kubeadm 命令包下面；接着打开 `app` 目录一眼就看到了 `phases`... `phases` 顾名思义啊，整个 init 都是通过不同的 `phases` 完成的，那么直接去 `phases` 包下面找证书阶段的源码既可

![init_source](http://cdn.oss.link/markdown/ssdo7.jpg)

进入到这个 `certs.go` 里面，直接列出所有方法，go 的规范里只有首字母大写才会被暴露出去，那么我们直接查看这些方法名既可；从名字上很轻松的看到了这个方法...基本上就是它了

![certs.go](http://cdn.oss.link/markdown/uoqx4.jpg)

通过这个方法的代码会发现最终还是调用了 `certSpec.CreateFromCA(cfg, caCert, caKey)`，那么接着看看这个方法

![pkiutil.NewCertAndKey](http://cdn.oss.link/markdown/psrho.jpg)

通过这个方法继续往下翻发现调用了 `pkiutil.NewCertAndKey(caCert, caKey, cfg)`，这个方法里最终调用了 `NewSignedCert(config, key, caCert, caKey)`

![NewSignedCert](http://cdn.oss.link/markdown/nel5u.jpg)

从 `NewSignedCert` 方法里看到证书有效期实际上是个常量，**那也就意味着我改了这个常量 init 阶段的证书有效期八九不离十的就变了，再通过包名看这个是个 `pkiutil`... `xxxxxutil` 明显是公共的，所以推测改了它 renew 阶段应该也会变**

![CertificateValidity](http://cdn.oss.link/markdown/t3amy.jpg)

#### 2.1.2、renew 阶段

renew 阶段也是老套路，不过稳妥点先从 cmd 找起来，所以先看 `alpha` 包下的 `certs.go`；这时候方法名语义清晰就很有好处，一下就能找到 `newCmdCertsRenewal` 方法

![alpha_certs.go](http://cdn.oss.link/markdown/amupo.jpg)

而这个 `newCmdCertsRenewal` 方法实际上没啥实现，所以目测实现是从 `getRenewSubCommands` 实现的

![getRenewSubCommands](http://cdn.oss.link/markdown/8c38y.jpg)

看了 `getRenewSubCommands` 以后发现上面全是命令行库、配置文件参数啥的处理，核心在 `renewCert` 上，从这个方法里发现还有意外收获: **renew 时实际上分两种情况处理，一种是使用了 `--use-api` 选项，另一种是未使用**；当然根据上面的命令来说我们没使用，那么看 else 部份就行了(没看源码之前我特么居然没看 `--help` 不知道有这个选项)

![renewCert](http://cdn.oss.link/markdown/9zsgp.jpg)

else 部份源码最终还是调用了 `RenewUsingLocalCA` 方法，这个方法一直往下跟会有一个 `Renew` 方法

![Renew](http://cdn.oss.link/markdown/s3a5c.jpg)

这个方法一点进去... **我上面的想法是对的**

![FileRenewer_Renew](http://cdn.oss.link/markdown/08cnb.jpg)

#### 2.1.3、其他推测

根据刚刚查看代码可以看到在 renew 阶段判断了 `--use-api` 选项是否使用，通过跟踪源码发现最终会调用到 `RenewUsingCSRAPI` 方法上，`RenewUsingCSRAPI` 会调用集群 CSR Api 执行证书签署

![RenewUsingCSRAPI](http://cdn.oss.link/markdown/xivs9.png)

有了这个发现后基本上可以推测出这一步通过集群完成，那么按理说是应该受到 `kube-controller-manager` 组件的 `--experimental-cluster-signing-duration` 影响。

### 2.2、测试验证

#### 2.2.1、验证修改源码

想验证修改源码是否有效只需要修改源码重新 build 出 kubeadm 命令，然后使用这个特定版本的 kubeadm renew 证书测试既可，源码调整的位置如下

![update_source](http://cdn.oss.link/markdown/qaavr.png)

然后命令行下执行 `make cross` 进行跨平台交叉编译(如果过你在 linux amd64 平台下则直接 `make` 既可)

```sh
➜  kubernetes git:(v1.17.4) ✗ make cross
grep: /proc/meminfo: No such file or directory
grep: /proc/meminfo: No such file or directory
+++ [0116 23:43:19] Multiple platforms requested and available 64G >= threshold 40G, building platforms in parallel
+++ [0116 23:43:19] Building go targets for {linux/amd64 linux/arm linux/arm64 linux/s390x linux/ppc64le} in parallel (output will appear in a burst when complete):
    cmd/kube-proxy
    cmd/kube-apiserver
    cmd/kube-controller-manager
    cmd/kubelet
    cmd/kubeadm
    cmd/kube-scheduler
    vendor/k8s.io/apiextensions-apiserver
    cluster/gce/gci/mounter
+++ [0116 23:43:19] linux/amd64: build started
+++ [0116 23:47:24] linux/amd64: build finished
+++ [0116 23:43:19] linux/arm: build started
+++ [0116 23:47:23] linux/arm: build finished
+++ [0116 23:43:19] linux/arm64: build started
+++ [0116 23:47:23] linux/arm64: build finished
+++ [0116 23:43:19] linux/s390x: build started
+++ [0116 23:47:24] linux/s390x: build finished
+++ [0116 23:43:19] linux/ppc64le: build started
+++ [0116 23:47:24] linux/ppc64le: build finished
grep: /proc/meminfo: No such file or directory
grep: /proc/meminfo: No such file or directory
+++ [0116 23:47:52] Multiple platforms requested and available 64G >= threshold 40G, building platforms in parallel
+++ [0116 23:47:52] Building go targets for {linux/amd64 linux/arm
# ... 省略编译日志
```

编译完成后能够在 `_output/local/bin/linux/amd64` 下找到刚刚编译成功的 `kubeadm` 文件，将编译好的 kubeadm scp 到已经存在集群上执行 renew，然后查看证书时间

![kubeadm_renew](http://cdn.oss.link/markdown/i3laa.png)

**经过测试后确认源码修改方式有效**

#### 2.2.2、验证调整 CSR API

根据推测当使用 `--use-api` 会受到 `kube-controller-manager` 组件的 `--experimental-cluster-signing-duration` 影响，从而从集群中下发证书；所以首先在启动集群时需要将 `--experimental-cluster-signing-duration` 调整为 10 年，然后再进行测试

```yaml
controllerManager:
  extraArgs:
    v: "4"
    node-cidr-mask-size: "19"
    deployment-controller-sync-period: "10s"
    # 在 kubeadm 配置文件中设置证书有效期为 10 年
    experimental-cluster-signing-duration: "86700h"
    node-monitor-grace-period: "20s"
    pod-eviction-timeout: "2m"
    terminated-pod-gc-threshold: "30"
```

然后使用 `--use-api` 选项进行 renew

```sh
kubeadm alpha certs renew all --use-api
```

此时会发现日志中打印出 `[certs] Certificate request "kubeadm-cert-kubernetes-admin-648w4" created` 字样，接下来从 `kube-system` 的 namespace 中能够看到相关 csr

![list_csr](https://cdn.oss.link/markdown/54awl.png)

这时我们开始手动批准证书，每次批准完成一个 csr，紧接着 kubeadm 会创建另一个 csr

![approve_csr](https://cdn.oss.link/markdown/tdde7.png)

当所有 csr 被批准后，再次查看集群证书发现证书期限确实被调整了

![success](https://cdn.oss.link/markdown/081qe.png)

## 三、总结

总结一下，调整 kubeadm 证书期限有两种方案；第一种直接修改源码，耗时耗力还得会 go，最后还要跑跨平台编译(很耗时)；第二种在启动集群时调整 `kube-controller-manager` 组件的 `--experimental-cluster-signing-duration` 参数，集群创建好后手动 renew 一下并批准相关 csr。

两种方案各有利弊，修改源码方式意味着在 client 端签发处理，不会对集群产生永久性影响，也就是说哪天你想 "反悔了" 你不需要修改集群什么配置，直接用官方 kubeadm renew 一下就会变回一年期限的证书；改集群参数实现的方式意味着你不需要懂 go 代码，只需要常规的集群配置既可实现，同时你也不需要跑几十分钟的交叉编译，不需要为编译过程中的网络问题而烦恼；所以最后使用哪种方案因人因情况而定吧。


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
