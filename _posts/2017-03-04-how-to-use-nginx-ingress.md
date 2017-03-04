---
layout: post
categories: Kubernetes Docker
title: Kubernetes Nginx Ingress 教程
date: 2017-03-04 23:16:36 +0800
description: Kubernetes Nginx Ingress 教程
keywords: Ingress Kubernetes Nginx
---

> 最近发现好多人问 Ingress，同时一直也没去用 Nginx 的 Ingress，索性鼓捣了一把，发现跟原来确实有了点变化，在这里写篇文章记录一下


### 一、Ingress 介绍

Kubernetes 暴露服务的方式目前只有三种：LoadBlancer Service、NodePort Service、Ingress；前两种估计都应该很熟悉，具体的可以参考下 [这篇文章](https://mritd.me/2016/12/06/try-traefik-on-kubernetes/)；下面详细的唠一下这个 Ingress

#### 1.1、Ingress 是个什么玩意

可能从大致印象上 Ingress 就是能利用 Nginx、Haproxy 啥的负载均衡器暴露集群内服务的工具；那么问题来了，集群内服务想要暴露出去面临着几个问题：

#### 1.2、Pod 漂移问题

众所周知 Kubernetes 具有强大的副本控制能力，能保证在任意副本(Pod)挂掉时自动从其他机器启动一个新的，还可以动态扩容等，总之一句话，这个 Pod 可能在任何时刻出现在任何节点上，也可能在任何时刻死在任何节点上；那么自然随着 Pod 的创建和销毁，Pod IP 肯定会动态变化；**那么如何把这个动态的 Pod IP 暴露出去？这里借助于 Kubernetes 的 Service 机制，Service 可以以标签的形式选定一组带有指定标签的 Pod，并监控和自动负载他们的 Pod IP，那么我们向外暴露只暴露 Service IP 就行了**；这就是 NodePort 模式：即在每个节点上开起一个端口，然后转发到内部 Service IP 上，如下图所示

![NodePort](https://mritd.b0.upaiyun.com/markdown/5a1i4.jpg)

#### 1.3、端口管理问题

采用 NodePort 方式暴露服务面临一个坑爹的问题是，服务一旦多起来，NodePort 在每个节点上开启的端口会及其庞大，而且难以维护；这时候引出的思考问题是 **"能不能使用 Nginx 啥的只监听一个端口，比如 80，然后按照域名向后转发？"** 这思路很好，简单的实现就是使用 DaemonSet 在每个 node 上监听 80，然后写好规则，**因为 Nginx 外面绑定了宿主机 80 端口(就像 NodePort)，本身又在集群内，那么向后直接转发到相应 Service IP 就行了**，如下图所示

![use nginx proxy](https://mritd.b0.upaiyun.com/markdown/rrcuu.jpg)

#### 1.4、域名分配及动态更新问题

从上面的思路，采用 Nginx 似乎已经解决了问题，但是其实这里面有一个很大缺陷：**每次有新服务加入怎么改 Nginx 配置？总不能手动改或者来个 Rolling Update 前端 Nginx Pod 吧？**这时候 "伟大而又正直勇敢的" Ingress 登场，**如果不算上面的 Nginx，Ingress 只有两大组件：Ingress Controller 和 Ingress**

Ingress 这个玩意，简单的理解就是 **你原来要改 Nginx 配置，然后配置各种域名对应哪个 Service，现在把这个动作抽象出来，变成一个 Ingress 对象，你可以用 yml 创建，每次不要去改 Nginx 了，直接改 yml 然后创建/更新就行了**；那么问题来了："Nginx 咋整？"

Ingress Controller 这东西就是解决 "Nginx 咋整" 的；**Ingress Controoler 通过与 Kubernetes API 交互，动态的去感知集群中 Ingress 规则变化，然后读取他，按照他自己模板生成一段 Nginx 配置，再写到 Nginx Pod 里，最后 reload 一下**，工作流程如下图

![Ingress](https://mritd.b0.upaiyun.com/markdown/e5fcy.jpg)

**当然在实际应用中，最新版本 Kubernetes 已经将 Nginx 与 Ingress Controller 合并为一个组件，所以 Nginx 无需单独部署，只需要部署 Ingress Controller 即可**

### 二、怼一个 Nginx Ingress

上面啰嗦了那么多，只是为了讲明白 Ingress 的各种理论概念，下面实际部署很简单

#### 2.1、部署默认后端

我们知道 **前端的 Nginx 最终要负载到后端 service 上，那么如果访问不存在的域名咋整？**官方给出的建议是部署一个 **默认后端**，对于未知请求全部负载到这个默认后端上；这个后端啥也不干，就是返回 404，部署如下

``` sh
➜  ~ kubectl create -f default-backend.yaml
deployment "default-http-backend" created
service "default-http-backend" created
```

这个 `default-backend.yaml` 文件可以在 [官方 Ingress 仓库](https://github.com/kubernetes/ingress/blob/master/examples/deployment/nginx/default-backend.yaml) 找到，由于篇幅限制这里不贴了，仓库位置如下

![default-backend](https://mritd.b0.upaiyun.com/markdown/1ct6w.jpg)

#### 2.2、部署 Ingress Controller

部署完了后端就得把最重要的组件 Nginx+Ingres Controller(官方统一称为 Ingress Controller) 部署上

``` sh
➜  ~ kubectl create -f nginx-ingress-controller.yaml
daemonset "nginx-ingress-lb" created
```

**注意：官方的 Ingress Controller 有个坑，至少我看了 DaemonSet 方式部署的有这个问题：没有绑定到宿主机 80 端口，也就是说前端 Nginx 没有监听宿主机 80 端口(这还玩个卵啊)；所以需要把配置搞下来自己加一下 `hostNetwork`**，截图如下

![add hostNetwork](https://mritd.b0.upaiyun.com/markdown/n1fsc.jpg)

同样配置文件自己找一下，地址 [点这里](https://github.com/kubernetes/ingress/blob/master/examples/daemonset/nginx/nginx-ingress-daemonset.yaml)，仓库截图如下

![Ingress Controller](https://mritd.b0.upaiyun.com/markdown/jirhn.jpg)

**当然它支持以 deamonset 的方式部署，这里用的就是(个人喜欢而已)，所以你发现我上面截图是 deployment，但是链接给的却是 daemonset，因为我截图截错了.....**

#### 2.3、部署 Ingress

**这个可就厉害了，这个部署完就能装逼了**

![daitouzhaungbi](https://mritd.b0.upaiyun.com/markdown/v450z.jpg)
![zhanxianjishu](https://mritd.b0.upaiyun.com/markdown/b1kz2.jpg)

**咳咳，回到正题，从上面可以知道 Ingress 就是个规则，指定哪个域名转发到哪个 Service，所以说首先我们得有个 Service，当然 Service 去哪找这里就不管了；这里默认为已经有了两个可用的 Service，以下以 Dashboard 和 kibana 为例**

**先写一个 Ingress 文件，语法格式啥的请参考 [官方文档](https://kubernetes.io/docs/user-guide/ingress)，由于我的 Dashboard 和 Kibana 都在 kube-system 这个命名空间，所以要指定 namespace**，写之前 Service 分布如下

![All Service](https://mritd.b0.upaiyun.com/markdown/vtg8f.jpg)

``` sh
vim dashboard-kibana-ingress.yml

apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: dashboard-kibana-ingress
  namespace: kube-system
spec:
  rules:
  - host: dashboard.mritd.me
    http:
      paths:
      - backend:
          serviceName: kubernetes-dashboard
          servicePort: 80
  - host: kibana.mritd.me
    http:
      paths:
      - backend:
          serviceName: kibana-logging
          servicePort: 5601
```

**装逼成功截图如下**

![Dashboard](https://mritd.b0.upaiyun.com/markdown/pyhdy.jpg)

![Kibana](https://mritd.b0.upaiyun.com/markdown/p3qli.jpg)

### 三、部署 Ingress TLS

上面已经搞定了 Ingress，下面就顺便把 TLS 怼上；官方给出的样例很简单，大致步骤就两步：**创建一个含有证书的 secret、在 Ingress 开启证书**；但是我不得不喷一下，文档就提那么一嘴，大坑一堆，比如多域名配置，还有下面这文档特么的是逗我玩呢？

![douniwan](https://mritd.b0.upaiyun.com/markdown/t3n1j.jpg)

#### 3.1、创建证书

首先第一步当然要有个证书，由于我这个 Ingress 有两个服务域名，所以证书要支持两个域名；生成证书命令如下：

``` sh
# 生成 CA 自签证书
mkdir cert && cd cert
openssl genrsa -out ca-key.pem 2048
openssl req -x509 -new -nodes -key ca-key.pem -days 10000 -out ca.pem -subj "/CN=kube-ca"

# 编辑 openssl 配置
cp /etc/pki/tls/openssl.cnf .
vim openssl.cnf

# 主要修改如下
[req]
req_extensions = v3_req # 这行默认注释关着的 把注释删掉
# 下面配置是新增的
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName = @alt_names
[alt_names]
DNS.1 = dashboard.mritd.me
DNS.2 = kibana.mritd.me

# 生成证书
openssl genrsa -out ingress-key.pem 2048
openssl req -new -key ingress-key.pem -out ingress.csr -subj "/CN=kube-ingress" -config openssl.cnf
openssl x509 -req -in ingress.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial -out ingress.pem -days 365 -extensions v3_req -extfile openssl.cnf
```

#### 3.2、创建 secret

创建好证书以后，需要将证书内容放到 secret 中，secret 中全部内容需要 base64 编码，然后注意去掉换行符(变成一行)；以下是我的 secret 样例(上一步中 ingress.pem 是证书，ingress-key.pem 是证书的 key)

``` sh
vim ingress-secret.yml

apiVersion: v1
data:
  tls.crt: LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUM5akNDQWQ2Z0F3SUJBZ0lKQU5TR2dNNnYvSVd5TUEwR0NTcUdTSWIzRFFFQkJRVUFNQkl4RURBT0JnTlYKQkFNTUIydDFZbVV0WTJFd0hoY05NVGN3TXpBME1USTBPRFF5V2hjTk1UZ3dNekEwTVRJME9EUXlXakFYTVJVdwpFd1lEVlFRRERBeHJkV0psTFdsdVozSmxjM013Z2dFaU1BMEdDU3FHU0liM0RRRUJBUVVBQTRJQkR3QXdnZ0VLCkFvSUJBUUM2dkNZRFhGSFpQOHI5Zk5jZXlkV015VVlELzAwQ2xnS0M2WjNpYWZ0QlRDK005TmcrQzloUjhJUE4KWW00cjZOMkw1MmNkcmZvQnBHZXovQVRIT0NJYUhJdlp1K1ZaTzNMZjcxZEVLR09nV21LMTliSVAzaGpSeDZhWQpIeGhEVWNab3ZzYWY1UWJHRnUydEF4L2doMTFMdXpTZWJkT0Y1dUMrWHBhTGVzWWdQUjhFS0cxS0VoRXBLMDFGCmc4MjhUU1g2TXVnVVZmWHZ1OUJRUXExVWw0Q2VMOXhQdVB5T3lMSktzbzNGOEFNUHFlaS9USWpsQVFSdmRLeFYKVUMzMnBtTHRlUFVBb2thNDRPdElmR3BIOTZybmFsMW0rMXp6YkdTemRFSEFaL2k1ZEZDNXJOaUthRmJnL2NBRwppalhlQ01xeGpzT3JLMEM4MDg4a0tjenJZK0JmQWdNQkFBR2pTakJJTUM0R0ExVWRFUVFuTUNXQ0VtUmhjMmhpCmIyRnlaQzV0Y21sMFpDNXRaWUlQYTJsaVlXNWhMbTF5YVhSa0xtMWxNQWtHQTFVZEV3UUNNQUF3Q3dZRFZSMFAKQkFRREFnWGdNQTBHQ1NxR1NJYjNEUUVCQlFVQUE0SUJBUUNFN1ByRzh6MytyaGJESC8yNGJOeW5OUUNyYVM4NwphODJUUDNxMmsxUUJ1T0doS1pwR1N3SVRhWjNUY0pKMkQ2ZlRxbWJDUzlVeDF2ckYxMWhGTWg4MU9GMkF2MU4vCm5hSU12YlY5cVhYNG16eGNROHNjakVHZ285bnlDSVpuTFM5K2NXejhrOWQ1UHVaejE1TXg4T3g3OWJWVFpkZ0sKaEhCMGJ5UGgvdG9hMkNidnBmWUR4djRBdHlrSVRhSlFzekhnWHZnNXdwSjlySzlxZHd1RHA5T3JTNk03dmNOaQpseWxDTk52T3dNQ0h3emlyc01nQ1FRcVRVamtuNllLWmVsZVY0Mk1yazREVTlVWFFjZ2dEb1FKZEM0aWNwN0sxCkRPTDJURjFVUGN0ODFpNWt4NGYwcUw1aE1sNGhtK1BZRyt2MGIrMjZjOVlud3ROd24xdmMyZVZHCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0K
  tls.key: LS0tLS1CRUdJTiBSU0EgUFJJVkFURSBLRVktLS0tLQpNSUlFb3dJQkFBS0NBUUVBdXJ3bUExeFIyVC9LL1h6WEhzblZqTWxHQS85TkFwWUNndW1kNG1uN1FVd3ZqUFRZClBndllVZkNEeldKdUsramRpK2RuSGEzNkFhUm5zL3dFeHpnaUdoeUwyYnZsV1R0eTMrOVhSQ2hqb0ZwaXRmV3kKRDk0WTBjZW1tQjhZUTFIR2FMN0duK1VHeGhidHJRTWY0SWRkUzdzMG5tM1RoZWJndmw2V2kzckdJRDBmQkNodApTaElSS1N0TlJZUE52RTBsK2pMb0ZGWDE3N3ZRVUVLdFZKZUFuaS9jVDdqOGpzaXlTcktOeGZBREQ2bm92MHlJCjVRRUViM1NzVlZBdDlxWmk3WGoxQUtKR3VPRHJTSHhxUi9lcTUycGRadnRjODJ4a3MzUkJ3R2Y0dVhSUXVhelkKaW1oVzRQM0FCb28xM2dqS3NZN0RxeXRBdk5QUEpDbk02MlBnWHdJREFRQUJBb0lCQUJtRmIzaVVISWVocFYraAp1VkQyNnQzVUFHSzVlTS82cXBzenpLVk9NTTNLMk5EZUFkUHhFSDZhYlprYmM4MUNoVTBDc21BbkQvMDdlQVRzClU4YmFrQ2FiY2kydTlYaU5uSFNvcEhlblFYNS8rKys4aGJxUGN6cndtMzg4K0xieXJUaFJvcG5sMWxncWVBOW0KVnV2NzlDOU9oYkdGZHh4YzRxaUNDdmRETDJMbVc2bWhpcFRKQnF3bUZsNUhqeVphdGcyMVJ4WUtKZ003S1p6TAplYWU0bTJDR3R0bmNyUktodklaQWxKVmpyRWoxbmVNa3RHODFTT3QyN0FjeDRlSnozbmcwbjlYSmdMMHcwU05ZCmlwd3I5Uk5PaDkxSGFsQ3JlWVB3bDRwajIva0JIdnozMk9Qb2FOSDRQa2JaeTEzcks1bnFrMHBXdUthOEcyY00KLzY4cnQrRUNnWUVBN1NEeHRzRFFBK2JESGdUbi9iOGJZQ3VhQ2N4TDlObHIxd2tuTG56VVRzRnNkTDByUm1uZAp5bWQ4aU95ME04aUVBL0xKb3dPUGRRY240WFdWdS9XbWV5MzFVR2NIeHYvWlVSUlJuNzgvNmdjZUJSNzZJL2FzClIrNVQ1TEMyRmducVd2MzMvdG0rS0gwc0J4dEM3U2tSK3Y2UndVQk1jYnM3c0dUQlR4NVV2TkVDZ1lFQXlaaUcKbDBKY0dzWHhqd1JPQ0FLZytEMlJWQ3RBVmRHbjVMTmVwZUQ4bFNZZ3krZGxQaCt4VnRiY2JCV0E3WWJ4a1BwSAorZHg2Z0p3UWp1aGN3U25uOU9TcXRrZW04ZmhEZUZ2MkNDbXl4ZlMrc1VtMkxqVzM1NE1EK0FjcWtwc0xMTC9GCkIvK1JmcmhqZW5lRi9BaERLalowczJTNW9BR0xRVFk4aXBtM1ZpOENnWUJrZGVHUnNFd3dhdkpjNUcwNHBsODkKdGhzemJYYjhpNlJSWE5KWnNvN3JzcXgxSkxPUnlFWXJldjVhc0JXRUhyNDNRZ1BFNlR3OHMwUmxFMERWZWJRSApXYWdsWVJEOWNPVXJvWFVYUFpvaFZ0U1VETlNpcWQzQk42b1pKL2hzaTlUYXFlQUgrMDNCcjQ0WWtLY2cvSlplCmhMMVJaeUU3eWJ2MjlpaWprVkVMRVFLQmdRQ2ZQRUVqZlNFdmJLYnZKcUZVSm05clpZWkRpNTVYcXpFSXJyM1cKSEs2bVNPV2k2ZlhJYWxRem1hZW1JQjRrZ0hDUzZYNnMyQUJUVWZLcVR0UGxKK3EyUDJDd2RreGgySTNDcGpEaQpKYjIyS3luczg2SlpRY2t2cndjVmhPT1Z4YTIvL1FIdTNXblpSR0FmUGdXeEcvMmhmRDRWN1R2S0xTNEhwb1dQCm5QZDV0UUtCZ0QvNHZENmsyOGxaNDNmUWpPalhkV0ZTNzdyVFZwcXBXMlFoTDdHY0FuSXk5SDEvUWRaOXYxdVEKNFBSanJseEowdzhUYndCeEp3QUtnSzZmRDBXWmZzTlRLSG01V29kZUNPWi85WW13cmpPSkxEaUU3eFFNWFBzNQorMnpVeUFWVjlCaDI4cThSdnMweHplclQ1clRNQ1NGK0Q5NHVJUmkvL3ZUMGt4d05XdFZxCi0tLS0tRU5EIFJTQSBQUklWQVRFIEtFWS0tLS0tCg==
kind: Secret
metadata:
  name: ingress-secret
  namespace: kube-system
type: Opaque
```

**创建完成后 create 一下就可**

``` sh
➜  ~ kubectl create -f ingress-secret.yml
secret "ingress-secret" created
```

**其实这个配置比如证书转码啥的没必要手动去做，可以直接使用下面的命令创建，这里写这么多只是为了把步骤写清晰**

``` sh
kubectl create secret tls ingress-secret --key cert/ingress-key.pem --cert cert/ingress.pem
```

#### 3.3、重新部署 Ingress

生成完成后需要在 Ingress 中开启 TLS，Ingress 修改后如下

``` sh
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: dashboard-kibana-ingress
  namespace: kube-system
spec:
  tls:
  - hosts:
    - dashboard.mritd.me
    - kibana.mritd.me
    secretName: ingress-secret
  rules:
  - host: dashboard.mritd.me
    http:
      paths:
      - backend:
          serviceName: kubernetes-dashboard
          servicePort: 80
  - host: kibana.mritd.me
    http:
      paths:
      - backend:
          serviceName: kibana-logging
          servicePort: 5601
```

**注意：一个 Ingress 只能使用一个 secret(secretName 段只能有一个)，也就是说只能用一个证书，更直白的说就是如果你在一个 Ingress 中配置了多个域名，那么使用 TLS 的话必须保证证书支持该 Ingress 下所有域名；并且这个 `secretName` 一定要放在上面域名列表最后位置，否则会报错 `did not find expected key` 无法创建；同时上面的 `hosts` 段下域名必须跟下面的 `rules` 中完全匹配**

**更需要注意一点：之所以这里单独开一段就是因为有大坑；Kubernetes Ingress 默认情况下，当你不配置证书时，会默认给你一个 TLS 证书的，也就是说你 Ingress 中配置错了，比如写了2个 `secretName`、或者 `hosts` 段中缺了某个域名，那么对于写了多个 `secretName` 的情况，所有域名全会走默认证书；对于 `hosts` 缺了某个域名的情况，缺失的域名将会走默认证书，部署时一定要验证一下证书，不能 "有了就行"；更新 Ingress 证书可能需要等一段时间才会生效**

最后重新部署一下即可

``` sh
➜  ~ kubectl delete -f dashboard-kibana-ingress.yml
ingress "dashboard-kibana-ingress" deleted
➜  ~ kubectl create -f dashboard-kibana-ingress.yml
ingress "dashboard-kibana-ingress" created
```

**注意：部署 TLS 后 80 端口会自动重定向到 443**，最终访问截图如下

![Ingress TLS](https://mritd.b0.upaiyun.com/markdown/6o0pj.jpg)

![Ingress TLS Certificate](https://mritd.b0.upaiyun.com/markdown/2ch1k.jpg)

**历时 5 个小时鼓捣，到此结束**

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
