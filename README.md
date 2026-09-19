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
  from a labPBR resource pack, with reflections and self-shadowing.
* **Distant terrain** - screen-space shadows for terrain past the shadow map's
  reach, which is what Distant Horizons and Voxy terrain otherwise never gets.
* **Water that is not flat on the ground** - the sides of waterfalls and of water
  running downhill are drawn as water, with the same surface, colour and
  reflections as a still surface, laid out in the frame the face actually has
  rather than one assumed from the world's axes.
* **Temporal antialiasing** - on by default, with the history weighted by motion
  so that it reduces noise while standing still without smearing while walking.
* **The End** - the dimension is supported rather than falling back to the
  Overworld's sky.
* Plus the blocky volumetric clouds, motion blur and the rest that Steadfast's
  own release notes describe.

## Requirements

* **Iris + Sodium**, on Minecraft 1.21.x. OptiFine is not supported.
* **Voxy** and **Distant Horizons** are both supported, and the distant-terrain
  shadows above need one of them to be worth anything.
* The material features need a **labPBR resource pack**. Without one the pack
  works normally; materials simply decode to a flat surface.

## Installation

1. Drop `Firmament-v0.4-edit-of-coderbot-Steadfast.zip` into `.minecraft/shaderpacks/`.
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
* Everything in `NOTICE.md` about what is and is not covered by Steadfast.

## Credits

| | |
|---|---|
| **Steadfast 0.8.0** | coderbot - the original shader, and all of the base rendering, profiles and style |
| **Firmament edit** | Remiiil1a - direction, testing, tuning; code written by **DeepSeek V4.1 Flash** (AI) |
| **Referenced code** | follows **Mellow Shader v3.4** by **TheCMK** (MIT) and **Sundial Lite** by **geforcelegend** (GPLv3) |
| **labPBR standard** | the shaderLABS community - material channel layout and conventions |

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
  in each release is in the **`RELEASE_NOTES-*.md`** files, which are kept with
  the project rather than shipped inside the pack.
