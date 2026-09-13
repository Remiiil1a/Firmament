# Firmament - v0.1 (edit of coderbot's Steadfast)

Steadfast is free and open-source software developed by coderbot, and can be downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth), https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and distribute it under the terms of the GNU General Public License, version 3.

**Firmament** is an edit of **Steadfast 0.8.0**. It keeps Steadfast's look,
structure and performance tiers, and adds material (PBR) support and support for
the End. It is version 0.1 - an early, unfinished edit, not an official
Steadfast release, and not supported by coderbot.

> **On the name:** Steadfast's additional licence terms require the name of a
> modified version to end with `(edit of coderbot's Steadfast)`, and forbid the
> name "Steadfast" anywhere else in it. So this edit is called
> `Firmament - v0.1 (edit of coderbot's Steadfast)`, and the file it is
> distributed as is named `Firmament-v0.1-edit-of-coderbot-Steadfast.zip`. That
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
  shader gets. If something looks wrong, treat that as expected for v0.1 rather
  than as surprising.

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
  the previous frame; a ray that misses falls back to the sky.
* Stained glass and glass panes get specular reflections as well.

### The End

Steadfast has no real support for the End; this edit gives it some:

* The End's own light, so its islands are not lit by the ambient floor alone.
* A **void glow** from below, so the islands do not read as flat cutouts.
* **End haze**, so islands fade into space rather than into a grey cave wall.
* A debug view for the checks that decide whether the current dimension is the
  End, since not every Iris version provides every uniform.

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

This is v0.1. These are the parts that are known to be incomplete:

* **TAA is unfinished and is off.** Steadfast ships a temporal anti-aliasing
  path whose options exist in the menu, but this edit leaves it off exactly as
  upstream does. It has no motion vectors, so anything that moves relative to
  the world (mobs, water, particles, the held item) cannot be reprojected and
  has to be handled by rejecting history instead of tracking it. Its four
  options do nothing until TAA itself is switched on, and it should be treated
  as experimental.
* **Parallax occlusion mapping is unfinished, and off by default.** It works,
  but it has not been tuned against enough resource packs, and at distance it
  can shimmer. The depth, step count and maximum offset are all exposed if you
  want to experiment.
* **Reflections are screen-space only.** They cannot see behind you, they use
  the previous frame's colours, and a rough surface gets a single sample rather
  than a blur, so very rough reflective materials can look grainy.
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
* **Nothing here is exhaustively tested.** The edit was developed without the
  ability to run the game in the development environment, so verification was
  done in game by one person on one machine. There are no benchmarks for other
  GPU vendors.
* **Inherited from upstream:** Steadfast requires Iris (1.5+, Minecraft 1.18.2+)
  and does **not** support OptiFine, and it does not support the Nether or End
  to the same standard as the Overworld - which is exactly what the End work
  here is a partial answer to.

## Installation

1. Put `Firmament-v0.1-edit-of-coderbot-Steadfast.zip` into
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

* `✎ EDIT默认 style` (profile) - the configuration this edit ships with: Steadfast's
  own look, with the material options at their tuned values. Selecting it after
  trying one of Steadfast's styles puts the original look back.
* **Materials (PBR)** - format switch, debug view, and three sub-pages:
  material maps and detail, surface response and reflections, coverage.
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
* **末地维度**：末地自身的光照、虚空辉光、末地雾，以及一个判断维度的调试视图。
* **切线基修复**：材质切线改用几何体自带的切线（`at_tangent`），修掉了此前"特定距离法线翻转"的问题。

**性能：比原版更吃配置。** 两个原因：每个受光表面要多写两张材质缓冲（约每像素 12 字节带宽）；SSR 要在每个通过粗糙度上限的像素上走最多 12 步。掉帧时按这个顺序关：**屏幕空间反射 → 天空反射 → 把 SSR 步数降到 8 / 把粗糙度上限收到 0.1 → 关视差 → 降档位、降阴影分辨率与距离**。

**还不完善的地方（v0.1）。** TAA **未完成、默认关闭**（没有运动矢量，菜单里那四项要等你手动打开 TAA 才生效）；视差 **未完成、默认关闭**；反射只能反射屏幕内的东西、只取上一帧、粗糙面没有模糊；屋檐下与玻璃窗附近可能出现奇怪的天空反射（天光会横向渗透，这是"能看见天空"与"天光很亮"不等价导致的）；实体材质是实验项；只在单机单人环境下验证过，没有做不同显卡的测试。需要 **Iris 1.5+ / MC 1.18.2+**，**不支持 OptiFine**。

**怎么用。** 把 `Firmament-v0.1-edit-of-coderbot-Steadfast.zip` 放进 `.minecraft/shaderpacks/`，在 Iris 里选中并 Apply。菜单里 `✎ EDIT默认 style` 是出厂配置（点它即可从其它风格一键回到原样），`材质（PBR）` 分三个子页放全部材质选项，`制作与许可` 页有制作人、原作者与材质来源的署名。

**关于许可（重要）。** 本包按 **GNU GPLv3 + Steadfast 附加条款**分发。附加条款要求：任何传播本包的页面都必须**在下载链接之前**给出 coderbot 的声明原文；**名称必须以 `(edit of coderbot's Steadfast)` 结尾**，且 "Steadfast" 不得出现在该括号之外；文件名要带等价后缀。所以本修改版叫 `Firmament - v0.1 (edit of coderbot's Steadfast)`，别改成别的写法。材质部分**借鉴了 Mellow Shader v3.4（TheCMK，MIT 许可）**的做法，用到的都是公开规范里的数学（GGX、Smith、Schlick、Henyey-Greenstein、labPBR），代码在 Steadfast 的风格下重写，未逐字搬运，也未使用其名称/素材。完整说明见 `NOTICE.md`。
