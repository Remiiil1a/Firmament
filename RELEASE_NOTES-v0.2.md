<!--
GitHub Release 正文（v0.2）。发布设置：
  Tag     v0.2
  Title   Firmament - v0.2 (edit of coderbot's Steadfast)
  Asset   Firmament-v0.2-edit-of-coderbot-Steadfast.zip
  勾选    Set as a pre-release
上面这段注释在渲染后的页面里不显示。以下第一段英文是 Steadfast 附加许可条款
要求逐字保留、且必须排在下载链接之前的声明，请勿改动或移动。
-->

Steadfast is free and open-source software developed by coderbot, and can be downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth), https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and distribute it under the terms of the GNU General Public License, version 3.

---

## 下载 / Download

下载 **Assets** 里的 `Firmament-v0.2-edit-of-coderbot-Steadfast.zip` —— 自动生成的 "Source code" 压缩包不是光影包，不要下。放进 `.minecraft/shaderpacks/`，在 Iris 里选中并 Apply。

Get the zip from **Assets** - the auto-generated "Source code" archives are not the shader pack. Put it in `.minecraft/shaderpacks/`, select it in Iris and press Apply.

## 这是什么 / What this is

**中文**　Steadfast 0.8.0 的修改版。原光影由 **coderbot** 开发；本修改版由 **Remiiil1a** 提出需求、试玩与逐项调参，**全部代码改动由 AI（DeepSeek V4.1 Flash）编写**。喜欢 Steadfast 的画面风格，所以借助 AI 把想要的效果一点点加上去。**这不是官方版本，coderbot 不提供支持**，也请不要把本包的问题报到 Steadfast 的仓库或发布页。

**English**　An edit of Steadfast 0.8.0, which is developed by **coderbot**. The work was directed, play-tested and tuned by **Remiiil1a**; all of the code in this edit was written by an AI assistant (**DeepSeek V4.1 Flash**). This is **not** an official Steadfast release and is not supported by coderbot - please do not report bugs in it to Steadfast's issue tracker or project pages.

## 版本怎么算 / How the versions are counted

**中文**　**v0.1** = 材质（PBR）、反射、末地与切线基修复那一批。**v0.2 = 从「体积云」开始往后的全部内容** —— 体积云是 v0.2 加的第一样东西，之后的动态模糊、菜单整理与所有修复都算在 v0.2 里。两份更新日志分别对应这两批：`RELEASE_NOTES-v0.1.md`、`RELEASE_NOTES-v0.2.md`。

**English**　**v0.1** is the material work - materials (PBR), reflections, the End and the tangent frame fix. **v0.2 is everything from the cloud layer onward**: the clouds were the first thing it added, and the motion blur, the menu work and every fix after them belong to it as well.

## v0.2 新增内容 / What v0.2 added

| 中文 | English |
|---|---|
| **方块状体积云**（v0.2 的第一项）：立方体云格组成的云层，替代原版扁平方块云；在 deferred 趟沿视线步进，地形能挡住它；云格有顶有底、底面比顶面暗，挡住太阳时有亮边；随本包天气缓慢变化、随风漂移。只出现在主世界 | **A cloud layer of cube-shaped cells** (the first thing v0.2 added): marched along the view ray in the deferred pass so the terrain hides the clouds behind it - cell-shaped, so a cloud has a lit top, a darker underside and a bright rim, following the pack's weather slowly and drifting with the same wind the planar clouds use. Overworld only |
| **动态模糊**（默认关闭）：按相机在世界里的移动把画面糊开——走路、奔跑、下落、坐船、被击飞都有拖影；位移**逐像素**计算，因此脚下掠得比地平线快得多。可调模糊量与采样率 | **Motion blur** (off by default): blurs along the camera's travel - walking, running, falling, boats and knockback all trail. The movement is recovered **per pixel**, so the ground at your feet rushes past while the horizon barely moves. Amount and sample count are adjustable |
| **日月光源大小**：太阳/月亮按真实视角大小（约 0.53°）参与高光计算，抛光与金属面上是一轮日面圆盘而不是一个亮像素 | **Sun and moon size**: both are treated as lights with their real angular size (about 0.53°), so a polished or metallic surface catches the sun's disc rather than a bright pixel |
| **特效菜单二级分类**：`特效与后期处理` 分为 光照特效 / 镜头效果 / 色彩与色调 /【实验性】时间抗锯齿（TAA），TAA 的五项全部标注【实验性】 | **Effects menu split into sub-pages**: light effects, camera effects, colour and tonemapping, and [experimental] temporal anti-aliasing - the unfinished TAA is marked on its page and on all five of its options |

## v0.2 修复与调整 / What v0.2 fixed

| 中文 | English |
|---|---|
| **体积云不再出现在下界**：`dimension` 这个 uniform 缺失时会读成 0（主世界），现在同时用生物群系类别判断 | **The cloud layer stays out of the Nether**: a missing `dimension` uniform reads as the Overworld, so the biome category is now checked as well |
| **云的自身明暗恢复"硬切"**：此前为地形云影做的柔化在地面阴影移除后只剩"云看起来糊"，已恢复成逐格量化读取 | **A cloud's own shading is hard-edged again**: the softening that existed for the removed ground shadow only cost the look |
| **云不再向地面投影**（这是移除而不是新增）：它只能落在本包自己画的区块上、落不到 Distant Horizons / Voxy 的 LOD 上，且走路时的抖动始终没治好 | **The cloud layer no longer casts a shadow on the ground** (a removal, not an addition): it could only ever fall on terrain this pack draws, and its walk-time jitter was never settled |
| **玻璃与平静水面的反射不再随走路摇晃抖动**：取样点按上一帧的相机重投影（此前用这一帧的位置去读上一帧的画面，走路时反射内容会来回滑） | **Reflections on glass and calm water stop shivering with the walk bob**: the sample is reprojected into the previous frame's camera |
| **手持物品不再"透视"**：手是挂在相机前的、不在世界里，环境反射的两半（屏幕空间追踪会命中物品背后的世界、天空反射会照到玩家背后的天空）在它这里都不成立，现已整块排除；材质法线、粗糙度、材质 AO、环境光与日月高光全部保留 | **A held item no longer shows the world through itself**: the hand is not part of the world a reflection is built from, so it no longer gets one. Its material normal, roughness, AO, ambient response and sun highlight are all kept |
| **日/月高光的加宽量纲修正**：此前把角度按平方和加进了粗糙度（而 `D_GGX` 的形参本身就是它要平方的 √α），实际效果小了约四个数量级，等于没生效 | **The sun's highlight was widened in the wrong units**: the angle had been added to the roughness, which `D_GGX` then squares, so the effect was some four orders of magnitude too small to see |
| **动态模糊不再被"视角摇晃"带动**：摇晃本质是旋转，而且与转头共用同一个相机矩阵，无法按名字剔除；现在按**幅度**区分——转头推动画面超过几像素/帧才计入，走路时摇晃每帧只推动一两像素 | **Motion blur is no longer driven by the walk bob**: the bob is a rotation and shares the camera's matrix with the turning, so size is what separates them - a turn is blurred once it moves the picture more than a few pixels a frame, and the bob moves it one or two |
| **出厂默认按实际调校值更新**：白昼天空光照模式、物理光照模型、云层速度三项按试玩中调好的值写入默认 | **The shipped defaults were updated to the values this was actually tuned to** for the day sky lighting model, the physical lighting model and the cloud speed |

## 保留的趣味项 / Kept on purpose

**中文**　动态模糊的第一个版本有一个 bug：一块"错误的位移"圆盘跟着镜头转，但转的角度是**两倍**（面朝正北时与视线重合、什么也不做；视角转 90°，它就跑到正南）。成因是判断转头时把**视图空间**的方向直接交给了**上一帧的矩阵**，等于把相机自身的旋转算了两遍。它已经被修掉，但按需求**原样保留成一个默认关闭的开关**：

* 菜单：`特效与后期处理 → 镜头效果 → 趣味：模糊透镜（原来的 bug）`
* 打开时是**替换**正确的转头模糊，不是叠加。
* 与画质无关，纯属好玩。

**English**　The first version of the motion blur had a bug: a disc of movement nobody made, turning with the camera at **twice** the angle - looking north it sat exactly where you were looking and did nothing, and a quarter turn of the view carried it half a turn round. It came from handing a **view-space** direction to the **previous frame's matrix**, which applies the camera's own rotation a second time. It is fixed, and kept exactly as it was behind an option that is off by default:

* Menu: `Effects & post-processing → Camera effects → Fun: the blur lens (an old bug)`
* Turning it on **replaces** the turning blur rather than adding to it.
* It does nothing for image quality; it is there because it is interesting to look at.

## 运行要求 / Requirements

| 中文 | English |
|---|---|
| Iris 1.5 或更新版本，Minecraft 1.18.2 或更新版本 | Iris 1.5 or newer, Minecraft 1.18.2 or newer |
| **不支持 OptiFine**（这是 Steadfast 本身的限制） | **OptiFine is not supported** (that is Steadfast's own limitation) |

## 已知问题 / Known issues

* **TAA 未完成，默认关闭**，菜单里已统一标注【实验性】；那四项参数要等你手动打开 TAA 才会生效。
  *TAA is off and unfinished, and is marked [experimental] in the menu; its four options do nothing until it is switched on.*
* **动态模糊只知道相机**：世界里会自己动的实体、水流、掉落物都不糊（Steadfast 没有运动矢量），手持物品也不糊（它在屏幕上静止）；因为摇晃与转头无法区分，极慢的转头同样不糊。
  *Motion blur only knows about the camera: nothing that moves on its own inside the world blurs, the hand does not blur, and neither does a very slow turn.*
* **视差（POM）未完成，默认关闭** —— 能用，但还没对着足够多的资源包调过，远处可能闪烁。
  *Parallax occlusion mapping is off and unfinished - it works, but is not tuned against enough resource packs and can shimmer at distance.*
* **反射只能反射屏幕内的东西，且只取上一帧**，粗糙表面是单次采样而不是模糊，很粗糙的反射材质可能发颗粒。
  *Reflections only see what is on screen and only from the previous frame; a rough surface gets a single sample rather than a blur.*
* **屋檐下、玻璃窗附近可能出现奇怪的天空反射** —— 天光会横向渗透，"天光很亮"不等于"能看见天空"；已有阈值选项能压掉大部分，玻璃窗那类情况无解。
  *Reflections can appear where sky light reaches the ground but the sky is not visible - there is a threshold option for most of it, but the glass-window case is not solvable without a real visibility test.*
* **实体材质是实验项**，可能被套上别的方块的材质；选项说明里写了怎么验证。
  *Entity materials are an experiment; the tooltip explains how to check and what to do if it looks wrong.*
* **云不在天空反射里**，只在主世界出现，形状是程序化的，不会与重画过原版云贴图的资源包对齐；**云不投影到地面**。
  *The clouds are not in sky reflections, the layer is Overworld-only, its shape is procedural, and it does not cast a shadow on the ground.*
* **只在单机单人环境下验证过**，没有做不同显卡的测试。
  *Verified in game by one person on one machine; no testing across GPU vendors.*

## 性能 / Performance

**中文**　比原版 Steadfast 明显更吃配置：每个受光表面要多写两张材质缓冲（约每像素多 12 字节带宽），屏幕空间反射要在每个通过粗糙度上限的像素上追踪最多 12 步（未命中也要付），云层要对每个天空像素做最多 12 次噪声取样。**动态模糊默认关闭，关着时零开销**；打开后每帧多付"采样率 × 全屏一次取样"。掉帧时按这个顺序关：**动态模糊 → 云层步进次数（12→8）→ 屏幕空间反射 → 天空反射 → SSR 步数降到 8 / 粗糙度上限收到 0.1 → 关视差 → 降档位、降阴影分辨率与阴影距离**。

**English**　This costs noticeably more than upstream Steadfast: every lit surface writes two extra material buffers (roughly 12 bytes per pixel of extra bandwidth), screen-space reflections march the depth buffer up to 12 steps on every pixel that passes the roughness limit - paid whether or not a ray hits - and the cloud layer walks the sky pixel by pixel. **Motion blur is off by default and costs nothing while it is off**; switched on, it costs one screen-wide fetch per sample. If you need the frames back, in order: **motion blur → cloud march steps (12 → 8) → screen-space reflections → sky reflections → SSR steps down to 8 or the roughness limit down to 0.1 → parallax off → a lower profile, shadow resolution and shadow distance**.

## 署名与许可 / Credits and licensing

**中文**　原光影 **Steadfast** 由 **coderbot** 开发，采用 **GNU GPLv3 加附加条款**发布；本修改版沿用同一许可，附加条款要求名称以 `(edit of coderbot's Steadfast)` 结尾、且任何传播页面必须在下载链接之前给出上面的声明原文。材质部分**借鉴了 Mellow Shader v3.4（TheCMK，MIT 许可）**的做法；用到的都是公开规范里的数学（GGX、Smith、Schlick、Henyey-Greenstein、labPBR 1.3），代码在 Steadfast 的风格下重写，未逐字搬运，也未使用其名称、logo 或截图。完整说明见包内 `NOTICE.md`，许可全文见 `LICENSE.md`、`LICENSE-ADDITIONAL-TERMS.md`、`LICENSE-MELLOW-MIT.txt`。

**English**　Steadfast is by **coderbot**, licensed under the **GNU GPLv3 with additional terms**; this edit is distributed under the same terms. The material work follows **Mellow Shader v3.4 by TheCMK** (MIT) - what is used from it is mathematics from published specifications (GGX, Smith, Schlick, Henyey-Greenstein, labPBR 1.3), reimplemented in Steadfast's own style, with none of that pack's assets, logo or screenshots, and no code copied across. Full details in `NOTICE.md`; licence texts in `LICENSE.md`, `LICENSE-ADDITIONAL-TERMS.md` and `LICENSE-MELLOW-MIT.txt`.

---

**非官方版本，不受 coderbot 支持。** 有问题请提到本仓库，不要提到 Steadfast 的仓库或发布页。

**Not an official Steadfast release, and not supported by coderbot.** Please report problems in this repository, not in Steadfast's.
