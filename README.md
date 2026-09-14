# Firmament - v0.2 (edit of coderbot's Steadfast)

Steadfast is free and open-source software developed by coderbot, and can be downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth), https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and distribute it under the terms of the GNU General Public License, version 3.

**Firmament** is an edit of **Steadfast 0.8.0**. It keeps Steadfast's look,
structure and performance tiers, and adds material (PBR) support, support for
the End, and a few effects of its own. It is version 0.2 - a personal edit that
is still unfinished, not an official Steadfast release, and not supported by
coderbot.

> **On the name:** Steadfast's additional licence terms require the name of a
> modified version to end with `(edit of coderbot's Steadfast)`, and forbid the
> name "Steadfast" anywhere else in it. So this edit is called
> `Firmament - v0.2 (edit of coderbot's Steadfast)`, and the file it is
> distributed as is named `Firmament-v0.2-edit-of-coderbot-Steadfast.zip`. That
> parenthesis is not decoration - it is the licence, and it has to stay on the
> end of the name on every page or download that conveys this pack. See
> `NOTICE.md`.

## What this is, and who made it

* **Original shader:** [Steadfast](https://github.com/coderbot16/Steadfast) 0.8.0
  by **coderbot**. All of the rendering, the atmosphere, the water, the shadows,
  the clouds, the profiles and the option system are his work. This edit only
  adds to it.
* **Editing, and writing the additions:** **Remiiil1a**, with the changes
  **written entirely by an AI assistant (DeepSeek V4.1 Flash)**.
* **Why:** Remiiil1a is not a shader programmer. Steadfast's art style is what
  they wanted to play with, so the additions they wanted - real material
  response on blocks, reflections, a proper End - were described to the AI and
  implemented that way, one feature at a time, each one reviewed in game before
  the next was started.
* **What that means for you:** the code added here has been checked for the
  things that can be checked offline, and every option is documented in its
  tooltip, but it has **not** been through the kind of review a hand-written
  shader gets. If something looks wrong, treat that as expected for an edit at
  this stage rather than as surprising.

## What this edit adds over Steadfast 0.8.0

Everything below is **on by default** except the two options marked otherwise,
and every one of them can be switched off in the settings menu. The pack's
defaults are the ones this edit was tuned with, so it looks like the
screenshots/gameplay it was built around out of the box.

### Materials (PBR)

Following the [labPBR 1.3 material standard](https://shaderlabs.org/wiki/LabPBR_Material_Standard),
so it works with any PBR resource pack that follows it:

* **Normal maps** (`_n`), with strength, mip fade and a distance fade.
* **Specular / metal maps** (`_s`): perceptual smoothness, F0, hardcoded metals,
  and metal-vs-dielectric handling.
* **Material ambient occlusion** (`_n.b`), darkening indirect light only.
* **Subsurface scattering** (`_s.b` upper half): light coming through leaves and
  thin materials, plus softer shadow edges.
* **Porosity / wetness** (`_s.b` lower half): porous materials darken in rain.
* **Emissive maps** (`_s.a`), gated by the light map so that a block that is not
  a light source does not glow.
* **Parallax occlusion mapping** (`_n.a`) - **off by default, and unfinished.**
* A **material debug view** that shows each channel on its own (height,
  smoothness, F0, normal, tangents, occlusion, scattering, emission), which is
  the fastest way to find out what a resource pack actually ships.

### Reflections

* A **sky reflection** per material, with the reflection direction bent towards
  the surface normal according to roughness, so a polished block reflects the
  sky and a rough one does not read as a mirror.
* **Screen-space reflections** (on by default) that let that reflection contain
  the world and not just the sky. They are traced through the depth buffer in
  the deferred pass, so they can only reflect what is on screen and only from
  the previous frame; a ray that misses falls back to the sky. That previous
  frame is read where *it* had the point the ray hit, not where this frame has
  it, so a reflection does not slide about as the view bobs while walking.
* Stained glass and glass panes get specular reflections as well.
* The sun and moon are treated as **lights with a real size** rather than as
  points, so the highlight a polished or metallic block catches is the disc of
  the sun (about half a degree across) and not a single bright pixel. `Sun and
  moon size` in the material options scales it, from 0.0 for a point light to
  several times the real size.

### The End

Steadfast has no real support for the End; this edit gives it some:

* The End's own light, so its islands are not lit by the ambient floor alone.
* A **void glow** from below, so the islands do not read as flat cutouts.
* **End haze**, so islands fade into space rather than into a grey cave wall.
* A debug view for the checks that decide whether the current dimension is the
  End, since not every Iris version provides every uniform.

### Clouds (blocky volumetric)

* A cloud layer made of **cube-shaped cells** (12 blocks on a side by default)
  that replaces Minecraft's flat cloud boxes, which are switched off while it is
  on.
* It is marched along the view ray in the deferred pass, so the terrain hides
  the clouds behind it. Cloud cells have a top and a bottom, their undersides
  are darker than their tops, and a cloud standing between you and the sun has a
  bright rim.
* It does **not** cast a shadow on the ground. An earlier build had it do that,
  and it was removed: the shadow could only fall on terrain this pack draws, not
  on the level-of-detail terrain Distant Horizons/ Voxy draws, and getting it to
  hold still while walking was not worth the cost for a shadow with a hole at the
  horizon. The lighting *inside* the layer (a cell lit only by the light that
  reaches it past its neighbours) is still what makes the layer read as volume.
* It follows the pack's own weather, **slowly**: it thickens from the wetness the
  game tracks rather than from the rain itself, so rain takes about a minute to
  work through the clouds and the same to clear out again. It drifts with the
  same wind the planar clouds use.
* Overworld only - the End and the Nether are left alone.
* Cost and tuning are both in `Atmosphere & clouds`: cloud size, coverage,
  height, thickness, speed and step count. Lower the step count first if it is
  too expensive; raise the cloud size for fewer, bigger clouds, which is also
  cheaper. Nothing here is paid for by the terrain.

### Motion blur (new in v0.2)

* The camera's own movement blurs the image along it: walking, running, falling,
  riding a boat and being knocked back all trail.
* It is worked out **per pixel** - each pixel's position is recovered, the
  camera's travel over the last frame says where that point was a frame ago, and
  the blur runs between the two screen positions. Walking therefore makes the
  ground at your feet rush past while the horizon barely moves, which is what a
  camera does and what one screen-wide offset cannot do.
* **The walk bob is deliberately not blurred.** It is a rotation of the view,
  and it shares the camera's matrix with the turning, so it cannot be filtered
  out by name - only by size. A turn is blurred once it is moving the picture
  more than a few pixels a frame; the bob moves it one or two, and a slow
  deliberate turn does not blur either.
* Nothing with its own motion inside the world is blurred: Steadfast has no
  motion vectors, so a mob, a river or a falling block keeps its detail. So does
  the hand, which hangs in front of the camera and is standing still on screen.
* **Off by default.** Turn it on under `Effects & post-processing → Camera
  effects`, with a blur amount and a sample count next to it.
* `Fun: the blur lens` on the same page is a bug that was in the first release
  of this effect, kept as a curiosity. See `RELEASE_NOTES-v0.2.md`.

### One correctness fix

Material tangent frames are now built from the geometry's own tangents
(`at_tangent`, the same source Mellow uses) instead of being reconstructed from
the depth buffer. The old approach flipped normal maps at certain distances,
which looked like a broken material rather than a broken tangent basis. This is
the one default that changes the image, because it fixes a bug.

### Where the material work comes from

The material implementation **follows Mellow Shader v3.4 by TheCMK**, and was
written with reference to how it does this. What is used from it is mathematics
that is published anyway - the GGX distribution, the Smith visibility term,
Schlick Fresnel, the Henyey-Greenstein phase function, and the labPBR channel
layout - reimplemented in Steadfast's own style and naming, with no Mellow code
copied across and none of Mellow's assets, logo or branding used anywhere.
Mellow's MIT licence is included as `LICENSE-MELLOW-MIT.txt`, and the credit is
also shown in the settings menu.

## How the versions are counted

* **v0.1** is the material work: materials (PBR), reflections, the End, and the
  tangent frame fix. That is what `RELEASE_NOTES-v0.1.md` describes.
* **v0.2** is everything from the **cloud layer onward**. The clouds are the
  first thing v0.2 added, and the motion blur, the menu work and every fix made
  after them belong to it too. That is what `RELEASE_NOTES-v0.2.md` describes.

## What v0.2 added

* **A cloud layer made of cube-shaped cells**, drawn in place of Minecraft's
  flat cloud boxes: marched along the view ray in the deferred pass, so the
  terrain hides the clouds behind it; cell-shaped, so a cloud has a top and a
  bottom, a darker underside and a bright rim when it stands between you and the
  sun. It follows the pack's weather slowly and drifts with the same wind the
  planar clouds use. Overworld only. See "Clouds" below.
* **Motion blur**, driven by the camera's own travel - walking, running,
  falling, boats and knockback all trail the way they do in a camera, and the
  walk bob is deliberately left out of it. Off by default. See "Motion blur"
  below.
* **Sun and moon size** - the highlight a polished or metallic surface catches
  is the sun's actual disc rather than a single bright pixel.
* **The effects menu was split into sub-pages** - light, camera, colour and
  temporal anti-aliasing each have their own page, and the unfinished TAA is
  marked experimental on all of them.

## What v0.2 fixed since the clouds landed

* **The cloud layer stays out of the Nether** (a missing `dimension` uniform
  reads as the Overworld, so the biome category is checked as well), and **its
  own shading is hard-edged again**, the way it was before the removed ground
  shadow softened it out to a cell's width. **It no longer casts a shadow on the
  ground** at all: that was tried, could only ever fall on terrain this pack
  draws, and was taken back out.
* **Reflections on glass and calm water stop shivering with the walk bob**, by
  reading the previous frame where *it* had the point the ray hit rather than
  where this frame has it.
* **A held item no longer shows the world through itself.** The hand is not part
  of the world a reflection is built from - a traced ray from it lands on
  whatever stands behind the item, and a sky reflection lands on the sky behind
  the player - so it is left out of the environment reflection entirely. It
  keeps its normal, roughness, ambient response and sun highlight.
* **The sun's highlight was being widened in the wrong units** and so barely
  changed at all; it now spreads the way half a degree of sunlight should.

## Kept on purpose

* `Fun: the blur lens` - a bug the motion blur used to have, kept as a toggle
  because it turned out to be interesting to look at. It turns with the camera
  at twice the angle: looking north it sits where you are looking and does
  nothing, and a quarter turn of the view carries it half a turn round. See
  `RELEASE_NOTES-v0.2.md`.

## Performance: this costs noticeably more than Steadfast

Steadfast is built to be cheap: it is a forward renderer with a small number of
buffer writes, made for integrated graphics. **This edit is heavier, and you
should expect lower FPS than upstream Steadfast at the same profile.** Two
things cause that:

1. **The material G-buffer.** Every lit surface writes two extra buffers (world
   normal + roughness, and F0) so the deferred pass can reflect without
   re-deriving the material. That is roughly 12 bytes per surface pixel of extra
   bandwidth, every frame, whether or not reflections are on.
2. **The traces.** Sky reflections evaluate a sky model per covered pixel.
   Screen-space reflections additionally march the depth buffer, up to
   `PBR_SSR_STEPS` steps per pixel, on every pixel that passes the roughness
   limit - those steps are paid whether or not a ray hits anything.

If you need the frames back, in this order:

0. Lower **Cloud march steps** (12 → 8) in `Atmosphere & clouds`. The cloud
   layer walks the sky pixel by pixel and the step count is the whole cost of
   it. Turning the layer off entirely (`Blocky volumetric clouds`) returns you to
   Minecraft's own cloud boxes.
1. Turn off **Screen-space reflections** (`PBR_SSR`). Biggest single win; sky
   reflections remain.
2. Turn off **Sky reflections** (`PBR_REFLECTIONS`) entirely. Materials still
   shade correctly; they just stop reflecting the environment.
3. Lower **SSR steps** (12 → 8) or tighten **SSR roughness limit** (0.2 → 0.1)
   so fewer surfaces are traced.
4. Turn off **Parallax** if you had it on - it is off by default.
5. Then go down Steadfast's own quality ladder: a lower profile, a lower
   `shadowMapResolution`, a shorter `shadowDistance`.

Steadfast's own performance notes still describe the base cost of everything
else; see "Upstream notes" below.

## Known limitations and rough edges

These are the parts that are known to be incomplete:

* **TAA is unfinished and is off**, and the menu now says so: the temporal
  anti-aliasing page and every option on it are marked **[experimental]**. It
  has no motion vectors, so anything that moves relative to the world (mobs,
  water, particles, the held item) cannot be reprojected and has to be handled
  by rejecting history instead of tracking it. Its four options do nothing until
  TAA itself is switched on.
* **Motion blur only knows about the camera.** A mob that walks past, flowing
  water, a falling block - none of them blur, because nothing in this pack
  records where they were a frame ago. And because the walk bob cannot be told
  apart from a real turn, a very slow turn is not blurred either.
* **Parallax occlusion mapping is unfinished, and off by default.** It works,
  but it has not been tuned against enough resource packs, and at distance it
  can shimmer. The depth, step count and maximum offset are all exposed if you
  want to experiment.
* **Reflections are screen-space only.** They cannot see behind you, they use
  the previous frame's colours, and a rough surface gets a single sample rather
  than a blur, so very rough reflective materials can look grainy. The sample is
  reprojected into the previous frame's camera, which is what keeps a mirror
  (glass, or water with the waves off) from shivering as you walk.
* **Reflections can appear where sky light reaches but sky cannot be seen.**
  Minecraft spreads sky light sideways under overhangs and through glass, so
  "this pixel is brightly sky-lit" does not mean "this pixel can see the sky".
  There is a threshold option (`PBR_REFLECTION_SKY_MIN`) that removes most of
  it, but the glass-window case is not solvable without a real visibility test.
* **Entity materials are an experiment.** The block atlas is the only atlas
  that Iris is documented to build material maps for, so an entity may end up
  shaded with an arbitrary block's material. `PBR_ENTITIES` is on by default
  because that is how to find out; the tooltip explains how to check and what to
  do if it looks wrong.
* **The clouds are not in reflections.** A sky reflection is the pack's sky
  model, which has no cloud layer in it, so water and glass do not reflect the
  clouds - screen-space reflections do, since those read the previous frame. The
  layer is also Overworld-only and does not appear in the Nether or the End.
* **The cloud layer's shape is procedural.** It does not follow Minecraft's own
  cloud texture, so it will not line up with a resource pack that redraws the
  vanilla clouds; coverage, height and thickness are what to adjust instead.
* **Nothing here is exhaustively tested.** The edit was developed without the
  ability to run the game in the development environment, so verification was
  done in game by one person on one machine. There are no benchmarks for other
  GPU vendors.
* **Inherited from upstream:** Steadfast requires Iris (1.5+, Minecraft 1.18.2+)
  and does **not** support OptiFine, and it does not support the Nether or End
  to the same standard as the Overworld - which is exactly what the End work
  here is a partial answer to.

## Installation

1. Put `Firmament-v0.2-edit-of-coderbot-Steadfast.zip` into
   `.minecraft/shaderpacks/`.
   * Do not repack the folder yourself with a tool that writes backslash entry
     names - Java looks for `shaders/...` and the pack will fail to load.
2. Select it in Iris and press **Apply**. Changing any option requires Apply to
   recompile.
3. If you do not like the default material look, the **Materials (PBR)** page in
   the settings menu is where everything lives, split into material maps,
   surface response, and coverage. The `✎ EDIT默认 style` profile restores the
   shipped defaults.

## Settings menu: what is where

* `✎ EDIT默认 style` (profile) - the configuration this edit ships with: the look
  the pack was tuned to, with the material options at their tuned values.
  Selecting it after trying one of Steadfast's styles puts that look back.
* **Materials (PBR)** - format switch, debug view, and three sub-pages:
  material maps and detail, surface response and reflections, coverage.
* **Effects & post-processing** - four sub-pages: `Light effects` (godrays,
  night desaturation), `Camera effects` (motion blur and its two controls, plus
  the blur lens), `Colour and tonemapping`, and `[experimental] Temporal
  anti-aliasing` (TAA and its four options).
* **Credits & licence** - who wrote what, with the licence text in the tooltips.
* Everything else is Steadfast's own menu, unchanged.

## Credits

| | |
|---|---|
| **Steadfast 0.8.0** | coderbot - original shader, all of the base rendering, profiles, options and style |
| **Firmament edit** | Remiiil1a - direction, testing, tuning; code written by **DeepSeek V4.1 Flash** (AI) |
| **Material (PBR) approach** | follows **Mellow Shader v3.4** by **TheCMK** (MIT) |
| **labPBR standard** | shaderLABS community - material channel layout and conventions |

## Licence

* Steadfast is Copyright (C) 2026 coderbot, licensed under the **GNU General
  Public License, version 3 or later**, with **additional terms** under GPLv3
  section 7. This edit is distributed under the same terms. **Read
  `LICENSE-ADDITIONAL-TERMS.md`** - among other things it requires the
  `(edit of coderbot's Steadfast)` name ending and the notice quoted at the top
  of this file.
* Mellow Shader is Copyright (c) 2026 TheCMK, licensed under the **MIT
  License** (`LICENSE-MELLOW-MIT.txt`); `LICENSE-MELLOW-APACHE.txt` is included
  from that pack verbatim as well.
* Full details, including what may and may not be done when redistributing, are
  in **`NOTICE.md`**.
* There is no warranty, as set out in the GPL.

## Upstream notes (Steadfast's own README, kept for reference)

The following is from Steadfast 0.8.0's README, describing the base this edit is
built on. Where it says Steadfast lacks dimension support, see "The End" above -
this edit adds a first pass at it.

> Steadfast is a remarkably fast and unobtrusive shader pack with exceptional
> attention-to-detail. Easy on the eyes and on your computer, Steadfast massively
> improves the graphical quality and realism of Minecraft without getting in the
> way of actually playing the game.

**How fast is it really?** Steadfast runs great even on midrange laptops from
5+ years ago, with the default High profile delivering a smooth 60+ FPS
experience on most computers capable of running Minecraft. On computers with a
dedicated high-end graphics card, Steadfast flies and even the High profile can
reliably reach 250-500 FPS. With a lower profile, it runs playably even on a
Raspberry Pi. Steadfast is designed for mobile / integrated graphics hardware,
and is built to require minimal graphics memory bandwidth and only moderate
graphical compute power. (This edit's additions move it away from that target -
see "Performance" above.)

**Features:** semi-realistic atmosphere with high-quality sky and fog; real-time
shadows cast by the sun and moon; foliage that waves with the wind and has
subsurface light scattering; tuned lighting that gives the illusion of bright
sunlight and darker nights and interiors without auto-exposure; approximate
light shafts from the sun and moon; detailed water waves with depth, reflection,
refraction and absorption; water and ice that reflect what is on screen;
water caustics; cirrus clouds and vanilla blocky clouds; ambient occlusion
through Minecraft's smooth lighting; integration with Distant Horizons and Voxy;
and support for high-performance rendering paths in mods like Create through the
Colorwheel add-on.

**Platform compatibility:** NVIDIA, AMD and Intel GPUs; macOS including Apple
Silicon; Linux including Mesa drivers (Raspberry Pi, Steam Deck); Minecraft
1.18.2 and above using Iris 1.5 or newer.

**Support policy (upstream):** coderbot aims for a high standard of quality in
the beta testing phase and asks that duplicate bug reports be avoided and that
reports be directed to the right project. Steadfast cannot be supported on
phones or mobile devices through PojavLauncher-style setups.

## Support for this edit

There is none to speak of: this is a personal edit, it is not affiliated with or
endorsed by coderbot, and **do not report bugs in it to Steadfast's issue
tracker or Modrinth/CurseForge pages.** The tooltip behind every option says
what it does; if you find a bug, the most useful thing you can attach is a
screenshot plus the option values that produce it. (The working notes for the
material port are in `PBR_PORTING.md`, which is kept with the project this edit
was built in and is not shipped inside the pack.)

---

## 中文说明

**这是什么。** 这是 **Steadfast 0.8.0** 的修改版。原光影由 **coderbot** 开发，本修改版的需求、调校与试玩由 **Remiiil1a** 负责，**全部代码改动由 AI（DeepSeek V4.1 Flash）编写**——本人不写着色器编程，因为很喜欢 Steadfast 的画面风格，所以借助 AI 一点点加上自己想要的效果。**这不是官方版本，coderbot 不提供支持**，也请不要把本包的问题报到 Steadfast 的仓库或发布页。

**加了什么。**

* **材质（PBR）**：按 labPBR 1.3 规范解码法线、高光/金属、材质环境光遮蔽、次表面散射、孔隙度/潮湿、自发光，并有一个可以逐通道查看的材质调试视图。普通 PBR 资源包即可生效。
* **反射**：每个材质的天空反射（按粗糙度把反射方向朝法线偏折），以及屏幕空间反射（SSR）——让反射里出现世界而不只是天空；染色玻璃与玻璃板也有镜面反射。
* **日月光源大小**：太阳与月亮被当成**有实际大小的光源**而不是点光源，所以抛光面与金属面上接到的高光是太阳真实的圆盘（约 0.53° 视角），而不是一个亮像素。材质选项里的「日月光源大小」可调：0.0 = 点光源、1.0 = 真实大小（默认）、再往上是夸张化。
* **末地维度**：末地自身的光照、虚空辉光、末地雾，以及一个判断维度的调试视图。
* **方块状体积云**：用一个个立方体云格（默认边长 12 格）组成云层，替代 Minecraft 那种扁平方块云（开启时原版云会自动关闭）。云在 deferred 趟沿视线步进，所以地形能挡住它后面的云；云格有顶有底、底面比顶面暗，挡在太阳前面会有亮边。它会跟着本包自己的天气走（下雨自动加厚），并随风漂移。只出现在主世界。云层**不向地面投影**（早先做过，已移除：它只能落在本包自己画的区块上、落不到 Distant Horizons / Voxy 的 LOD 上，而且走路时固定不下来）。
* **动态模糊（v0.2 新增）**：按**相机在世界里的移动**把画面沿运动方向糊开——走路、奔跑、下落、坐船、被击飞都有拖影。位移是**逐像素**算的，所以走路时脚下飞快掠过、地平线几乎不动。「**视角摇晃刻意不参与**」：它本质是旋转，且与转头共用同一个矩阵，只能按幅度区分——转头推动画面超过几个像素/帧才计入，而摇晃每帧只推一两像素，因此**手搭在鼠标上的慢速转头也不会糊**。世界内部会自己动的东西（实体、水流、掉落物）以及手持物品都不参与。**默认关闭**，菜单里可调模糊量与采样率。
* **切线基修复**：材质切线改用几何体自带的切线（`at_tangent`），修掉了此前"特定距离法线翻转"的问题。

**版本是怎么算的。** **v0.1** = 材质（PBR）、反射、末地、切线基修复这一批（见 `RELEASE_NOTES-v0.1.md`）。**v0.2 = 从体积云开始往后的全部内容** —— 体积云是 v0.2 加的第一样东西，之后做的动态模糊、菜单整理和所有修复都算在 v0.2 里（见 `RELEASE_NOTES-v0.2.md`）。

**v0.2 新增。**

* **方块状体积云**（v0.2 的第一项，见上）。
* **动态模糊**（默认关闭，见上）。
* **日月光源大小**：太阳与月亮按真实视角大小参与高光计算。
* **特效菜单二级分类**：光照特效 / 镜头效果 / 色彩与色调 /【实验性】时间抗锯齿（TAA），**TAA 相关的五项统一标注【实验性】**。

**v0.2 之后修的。**

* **云**：下界不再出云（`dimension` 缺失时会读成主世界，现在同时看生物群系类别）；云的自身明暗恢复"硬切"；**不再向地面投影**（做过，只能落本包自己画的区块上、落不到 DH/Voxy 的 LOD 上，已整体移除）。
* **反射**：玻璃与平静水面的反射不再随走路摇晃抖动（取样点按上一帧的相机重投影）。
* **手持物品不再"透视"**：手不在世界里，环境反射的两半在它这里都拿不到正确输入，现已整块排除；材质法线、粗糙度、材质 AO、环境光与日月高光全部保留。
* **日/月高光的加宽量纲修正**：此前把角度加进了会被平方的粗糙度，实际效果小了约四个数量级，等于没生效。

**保留的趣味项**：`趣味：模糊透镜（原来的 bug）` —— 动态模糊早期那个"跟着镜头转、角度是两倍"的 bug（面朝正北与视线重合、什么都不做；视角转 90°，它跑到正南），按你的要求原样保留成一个默认关闭的开关，成因与行为都写在它的说明里。

**性能：比原版更吃配置。** 三个原因：每个受光表面要多写两张材质缓冲（约每像素 12 字节带宽）；SSR 要在每个通过粗糙度上限的像素上走最多 12 步；云层要对每个天空像素做最多 12 次噪声取样（云自身受光再多几次，地面不受影响）。开启动态模糊后还要按采样率给整屏加一次取样（默认关，关着时零开销）。掉帧时按这个顺序关：**动态模糊 → 云层步进次数（12→8）→ 屏幕空间反射 → 天空反射 → 把 SSR 步数降到 8 / 把粗糙度上限收到 0.1 → 关视差 → 降档位、降阴影分辨率与距离**。

**还不完善的地方（v0.2）。** 云层**不会出现在反射里**（天空反射用的是本包的天空模型，里面没有云；屏幕空间反射会带到云，因为读的是上一帧）；云层的形状是程序化生成的，不会与重画过原版云贴图的资源包对齐；云层只在主世界出现。**TAA 未完成、默认关闭，菜单里已统一标注【实验性】**（没有运动矢量，所以会自己动的东西只能靠丢弃历史来处理；那四项参数要等你手动打开 TAA 才生效）；**动态模糊只知道相机**——世界里会自己动的实体/水流/掉落物都不糊，而且因为摇晃与转头无法区分，极慢的转头也不糊；视差 **未完成、默认关闭**；反射只能反射屏幕内的东西、只取上一帧（取样点按上一帧的相机重投影过，所以走路时不会随视角摇晃滑动）、粗糙面没有模糊；屋檐下与玻璃窗附近可能出现奇怪的天空反射（天光会横向渗透，这是"能看见天空"与"天光很亮"不等价导致的）；实体材质是实验项；只在单机单人环境下验证过，没有做不同显卡的测试。需要 **Iris 1.5+ / MC 1.18.2+**，**不支持 OptiFine**。

**怎么用。** 把 `Firmament-v0.2-edit-of-coderbot-Steadfast.zip` 放进 `.minecraft/shaderpacks/`，在 Iris 里选中并 Apply。菜单里 `✎ EDIT默认 style` 是出厂配置（点它即可从其它风格一键回到原样）；`材质（PBR）` 分三个子页放全部材质选项；`特效与后期处理` 分四个子页（光照特效 / 镜头效果 / 色彩与色调 / 【实验性】时间抗锯齿）；`制作与许可` 页有制作人、原作者与材质来源的署名。

**关于许可（重要）。** 本包按 **GNU GPLv3 + Steadfast 附加条款**分发。附加条款要求：任何传播本包的页面都必须**在下载链接之前**给出 coderbot 的声明原文；**名称必须以 `(edit of coderbot's Steadfast)` 结尾**，且 "Steadfast" 不得出现在该括号之外；文件名要带等价后缀。所以本修改版叫 `Firmament - v0.2 (edit of coderbot's Steadfast)`，别改成别的写法。材质部分**借鉴了 Mellow Shader v3.4（TheCMK，MIT 许可）**的做法，用到的都是公开规范里的数学（GGX、Smith、Schlick、Henyey-Greenstein、labPBR），代码在 Steadfast 的风格下重写，未逐字搬运，也未使用其名称/素材。完整说明见 `NOTICE.md`。
