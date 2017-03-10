---
layout: post
categories: Kubernetes Docker
title: kargo 集群扩展及细粒度配置
date: 2017-03-10 23:57:12 +0800
description: kargo 集群扩展及细粒度配置
keywords: kargo Kubernetes Docker HA
---

> 上一篇写了一下一下使用 kargo 快速部署 Kubernetes 高可用集群，但是一些细节部分不算完善，这里准备补一下，详细说明一下一些问题；比如后期如何扩展、一些配置如何自定义等

### 一、集群扩展

如果已经有了一个 kargo 搭建的集群，那么扩展其极其容易；只需要修改集群 `inventory` 配置，加入新节点重新运行命令价格参数即可，如下新增一个 node6 节点

``` sh
vim inventory/inventory.cfg

# 在 Kubernetes node 组中加入新的 node6 节点
[all]
node1    ansible_host=192.168.1.11 ip=192.168.1.11
node2    ansible_host=192.168.1.12 ip=192.168.1.12
node3    ansible_host=192.168.1.13 ip=192.168.1.13
node4    ansible_host=192.168.1.14 ip=192.168.1.14
node5    ansible_host=192.168.1.15 ip=192.168.1.15
node6    ansible_host=192.168.1.16 ip=192.168.1.16

[kube-master]
node1
node2
node3
node5

[kube-node]
node1
node2
node3
node4
node5
node6

[etcd]
node1
node2
node3

[k8s-cluster:children]
kube-node
kube-master

[calico-rr]
```

**然后重新运行集群命令，注意增加 `--limit` 参数**

``` sh
ansible-playbook -i inventory/inventory.cfg cluster.yml -b -v --private-key=~/.ssh/id_rsa --limit node6
```

**稍等片刻 node6 节点便加入现有集群，如果有多个节点加入，只需要以逗号分隔即可，如 `--limit node5,node6`；在此过程中只会操作新增的 node 节点，不会影响现有集群，可以实现动态集群扩容(master 也可以扩展)**

### 二、kargo 细粒度控制

对于 kargo 高度自动化的工具，可能有些东西我们已经预先处理好了，**比如事先已经安装了 docker，而且 docker 配置了一些参数(日志驱动、存储驱动等)；这时候我们可能并不希望 kargo 再去处理，因为 kargo 会进行覆盖，可能导致一些问题**

**kargo 是基于 ansible 的，实际上也就是 ansible，只不过它帮我们写好了配置文件而已；按照 ansible 的规则，Play Book 首先执行 roles 目录下的 roles，在这些 roles 中定义了如何配置集群、如何初始化网络、怎么配置 docker 等等，所以只要我们去更改这些 roles 规则就可以实现一些功能的定制，roles 目录位置如下**

![roles](https://mritd.b0.upaiyun.com/markdown/jmy7o.jpg)

如果需要更改某些默认配置，那么只需要更改对应目录下的 role 即可，**每个 role 子目录都是一个组件的配置过程(动作)，动作实际上就是不同的 task，所有的 task 定义在 `tasks/main.yml` 中，如果我们注释(删掉)了相关 task，那么也就关闭了 kargo 对应的处理；如下禁用了 kargo 安装 docker，但是允许 kargo 覆盖 docker service 文件**

![docker task](https://mritd.b0.upaiyun.com/markdown/vv2px.jpg)

**禁用掉 docker 仓库以及 docker 的安装动作**

``` sh
vim roles/docker/tasks/main.yml

---
- name: gather os specific variables
  include_vars: "{ { item } }"
  with_first_found:
    - files:
      - "{ { ansible_distribution|lower } }-{ { ansible_distribution_version|lower|replace('/', '_') } }.yml"
      - "{ { ansible_distribution|lower } }-{ { ansible_distribution_release } }.yml"
      - "{ { ansible_distribution|lower } }-{ { ansible_distribution_major_version|lower|replace('/', '_') } }.yml"
      - "{ { ansible_distribution|lower } }.yml"
      - "{ { ansible_os_family|lower } }.yml"
      - defaults.yml
      paths:
      - ../vars
      skip: true
  tags: facts

- include: set_facts_dns.yml
  when: dns_mode != 'none' and resolvconf_mode == 'docker_dns'
  tags: facts

- name: check for minimum kernel version
  fail:
    msg: >
          docker requires a minimum kernel version of
          { { docker_kernel_min_version } } on
          { { ansible_distribution } }-{ { ansible_distribution_version } }
  when: (not ansible_os_family in ["CoreOS", "Container Linux by CoreOS"]) and (ansible_kernel|version_compare(docker_kernel_min_version, "<"))
  tags: facts

# 禁用 docker 仓库处理，因为默认 kargo 会写入国外 docker 源，我已经自己设置了清华大学的镜像源

#- name: ensure docker repository public key is installed
#  action: "{ { docker_repo_key_info.pkg_key } }"
#  args:
#    id: "{ {item} }"
#    keyserver: "{ {docker_repo_key_info.keyserver} }"
#    state: present
#  register: keyserver_task_result
#  until: keyserver_task_result|success
#  retries: 4
#  delay: "{ { retry_stagger | random + 3 } }"
#  with_items: "{ { docker_repo_key_info.repo_keys } }"
#  when: not ansible_os_family in ["CoreOS", "Container Linux by CoreOS"]
#
#- name: ensure docker repository is enabled
#  action: "{ { docker_repo_info.pkg_repo } }"
#  args:
#    repo: "{ {item} }"
#    state: present
#  with_items: "{ { docker_repo_info.repos } }"
#  when: (not ansible_os_family in ["CoreOS", "Container Linux by CoreOS"]) and (docker_repo_info.repos|length > 0)
#
#- name: Configure docker repository on RedHat/CentOS
#  template:
#    src: "rh_docker.repo.j2"
#    dest: "/etc/yum.repos.d/docker.repo"
#  when: ansible_distribution in ["CentOS","RedHat"]
#

# 这步 kargo 会重新安装 docker，已经装好了，所以不需要再覆盖安装

#- name: ensure docker packages are installed
#  action: "{ { docker_package_info.pkg_mgr } }"
#  args:
#    pkg: "{ {item.name} }"
#    force: "{ {item.force|default(omit)} }"
#    state: present
#  register: docker_task_result
#  until: docker_task_result|success
#  retries: 4
#  delay: "{ { retry_stagger | random + 3 } }"
#  with_items: "{ { docker_package_info.pkgs } }"
#  notify: restart docker
#  when: (not ansible_os_family in ["CoreOS", "Container Linux by CoreOS"]) and (docker_package_info.pkgs|length > 0)
#

# 对于 docker 版本的检查个人感觉还是有点必要的

- name: check minimum docker version for docker_dns mode. You need at least docker version >= 1.12 for resolvconf_mode=docker_dns
  command: "docker version -f '{ { '{ {' } }.Client.Version{ { '} }' } }'"
  register: docker_version
  failed_when: docker_version.stdout|version_compare('1.12', '<')
  changed_when: false
  when: dns_mode != 'none' and resolvconf_mode == 'docker_dns'

# kargo 对 docker service 的配置会在此写入，我感觉还不错，所以留着了；但是注意的是它会把原来的覆盖掉

- name: Set docker systemd config
  include: systemd.yml

- name: ensure docker service is started and enabled
  service:
    name: "{ { item } }"
    enabled: yes
    state: started
  with_items:
    - docker
```

**kargo 在进行各种任务(task)时可能会释放一些配置文件，比如 docker service 配置文件、kubernetes 配置文件等；这些文件一般位于 `roles/组件/templates` 目录，比如 docker 的 service 配置位于如下位置；我们可以更改，甚至直接换一个，把里面写死变成我们自己的**

![docker service template](https://mritd.b0.upaiyun.com/markdown/f1f9g.jpg)

### 三、其他相关

**以上只是介绍了自定义配置的大体思路，更深度的处理需要去玩转  ansible，如果玩明白了 ansible 那么基本上这个 kargo 就可以随便搞了；要写的差不多也就这么多了，感觉这东西比 kubeadm 要好的多，所有操作都是可视化的，没有莫名其妙的问题；其他的可以参考 [ansible 中文文档](http://ansible-tran.readthedocs.io/en/latest/)、[kargo 官方文档](https://github.com/kubernetes-incubator/kargo/blob/master/README.md)**



转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
