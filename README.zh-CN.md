# Firmament（edit of coderbot's Steadfast）

[English](README.md) | 简体中文

面向 **Minecraft: Java 版**、为 **Iris + Sodium** 制作的光影包。它是 coderbot 的
[Steadfast](https://github.com/coderbot16/Steadfast) 的修改版，名字也由此而来：
Steadfast 的附加条款要求修改版的名称以 `(edit of coderbot's Steadfast)` 结尾。

## Steadfast 与它的下载地址

> Steadfast is free and open-source software developed by coderbot, and can be
> downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth),
> https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or
> https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and
> distribute it under the terms of the GNU General Public License, version 3.

（上面这段是 Steadfast 附加条款要求逐字给出的声明原文，故保留英文。）

**本包不是 Steadfast 的官方发行版，coderbot 不为它提供支持。**
关于本包的问题请不要提交到 Steadfast 的 issue 区。

## 这个修改版加了什么

* **材质（PBR）**：读取 labPBR 资源包的法线、高光、视差、次表面与自发光贴图，
  并据此做反射与自阴影。视差另有一个"平滑"开关；位移会被限制在片元自己所属的
  sprite 之内，而不是绕到贴图的另一侧去。
* **彩色阴影**：透过染色玻璃的阳照落到地面时带的是玻璃自己的颜色；地狱传送门
  则用它自己的辉光给周围的光上色。带上多少颜色是一个设置项，传送门辉光可以
  单独关掉。
* **体积光（水面上下都有）**：水下也会画光柱，与水面上的光柱共用同一根光轴，
  并在水面波纹把光聚起来的地方更亮。光柱强度是一个设置项，水下光柱在它之上
  另有一个倍率。
* **附魔光效强度**：附魔物品与盔甲上的闪光可以调得更亮。游戏是以"叠加自身颜色"
  的方式画这层的，所以它贡献的光按设置值的平方增长——出厂值 2.0 时是原来的四倍。
* **远景**：给阴影贴图够不到的远景补上屏幕空间阴影——Distant Horizons 与 Voxy
  的 LOD 地形本来一点阴影都没有。
* **不是平铺在地面的水**：瀑布侧面、沿坡流下的水现在也按水面绘制，
  表面样式、水色与反射都和静水一致，并按**该面自己的切线基**铺开，
  而不是按假定的世界轴。
* **反射**：每个材质的天空反射，加上可选的屏幕空间反射；反射由两趟模糊处理，
  会把"反射到的东西不一样"的相邻像素分开，而不是一概平均。金属反射强度、
  反射所需的光滑度、模糊宽度，以及一个"只显示反射"的调试视图都是设置项。
* **时间抗锯齿（TAA）**：默认开启，历史权重随运动变化——静止时压噪点，
  走动时不拖影。
* **云**：用立方体云格组成的云层替代原版的扁平方块云，云内有多次散射，
  云的相位、透射与层高衰减都是设置项。
* **末地**：支持末地维度，而不是退回主世界的天空。
* 此外还有动态模糊、**默认开启**的屏幕暗角，以及 Steadfast 自己的发行说明里
  写到的其余内容。

## 运行要求

* **Iris + Sodium**，Minecraft 1.21.x。**不支持 OptiFine**。
* **Voxy** 与 **Distant Horizons** 都支持；上面说的远景阴影需要装了其中之一才有意义。
* 材质相关功能需要 **labPBR 资源包**。没有资源包时本包照常工作，
  材质会解码成平坦表面。

## 安装

1. 把 `Firmament-v0.5-edit-of-coderbot-Steadfast.zip` 放进 `.minecraft/shaderpacks/`，
   **不要解压**。
2. 在 **视频设置 → 光影** 里选中它。
3. 光影选项里 `材质（PBR）→ 材质格式` 跟着资源包走：用资源包就保持 `LabPBR`，
   不用就设成 `关闭`。

## 已知限制

* **远景阴影只到深度缓冲能到的地方**：背对镜头、屏幕外、被挡住的地形不投影，
  草与栅栏这类薄物体也容易漏。
* **TAA 没有运动矢量**——自身会移动的东西靠"丢弃与当前帧不符的历史"处理，
  而不是靠跟踪。
* **Voxy 的顶点由模组发射**，不经过本包的顶点着色器，因此不参与 TAA 的亚像素抖动。
* **反射在画不对的地方一律不画。** 隔着水、冰或玻璃看到的物体没有环境反射，
  正对镜头的面也没有——因为指向观察者的反射线前方没有东西可以追踪。这两条都是
  有意的：位置画错的反射比没有反射更难看。
* **附魔那项只能把闪光调亮，不能改颜色。** Minecraft 在本包看到这一层之前就已经
  把附魔的颜色乘进去了，再乘一次颜色只可能把光拿走。
* 其余关于"什么算在内、什么不算"的说明见 `NOTICE.md`。

## 署名

| | |
|---|---|
| **Steadfast 0.8.0** | coderbot——原光影，以及全部基础渲染、配置与风格 |
| **Firmament 修改** | Remiiil1a——方向、测试、调参；代码由 **DeepSeek V4.1 Flash**（AI）编写 |
| **参考了其代码** | 参考 **TheCMK** 的 **Mellow Shader v3.4**（MIT）与 **geforcelegend** 的 **Sundial Lite**（GPLv3） |
| **labPBR 标准** | shaderLABS 社区——材质通道布局与约定 |

两个被参考的项目**没有任何素材被搬到这里**——没有贴图、没有 logo、没有截图；
它们与本包没有隶属关系，也没有为本包背书。它们的名字不是本包名称与标识的一部分。

两个被参考的项目在光影菜单里有各自独立的条目：
**「制作与许可 → 特别鸣谢」**。

## 许可

* Steadfast 版权归 coderbot 所有 (C) 2026，以 **GNU 通用公共许可证第 3 版或更高版本**
  授权，并带有 GPLv3 第 7 节允许的**附加条款**。本修改版以同样的条款分发——
  见 `LICENSE-ADDITIONAL-TERMS.md`。这些条款要求上面那段声明原文，
  以及名称以 `(edit of coderbot's Steadfast)` 结尾。
* Mellow Shader 版权归 TheCMK 所有 (c) 2026，**MIT**（`LICENSE-MELLOW-MIT.txt`）。
* Sundial Lite 版权归 geforcelegend 所有，**GPLv3**——与本包同一份许可，
  副本即 `LICENSE.md`。
* 本包不提供任何担保。完整摘要见 **`NOTICE.md`**，
  每个版本改了什么见 **`CHANGELOG.md`**；一版一份的详细日志是 `RELEASE_NOTES-*.md`，
  它们**保存在项目里，不随包发行**。
