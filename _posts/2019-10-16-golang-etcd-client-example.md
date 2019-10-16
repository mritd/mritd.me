---
layout: post
categories: Golang
title: Golang Etcd client example
date: 2019-10-16 10:59:03 +0800
description: Golang Etcd client example
keywords: etcd,example
catalog: true
multilingual: false
tags: Golang
---

> 准备开发点东西，需要用到 Etcd，由于生产 Etcd 全部开启了 TLS 加密，所以客户端需要相应修改，以下为 Golang 链接 Etcd 并且使用客户端证书验证的样例代码


## API V2

``` golang
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"io/ioutil"
	"log"
	"net"
	"net/http"
	"time"

	"go.etcd.io/etcd/client"
)

func main() {

	// 为了保证 HTTPS 链接可信，需要预先加载目标证书签发机构的 CA 根证书
	etcdCA, err := ioutil.ReadFile("/Users/mritd/tmp/etcd_ssl/etcd-root-ca.pem")
	if err != nil {
		log.Fatal(err)
	}

	// etcd 启用了双向 TLS 认证，所以客户端证书同样需要加载
	etcdClientCert, err := tls.LoadX509KeyPair("/Users/mritd/tmp/etcd_ssl/etcd.pem", "/Users/mritd/tmp/etcd_ssl/etcd-key.pem")
	if err != nil {
		log.Fatal(err)
	}

	// 创建一个空的 CA Pool
	// 因为后续只会链接 Etcd 的 api 端点，所以此处选择使用空的 CA Pool，然后只加入 Etcd CA 既可
	// 如果期望链接其他 TLS 端点，那么最好使用 x509.SystemCertPool() 方法先 copy 一份系统根 CA
	// 然后再向这个 Pool 中添加自定义 CA
	rootCertPool := x509.NewCertPool()
	rootCertPool.AppendCertsFromPEM(etcdCA)

	cfg := client.Config{
		// Etcd HTTPS api 端点
		Endpoints: []string{"https://172.16.14.114:2379"},
		// 自定义 Transport 实现自签 CA 加载以及 Client Cert 加载
		// 其他参数最好从 client.DefaultTranspor copy，以保证与默认 client 相同的行为
		Transport: &http.Transport{
			Proxy: http.ProxyFromEnvironment,
			// Dial 方法已被启用，采用新的 DialContext 设置超时
			DialContext: (&net.Dialer{
				KeepAlive: 30 * time.Second,
				Timeout:   30 * time.Second,
			}).DialContext,
			// 自定义 CA 及 Client Cert 配置
			TLSClientConfig: &tls.Config{
				RootCAs:      rootCertPool,
				Certificates: []tls.Certificate{etcdClientCert},
			},
			TLSHandshakeTimeout: 10 * time.Second,
		},
		// set timeout per request to fail fast when the target endpoint is unavailable
		HeaderTimeoutPerRequest: time.Second,
	}
	c, err := client.New(cfg)
	if err != nil {
		log.Fatal(err)
	}
	kapi := client.NewKeysAPI(c)
	// set "/foo" key with "bar" value
	log.Print("Setting '/foo' key with 'bar' value")
	resp, err := kapi.Set(context.Background(), "/foo", "bar", nil)
	if err != nil {
		log.Fatal(err)
	} else {
		// print common key info
		log.Printf("Set is done. Metadata is %q\n", resp)
	}
	// get "/foo" key's value
	log.Print("Getting '/foo' key value")
	resp, err = kapi.Get(context.Background(), "/foo", nil)
	if err != nil {
		log.Fatal(err)
	} else {
		// print common key info
		log.Printf("Get is done. Metadata is %q\n", resp)
		// print value
		log.Printf("%q key has %q value\n", resp.Node.Key, resp.Node.Value)
	}
}
```

## API V3

``` golang
package main

import (
	"context"
	"crypto/tls"
	"crypto/x509"
	"io/ioutil"
	"log"
	"time"

	"go.etcd.io/etcd/clientv3"
)

func main() {

	// 为了保证 HTTPS 链接可信，需要预先加载目标证书签发机构的 CA 根证书
	etcdCA, err := ioutil.ReadFile("/Users/mritd/tmp/etcd_ssl/etcd-root-ca.pem")
	if err != nil {
		log.Fatal(err)
	}

	// etcd 启用了双向 TLS 认证，所以客户端证书同样需要加载
	etcdClientCert, err := tls.LoadX509KeyPair("/Users/mritd/tmp/etcd_ssl/etcd.pem", "/Users/mritd/tmp/etcd_ssl/etcd-key.pem")
	if err != nil {
		log.Fatal(err)
	}

	// 创建一个空的 CA Pool
	// 因为后续只会链接 Etcd 的 api 端点，所以此处选择使用空的 CA Pool，然后只加入 Etcd CA 既可
	// 如果期望链接其他 TLS 端点，那么最好使用 x509.SystemCertPool() 方法先 copy 一份系统根 CA
	// 然后再向这个 Pool 中添加自定义 CA
	rootCertPool := x509.NewCertPool()
	rootCertPool.AppendCertsFromPEM(etcdCA)

	// 创建 api v3 的 client
	cli, err := clientv3.New(clientv3.Config{
		// etcd https api 端点
		Endpoints:   []string{"https://172.16.14.114:2379"},
		DialTimeout: 5 * time.Second,
		// 自定义 CA 及 Client Cert 配置
		TLS: &tls.Config{
			RootCAs:      rootCertPool,
			Certificates: []tls.Certificate{etcdClientCert},
		},
	})
	if err != nil {
		log.Fatal(err)
	}
	defer func() { _ = cli.Close() }()

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	putResp, err := cli.Put(ctx, "sample_key", "sample_value")
	if err != nil {
		log.Fatal(err)
	} else {
		log.Println(putResp)
	}
	cancel()

	ctx, cancel = context.WithTimeout(context.Background(), 3*time.Second)
	delResp, err := cli.Delete(ctx, "sample_key")
	if err != nil {
		log.Fatal(err)
	} else {
		log.Println(delResp)
	}
	cancel()
}
```

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
