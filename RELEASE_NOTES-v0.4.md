# Release notes - v0.4（开发中 / in development）

> Steadfast is free and open-source software developed by coderbot, and can be
> downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth),
> https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or
> https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and
> distribute it under the terms of the GNU General Public License, version 3.

**Firmament 不是 Steadfast 的官方发行版，coderbot 不为它提供支持。**
许可、署名与来源的完整摘要见 `NOTICE.md`。

**这一版还在开发中。** 下面写的是目前已经落进 v0.4 的内容；正式发行时这里会补全，
和 `RELEASE_NOTES-v0.3.md` 的体例一致。

---

## 水面现在用「这个面自己的切线基」/ The water surface uses the face's own frame

**中文**　水的波面是一张铺在面内的场：它需要知道"沿面往哪个方向是横、哪个方向是竖"，
也就是这个面的切线（tangent）与副切线（bitangent）。在这之前，本包对这件事是**假定**的 ——
平铺的水假定为世界的东/北，竖着的水自己拿世界上方向叉出一个基。在与世界轴对齐的方块面上，这些假定
恰好是对的；在**斜着的面**上（模组的斜坡、斜放的水）就不是了，波纹会铺错方向。

现在，顶点阶段把几何**真正带的**切线取出来（连同手性一起），和法线、材质 ID 编进同一个 32 位整数
（原本空着的 10 个 bit 就是留给它的），片元阶段再解出一个完整的 TBN 基。
没有切线的几何（Minecraft 的实体格式、部分模组）会用一个由该面法线推出来的切线顶上，不会出问题。

**English**　The water's waves are a field that lives in the plane of the face, so they need the
face's own tangent and bitangent to know which way across the face is which. Until now this pack
**assumed** that frame: flat water assumed the world's east and north, and water standing up built
a frame by crossing the world's up axis with its normal. On a block face lined up with the world
those assumptions happen to be right; on a face that is tilted - a mod's slope, water lying at an
angle - they are not, and the waves are laid out the wrong way across it.

The vertex stage now takes the tangent the geometry actually carries - with its handedness - and
packs it with the face normal and the material ID into the same 32-bit value they already shared
(those ten spare bits were reserved for exactly this), and the fragment stage rebuilds a full TBN
matrix from it. Geometry that carries no tangent at all, which is Minecraft's entity format and
some mods, is given one derived from its face normal rather than failing.

## 可能看不出变化，这是有意的 / You may not see a difference, and that is expected

**中文**　在与世界轴对齐的方块面上（也就是水几乎总是出现的地方），新旧两套基只差各轴的符号，
而符号只影响噪声场的镜像，不影响它的滚动；视差与抗锯齿所用的世界空间导数本来就只喂给抗锯齿强度，
不参与波面朝向。所以这一版的可见差别主要集中在**非轴对齐的面**与**侧面波纹的走向**上。
平铺的水面走的是原来那条路径，一个字节都没改。

**English**　On a block face lined up with the world - which is where water almost always is - the
new frame and the old assumption differ only in the sign of each axis, and a sign only mirrors the
noise field without changing which way it scrolls. The world-space derivatives the parallax and the
antialiasing use feed the antialiasing strength alone and never the waves' direction. So what you
can see is confined to faces that are not lined up with the world, and to which way the waves run
across a side. Water lying flat takes the same path it always did, unchanged.

## 没有动的东西 / What this did not touch

**中文**　水的颜色、吸收、散射、反射强度与透明度全部保持原样；材质（labPBR）的法线、视差与自阴影
这条路径也完全没有改。

**English**　Water's colour, absorption, scattering, reflection strength and transparency are all
exactly as they were, and the material path - labPBR normal maps, parallax and self-shadowing - is
untouched.

---

## 视差：一条轴读不出来的面不再整片放弃 / Faces whose mapping could not be read no longer lose their parallax whole

**中文**　视差位移要换算成纹理坐标，靠的是"一个单位的 u/v 在世界空间里有多长"这两个量，它们由屏幕
空间导数解出。有些面（取决于它们的贴图怎么摆，所以看着就是"某些侧面"）其中一条轴会几乎被压扁：
这条轴算出来不是短，而是**不可信**。以前遇到这种情况会**把两条轴一起丢掉**——于是这个面完全没有视差，
看上去就是平的。现在只丢掉出问题的那一条：另一条照旧描述这个表面，于是这个面**仍有一个方向上的深度**，
而且不会像更早的版本那样"看穿一层"（那是位移被放大导致的）。两条轴都正常的面对本版完全无感。

**English**　A parallax displacement is converted into texture coordinates from two quantities: how
far one unit of u and of v reaches across the world, both solved out of the screen-space derivatives.
On some faces - which ones depends on how their texture happens to be laid out, which is why it shows
up as particular sides of a block - one of those axes comes out not merely short but **untrustworthy**.
That used to throw both axes away, and the face then had no parallax at all and read as flat. Only the
axis that failed is dropped now: the other one still describes the surface, so the face keeps depth
along one direction instead - and it no longer overshoots the way it did before the guard existed,
which is what made those faces look as if you could see one layer through them. A face with both axes
intact is completely unaffected by this version.

---

## 水散射 / Water scattering

**中文**　吸收只能把光**拿走** —— 它给水那份深蓝绿，但做不出"被照亮的水体在发光"。散射是光从水里
**加回来**的那一半：光在水中的颗粒上折返，而不是从水底反射回来。本版把它加在**折射背景**那一步之后，
所以它作用在"透过水面看到的水体"上。

三个新选项都在 **`水`** 页：`水体散射强度`、`水体散射倍率`、`水体散射亮度`。
**默认全为 0**，此时加进去的项**精确等于零** —— 没调过它的包渲染出来的水和以前**一模一样**。
想要效果请自己调起来（建议先试 `散射强度 0.25` + `散射亮度 0.50`）。

**一处限制**：Voxy 的远景水**没有**散射。Voxy 的着色器补丁由模组自己喂 uniform，
而散射需要用到一个补丁名单里没有的值，所以整块代码在补丁里被跳过——与包内既有的几处同因同法。

**English**　Absorption can only take light **away**: it gives water its deep blue-green, but it
cannot make a lit body of water glow. Scattering is the half that puts light back - off the water's
own particles rather than off its floor. It is added where the refracted background is read, so it
lands on water seen through a surface.

Three new options, all on the **Water** page: scattering, its magnitude, and its brightness. **All
three default to zero**, and at zero the term they add is exactly zero - a pack that has never
touched them renders the water it always did. Raise them to see it (start at 0.25 and 0.50).

**One limitation**: Voxy's distant water has no scattering. Voxy's shader patch is handed its
uniforms by the mod, and scattering needs one that is not on that list, so the whole of it is skipped
there - the same cause and the same treatment as a few already in the pack.

---

## 修复：远处的水不再被"水底的阴影"压暗 / Fixed: distant water is no longer darkened by its own bottom

**中文**　屏幕空间阴影（给阴影贴图够不到的远景补的那层阴影）原本把**不透明深度**当成了被照的表面。
可水面不在不透明通道里——它是半透明画出来的——所以在水面像素上，那个深度属于**水后面的地形**。
结果是：为**水底**算出来的阴影被乘到了**水面**的颜色上，而它只在阴影距离之外生效，
看起来就是**远处（Voxy 区块）的水明显比近处的水暗**。

现在被照的表面取自**含半透明的深度**，遮挡它的仍然是**不透明世界**（水自己不该参与遮挡）。
在没有半透明挡在镜头前的像素上这两个深度完全相同，所以**陆地的一切都和之前一模一样**，
只有"你正在看的那层表面是水或冰"的像素会变。

**English**　The screen-space shadows - the layer that stands in for the shadow map past its reach -
were casting onto the **opaque** depth. Water is not in the opaque pass, so at a water pixel that
depth belongs to whatever stands **behind** the water: the shadow worked out for the water's own
bottom was being multiplied into the water's colour, and only past the shadow map's reach, which is
why water on LOD terrain looked darker than the same water nearby.

The surface being shadowed now comes from the depth buffer that **includes translucents**, and its
occluders still come from the opaque world - water should not occlude itself. Those two depths are
identical wherever nothing translucent is in front, so **everything on land is exactly as it was**;
only pixels whose visible surface is water or ice change.

---

## 修复：远处 LOD 水面的颜色 / Fixed: water on LOD terrain

**中文**　水色来自"折射辅助吸收"，它用一个**天光缓冲**去反推水的厚度：缓冲越暗，就认为水越深、
吸收越多。Voxy 的着色器补丁是由模组自己喂 uniform 与贴图的，而那个天光缓冲**不在名单里**，
于是读出来是空的 —— 空 = 天光为零 = 这套启发式能描述的最深的水。结果就是 LOD 上的水一律按**满水深**
上色，比近处的水暗；近处的水读的是真缓冲，水浅、亮。现在在拿不到缓冲的程序里，改用**该像素自身的天光**
顶上（`diffuse.glsl` 对水下吸收用的就是同一个式子），于是两边对上了。

**English**　Water's colour comes from a heuristic that infers the water's thickness from a sky light
buffer: the darker the buffer, the deeper the water is taken to be, and the more light is absorbed.
Voxy's shader patch is handed its uniforms and textures by the mod, and that buffer is not among them,
so reading it returned nothing - and nothing is a sky light of zero, which is the deepest water the
heuristic can describe. LOD water was therefore shaded at full absorption, darker than the water
beside it, while water inside the render distance read the real buffer and stayed shallow. Programs
that are not given that buffer now use the sky light on the fragment's own surface instead - the same
substitution the underwater absorption already makes - and the two now agree.

---

## 修复：屏幕空间阴影的条纹 / Fixed: the stripes in the screen-space shadows

**中文**　屏幕空间阴影原来在**视图空间里按固定距离推进**，每走一步再投影到屏幕上。这在太阳高的时候没问题，
但太阳一低，射线几乎与屏幕平面平行 —— 一步要跨过很多像素，于是**采样点之间拉开缝隙**，
阴影碎成**从太阳方向放射的条纹**（水面上的变暗正是这个条纹，不是整片均匀变暗）。

现在照 **Sundial Lite** 的做法：把射线的**起点与终点都投影到屏幕**，在这两个位置之间**均匀地走**，
所以无论太阳多低，相邻采样点之间始终隔着相同的像素数。遮挡判据也换成 Sundial 那种
**按距离成比例的厚度窗口**（在深度缓冲自己的单位里量，而不是按方块数），
并且**一次遮挡只压暗一档**而不是一票否决 —— 单次命中读起来是轻阴影而不是黑色条纹，
整条射线都撞上实体时才真正变暗。每像素逐帧的抖动保留，时间抗锯齿仍然有东西可平均。

**English**　The screen-space shadows used to advance a fixed distance in **view space** and project
each step. That is fine with a high sun, but when the sun is low the ray runs nearly parallel to the
screen plane: one step then crosses many pixels, the samples open gaps between each other, and the
shadow breaks up into **stripes radiating from the sun**. The darkening seen on water was that same
striping rather than a uniform darkening.

They now follow **Sundial Lite** for the stepping: the ray's start and its end are both projected to
the screen, and it is walked **evenly between those two positions**, so the samples are always the
same number of pixels apart whatever the sun's angle. What the shadow is, in the end, is the
**fraction of the ray the depth buffer says is blocked** - how much of the way to the sun something
stands in. The per-pixel, per-frame dither is unchanged, so the temporal filter still has something
to average.

**Why a fraction and not a running darkening**: an earlier attempt took a fixed amount off the light
for every sample that came back blocked. That made the result depend on the step count itself, which
is not a thing the step count should ever change: raising it darkened the whole distance further even
where nothing had changed, because whatever the test wrongly counts as an occluder gets more chances
the more samples are taken. It was found by lowering the step count from the driver's seat until the
darkening went away, which is the one setting a shadow should never answer to.

**One thing that is deliberately not Sundial's**: Sundial measures how thick the thing the ray met is
allowed to be in *its own* packed depth, as a fraction of the distance. That does not carry over to
this pack's depth buffer, whose units are not linear in distance - out at the range this works over,
the whole distant world sits in the last thousandth of the range, so a window expressed in those units
stops telling anything apart from anything else. Trying it marked nearly every sample as blocked and
turned the entire distance black. The thickness here is measured in blocks, in view space, where it
means the same thing at every distance.

---

## 修复：雷雨天里突然发白的天空 / Fixed: the sky that went white in a thunderstorm

**中文**　游戏把它的星空画成一批**平色的四边形**，本包用一个"这个颜色是不是平色"的判断来认它们。
问题在于，**游戏自己的天空底色四边形也是平色** —— 只要它三个通道**恰好相等**就会被误判。
而雨天正好会把天空底色一路去饱和到那个等号上：在那几秒里，整个天穹走进"星星"那一支，
被填成**纯白** —— 云是在这之后画的，所以白里还看得到云；地平线那一圈是另一块四边形，所以保持原样。
这正是"雷雨天月亮刚出来时天空发白"的成因。那一支已经删掉。

**English**　The game draws its star field as flat-coloured quads, and the pack recognized them with a
test that asked whether a colour was flat. The game's own sky colour quad is flat too, whenever all
three of its channels come out equal - and rain desaturates the sky colour until they do. For the few
seconds the colour sat on that equality the whole dome took the star branch and was filled with pure
white, with the clouds still drawn over it afterwards and the horizon band, which is its own quad,
left alone. That branch is gone.

## 新做了一套星空 / A star field is generated instead

**中文**　旧的星星随那一支一起没了，所以这套是**重新生成**的：在视线方向上铺一层格子，
**大多数格子是空的**，有星星的格子各自带亮度与色温，画成一个**收紧的核心**而不是一个圆盘。
它**随夜色渐入**而不是在天黑时打开，**被雨盖住**（与天空对天气的态度一致），并在地平线以下淡出。
四个选项：星空开关、星光亮度、网格密度、星星大小。（游戏自己那套星空**删不掉** —— 它到了片元着色器里
与太阳月亮**完全同源**，没有任何特征能区分，而太阳月亮必须画 —— 所以它还在，亮度与以往一致。）

**English**　The old stars went with that branch, so these are generated: a grid is laid over the view
direction, most cells are empty, and each cell that is not carries its own brightness and colour and is
drawn as a tight core rather than a disc. It fades in with the night rather than switching on at it, it
is covered by rain exactly as the sky is, and it fades out below the horizon. Four options: the field
on or off, its brightness, its resolution and the size of a star. (The game's own star field could not
be removed - by the time it reaches a fragment shader there is nothing to tell it from the sun and the
moon, which arrive through the same program and do need to be drawn - so it is still there, at the
brightness it always had.)

## 水里映出了太阳和月亮 / The sun and the moon are reflected in water

**中文**　本包生成的天空**只有大气**：天上那两个圆盘是游戏当贴图画上去的。所以"反射天空"反射的是
**没有东西立在里面**的空气 —— 水面映不出太阳，夜里也没有那条月光带。现在两个圆盘都补进了反射：
尺寸按游戏画日月的大小、暖色与冷色各一、**月亮只有太阳的五十分之一**，各自在自己落下与升起时淡出，
雨天被盖住。**只作用于水** —— 玻璃与冰保留天空反射和自己的菲涅尔项（窗上贴一个日斑会像**破了个洞**，
因为窗是被看穿的多于被反射的）。另有两项保证它对得上：倒影用的两个方向取在**同一个空间**里
（游戏画太阳用的那个），所以**走动时不会随视角摇晃而偏移**；而水面的视差映射现在**在原版视距处收口**，
免得与另一个渲染器的水（Voxy / DH）交界处跳一下。

**English**　The sky this pack generates is atmosphere only: the two discs up there are sprites the game
draws. So a reflection of the sky was a reflection of the air with nothing standing in it - no sun on
the water and no path of moonlight across it, however clear the night. Both discs are added to the
reflection now: sized to match the game's own sun and moon, one warm and one cool, **the moon worth a
fiftieth of the sun**, each fading as its body sets and rises and both covered by rain. **Water only** -
glass and ice keep the sky reflection and their own Fresnel term, because a disc of sunlight on a
window reads as a hole in it, a window being seen through as much as reflected in. Two further things
keep it lined up: the two directions are compared in the **same space** the game draws the sun in, so
the reflection does not sway with the view bob, and parallax mapping on water now **stops at the edge
of the vanilla render distance**, so it no longer steps where this pack's water meets another
renderer's.

## 修复：屏幕空间阴影的方向是反的 / Fixed: the screen-space shadows were inverted

**中文**　遮挡判据把"**比射线更靠后**的表面"也算成了遮挡物 —— 那正是阴影的反面。
这一处改过来之后，原本存在的远景阴影问题一次性消失。同时：结果是**被挡住的射线占全程的比例**
（不随步数变化），新增**阴影强度**选项，日月交接改为在地平线两侧各 2° 内**淡出**而不是切换。

**English**　The occlusion test counted a surface **behind** the ray as an occluder, which is the
opposite of a shadow. Changing that one comparison is what made the distant shadows work. With it: the
result is the **fraction of the ray that was blocked**, so it does not change with the step count;
**strength** is an option; and the handover between the sun and the moon fades over two degrees either
side of the horizon instead of switching.

## 云：受光不再依赖方向 / The cloud layer's lighting no longer depends on direction

**中文**　层的受光原来含**相位**与**透射**两项，它们随光的方向变化；而日月交接时方向会变，
于是那几个时间点（约 12782 与 23218）云会跳。现在这两项按**常数**乘进去，跳变随之消失；
两者加上"由层底向上的受光衰减"都做成了选项，观感可以直接调。

**English**　The layer's lighting carried a phase and a transmittance term, both of which vary with the
direction of the light - and that direction changes hands when the sun and the moon cross. That is what
made the clouds jump at those points in the day (around 12782 and 23218). Both terms are now applied as
constants, and the jumps went with them. The two of them, plus the falloff towards the base of the
layer, are options.

## 菜单 / The settings menu

**中文**　整个菜单**重排成两级**：每个选项都归到它所属主题的子页下（水、大气与云、光照、材质、开发），
**一个都没有丢**。另外：**默认配置的名字在英文菜单里显示中文**这个老问题修好了（两种语言下都是
"EDIT default"）；那些"值很多但点一下跳一档"的选项恢复成**滑块**（原因是它没写进 `sliders=`，不是选项本身）。

**English**　The menu is **reorganised into two levels**: every option now lives on a sub-page of the
theme it belongs to - water, atmosphere and clouds, lighting, materials, development - and none was
lost in the move. Two older problems went with it: the shipped profile **no longer shows Chinese in an
English menu** (it is "EDIT default" in both), and options that had several values but rendered as
click-to-cycle are **sliders** again (the cause was a missing `sliders=` entry, not the options).

## 默认值 / The defaults

**中文**　本包现在按这个修改版调校好的一套值出厂。

**English**　The pack now ships with the values this edit is tuned to.

| 选项 / Option | 原 / Was | 现 / Now |
|---|---|---|
| 云受光亮度（相位常数）/ Cloud phase | 0.60 | **0.25** |
| 阴影扭曲系数 / Shadow distortion factor | 0.05 | **0.20** |
| 星光亮度 / Star brightness | 2.0 | **5.0** |
| 星星数量占比 / Star density | 0.05 | **0.08** |
| 日月倒影大小 / Reflected body size | 0.985 | **0.995** |
| 日月倒影亮度 / Reflected body brightness | 8.0 | **4.0** |
| 水体散射亮度 / Water scattering luminance | 0.00 | **0.50** |

## 试过又拿掉的 / Tried and taken back out

**中文**　**云隙光柱（丁达尔）**：本包的 godrays 是屏幕空间的一趟，它**只在地形挡出轮廓的地方**才亮
（所以透过树叶最明显），并**不会铺满开阔的天空**。把云加进那个缓冲，因此做不到"整片天都有光柱" ——
要真做得另起一套体光。这个尝试已整条撤回。

**English**　**Shafts of light through the clouds.** This pack's godrays are a screen-space pass that
lights a pixel only where the depth buffer says geometry is in the way, so they appear through foliage
and not across open sky. Adding the clouds to that buffer therefore could not put shafts across the
sky; doing it properly needs a second volumetric pass. The attempt was reverted whole.

## 清理 / Housekeeping

**中文**　删除无用代码：云失去方向依赖后遗留的一个相位函数、喂给旧星星那一支的 varying、以及一条
没有任何着色器读取的 uniform。`PBR_PORTING.md` 记录了上列每一处改动（**包括被撤回的那些及其原因**）。

**English**　Dead code removed: a phase function left behind when the clouds lost their
direction-dependent term, the varying that fed the old star branch, and a uniform no shader read.
`PBR_PORTING.md` records the work behind each change above, **including the ones that were reverted
and why**.
