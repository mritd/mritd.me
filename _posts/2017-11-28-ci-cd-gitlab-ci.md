---
layout: post
categories: CI/CD
title: CI/CD 之 GitLab CI
date: 2017-11-28 17:43:23 +0800
description: CI/CD 之 GitLab CI
keywords: CI/CD GitLab CI Runner
---

> 接着上篇文章整理，这篇文章主要介绍一下 GitLab CI 相关功能，并通过 GitLab CI 实现自动化构建项目；项目中所用的示例项目已经上传到了 [GitHub](https://github.com/mritd/GitLabCI-TestProject)

### 一、环境准备

首先需要有一台 GitLab 服务器，然后需要有个项目；这里示例项目以 Spring Boot 项目为例，然后最好有一台专门用来 Build 的机器，实际生产中如果 Build 任务不频繁可适当用一些业务机器进行 Build；本文示例所有组件将采用 Docker 启动， GitLab HA 等不在本文阐述范围内


- Docker Version : 1.13.1
- GitLab Version : 10.1.4-ce.0
- GitLab Runner Version : 10.1.0
- GitLab IP : 172.16.0.37
- GitLab Runner IP : 172.16.0.36

### 二、GitLab CI 简介

GitLab CI 是 GitLab 默认集成的 CI 功能，GitLab CI 通过在项目内 `.gitlab-ci.yaml` 配置文件读取 CI 任务并进行相应处理；GitLab CI 通过其称为 GitLab Runner 的 Agent 端进行 build 操作；Runner 本身可以使用多种方式安装，比如使用 Docker 镜像启动等；Runner 在进行 build 操作时也可以选择多种 build 环境提供者；比如直接在 Runner 所在宿主机 build、通过新创建虚拟机(vmware、virtualbox)进行 build等；同时 Runner 支持 Docker 作为 build 提供者，即每次 build 新启动容器进行 build；GitLab CI 其大致架构如下


![GitLab](https://mritd.b0.upaiyun.com/markdown/wejnz.png)

### 三、搭建 GitLab 服务器

#### 3.1、GitLab 搭建

GitLab 搭建这里直接使用 docker compose 启动，compose 配置如下

``` sh
version: '2'
services:
  gitlab:
    image: 'gitlab/gitlab-ce:10.1.4-ce.0'
    restart: always
    container_name: gitlab
    hostname: 'git.mritd.me'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'http://git.mritd.me'
        # Add any other gitlab.rb configuration here, each on its own line
    ports:
      - '80:80'
      - '443:443'
      - '8022:22'
    volumes:
      - './data/gitlab/config:/etc/gitlab'
      - './data/gitlab/logs:/var/log/gitlab'
      - './data/gitlab/data:/var/opt/gitlab'
```

直接启动后，首次登陆需要设置初始密码如下，默认用户为 `root`

![gitkab init](https://mritd.b0.upaiyun.com/markdown/5go94.png)

登陆成功后创建一个用户(该用户最好给予 Admin 权限，以后操作以该用户为例)，并且创建一个测试 Group 和 Project，如下所示

![Create User](https://mritd.b0.upaiyun.com/markdown/vtyhi.png)


![Test Project](https://mritd.b0.upaiyun.com/markdown/3b7gl.png)

#### 3.2、增加示例项目

这里示例项目采用 Java 的 SpringBoot 项目，并采用 Gradle 构建，其他语言原理一样；**如果不熟悉 Java 的没必要死磕此步配置，任意语言(最好 Java)整一个能用的 Web 项目就行，并不强求一定 Java 并且使用 Gradle 构建，以下只是一个样例项目**；SpringBoot 可以采用 [Spring Initializr](https://start.spring.io/) 直接生成(依赖要加入 WEB)，如下所示

![Spring Initializr](https://mritd.b0.upaiyun.com/markdown/0wx6d.png)

将项目导入 IDEA，然后创建一个 index 示例页面，主要修改如下

- build.gradle

``` groovy
buildscript {
    ext {
        springBootVersion = '1.5.8.RELEASE'
    }
    repositories {
        mavenCentral()
    }
    dependencies {
        classpath("org.springframework.boot:spring-boot-gradle-plugin:${springBootVersion}")
    }
}

apply plugin: 'java'
apply plugin: 'eclipse'
apply plugin: 'idea'
apply plugin: 'org.springframework.boot'

group = 'me.mritd'
version = '0.0.1-SNAPSHOT'
sourceCompatibility = 1.8

repositories {
    mavenCentral()
}


dependencies {
    compile('org.springframework.boot:spring-boot-starter')
    compile('org.springframework.boot:spring-boot-starter-web')
    compile('org.springframework.boot:spring-boot-starter-thymeleaf')
    testCompile('org.springframework.boot:spring-boot-starter-test')
}
```

- 新建一个 HomeController

``` java
package me.mritd.TestProject;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;

/*******************************************************************************
 * Copyright (c) 2005-2017 Mritd, Inc.
 * TestProject
 * me.mritd.TestProject
 * Created by mritd on 2017/11/24 下午12:23.
 * Description: 
 *******************************************************************************/
@Controller
public class HomeController {

    @RequestMapping("/")
    public String home(){
        return "index";
    }
}
```

- templates 下新建 index.html

``` html
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8"/>
    <title>Title</title>
</head>
<body>
<h1>Test...</h1>
</body>
</html>
```

最后项目整体结构如下

![TestProject](https://mritd.b0.upaiyun.com/markdown/5k12p.png)

执行 `assemble` Task 打包出可执行 jar 包，并运行 `java -jar TestProject-0.0.1-SNAPSHOT.jar` 测试下能启动访问页面即可

![TestProject assemble](https://mritd.b0.upaiyun.com/markdown/xoj3d.png)

最后将项目提交到 GitLab 后如下

![init Project](https://mritd.b0.upaiyun.com/markdown/1fuex.png)

### 四、GitLab CI 配置

> 针对这一章节创建基础镜像以及项目镜像，这里仅以 Java 项目为例；其他语言原理相通，按照其他语言对应的运行环境修改即可


#### 4.1、增加 Runner

GitLab CI 在进行构建时会将任务下发给 Runner，让 Runner 去执行；所以先要添加一个 Runner，Runner 这里采用 Docker Compose 启动，build 方式也使用 Docker 方式 Build；compose 文件如下

``` yaml
version: '2'
services:
  gitlab-runner:
    container_name: gitlab-runner
    image: gitlab/gitlab-runner:alpine-v10.1.0
    restart: always
    network_mode: "host"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ./config.toml:/etc/gitlab-runner/config.toml
    extra_hosts:
      - "git.mritd.me:172.16.0.37"
```

**在启动前，我们需要先 touch 一下这个 config.toml 配置文件**；该文件是 Runner 的运行配置，此后 Runner 所有配置都会写入这个文件(不 touch 出来 docker-compose 发现不存在会挂载一个目录进去，导致 Runner 启动失败)；启动 docker-compose 后，**需要进入容器执行注册，让 Runner 主动去连接 GitLab 服务器**

``` sh
# 生成 Runner 配置文件
touch config.toml
# 启动 Runner
docker-compose up -d
# 激活 Runner
docker exec -it gitlab-runner gitlab-runner register
```

在执行上一条激活命令后，会按照提示让你输入一些信息；**首先输入 GitLab 地址，然后是 Runner Token，Runner Token 可以从 GitLab 设置中查看**，如下所示

![Runner Token](https://mritd.b0.upaiyun.com/markdown/mfqg7.png)

整体注册流程如下

![Runner registry](https://mritd.b0.upaiyun.com/markdown/r7xay.png)

注册完成后，在 GitLab Runner 设置中就可以看到刚刚注册的 Runner，如下所示

![Runner List](https://mritd.b0.upaiyun.com/markdown/xv03e.png)

**Runner 注册成功后会将配置写入到 config.toml 配置文件；由于两个测试宿主机都没有配置内网 DNS，所以为了保证 runner 在使用 docker build 时能正确的找到 GitLab 仓库地址，还需要增加一个 docker 的 host 映射( `extra_hosts` )；同时为了能调用 宿主机 Docker 和持久化 build 的一些缓存还挂载了一些文件和目录；完整的 配置如下(配置文件可以做一些更高级的配置，具体参考 [官方文档](https://docs.gitlab.com/runner/configuration/advanced-configuration.html) )**

- config.toml

``` toml
concurrent = 1
check_interval = 0

[[runners]]
  name = "Test Runner"
  url = "http://git.mritd.me"
  token = "c279ec1ac08aec98c7141c7cf2d474"
  executor = "docker"
  builds_dir = "/gitlab/runner-builds"
  cache_dir = "/gitlab/runner-cache"
  [runners.docker]
    tls_verify = false
    image = "debian"
    privileged = false
    disable_cache = false
    shm_size = 0
    volumes = ["/data/gitlab-runner:/gitlab","/var/run/docker.sock:/var/run/docker.sock","/data/maven_repo:/data/repo","/data/maven_repo:/data/maven","/data/gradle:/data/gradle","/data/sonar_cache:/root/.sonar","/data/androidsdk:/usr/local/android","/data/node_modules:/data/node_modules"]
    extra_hosts = ["git.mritd.me:172.16.0.37"]
  [runners.cache]
```

**注意，这里声明的 Volumes 会在每个运行的容器中都生效；也就是说 build 时新开启的每个容器都会被挂载这些目录**；修改完成后重启 runner 容器即可，由于 runner 中没啥可保存的东西，所以可以直接 `docker-compose down && docker-compose up -d` 重启

#### 4.2、创建基础镜像

由于示例项目是一个 Java 项目，而且是采用 Spring Boot 的，所以该项目想要运行起来只需要一个 java 环境即可，中间件已经被打包到了 jar 包中；以下是一个作为基础运行环境的 openjdk 镜像的 Dockerfile

``` sh
FROM alpine:edge 

LABEL maintainer="mritd <mritd1234@gmail.com>"

ENV JAVA_HOME /usr/lib/jvm/java-1.8-openjdk
ENV PATH $PATH:/usr/lib/jvm/java-1.8-openjdk/jre/bin:/usr/lib/jvm/java-1.8-openjdk/bin

RUN apk add --update bash curl tar wget ca-certificates unzip \
        openjdk8 font-adobe-100dpi ttf-dejavu fontconfig \
    && rm -rf /var/cache/apk/* \

CMD ["bash"]
```

**这个 openjdk Dockerfile 升级到了 8.151 版本，并且集成了一些字体相关的软件，以解决在 Java 中某些验证码库无法运行问题，详见 [Alpine 3.6 OpenJDK 8 Bug](https://mritd.me/2017/09/27/alpine-3.6-openjdk-8-bug/)**；使用这个 Dockerfile，在当前目录执行 `docker build -t mritd/openjdk:8 .` build 一个 openjdk8 的基础镜像，然后将其推送到私服，或者 Docker Hub 即可


#### 4.3、创建项目镜像

有了基本的 openjdk 的 docker 镜像后，针对于项目每次 build 都应该生成一个包含发布物的 docker 镜像，所以对于项目来说还需要一个项目本身的 Dockerfile；**项目的 Dockerfile 有两种使用方式；一种是动态生成 Dockerfile，然后每次使用新生成的 Dockerfile 去 build；还有一种是写一个通用的 Dockerfile，build 时利用 ARG 参数传入变量**；这里采用第二种方式，以下为一个可以反复使用的 Dockerfile

``` sh
FROM mritd/openjdk:8-144-01

MAINTAINER mritd <mritd1234@gmail.com>

ARG PROJECT_BUILD_FINALNAME

ENV TZ 'Asia/Shanghai'
ENV PROJECT_BUILD_FINALNAME ${PROJECT_BUILD_FINALNAME}


COPY build/libs/${PROJECT_BUILD_FINALNAME}.jar /${PROJECT_BUILD_FINALNAME}.jar

CMD ["bash","-c","java -jar /${PROJECT_BUILD_FINALNAME}.jar"]
```

**该 Dockerfile 通过声明一个 `PROJECT_BUILD_FINALNAME` 变量来表示项目的发布物名称；然后将其复制到根目录下，最终利用 java 执行这个 jar 包；所以每次 build 之前只要能拿到项目发布物的名称即可**


#### 4.4、Gradle 修改

上面已经创建了一个标准的通用型 Dockerfile，每次 build 镜像只要传入 `PROJECT_BUILD_FINALNAME` 这个最终发布物名称即可；对于发布物名称来说，最好不要固定死；当然不论是 Java 还是其他语言的项目我们都能将最终发布物变成一个固定名字，最不济可以写脚本重命名一下；但是不建议那么干，最好保留版本号信息，以便于异常情况下进入容器能够分辨；对于当前 Java 项目来说，想要拿到 `PROJECT_BUILD_FINALNAME` 很简单，我们只需要略微修改一下 Gradle 的 build 脚本，让其每次打包 jar 包时将项目的名称及版本号导出到文件中即可；同时这里也加入了镜像版本号的处理，Gradle 脚本修改如下

- build.gradle 最后面增加如下

``` groovy
bootRepackage {

    mainClass = 'me.mritd.TestProject.TestProjectApplication'
    executable = true

    doLast {
        File envFile = new File("build/tmp/PROJECT_ENV")

        println("Create ${archivesBaseName} ENV File ===> " + envFile.createNewFile())
        println("Export ${archivesBaseName} Build Version ===> ${version}")
        envFile.write("export PROJECT_BUILD_FINALNAME=${archivesBaseName}-${version}\n")

        println("Generate Docker image tag...")
        envFile.append("export BUILD_DATE=`date +%Y%m%d%H%M%S`\n")
        envFile.append("export IMAGE_NAME=mritd/test:`echo \${CI_BUILD_REF_NAME} | tr '/' '-'`-`echo \${CI_COMMIT_SHA} | cut -c1-8`-\${BUILD_DATE}\n")
        envFile.append("export LATEST_IMAGE_NAME=mritd/test:latest\n")
    }
}
```

**这一步操作实际上是修改了 `bootRepackage` 这个 Task(不了解 Gradle 或者不是 Java 项目的请忽略)，在其结束后创建了一个叫 `PROJECT_ENV` 的文件，里面实际上就是写入了一些 bash 环境变量声明，以方便后面 source 一下这个文件拿到一些变量，然后用户 build 镜像使用**，`PROJECT_ENV` 最终生成如下

``` sh
export PROJECT_BUILD_FINALNAME=TestProject-0.0.1-SNAPSHOT
export BUILD_DATE=`date +%Y%m%d%H%M%S`
export IMAGE_NAME=mritd/test:`echo ${CI_BUILD_REF_NAME} | tr '/' '-'`-`echo ${CI_COMMIT_SHA} | cut -c1-8`-${BUILD_DATE}
export LATEST_IMAGE_NAME=mritd/test:latest
```

![PROJECT_ENV](https://mritd.b0.upaiyun.com/markdown/gr6kc.png)


#### 4.5、创建 CI 配置文件

一切准备就绪以后，就可以编写 CI 脚本了；GitLab 依靠读取项目根目录下的 `.gitlab-ci.yml` 文件来执行相应的 CI 操作；以下为测试项目的 `.gitlab-ci.yml` 配置


``` yaml
# 调试开启
#before_script:
#  - pwd
#  - env

cache:
  key: $CI_PROJECT_NAME/$CI_COMMIT_REF_NAME-$CI_COMMIT_SHA
  paths:
    - build

stages:
  - build
  - deploy

auto-build:
  image: mritd/build:2.1.1
  stage: build
  script:
    - gradle --no-daemon clean assemble
  tags:
    - test

deploy:
  image: mritd/docker-kubectl:v1.7.4
  stage: deploy
  script:
    - source build/tmp/PROJECT_ENV
    - echo "Build Docker Image ==> ${IMAGE_NAME}"
    - docker build -t ${IMAGE_NAME} --build-arg PROJECT_BUILD_FINALNAME=${PROJECT_BUILD_FINALNAME} .
#    - docker push ${IMAGE_NAME}
    - docker tag ${IMAGE_NAME} ${LATEST_IMAGE_NAME}
#    - docker push ${LATEST_IMAGE_NAME}
#    - docker rmi ${IMAGE_NAME} ${LATEST_IMAGE_NAME}
#    - kubectl --kubeconfig ${KUBE_CONFIG} set image deployment/test test=$IMAGE_NAME
  tags:
    - test
  only:
    - master
    - develop
    - /^chore.*$/
```

**关于 CI 配置的一些简要说明如下**

##### stages

stages 字段定义了整个 CI 一共有哪些阶段流程，以上的 CI 配置中，定义了该项目的 CI 总共分为 `build`、`deploy` 两个阶段；GitLab CI 会根据其顺序执行对应阶段下的所有任务；**在正常生产环境流程可以定义很多个，比如可以有 `test`、`publish`，甚至可能有代码扫描的 `sonar` 阶段等；这些阶段没有任何限制，完全是自定义的**，上面的阶段定义好后在 CI 中表现如下图

![stages](https://mritd.b0.upaiyun.com/markdown/8c7gs.png)

##### task

task 隶属于 stages 之下；也就是说一个阶段可以有多个任务，任务执行顺序默认不指定会并发执行；对于上面的 CI 配置来说 `auto-build` 和 `deploy` 都是 task，他们通过 `stage: xxxx` 这个标签来指定他们隶属于哪个 stage；当 Runner 使用 Docker 作为 build 提供者时，我们可以在 task 的 `image` 标签下声明该 task 要使用哪个镜像运行，不指定则默认为 Runner 注册时的镜像(这里是 debian)；**同时 task 还有一个 `tags` 的标签，该标签指明了这个任务将可以在哪些 Runner 上运行；这个标签可以从 Runner 页面看到，实际上就是 Runner 注册时输入的哪个 tag；对于某些特殊的项目，比如 IOS 项目，则必须在特定机器上执行，所以此时指定 tags 标签很有用**，当 task 运行后如下图所示

![Task](https://mritd.b0.upaiyun.com/markdown/qzvlh.png)

除此之外 task 还能指定 `only` 标签用于限定那些分支才能触发这个 task，如果分支名字不满足则不会触发；**默认情况下，这些 task 都是自动执行的，如果感觉某些任务太过危险，则可以通过增加 `when: manual` 改为手动执行；注意: 手动执行被 GitLab 认为是高权限的写操作，所以只有项目管理员才能手动运行一个 task，直白的说就是管理员才能点击**；手动执行如下图所示


![manual task](https://mritd.b0.upaiyun.com/markdown/vcjci.png)


##### cache

cache 这个参数用于定义全局那些文件将被 cache；**在 GitLab CI 中，跨 stage 是不能保存东西的；也就是说在第一步 build 的操作生成的 jar 包，到第二部打包 docker image 时就会被删除；GitLab 会保证每个 stage 中任务在执行时都将工作目录(Docker 容器 中)还原到跟 GitLab 代码仓库中一模一样，多余文件及变更都会被删除**；正常情况下，第一步 build 生成 jar 包应当立即推送到 nexus 私服；但是这里测试没有搭建，所以只能放到本地；但是放到本地下一个 task 就会删除它，所以利用 `cache` 这个参数将 `build` 目录 cache 住，保证其跨 stage 也能存在

**关于 `.gitlab-ci.yml` 具体配置更完整的请参考 [官方文档](https://docs.gitlab.com/ee/ci/yaml/)**

### 五、其他相关

#### 5.1、GitLab 内置环境变量

上面已经基本搞定了一个项目的 CI，但是有些变量可能并未说清楚；比如在创建的 `PROJECT_ENV` 文件中引用了 `${CI_COMMIT_SHA}` 变量；这种变量其实是 GitLab CI 的内置隐藏变量，这些变量在每次 CI 调用 Runner 运行某个任务时都会传递到对应的 Runner 的执行环境中；**也就是说这些变量在每次的任务容器 SHELL 环境中都会存在，可以直接引用**，具体的完整环境变量列表可以从 [官方文档](https://docs.gitlab.com/ee/ci/variables/) 中获取；如果想知道环境变量具体的值，实际上可以通过在任务执行前用 `env` 指令打印出来，如下所示

![env](https://mritd.b0.upaiyun.com/markdown/la9kn.png)

![env task](https://mritd.b0.upaiyun.com/markdown/0175j.png)

#### 5.2、GitLab 自定义环境变量

在某些情况下，我们希望 CI 能自动的发布或者修改一些东西；比如将 jar 包上传到 nexus、将 docker 镜像 push 到私服；这些动作往往需要一个高权限或者说有可写入对应仓库权限的账户来支持，但是这些账户又不想写到项目的 CI 配置里；因为这样很不安全，谁都能看到；此时我们可以将这些敏感变量写入到 GitLab 自定义环境变量中，GitLab 会像对待内置变量一样将其传送到 Runner 端，以供我们使用；GitLab 中自定义的环境变量可以有两种，一种是项目级别的，只能够在当前项目使用，如下

![project env](https://mritd.b0.upaiyun.com/markdown/ennug.png)

另一种是组级别的，可以在整个组内的所有项目中使用，如下

![group env](https://mritd.b0.upaiyun.com/markdown/si8ig.png)

这两种变量添加后都可以在 CI 的脚本中直接引用

#### 5.3、Kubernetes 集成

对于 Kubernetes 集成实际上有两种方案，一种是对接 Kubernetes 的 api，纯代码实现；另一种取巧的方案是调用 kubectl 工具，用 kubectl 工具来实现滚动升级；这里采用后一种取巧的方式，将 kubectl 二进制文件封装到镜像中，然后在 deploy 阶段使用这个镜像直接部署就可以


![kubectl](https://mritd.b0.upaiyun.com/markdown/bu17r.png)


其中 `mritd/docker-kubectl:v1.7.4` 这个镜像的 Dockerfile 如下

``` sh
FROM docker:dind 

LABEL maintainer="mritd <mritd1234@gmail.com>"

ARG TZ="Asia/Shanghai"

ENV TZ ${TZ}

ENV KUBE_VERSION v1.8.0

RUN apk upgrade --update \
    && apk add bash tzdata wget ca-certificates \
    && wget https://storage.googleapis.com/kubernetes-release/release/${KUBE_VERSION}/bin/linux/amd64/kubectl -O /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo ${TZ} > /etc/timezone \
    && rm -rf /var/cache/apk/*

CMD ["/bin/bash"]
```

这里面的 `${KUBE_CONFIG}` 是一个自定义的环境变量，对于测试环境我将配置文件直接挂载入了容器中，然后 `${KUBE_CONFIG}` 只是指定了一个配置文件位置，实际生产环境中可以选择将配置文件变成自定义环境变量使用


#### 5.4、GitLab CI 总结

关于 GitLab CI 上面已经讲了很多，但是并不全面，也不算太细致；因为这东西说起来实际太多了，现在目测已经 1W 多字了；以下总结一下 GitLab CI 的总体思想，当思路清晰了以后，我想后面的只是查查文档自己试一试就行了

**CS 架构**

GitLab 作为 Server 端，控制 Runner 端执行一系列的 CI 任务；代码 clone 等无需关心，GitLab 会自动处理好一切；Runner 每次都会启动新的容器执行 CI 任务

**容器即环境**

在 Runner 使用 Docker build 的前提下；**所有依赖切换、环境切换应当由切换不同镜像实现，即 build 那就使用 build 的镜像，deploy 就用带有 deploy 功能的镜像；通过不同镜像容器实现完整的环境隔离**

**CI即脚本**

不同的 CI 任务实际上就是在使用不同镜像的容器中执行 SHELL 命令，自动化 CI 就是执行预先写好的一些小脚本

**敏感信息走环境变量**

一切重要的敏感信息，如账户密码等，不要写到 CI 配置中，直接放到 GitLab 的环境变量中；GitLab 会保证将其推送到远端 Runner 的 SHELL 变量中



转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
