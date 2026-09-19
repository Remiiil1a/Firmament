# Firmament（edit of coderbot's Steadfast）

[English](README.md) | 简体中文

面向 **Minecraft: Java 版**、为 **Iris + Sodium** 制作的光影包。它是 coderbot 的
[Steadfast](https://github.com/coderbot16/Steadfast) 的修改版，名字也由此而来：
Steadfast 的附加条款要求修改版的名称以 `(edit of coderbot's Steadfast)` 结尾。

## Steadfast 与它的下载地址

> Steadfast 是由 coderbot 开发的自由开源软件，可从
> https://modrinth.com/shader/steadfast-shaders（Modrinth）、
> https://www.curseforge.com/minecraft/shaders/steadfast（CurseForge）或
> https://github.com/coderbot16/Steadfast（GitHub）下载。任何人都可以按
> GNU 通用公共许可证第 3 版的条款修改和分发它。

**本包不是 Steadfast 的官方发行版，coderbot 不为它提供支持。**
关于本包的问题请不要提交到 Steadfast 的 issue 区。

## 这个修改版加了什么

* **材质（PBR）**：读取 labPBR 资源包的法线、高光、视差、次表面与自发光贴图，
  并据此做反射与自阴影。
* **远景**：给阴影贴图够不到的远景补上屏幕空间阴影——Distant Horizons 与 Voxy
  的 LOD 地形本来一点阴影都没有。
* **不是平铺在地面的水**：瀑布侧面、沿坡流下的水现在也按水面绘制，
  表面样式、水色与反射都和静水一致，并按**该面自己的切线基**铺开，
  而不是按假定的世界轴。
* **时间抗锯齿（TAA）**：默认开启，历史权重随运动变化——静止时压噪点，
  走动时不拖影。
* **末地**：支持末地维度，而不是退回主世界的天空。
* 此外还有方块体积云、动态模糊等 Steadfast 自己的发行说明里写到的内容。

## 运行要求

* **Iris + Sodium**，Minecraft 1.21.x。**不支持 OptiFine**。
* **Voxy** 与 **Distant Horizons** 都支持；上面说的远景阴影需要装了其中之一才有意义。
* 材质相关功能需要 **labPBR 资源包**。没有资源包时本包照常工作，
  材质会解码成平坦表面。

## 安装

1. 把 `Firmament-v0.4-edit-of-coderbot-Steadfast.zip` 放进 `.minecraft/shaderpacks/`，
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
* 其余关于"什么算在内、什么不算"的说明见 `NOTICE.md`。

## 署名

| | |
|---|---|
| **Steadfast 0.8.0** | coderbot——原光影，以及全部基础渲染、配置与风格 |
| **Firmament 修改** | Remiiil1a——方向、测试、调参；代码由 **DeepSeek V4.1 Flash**（AI）编写 |
| **参考了其代码** | 参考 **TheCMK** 的 **Mellow Shader v3.4**（MIT）与 **geforcelegend** 的 **Sundial Lite**（GPLv3） |
| **labPBR 标准** | shaderLABS 社区——材质通道布局与约定 |

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
  每个版本改了什么见 **`RELEASE_NOTES-*.md`**（一版一份）—— 它们**保存在项目里，不随包发行**。
