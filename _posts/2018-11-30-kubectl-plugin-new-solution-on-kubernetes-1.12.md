---
layout: post
categories: Kubernetes
title: Kubernetes 1.12 新的插件机制
date: 2018-11-30 00:05:34 +0800
description: Kubernetes 1.12 新的插件机制
keywords: kubectl,plugin
catalog: true
multilingual: false
tags: Kubernetes
---

> 在很久以前的版本研究过 kubernetes 的插件机制，当时弄了一个快速切换 `namespace` 的小插件；最近把自己本机的 kubectl 升级到了 1.12，突然发现插件不能用了；撸了一下文档发现插件机制彻底改了...

## 一、插件编写语言

kubernetes 1.12 新的插件机制在编写语言上同以前一样，**可以以任意语言编写，只要能弄一个可执行的文件出来就行**，插件可以是一个 `bash`、`python` 脚本，也可以是 `Go` 等编译语言最终编译的二进制；以下是一个 Copy 自官方文档的 `bash` 编写的插件样例

``` sh
#!/bin/bash

# optional argument handling
if [[ "$1" == "version" ]]
then
    echo "1.0.0"
    exit 0
fi

# optional argument handling
if [[ "$1" == "config" ]]
then
    echo $KUBECONFIG
    exit 0
fi

echo "I am a plugin named kubectl-foo"
```

## 二、插件加载方式

### 2.1、插件位置

1.12 kubectl 插件最大的变化就是加载方式变了，由原来的放置在指定位置，还要为其编写 yaml 配置变成了现在的类似 git 扩展命令的方式: **只要放置在 PATH 下，并以 `kubectl-` 开头的可执行文件都被认为是 `kubectl` 的插件**；所以你可以随便弄个小脚本(比如上面的代码)，然后改好名字赋予可执行权限，扔到 PATH 下即可

![test-plugin](https://cdn.oss.link/markdown/s64v6.png)

### 2.2、插件变量

同以前不通，**以前版本的执行插件时，`kubectl` 会向插件传递一些特定的与 `kubectl` 相关的变量，现在则只会传递标准变量；即 `kubectl` 能读到什么变量，插件就能读到，其他的私有化变量(比如 `KUBECTL_PLUGINS_CURRENT_NAMESPACE`)不会再提供**

![plugin env](https://cdn.oss.link/markdown/vs1c3.png)

**并且新版本的插件体系，所有选项(`flag`) 将全部交由插件本身处理，kubectl 不会再解析**，比如下面的 `--help` 交给了自定义插件处理，由于脚本内没有处理这个选项，所以相当于选项无效了

![plugin flag](https://cdn.oss.link/markdown/8ch88.png)

还有就是 **传递给插件的第一个参数永远是插件自己的绝对位置，比如这个 `test` 插件在执行时的 `$0` 是 `/usr/local/bin/kubectl-test`**

### 2.3、插件命名及查找

目前在插件命名及查找顺序上官方文档写的非常详尽，不给过对于普通使用者来说，实际上命名规则和查找与常规的 Linux 下的命令查找机制相同，只不过还做了增强；增强后的基本规则如下

- `PATH` 优先匹配原则
- 短横线 `-` 自动分割匹配以及智能转义
- 以最精确匹配为首要目标
- 查找失败自动转换参数

`PATH` 优先匹配原则跟传统的命令查找一致，即当多个路径下存在同名的插件时，则采用最先查找到的插件

![plugin path](https://cdn.oss.link/markdown/ljyp5.png)

当你的插件文件名中包含 `-` ，并且 `kubectl` 在无法精确找到插件时会尝试自动拼接命令来尝试匹配；如下所示，在没有找到 `kubectl-test` 这个命令时会尝试拼接参数查找

![auto merge](https://cdn.oss.link/markdown/l85bp.png)

由于以上这种查找机制，**当命令中确实包含 `-` 时，必须进行转义以 `_` 替换，否则 `kubectl` 会提示命令未找到错误**；替换后可直接使用 `kubectl 插件命令(包含-)` 执行，同时也支持以原始插件名称执行(使用 `_`)

![name contains dash](https://cdn.oss.link/markdown/7vm0l.png)

在复杂插件体系下，多个插件可能包含同样的前缀，此时将遵序最精确查找原则；即当两个插件 `kubectl-test-aaa`、`kubectl-test-aaa-bbb` 同时存在，并且执行 `kubectl test aaa bbb` 命令时，优先匹配最精确的插件 `kubectl-test-aaa-bbb`，**而不是将 `bbb` 作为参数传递给 `kubectl-test-aaa` 插件**

![precise search](https://cdn.oss.link/markdown/god8q.png)

### 2.4、总结

插件查找机制在一般情况下与传统 PATH 查找方式相同，同时 `kubectl` 实现了智能的 `-` 自动匹配查找、更精确的命令命中功能；这两种机制的实现主要为了方便编写插件的命令树(插件命令的子命令...)，类似下面这种

``` sh
$ ls ./plugin_command_tree
kubectl-parent
kubectl-parent-subcommand
kubectl-parent-subcommand-subsubcommand
```

当出现多个位置有同名插件时，执行 `kubectl plugin list` 能够检测出哪些插件由于 PATH 查找顺序原因导致永远不会被执行问题

``` sh
$ kubectl plugin list
The following kubectl-compatible plugins are available:

test/fixtures/pkg/kubectl/plugins/kubectl-foo
/usr/local/bin/kubectl-foo
  - warning: /usr/local/bin/kubectl-foo is overshadowed by a similarly named plugin: test/fixtures/pkg/kubectl/plugins/kubectl-foo
plugins/kubectl-invalid
  - warning: plugins/kubectl-invalid identified as a kubectl plugin, but it is not executable

error: 2 plugin warnings were found
```

### 三、Golang 的插件辅助库

由于插件机制的变更，导致其他语言编写的插件在实时获取某些配置信息、动态修改 `kubectl` 配置方面可能造成一定的阻碍；为此 kubernetes 提供了一个 [command line runtime package](https://github.com/kubernetes/cli-runtime)，使用 Go 编写插件，配合这个库可以更加方便的解析和调整 `kubectl` 的配置信息

官方为了演示如何使用这个 [cli-runtime](https://github.com/kubernetes/cli-runtime) 库编写了一个 `namespace` 切换的插件(自己白写了...)，仓库地址在 [Github](https://github.com/kubernetes/sample-cli-plugin) 上，基本编译使用如下(直接 `go get` 后编译文件默认为目录名 `cmd`)

``` sh
➜  ~ go get k8s.io/sample-cli-plugin/cmd
➜  ~ sudo mv gopath/bin/cmd /usr/local/bin/kubectl-ns
➜  ~ kubectl ns
default
➜  ~ kubectl ns --help
View or set the current namespace

Usage:
  ns [new-namespace] [flags]

Examples:

        # view the current namespace in your KUBECONFIG
        kubectl ns

        # view all of the namespaces in use by contexts in your KUBECONFIG
        kubectl ns --list

        # switch your current-context to one that contains the desired namespace
        kubectl ns foo


Flags:
      --as string                      Username to impersonate for the operation
      --as-group stringArray           Group to impersonate for the operation, this flag can be repeated to specify multiple groups.
      --cache-dir string               Default HTTP cache directory (default "/Users/mritd/.kube/http-cache")
      --certificate-authority string   Path to a cert file for the certificate authority
      --client-certificate string      Path to a client certificate file for TLS
      --client-key string              Path to a client key file for TLS
      --cluster string                 The name of the kubeconfig cluster to use
      --context string                 The name of the kubeconfig context to use
  -h, --help                           help for ns
      --insecure-skip-tls-verify       If true, the server's certificate will not be checked for validity. This will make your HTTPS connections insecure
      --kubeconfig string              Path to the kubeconfig file to use for CLI requests.
      --list                           if true, print the list of all namespaces in the current KUBECONFIG
  -n, --namespace string               If present, the namespace scope for this CLI request
      --request-timeout string         The length of time to wait before giving up on a single server request. Non-zero values should contain a corresponding time unit (e.g. 1s, 2m, 3h). A value of zero means don't timeout requests. (default "0")
  -s, --server string                  The address and port of the Kubernetes API server
      --token string                   Bearer token for authentication to the API server
      --user string                    The name of the kubeconfig user to use
```

限于篇幅原因，具体这个 `cli-runtime` 包怎么用请自行参考官方写的这个 `sample-cli-plugin` (其实并不怎么 "simple"...)


本文参考文档:

- [Extend kubectl with plugins](https://kubernetes.io/docs/tasks/extend-kubectl/kubectl-plugins/)
- [cli-runtime](https://github.com/kubernetes/cli-runtime)
- [sample-cli-plugin](https://github.com/kubernetes/sample-cli-plugin)

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
