---
layout: post
title: 浅谈 java中的 equals 和 hashcode
categories: [J2SE]
description: 浅谈 java中的 equals 和 hashcode
keywords: equals,hashcode
---

![hexo_java_equals_hashcode.jpg](https://mritd.b0.upaiyun.com/markdown/hexo_java_equals_hashcode.jpg)

## equals 方法
> equals 方法来源于 Object 超类；该方法用于检测一个对象与另一个对象是否相等。

### Object 中的 equals

> 在 java 源码中，Object 的 equals 实现如下

``` java
public boolean equals(Object obj) {
    return (this == obj);
}
```

<!--more-->

> 由此可见，Object 中 equals 默认比较的是两个对象的 内存地址(==)，即 **默认比较两个对象的引用，引用相同返回true，反之返回false。**这看起来似乎合情合理，但实际开发中，这种比较方式则不适用；比如我们要比较两个 pserson 对象是否相等，**从业务角度来说，只要这两个人 名字、年龄、身份证号相同，我们就可以认为两个对象相等。但由于是两个 pserson对象，所以所以引用肯定不同，这样调用默认的 equals 方法就会返回 false，显然是不合理的。**

### 重写 equals
> 从上面的例子可以看出，Object 中的 equals 并不适用与实际业务场景，此时我们应该 对 equals进行重写；但是 重写 equals 必须满足以下规则(特性)：

- 自反性
> 对于对象 x ，`x.equals(x)` 应当始终返回 true。

- 对称性
> 对于对象 x、y，如果 `x.equals(y)` 返回 true，那么 `y.equals(x)` 也必须返回 true。

- 传递性
> 对于对象 x、y、z，如果 `x.equals(y)` 返回 true，`y.equals(z)` 返回 true；那么 `x.equals(z)` 也必须返回 true。

- 一致性
> 对于对象 x、y，如果 `x.equals(y)` 返回 true，那么反复调用的结果应当一直为 true。

- 空值不行等性
> 对于任意非空对象 x，`x.equals(null)` 应当永远返回 false。

---

**然而，对于以上5种特性，在某些特殊情况下需要严格考虑。**

- 对象属性的冲突

假设我们将对象内的属性看作是对象内容，在实际业务场景，可能一个 汽车 Car 对象 和一个人 pserson 对象具有相同的名字，比如 `特斯拉`；此时如果我们重写 equals 时仅仅比较对象内容的话，很可能误判为 **一辆汽车和一个人相等**；是的，这很滑稽。

### getClass 的使用

在上面列举的情况来看，我们似乎再重写 equals 时还需要考虑对象的类型；在 java 里，对象类型我们 采用 Class 描述。那么此时 我们在重写的 equals 方法里应当 增加 `car.getClass()==pserson.getClass()` 的检测，这样能有效避免上述情况的发生；伪代码如下

``` java
public boolean equals(Object obj){
    // 进行完全匹配检测(引用)
    if(this==obj) return true;
    // 进行空值检测
    if(obj==null) return false;
    // 进行类型匹配检测
    if(this.getClass()!=obj.getClass()) return false;
    // 进行属性相等检测，省略...
}
```

### instanceof 的使用

然而，即使我们考虑了属性相等的情况，我们还是忽略了很多其他的业务场合。比如 一个学生 Student 对象和一个人 pserson 对象；当使用上面的检测方法时，很明显 pserson 对象和 Student 对象的 Class 不一致，直接返回了 false；而实际业务场景是 一个 Student 对象也是一个人 pserson；**Student 对象可能继承于pserson对象。**而此时我们应当使用 instanceof 进行检测，伪代码如下：

``` java
public boolean equals(Object obj){
    // 进行完全匹配检测(引用)
    if(!(this instaceof obj)) return false;
    // 进行空值检测
    if(obj==null) return false;
    // 进行类型匹配检测
    if(this.getClass()!=obj.getClass()) return false;
    // 进行属性相等检测，省略...
}
```

### getClass 与 instaceof 的取舍

或许从上两个例子中我们感觉使用 instaceof 更 "靠谱一些"；但其实我们注意到，**采用 instaceof 检测实际上违反了 `对称性` 原则；** 因为 `pserson instaceof Student` 返回 false，反之返回 true。

所以对于 `instanceof` 有时候并不那么完美；就连 JDK的开发者也遇到了这个问题；在 `Timestamp` 类中，由于继承自 `java.util.Date`；而不幸的是 Date 类的 equals 采用的是 instanceof，这就导致对称性出了问题。从上可知，我们根据实际业务进行取舍，取舍原则如下：

- 如果子类拥有自己的相等性概念，则对称性强制要求采用 getClass 方式检测。
- 如果由超类决定相等性概念，那么就可以采用 instanceof 检测，保证我们可以在子类对象间进行相等性判断。

### 重写 equals 的建议

- 首先检测 this 与 otherObject 是否引用同一对象

``` java
if(this==otherObject) return true;
```

- 然后检测 otherObject是否为 null，如果为 null 返回 false，这是必须的

``` java
if(otherObject == null) return false;
```

- 其次比较 this 与 otherObject 是否同属于一个类；如果 equals 语义在子类中有所改变，则 使用 getClass 检测

``` java
if(this.getClass()!=otherObject.getClass()) return false;
```

- 最后将 otherObject强制转换为 当前类型，并进行属性值检测；注意：**如果在子类中重写的equals，则需要在重写时首先进行 `super.equals(other)` 判断**

## hashcode 方法

> 写这篇博客之前，也看过很多博客，大部分大家写的都是这样的一句话：**重写 equals 必须重写 hashcode，两个对象 equals 返回 true 则 hashcode 必须保证相同。**但是，接下来就没有然后了；搞的我刚学 java 时候也挺晕的，就像是 "知其然而不知所以然"。

> 总结一下一般会有这几个问题：

- hashcode 方法是干啥的？
- hashcode(哈希值) 是个什么玩意？
- hashcode 有什么用？
- 我为啥要重写 hashcode？
- 我不重写它有啥后果？

### hashcode 方法是干啥的？

> 官方的解释是这样的：**hashcode 方法用于返回一个对象的 哈希值。**说白了就是 hashcode 方法能返回一个 哈希值，这玩意是个整数。

### hashcode(哈希值) 是个什么玩意？

> 由上面可知，这个 哈希值就是一个整数，可能是正数也可能是负数。

### hashcode 有什么用？

> hashcode(哈希值) 的作用就是用于在使用 Hash算法实现的集合中确定元素位置。

拿我们最常见的 HashMap 来说，我们都知道 HashMap 里通过 key 取 value 时的速度 是 O(1) 级别的；

什么是 O(1)级别？

O(1)级别说白了就是 **在任意数据大小的容器中，取出一个元素所使用的时间与元素个数无关；通俗的说法就是 不论你这个 HashMap 里有100个元素还是有9999999个元素，我通过 key 取出一个元素所使用的时间是一样的。**

为何是 O(1) 级别？为何这么吊？

这个问题就要谈一下 HashMap 等 hash 容器的存储方式了；这些容器在存储元素是是这样的：首先获取你要存储元素的 hashcode(一个整数)，然后再定义一个固定整数(标准叫桶数)，最后用 hashcode 对 另一个整数(桶数) 取余；取余的结果即为元素要存储的下标(可能存放到数组里)。当然这里是简单的取余，可能更复杂。

当我们要从一个 HashMap 中取出一个 value 时，实际上他就是通过这套算法，用 key 的 hashcode 计算出元素位置，直接取出来了；所以说 无论你这里面有多少元素，它取的时候始终是用着一个算法、一个流程，不会因为你数据多少而产生影响，这就是 O(1) 级别的存储。

**总结：由上面可知，这个 hashcode 的作用就是 通过算法来确立元素存放的位置，以便于放入元素或者获取元素。**

### 我为啥要重写 hashcode && 不重写有啥后果

> 回顾一下上面：hashcode 是个整数，hashcode 方法的作用就是计算并返回这个整数；这个整数用于存放 Hash 算法实现的容器时 确定元素位置。

接下来考虑一个业务场景：有两个对象 pserson1 和 pserson2 ，pserson1 和 pserson2 都只有两个属性，分别是名字(name)和年龄(age)。现在 pserson1 和 pserson2 的名字(name)、年龄(age) 都相同；那么我们是否可以根据业务场景来说 **pserson1 和 pserson2 是同一个人**？

如果说 "是" 的话，我们刚刚所认为的 "从业务角度理解 pserson1 和 pserson2 是一个人" 是不是就相当于 重写了 Pserson 的 equals 方法呢？就像下面这样：

``` java
public class Pserson {
	private String name;
	private int age;

	// 重写 equals
	@Override
	public boolean equals(Object obj) {
		if (this == obj)
			return true;
		if (obj == null)
			return false;
		if (getClass() != obj.getClass())
			return false;

		// 主要在这，我们根据业务逻辑，即 姓名和年龄 确立相等关系
		pserson other = (pserson) obj;
		if (age != other.age)
			return false;
		if (name == null) {
			if (other.name != null)
				return false;
		} else if (!name.equals(other.name))
			return false;
		return true;
	}
}
```

我们注意到，我们根据业务逻辑重写 equals 后，造成的结果就是，两个 属性相同的 Pserson 对象 我们就认为是相同的，即 equals 返回了 true；
**但我们没有重写 hashcode，Object 中的 hashcode 是 native(本地的)，也就是很可能不同对象返回不同的 hashcode，即使属性相同也没用。**

---

到这里我们再总结一下：

- **hashcode 方法返回对象的 哈希值；**
- **我们通过 哈希值 的运算(与指定数取余等)来确立元素在 hash 算法实现的容器中的位置；**
- **Object 中的 hashcode 方法 对于业务逻辑上相等的两个对象(属性相同，不同引用) 返回的 hashcode 是不同的。**

---

**墨迹了那么多最终问题来了：假设我们只重写了 pserson 的 equals 方法，使之 "属性相同即为相等"，当我们把两个 "相等的(属性相同的)" Pserson 对象 放入 HashSet 中会怎样？**

友情提示：HashSet中默认是不许放重复元素的，放重复的是会被过滤掉的，如下代码所示：

``` java
public class Test1 {
	public static void main(String[] args) {
		Pserson pserson1 = new Pserson();
		pserson1.setName("张三");
		pserson1.setAge(10);

		Pserson pserson2 = new Pserson();
		pserson2.setName("张三");
		pserson2.setAge(10);

		HashSet<Pserson> hashSet = new HashSet<Pserson>();

		hashSet.add(pserson1);
		hashSet.add(pserson2);

		System.out.println(hashSet.size());
	}
}
```

> 结论&&后果：当我们仅重写了 equals 保证了 "名字和年龄一样的就是一个人" 这条业务以后；把两个 pserson 对象放入 HashSet 容器里时，由于 HashSet 是通过 hashcode 来区分两个 对象存放位置，而我们又 没有根据业务逻辑重写 hashcode 方法；导致了两个 在业务上相同的对象 放到了 HashSet里，HashSet 会认为他是两个不同的对象，故最后不会去重，hashset.size()打印出来是2。

## 最终结论

> 对于重写 euqals ，要很据实际业务逻辑来，并满足上述的设计要求；一旦重写了 equals 那就必须重写 hashcode，除非你保证你的对象不会被放到 Hash 实现的容器里；不重写的话就会导致 Hash 容器认为两个属性相同的对象是2个，而不是业务上的1个。
转载请注明出处，本文采用 [CC4.0](http://creativecommons.org/licenses/by-nc-nd/4.0/) 协议授权
