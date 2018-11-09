---
layout: post
categories: Golang
title: Go ssh 交互式执行命令
date: 2018-11-09 23:13:44 +0800
description: Go ssh 交互式执行命令
keywords: golang,ssh
catalog: true
multilingual: false
tags: Golang
---

> 最近在写一个跳板机登录的小工具，其中涉及到了用 Go 来进行交互式执行命令，简单地说就是弄个终端出来；一开始随便 Google 了一下，copy 下来基本上就是能跑了...但是后来发现了一些各种各样的小问题，强迫症的我实在受不了，最后翻了一下 Teleport 的源码，从中学到了不少有用的知识，这里记录一下

## 一、原始版本

> 不想看太多可以直接跳转到 [第三部分](#完整代码) 拿代码

### 1.1、样例代码

一开始随便 Google 出来的代码，copy 上就直接跑；代码基本如下:

``` golang
func main() {

	// 创建 ssh 配置
	sshConfig := &ssh.ClientConfig{
		User: "root",
		Auth: []ssh.AuthMethod{
			ssh.Password("password"),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
		Timeout:         5 * time.Second,
	}

	// 创建 client
	client, err := ssh.Dial("tcp", "192.168.1.20:22", sshConfig)
	checkErr(err)
	defer client.Close()

	// 获取 session
	session, err := client.NewSession()
	checkErr(err)
	defer session.Close()

	// 拿到当前终端文件描述符
	fd := int(os.Stdin.Fd())
	termWidth, termHeight, err := terminal.GetSize(fd)

	// request pty
	err = session.RequestPty("xterm-256color", termHeight, termWidth, ssh.TerminalModes{})
	checkErr(err)

	// 对接 std
	session.Stdout = os.Stdout
	session.Stderr = os.Stderr
	session.Stdin = os.Stdin

	err = session.Shell()
	checkErr(err)
	err = session.Wait()
	checkErr(err)

}

func checkErr(err error) {
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}
```

### 1.2、遇到的问题

以上代码跑起来后，基本上遇到了以下问题:

- 执行命令有回显，表现为敲一个 `ls` 出现两行
- 本地终端大小调整，远端完全无反应，导致显示不全
- Tmux 下终端连接后窗口标题显示的是原始命令，而不是目标机器 shell 环境的目录位置
- 首次连接一些刚装完系统的机器可能出现执行命令后回显不换行

## 二、改进代码

### 2.1、回显问题

关于回显问题，实际上解决方案很简单，设置当前终端进入 `raw` 模式即可；代码如下:

``` golang
// 拿到当前终端文件描述符
fd := int(os.Stdin.Fd())
// make raw
state, err := terminal.MakeRaw(fd)
checkErr(err)
defer terminal.Restore(fd, state)
```

代码很简单，网上一大堆，But...基本没有文章详细说这个 `raw` 模式到底是个啥玩意；好在万能的 StackOverflow 对于不熟悉 Linux 的人给出了一个很清晰的解释: [What’s the difference between a “raw” and a “cooked” device driver?](https://unix.stackexchange.com/questions/21752/what-s-the-difference-between-a-raw-and-a-cooked-device-driver)


大致意思就是说 **在终端处于 `Cooked` 模式时，当你输入一些字符后，默认是被当前终端 cache 住的，在你敲了回车之前这些文本都在 cache 中，这样允许应用程序做一些处理，比如捕获 `Cntl-D` 等按键，这时候就会出现敲回车后本地终端帮你打印了一下，导致出现类似回显的效果；当设置终端为 `raw` 模式后，所有的输入将不被 cache，而是发送到应用程序，在我们的代码中表现为通过 `io.Copy` 直接发送到了远端 shell 程序**

### 2.2、终端大小问题

当本地调整了终端大小后，远程终端毫无反应；后来发现在 `*ssh.Session` 上有一个 `WindowChange` 方法，用于向远端发送窗口调整事件；解决方案就是启动一个 `goroutine` 在后台不断监听窗口改变事件，然后调用 `WindowChange` 即可；代码如下:

``` golang
go func() {
	// 监听窗口变更事件
	sigwinchCh := make(chan os.Signal, 1)
	signal.Notify(sigwinchCh, syscall.SIGWINCH)

	fd := int(os.Stdin.Fd())
	termWidth, termHeight, err := terminal.GetSize(fd)
	if err != nil {
		fmt.Println(err)
	}

	for {
		select {
		// 阻塞读取
		case sigwinch := <-sigwinchCh:
			if sigwinch == nil {
				return
			}
			currTermWidth, currTermHeight, err := terminal.GetSize(fd)

			// 判断一下窗口尺寸是否有改变
			if currTermHeight == termHeight && currTermWidth == termWidth {
				continue
			}
			// 更新远端大小
			session.WindowChange(currTermHeight, currTermWidth)
			if err != nil {
				fmt.Printf("Unable to send window-change reqest: %s.", err)
				continue
			}

			termWidth, termHeight = currTermWidth, currTermHeight

		}
	}
}()
```

### 2.3、Tmux 标题以及回显不换行

这两个问题实际上都是由于我们直接对接了 `stderr`、`stdout` 和 `stdin` 造成的，实际上我们应当启动一个异步的管道式复制行为，并且最好带有 buf 的发送；代码如下:

``` golang
stdin, err := session.StdinPipe()
checkErr(err)
stdout, err := session.StdoutPipe()
checkErr(err)
stderr, err := session.StderrPipe()
checkErr(err)

go io.Copy(os.Stderr, stderr)
go io.Copy(os.Stdout, stdout)
go func() {
	buf := make([]byte, 128)
	for {
		n, err := os.Stdin.Read(buf)
		if err != nil {
			fmt.Println(err)
			return
		}
		if n > 0 {
			_, err = stdin.Write(buf[:n])
			if err != nil {
				checkErr(err)
			}
		}
	}
}()
```

## 三、完整代码

``` golang
type SSHTerminal struct {
	Session *ssh.Session
	exitMsg string
	stdout  io.Reader
	stdin   io.Writer
	stderr  io.Reader
}

func main() {
	sshConfig := &ssh.ClientConfig{
		User: "root",
		Auth: []ssh.AuthMethod{
			ssh.Password("password"),
		},
		HostKeyCallback: ssh.InsecureIgnoreHostKey(),
	}

	client, err := ssh.Dial("tcp", "192.168.1.20:22", sshConfig)
	if err != nil {
		fmt.Println(err)
	}
	defer client.Close()
	
	err = New(client)
	if err != nil {
		fmt.Println(err)
	}
}

func (t *SSHTerminal) updateTerminalSize() {

	go func() {
		// SIGWINCH is sent to the process when the window size of the terminal has
		// changed.
		sigwinchCh := make(chan os.Signal, 1)
		signal.Notify(sigwinchCh, syscall.SIGWINCH)

		fd := int(os.Stdin.Fd())
		termWidth, termHeight, err := terminal.GetSize(fd)
		if err != nil {
			fmt.Println(err)
		}

		for {
			select {
			// The client updated the size of the local PTY. This change needs to occur
			// on the server side PTY as well.
			case sigwinch := <-sigwinchCh:
				if sigwinch == nil {
					return
				}
				currTermWidth, currTermHeight, err := terminal.GetSize(fd)

				// Terminal size has not changed, don't do anything.
				if currTermHeight == termHeight && currTermWidth == termWidth {
					continue
				}

				t.Session.WindowChange(currTermHeight, currTermWidth)
				if err != nil {
					fmt.Printf("Unable to send window-change reqest: %s.", err)
					continue
				}

				termWidth, termHeight = currTermWidth, currTermHeight

			}
		}
	}()

}

func (t *SSHTerminal) interactiveSession() error {

	defer func() {
		if t.exitMsg == "" {
			fmt.Fprintln(os.Stdout, "the connection was closed on the remote side on ", time.Now().Format(time.RFC822))
		} else {
			fmt.Fprintln(os.Stdout, t.exitMsg)
		}
	}()

	fd := int(os.Stdin.Fd())
	state, err := terminal.MakeRaw(fd)
	if err != nil {
		return err
	}
	defer terminal.Restore(fd, state)

	termWidth, termHeight, err := terminal.GetSize(fd)
	if err != nil {
		return err
	}

	termType := os.Getenv("TERM")
	if termType == "" {
		termType = "xterm-256color"
	}

	err = t.Session.RequestPty(termType, termHeight, termWidth, ssh.TerminalModes{})
	if err != nil {
		return err
	}

	t.updateTerminalSize()

	t.stdin, err = t.Session.StdinPipe()
	if err != nil {
		return err
	}
	t.stdout, err = t.Session.StdoutPipe()
	if err != nil {
		return err
	}
	t.stderr, err = t.Session.StderrPipe()

	go io.Copy(os.Stderr, t.stderr)
	go io.Copy(os.Stdout, t.stdout)
	go func() {
		buf := make([]byte, 128)
		for {
			n, err := os.Stdin.Read(buf)
			if err != nil {
				fmt.Println(err)
				return
			}
			if n > 0 {
				_, err = t.stdin.Write(buf[:n])
				if err != nil {
					fmt.Println(err)
					t.exitMsg = err.Error()
					return
				}
			}
		}
	}()

	err = t.Session.Shell()
	if err != nil {
		return err
	}
	err = t.Session.Wait()
	if err != nil {
		return err
	}
	return nil
}

func New(client *ssh.Client) error {

	session, err := client.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()

	s := SSHTerminal{
		Session: session,
	}

	return s.interactiveSession()
}
```


转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
