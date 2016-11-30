---
layout: post
title: WebLogic request.getContextPath() 为 null 问题
categories: [WebLogic]
description: WebLogic request.getContextPath() 为 null 问题
keywords: WebLogic,getContextPath
---

当使用 Weblogic 作为中间件，并且 Web 项目部署方式为 war 包部署时，jsp 页面`request.getContextPath()` 将返回 null，此时加入以下代码设置 `webRoot` 即可：

``` java
String webRoot = request.getSession().getServletContext().getRealPath("/");
if(webRoot == null){
    webRoot = this.getClass().getClassLoader().getResource("/").getPath();
    webRoot = webRoot.substring(0,webRoot.indexOf("WEB-INF"));
}
```
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
