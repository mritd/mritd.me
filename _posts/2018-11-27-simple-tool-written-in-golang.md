---
layout: post
categories: Golang Linux
title: Go 编写的一些常用小工具
date: 2018-11-27 12:45:46 +0800
description: Go 编写的一些常用小工具
keywords: 小工具
catalog: true
multilingual: false
tags: Golang Linux
---

> 迫于 Github 上 Star 的项目有点多，今天整理一下一些有意思的 Go 编写的小工具；大多数为终端下的实用工具，装逼的比如天气预报啥的就不写了


### syncthing

强大的文件同步工具，构建私人同步盘 👉 [Github](https://github.com/syncthing、syncthing)

![syncthing](https://mritd.oss.link/markdown/er3tj.jpg)

### fzf

一个强大的终端文件浏览器 👉 [Github](https://github.com/junegunn/fzf)

![fzf](https://mritd.oss.link/markdown/ihhqy.jpg)

### hey

http 负载测试工具，简单好用 👉 [Github](https://github.com/rakyll/hey)

``` sh
Usage: hey [options...] <url>

Options:
  -n  Number of requests to run. Default is 200.
  -c  Number of requests to run concurrently. Total number of requests cannot
      be smaller than the concurrency level. Default is 50.
  -q  Rate limit, in queries per second (QPS). Default is no rate limit.
  -z  Duration of application to send requests. When duration is reached,
      application stops and exits. If duration is specified, n is ignored.
      Examples: -z 10s -z 3m.
  -o  Output type. If none provided, a summary is printed.
      "csv" is the only supported alternative. Dumps the response
      metrics in comma-separated values format.

  -m  HTTP method, one of GET, POST, PUT, DELETE, HEAD, OPTIONS.
  -H  Custom HTTP header. You can specify as many as needed by repeating the flag.
      For example, -H "Accept: text/html" -H "Content-Type: application/xml" .
  -t  Timeout for each request in seconds. Default is 20, use 0 for infinite.
  -A  HTTP Accept header.
  -d  HTTP request body.
  -D  HTTP request body from file. For example, /home/user/file.txt or ./file.txt.
  -T  Content-type, defaults to "text/html".
  -a  Basic authentication, username:password.
  -x  HTTP Proxy address as host:port.
  -h2 Enable HTTP/2.

  -host    HTTP Host header.

  -disable-compression  Disable compression.
  -disable-keepalive    Disable keep-alive, prevents re-use of TCP
                        connections between different HTTP requests.
  -disable-redirects    Disable following of HTTP redirects
  -cpus                 Number of used cpu cores.
                        (default for current machine is 8 cores)
```

### vegeta

http 负载测试工具，功能强大 👉 [Github](https://github.com/tsenart/vegeta)

``` sh
Usage: vegeta [global flags] <command> [command flags]

global flags:
  -cpus int
        Number of CPUs to use (default 8)
  -profile string
        Enable profiling of [cpu, heap]
  -version
        Print version and exit

attack command:
  -body string
        Requests body file
  -cert string
        TLS client PEM encoded certificate file
  -connections int
        Max open idle connections per target host (default 10000)
  -duration duration
        Duration of the test [0 = forever]
  -format string
        Targets format [http, json] (default "http")
  -h2c
        Send HTTP/2 requests without TLS encryption
  -header value
        Request header
  -http2
        Send HTTP/2 requests when supported by the server (default true)
  -insecure
        Ignore invalid server TLS certificates
  -keepalive
        Use persistent connections (default true)
  -key string
        TLS client PEM encoded private key file
  -laddr value
        Local IP address (default 0.0.0.0)
  -lazy
        Read targets lazily
  -max-body value
        Maximum number of bytes to capture from response bodies. [-1 = no limit] (default -1)
  -name string
        Attack name
  -output string
        Output file (default "stdout")
  -rate value
        Number of requests per time unit (default 50/1s)
  -redirects int
        Number of redirects to follow. -1 will not follow but marks as success (default 10)
  -resolvers value
        List of addresses (ip:port) to use for DNS resolution. Disables use of local system DNS. (comma separated list)
  -root-certs value
        TLS root certificate files (comma separated list)
  -targets string
        Targets file (default "stdin")
  -timeout duration
        Requests timeout (default 30s)
  -workers uint
        Initial number of workers (default 10)

encode command:
  -output string
        Output file (default "stdout")
  -to string
        Output encoding [csv, gob, json] (default "json")

plot command:
  -output string
        Output file (default "stdout")
  -threshold int
        Threshold of data points above which series are downsampled. (default 4000)
  -title string
        Title and header of the resulting HTML page (default "Vegeta Plot")

report command:
  -every duration
        Report interval
  -output string
        Output file (default "stdout")
  -type string
        Report type to generate [text, json, hist[buckets]] (default "text")

examples:
  echo "GET http://localhost/" | vegeta attack -duration=5s | tee results.bin | vegeta report
  vegeta report -type=json results.bin > metrics.json
  cat results.bin | vegeta plot > plot.html
  cat results.bin | vegeta report -type="hist[0,100ms,200ms,300ms]"
```

### dive

功能强大的 Docker 镜像分析工具，可以查看每层镜像的具体差异等 👉 [Github](https://github.com/wagoodman/dive)

![dive](https://mritd.oss.link/markdown/ik3ng.gif)

### ctop

容器运行时资源分析，如 CPU、内存消耗等 👉 [Github](https://github.com/bcicen/ctop)

![ctop](https://mritd.oss.link/markdown/mr3x3.gif)

### container-diff

Google 推出的工具，功能就顾名思义了 👉 [Github](https://github.com/GoogleContainerTools/container-diff)

![container-diff](https://mritd.oss.link/markdown/dtapx.png)

### transfer.sh

快捷的终端文件分享工具 👉 [Github](https://github.com/dutchcoders/transfer.sh)

![transfer.sh](https://mritd.oss.link/markdown/76vh0.png)

### vuls

 Linux/FreeBSD 漏洞扫描工具 👉 [Github](https://github.com/future-architect/vuls)
 
 ![vuls](https://mritd.oss.link/markdown/bpsps.jpg)

### restic

高性能安全的文件备份工具 👉 [Github](https://github.com/restic/restic)

![restic](https://mritd.oss.link/markdown/g51z4.png)

### gitql

使用 sql 的方式查询 git 提交 👉 [Github](https://github.com/cloudson/gitql)

![gitql](https://mritd.oss.link/markdown/4h095.gif)

### gitflow-toolkit

帮助生成满足 Gitflow 格式 commit message 的小工具(自己写的) 👉 [Github](https://github.com/mritd/gitflow-toolkit)

![gitflow-toolkit](https://mritd.oss.link/markdown/1e2v1.gif)

### git-chglog

对主流的 Gitflow 格式的 commit message 生成 CHANGELOG 👉 [Github](https://github.com/git-chglog/git-chglog)

![git-chglog](https://mritd.oss.link/markdown/zphxd.gif)

### grv

一个 git 终端图形化浏览工具 👉 [Github](https://github.com/rgburke/grv)

![grv](https://mritd.oss.link/markdown/k1vh2.jpg)

### jid

命令行 json 格式化处理工具，类似 jq，不过感觉更加强大 👉 [Github](https://github.com/simeji/jid)

![jid](https://mritd.oss.link/markdown/3k4ue.gif)

### annie

类似 youget 的一个视频下载工具，可以解析大部分视频网站直接下载 👉 [Github](https://github.com/iawia002/annie)

``` sh
$ annie -i https://www.youtube.com/watch?v=dQw4w9WgXcQ

 Site:      YouTube youtube.com
 Title:     Rick Astley - Never Gonna Give You Up (Video)
 Type:      video
 Streams:   # All available quality
     [248]  -------------------
     Quality:         1080p video/webm; codecs="vp9"
     Size:            49.29 MiB (51687554 Bytes)
     # download with: annie -f 248 ...

     [137]  -------------------
     Quality:         1080p video/mp4; codecs="avc1.640028"
     Size:            43.45 MiB (45564306 Bytes)
     # download with: annie -f 137 ...

     [398]  -------------------
     Quality:         720p video/mp4; codecs="av01.0.05M.08"
     Size:            37.12 MiB (38926432 Bytes)
     # download with: annie -f 398 ...

     [136]  -------------------
     Quality:         720p video/mp4; codecs="avc1.4d401f"
     Size:            31.34 MiB (32867324 Bytes)
     # download with: annie -f 136 ...

     [247]  -------------------
     Quality:         720p video/webm; codecs="vp9"
     Size:            31.03 MiB (32536181 Bytes)
     # download with: annie -f 247 ...
```

### up

Linux 下管道式终端搜索工具 👉 [Github](https://github.com/akavel/up)

![up](https://mritd.oss.link/markdown/n8zdj.gif)

### lego

Let's Encrypt 证书申请工具 👉 [Github](https://github.com/xenolf/lego)

``` sh
NAME:
   lego - Let's Encrypt client written in Go

USAGE:
   lego [global options] command [command options] [arguments...]

COMMANDS:
     run      Register an account, then create and install a certificate
     revoke   Revoke a certificate
     renew    Renew a certificate
     dnshelp  Shows additional help for the --dns global option
     help, h  Shows a list of commands or help for one command

GLOBAL OPTIONS:
   --domains value, -d value   Add a domain to the process. Can be specified multiple times.
   --csr value, -c value       Certificate signing request filename, if an external CSR is to be used
   --server value, -s value    CA hostname (and optionally :port). The server certificate must be trusted in order to avoid further modifications to the client. (default: "https://acme-v02.api.letsencrypt.org/directory")
   --email value, -m value     Email used for registration and recovery contact.
   --filename value            Filename of the generated certificate
   --accept-tos, -a            By setting this flag to true you indicate that you accept the current Let's Encrypt terms of service.
   --eab                       Use External Account Binding for account registration. Requires --kid and --hmac.
   --kid value                 Key identifier from External CA. Used for External Account Binding.
   --hmac value                MAC key from External CA. Should be in Base64 URL Encoding without padding format. Used for External Account Binding.
   --key-type value, -k value  Key type to use for private keys. Supported: rsa2048, rsa4096, rsa8192, ec256, ec384 (default: "rsa2048")
   --path value                Directory to use for storing the data (default: "./.lego")
   --exclude value, -x value   Explicitly disallow solvers by name from being used. Solvers: "http-01", "dns-01", "tls-alpn-01".
   --webroot value             Set the webroot folder to use for HTTP based challenges to write directly in a file in .well-known/acme-challenge
   --memcached-host value      Set the memcached host(s) to use for HTTP based challenges. Challenges will be written to all specified hosts.
   --http value                Set the port and interface to use for HTTP based challenges to listen on. Supported: interface:port or :port
   --tls value                 Set the port and interface to use for TLS based challenges to listen on. Supported: interface:port or :port
   --dns value                 Solve a DNS challenge using the specified provider. Disables all other challenges. Run 'lego dnshelp' for help on usage.
   --http-timeout value        Set the HTTP timeout value to a specific value in seconds. The default is 10 seconds. (default: 0)
   --dns-timeout value         Set the DNS timeout value to a specific value in seconds. The default is 10 seconds. (default: 0)
   --dns-resolvers value       Set the resolvers to use for performing recursive DNS queries. Supported: host:port. The default is to use the system resolvers, or Google's DNS resolvers if the system's cannot be determined.
   --pem                       Generate a .pem file by concatenating the .key and .crt files together.
   --help, -h                  show help
   --version, -v               print the version
```

### noti

贼好用的终端命令异步执行通知工具 👉 [Github](https://github.com/variadico/noti)

![noti](https://mritd.oss.link/markdown/m2r1e.jpg)

### gosu

临时切换到指定用户运行特定命令，方便测试权限问题 👉 [Github](https://github.com/tianon/gosu)

``` sh
$ gosu
Usage: ./gosu user-spec command [args]
   eg: ./gosu tianon bash
       ./gosu nobody:root bash -c 'whoami && id'
       ./gosu 1000:1 id
```

### sup

类似 Ansible 的一个批量执行工具，暂且称之为低配版 Ansible 👉 [Github](https://github.com/pressly/sup)

![sup](https://mritd.oss.link/markdown/x0eaz.gif)

### aptly

Debian 仓库管理工具 👉 [Github](https://github.com/aptly-dev/aptly)

![aptly](https://mritd.oss.link/markdown/8e0ml.jpg)

### mmh

支持无限跳板机登录的 ssh 小工具(自己写的) 👉 [Github](https://github.com/mritd/mmh)

![mmh](https://mritd.oss.link/markdown/37638.gif)



转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
