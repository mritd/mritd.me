---
layout: post
categories: Kubernetes Docker Ceph
title: Kubernetes 使用 Ceph 存储
date: 2017-06-03 12:38:55 +0800
description: Kubernetes 使用 Ceph 存储
keywords: Kubernetes Docker Ceph 
---

> 本文主要记录一下 Kubernetes 使用 Ceph 存储的相关配置过程，Kubernetes 集群环境采用的 kargo 部署方式，并且所有组件以容器化运行


### 一、基础环境准备

Kubernetes 集群总共有 5 台，部署方式为 kargo 容器化部署，**采用 kargo 部署时确保配置中开启内核模块加载( `kubelet_load_modules: true` )**；Kubernetes 版本为 1.6.4，Ceph 采用最新的稳定版 Jewel

|节点|IP|部署|
|----|--|----|
|docker1|192.168.1.11|master、monitor、osd|
|docker2|192.168.1.12|master、monitor、osd|
|docker3|192.168.1.13|node、monitor、osd|
|docker4|192.168.1.14|node、osd|
|docker5|192.168.1.15|node、osd|

### 二、部署 Ceph 集群

具体安装请参考 [Ceph 笔记(一)](https://mritd.me/2017/05/27/ceph-note-1/)、[Ceph 笔记(二)](https://mritd.me/2017/05/30/ceph-note-2/)，以下直接上命令

#### 2.1、部署集群

``` sh
# 创建集群配置目录
mkdir ceph-cluster && cd ceph-cluster
# 创建 monitor-node
ceph-deploy new docker1 docker2 docker3
# 追加 OSD 副本数量
echo "osd pool default size = 5" >> ceph.conf
# 安装 ceph
ceph-deploy install docker1 docker2 docker3 docker4 docker5
# init monitor node
ceph-deploy mon create-initial
# 初始化 ods
ceph-deploy osd prepare docker1:/dev/sda docker2:/dev/sda docker3:/dev/sda docker4:/dev/sda docker5:/dev/sda
# 激活 osd
ceph-deploy osd activate docker1:/dev/sda1:/dev/sda2 docker2:/dev/sda1:/dev/sda2 docker3:/dev/sda1:/dev/sda2 docker4:/dev/sda1:/dev/sda2 docker5:/dev/sda1:/dev/sda2
# 部署 ceph cli 工具和秘钥文件
ceph-deploy admin docker1 docker2 docker3 docker4 docker5
# 确保秘钥有读取权限
chmod +r /etc/ceph/ceph.client.admin.keyring
# 检测集群状态
ceph health
```

#### 2.2、创建块设备

``` sh
# 创建存储池
rados mkpool data
# 创建 image
rbd create data --size 10240 -p data
# 关闭不支持特性
rbd feature disable data exclusive-lock, object-map, fast-diff, deep-flatten -p data
# 映射(每个节点都要映射)
rbd map data --name client.admin -p data
# 格式化块设备(单节点即可)
mkfs.xfs /dev/rbd0
```

### 三、kubernetes 使用 Ceph

#### 3.1、PV & PVC 方式

传统的使用分布式存储的方案一般为 `PV & PVC` 方式，也就是说管理员预先创建好相关 PV 和 PVC，然后对应的 deployment 或者 replication 挂载 PVC 来使用

**创建 Secret**

``` sh
# 获取管理 key 并进行 base64 编码
ceph auth get-key client.admin | base64

# 创建一个 secret 配置(key 为上条命令生成的)
cat << EOF >> ceph-secret.yml
apiVersion: v1
kind: Secret
metadata:
  name: ceph-secret
data:
  key: QVFDaWtERlpzODcwQWhBQTdxMWRGODBWOFZxMWNGNnZtNmJHVGc9PQo=
EOF
kubectl create -f ceph-secret.yml
```

**创建 PV**

``` sh
# monitor 需要多个，pool 和 image 填写上面创建的
cat << EOF >> test.pv.yml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: test-pv
spec:
  capacity:
    storage: 2Gi
  accessModes:
    - ReadWriteMany
  rbd:
    monitors:
      - 192.168.1.11:6789
      - 192.168.1.12:6789
      - 192.168.1.13:6789
    pool: data
    image: data
    user: admin
    secretRef:
      name: ceph-secret
    fsType: xfs
    readOnly: false
  persistentVolumeReclaimPolicy: Recycle
EOF

kubectl create -f test.pv.yml
```

**创建 PVC**

``` sh
cat << EOF >> test.pvc.yml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: test-pvc
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 2Gi
EOF

kubectl create -f test.pvc.yml
```

**创建 Deployment并挂载**

``` sh
cat << EOF >> test.deploy.yml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: demo
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - name: demo
        image: mritd/demo
        ports:
        - containerPort: 80
        volumeMounts:
          - mountPath: "/data"
            name: data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: test-pvc
EOF

kubectl create -f test.deploy.yml
```

#### 3.2、StoragaClass 方式

在 1.4 以后，kubernetes 提供了一种更加方便的动态创建 PV 的方式；也就是说使用 StoragaClass 时无需预先创建固定大小的 PV，等待使用者创建 PVC 来使用；而是直接创建 PVC 即可分配使用


**创建系统级 Secret**

**注意: 由于 StorageClass 要求 Ceph 的 Secret type 必须为 `kubernetes.io/rbd`，所以上一步创建的 `ceph-secret` 需要先被删除，然后使用如下命令重新创建；此时的 key 并没有经过 base64**

``` sh
# 这个 secret type 必须为 kubernetes.io/rbd，否则会造成 PVC 无法使用
kubectl create secret generic ceph-secret --type="kubernetes.io/rbd" --from-literal=key='AQCikDFZs870AhAA7q1dF80V8Vq1cF6vm6bGTg==' --namespace=kube-system
kubectl create secret generic ceph-secret --type="kubernetes.io/rbd" --from-literal=key='AQCikDFZs870AhAA7q1dF80V8Vq1cF6vm6bGTg==' --namespace=default
```

**创建 StorageClass**

``` sh
cat << EOF >> test.storageclass.yml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: test-storageclass
provisioner: kubernetes.io/rbd
parameters:
  monitors: 192.168.1.11:6789,192.168.1.12:6789,192.168.1.13:6789
  # Ceph 客户端用户 ID(非 k8s 的)
  adminId: admin
  adminSecretName: ceph-secret
  adminSecretNamespace: kube-system
  pool: data
  userId: admin
  userSecretName: ceph-secret
EOF

kubectl create -f test.storageclass.yml
```

**关于上面的 adminId 等字段具体含义请参考这里 [Ceph RBD](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#ceph-rbd)**

**创建 PVC**

``` sh
cat << EOF >> test.sc.pvc.yml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: test-sc-pvc
  annotations: 
    volume.beta.kubernetes.io/storage-class: test-storageclass
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 2Gi
EOF

kubectl create -f test.sc.pvc.yml
```

**创建 Deployment**

``` sh
cat << EOF >> test.sc.deploy.yml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  name: demo-sc
spec:
  replicas: 3
  template:
    metadata:
      labels:
        app: demo-sc
    spec:
      containers:
      - name: demo-sc
        image: mritd/demo
        ports:
        - containerPort: 80
        volumeMounts:
          - mountPath: "/data"
            name: data
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: test-sc-pvc
EOF

kubectl create -f test.sc.deploy.yml
```

到此完成，检测是否成功最简单的方式就是看相关 pod 是否正常运行

转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
