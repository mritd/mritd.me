---
layout: post
categories: Golang
title: 如何编写一个 CoreDNS 插件
date: 2019-11-05 20:55:53 +0800
description: 如何编写一个 CoreDNS 插件
keywords: coredns
catalog: true
multilingual: false
tags: Golang
---

> 目前测试环境中有很多个 DNS 服务器，不同项目组使用的 DNS 服务器不同，但是不可避免的他们会访问一些公共域名；老的 DNS 服务器都是 dnsmasq，改起来很麻烦，最近研究了一下 CoreDNS，通过编写插件的方式可以实现让多个 CoreDNS 实例实现分布式的统一控制，以下记录了插件编写过程

## 一、CoreDNS 简介

CoreDNS 目前是 CNCF 旗下的项目(已毕业)，为 Kubernetes 等云原生环境提供可靠的 DNS 服务发现等功能；官网的描述只有一句话: **CoreDNS: DNS and Service Discovery**，而实际上分析源码以后发现 CoreDNS 实际上是基于 Caddy (一个现代化的负载均衡器)而开发的，通过插件式注入，并监听 TCP/UDP 端口提供 DNS 服务；**得益于 Caddy 的插件机制，CoreDNS 支持自行编写插件，拦截 DNS 请求然后处理，**通过这个插件机制你可以在 CoreDNS 上实现各种功能，比如构建分布式一致性的 DNS 集群、动态的 DNS 负载均衡等等

## 二、CoreDNS 插件规范

### 2.1、插件模式

CoreDNS 插件编写目前有两种方式:

- 深度耦合 CoreDNS，使用 Go 编写插件，直接编译进 CoreDNS 二进制文件
- 通过 GRPC 解耦，任意语言编写 GRPC 接口实现，CoreDNS 通过 GRPC 与插件交互

由于 GRPC 链接实际上借助于 CoreDNS 的 GRPC 插件，同时 GRPC 会有网络开销，TCP 链接不稳定可能造成 DNS 响应过慢等问题，所以本文只介绍如何使用 Go 编写 CoreDNS 的插件，这种插件将直接编译进 CoreDNS 二进制文件中

### 2.2、插件注册

在通常情况下，插件中应当包含一个 `setup.go` 文件，这个文件的 `init` 方法调用插件注册，类似这样

``` golang
func init() { 
    plugin.Register("gdns", setup) 
}
```

注册方法的第一个参数是插件名称，第二个是一个 func，func 签名如下

``` golang
// SetupFunc is used to set up a plugin, or in other words,
// execute a directive. It will be called once per key for
// each server block it appears in.
type SetupFunc func(c *Controller) error
```

**在这个 SetupFunc 中，插件编写者应当通过 `*Controller` 拿到 CoreDNS 的配置并解析它，从而完成自己插件的初始化配置；**比如你的插件需要连接 Etcd，那么在这个方法里你要通过 `*Controller` 遍历配置，拿到 Etcd 的地址、证书、用户名密码配置等信息；

如果配置信息没有问题，该插件应当初始化完成；如果有问题就报错退出，然后整个 CoreDNS 启动失败；如果插件初始化完成，最后不要忘记将自己的插件加入到整个插件链路中(CoreDNS 根据情况逐个调用)

``` golang
func setup(c *caddy.Controller) error {
	e, err := etcdParse(c)
	if err != nil {
		return plugin.Error("gdns", err)
	}

	dnsserver.GetConfig(c).AddPlugin(func(next plugin.Handler) plugin.Handler {
		e.Next = next
		return e
	})

	return nil
}
```

### 2.3、插件结构体

一般来说，每一个插件都会定义一个结构体，**结构体中包含必要的 CoreDNS 内置属性，以及当前插件特性的相关配置；**一个样例的插件结构体如下所示

``` golang
type GDNS struct {
  // Next 属性在 Setup 之后会被设置到下一个插件的引用，以便在本插件解析失败后可以交由下面的插件继续解析
	Next       plugin.Handler
	// Fall 列表用来控制哪些域名的请求解析失败后可以继续穿透到下一个插件重新处理
	Fall       fall.F
	// Zones 表示当前插件应该 case 哪些域名的 DNS 请求
	Zones      []string
	
	// PathPrefix 和 Client 就是插件本身的业务属性了，由于插件要连 Etcd
	// PathPrefix 就是 Etcd 目录前缀，Client 是一个 Etcd 的 client
	// endpoints 是 Etcd api 端点的地址
	PathPrefix string
	Client     *etcdcv3.Client
	endpoints []string // Stored here as well, to aid in testing.
}
```

### 2.4、插件接口

一个 Go 编写的 CoreDNS 插件实际上只需要实现一个 `Handler` 接口既可，接口定义如下

``` golang
// Handler is like dns.Handler except ServeDNS may return an rcode
// and/or error.
//
// If ServeDNS writes to the response body, it should return a status
// code. CoreDNS assumes *no* reply has yet been written if the status
// code is one of the following:
//
// * SERVFAIL (dns.RcodeServerFailure)
//
// * REFUSED (dns.RecodeRefused)
//
// * FORMERR (dns.RcodeFormatError)
//
// * NOTIMP (dns.RcodeNotImplemented)
//
// All other response codes signal other handlers above it that the
// response message is already written, and that they should not write
// to it also.
//
// If ServeDNS encounters an error, it should return the error value
// so it can be logged by designated error-handling plugin.
//
// If writing a response after calling another ServeDNS method, the
// returned rcode SHOULD be used when writing the response.
//
// If handling errors after calling another ServeDNS method, the
// returned error value SHOULD be logged or handled accordingly.
//
// Otherwise, return values should be propagated down the plugin
// chain by returning them unchanged.
Handler interface {
	ServeDNS(context.Context, dns.ResponseWriter, *dns.Msg) (int, error)
	Name() string
}
```

- `ServeDNS` 方法是插件需要实现的主要逻辑方法，DNS 请求接受后会从这个方法传入，插件编写者需要实现查询并返回结果
- `Name` 方法只返回一个插件名称标识，具体作用记不太清楚，好像是为了判断插件命名唯一性然后做链式顺序调用的，原则只要你不跟系统插件重名就行

**基本逻辑就是在 setup 阶段通过配置文件创建你的插件结构体对象；然后插件结构体实现这个 `Handler` 接口，运行期 CoreDNS 会调用接口的 `ServeDNS` 方法来向插件查询 DNS 请求**

### 2.5、ServeDNS 方法

ServeDNS 方法入参有 3 个:

- `context.Context` 用来控制超时等情况的 context
- `dns.ResponseWriter` 插件通过这个对象写入对 Client DNS 请求的响应结果
- `*dns.Msg` 这个是 Client 发起的 DNS 请求，插件负责处理它，比如当你发现请求类型是 `AAAA` 而你的插件又不想去支持时要如何返回结果

对于返回结果，插件编写者应当通过 `dns.ResponseWriter.WriteMsg` 方法写入返回结果，基本代码如下

``` golang
// ServeDNS implements the plugin.Handler interface.
func (gDNS *GDNS) ServeDNS(ctx context.Context, w dns.ResponseWriter, r *dns.Msg) (int, error) {
	
	// ...... 这里应当实现你的业务逻辑，查找相应的 DNS 记录
	
	// 最后通过 new 一个 dns.Msg 作为返回结果
	resp := new(dns.Msg)
	resp.SetReply(r)
	resp.Authoritative = true
	
	// records 是真正的记录结果，应当在业务逻辑区准备好
	resp.Answer = append(resp.Answer, records...)
	
	// 返回结果
	err = w.WriteMsg(resp)
	if err != nil {
		log.Error(err)
	}

   // 告诉 CoreDNS 是否处理成功
	return dns.RcodeSuccess, nil
}
```

**需要注意的是，无论根据业务逻辑是否查询到 DNS 记录，都要返回响应结果(没有就返回空)，错误或者未返回将会导致 Client 端查询 DNS 超时，然后不断重试，最终可能导致 Client 端服务故障**


### 2.6、Name 方法

`Name` 方法非常简单，只需要返回当前插件名称既可；该方法的作用是为了其他插件判断本插件是否加载等情况

``` golang
// Name implements the Handler interface.
func (gDNS *GDNS) Name() string { return "gdns" }
```

## 三、CoreDNS 插件处理

对于实际的业务处理，可以通过 `case` 请求 `QType` 来做具体的业务实现

``` golang
// ServeDNS implements the plugin.Handler interface.
func (gDNS *GDNS) ServeDNS(ctx context.Context, w dns.ResponseWriter, r *dns.Msg) (int, error) {
	state := request.Request{W: w, Req: r}
	zone := plugin.Zones(gDNS.Zones).Matches(state.Name())
	if zone == "" {
		return plugin.NextOrFailure(gDNS.Name(), gDNS.Next, ctx, w, r)
	}

	// ...业务处理
	switch state.QType() {
	case dns.TypeA:
		// A 记录查询业务逻辑
	case dns.TypeAAAA:
		// AAAA 记录查询业务逻辑
	default:
		return false

	resp := new(dns.Msg)
	resp.SetReply(r)
	resp.Authoritative = true
	resp.Answer = append(resp.Answer, records...)
	err = w.WriteMsg(resp)
	if err != nil {
		log.Error(err)
	}

	return dns.RcodeSuccess, nil
}
```

## 四、插件编译及测试

### 4.1、官方标准操作

根据官方文档的描述，当你编写好插件以后，**你的插件应当提交到一个 Git 仓库中，可以使 Github 等(保证可以 `go get` 拉取就行)，然后修改 `plugin.cfg`，最后执行 `make` 既可**；具体修改如下所示

![plugin.cfg](http://cdn.oss.link/markdown/vey4u.png)

**值得注意的是: 插件配置在 `plugin.cfg` 内的顺序决定了插件的执行顺序；通俗的讲，如果 Client 的一个 DNS 请求进来，CoreDNS 根据你在 `plugin.cfg` 内书写的顺序依次调用，而并非 `Corefile` 内的配置顺序**

配置好以后直接执行 `make` 既可编译成功一个包含自定义插件的 CoreDNS 二进制文件(编译过程的 `go mod` 下载加速问题不在本文讨论范围内)；你可以直接通过这个二进制测试插件的处理情况，当然这种测试不够直观，而且频繁修改由于 `go mod` 缓存等原因并不一定能保证每次编译的都包含最新插件代码，所以另一种方式请看下一章节

### 4.2、经验性的操作

根据个人测试以及对源码的分析，在修改 `plugin.cfg` 然后执行 `make` 命令后，实际上是进行了代码生成；当你通过 git 命令查看相关修改文件时，整个插件加载体系便没什么秘密可言了；**在整个插件体系中，插件加载是通过 `init` 方法注册的，那么既然用 go 写插件，那么应该清楚 `init` 方法只有在包引用之后才会执行，所以整个插件体系实际上是这样事儿的:**

首先 `make` 以后会修改 `core/plugin/zplugin.go` 文件，这个文件啥也不干，就是 `import` 来实现调用对应包的 `init` 方法

![zplugin.go](http://cdn.oss.link/markdown/ny1rz.png)

当 `init` 执行后你去追源码，实际上就是 Caddy 维护了一个 `map[string]Plugin`，`init` 会把你的插件 func 塞进去然后后面再调用，实现一个懒加载或者说延迟初始化

![caddy_plugin](http://cdn.oss.link/markdown/idno4.png)

接着修改了一下 `core/dnsserver/zdirectives.go`，这个里面也没啥，就是一个 `[]string`，**但是 `[]string` 这玩意有顺序啊，这就是为什么你在 `plugin.cfg` 里写的顺序决定了插件处理顺序的原因(因为生成的这个切片有顺序)**

![zdirectives.go](http://cdn.oss.link/markdown/bixos.png)


综上所述，实际上 `make` 命令一共修改了两个文件，如果想在 IDE 内直接 debug CoreDNS + Plugin 源码，那么只需要这样做:

复制自己编写的插件目录到 `plugin` 目录，类似这样

![gdns](http://cdn.oss.link/markdown/whwuy.png)

手动修改 `core/plugin/zplugin.go`，加入自己插件的 `import`(此时你直接复制系统其他插件，改一下目录名既可)

![update_zplugin](http://cdn.oss.link/markdown/g7wp0.png)

手动修改 `core/dnsserver/zdirectives.go` 把自己插件名称写进去(自己控制顺序)，然后 debug 启动 `coredns.go` 里面的 main 方法测试既可

![coredns.go](http://cdn.oss.link/markdown/4ucqg.png)

## 五、本文参考

- Writing Plugins for CoreDNS: https://coredns.io/2016/12/19/writing-plugins-for-coredns
- how-to-add-plugins.md: https://github.com/coredns/coredns.io/blob/master/content/blog/how-to-add-plugins.md
- example plugin: https://github.com/coredns/example

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
