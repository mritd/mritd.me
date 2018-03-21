---
layout: post
categories: CI/CD Git
title: CI/CD Git Flow
date: 2017-09-05 14:00:55 +0800
description: CI/CD Git Flow
keywords: 记录,Git,Flow,工作流程
catalog: true
multilingual: false
tags: CI/CD
---

> 由于 git 代码管理比较混乱，所以记录一下 Git Flow + GitLab 的整体工作流程


### 一、Git Flow 简介

Git Flow 定义了一个围绕项目开发发布的严格 git 分支模型，用于管理多人协作的大型项目中实现高效的协作开发；Git Flow 分支模型最早起源于 [Vincent Driessen](http://nvie.com/about/) 的 [A successful Git branching model](http://nvie.com/posts/a-successful-git-branching-model/) 文章；随着时间发展，Git Flow 大致分为三种:

- Git Flow: 最原始的 Git Flow 分支模型
- Github Flow: Git Flow 的简化版，专门配合持续发布
- GitLab Flow: Git Flow 与 Github Flow 的结合版

关于三种 Git Flow 区别详情可参考 [Git 工作流程](http://www.ruanyifeng.com/blog/2015/12/git-workflow.html)

### 二、 Git Flow 流程

Github Flow 和 GitLab Flow 对于持续发布支持比较好，但是原始版本的 Git Flow 对于传统的按照版本发布更加友好一些，所以以下主要说明以下 Git Flow 的工作流程；Git Flow 主要分支模型如下

![git flow](https://mritd.b0.upaiyun.com/markdown/80dio.jpg)


在整个分支模型中 **存在两个长期分支: develop 和 master**，其中 develop 分支为开发分支，master 为生产分支；**master 代码始终保持随时可以部署到线上的状态；develop 分支用于合并最新提交的功能性代码**；具体的分支定义如下


- master: 生产代码，始终保持可以直接部署生产的状态
- develop: 开发分支，每次合并最新功能代码到此分支
- feature: 新功能分支，所有新开发的功能将采用 `feature/xxxx` 形式命名分支
- hotfixes: 紧急修复补丁分支，当新功能部署到了线上出现了严重 bug 需要紧急修复时，则创建 `hotfixes/xxxx` 形式命名的分支
- release: 稳定版分支，当完成大版本变动后，应该创建 `release/xxxx` 分支

在整个分支模型中，develop 分支为最上游分支，会不断有新的 feature 合并入 develop 分支，当功能开发达到完成所有版本需求时，则从 develop 分支创建 release 分支，release 后如没有发现其他问题，最终 release 会被合并到 master 分支以完成线上部署

### 三、Git Flow 工具

针对于 Git Flow，其手动操作 git 命令可能过于繁琐，所以后来有了 git-flow 工具；git-flow 是一个 git 扩展集，按 Vincent Driessen 的分支模型提供高层次的库操作；使用 git-flow 工具可以以更加简单的命令完成对 Vincent Driessen 分支模型的实践；
git-flow 安装以及使用具体请参考 [git-flow 备忘清单](https://danielkummer.github.io/git-flow-cheatsheet/index.zh_CN.html)，该文章详细描述了 git-flow 工具的使用方式

还有另一个工具是 [git-extras](https://github.com/tj/git-extras)，该工具没有 git-flow 那么简单化，不过其提供更加强大的命令支持

### 四、Git Commit Message

在整个 Git Flow 中，commit message 也是必不可少的一部分；一个良好且统一的 commit message 有助于代码审计以及 review 等；目前使用最广泛的写法是 [Angular 社区规范](https://docs.google.com/document/d/1QrDFcIiPjSLDn3EL15IJygNPiHORgU1_OOAqWjiDU5Y/edit#heading=h.greljkmo14y0)，该规范大中 commit message 格式大致如下:

``` sh
<type>(<scope>): <subject>
<BLANK LINE>
<body>
<BLANK LINE>
<footer>
```

总体格式大致分为 3 部分，首行主要 3 个组成部分:

- type: 本次提交类型
- scope: 本次提交影响范围，一般标明影响版本号或者具体的范围如 `$browser, $compile, $rootScope, ngHref, ngClick, ngView, etc...`
- subject: 本次提交简短说明

关于 type 提交类型，有如下几种值:

- feat：新功能(feature)
- fix：修补 bug
- docs：文档(documentation)
- style： 格式(不影响代码运行的变动)
- refactor：重构(即不是新增功能，也不是修改 bug 的代码变动)
- test：增加测试
- chore：构建过程或辅助工具的变动

中间的 body 部分是对本次提交的详细描述信息，底部的 footer 部分一般分为两种情况:

- 不兼容变动: 如果出现不兼容变动，则以 `BREAKING CHANGE:` 开头，后面跟上不兼容变动的具体描述和解决办法
- 关闭 issue: 如果该 commit 针对某个 issue，并且可以将其关闭，则可以在其中指定关闭的 issue，如 `Close #9527,#9528`

不过 footer 部分也有特殊情况，如回滚某次提交，则以 `revert:` 开头，后面紧跟 commit 信息和具体描述；还有时某些 commit 只是解决了 某个 issue 的一部分问题，这是可以使用 `refs ISSUE` 的方式来引用该 issue 


### 五、Git Commit Message 工具

针对 Git 的 commit message 目前已经有了成熟的生成工具，比较有名的为 [commitizen-cli](https://github.com/commitizen/cz-cli) 工具，其采用 node.js 编写，执行 `git cz` 命令能够自动生成符合 Angular 社区规范的 commit message；不过由于其使用 node.js 编写，所以安装前需要安装 node.js，因此可能不适合其他非 node.js 的项目使用；这里推荐一个基于 shell 编写的 [Git-toolkit](https://cimhealth.github.io/git-toolkit)，安装此工具后执行 `git ci` 命令进行提交将会产生交互式生成 Angular git commit message 格式的提交说明，截图如下:

![git ci](https://mritd.b0.upaiyun.com/markdown/xnonb.jpg)

### 六、GitLab 整合

以上 Git Flow 所有操作介绍的都是在本地操作，而正常我们在工作中都是基于 GitLab 搭建私有 Git 仓库来进行协同开发的，以下简述以下 Git Flow 配合 GitLab 的流程

#### 6.1、开发 features

当开发一个新功能时流程如下:

- 本地 `git flow feature start xxxx` 开启一个 feature 新分支
- `git flow feature publish xxxx` 将此分支推送到远端以便他人获取
- 完成开发后 GitLab 上向 `develop` 分支发起合并请求
- CI sonar 等质量检测工具扫描，其他用户 review 代码
- 确认无误后 `master` 权限用户合并其到 `develop` 分支
- 部署到测试环境以便测试组测试
- 如果测试不通过，则继续基于此分支开发，直到该功能开发完成

#### 6.2、创建 release

当一定量的 feature 开发完成并合并到 develop 后，如所有 feature 都测试通过并满足版本需求，则可以创建 release 版本分支；release 分支流程如下

- 本地 `git flow release start xxxx` 开启 release 分支
- `git flow release publish xxxx` 将其推送到远端以便他人获取
- 继续进行完整性测试，出现问题继续修复，直到 release 完全稳定
- 从 release 分支向 master、develop 分支分别发起合并请求
- master 合并后创建对应的 release 标签，并部署生产环境
- develop 合并 release 的后期修改

#### 6.3、紧急修复

当 master 某个 tag 部署到生产环境后，也可能出现不符合预期的问题出现；此时应该基于 master 创建 hotfix 分支进行修复，流程如下

- 本地 `git flow hotfix start xxxx` 创建紧急修复分支
- 修改代码后将其推送到远端，并像 master、develop 分支发起合并
- develop 合并紧急修复补丁，如果必要最好再做一下测试
- master 合并紧急修复补丁，创建紧急修复 tag，并部署生产环境

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
