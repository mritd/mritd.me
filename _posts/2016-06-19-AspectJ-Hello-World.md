---
layout: post
title: AspectJ Hello World
categories: [AspectJ]
description: AspectJ Hello World
keywords: Java,AspectJ
---

## 一、简介

AspectJ 是一个强大的面向切面编程框架，Spring 等 AOP 全部兼容该框架；它扩展了Java语言。AspectJ 定义了 AOP 语法所以它有一个专门的编译器用来生成遵守Java字节编码规范的Class文件。

## 二、环境准备

- IntelliJ IDEA 2016
- Maven 3.3.9
- AspectJ 1.8.9
- aspectjtools 1.8.9

<!--more-->

## 三、Hello World

### 1、首先新建一个 Java 项目 :

![hex_aspect_create_project](https://mritd.b0.upaiyun.com/markdown/hex_aspect_create_project.png)

### 2、将其转化为 Maven 项目

![hexo_aspect_add_maven](https://mritd.b0.upaiyun.com/markdown/hexo_aspect_add_maven.png)

### 3、加入相关依赖

![hexo_aspect_maven_dependencies](https://mritd.b0.upaiyun.com/markdown/hexo_aspect_maven_dependencies.png)

**POM 如下 :**

``` xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>

    <groupId>me.mritd</groupId>
    <artifactId>Test1</artifactId>
    <version>1.0-SNAPSHOT</version>
    <packaging>jar</packaging>


    <dependencies>
        <!-- https://mvnrepository.com/artifact/org.aspectj/aspectjrt -->
        <dependency>
            <groupId>org.aspectj</groupId>
            <artifactId>aspectjrt</artifactId>
            <version>1.8.9</version>
        </dependency>
        <!-- https://mvnrepository.com/artifact/org.aspectj/aspectjtools -->
        <dependency>
            <groupId>org.aspectj</groupId>
            <artifactId>aspectjtools</artifactId>
            <version>1.8.9</version>
        </dependency>
    </dependencies>
    <build>
        <plugins>
            <!-- Maven 编译插件 -->
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <version>3.5.1</version>
                <configuration>
                    <source>1.8</source>
                    <target>1.8</target>
                    <encoding>UTF-8</encoding>
                </configuration>
            </plugin>
            <!-- AspectJ 编译插件 -->
            <plugin>
                <groupId>org.codehaus.mojo</groupId>
                <artifactId>aspectj-maven-plugin</artifactId>
                <version>1.8</version>
                <executions>
                    <execution>
                        <goals>
                            <goal>compile</goal>       <!-- use this goal to weave all your main classes -->
                            <goal>test-compile</goal>  <!-- use this goal to weave all your test classes -->
                        </goals>
                    </execution>
                </executions>
            </plugin>
        </plugins>
    </build>
</project>
```

### 4、创建一个普通类

``` java
package me.mritd.test;

/**
 * Created by mritd on 16/6/19.
 */
public class Test1 {

    public static void main(String[] args) {
        System.out.println("Test AspectJ...");
    }

}
```

### 5、创建一个切面

**创建时选择 AspectJ 程序 :**

![hexo_aspect_newaspect](https://mritd.b0.upaiyun.com/markdown/hexo_aspect_newaspect.png)

``` java
package me.mritd.testaspect;

/**
 * Created by mritd on 16/6/19.
 */
public aspect TestAspect {

    // 定义 pointcut
    pointcut TestAspectPointCutBefore() : execution(* me.mritd.test.Test1.main(..));
    pointcut TestAspectPointCutAfter() : execution(* me.mritd.test.Test1.main(..));


    // 定义执行动作
    before() : TestAspectPointCutBefore(){
        System.out.println("执行前切入...");
    }

    after() : TestAspectPointCutAfter(){
        System.out.println("执行前切入...");
    }
}
```

### 6、调整编译

由于 AspectJ 需要单独的编译器编译，所以需要设置 Ajc 编译器，Maven 中已经加入了相关编译插件，直接 `compile` 也可以。

#### 6.1、设置项目依赖

![hexo_aspect_add_ajc](https://mritd.b0.upaiyun.com/markdown/hexo_aspect_add_ajc.png)

#### 6.2、设置编译器

![hexo_aspect_set_ajc](https://mritd.b0.upaiyun.com/markdown/hexo_aspect_set_ajc.png)

### 7、运行测试

![hexo_aspect_runtest_helloworld](https://mritd.b0.upaiyun.com/markdown/hexo_aspect_runtest_helloworld.png)
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
