---
layout: post
categories: Linux
title: Jekyll + Travis CI 自动化部署博客
date: 2017-02-25 12:22:49 +0800
description: Jekyll + Travis CI 自动化部署博客
keywords: Jekyll Travis-CI
---

> 由于 Github 访问过慢，所以博客一直放在自己的服务器上托管；博客采用了 Jekyll 生成静态展点，最近鼓捣了一下完成了 Travis CI 自动化部署，顺便在此记录下

### 一、原部署方式

#### 1.1、原部署流程

由于博客访问量不大，同时 jekyll 启动后会开启 http 服务器，还能自动监听文件变化实现刷新；所以以前的方式就是打了一个 docker 镜像，然后镜像每隔 15 分钟拉取 Github 仓库，实现定时更新，基本流程如下

- 本地写博客 Markdown 文件 commit 到 Github
- 服务器上将 jekyll 打成 docker 镜像启动
- 服务器镜像内使用 crond 每隔 15 分钟拉取最新代码
- jekyll 获得最新代码后自动刷新

整体 "架构" 如下

![老架构](https://mritd.b0.upaiyun.com/markdown/44qmr.jpg)

#### 1.2、存在问题

按照以前的方式其实存在一个很大问题就是部署不及时，每次写完文章实际上都是自己 ssh 到服务器手动 pull 一下，感觉很繁琐；另一个大问题(这也不能算 bug) jekyll 的 rss 插件默认生成的 rss 引用地址为 `jekyll server -H x.x.x.x` 的监听地址，而容器化启动 jekyll 监听地址必然是 `0.0.0.0`；后果就是 feed.xml 无法访问，如下所示(这里监听的是 localhost)

![feed error](https://mritd.b0.upaiyun.com/markdown/fq9im.jpg)

#### 1.3、新部署思路

从问题角度上来说，每次手动 pull 虽然有点烦，但是并不是大问题；而 rss 订阅由于网友反馈，再加个人强迫症感觉确实是个大毛病；随着试验发现，**在进行 `jekyll build` 时生成的 feed.xml 中的引用地址会正确读取 _config.yml 中的网址**；而 `jekyll server` 命令实际上也是先 build，然后生成静态文件到 `_site` 目录，最后搞个 http 服务器发布出去

基于以上试验可以得到一个简单的解决方案：不使用 `jekyll server` 启动，先 build 生成正确的 feed.xml 等静态文件，然后自己搞个 nginx 把它发布出去

### 二、Travis CI 自动化部署

#### 2.1、任务拆分

从上面的结论上基本要实现自动化部署需要以下步骤：

- Github commit 后要能自动 build
- 生成的 _site 目录文件能实时更新到容器

#### 2.2、Travis CI 配置

##### 2.2.1、基本配置

对于自动 build，好在 Travis CI 对于开源项目完全免费，并且能自动感知到 Github 的 commit；所以自动 build 生成 静态文件这个过程就由 Travis CI 完成，以下为配置过程

首先注册好 Travis CI 账号，然后点击最左侧 `+` 按钮添加项目

![add repo](https://mritd.b0.upaiyun.com/markdown/7axvx.jpg)

在想要使用 Travis CI 的项目上开启 build

![open](https://mritd.b0.upaiyun.com/markdown/ouod9.jpg)

点击设置按钮设置一下项目

![set options](https://mritd.b0.upaiyun.com/markdown/p1cad.jpg)

##### 2.2.2、.travis.yml 配置

当项目内存在 `.travis.yml` 文件时，Travis CI 会按照其定义完成自动 build 过程，所以开启了上述配置以后还要在项目下创建 `.travis.yml` 配置文件，配置文件定义如下

``` sh
language: ruby
rvm:
  - 2.3.3
before_install:
  - openssl aes-256-cbc -K $encrypted_ecabfac08d8e_key -iv $encrypted_ecabfac08d8e_iv
    -in id_rsa.enc -out ~/.ssh/id_rsa -d
  - chmod 600 ~/.ssh/id_rsa
  - echo -e "Host mritd.me\n\tStrictHostKeyChecking no\n" >> ~/.ssh/config
script:
  - bundle install
  - bundle exec jekyll build
after_success:
  - git clone https://github.com/mritd/mritd.me.git
  - cd mritd.me && rm -rf * && cp -r ../_site/* .
  - git config user.name "mritd"
  - git config user.email "mritd1234@gmail.com"
  - git add --all .
  - git commit -m "Travis CI Auto Builder"
  - git push --force https://$DEPLOY_TOKEN@github.com/mritd/mritd.me.git master
  - ssh root@mritd.me "docker restart mritd_jekyll_1"
branches:
  only:
  - master
env:
  global:
  - NOKOGIRI_USE_SYSTEM_LIBRARIES=true
```

其中 `language`声明使用的语言，`rvm` 是 ruby 的管理工具，并定义了 ruby 版本；`before_install` 定义了执行前的预处理动作，上面增加了一个密钥用于远程登录服务器；`script` 段真正定义了编译过程的命令，`after_success` 定义了如何 build 后如何处理发布物，`branches` 指定有哪些分支变动后触发 CI build，env 是一些环境变量，上面添加了一个变量(根据 jekyll 官方文档)用于加速 jekyll 编译(有些配置不理解往下看)

**具体 `.travis.yml` 配置请参考 [官方文档](https://docs.travis-ci.com/)**

#### 2.3、静态文件的自动更新

Travis CI 在完成 build 后会在 `_site` 目录生成博客的静态文件，而如如何将这些静态文件发送到服务器完成更新是个待解决的问题

##### 2.3.1、解决思路

将 Travis CI 生成的静态文件推送到 Github，博客仍然 docker 化部署，采用 `nginx` + `静态文件` 方式；每次容器启动后都要从 Github pull 最新的静态文件，流程如下

- 本地提交博客 Markdown 文件 到 Github
- Github 触发 Travis CI 执行自动编译
- Travis CI 编译后 push 静态文件到 Github
- Travis CI 通知服务器重启博客容器
- 容器重启拉取最新静态文件完成更新

流程图如下

![new auto deploy](https://mritd.b0.upaiyun.com/markdown/8tro9.jpg)

##### 2.3.2、实现方法

其实主要问题是从上面第三步开始：

Travis CI push 静态文件到 Github 通过 Github 的 token 
实现授权，代码如下

``` sh
after_success:
  - git clone https://github.com/mritd/mritd.me.git
  - cd mritd.me && rm -rf * && cp -r ../_site/* .
  - git config user.name "mritd"
  - git config user.email "mritd1234@gmail.com"
  - git add --all .
  - git commit -m "Travis CI Auto Builder"
  - git push --force https://$DEPLOY_TOKEN@github.com/mritd/mritd.me.git master
```

`$DEPLOY_TOKEN` 是从 Github 授权得到的，然后给于相应权限即可

![Github token](https://mritd.b0.upaiyun.com/markdown/pco7k.jpg)

**关于代码中 `$DEPLOY_TOKEN` 这种重要的密码类变量，Travis CI 在每个项目下提供了设置环境变量功能，如下图**

![setting](https://mritd.b0.upaiyun.com/markdown/7zmj2.jpg)

![add env](https://mritd.b0.upaiyun.com/markdown/0b91x.jpg)

**设置后可在 `.travis.yml` 中直接引用，不过注意一定要关闭 `Display value in build log` 功能，否则 CI log 中会显示 `export XXXX=XXXX` 这种 log 从而暴露重要密码(公有项目的 log 别人可以查看的)；如果开启了那么尽快找到相应 build 并删除 log 日志，如下**

![delete log](https://mritd.b0.upaiyun.com/markdown/kal69.jpg)

在成功 push 了静态文件以后，就要实现服务器的自动更新，自动更新很简单，只需要写个脚本让容器启动后自动 pull 即可，这里不再阐述；下面说一下怎么通知服务器重启容器，这里的思路很简单，**让 CI ssh 上去执行一些 docker 命令即可**；但是有个很大问题是 **SSH 密码怎么整？**

**Travis CI 提供了存放加密文件的方式，文档见 [这里](https://docs.travis-ci.com/user/encrypting-files/)**

简单的说就是将你的 ssh 私钥加密以后扔进去即可，按照稳当的步骤很简单：

- 先安装 ruby 环境，然后用 gem 装 travis (gem install travis)
- 然后登陆 travis (travis login)
- 登陆后加密文件 (travis encrypt-file xxxx)，注意要在 `.travis.yml` 同级目录下执行，待加密文件可在任意位置
- travis 会在 `.travis.yml` 写入 `before_install` 段解密还原回该文件，如果是 ssh 密钥的话参考上面的配置再改一下权限即可

最后一个小问题是可能会有主机信任问题，因为 CI 服务器第一次连接我的服务器会出现 ssh 主机验证，官方给出的做法是添加 addons 配置

``` sh
addons:
  ssh_known_hosts: mritd.me
```

### 三、一些想法

这只是一个小博客，所以服务中断以下无所谓；如果大型部署肯定不会直接重启容器，至少应该是 k8s 滚动升级等措施；与服务器通讯也不应该采用 ssh 方式，虽然 Travis CI 做了加密，但是总感觉不那么稳妥，最好应该写个程序开放一个 REST 接口，并做好授权，必要的话需要开启一次性认证令牌那种方式，其他的后续接着优化 ( :

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
