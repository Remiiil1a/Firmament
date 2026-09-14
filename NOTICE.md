# Notices and licensing

**Firmament - v0.2 (edit of coderbot's Steadfast)**, for Minecraft: Java Edition.

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
`RELEASE_NOTES-v0.2.md` rather than being written back into the notices.

Steadfast's additional terms (permitted by section 7 of the GPLv3) require the
following notice to appear prominently, and as early as possible, on any page or
message that conveys Steadfast or a modified version of it - before any download
link:

> Steadfast is free and open-source software developed by coderbot, and can be downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth), https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and distribute it under the terms of the GNU General Public License, version 3.

Those same terms also require, for any modified version:

* that its **human readable name end with `(edit of coderbot's Steadfast)`** -
  hence `Firmament - v0.2 (edit of coderbot's Steadfast)`, and hence the
  `(edit of coderbot's Steadfast)` in the string `FIRMAMENT` in
  `shaders/lang/*.lang` and `shaders/environment/lighting/diffuse.glsl`. Do not
  shorten it: the name "Steadfast" may not appear in the name or branding of a
  modified version anywhere else;
* that the **file name include the same thing**, for which the terms suggest the
  suffix `-edit-of-coderbot-Steadfast` - hence
  `Firmament-v0.2-edit-of-coderbot-Steadfast.zip`;
* that the GPL and those terms are kept, and that nothing suggests this is an
  official Steadfast release. **It is not.** coderbot does not support it, and
  bug reports about it do not belong in Steadfast's issue tracker.

Steadfast itself is Copyright (C) 2026 coderbot, licensed under the GNU General
Public License version 3 or later, with the additional terms above. There is
**no warranty**, as set out in the GPL.

## 2. Mellow Shader, by TheCMK (where the material work follows from)

The material (PBR) support this edit adds follows **Mellow Shader v3.4**, by
TheCMK. Their licence asks that the credit be kept, and that their name, logo
and screenshots not be reused for another project - so:

* **No Mellow code was copied.** Everything taken from that shader is
  mathematics from published specifications or the labPBR standard: the GGX
  normal distribution, the Smith correlated visibility term, Schlick Fresnel,
  the Henyey-Greenstein phase function, and the labPBR 1.3 channel layout
  (see the shaderLABS LabPBR Material Standard). It was reimplemented in
  Steadfast's own style and naming.
* **No Mellow assets are used.** No textures, no logo, no screenshots, and the
  name "Mellow" appears only in this credit and in the `MELLOW_PBR` credit line
  in the settings menu - not as part of this pack's name.
* Mellow Shader is Copyright (c) 2026 TheCMK, licensed under the MIT License.
  A verbatim copy of that licence is included as `LICENSE-MELLOW-MIT.txt`
  because the design of the material code follows theirs. `LICENSE-APACHE` from
  that pack is included verbatim as well, as its own files ask for the whole
  licence set to be kept together.

## 3. What this means in practice

* You may modify and redistribute this pack under the **GPLv3**, as long as you
  keep the notices, keep the required name ending, and do not present it as an
  official Steadfast release.
* If you build on the material code, the Mellow credit (section 2) is expected
  to travel with it.
* If you convey this pack anywhere public - a page, a download, a video with a
  download link - the paragraph quoted in section 1 has to appear early on that
  page, before the download link.

## 4. What this edit changes, relative to Steadfast 0.8.0

Versions are counted as: **v0.1** is the material work, **v0.2** is everything
from the cloud layer onward. See `RELEASE_NOTES-v0.1.md` and
`RELEASE_NOTES-v0.2.md`.

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

**Other**

* GNU/Linux, macOS and Windows are unaffected; the shader still requires Iris.

## 5. Files

| File | What it is |
|---|---|
| `LICENSE.md` | GNU GPL version 3 - Steadfast's licence, unchanged |
| `LICENSE-ADDITIONAL-TERMS.md` | Steadfast's additional terms under GPLv3 section 7, unchanged. **Read this one.** |
| `LICENSE-MELLOW-MIT.txt` | MIT License, Copyright (c) 2026 TheCMK - verbatim copy from Mellow Shader v3.4 |
| `LICENSE-MELLOW-APACHE.txt` | Apache License 2.0 - verbatim copy from Mellow Shader v3.4 |
| `README.md` | What the pack is, what it adds, what it costs |
| `PBR_PORTING.md` | Working notes for the material port: options, verification checklist, known limits (in the project this pack was built in) |

If a distributor removes any of the files in this list, the result is not
distributable.
