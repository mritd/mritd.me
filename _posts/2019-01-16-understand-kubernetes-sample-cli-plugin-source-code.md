---
layout: post
categories: Kubernetes
title: Kubernetes sample-cli-plugin 源码分析
date: 2019-01-16 12:16:42 +0800
description: Kubernetes sample-cli-plugin 源码分析
keywords: kubernetes,源码
catalog: true
multilingual: false
tags: Kubernetes
---

> 写这篇文章的目的是为了继续上篇 [Kubernetes 1.12 新的插件机制](https://mritd.me/2018/11/30/kubectl-plugin-new-solution-on-kubernetes-1.12/) 中最后部分对 `Golang 的插件辅助库` 说明；以及为后续使用 Golang 编写自己的 Kubernetes 插件做一个基础铺垫；顺边说一下 **sample-cli-plugin 这个项目是官方为 Golang 开发者编写的一个用于快速切换配置文件中 Namespace 的一个插件样例**

## 一、基础准备

在开始分析源码之前，**我们假设读者已经熟悉 Golang 语言，至少对基本语法、指针、依赖管理工具有一定认知**；下面介绍一下 [sample-cli-plugin](https://github.com/kubernetes/sample-cli-plugin) 这个项目一些基础核心的依赖:

### 1.1、Cobra 终端库

这是一个强大的 Golang 的 command line interface 库，其支持用非常简单的代码创建出符合 Unix 风格的 cli 程序；甚至官方提供了用于创建 cli 工程脚手架的 cli 命令工具；Cobra 官方 Github 地址 [点击这里](https://github.com/spf13/cobra)，具体用法请自行 Google，以下只做一个简单的命令定义介绍(docker、kubernetes 终端 cli 都基于这个库)

``` golang
# 每一个命令(不论是子命令还是主命令)都会是一个 cobra.Command 对象
var lsCmd = &cobra.Command{
    // 一些命令帮助文档有关的描述信息
    Use:   "ls",
    Short: "A brief description of your command",
    Long: `A longer description that spans multiple lines and likely contains examples
and usage of using your command. For example:

Cobra is a CLI library for Go that empowers applications.
This application is a tool to generate the needed files
to quickly create a Cobra application.`,
    // 命令运行时真正执行逻辑，如果需要返回 Error 信息，我们一般设置 RunE
    Run: func(cmd *cobra.Command, args []string) {
        fmt.Println("ls called")
    },
}

// 为这个命令添加 flag，比如 `--help`、`-p`
// PersistentFlags() 方法添加的 flag 在所有子 command 也会生效
// Cobra 的 command 可以无限级联，比如 `kubectl get pod` 就是在 `kubectl` command 下增加了子 `get` command
lsCmd.PersistentFlags().String("foo", "", "A help for foo")
// Flags() 方法添加的 flag 仅在直接调用此子命令时生效
lsCmd.Flags().BoolP("toggle", "t", false, "Help message for toggle")
```

### 1.2、vendor 依赖

vendor 目录用于存放 Golang 的依赖库，sample-cli-plugin 这个项目采用 [godep](https://github.com/tools/godep) 工具管理依赖；依赖配置信息被保存在 `Godeps/Godeps.json` 中，**一般项目不会上传 vendor 目录，因为它的依赖信息已经在 Godeps.json 中存在，只需要在项目下使用 `godep restore` 命令恢复就可自动重新下载**；这里上传了 vendor 目录的原因应该是为了方便开发者直接使用 `go get` 命令安装；顺边说一下在 Golang 新版本已经开始转换到 `go mod` 依赖管理工具，标志就是项目下会有 `go.mod` 文件

## 二、源码分析

### 2.1、环境搭建

这里准备一笔带过了，基本就是 clone 源码到 `$GOPATH/src/k8s.io/sample-cli-plugin` 目录，然后在 GoLand 中打开；目前我使用的 Go 版本为最新的 1.11.4；以下时导入源码后的截图

![GoLand](https://mritd.b0.upaiyun.com/markdown/sn8o8.png)

### 2.2、定位核心运行方法

熟悉过 Cobra 库以后，再从整个项目包名上分析，首先想到的启动入口应该在 `cmd` 包下(一般 `cmd` 包下的文件都会编译成最终可执行文件名，Kubernetes 也是一样)

![main](https://mritd.b0.upaiyun.com/markdown/rafeq.png)

从以上截图中可以看出，首先通过 `cmd.NewCmdNamespace` 方法创建了一个 Command 对象 `root`，然后调用了 `root.Execute` 就结束了；那么也就说明 `root` 这个 Command 是唯一的核心命令对象，整个插件实现都在这个 `root` 里；所以我们需要查看一下这个 `cmd.NewCmdNamespace` 是如何对它初始化的，找到 Cobra 中的 `Run` 或者 `RunE` 设置

![NewCmdNamespace](https://mritd.b0.upaiyun.com/markdown/77krg.png)

定位到 `NewCmdNamespace` 方法以后，基本上就是标准的 Cobra 库的使用方式了；**从截图上可以看到，`RunE` 设置的函数总共运行了 3 个动作: `o.Complete`、`o.Validate`、`o.Run`**；所以接下来我们主要分析这三个方法就行了


### 2.3、NamespaceOptions 结构体

在分析上面说的这三个方法之前，我们还应当了解一下这个 `o` 是什么玩意

![NamespaceOptions](https://mritd.b0.upaiyun.com/markdown/4b3cc.png)

从源码中可以看到，`o` 这个对象由 `NewNamespaceOptions` 创建，而 `NewNamespaceOptions` 方法返回的实际上是一个 `NamespaceOptions` 结构体；接下来我们需要研究一下这个结构体都是由什么组成的，换句话说要基本大致上整明白结构体的基本结构，比如里面的属性都是干啥的

#### 2.3.1、*genericclioptions.ConfigFlags

首先看下第一个属性 `configFlags`，它的实际类型是 `*genericclioptions.ConfigFlags`，点击查看以后如下

![genericclioptions.ConfigFlags](https://mritd.b0.upaiyun.com/markdown/li6s4.png)

从这些字段上来看，我们可以暂且模糊的推测出这应该是个基础配置型的字段，负责存储一些全局基本设置，比如 API Server 认证信息等

#### 2.3.2、*api.Context

下面这两个 `resultingContext`、`resultingContextName` 就很好理解了，从名字上看就可以知道它们应该是用来存储结果集的 Context 信息的；当然这个 `*api.Context` 就是 Kubernetes 配置文件中 Context 的 Go 结构体

#### 2.3.3、userSpecified*

这几个字段从名字上就可以区分出，他们应该用于存储用户设置的或者说是通过命令行选项输入的一些指定配置信息，比如 Cluster、Context 等

#### 2.3.4、rawConfig

rawConfig 这个变量名字有点子奇怪，不过它实际上是个 `api.Config`；里面保存了与 API Server 通讯的配置信息；**至于为什么要有这玩意，是因为配置信息输入源有两个: cli 命令行选项(eg: `--namespace`)和用户配置文件(eg: `~/.kube/config`)；最终这两个地方的配置合并后会存储在这个 rawConfig 里**

#### 2.3.5、listNamespaces

这个变量实际上相当于一个 flag，用于存储插件是否使用了 `--list` 选项；在分析结构体这里没法看出来；不过只要稍稍的多看一眼代码就能看在 `NewCmdNamespace` 方法中有这么一行代码

![listNamespaces](https://mritd.b0.upaiyun.com/markdown/f07l3.png)


### 2.4、核心处理逻辑

介绍完了结构体的基本属性，最后我们只需要弄明白在核心 Command 方法内运行的这三个核心方法就行了

![core func](https://mritd.b0.upaiyun.com/markdown/8lm4b.png)


#### 2.4.1、*NamespaceOptions.Complete

这个方法代码稍微有点多，这里不会对每一行代码都做解释，只要大体明白都在干什么就行了；我们的目的是理解它，后续模仿它创造自己的插件；下面是代码截图

![NamespaceOptions.Complete](https://mritd.b0.upaiyun.com/markdown/qqf0f.png)

从截图上可以看到，首先弄出了 `rawConfig` 这个玩意，`rawConfig` 上面也提到了，它就是终端选项和用户配置文件的最终合并，至于为什么可以查看 `ToRawKubeConfigLoader().RawConfig()` 这两个方法的注释和实现即可；

接下来就是各种获取插件执行所需要的变量信息，比如获取用户指定的 `Namespace`、`Cluster`、`Context` 等，其中还包含了一些必要的校验；比如不允许使用 `kubectl ns NS_NAME1 --namespace NS_NAME2` 这种操作(因为这么干很让人难以理解 "你到底是要切换到 `NS_NAME1` 还是 `NS_NAME2`")

最后从 `153` 行 `o.resultingContext = api.NewContext()` 开始就是创建最终的 `resultingContext` 对象，把获取到的用户指定的 `Namespace` 等各种信息赋值好，为下一步将其持久化到配置文件中做准备

#### 2.4.2、*NamespaceOptions.Validate

这个方法看名字就知道，里面全是对最终结果的校验；比如检查一下 `rawConfig` 中的 `CurrentContext` 是否获取到了，看看命令行参数是否正确，确保你不会瞎鸡儿输入 `kubectl ns NS_NAME1 NS_NAME2` 这种命令

![NamespaceOptions.Validate](https://mritd.b0.upaiyun.com/markdown/frqpb.png)

#### 2.4.3、*NamespaceOptions.Run

第一步合并配置信息并获取到用户设置(输入)的配置，第二部做参数校验；可以说前面的两步操作都是为这一步做准备，`Run` 方法真正的做了配置文件写入、终端返回结果打印操作

![NamespaceOptions.Run](https://mritd.b0.upaiyun.com/markdown/6tkjz.png)

可以看到，`Run` 方法第一步就是更加谨慎的检查了一下参数是否正常，然后调用了 `o.setNamespace`；这个方法截图如下

![NamespaceOptions.setNamespace](https://mritd.b0.upaiyun.com/markdown/1jc3k.png)

这个 `setNamespace`是真正的做了配置文件写入动作的，实际写入方法就是 `clientcmd.ModifyConfig`；这个是 `Kubernetes` `client-go` 提供的方法，这些库的作用就是提供给我们非常方便的 API 操作；比如修改配置文件，你不需要关心配置文件在哪，你更不需要关系文件句柄是否被释放

从 `o.setNamespace` 方法以后其实就没什么看头了，毕竟插件的核心功能就是快速修改 `Namespace`；下面的各种 `for` 循环遍历其实就是在做打印输出；比如当你没有设置 `Namespace` 而使用了 `--list` 选项，插件就通过这里帮你打印设置过那些 `Namespace`

## 三、插件总结

分析完了这个官方的插件，然后想一下自己以后写插件可能的需求，最后对比一下，可以为以后写插件做个总结:

- 我们最好也弄个 `xxxOptions` 这种结构体存存一些配置
- 结构体内至少我们应当存储 `configFlags`、`rawConfig` 这两个基础配置信息
- 结构体内其它参数都应当是跟自己实际业务有关的
- 最后在在结构体上增加适当的方法完成自己的业务逻辑并保持好适当的校验


转载请注明出n，本文采用 [CC4.0](http://c 1.12 新的插件机制](https://mritd.me/2018/11/30/kubectl-plugin-new-solution-on-kubernetes-1.12/) 中最后部分对 `Golang 的插件辅助库` 说明；以及为后续使用 Golang 编写自己的 Kubernetes 插件做一个基础铺垫；顺边说一下 **sample-cli-plugin 这个项目是官方为 Golang 开发者编写的一个用于快速切换配置文件中 Namespace 的一个插件样例**

