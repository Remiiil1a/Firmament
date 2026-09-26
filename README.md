# Firmament (edit of coderbot's Steadfast)

English | [简体中文](README.zh-CN.md)

A shaderpack for **Minecraft: Java Edition**, built for **Iris + Sodium**. It is
an edit of [Steadfast](https://github.com/coderbot16/Steadfast) by coderbot, and
takes its name from that: Steadfast's additional terms require a modified version
to end with `(edit of coderbot's Steadfast)`.

## Steadfast, and where to get it

> Steadfast is free and open-source software developed by coderbot, and can be
> downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth),
> https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or
> https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and
> distribute it under the terms of the GNU General Public License, version 3.

**This is not an official Steadfast release and coderbot does not support it.**
Bug reports about it do not belong in Steadfast's issue tracker.

## What this edit adds

* **Materials (PBR)** - normal, specular, parallax, subsurface and emissive maps
  from a labPBR resource pack, with reflections and self-shadowing. Parallax has a
  smoothing option of its own, and the displacement is held inside the sprite the
  fragment came from rather than wrapped round to the far side of it.
* **Colored shadows** - sunlight that has come through stained glass lands on the
  ground in the colour of the pane, and a nether portal tints the light around it
  with its own glow. How much colour the light takes on is a setting, and the
  portal's glow can be switched off on its own.
* **Volumetric light, above and below the waterline** - the light shafts are drawn
  under water as well, running along the same light axis as the ones above it, and
  brightened where the ripples on the surface gather them. Their strength is a
  setting, and the underwater shafts have a multiplier of their own on top of it.
* **Enchantment glint brightness** - the sparkle on an enchanted item or a piece
  of armour can be made brighter. The game adds the glint's own colour to the
  frame, so the light it contributes grows with the square of the setting: at the
  shipped value of 2.0 it contributes four times what it did.
* **Distant terrain** - screen-space shadows for terrain past the shadow map's
  reach, which is what Distant Horizons and Voxy terrain otherwise never gets.
* **Water that is not flat on the ground** - the sides of waterfalls and of water
  running downhill are drawn as water, with the same surface, colour and
  reflections as a still surface, laid out in the frame the face actually has
  rather than one assumed from the world's axes.
* **Reflections** - a sky term per material, plus optional screen-space
  reflections of the world. A rough surface's reflection is gathered over the
  cone its own roughness opens - two rings of four directions - rather than taken
  in one direction and called the answer, and the sky it reflects is gathered
  over the same cone. A metal reflection strength, the smoothness a surface needs
  before it reflects at all, how far that gathering spreads, and a debug view that
  shows the reflection on its own are all options.
* **Bloom** - anything brighter than the display can hold spills a glow around
  itself. The specular highlight of a surface is left out of it by default: a
  highlight is a picture of a light rather than a light.
* **Volumetric fog** - the air marched through as a medium rather than tinted over
  the frame, at a quarter of the frame's resolution and lit by the shadow map, so
  the shafts through a canopy are cast by it. The medium is a world-locked noise
  drifting with the same wind the clouds use, so it never slides with the camera,
  and rain thickens it.
* **Rain and snow particles** - the rain texture can be tiled across each column
  and each drop's width kept or trimmed, and its colour taken out or pushed.
* **The sun and the moon in water** - the game's own `sun.png` and its eight
  lunar phases, carried by the pack, so the disc on the water and its phase are
  the ones the sky is showing. Each body is trimmed against the sky's size
  separately, and the axis they orbit about is a setting of its own - the two
  rise in the east, set in the west, and cross the sky at an angle.
* **Temporal antialiasing** - off by default and experimental, with the history
  weighted by motion when it is on.
* **Clouds** - a layer of cube-shaped cells in place of Minecraft's flat cloud
  boxes, with scattering inside the cloud, and its phase, transmittance and
  height falloff as settings.
* **The End** - the dimension is supported rather than falling back to the
  Overworld's sky.
* Plus motion blur, a screen vignette that is **on by default**, and the rest that
  Steadfast's own release notes describe.

## Requirements

* **Iris + Sodium**, on Minecraft 1.21.x. OptiFine is not supported.
* **Voxy** and **Distant Horizons** are both supported, and the distant-terrain
  shadows above need one of them to be worth anything.
* The material features need a **labPBR resource pack**. Without one the pack
  works normally; materials simply decode to a flat surface.

## Installation

1. Drop `Firmament-v0.7-edit-of-coderbot-Steadfast.zip` into `.minecraft/shaderpacks/`.
   Do not unzip it.
2. Pick it in **Video Settings → Shader Packs**.
3. In the shader options, `Materials (PBR) → Material format` follows the
   resource pack: leave it on `LabPBR` if you use one, set it to `Off` if not.

## Known limitations

* **Distant shadows only reach as far as the depth buffer does**: terrain behind
  the camera, off screen, or hidden does not cast, and thin things like grass and
  fences are easy to miss.
* **TAA has no motion vectors** - anything that moves on its own is handled by
  rejecting history that disagrees, not by tracking it.
* **Voxy terrain's vertices are emitted by the mod**, not by this pack, so it is
  not covered by TAA's sub-pixel jitter.
* **Reflections are left out where they cannot be right.** A surface seen through
  water, ice or glass gets no environment reflection at all, and neither does a
  face turned towards the camera, because a ray that points back at the viewer has
  nothing in front of it to trace. Both are deliberate: a reflection in the wrong
  place reads worse than no reflection.
* **The glint option only ever makes the sparkle brighter.** It cannot recolour
  it: Minecraft multiplies the enchantment's colour in before this pack sees the
  layer, so any second colour could only take light away.
* Everything in `NOTICE.md` about what is and is not covered by Steadfast.

## Credits

| | |
|---|---|
| **Steadfast 0.8.0** | coderbot - the original shader, and all of the base rendering, profiles and style |
| **Firmament edit** | Remiiil1a - direction, testing, tuning; code written by **DeepSeek V4.1 Flash** (AI) |
| **Referenced code** | follows **Mellow Shader v3.4** by **TheCMK** (MIT) and **Sundial Lite** by **geforcelegend** (GPLv3) |
| **labPBR standard** | the shaderLABS community - material channel layout and conventions |

No assets are reused from either of the two referenced packs - no textures, no
logos, no screenshots - and neither project is affiliated with this one or
endorses it. Their names are not part of this pack's name or branding.

The two referenced packs have their own entries in the settings menu, under
**Credits & licence → Special thanks**.

## Licence

* Steadfast is Copyright (C) 2026 coderbot, licensed under the **GNU General
  Public License, version 3 or later**, with **additional terms** under GPLv3
  section 7. This edit is distributed under the same terms - see
  `LICENSE-ADDITIONAL-TERMS.md`. Among other things they require the notice
  quoted above, and the `(edit of coderbot's Steadfast)` name ending.
* Mellow Shader is Copyright (c) 2026 TheCMK, **MIT** (`LICENSE-MELLOW-MIT.txt`).
* Sundial Lite is Copyright (c) geforcelegend, **GPLv3** - the same licence as
  this pack, whose copy is `LICENSE.md`.
* There is no warranty. The full summary is in **`NOTICE.md`**, and what changed
  in each release is in **`CHANGELOG.md`**. The long-form notes for each release
  are the `RELEASE_NOTES-*.md` files, which are kept with the project rather than
  shipped inside the pack.
