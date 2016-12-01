---
layout: post
title: List 的 UnsupportedOperationException 异常
categories: [J2SE]
description: List 的 UnsupportedOperationException 异常
keywords: List,UnsupportedOperationException
---

## 一、前言
今天偶尔测试 `List.remove()` 和 `List.add()` 方法很奇怪的出现了 `UnsupportedOperationException` 异常，但是 "某些情况下" 调用则不会出现这个异常，由于只考虑了局部代码，所以让我很困惑，以下分析一下 "搞笑的 UnsupportedOperationException" 异常。

<!--more-->

## 二、测试代码

**首先一个正常的**

``` java
// 创建一个 ArrayList
List<String> list = new ArrayList<String>();

// add 操作
list.add("a");
list.add("b");
list.add("c");

// remove 操作
list.remove(2);

System.out.println(list);
```

**接着一个报错的**

``` java
// 使用数组来创建 "ArrayList"
String s[] = {"a","b","c"};

List<String> list = Arrays.asList(s);

// UnsupportedOperationException
list.add("d");

// UnsupportedOperationException
list.remove(3);
```

## 三、原因分析

首先两个代码唯一差别就是第一个直接 `new ArrayList()`，第二个通过 `Arrays.asList()` 创建；

### 1、Arrays.asList() 方法

查看源码如下：

``` java
@SafeVarargs
@SuppressWarnings("varargs")
public static <T> List<T> asList(T... a) {
    return new ArrayList<>(a);
}
```

乍眼一看，也是返回 `ArrayList`，这就搞笑了，同样是 `ArrayList` 一个报错一个不报错......

当点进去这个 `ArrayList` 构造方法后，**实质上 `Arrays.aslist()` 方法 new 出的 `ArrayList` 并非 `java.util.ArrayList`，其实质是 `Arrays` 的内部类，**如下：

``` java
/**
 * @serial include
 */
private static class ArrayList<E> extends AbstractList<E>
    implements RandomAccess, java.io.Serializable
{
    private static final long serialVersionUID = -2764017481108945198L;
    private final E[] a;

    ArrayList(E[] array) {
        a = Objects.requireNonNull(array);
    }

    @Override
    public int size() {
        return a.length;
    }

    @Override
    public Object[] toArray() {
        return a.clone();
    }

    @Override
    @SuppressWarnings("unchecked")
    public <T> T[] toArray(T[] a) {
        int size = size();
        if (a.length < size)
            return Arrays.copyOf(this.a, size,
                                 (Class<? extends T[]>) a.getClass());
        System.arraycopy(this.a, 0, a, 0, size);
        if (a.length > size)
            a[size] = null;
        return a;
    }

    @Override
    public E get(int index) {
        return a[index];
    }

    @Override
    public E set(int index, E element) {
        E oldValue = a[index];
        a[index] = element;
        return oldValue;
    }

    @Override
    public int indexOf(Object o) {
        E[] a = this.a;
        if (o == null) {
            for (int i = 0; i < a.length; i++)
                if (a[i] == null)
                    return i;
        } else {
            for (int i = 0; i < a.length; i++)
                if (o.equals(a[i]))
                    return i;
        }
        return -1;
    }

    @Override
    public boolean contains(Object o) {
        return indexOf(o) != -1;
    }

    @Override
    public Spliterator<E> spliterator() {
        return Spliterators.spliterator(a, Spliterator.ORDERED);
    }

    @Override
    public void forEach(Consumer<? super E> action) {
        Objects.requireNonNull(action);
        for (E e : a) {
            action.accept(e);
        }
    }

    @Override
    public void replaceAll(UnaryOperator<E> operator) {
        Objects.requireNonNull(operator);
        E[] a = this.a;
        for (int i = 0; i < a.length; i++) {
            a[i] = operator.apply(a[i]);
        }
    }

    @Override
    public void sort(Comparator<? super E> c) {
        Arrays.sort(a, c);
    }
}
```

### 2、AbstractList 抽象类

通过对比代码发现 `java.util.ArrayList` 和 `Arrays$ArrayList` 同样继承自 `java.util.AbstractList`；而 `add()` 和 `remove()` 方法同样在此抽象类中定义，以下为两个方法在抽象类中的默认实现：


**add() 方法**
``` java
public boolean add(E e) {
    add(size(), e);
    return true;
}

public void add(int index, E element) {
    throw new UnsupportedOperationException();
}
```

**remove() 方法**

``` java
public E remove(int index) {
    throw new UnsupportedOperationException();
}
```

### 3、结论

`Arrays.asList` 最终返回的 `ArrayList` 实质上是其内部类，`java.util.Arrays$ArrayList` 和 `java.util.ArrayList` 全部继承自 `java.util.AbstractList` 抽象类，而 `java.util.AbstractList` 中默认的 `add()` 和 `remove()` 方法默认将抛出 `UnsupportedOperationException` 异常，不巧的是 `java.util.Arrays$ArrayList` 并未重写这两个方法，导致调用后抛出此异常。
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
