# Changelog

What changed in each release of **Firmament (edit of coderbot's Steadfast)**, a
shaderpack for **Minecraft: Java Edition** built for **Iris + Sodium**. This is the
short version; the long-form notes for each release are the `RELEASE_NOTES-*.md`
files, which are kept with the project rather than shipped inside the pack.

> Steadfast is free and open-source software developed by coderbot, and can be
> downloaded from https://modrinth.com/shader/steadfast-shaders (Modrinth),
> https://www.curseforge.com/minecraft/shaders/steadfast (CurseForge), or
> https://github.com/coderbot16/Steadfast (GitHub). Anyone can modify and
> distribute it under the terms of the GNU General Public License, version 3.

**Not an official Steadfast release, and not supported by coderbot.** Please
report problems in this project, not in Steadfast's.

---

## v0.5 - 2026-09-22

### Added

* **Colored shadows.** Sunlight that has come through stained glass lands on the
  ground in the colour of the pane instead of as a hole in the light, and a
  nether portal tints the light around it with its own glow. The colour comes from
  the pane's own texture, so a resource pack that recolours its glass recolours the
  light with it. How much of the colour the light takes on is a setting; the
  portal's glow is a separate switch, and is deliberately kept off translucent
  surfaces so that a portal does not light its own faces.
* **Volumetric light strength**, as a multiplier on what the pack used to draw, and
  the light shafts are now drawn **under water** as well. The underwater shafts run
  along the same light axis as the ones above the waterline, brighten where the
  ripples on the surface gather the light, and have a multiplier of their own on
  top of the general one.
* **Enchantment glint brightness.** The sparkle on an enchanted item or a piece of
  armour can be turned up. Minecraft adds the glint's colour to the frame, so the
  light it contributes grows with the square of the setting.
* **Scattering inside the cloud layer**, with the number of scattering passes and
  how much each one attenuates as settings.
* **Reflection settings**: a metal reflection strength, the smoothness a surface
  needs before it reflects at all, a blur width, and a debug view that shows the
  reflection on its own.
* **Smooth parallax**, a setting for whether the height channel is interpolated
  across a texel rather than sampled at its centre.
* **The star field is reflected in water**, alongside the sun and the moon.

### Changed

* **Reflections were reworked.** The ray is no longer tilted towards the surface
  normal on its way out, the trace has twice the step budget it had, and the blur
  is a two-pass filter that weighs a neighbour by how closely it matches what the
  pixel it is being blurred into reflects, so that a reflection of the ground and a
  reflection of the sky are no longer averaged into each other.
* **Parallax marching was rewritten** and its direction is now taken from the
  texture's own axes rather than from the geometry's tangent frame, which is what
  had made it move the wrong way on some faces. The displacement is also held
  inside the sprite the fragment came from - faded out to the room it has left, and
  clamped behind that - where it used to wrap round to the far side of the texture.
* **The shipped defaults were retuned**: sky reflections are off, the volumetric
  light is twice the pack's own amount, the underwater shafts are at 1.5 times the
  ones above them, and the minimum ambient brightness was lowered.

### Fixed

* **Reflections on metal blocks could be incomplete or deformed.** A division by
  zero in the trace made its thickness limit ineffective, so hits were accepted
  through any amount of solid geometry.
* **Reflections were traced from the wrong place** on pixels with water, ice or
  glass in front of them.
* **A block seen through water showed two images of itself** - one refracted by the
  surface and one left where the block is. Surfaces seen through water, ice or
  glass now get no environment reflection at all; a reflection in the wrong place
  reads worse than none.
* **A one-pixel ring of sky around the edges of bevelled blocks** (most metal
  blocks, whose sprites carry a bevel in their outermost texels) was removed. The
  reflection ray left those texels, turned back into the surface it had left, and
  the hit was thrown away as a self-hit, which fell back to the sky.
* **Held items and armour, in third person, showed the world through them.**
* **Held items were lit by a sky reflection** that pointed back behind the player
  and washed metal out. That term is gone, and the reflection is traced instead.
* **Parallax could flicker, shed fine grain, or punch holes in a surface** through
  which the sky showed. Three separate causes were found and fixed: an extra
  division in the displacement, a displacement that landed on a neighbouring
  sprite's texels, and a displacement that sent the colour sample into a
  transparent texel of its own sprite.
* **Reflections blurred into a smear or a ghost** rather than into a soft image.

### Removed

* **Water scattering**, which v0.4 added: the options and the code behind them are
  gone. The water's absorption, colour and reflection are unchanged.
* An **enchant glint colour** option was tried and removed. The vanilla glint
  already arrives in the enchantment's colour, multiplied in before the pack sees
  the layer, so a second colour could only take light away rather than change the
  hue - which is exactly how it looked.

---

## v0.4 - 2026-09-20

### Added

* **The water surface is laid out in the frame the face actually has**, taken from
  the geometry's own tangent, instead of one assumed from the world's axes. Nothing
  about the water's colour, absorption, scattering or reflection changed; on faces
  lined up with the world there is no visible difference, and the difference is on
  the ones that are not.
* **Water scattering**, as three options on the water page. All off by default.
* **A star field the pack generates for itself**, with its brightness, resolution,
  density and star size to set. It fades in with the night and is covered by rain.
  The game's own star field is still drawn and is unchanged.
* **The sun and the moon reflected in water**, sized to match the game's own, the
  moon worth a fiftieth of the sun, and water only - glass and ice keep the sky
  reflection and their own Fresnel term.
* **Screen-space shadow strength**, and a handover between the sun and the moon
  that fades over two degrees either side of the horizon rather than switching.
* **The cloud layer's phase, transmittance and height falloff** as options.
* **A settings menu reorganised into two levels**, with every option reachable and
  the shipped profile named the same in both languages.

### Fixed

* **A sky that turned solid white for a few seconds in a thunderstorm.** The test
  that recognizes the game's star quads also matched the game's own sky colour quad
  whenever all three of its channels came out equal, which is what rain drives the
  sky colour to.
* **Screen-space shadows counted a surface behind the ray as an occluder**, which
  is the opposite of a shadow; they also changed with the step count.
* **Parallax mapping on water stopped at the edge of the vanilla render distance**,
  so it no longer steps where this pack's water meets a distant terrain renderer's.
* **The cloud layer no longer jumps** when the sun and the moon change hands, which
  it used to do through the phase and the transmittance.
* **The shipped profile no longer shows Chinese in an English menu.**
* **Options that had several values but rendered as click-to-cycle are sliders
  again.**

---

## v0.3 - 2026-09-18

### Added

* **Screen-space shadows for terrain past the shadow map's reach**, handed over at
  the smaller of the shadow distance and the view distance. Distant Horizons and
  Voxy terrain - and anything else drawn past that distance - was lit by the sun
  and cast nothing; it now casts, without anything being shadowed twice.
* **Temporal antialiasing, on by default.** The history is weighted by how far each
  pixel moved, so a still image accumulates a long history and loses its noise
  while walking keeps a short one and does not smear. The pack's own noise moves
  every frame so that there is something for it to average.
* **Water that is not lying flat** - the side of a waterfall, water running
  downhill - is drawn as water rather than as flat texture: its own wave surface,
  the water's colour from the same absorption model as a lake, and a reflection
  filtered by roughness.

### Fixed

* **The Voxy shader patch.** `voxy.json` was written in an older format, which
  stopped the file from loading: none of the patch's uniforms were declared, and
  the distant terrain was not shaded by this pack at all.

---

## v0.2 - 2026-09-14

### Added

* **A cloud layer of cube-shaped cells**, drawn in place of Minecraft's flat cloud
  boxes, following the pack's weather slowly and drifting with the same wind the
  planar clouds use. Overworld only; it does not cast a shadow on the ground.
* **Motion blur** along the camera's own travel, with the walk bob left out of it on
  purpose, and a blur amount and sample count to tune. Off by default.
* **Sun and moon size**: their highlights carry the sun's real angular size rather
  than being a single pixel.
* **The settings menu's effects page split into sub-pages**, with the unfinished
  temporal anti-aliasing marked as experimental.

### Fixed

* **The cloud layer stays out of the Nether**, and a cloud's own shading is
  hard-edged again.
* **Reflections on glass and calm water no longer shiver** with the walk bob.
* **A held item no longer shows the world through itself**, because the hand is no
  longer given an environment reflection at all.
* **The sun's highlight** was widened in the wrong units and barely changed; it now
  spreads the way half a degree of sunlight should.

---

## v0.1 - 2026-09-14

The first release: the material work, and the first version published anywhere.

### Added

* **labPBR 1.3 material support**: normal maps, specular/metal maps, material
  ambient occlusion, subsurface scattering, porosity/wetness and emissive maps,
  with a debug view for each channel.
* **Reflections**: a sky term per material, plus optional screen-space reflections
  of the world, computed in the deferred pass. Stained glass and panes have
  specular reflections of their own.
* **The End**: its own light, void glow and haze, and a debug view for the checks
  that detect the dimension.
* **Tangent frames taken from the geometry's own tangents** (`at_tangent`) rather
  than reconstructed from depth, which fixes normal maps flipping at distance.

---

## Not an official Steadfast release

The name of a modified version must end with `(edit of coderbot's Steadfast)`
under Steadfast's additional terms, and it does - for the pack, for its file name
and for its title in the settings menu. coderbot does not support this pack, and
bug reports about it do not belong in Steadfast's issue tracker.
