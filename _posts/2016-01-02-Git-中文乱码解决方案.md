---
layout: post
title: Git 中文乱码解决方案
categories: [Git]
description: Git 中文乱码解决方案
keywords: Git,中文乱码
---

![hexo_git_encoding](https://mritd.b0.upaiyun.com/markdown/hexo_git_encoding.png)

> 今天在虚拟机中提交时 `git status` 了一下，发现中文文件名都变成了 `\344\270\255\346\226\207` 这种形式，记录一下解决方案。

<!--more-->

- 没修改配置前的状态

![hexo_git_luanma1](https://mritd.b0.upaiyun.com/markdown/hexo_git_luanma1.png)

- 更改 git 状态输出的编码显示方式

``` bash
# 设置 不会对0×80以上的字符进行quote
git config --global core.quotepath false
```

- 再次查看效果如下

![hexo_git_luanma2](https://mritd.b0.upaiyun.com/markdown/hexo_git_luanma2.png)

- 记录一下其他的配置 摘自 [Github](https://gist.github.com/hidoos/7866314)

> 步骤：
> 1. 下载：http://loaden.googlecode.com/files/gitconfig.7z
> 2. 解压到：<MsysGit安装目录>/cmd/，例如：D:\Program Files\Git\cmd
> 3. 进入Bash，执行gitconfig

> 搞定什么了？
> 看看gitconfig的内容先：

``` bash
#!/bin/sh

# 全局提交用户名与邮箱
git config --global user.name "Yuchen Deng"
git config --global user.email 邮箱名@gmail.com

# 中文编码支持
echo "export LESSCHARSET=utf-8" > $HOME/.profile
git config --global gui.encoding utf-8
git config --global i18n.commitencoding utf-8
git config --global i18n.logoutputencoding gbk

# 全局编辑器，提交时将COMMIT_EDITMSG编码转换成UTF-8可避免乱码
git config --global core.editor notepad2

# 差异工具配置
git config --global diff.external git-diff-wrapper.sh
git config --global diff.tool tortoise
git config --global difftool.tortoise.cmd 'TortoiseMerge -base:"$LOCAL" -theirs:"$REMOTE"'
git config --global difftool.prompt false

# 合并工具配置
git config --global merge.tool tortoise
git config --global mergetool.tortoise.cmd 'TortoiseMerge -base:"$BASE" -theirs:"$REMOTE" -mine:"$LOCAL" -merged:"$MERGED"'
git config --global mergetool.prompt false

# 别名设置
git config --global alias.dt difftool
git config --global alias.mt mergetool

# 取消 $ git gui 的中文界面，改用英文界面更易懂
if [ -f "/share/git-gui/lib/msgs/zh_cn.msg" ]; then
rm /share/git-gui/lib/msgs/zh_cn.msg
fi
```

> 这个脚本解决了：
> 1. 中文乱码
> 2. 图形化Diff/Merge
> 3. 还原英文界面，更好懂
> 其中最有价值的，就是Git的Diff/Merge外部工具TortoiseMerge配置。
> 安装MsysGit后，一个命令即可完成配置。
> 适用于MsysGit安装版与绿色版。

> 网上关于为Git配置TortoiseMerge来进行diff和merge的介绍几乎没有（反正我没有搜索到），但我认为TortoiseMerge是最好用的，单文件（一个可执行程序，绿色版，下载地址：http://sourceforge.net/projects/tortoisesvn/files/Tools/1.6.7/TortoiseDiff-1.6.7.zip/download)，实在是绝配！

> 为什么不使用TortoiseGit？他们不是集成了TortoiseMerge吗？
> 理由：TortoiseGit只有Windows才有，我更喜欢git gui，结合gitk，跨平台实在相同的操作方式，更爽！
> 如果您离不开TortoiseGit，这篇文章就直接无视吧。
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
