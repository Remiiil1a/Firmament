<!--
GitHub Release 正文（v0.1）。发布设置：
  Tag     v0.1
  Title   Firmament - v0.1 (edit of coderbot's Steadfast)
  Asset   Firmament-v0.1-edit-of-coderbot-Steadfast.zip
  勾选    Set as a pre-release
上面这段注释在渲染后的页面里不显示。以下第一段英文是 Steadfast 附加许可条款
要求逐字保留、且必须排在下载链接之前的声明，请勿改动或移动。
-->

Steadfast is free and open-source software developed by coderbot, and can be downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth), https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and distribute it under the terms of the GNU General Public License, version 3.

---

## 下载 / Download

下载 **Assets** 里的 `Firmament-v0.1-edit-of-coderbot-Steadfast.zip` —— 自动生成的 "Source code" 压缩包不是光影包，不要下。放进 `.minecraft/shaderpacks/`，在 Iris 里选中并 Apply。

Get the zip from **Assets** - the auto-generated "Source code" archives are not the shader pack. Put it in `.minecraft/shaderpacks/`, select it in Iris and press Apply.

## 这是什么 / What this is

**中文**　Steadfast 0.8.0 的修改版。原光影由 **coderbot** 开发；本修改版由 **Remiiil1a** 提出需求、试玩与逐项调参，**全部代码改动由 AI（DeepSeek V4.1 Flash）编写**。喜欢 Steadfast 的画面风格，所以借助 AI 把想要的效果一点点加上去。**这不是官方版本，coderbot 不提供支持**，也请不要把本包的问题报到 Steadfast 的仓库或发布页。

**English**　An edit of Steadfast 0.8.0, which is developed by **coderbot**. The work was directed, play-tested and tuned by **Remiiil1a**; all of the code in this edit was written by an AI assistant (**DeepSeek V4.1 Flash**). This is **not** an official Steadfast release and is not supported by coderbot - please do not report bugs in it to Steadfast's issue tracker or project pages.

## v0.1 新增内容 / What's new in v0.1

| 中文 | English |
|---|---|
| **材质（PBR）**：按 labPBR 1.3 解码法线、高光/金属、材质环境光遮蔽、次表面散射、孔隙度/潮湿、自发光，并带逐通道的材质调试视图 | **Materials (PBR)**: labPBR 1.3 normal, specular/metal, material ambient occlusion, subsurface scattering, porosity/wetness and emissive maps, with a per-channel debug view |
| **反射**：每个材质的天空反射，加上屏幕空间反射（SSR）让反射里出现世界；染色玻璃与玻璃板也有镜面反射 | **Reflections**: a sky reflection term per material, plus screen-space reflections so the world appears in them; specular reflections on stained glass and panes |
| **末地**：末地自身的光照、虚空辉光、末地雾，以及判断维度的调试视图 | **The End**: its own light, a void glow, End haze, and a debug view for the dimension checks |
| **方块状体积云**：立方体云格组成的云层（默认边长 12 格），替代原版的扁平方块云；地形能遮挡它，云自身有顶有底、底面比顶面暗，随天气与风变化，只出现在主世界 | **Blocky volumetric clouds**: a layer of cube-shaped cloud cells replacing Minecraft's flat cloud boxes - occluded by terrain, with a lit top and a darker underside, following the weather and the wind, Overworld only |
| **切线基修复**：材质切线改用几何体自带的 `at_tangent`，修掉"特定距离法线翻转" | **Tangent frame fix**: material tangents now come from the geometry's own `at_tangent`, fixing normal maps flipping at distance |

出厂默认就是你看到的那套配置；菜单里的 `✎ EDIT默认 style` 可以在试过 Steadfast 自带风格之后一键回到原样，`材质（PBR）` 页下分三个子页放全部材质选项，`制作与许可` 页有署名。

## 运行要求 / Requirements

| 中文 | English |
|---|---|
| Iris 1.5 或更新版本，Minecraft 1.18.2 或更新版本 | Iris 1.5 or newer, Minecraft 1.18.2 or newer |
| **不支持 OptiFine**（这是 Steadfast 本身的限制） | **OptiFine is not supported** (that is Steadfast's own limitation) |

## 已知问题 / Known issues

* **TAA 未完成，默认关闭** —— 菜单里那四项要等你手动打开 TAA 才会生效。
  *TAA is off and unfinished; its options do nothing until it is switched on.*
* **视差（POM）未完成，默认关闭** —— 能用，但还没对着足够多的资源包调过，远处可能闪烁。
  *Parallax occlusion mapping is off and unfinished - it works, but is not tuned against enough resource packs and can shimmer at distance.*
* **反射只能反射屏幕内的东西，且只取上一帧**，粗糙表面是单次采样而不是模糊，很粗糙的反射材质可能发颗粒。
  *Reflections only see what is on screen and only from the previous frame; a rough surface gets a single sample rather than a blur.*
* **屋檐下、玻璃窗附近可能出现奇怪的天空反射** —— 天光会横向渗透，"天光很亮"不等于"能看见天空"；已有阈值选项能压掉大部分，玻璃窗那类情况无解。
  *Reflections can appear where sky light reaches the ground but the sky is not visible - there is a threshold option for most of it, but the glass-window case is not solvable without a real visibility test.*
* **实体材质是实验项**，可能被套上别的方块的材质；选项说明里写了怎么验证。
  *Entity materials are an experiment; the tooltip explains how to check and what to do if it looks wrong.*
* **只在单机单人环境下验证过**，没有做不同显卡的测试。
  *Verified in game by one person on one machine; no testing across GPU vendors.*
* **云不在反射里**：天空反射用的是本包的天空模型（里面没有云），屏幕空间反射会读到云。云层只在主世界出现，形状是程序化的，不会与重画过原版云贴图的资源包对齐。
  *The clouds are not in sky reflections (that is the pack's sky model) - screen-space reflections do include them. The layer is Overworld-only and procedural, so it will not line up with a resource pack that redraws the vanilla cloud texture.*

## 性能 / Performance

**中文**　这个版本比原版 Steadfast 明显更吃配置，两个原因：每个受光表面要多写两张材质缓冲（约每像素多 12 字节带宽），屏幕空间反射要在每个通过粗糙度上限的像素上追踪最多 12 步（未命中也要付）。掉帧时按这个顺序关：**屏幕空间反射 → 天空反射 → SSR 步数降到 8 / 粗糙度上限收到 0.1 → 关视差 → 降档位、降阴影分辨率与阴影距离**。

**English**　This costs noticeably more than upstream Steadfast. Every lit surface writes two extra buffers for the material data (roughly 12 bytes per pixel of extra bandwidth), and screen-space reflections march the depth buffer up to 12 steps on every pixel that passes the roughness limit - paid whether or not a ray hits. If you need the frames back, in order: **screen-space reflections → sky reflections → SSR steps down to 8 or roughness limit down to 0.1 → parallax off → a lower profile, shadow resolution and shadow distance**.

## 署名与许可 / Credits and licensing

**中文**　原光影 **Steadfast** 由 **coderbot** 开发，采用 **GNU GPLv3 加附加条款**发布；本修改版沿用同一许可，附加条款要求名称以 `(edit of coderbot's Steadfast)` 结尾、且任何传播页面必须在下载链接之前给出上面的声明原文。材质部分**借鉴了 Mellow Shader v3.4（TheCMK，MIT 许可）**的做法；用到的都是公开规范里的数学（GGX、Smith、Schlick、Henyey-Greenstein、labPBR 1.3），代码在 Steadfast 的风格下重写，未逐字搬运，也未使用其名称、logo 或截图。完整说明见包内 `NOTICE.md`，许可全文见 `LICENSE.md`、`LICENSE-ADDITIONAL-TERMS.md`、`LICENSE-MELLOW-MIT.txt`。

**English**　Steadfast is by **coderbot**, licensed under the **GNU GPLv3 with additional terms**; this edit is distributed under the same terms. The material work follows **Mellow Shader v3.4 by TheCMK** (MIT) - what is used from it is mathematics from published specifications (GGX, Smith, Schlick, Henyey-Greenstein, labPBR 1.3), reimplemented in Steadfast's own style, with none of that pack's assets, logo or screenshots, and no code copied across. Full details in `NOTICE.md`; licence texts in `LICENSE.md`, `LICENSE-ADDITIONAL-TERMS.md` and `LICENSE-MELLOW-MIT.txt`.

---

**非官方版本，不受 coderbot 支持。** 有问题请提到本仓库，不要提到 Steadfast 的仓库或发布页。

**Not an official Steadfast release, and not supported by coderbot.** Please report problems in this repository, not in Steadfast's.
