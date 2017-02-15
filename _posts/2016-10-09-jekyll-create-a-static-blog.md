---
layout: post
categories: jekyll
title: Jekyll 搭建静态博客
date: 2016-10-09 00:14:31 +0800
description: 记录一下使用 jekyll 创建静态博客的过程
keywords: jekyll
---

> 最近从 Hexo 切换到了 jekyll，发现 jekyll 搭建静态博客要比 Hexo 好得多；顺便吐槽一下 node 的依赖管理，感觉很蛋疼；同样的操作步骤往往在其他机器上无法搭建成功，每次挂掉的原因都是依赖不对等等，感觉没有一个良好的依赖管理系统；而 jekyll 使用 ruby 编写，暂不论语言哪个好那个坏，至少有 Genfile 等约束可以保证每次同样的操作搭建时不会出现依赖问题

### 一、环境准备

- CentOS 7
- rvm
- ruby 2.3
- jekyll 3.2.1

本文基于 CentOS 7 系统，Mac OS 与其他系统基本操作类似，大致步骤相同，唯一差别就是搞定前期的 ruby 相关配置

### 二、安装 ruby

由于众所周知的原因(就是特么的有GFW)，导致 ruby 源等在国内不可用，所以可以使用淘宝源等替代

#### 2.1、安装 rvm

rvm 是 ruby 管理工具，可以使用 rvm 在系统中安装配置多个版本的 ruby，同时可方便进行切换

``` sh
# 首先安装基本工具
yum install -y wget which
# 设置一下环境变量，下面要用到
PATH=$PATH:/usr/local/rvm/bin:/usr/local/rvm/rubies/ruby-2.3.0/bin
# 下载 rvm 的密钥文件(有墙太慢，我已经提取放到了 CDN 里)
wget http://upyun.mritd.me/keys/rvm.key -O rvm.key
# 导入密钥
gpg2 --import rvm.key
# 安装 rvm
curl -sSL https://get.rvm.io | bash -s stable
# 切换 ruby 源
echo "ruby_url=https://cache.ruby-china.org/pub/ruby" >> /usr/local/rvm/user/db
rvm requirements
```

#### 2.2、安装 ruby

安装好 rvm 后，可使用 rvm 直接安装 ruby

``` sh
# 安装 ruby
rvm install 2.3.0
# 设置默认使用的 ruby 版本
rvm use 2.3.0 --default
# 安装 bundler
gem install bundler
```

### 三、搭建 jekyll

jekyll 搭建静态博客非常简单，只需要找一套可用的主题，然后安装好相关依赖即可，关于主题可参考这里 [https://www.zhihu.com/question/20223939](https://www.zhihu.com/question/20223939)，以下以 mzlogin.github.io 的主题为例

#### 3.1、clone 主题

``` sh
git clone https://github.com/mzlogin/mzlogin.github.io.git
```

#### 3.2、安装 jekyll

``` sh
# 进入主题目录
cd mzlogin.github.io
# 安装 jekyll 等
bundle install
```

#### 3.3、启动并修改

jekyll 等组件安装完成后便可直接启动预览博客

``` sh
# 启动 jekyll 并设置监听地址和端口
jekyll serve -H 0.0.0.0 -P 1234
```

此时访问便可看到效果

![jekyll_startjekyll](https://mritd.b0.upaiyun.com/markdown/jekyll_startjekyll.png)

**接下来只需要根据主题作者的说明修改对应配置文件即可**

### 四、推送到 Github

**首先在 Github 上创建 `用户名.github.io` 项目，如 `mritd.github.io`，然后删除主题目录下的 `.git` 目录，在执行 `git init` 初始化一下 git 仓库，最后将 master 地址指向新建的仓库地址推送即可；Github 本身也是使用 jekyll 进行生成，所以会自动识别并生成博客；最后访问 `http://用户名.github.io` 即可；其他相关比如 sitemap 设置等可参考 [https://github.com/mritd/mritd.github.io](https://github.com/mritd/mritd.github.io)**
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
