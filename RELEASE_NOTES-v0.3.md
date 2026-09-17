# Release notes - v0.3

An edit of [Steadfast](https://github.com/coderbot16/Steadfast) by coderbot, for
**Iris + Sodium** on Minecraft 1.21.x. Distributed under the GPLv3 with
Steadfast's additional terms; see `NOTICE.md` and `LICENSE-ADDITIONAL-TERMS.md`.

## Distant terrain: screen-space shadows

The shadow map only covers a fixed distance around the player, so Distant
Horizons and Voxy terrain - and anything drawn past that distance - was lit by
the sun and cast nothing. A ray is now walked from each fragment towards the sun
through the depth buffer, and whatever the buffer says is in the way is in the
way; it is used only past the shadow map's reach, so nothing is shadowed twice.

* The handover point is the **smaller of the shadow distance and the view
  distance**, because the shadow map can only contain terrain that was actually
  rendered into it.
* It steps a fixed fraction of the distance to the receiver, rather than a fixed
  number of blocks, which is what keeps the shadow edges lined up with what casts
  them at every range.
* It has boundaries that cannot be lifted: terrain behind the camera or off
  screen casts nothing, and thin things are easy to miss.

## Temporal antialiasing

* **On by default.** The history is weighted by how far each pixel moved, so a
  still image accumulates a long history and loses its noise while walking keeps
  a short one and does not smear. This is what lets the screen-space shadows
  above be dithered per frame and averaged away instead of sitting there as grain.
* The history is fetched with a Catmull-Rom filter, so a moving camera stops
  quietly softening the picture it accumulates.
* The noise the pack's own effects use is shifted every frame for the same
  reason: a fixed pattern cannot be averaged out by anything.

## Water

* **Water that is not lying flat** - the side of a waterfall, water running
  downhill - is drawn as water rather than as flat texture: its own wave surface,
  the water's colour from the same absorption model as a lake, and a reflection
  filtered by roughness, so it reads as rough water instead of as a mirror
  showing something it is not facing.
* Nothing about a still surface changed.

## Voxy

* **The shader patch is fixed.** The `samplers` field of `voxy.json` was written
  as a list where the format wants a map of names to types, which stopped the
  whole file from loading: none of the patch's uniforms were declared, and the
  distant terrain was not shaded by this pack at all.

## Clouds

* **The layer can be seen from above.** It was drawn only on sky pixels, and the
  ray march itself refused any ray that was not going up, so a player above the
  clouds looked down at empty sky. The layer now stays at its configured height -
  it does not move with the player - and is drawn wherever it is in front of the
  scene.

## Materials and the rest

* Parallax mapping was **reverted to Steadfast's own implementation**, with the
  refinement default raised to 32 and the depth and maximum-displacement options
  untangled. The face-disappearing defect it used to have is not fixed; it is
  documented in `PBR_PORTING.md` and was left alone.
* Ambient occlusion was tried and **removed**: six attempts never made a crevice
  darker rather than the whole image greyer.
* Water caustics, blocky volumetric clouds, motion blur and the End's sky are
  unchanged from v0.2 apart from the layer work above.

## Credits

Code from **Mellow Shader v3.4** by **TheCMK** (MIT) and **Sundial Lite** by
**geforcelegend** (GPLv3) is referenced in the temporal antialiasing and the
water; both are credited in the settings menu under
**Credits & licence → Special thanks**, and in `NOTICE.md`.
