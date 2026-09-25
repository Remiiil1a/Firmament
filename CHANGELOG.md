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

## v0.6 - 2026-09-26

### Added

* **Bloom.** Anything brighter than the display can hold now spills a glow around
  itself, with its strength, the brightness it starts at and the radius of the
  spill as settings. The specular highlight of a surface is left out of it by
  default: a highlight is a picture of a light rather than a light, and blooming
  it puts a second sun on every wet stone.
* **Volumetric fog.** The air is a medium that is marched through rather than a
  tint laid over the frame. It is drawn at a quarter of the frame's resolution
  and lit by the shadow map, so the shafts that come through a canopy are cast by
  it, and the medium is a world-locked noise that drifts with the same wind the
  clouds use, so it never slides with the camera. Density, height, base,
  distance, march steps, the amount and scale of the noise and its octaves are
  settings, the whole thing can be drawn at full resolution, and rain thickens
  it.
* **Rain and snow particles.** The two controls the texture allows without new
  art: how many times it is tiled across each rain column, and how much of each
  drop's width is kept, which makes the rain thicker or thinner. Its colour can
  be taken out or pushed as well. Snow is drawn by the same program and moves
  with it.
* **The sun and the moon in water are the game's own images.** The pack carries
  `sun.png` and the eight lunar phases and reflects those, so the disc on the
  water is the disc the sky shows and its phase is the sky's phase. Each body is
  trimmed against the sky's size separately, and the axis the two orbit about is
  a setting of its own, because that axis is neither the world's up nor the
  horizon: the two rise in the east, set in the west, and cross the sky at an
  angle.

### Changed

* **Temporal anti-aliasing is off by default** and has moved to the development
  page as an experimental effect. The black blot it can produce is still
  unexplained, and an effect that produces one does not belong in the defaults.
* **The shipped defaults were retuned**: bloom has no threshold, PBR emission is
  brighter, the rain is thinner, the volumetric fog is thinner and answers rain
  less, the water reflects less of the sky, and the sun and the moon on the water
  are brighter.

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
  needs before it reflects at all, how far a rough surface's reflection is
  gathered, and a debug view that shows the reflection on its own.
* **Smooth parallax**, a setting for whether the height channel is interpolated
  across a texel rather than sampled at its centre.
* **The star field is reflected in water**, alongside the sun and the moon.

### Changed

* **Reflections were reworked.** The ray is no longer tilted towards the surface
  normal on its way out, the trace has twice the step budget it had, and a rough
  surface's reflection is gathered over the cone its own roughness opens - two
  rings of four directions - with the sky it reflects gathered over the same cone,
  rather than both being taken at a single direction.
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
* **Parallax flickered, and the fine grain on ordinary block faces** turned out to
  be the height channel being read one texel at a time, which is what the
  interpolating option above is for. The march also had an extra division in its
  displacement, which is what made it overshoot on some faces.
* **Parallax moved the wrong way** across a face, because the displacement was
  being laid out along the geometry's tangent frame rather than along the
  texture's own axes.

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
