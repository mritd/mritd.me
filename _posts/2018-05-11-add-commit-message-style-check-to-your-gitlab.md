---
layout: post
categories: CI/CD
title: 为你的 GitLab 增加提交信息检测
date: 2018-05-11 17:44:40 +0800
description: 为 GitLab 添加提交信息检测
keywords: gitlab,提交格式,检测
catalog: true
multilingual: false
tags: CI/CD
---

> 最近准备对项目生成 Change Log，然而发现提交格式不统一根本没法处理；so 后来大家约定式遵循 GitFlow，并使用 Angular 社区规范的提交格式，同时扩展了一些前缀如 hotfix 等；但是时间长了发现还是有些提交为了 "方便" 不遵循 Angular 社区规范的提交格式，这时候我唯一能做的就是想办法在服务端增加一个提交检测；以下记录了 GitLab 增加自定义 Commit 提交格式检测的方案

## 一、相关文章资料

最开始用 Google 搜索到的方案是使用 GitLab 的 Push Rules 功能，具体文档见 [这里](https://docs.gitlab.com/ee/push_rules/push_rules.html)，看完了我才发现这是企业版独有的，作为比较有逼格(qiong)的我们是不可能接受这种 "没技术含量" 的方式的；后来找了好多资料，发现还得借助 Git Hook 功能，文档见 [Custom Git Hooks](https://docs.gitlab.com/ee/administration/custom_hooks.html)；简单地说 Git Hook 就是在 git 操作的不同阶段执行的预定义脚本，**GitLab 目前仅支持 `pre-receive` 这个钩子，当然他可以链式调用**；所以一切操作就得从这里入手

## 二、pre-receive 实现

查阅了相关资料得出，在进行 push 时，GitLab 会调用这个钩子文件，这个钩子文件必须放在 `/var/opt/gitlab/git-data/repositories/<group>/<project>.git/custom_hooks` 目录中，当然具体路径也可能是 `/home/git/repositories/<group>/<project>.git/custom_hooks`；`custom_hooks` 目录需要自己创建，具体可以参阅文档的 [Setup](https://docs.gitlab.com/ee/administration/custom_hooks.html#setup)；

**在进行 push 操作时，GitLab 会调用这个钩子文件，并且从 stdin 输入三个参数，分别为 之前的版本 commit ID、push 的版本 commit ID 和 push 的分支；根据 commit ID 我们就可以很轻松的获取到提交信息，从而实现进一步检测动作；根据 GitLab 的文档说明，当这个 hook 执行后以非 0 状态退出则认为执行失败，从而拒绝 push；同时会将 stderr 信息返回给 client 端；**说了这么多，下面就可以直接上代码了，为了方便我就直接用 go 造了一个 [pre-receive](https://github.com/mritd/pre-receive)，官方文档说明了不限制语言


``` golang
package main

import (
    "fmt"
    "io/ioutil"
    "os"
    "os/exec"
    "regexp"
    "strings"
)

type CommitType string

const (
    FEAT     CommitType = "feat"
    FIX      CommitType = "fix"
    DOCS     CommitType = "docs"
    STYLE    CommitType = "style"
    REFACTOR CommitType = "refactor"
    TEST     CommitType = "test"
    CHORE    CommitType = "chore"
    PERF     CommitType = "perf"
    HOTFIX   CommitType = "hotfix"
)
const CommitMessagePattern = `^(?:fixup!\s*)?(\w*)(\(([\w\$\.\*/-].*)\))?\: (.*)|^Merge\ branch(.*)`

const checkFailedMeassge = `##############################################################################
##                                                                          ##
## Commit message style check failed!                                       ##
##                                                                          ##
## Commit message style must satisfy this regular:                          ##
##   ^(?:fixup!\s*)?(\w*)(\(([\w\$\.\*/-].*)\))?\: (. *)|^Merge\ branch(.*) ##
##                                                                          ##
## Example:                                                                 ##
##   feat(test): test commit style check.                                   ##
##                                                                          ##
##############################################################################`

// 是否开启严格模式，严格模式下将校验所有的提交信息格式(多 commit 下)
const strictMode = false

var commitMsgReg = regexp.MustCompile(CommitMessagePattern)

func main() {

    input, _ := ioutil.ReadAll(os.Stdin)
    param := strings.Fields(string(input))

    // allow branch/tag delete
    if param[1] == "0000000000000000000000000000000000000000" {
        os.Exit(0)
    }

    commitMsg := getCommitMsg(param[0], param[1])
    for _, tmpStr := range commitMsg {
        commitTypes := commitMsgReg.FindAllStringSubmatch(tmpStr, -1)

        if len(commitTypes) != 1 {
            checkFailed()
        } else {
            switch commitTypes[0][1] {
            case string(FEAT):
            case string(FIX):
            case string(DOCS):
            case string(STYLE):
            case string(REFACTOR):
            case string(TEST):
            case string(CHORE):
            case string(PERF):
            case string(HOTFIX):
            default:
                if !strings.HasPrefix(tmpStr, "Merge branch") {
                    checkFailed()
                }
            }
        }
        if !strictMode {
            os.Exit(0)
        }
    }

}

func getCommitMsg(odlCommitID, commitID string) []string {
    getCommitMsgCmd := exec.Command("git", "log", odlCommitID+".."+commitID, "--pretty=format:%s")
    getCommitMsgCmd.Stdin = os.Stdin
    getCommitMsgCmd.Stderr = os.Stderr
    b, err := getCommitMsgCmd.Output()
    if err != nil {
        fmt.Print(err)
        os.Exit(1)
    }

    commitMsg := strings.Split(string(b), "\n")
    return commitMsg
}

func checkFailed() {
    fmt.Fprintln(os.Stderr, checkFailedMeassge)
    os.Exit(1)
}

```

## 三、安装 pre-receive

把以上代码编译后生成的 `pre-receive` 文件复制到对应项目的钩子目录即可；**要注意的是文件名必须为 `pre-receive`，同时 `custom_hooks` 目录需要自建；`custom_hooks` 目录以及 `pre-receive` 文件用户组必须为 `git:git`；在删除分支时 commit ID 为 `0000000000000000000000000000000000000000`，此时不需要检测提交信息，否则可能导致无法删除分支/tag**；最后效果如下所示

![commit msg check](https://oss.link/markdown/hs9c2.png)


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
