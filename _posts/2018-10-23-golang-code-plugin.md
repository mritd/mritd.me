---
layout: post
categories: Golang
title: Go 代码的扩展套路
date: 2018-10-23 21:32:13 +0800
description: Go 代码的扩展套路
keywords: golang,plugin
catalog: true
multilingual: false
tags: Golang
---

> 折腾 Go 已经有一段时间了，最近在用 Go 写点 web 的东西；在搭建脚手架的过程中总是有点不适应，尤其对可扩展性上总是感觉没有 Java 那么顺手；索性看了下 coredns 的源码，最后追踪到 caddy 源码；突然发现他们对代码内的 plugin 机制有一些骚套路，这里索性记录一下

### 一、问题由来

纵观现在所有的 Go web 框架，在文档上可以看到使用方式很简明；非常符合我对 Go 的一贯感受: "所写即所得"；就拿 Gin 这个来说，在 README.md 上可以很轻松的看到 `engine` 或者说 `router` 这玩意的使用，比如下面这样:

``` golang
func main() {
	// Disable Console Color
	// gin.DisableConsoleColor()

	// Creates a gin router with default middleware:
	// logger and recovery (crash-free) middleware
	router := gin.Default()

	router.GET("/someGet", getting)
	router.POST("/somePost", posting)
	router.PUT("/somePut", putting)
	router.DELETE("/someDelete", deleting)
	router.PATCH("/somePatch", patching)
	router.HEAD("/someHead", head)
	router.OPTIONS("/someOptions", options)

	// By default it serves on :8080 unless a
	// PORT environment variable was defined.
	router.Run()
	// router.Run(":3000") for a hard coded port
}
```

乍一看简单到爆，但实际使用中，在脚手架搭建上，我们需要规划好 **包结构、配置文件、命令行参数、数据库连接、cache** 等等；直到目前为止，至少我没有找到一种非常规范的后端 MVC 的标准架子结构；这点目前确实不如 Java 的生态；作为最初的脚手架搭建者，站在这个角度，我想我们更应当考虑如何做好适当的抽象、隔离；以防止后面开发者对系统基础功能可能造成的破坏。

综上所述，再配合 Gin 或者说 Go 的代码风格，这就形成了一种强烈的冲突；在 Java 中，由于有注解(`Annotation`)的存在，事实上你是可以有这种操作的: **新建一个 Class，创建 func，在上面加上合适的注解，最终框架会通过注解扫描的方式以适当的形式进行初始化**；而 Go 中并没有 `Annotation` 这玩意，我们很难实现在 **代码运行时扫描自身做出一种策略性调整**；从而下面这个需求很难实现: **作为脚手架搭建者，我希望我的基础代码安全的放在一个特定位置，后续开发者开发应当以一种类似可热插拔的形式注入进来**，比如 Gin 的 router 路由设置，我不希望每次有修改都会有人动我的 router 核心配置文件。

### 二、Caddy 的套路

在翻了 coredns 的源码后，我发现他是依赖于 Caddy 这框架运行的，coredns 的代码内的插件机制也是直接调用的 Caddy；所以接着我就翻到了 Caddy 源码，其中的代码如下(完整代码[点击这里](https://github.com/mholt/caddy/blob/master/plugins.go)):

``` golang
// RegisterPlugin plugs in plugin. All plugins should register
// themselves, even if they do not perform an action associated
// with a directive. It is important for the process to know
// which plugins are available.
//
// The plugin MUST have a name: lower case and one word.
// If this plugin has an action, it must be the name of
// the directive that invokes it. A name is always required
// and must be unique for the server type.
func RegisterPlugin(name string, plugin Plugin) {
	if name == "" {
		panic("plugin must have a name")
	}
	if _, ok := plugins[plugin.ServerType]; !ok {
		plugins[plugin.ServerType] = make(map[string]Plugin)
	}
	if _, dup := plugins[plugin.ServerType][name]; dup {
		panic("plugin named " + name + " already registered for server type " + plugin.ServerType)
	}
	plugins[plugin.ServerType][name] = plugin
}
```

套路很清奇，为了实现我上面说的那个需求: "后面开发不需要动我核心代码，我还能允许他们动态添加"，Caddy 套路就是**定义一个 map，map 里用于存放一种特定形式的 func，并且暴露出一个方法用于向 map 内添加指定 func，然后在合适的时机遍历这个 map，并执行其中的 func。**这种套路利用了 Go 函数式编程的特性，将行为先存储在容器中，然后后续再去调用这些行为。

### 三、总结

长篇大论这么久，实际上我也是在一边折腾 Go 的过程中一边总结和对比跟 Java 的差异；在 Java 中扫描自己注解的套路 Go 中没法实现，但是 Go 利用其函数式编程的优势也可以利用一些延迟加载方式实现对应的功能；总结来说，不同语言有其自己的特性，当有对比的时候，可能更加深刻。

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
