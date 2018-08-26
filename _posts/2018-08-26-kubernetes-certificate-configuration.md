---
layout: post
categories: Kubernetes
title: Kubernetes 证书配置
date: 2018-08-26 22:54:16 +0800
description: Kubernetes 证书配置
keywords: kubernetes,证书
catalog: true
multilingual: false
tags: Kubernetes
---

> 一直以来自己的 Kubernetes 集群大部分证书配置全部都在使用一个 CA，而事实上很多教程也没有具体的解释过这些证书代表的作用以及含义；今天索性仔细的翻了翻，顺便看到了一篇老外的文章，感觉写的不错，这里顺带着自己的理解总结一下。

## 一、Kubernetes 证书分类

这里的证书分类只是我自己定义的一种 "并不 ok" 的概念；从整体的作用上 Kubernetes 证书大致上应当分为两类:

- API Server 用于校验请求合法性证书
- 对其他敏感信息进行签名的证书(如 Service Account)

对于 API Server 用于检验请求合法性的证书配置一般会在 API Server 中配置好，而对其他敏感信息签名加密的证书一般会可能放在 Controller Manager 中配置，也可能还在 API Server，具体不同版本需要撸文档

另外需要明确的是: **Kubernetes 中 CA 证书并不一定只有一个，很多证书配置实际上是不相干的，只是大家为了方便普遍选择了使用一个 CA 进行签发；同时有一些证书如果不设置也会自动默认一个，就目前我所知的大约有 5 个可以完全不同的证书签发体系(或者说由不同的 CA 签发)**

## 二、API Server 中的证书配置

### 2.1、API Server 证书
API Server 证书配置中最应当明确的两个选项应该是以下两个:

```sh
--tls-cert-file string
    File containing the default x509 Certificate for HTTPS. (CA cert, if any, concatenated after server cert). If HTTPS serving is enabled, and --tls-cert-file and --tls-private-key-file are not provided, a self-signed certificate and key are generated for the public address and saved to the directory specified by --cert-dir.

--tls-private-key-file string
    File containing the default x509 private key matching --tls-cert-file.
```

从描述上就可以看出，这两个选项配置的就是 API Server HTTPS 端点应当使用的证书

### 2.2、Client CA 证书

接下来就是我们常见的 CA 配置:

```sh
--client-ca-file string
    If set, any request presenting a client certificate signed by one of the authorities in the client-ca-file is authenticated with an identity corresponding to the CommonName of the client certificate.
```

该配置明确了 Clent 连接 API Server 时，API Server 应当确保其证书源自哪个 CA 签发；如果其证书不是由该 CA 签发，则拒绝请求；事实上，这个 CA 不必与 HTTPS 端点所使用的证书 CA 相同；同时这里的 Client 是一个泛指的，可以是 kubectl，也可能是你自己开发的应用

### 2.3、请求头证书

由于 API Server 是支持多种认证方式的，其中一种就是使用 HTTP 头中的指定字段来进行认证，相关配置如下:

``` sh
--requestheader-allowed-names stringSlice
    List of client certificate common names to allow to provide usernames in headers specified by --requestheader-username-headers. If empty, any client certificate validated by the authorities in --requestheader-client-ca-file is allowed.
--requestheader-client-ca-file string
    Root certificate bundle to use to verify client certificates on incoming requests before trusting usernames in headers specified by --requestheader-username-headers. WARNING: generally do not depend on authorization being already done for incoming requests.
```

当指定这个 CA 证书后，则 API Server 使用 HTTP 头进行认证时会检测其 HTTP 头中发送的证书是否由这个 CA 签发；同样它也可独立于其他 CA(可以是个独立的 CA)；具体可以参考 [Authenticating Proxy](https://kubernetes.io/docs/reference/access-authn-authz/authentication/#authenticating-proxy)

### 2.4、Kubelet 证书

对于 Kubelet 组件，API Server 单独提供了证书配置选项，同时 Kubelet 组件也提供了反向设置的相关选项:

```sh
# API Server
--kubelet-certificate-authority string
    Path to a cert file for the certificate authority.
--kubelet-client-certificate string
    Path to a client cert file for TLS.
--kubelet-client-key string
    Path to a client key file for TLS.

# Kubelet
--client-ca-file string
    If set, any request presenting a client certificate signed by one of the authorities in the client-ca-file is authenticated with an identity corresponding to the CommonName of the client certificate.
--tls-cert-file string
    File containing x509 Certificate used for serving HTTPS (with intermediate certs, if any, concatenated after server cert). If --tls-cert-file and --tls-private-key-file are not provided, a self-signed certificate and key are generated for the public address and saved to the directory passed to --cert-dir.
--tls-private-key-file string
    File containing x509 private key matching --tls-cert-file.
```

相信这个配置不用多说就能猜到，这个就是用于指定 API Server 与 Kubelet 通讯所使用的证书以及其签署的 CA；同样这个 CA 可以完全独立与上述其他CA

## 三、Service Account 证书

在 API Server 配置中，对于 Service Account 同样有两个证书配置:

```sh
--service-account-key-file stringArray
    File containing PEM-encoded x509 RSA or ECDSA private or public keys, used to verify ServiceAccount tokens. The specified file can contain multiple keys, and the flag can be specified multiple times with different files. If unspecified, --tls-private-key-file is used. Must be specified when --service-account-signing-key is provided
--service-account-signing-key-file string
    Path to the file that contains the current private key of the service account token issuer. The issuer will sign issued ID tokens with this private key. (Requires the 'TokenRequest' feature gate.)
```

这两个配置描述了对 Service Account 进行签名验证时所使用的证书；不过需要注意的是这里并没有明确要求证书 CA，所以这两个证书的 CA 理论上也是可以完全独立的；至于未要求 CA 问题，可能是由于 jwt 库并不支持 CA 验证

## 四、总结

Kubernetes 中大部分证书都是用于 API Server 各种鉴权使用的；在不同鉴权方案或者对象上实际证书体系可以完全不同；具体是使用多个 CA 好还是都用一个，取决于集群规模、安全性要求等等因素，至少目前来说没有明确的那个好与不好

最后，嗯...吹牛逼就吹到这，有点晚了，得睡觉了...

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
