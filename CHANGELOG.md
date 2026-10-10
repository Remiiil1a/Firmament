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

## v1.0.1 - 2026-10-10

The Nether's smoke rebuilt: columns that churn, hide what is behind them and thin
out as they rise, lit from the core outwards over a bed of their own - and a
volumetric fog whose edges land on the geometry rather than beside it.

### Added

* **The plumes churn, and each column churns at its own rate.** The churn rides
  the same wind the leaves and the clouds move on, and where it is read is offset
  by the column's own density, so a thick column rolls out of step with the gap
  beside it instead of the whole layer sliding past on one sheet. **Plume churn
  speed** sets how fast the smoke moves and **Plume churn offset** how far apart
  the columns are set.
* **A bed of smoke at the foot of the columns.** Without it the columns started
  part way up the floor's fade and read as standing in mid-air, with the gaps
  between them empty all the way down to the lava. **Plume bed height** is how
  far up it reaches and **Plume bed density** is how thick it is against the
  columns standing in it; it is carved by the same moving noise as the smoke
  above it, so it churns on the same clock.
* **A thin haze fills the Nether's air.** It is not made of columns: it is the
  same everywhere in the dimension, and its colour is the game's own fog colour,
  so the crimson forest, the warped forest, the soul sand valley and the basalt
  deltas each tint it differently. **Haze density** sets it, and it only ever
  adds light - which is what the columns have to stand out from.
* **Plume core gradient.** A column's light is brightest in its middle now and
  falls away towards its thin edge, with the core taking a deeper, hotter colour
  and the edge a paler one. Before it, a column was one colour from edge to edge
  and read as a stripe of light rather than as a mass with a core. It cannot
  brighten anything - it only takes light away from the thinnest parts - and
  `0.0` gives back exactly the old flat colour.

### Changed

* **The plumes fade what is behind them instead of only adding glow.** **Plume
  extinction** is charged for every block of column a sight line crosses, so the
  dimming builds up along the view and what is far behind a column is taken out
  far harder than what is close to it. `0.0` is the old add-only look, which is
  how the plumes behaved before the option existed.
* **The glow is shaded.** **Plume shading** weights a column's own light by the
  smoke the view has already crossed: the near face is lit and the far side goes
  dark, so a column has an outline against the lava. Without it the light
  depended on the local thickness alone and every part of a column came out
  equally bright - a soft blob with neither a near face nor a far one. `0.0`
  restores that flat look, and the top of the range lights little but the skin of
  a column.
* **The plumes thin out as they rise.** **Plume height falloff** is how far a
  column keeps its density, and over that height the density falls to about a
  third of what it is at the lava. Lower makes short plumes standing on the bed;
  higher makes tall ones that stay thick almost to the ceiling, which is the
  flat-topped look the option exists to avoid.
* **The smoke close to the player is no longer cleared away so widely.** **Plume
  clearing radius** was `24`, and it scales the whole effect down within that
  distance - which includes the distance a player stands from the lava sea, so
  the nearest columns were faded towards nothing rather than drawn. It is `8`
  now. The smoke right at the eye still fades, and walking into a column turns
  the screen orange faster than it used to.
* **The Nether page's defaults are the author's own tuning in game.** Plume
  density `2.0`, extinction `0.03`, height falloff `20`, churn speed `1.5`,
  brightness `0.32` and core gradient `0.6`, with the rest of the page as it now
  stands: width `26`, contrast `1.7`, shading `2.0`, clearing radius `8`, bed
  height `8` and bed density `0.10`, haze `1.0`, and ceiling smoke density `1.0`
  with brightness `0.004`.
* **The descriptions in that page say what an option does and which way to turn
  it, and nothing else.** They used to carry the tuning behind each default -
  percentages, ratios, which build changed which value - which is not what
  someone reading a menu needs. What is left is what the option does, which way
  to turn it, and what a value of `0.0` gives back.
* **The page went from three options to seventeen, and four of its labels now say
  what the option does.** `Plume rise` is **Plume churn offset** - it moves where
  a column's churn is read and raises nothing; `Ceiling smoke` is **Ceiling smoke
  density**, because it is a slider with an amount in it rather than the switch
  for that layer; `Plume churn` is **Plume churn speed** and `Plume clearing
  around the eye` is **Plume clearing radius**. The first two are new names for
  the setting itself, so a value saved under the old name goes back to its
  default once; the last two are label changes only.

### Fixed

* **The volumetric fog's edges are resolved against the geometry.** The fog is
  marched at a quarter of the frame and put back on the full frame with the depth
  taken into account, so an edge lands where the surface behind it is instead of
  being smeared across it.
* **Full resolution fog works again.** With it on, the fog was read from the
  quarter-resolution grid and drawn shrunken into a corner of the screen, because
  the size the buffer was given and the size the reader assumed had drifted
  apart; the reader asks the fog's own image for its size now, whichever of the
  two it is. The option had also dropped out of the menu and out of the High tier
  along the way, and both are back.
* **A cause of black speckles at silhouettes is gone.** A fog sample taken from
  outside the fog's own image, or a distance that came back as not-a-number,
  could leave a black dot on an edge. The reads are held inside the image, a
  non-finite distance is refused, and an empty sum falls back to the smoothed
  read rather than to a hole.

## v1.0.0 - 2026-10-04

The first official release: four ready-made performance tiers, and a first pass
over the pack's dead weight.

### Added

* **Four performance tiers - Low, Medium, High and Toaster - and one of them is
  the factory setting.** **Medium** is the pack's own look: the temporal resolve
  on, SMAA off, everything else as it was, and it is what a fresh install gets.
  **High** adds the volumetric fog drawn at full resolution and PBR parallax on
  top of Medium. **Low** gives up the screen-space shadows and the screen-space
  reflections and softens the metal diffuse. **Toaster** turns almost everything
  off - shadows, volumetric clouds, light shafts, bloom, SMAA, the temporal
  resolve, coloured light, the water's and glass's reflections, caustics, PBR
  materials and their reflections - for a machine that would otherwise not run
  the pack at all. The list reads `✎ Firmament - ↓ Low`, the other three in the
  same shape, and a tier is one click rather than thirty.
* **A gallery in both READMEs.** Four screenshots - the Overworld at sunset, PBR
  materials close up, the End, and under water - taken by the pack's author. The
  textures in them are **SPBR by ShulkerSakura**, built on Poudingue's *Vanilla
  Normals Renewed* and licensed GPLv3, and the captions say so: they are that
  resource pack's work and not this pack's. The pictures are kept in the
  repository and deliberately **not** shipped inside the download.

### Changed

* **The temporal resolve is on by default, and it was retuned**: strength
  `0.85`, jitter radius `1.0`, history clamp `1.0`. `SMAA` is off by default. It
  is on because Medium is the pack's own look rather than its cheapest setting,
  and the tiers below Medium are where a machine that cannot afford the look
  goes.
* **A tier now sets every option it should, and gives every one of them back.**
  Iris applies the options a profile names and leaves the others where they are,
  so a tier that did not name an option could not turn it back on once it had
  been switched off by hand. The default tier names sixteen more of them now -
  the screen-space shadows, bloom, coloured shadows, glass reflections, the sun
  and moon on water, the PBR sub-options, motion blur and full-resolution
  volumetric fog among them - so each tier is a complete configuration, and
  choosing Medium again puts everything Low changed back where it was.
* **The shipped profile is the Medium tier and is named as one.** The old
  `EDIT default` entry is gone. A profile chosen by an older version of the pack
  no longer matches a name, so the list reads Custom once; pick a tier and it is
  remembered again.
* **The shared tier tooltip was rewritten.** It says, tier by tier, what each one
  gives up; it says that these four cover this edit's default configuration only,
  with Steadfast's own style profiles below them kept as they were and not
  covered by them; and it gives Steadfast's unfinished **Physical** style the
  line upstream never wrote for it.
* **Dead options and dead code are gone**, with the text of features removed
  earlier: an unused `LABPBR_1_3` define, two debug switches no menu ever exposed
  and the empty branch they left behind, the orphan labels of the water
  scattering v0.5 removed and of `PBR_SSR_ROUGHNESS` and `ORANGER_BLOCKLIGHT`, a
  duplicated profile definition, and a line whose key contained a space and could
  therefore never match anything. Nothing a player can reach changed.
* **Nine options that had a Chinese label and no English one now have both** -
  among them the physical lighting model, underwater darkening, tonemapping, the
  two entity-shadow settings, the caustics distance and the sun and moon on
  water.

### Fixed

* **Water reflects again when you look along the surface.** A band just under
  the horizon lost its reflection where the water was seen level: the pack had
  added a guard to the reflection marcher's depth tolerance that upstream
  Steadfast does not have, and removing it restores upstream's behaviour. The
  guard was deliberate - it is what keeps a reflection from being stretched away
  from the point it actually came from - and the trade is now made upstream's
  way.
* **Resetting the shader options showed Custom instead of a tier.** The water
  reflection strength in the shipped profile read `1.0` while the pack's own
  default is `0.5`, so the current state could never match the default profile
  and the menu had nothing to name. They agree now, and a reset lands on Medium.
* **A profile in Steadfast's own family could refuse to apply.** One of its
  values is outside the option's allowed list - a letter missing from
  `SEMI_NATURAL` - and an invalid value makes the loader reject the whole
  profile, the family that inherits it included. Corrected.
* **The Chinese tooltip for the tiers was cut off in the middle of a
  sentence.** A continuation line had lost the backslash that continues it, so
  the value ended there and everything after it - the rest of the description and
  the whole performance ladder - became text nothing read. The line is back and
  the tooltip runs to the end.
* **The pack's own entry in the shader options had stopped working.** A
  checker's output had been written into the first line of both language files,
  on the same line as the entry's key, which left the key unmatchable. Both first
  lines are restored verbatim from Steadfast.
## v0.8 - 2026-10-02

### Added

* **Motion vectors, and a temporal filter rebuilt on them.** The reprojection of
  the previous frame now lives in one file rather than three, and the filter uses
  the nearest depth in a pixel's own neighbourhood as its anchor, which is what
  stops a silhouette from dragging the history of whatever stands behind it. The
  held item is left out of the camera's translation, because it does not move with
  the world. Three reference packs were read for this and all three had arrived at
  the same two ideas separately.
* **Parallax occlusion mapping, with the height taken from the material the pack
  already reads.** A surface whose normal map carries a height in its alpha
  channel is now displaced along the view ray: the albedo and the material maps
  are read where the surface appears to be rather than where the geometry is, so
  a brick's mortar line sits where the light says it does. How deep the surface
  is, how far it may be displaced on screen, the number of steps and how many of
  them are refined are all settings, and the effect has a switch and a distance of
  its own. It has a page of its own under **Materials (PBR)**.
* **Two ways to read the height.** The **smooth** path filters the height field
  the way the other material maps are filtered, which reads as a surface with a
  rounded profile; the per-texel path reads the height's own texel, which is what
  shows the field at the resolution it actually has. Which one a surface wants
  depends on what it is, so it is a setting rather than a decision made here.
* **Parallax self-shadowing.** The height field shadows itself, with a strength
  of its own: where the light arrives at a glancing angle, the parts of a
  displaced surface standing behind the parts in front of them are darkened.

### Fixed

* **A black blot the temporal filter used to grow, and drag across the terrain.**
  A history that could not be stored came back as an ordinary black pixel, and
  once a pixel's whole neighbourhood was black the filter held it there. What
  stopped it was not another threshold - those had all been tried - but changing
  the history's format and giving each pixel a flag for whether its history may be
  believed at all.
* **Parallax on surfaces seen nearly edge-on.** The displacement was measured in
  the wrong units at a glancing angle, and the sample spiral now starts from a
  jittered point and gathers towards the near end of the height range, which is
  where the detail is.
* **A faint band the beacon beam left across water**, drawn as it was into the
  buffer the water refracts, before the beam was finished.
* **The black band on level-of-detail water, at the edge of what the
  level-of-detail mod draws.** Water there took its refraction from the position
  the refracted ray left the water at - and on that terrain the depth the ray
  marches is the mod's own texture, which holds nothing past the edge of what the
  mod has drawn. The ray then ran its whole budget and the water was coloured by
  whatever happened to lie at the far end of it; because that position slides
  across the picture as the view turns, the colour was dragged along with the
  camera, and the temporal resolve accumulated the darker end of it into a flat
  black clump. A ray that left the water into the sky is now given the sky of the
  direction it left in, which depends on nothing on screen.
* **Rain drops no longer redraw snow.** The three weather settings change how a
  *rain* drop is drawn - how many are tiled across a column, how much of each
  drop's width is kept, and how much colour the drop carries. Snow is drawn by
  the same program, and all three were being applied to it as well. Which of the
  two a particle is is now read from the particle texture itself, the way Sundial
  reads it, and a flake is left as the resource pack draws it.
* **The haze no longer begins at a boundary around the player in rain.** Haze
  below a hundredth of a unit was being culled outright, and in light or moderate
  rain the whole rain term is under that out to about fifteen blocks - so the rain
  had a ring of clear air around the player, with the haze switching on at its
  edge. The cull is gone; the haze fades in from nothing instead.

## v0.7 - 2026-09-26

### Added

* **The End's own body.** The End has a body of its own: a dark core, an
  **Einstein ring** produced by **gravitational lensing**, and a faint halo.
  **It has no visible disc** - the photosphere, the chromosphere and the surface
  detail are gone. It is not a star with a surface but something that presses the
  sky behind it out into a ring.
* **Gravitational lensing.** The sky behind the body is **actually bent**, from
  the closed-form point-mass solution rather than by marching rays through a few
  hundred steps. What the ring holds is therefore **the sky, piled up**: the sky
  turns, and the contents of the ring stream with it. The ring's size is a
  setting.
* **A nebula band.** The End's sky has a band of nebula across it. It is both the
  scenery and **what makes the lensing visible** - against an even starfield there
  is nothing to see bend.
* **The End's sky moves.** The whole sky - stars and nebula together - turns
  slowly about the nebula band's own axis, and **far faster than in batch 337**:
  every step of the speed setting was raised, and the top of its range went from
  3.0 to 5.0.
* **A violet tint for the stars.** The End's field can be moved towards violet as
  a whole. Both ends of its range of colours move together rather than being
  replaced by one, so the field keeps its variety at every setting.
* **Nether plumes.** Columns of smoke now rise through the Nether's air, with a
  layer of it gathered under the ceiling. The amount and the ceiling layer have a
  setting each.
* **Four styles for the block selection outline.** Vanilla, None, Glow and RGB.
  **Glow** draws the outline in a colour you set - one value per channel, 0 to
  255 - and puts a halo of that colour around it; **RGB** walks the colour round
  the wheel on its own.

### Changed

* **The shipped defaults are this release's tuned set** (ten settings): End
  ambient light `1.0`, the End body's core brightness `0.0`, its tint `1.0` (fully
  violet), its rotation speed `0.25`, star size `2.0`, star violet tint `1.0`,
  Nether plume density `1.5`, and the outline's glow colour `255 / 255 / 255`.
  **A core brightness of `0.0` means the body's centre is dark** - what is left is
  the Einstein ring and the halo, which is this release's deliberate look.
* **The End's own light is on by default, and it is now properly saturated
  violet.** The violet end used to be so pale that mixing it into a warm white
  gave a slightly warm white - **the option could not reach the colour it was
  named after**. Now that it can, the colour was compensated for brightness, so
  turning it up does not darken the dimension with it.
* **The End's volumetric fog follows the body's own colour** - the same palette -
  **except underwater**, which stays with the water's own fog.
* **The old three-tier body is gone** (Off / Star / Black hole). The End's body is
  none of them.
* **Three End options that never did anything are gone**: the void glow, the End
  fog, and the switch for suppressing the flash. The flash suppression is now
  unconditional.
* **The End's body has no "photosphere / chromosphere / surface" settings any
  more**, removed along with the disc.

### Fixed

* **The End's stars were sliced off with a straight edge.** The field only ever
  looked at the one cell the view direction fell into, so a star that crossed a
  cell wall came out with a straight edge cut off it. A star is now placed inset
  from the walls by its own radius, which removes the edge and **removes the
  ceiling on the size setting with it**.
* **The Overworld's sun and moon no longer appear in the End's water**, the End's
  own body is reflected there instead, and **`WATER_BODY_BRIGHTNESS` now applies
  in the End as well**.

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
