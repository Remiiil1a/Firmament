# Notices and licensing

**Firmament (edit of coderbot's Steadfast)**, for Minecraft: Java Edition.

This file is the short version of where this pack comes from and what its
licences allow. Read it before redistributing the pack or anything built from
it. The full licence texts are in the files listed at the bottom.

---

## 1. Steadfast, by coderbot (the original work)

This pack is a **modified version** of Steadfast 0.8.0. The modifications were
made by Remiiil1a, dated 2026-09-13 and 2026-09-14; what they consist of is
listed in section 4 and documented in `PBR_PORTING.md` in the project this was
built in. The per-file notices in the source name the version each file was
**first** modified for - further changes to those files are recorded in
`RELEASE_NOTES-v0.3.md` rather than being written back into the notices.

Steadfast's additional terms (permitted by section 7 of the GPLv3) require the
following notice to appear prominently, and as early as possible, on any page or
message that conveys Steadfast or a modified version of it - before any download
link:

> Steadfast is free and open-source software developed by coderbot, and can be downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth), https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and distribute it under the terms of the GNU General Public License, version 3.

Those same terms also require, for any modified version:

* that its **human readable name end with `(edit of coderbot's Steadfast)`** -
  hence `Firmament (edit of coderbot's Steadfast)`, and hence the
  `(edit of coderbot's Steadfast)` in the string `FIRMAMENT` in
  `shaders/lang/*.lang` and `shaders/environment/lighting/diffuse.glsl`. Do not
  shorten it: the name "Steadfast" may not appear in the name or branding of a
  modified version anywhere else;
* that the **file name include the same thing**, for which the terms suggest the
  suffix `-edit-of-coderbot-Steadfast` - hence
  `Firmament-v0.6-edit-of-coderbot-Steadfast.zip`;
* that the GPL and those terms are kept, and that nothing suggests this is an
  official Steadfast release. **It is not.** coderbot does not support it, and
  bug reports about it do not belong in Steadfast's issue tracker.

Steadfast itself is Copyright (C) 2026 coderbot, licensed under the GNU General
Public License version 3 or later, with the additional terms above. There is
**no warranty**, as set out in the GPL.

## 2. Other shaders this pack references

Besides Steadfast, two projects are referenced or quoted from in the code. Both
are credited in the pack's own menu, on a **Special thanks** page under
`Credits & licence` (the `SPECIAL_THANKS` page in `shaders/lang/*.lang`, one
entry per project). That credit is deliberately
**not split up by feature**: it states plainly that this pack references or
quotes code from the projects named in it.

* **Mellow Shader v3.4, by TheCMK** - the temporal antialiasing follows that
  pack's implementation, both its weighting of the history by how far the pixel
  moved and its Catmull-Rom fetch of the history, and the material model follows
  its approach. The material mathematics is from published specifications - the
  GGX distribution, the Smith correlated visibility term, Schlick Fresnel, the
  Henyey-Greenstein phase function, and the labPBR 1.3 channel layout (see the
  shaderLABS LabPBR Material Standard) - but the approach is theirs. Mellow
  Shader is Copyright (c) 2026 TheCMK, licensed under the **MIT License**; a
  verbatim copy is included as `LICENSE-MELLOW-MIT.txt`, and
  `LICENSE-MELLOW-APACHE.txt` from that pack is included as well, because its
  own files ask for the whole licence set to be kept together.
* **Sundial Lite, by geforcelegend** - the screen-space shadows used past the
  shadow map's reach follow that pack's implementation: the ray is walked in
  **screen space**, projected from its start and its end and stepped evenly
  between those two positions rather than a fixed number of blocks in view
  space, its first sample is dithered both per pixel and per frame, and an
  occlusion only counts when it falls within a thickness window of the ray -
  which is itself measured as a fraction of the distance, in the depth buffer's
  own units, as Sundial measures it. Sundial Lite is licensed under the **GNU
  General Public License, version 3** - the same licence as this pack, whose copy
  is `LICENSE.md` - so no separate licence file is included for it.
* **No assets are reused from either.** No textures, no logos, no screenshots,
  and neither project's name is part of this pack's name or branding.

## 3. What this means in practice

* You may modify and redistribute this pack under the **GPLv3**, as long as you
  keep the notices, keep the required name ending, and do not present it as an
  official Steadfast release.
* If you build on any of this, the credits have to travel with it: the Steadfast
  notice quoted in section 1, and the **Special thanks** entries described in
  section 2.
* If you convey this pack anywhere public - a page, a download, a video with a
  download link - the paragraph quoted in section 1 has to appear early on that
  page, before the download link.

## 4. What this edit changes, relative to Steadfast 0.8.0

Versions are counted as: **v0.1** is the material work, **v0.2** is everything
from the cloud layer onward, and **v0.3** is the distant-terrain, temporal
antialiasing and water work after it, **v0.4** is the sky, the reflected sun and
moon, and the settings work after it, **v0.5** is the work after that, and
**v0.6** is bloom, volumetric fog, the rain and snow particles and the sun and
moon's own images. What each release changed is listed in `CHANGELOG.md` in the
short form, and in the `RELEASE_NOTES-*.md` files in full.

**Added in v0.1**

* labPBR 1.3 material support: normal maps, specular/metal maps, material
  ambient occlusion, subsurface scattering, porosity/wetness, and emissive
  maps, with a debug view for each channel.
* Reflections: a sky term per material, plus optional screen-space reflections
  of the world, computed in the deferred pass.
* The End: its own light, void glow and haze, and a debug view for the checks
  that detect the dimension.
* Tangent frames taken from the geometry's own tangents (`at_tangent`) rather
  than reconstructed from depth, which fixes normal maps flipping at distance.

**Added in v0.2**

* A cloud layer of cube-shaped cells, drawn in place of Minecraft's flat cloud
  boxes, following the pack's weather slowly and drifting with the same wind the
  planar clouds use. Overworld only; it does not cast a shadow on the ground.
* Motion blur along the camera's own travel, with the walk bob left out of it on
  purpose and a blur amount and sample count to tune. Off by default.
* Sun and moon size: their highlights carry the sun's real angular size rather
  than being a single pixel.
* The settings menu's effects page split into sub-pages, with the unfinished
  temporal anti-aliasing marked as experimental.

**Fixed in v0.2**

* The cloud layer stays out of the Nether, and a cloud's own shading is
  hard-edged again.
* Reflections on glass and calm water no longer shiver with the walk bob.
* A held item no longer shows the world through itself, because the hand is no
  longer given an environment reflection at all.
* The sun's highlight was widened in the wrong units and barely changed; it now
  spreads the way half a degree of sunlight should.

**Added in v0.3**

* Screen-space shadows for terrain past the shadow map's reach, handed over at
  the smaller of the shadow distance and the view distance.
* Temporal antialiasing on by default, its history weighted by motion and
  filtered with Catmull-Rom; the pack's own noise moves every frame so that
  there is something for it to average.
* Water that is not lying flat - the sides of waterfalls - drawn as water, with
  its own surface, colour and roughness-filtered reflection.
* The Voxy shader patch fixed: `voxy.json` was written in an older format.

**Added in v0.4**

* The water surface is laid out in the frame the face actually has, taken from
  the geometry's own tangent, instead of one assumed from the world's axes.
  Nothing about the water's colour, absorption, scattering or reflection
  changed; on faces lined up with the world there is no visible difference, and
  the difference is on the ones that are not.
* Water scattering, as three options on the water page. All off by default.
* A star field the pack generates for itself, with its brightness, resolution,
  density and star size to set. It fades in with the night and is covered by
  rain. The game's own star field is still drawn and is unchanged.
* The sun and the moon reflected in water: sized to match the game's own, the
  moon worth a fiftieth of the sun, and water only - glass and ice keep the sky
  reflection and their own Fresnel term.
* Screen-space shadow strength, and a handover between the sun and the moon that
  fades over two degrees either side of the horizon rather than switching.
* The cloud layer's phase, transmittance and height falloff as options.
* A settings menu reorganised into two levels, with every option reachable and
  the shipped profile named the same in both languages.

**Added in v0.5**

* A screen vignette, **on by default**: the corners of the frame lose a little
  of their light. It is applied to the linear light and before the tonemap,
  rather than to the finished image, so that the corners go dark instead of flat.
  Its strength, and where the falloff starts and where it completes, are options.
* Colored shadows: sunlight that has come through stained glass lands on the
  ground in the colour of the pane rather than as a hole in the light, and a
  nether portal tints the light around it with its own glow. How much colour the
  light takes on is an option, and the portal's glow can be switched off on its
  own.
* Volumetric light: the light shafts are drawn **under water** as well as in air,
  along the same light axis, and their strength is a setting - with a multiplier
  of its own for the underwater ones - where before there was no strength setting
  at all.
* Enchantment glint brightness: how bright the sparkle on an enchanted item or a
  piece of armour is drawn.
* Scattering inside the cloud layer, with the number of passes and how much each
  one attenuates as options.
* Reflection settings: a metal reflection strength, the smoothness a surface
  needs before it reflects at all, how far a rough surface's reflection is
  gathered, and a debug view that shows the reflection on its own.
* Smooth parallax: whether the height channel is interpolated across a texel
  rather than sampled at its centre.
* The star field is reflected in water, alongside the sun and the moon.

**Removed in v0.5**

* Water scattering, which v0.4 added: its options and the code behind them are
  gone. The water's absorption, colour and reflection are unchanged.

**Added in v0.6**

* Bloom, with its strength, the brightness it starts at and the radius of the
  spill as options, and the specular highlight of a surface left out of it by
  default.
* Volumetric fog: the air marched through as a medium rather than tinted over the
  frame, at a quarter of the frame's resolution and lit by the shadow map, with a
  world-locked noise medium that drifts with the wind. Density, height, base,
  distance, march steps, the noise and a full-resolution switch are options, and
  rain thickens it.
* Rain and snow particle options: how many times the texture is tiled across a
  rain column, how much of each drop's width is kept, and the particle's colour
  saturation.
* The sun and the moon are reflected from the game's own images - `sun.png` and
  the eight lunar phases, carried by the pack - with a size trim for each body
  and the tilt of their orbit as options.

**Changed in v0.6**

* Temporal antialiasing is off by default and marked experimental.
* The shipped defaults were retuned.

**Fixed in v0.4**

* A sky that turned solid white for a few seconds in a thunderstorm. The test
  that recognizes the game's star quads also matched the game's own sky colour
  quad whenever all three of its channels came out equal, which is what rain
  drives the sky colour to.
* Screen-space shadows counted a surface behind the ray as an occluder, which is
  the opposite of a shadow; they also changed with the step count.
* Parallax mapping on water now stops at the edge of the vanilla render
  distance, so it no longer steps where this pack's water meets a distant
  terrain renderer's.
* The cloud layer no longer jumps when the sun and the moon change hands, which
  it used to do through the phase and the transmittance.
* The shipped profile no longer shows Chinese in an English menu.
* Options that had several values but rendered as click-to-cycle are sliders
  again.

## 5. Files

| File | What it is |
|---|---|
| `LICENSE.md` | GNU GPL version 3 - Steadfast's licence, unchanged |
| `LICENSE-ADDITIONAL-TERMS.md` | Steadfast's additional terms under GPLv3 section 7, unchanged. **Read this one.** |
| `LICENSE-MELLOW-MIT.txt` | MIT License, Copyright (c) 2026 TheCMK - verbatim copy from Mellow Shader v3.4 |
| `LICENSE-MELLOW-APACHE.txt` | Apache License 2.0 - verbatim copy from Mellow Shader v3.4 |
| `README.md` | What the pack is, what it adds, what it costs |
| `README.zh-CN.md` | The same, in Simplified Chinese |
| `CHANGELOG.md` | What changed in each release, in the short form |
| `CHANGELOG.zh-CN.md` | The same, in Simplified Chinese |
Two further things are **not shipped inside the pack**. They are kept with the
project the pack is built in:

* `RELEASE_NOTES-*.md` - what changed in each release, one file per version.
* `PBR_PORTING.md` - the working notes behind every change this edit makes:
  options, verification checklist, known limits, and the changes that were tried
  and then reverted, with the reason.

The comments in the shaders that point at one of `PBR_PORTING.md`'s sections are
pointing at that copy.

If a distributor removes any of the files in this list, the result is not
distributable.
