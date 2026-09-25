// Steadfast is a fast and high-quality graphical overhaul for Minecraft (JE)
// Copyright (C) 2026 coderbot
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// Added 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

// LabPBR material support.
//
// This decodes the normal (_n) and specular (_s) atlases that Iris / OptiFine
// build from a PBR resource pack, following the shaderLABS LabPBR 1.3 material
// standard:
//
//   https://shaderlabs.org/wiki/LabPBR_Material_Standard
//
// Channel layout, as defined by the standard:
//
//   _n.rgb - tangent-space normal, stored in the DirectX convention (X points
//            right, Y points *down* in the texture). Note that _n.b is NOT the
//            Z component: LabPBR stores material ambient occlusion there and
//            requires Z to be reconstructed from X and Y. That occlusion is
//            read when PBR_MATERIAL_AO is on; with it off, only .xy is used
//            and the blue channel is never read at all.
//   _n.a   - height, used for parallax occlusion mapping.
//
//   _s.r   - perceptual smoothness. roughness = (1.0 - smoothness)^2
//   _s.g   - F0 / metal ID. Values are stored linearly as of 1.3 (older
//            versions stored the square root of F0 and would need squaring).
//              0-229   dielectric, F0 = the value itself (max ~0.898)
//              230-237 hardcoded metals, see PbrMetalF0
//              238-255 albedo-based metal, F0 = the albedo
//   _s.b   - subsurface scattering above 64.5/255, porosity below it. The
//            scattering is read when PBR_SUBSURFACE is on, the porosity when
//            PBR_POROSITY_WETNESS is.
//   _s.a   - emission. 254 means "fully emissive", 255 means "does not emit".
//
// Every feature below has its own switch, so a player who does not want, say,
// the cost of parallax mapping can turn just that off.
//
// Cost note - all of this is per-pixel:
//
//   Always executed (when PBR_SURFACE is defined and the material is not
//   skipped): the tangent frame, the parallax ray march if that is enabled, the
//   normal decode, and the specular / emission decode.
//
//   Conditionally executed: the hardcoded metal lookup (only for materials with
//   G > 229.5/255), emission (only when the material actually emits), the
//   occlusion channel of the normal map (only when PBR_MATERIAL_AO is on), and
//   the specular lobe itself (skipped entirely when F0 is zero, which is what a
//   resource pack without specular maps produces).
//
//   The parallax ray march is the only part with a variable cost, and it is
//   bounded by PBR_PARALLAX_STEPS texture samples. A resource pack whose height
//   channel is flat costs a single sample and produces no displacement, since
//   LabPBR stores 1.0 for "not displaced".

// A note for anyone adding options here: a boolean option is only registered
// by Iris if the macro is referenced by an #ifdef or #ifndef somewhere in the
// pack. A toggle that is only ever tested with "#if defined(NAME)" is declared,
// works when edited by hand, and silently never appears in the settings menu.
// That is what the #ifdef blocks after the toggles below are for.
//
// Whether to read PBR material data at all. Turn this off to fall back to
// Steadfast's original rendering, which is useful when playing with a resource
// pack that has no normal / specular maps.
#define PBR_OFF 0
#define LAB_PBR 1
#define PBR_FORMAT LAB_PBR // [PBR_OFF LAB_PBR]

// Whether to build the material tangent frame from the tangent the geometry
// actually has, instead of rebuilding one out of screen-space derivatives.
//
// The derivative route has to reconstruct the surface position from the depth
// buffer before it can differentiate it, and the depth buffer quantizes: past a
// certain distance the step it takes between two neighbouring pixels is larger
// than the distance between those pixels across the surface. The frame that
// comes out of those derivatives stops describing the surface, and the normal
// map then bends the normal along axes that have nothing to do with the
// material - which reads as the normal map inverting at a fixed distance from
// the camera, and which no amount of mip clamping or parallax tuning can fix,
// because neither of those is what is wrong. The distance it starts at depends
// on the depth buffer's precision and on how obliquely the surface is seen, not
// on the resource pack.
//
// The vertex tangent has none of that to worry about: it comes from the quad
// itself, and perspective-correct interpolation of it is exact on a flat
// triangle.
//
// On by default, since it is a correctness fix rather than a look. Turning it
// off restores the derivative frame, which is worth doing only to compare the
// two on the same scene.
//
// This option is about the material frame only. The frame the water surface is
// drawn in comes from the same per-face encoding and is not affected by it: the
// water surface has no resource pack to fall back on, so it always uses the
// frame the face has, and the option would otherwise have to mean two things.
#define PBR_TANGENT_ATTRIBUTE
#ifdef PBR_TANGENT_ATTRIBUTE
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in lit.vsh and lit.fsh.
#endif

// Whether to perturb the surface normal with the normal map, which is what
// makes the surface detail react to the light direction.
#define PBR_NORMAL_MAP

// Whether to use the smoothness and F0 stored in the specular map, which is
// what gives materials their roughness-driven highlights.
#define PBR_SPECULAR

// How strong the specular reflection is. 1.0 is the physically correct value,
// but a correct dielectric only reflects about 4% of the light that hits it,
// and Steadfast tonemaps its highlights down on top of that, so a physically
// correct highlight is far less visible than most people expect from a
// "reflective" material. Raise this if materials still look flat.
#define PBR_SPECULAR_STRENGTH 2.0 // [1.0 1.25 1.5 2.0 2.5 3.0 4.0 6.0]

// How big the sun and the moon are, as far as the highlight they make on a
// surface is concerned.
//
// Both are treated as points, which is why a polished block shows a highlight
// the size of a single pixel instead of the disc a mirror really shows: the sun
// covers about half a degree of sky, and that angle is what should spread the
// highlight out. This widens the specular lobe by that angle, so a mirror shows
// a disc of the sun's true size and a rough surface - whose lobe is far wider
// already - is left as it was.
//
// 1.0 is the sun's real angular size and is what the option is for. 0.0 is the
// point light this used to be, for comparing the two; larger values exaggerate
// the disc for the look of it, like a photographer's starburst. The moon is
// close enough to the sun in size to share the setting.
//
// Only the highlight is affected. The sun and moon drawn in the sky are a disc
// of their own and do not change size with this.
#define PBR_LIGHT_SIZE 1.0 // [0.0 1.0 2.0 3.0 4.0 6.0 8.0]

// Whether to weight the diffuse light by the part of it that the surface did
// not reflect, which is what keeps diffuse and specular from adding up to more
// light than arrived.
//
// Fresnel is the term that decides the split: a surface reflects a fraction of
// the light that hits it and lets the rest through into the material, and that
// transmitted part is what the diffuse response is made of. Steadfast adds the
// two together without that split, which is why a shiny surface can be brighter
// than the light falling on it, and why a metal - which reflects most of the
// light and should have almost no diffuse response at all - still takes half a
// diffuse response and reads as shiny plastic rather than as metal.
//
// Off by default because it changes the brightness of everything with a
// specular map at once. Turning it on is worth pairing with a specular strength
// of 1.0 above: that is the value at which the budget is balanced, and 2.0 was
// only ever a way of fighting the tonemapper without it.
//
// Note that this makes bright metals (gold, silver, aluminium) noticeably
// darker in caves and at night, which is correct - a metal that is not reflecting
// anything and is not lit by anything is dark - but it is a large enough change
// in look to be worth trying rather than assuming.
//#define PBR_ENERGY_CONSERVATION
#ifdef PBR_ENERGY_CONSERVATION
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in diffuse.glsl.
#endif

// Whether materials that the resource pack gives no usable specular data for
// should fall back to a plain dielectric instead of being left with no surface
// response at all.
//
// This is what makes a resource pack that only ships normal maps, or that only
// ships specular maps for some of its blocks, still look like it has materials
// everywhere. Turn it off if you would rather see exactly what the resource
// pack authored, matte blocks included.
#define PBR_DEFAULT_MATERIAL

// The roughness used for those fallback materials. Lower is glossier.
#define PBR_DEFAULT_ROUGHNESS 0.5 // [0.1 0.15 0.2 0.3 0.4 0.5 0.65 0.8 1.0]

// F0 for the fallback materials, and the floor applied to dielectrics. 0.04 is
// the reflectance of ordinary glass and plastic, and is what a dielectric
// should be reflecting; a resource pack that leaves the green channel at zero
// is asking for a surface that reflects nothing, which no real material does.
const float PBR_DEFAULT_F0 = 0.04;

// Whether to look up the LabPBR hardcoded metal types (iron, gold, copper, and
// so on). With this off, those materials are shaded as albedo-based metals
// instead, which is a much closer approximation than treating a metal as a
// dielectric.
#define PBR_METALS

// Whether to add the emission stored in the alpha channel of the specular map.
#define PBR_EMISSION

// Whether the emission in a specular map is used on any block, or only on the
// blocks the game's own lighting already treats as light sources.
//
// On by default, and this is the LabPBR rule: the alpha channel is the resource
// pack saying "this part of my texture emits", and it is how a pack makes an ore
// vein, a rune or a lamp's glass glow. An ore is not a light source in the game,
// so a rule that asked for one would mean the channel could never do the thing it
// exists for. See PBR_PORTING.md 164.
//
// Off is the older behaviour, kept as the escape hatch rather than as a default:
// a pack, or a texture a mod generated, that paints emission where it did not
// mean to - or that leaves the channel at its maximum by accident - would have
// every such sprite light up. Turn this off if something glows that should not,
// and the emission is then only added where the game's own lighting already
// calls the block a light source.
#define PBR_EMISSION_ANY_BLOCK

// How bright that emission is.
//
// LabPBR stores emission as a fraction of the surface color, and on its own
// that is rarely bright enough to read as something lit from within - the
// tonemapper compresses it straight back down. Raise this to make emissive
// materials actually glow.
#define PBR_EMISSION_STRENGTH 4.0 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0]

// Whether blocks that emit light should glow with their own color.
//
// This is what makes glowstone, sea lanterns, lava, torches, and the like look
// like they are lit from within rather than merely brightly lit, and unlike the
// emission above it needs nothing from the resource pack.
//
// Iris and OptiFine mark a face that can emit light by making the block light
// coordinate of its lightmap negative, which is the only signal available for
// this. Note that this lights up the block itself, not its surroundings: the
// light it casts on neighbouring blocks is already part of the block lighting.
#define BLOCK_EMISSION
#ifdef BLOCK_EMISSION
	// See the note on PBR_PARALLAX_SHADOW: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in lit.fsh.
#endif

// How bright block self-emission is. Values above 1.0 push the surface into
// overbright territory, which is what a light source should look like.
#define BLOCK_EMISSION_STRENGTH 1.5 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0]

// Whether to displace the material and base textures with the height stored in
// the alpha channel of the normal map.
//
// This is parallax occlusion mapping: the surface is traced against its own
// height field along the view ray. It is the most expensive part of this file,
// and the only one that changes where textures are sampled rather than just how
// they are lit.
//
// Where samples the albedo comes from is the whole point of it, but the alpha
// test is not allowed to follow the displacement: a ray that leaves the
// fragment's own material lands on texels that material does not have - the
// transparent pixels a cutout sprite keeps inside it - and reading a zero there
// would open holes in the middle of a solid surface. The base texture sample in
// lit.fsh carries the guard and the reasoning for it.
//#define PBR_PARALLAX

// How many layers the parallax ray march takes. Each layer is one texture
// sample for the view ray, and while PBR_PARALLAX_SHADOW is on it is one more
// for the light ray - this is the layer count for both marches, so it is what
// sets the cost of the effect as a whole. More layers track the height field
// more closely at grazing angles. 64 is enough for the effect to be essentially
// exact; 4 is enough to see that something is there.
//
// This is a quality knob and not a depth knob, which is worth stating because
// it was not true of the version before this one. The ray always covers the
// whole depth range no matter how many layers it takes, because the layers
// grow from small to large as it descends (see PbrParallaxUV). Raising this
// only makes the march finer, and what shows up as the count comes down is
// the crossing landing further from where it belongs on a surface that rises
// sharply - never a shallower surface.
//
// This is the knob that decides how much of the shape comes out, and it is the
// only one that does: the refinement below can only pin down a crossing inside
// the interval two layers bracketed, so a surface whose height varies more than
// once inside such an interval keeps whatever the coarser bracketing made of it
// however many refinement steps it is given. That is the note Sundial's own
// settings menu carries, and it is why this default is where it is rather than
// relying on the refinement to clean up after a short march.
//
// What it is not is a cure for a height channel read as a staircase, and that is
// worth spelling out because it is what the setting looks like it should do.
// More layers resolve a staircase *better* rather than less - the steps come out
// finer and closer together - so what shows up as a few bands at a low count and
// as fine grain at a high one is this setting re-arranging that error, not
// removing it. The interpolation behind PBR_PARALLAX_SMOOTH is what removes it,
// and that is why this default has come down: with the height channel
// interpolated, all that is left for the layer count to do is bound the interval
// for a height channel that crosses the ray more than once inside it. On this
// pack's own height channels the displacement it produces moves by less than a
// thousandth of a texel between 8 layers and 128, so 16 keeps a margin over the
// multi-crossing case while paying back half of the height fetches that the
// interpolation's four per sample added. With that option off there is no such
// bill to pay - a height sample is one fetch again - and raising this is the way
// to spend what it frees.
//
// The reference packs' defaults are Sundial 80 and Mellow 64, and they were set
// against a march whose every height sample is one unfiltered fetch - Sundial's
// SMOOTH_PARALLAX is the option that interpolates them, and it exists for the
// same reason PbrHeightBilinear does. Their numbers describe their march with
// that option off, so they are not this pack's; the list still reaches 64 for
// anyone who would rather have them.
//
// Note: these are written as #define rather than const, which is the form the
// rest of this pack uses for tunable values (see WATER_PARALLAX_DISTANCE).
#define PBR_PARALLAX_STEPS 16 // [4 8 12 16 24 32 48 64]

// How deep the height field is at its deepest point (height 0), as a fraction
// of the sprite the block face is drawn with.
//
// This used to be a distance in blocks, converted into texture coordinates
// through the surface's own UV axes, and that conversion is what made the
// setting do nothing at all on some faces: the axes are reconstructed from
// screen-space derivatives, a face whose mapping those derivatives cannot
// resolve had one of them dropped or blown up, and the depth that came out was
// then either zero or enormous depending on which side of a block was being
// looked at. Measuring it against the sprite instead takes the axes' *lengths*
// off the path, which is the half of them the derivatives are unreliable for,
// and makes the same number mean the same thing on every face and in every
// resource pack. Their direction is still where the ray direction comes from -
// see PbrParallaxUV - and there it is doing no harm.
//
// The two are the same number in the ordinary case, where one sprite covers one
// block face: 0.2 is a fifth of the block in either reading, which is what the
// range below was tuned for. On a face whose texture covers several blocks, or
// several faces of a small block, the depth follows the sprite and is
// correspondingly larger or smaller.
//
// LabPBR asks resource packs to stay within a quarter of a block, so values
// much above 0.25 are likely to look wrong on most packs. A resource pack with
// a flat height channel is unaffected by this setting.
#define PBR_PARALLAX_DEPTH 0.2 // [0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5]

// How many binary search steps refine the ray march.
//
// The layer march can only ever land on a layer boundary, and a resource pack's
// height channel usually covers only a fraction of its range, so very few
// layers actually fall inside the real height variation. Without refinement the
// texture then visibly snaps between a handful of positions - it stacks up in
// steps rather than following the surface.
//
// What it cannot do is recover shape the march did not bracket. It halves the
// interval between the two layers that straddle the crossing, so it finds that
// crossing to any accuracy it is asked for - but a height field that dips below
// the ray and rises again between two layers has more than one crossing in
// there, and bisecting picks one of them and can switch to another as the view
// moves. Layers are what narrows the interval and so what removes that; this
// setting is accuracy and only accuracy. Sundial's settings menu says the same
// thing about its own two knobs, which is where the split between them comes
// from.
//
// Each step is one more texture sample, and a bisection doubles its accuracy
// per step, which makes this the cheapest accuracy in the file and the last
// thing worth turning down. 8 steps leave the answer 256 times finer than the
// interval they were handed: at 32 layers that interval is a sixteenth of the
// height range to begin with, so 8 steps already land inside a four-thousandth
// of the range - far below one texel of any resource pack, and far past what
// the eye can tell apart. Sundial stops its own list at 16. The default here
// was 32 while the march above was short enough to need it; with the layer
// count raised, it is 8, and raising it further buys nothing.
#define PBR_PARALLAX_REFINE 8 // [2 4 6 8 12 16 24 32]

// Whether the height channel is interpolated between its texels by hand instead
// of being read one texel at a time.
//
// The atlas cannot be asked to do this for us. A block atlas is sampled with a
// nearest filter as it is magnified - that is what keeps a block's texels sharp
// - so one fetch of the height channel is a *point* sample, and a resource pack
// that draws a slope into it is read back as a staircase from one texel to the
// next. The march then traces that staircase, and the coordinate it returns
// jumps a whole texel at a time as the view moves, which is the flicker on an
// ordinary block face. Turning this on has the four texels around each sample
// fetched and mixed by hand, which is the arithmetic a linear filter does, with
// each of the four corners held inside the sprite first so that no mip level and
// no filtering across a sprite's edge is needed. See PbrHeightBilinear.
//
// What it changes is the shape of a hard-edged height field. Cobblestone and
// bricks have height channels that step between one texel and the next, and a
// step is what the march reads as a cliff and the eye reads as grain; this turns
// those steps into slopes. Sundial carries the same option and ships it on, and
// its menu describes it as making the parallax show a slope rather than
// individual cubes - which is the difference in one line.
//
// Off keeps the height field as sharp as the resource pack drew it, at the cost
// of the grain and banding coming back wherever the field has a hard edge. That
// is a look rather than a bug - it is what this pack showed before the option
// existed - and it is also the cheaper of the two: one fetch per height sample
// instead of four, so a layer count that had to come down to pay for the
// interpolation can go back up when it is off.
#define PBR_PARALLAX_SMOOTH
#ifdef PBR_PARALLAX_SMOOTH
	// See the note on PBR_PARALLAX_SHADOW above for the rule this #ifdef follows:
	// Iris only treats a bare #define as a boolean option if something tests it,
	// and the test has to sit outside every other guard. The use is in PbrHeight,
	// which is compiled only while PBR_PARALLAX is on - and parallax itself ships
	// off, so a test inside that guard would take this option out of the menu for
	// a player who has not turned parallax on yet.
#endif

// How far a sample is allowed to be displaced, in the same sprite-relative
// units as PBR_PARALLAX_DEPTH above.
//
// Grazing angles divide the displacement by the view direction's slope, so
// without a limit a shallow view would drag the sample whole blocks away and
// exaggerate the depth. This is that limit.
//
// It has to be at least as large as PBR_PARALLAX_DEPTH, or the depth setting
// stops having any effect partway up its own range: the displacement is the
// depth scaled by the view angle's slope, so a cap below the depth silently
// clips it and turning the depth up past the cap changes nothing. That is what
// the 0.25 this used to be did - on a view 50 degrees or so off the surface
// normal the slope is already past 1, so every depth setting above about 0.25
// produced the same picture.
//
// There is a second cap behind this one, at half a sprite, which is not
// exposed because it is not a look: past it the ray has left the material the
// fragment started in, and whatever it found there would belong to another
// texture rather than to a deeper part of this one. What keeps a sample out of
// that region now is the fade in PbrParallaxUV, with PbrClampToSprite behind it;
// what this cap still does is bound the offset that fade is asked to fit into
// the room a fragment has.
#define PBR_PARALLAX_MAX_OFFSET 0.5 // [0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5 0.6]

// Distance in meters at which parallax mapping fades out. Past a certain
// distance a single screen pixel covers more than the whole height range, so
// the ray march only produces shimmer at full cost. This mirrors the water
// parallax settings.
#define PBR_PARALLAX_DISTANCE 16.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0 96.0 128.0]

// Whether the height field should also shadow itself.
//
// Parallax mapping on its own only slides the texture around; the raised parts
// of the height field do not darken the crevices behind them, so the surface
// ends up looking like a flat picture pasted onto the block rather than like
// something with depth. Shadowing the height field against the light is what
// makes the sides of the bumps read as sides.
#define PBR_PARALLAX_SHADOW
#ifdef PBR_PARALLAX_SHADOW
	// The #ifdef is not decoration. Iris only treats a bare #define as a
	// boolean option if the macro is referenced by an #ifdef or #ifndef
	// somewhere, so without this the option would be declared but never appear
	// in the settings menu. (This is why every toggle elsewhere in this pack is
	// followed by an #ifdef block.) The actual use is in lit.fsh.
#endif

// How dark those height field shadows get. 1.0 is a fully occluded crevice.
#define PBR_PARALLAX_SHADOW_STRENGTH 0.85 // [0.25 0.5 0.65 0.75 0.85 1.0]

// How far the normal map is allowed to bend the surface normal. Raise this if
// the surface detail is there but too subtle to notice, or lower it if the
// lighting looks noisy.
#define PBR_NORMAL_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]

// The deepest mip level the material maps are sampled at.
//
// The space between sprites in the material atlases is empty, and an empty
// texel is black. Black is not a neutral value for a normal map: it decodes to
// a tangent-space direction of (-1, -1) with no Z at all, which is a strong
// fixed tilt rather than a flat normal. As distance grows, the mip level the
// maps are sampled at grows with it, and once those texels reach past the
// sprite the sample picks up that black - which is what makes a surface's
// normal map appear to invert beyond a particular distance.
//
// A higher-resolution resource pack reaches that mip sooner, so the artifact
// moves closer as the pack gets sharper. That is the signature to check for.
//
// 0 keeps every sample in the sharpest level, which makes the contamination
// impossible. Raise it only if you would rather have the mip filtering back.
#define PBR_MATERIAL_MAX_LOD 0 // [0 1 2 3]

// The mip level at which the normal map has faded out to a flat surface. The
// fade starts at 40% of this value and completes here.
//
// Keeping the samples in the sharpest mip means they can no longer be blurred
// out by distance, so they would alias instead. Fading the perturbation to flat
// over this range is the equivalent of that missing blur, and it is what stops
// distant surfaces from shimmering.
//
// The level this is measured against is the true one for the fragment's
// distance, not the level actually sampled, so it fades in the same place no
// matter what PBR_MATERIAL_MAX_LOD is set to. The Material detail limit debug
// view shows the same number, which is how to place this exactly: pick the
// level at which the surface stops looking like it has any detail left.
#define PBR_NORMAL_FADE_LOD 2.0 // [1.0 1.5 2.0 2.5 3.0 4.0 6.0]

// Whether to scale the indirect light that reaches a fragment by the ambient
// occlusion the resource pack baked into the blue channel of the normal map.
//
// That channel is the third of the three things LabPBR stores in a normal map -
// X and Y are the normal, alpha is the height, and blue is occlusion - and it is
// baked from the block's own geometry: the inside of a brick, the corner of a
// plank, the gaps between leaves. None of that is present in the lighting
// Steadfast computes on its own, because Minecraft's per-vertex ambient occlusion
// only knows about block corners and the shadow map only knows about the sun.
//
// This is off by default, as it is the one PBR feature that changes how bright
// familiar blocks are: a pack that bakes strong occlusion makes the world read
// darker than Steadfast's original rendering, and whether that looks like the
// depth it is meant to be or like a bug depends entirely on the pack. Use the
// occlusion view under PBR_DEBUG to see what a pack actually authored before
// deciding.
//
// Only indirect light is occluded. Sunlight is left to the shadow map and to the
// parallax height field, both of which know where the light comes from, so a
// sunlit surface is never darkened twice.
//#define PBR_MATERIAL_AO
#ifdef PBR_MATERIAL_AO
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in diffuse.glsl.
#endif

// How much of that occlusion is applied. 1.0 uses the channel exactly as the
// resource pack authored it; lower it if the pack overdoes the effect.
// Has no effect while PBR_MATERIAL_AO is off.
#define PBR_MATERIAL_AO_STRENGTH 1.0 // [0.25 0.5 0.75 1.0]

// Whether to add the light that scatters through a thin surface, using the
// amount stored in the blue channel of the specular map.
//
// LabPBR splits that channel at 64.5/255: below it the value is porosity, above
// it the material lets light through. Leaves, grass, paper, and similar thin
// materials are what use the upper range, and what the effect adds is the glow
// of a backlit leaf - the light comes through the surface instead of bouncing
// off it, so the brightest side is the one facing away from the sun.
//
// Steadfast already has a cruder version of this for foliage, chosen by block ID
// (see SUBSURFACE_SCATTERING, LEAVES and GROUND_FOLIAGE in materialIDs.glsl,
// and the NdotL remapping in DirectLighting). This option is what makes the
// effect follow the texture instead, so that a pack can mark one leaf or one
// plant as thin, and it is what adds the directional glow on top of the
// existing all-round brightening.
//
// A material with nothing stored in that channel scatters nothing, so a pack
// that does not support this renders exactly as it did before.
//#define PBR_SUBSURFACE
#ifdef PBR_SUBSURFACE
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in diffuse.glsl.
#endif

// How much of that scattered light is added.
//
// 0.7 is the value this effect was tuned at in the pack it was modelled on.
// Raise it for a stronger glow through leaves, lower it if foliage looks like it
// is lit from the inside rather than from the sun.
#define PBR_SSS_STRENGTH 0.7 // [0.0 0.25 0.5 0.7 1.0 1.5 2.0]

// Whether a surface that the resource pack marked as porous gets darker while
// it is wet, which is what makes brick, dirt, wood and the like look soaked
// after rain instead of merely shiny.
//
// LabPBR stores porosity in the lower half of the specular map's blue channel
// (0 to 64 out of 255, where 0 is not porous at all and 64 is fully porous). A
// porous surface is one whose light response comes from scattering inside the
// material rather than off its surface, and water filling those pores takes that
// scattering away - so the surface darkens, and what is left is the wet sheen.
//
// The darkening is scaled by the sky light, which is what keeps it outdoors: a
// torch-lit cellar does not dry out differently from a torch-lit cellar that
// happens to be under a storm. This is the pack's own convention and matches
// what Steadfast already does with rain elsewhere.
//
// On by default. It shows itself in rain, and only on the materials a pack
// marked as porous, so turning it off only matters for a pack that overdoes it.
#define PBR_POROSITY_WETNESS
#ifdef PBR_POROSITY_WETNESS
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in diffuse.glsl.
#endif

// How much darker a fully porous surface gets when it is fully wet and fully
// exposed to the sky. This is the value the effect was tuned at in the pack it
// was modelled on.
const float PBR_WETNESS_DARKENING = 0.66;

// Whether ice and other translucent solids take their surface response from the
// material maps, instead of from the assumption that they reflect nothing.
//
// Ice is drawn by the translucent pass, so it never reached the material model
// in this file: TranslucentLighting gives water a reflectance of 0.1 and gives
// everything else 0.0, which leaves ice with no specular response at all beyond
// the grazing Fresnel that every surface has. With this on, ice reads its
// reflectance and its normal from the resource pack like any other block, and
// the reflections it already had become the reflections of the material the
// pack authored.
//
// Water is deliberately left out of this. Steadfast's water is an animated
// surface whose normal comes from its own wave model, and the 0.1 it uses is a
// documented compromise; a pack's water material describes a thinner and much
// smoother surface than the one being drawn, so mixing the two does not produce
// the water the pack intended either.
//
// On by default. Turn it off to see an icy biome the way the resource pack left
// it.
#define PBR_TRANSLUCENT
#ifdef PBR_TRANSLUCENT
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in lit.fsh and
	// translucent.glsl.
#endif

// Whether the environment a material reflects gets a direction and a roughness,
// instead of being a flat wash of the ambient light.
//
// PbrAmbientSpecular below is a stand-in for image-based lighting that is cheap
// enough to run everywhere, and it is honest about being one: it reflects the
// light around the fragment equally in every direction, so a surface reflects
// exactly the same thing whichever way it faces, and roughness only scales how
// much of it there is. Turning this on asks the sky model for the colour along
// the reflected ray instead, which is what makes a polished surface outdoors
// look like something reflecting a sky rather than like something lit by it.
//
// By itself this reflects the sky and not the world: the reflection is looked up
// in the sky model along the reflected ray, so a metal outdoors picks up the sky
// and anything indoors or underground picks up nothing but its own ambient
// light. PBR_SSR below is what adds the world.
//
// It is applied in the deferred pass rather than where the surface is drawn,
// because that is the first point at which the depth buffer describes a finished
// frame - see the note on PBR_SSR. The material it needs (normal, roughness,
// reflectance) is written into two buffers by the programs that draw surfaces,
// and read back there.
//
// Noticeably more expensive than the term it replaces: one sky model evaluation
// per covered pixel. Off by default for that reason. PBR_REFLECTIONS_STRENGTH is
// the control for how visible it is, and this pack ships with it turned down.
//#define PBR_REFLECTIONS
#ifdef PBR_REFLECTIONS
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in copy_and_fog.fsh.
#endif

// How strong that reflection is. 1.0 is the value it was tuned at.
#define PBR_REFLECTIONS_STRENGTH 0.25 // [0.25 0.5 0.75 1.0 1.5 2.0]

// The same, for a metal.
//
// A metal gets its own because the strength above is not describing metals at
// all. It is there to hold back a wash of environment that used to land on every
// surface in the scene, and a metal is the case where the reflection is the
// material rather than a sheen over it - a held-back metal does not read as a
// restrained one, it reads as a dull one. The reference packs give metals no
// such factor, so 1.0 is the value that matches them.
//
// Turn it down if metals come out too bright in a scene, which is a judgement
// about the scene rather than about the physics.
#define PBR_METAL_REFLECTION_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

// How far a rough surface bends the reflected ray towards its own normal, as a
// fraction of the roughness range.
//
// This defaults to 0.0, which is to say it does nothing, and it should stay
// there. What it does is distort the reflection: a surface of roughness 0.2 has
// its reflected ray pulled a fifth of the way towards the normal, and the
// reflection of anything in front of it arrives shifted and misshapen even
// though the thing reflected was in plain sight.
//
// It was written to stand in for roughness, on the reasoning that a rough
// surface reflects an average of the sky over it and looking straight up is
// that average. The problem is that it is not what roughness does. A GGX lobe
// is centred on the mirror direction and spread around it; bending the centre
// moves the reflection, which no amount of roughness does. The blur is what
// spreads it, and the blur is separate - see PBR_REFLECTION_BLUR.
//
// With the normal map off, a block face is flat and its reflection should be a
// plain mirror. Any remaining distortion is this, which is how it was found.
//
// Raise it and the distortion comes back; there is no reason to.
#define PBR_REFLECTIONS_ROUGHNESS 0.0 // [0.0 0.5 0.75 1.0]

// Whether a reflection may include the world and not only the sky, by tracing
// the reflected ray through the depth buffer.
//
// This is possible here only because Steadfast applies its reflections in the
// deferred pass, after the opaque scene has been drawn and the depth buffer is
// complete. An opaque surface could not trace against the frame it is being
// drawn in, since that frame is still being filled; tracing the previous frame
// instead costs one frame of lag, so whatever has just come into view is not in
// the reflection yet. That is the same compromise the water reflections make,
// and the reason the sea looks right most of the time and briefly wrong when
// you spin around.
//
// A trace can only find what is on screen, so a ray that leaves the view or
// lands on nothing falls back to the sky, which is what the reflection would
// have been without this.
//
// The trace is by a wide margin the most expensive thing in the pack: it runs on
// every smooth pixel, at PBR_SSR_STEPS steps each, whether or not it finds
// anything. It ships on, with PBR_SSR_ROUGHNESS keeping most of a world out of
// it; turn that limit down first, and this option off second.
#define PBR_SSR
#ifdef PBR_SSR
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in copy_and_fog.fsh.
#endif

// The most the reflection may be spread out, in pixels.
//
// A rough surface does not reflect what a mirror reflects: a whole cone of
// directions arrives at the same pixel, and one sharp sample of that cone shows
// the mirror image the surface should not have. Spreading the sample over the
// cone is what makes a brushed or frosted metal read as brushed or frosted
// rather than as a mirror with its colours dimmed, and at 0.0 the reflection is
// as sharp as it is with no material data at all.
//
// The radius depends on roughness and not on distance, which is worth knowing
// before wondering why a distant reflection is not blurrier: a cone of a given
// angle covers about the same number of pixels whatever it lands on, because the
// screen-space size of the cone grows exactly as fast as the thing it spreads
// over shrinks.
//
// Only surfaces the reflection gate lets through pay for this, which is a small
// part of any scene - see PbrReflectionSmoothness. Each of those pays eight
// samples instead of one.
#define PBR_REFLECTION_BLUR 64.0 // [0.0 16.0 32.0 48.0 64.0 96.0]

// How many steps the reflection trace may take.
//
// Only the material reflections use this; the water reflections keep their own
// budget, because spending this many steps on the water and on every smooth
// pixel of the screen are two very different propositions. More steps find more
// hits and refine the ones they find better, and the cost is paid whether or not
// anything is found at all.
#define PBR_SSR_STEPS 24 // [8 12 16 24 32]

// How much sky a surface has to see before it reflects any of it.
//
// This is what keeps sky reflections out of caves and interiors. Minecraft's sky
// light spreads sideways under an overhang and passes straight through glass, so
// a fragment can be lit as if it were outdoors while nothing of the sky is
// actually visible from it - which is what a polished block on the floor of a
// shallow cave reflecting a noon sky looks like. Requiring nearly full sky
// light, and fading in over the last tenth of the range rather than switching on
// at a threshold, is what stops that.
//
// Note the one case this cannot fix: a surface lit through a glass window has a
// sky light of 15, exactly like one standing in the open, and no lighting
// information available here can tell the two apart. Lower this if you would
// rather have reflections indoors and put up with them in caves.
#define PBR_REFLECTION_SKY_MIN 0.9 // [0.0 0.5 0.75 0.85 0.9 0.95 1.0]

// How smooth a surface has to be before it reflects the sky at all.
//
// The reflectance on its own is not a gate: it falls off as a surface gets
// rougher but it never reaches zero, and the ground is always seen at a glancing
// angle, where the Fresnel term rises towards 1.0 whatever the surface is. The
// two together are what put a wash of sky colour over stone and dirt, and what
// made a whole landscape look faintly frosted rather than dull. A surface as
// rough as a stone has no business reflecting the sky, and nothing short of a
// threshold that reaches zero says so.
//
// The curve is Sundial's, from the "diffuse weight" it gives a solid surface in
// its Composite0, which is where the numbers come from: at 0.5 anything rougher
// than about 0.25 in this pack's roughness reflects nothing whatever, and the
// reflection comes in above that as the square root of how far past the
// threshold the surface is. See PbrReflectionSmoothness.
//
// Raise it to restrict reflections to shinier blocks and lower it to let them
// onto duller ones; 0.0 disables the gate and leaves the old fall-off alone.
#define PBR_REFLECTION_SMOOTHNESS_MIN 0.5 // [0.0 0.25 0.5 0.6 0.7 0.8 0.9]



// Replaces the shaded image with a visualisation of the material data, which is
// the quickest way to find out whether a resource pack actually provides what
// an effect needs. If Height shows a flat grey for the block you are looking
// at, that pack has no height channel there and no amount of parallax tweaking
// will produce any displacement.
#define PBR_DEBUG_NONE 0
#define PBR_DEBUG_HEIGHT 1
#define PBR_DEBUG_SMOOTHNESS 2
#define PBR_DEBUG_F0 3
#define PBR_DEBUG_NORMAL 4
#define PBR_DEBUG_MIP 5
#define PBR_DEBUG_TANGENT_NORMAL 6
#define PBR_DEBUG_MATERIAL_AO 7
#define PBR_DEBUG_SUBSURFACE 8
#define PBR_DEBUG_EMISSION 9

// A diagnostic rather than a material view: it draws the values the parallax ray
// march works with, so that a surface where the effect is missing can be told
// apart from a surface where it is merely subtle.
//
//   red   - how far the ray is displaced, in texture coordinates, before the
//           march runs. Black here means the offset itself is (near) zero,
//           which is the frame, the view angle or one of the two caps.
//   green - the displacement the march actually returned. Black with red lit
//           means the offset was fine and the march failed to find a crossing.
//   blue  - how much of the effect this distance is allowed, ie, the distance
//           fade. Black blue means the surface is simply too far away.
#define PBR_DEBUG_PARALLAX 10

// The environment reflection by itself, with the rest of the picture taken away.
//
// It exists because the reflection is the one thing in this pack that cannot be
// judged by looking at the finished image. Everything else can: a normal map
// that is wrong looks wrong, a shadow that is wrong looks wrong. A reflection
// that is being blurred wrongly and a reflection that is being traced wrongly
// both come out looking like a strange reflection, and there is no way to tell
// which from the picture - which is how seven attempts at its blur were made
// without once establishing whether the blur was running at all.
//
// Unlike the others this one is not read by the surface programs: it replaces
// the finished frame in composite1, which is the pass that applies the
// reflection. Turning it on leaves the sky and the terrain as the reflection
// alone, so what is shown is exactly what the reflection contributed, at four
// times its strength so that a faint one can be seen.
#define PBR_DEBUG_REFLECTION 11
#define PBR_DEBUG PBR_DEBUG_NONE // [PBR_DEBUG_NONE PBR_DEBUG_HEIGHT PBR_DEBUG_SMOOTHNESS PBR_DEBUG_F0 PBR_DEBUG_NORMAL PBR_DEBUG_MIP PBR_DEBUG_TANGENT_NORMAL PBR_DEBUG_MATERIAL_AO PBR_DEBUG_SUBSURFACE PBR_DEBUG_EMISSION PBR_DEBUG_PARALLAX PBR_DEBUG_REFLECTION]

// How much of its diffuse response a metal loses, over both the direct light
// and the indirect light around it.
//
// A metal has no diffuse response at all: light either reflects off it or it is
// absorbed, and everything that gives a metal its appearance is in the
// reflection. A surface that keeps some of its diffuse and gains a reflection on
// top does not look like a restrained metal - it looks like a metal with
// something smeared over it, because that is exactly what such a surface is: a
// bright, coloured, blurred film sitting on a body that is still scattering
// light the way a plastic would.
//
// This used to default to half, on the grounds that the pack had no environment
// reflection and a fully metallic surface would be left with its highlight alone
// and read as a black hole in a cave. The pack has had that reflection for a
// while now, and a metal in a lit cave picks up the block light around it
// through PbrAmbientSpecular, so the reason for stopping half-way is gone and
// the halfway value is what the smearing looked like.
//
// 0.0 = metals keep all of their diffuse response (shiny plastic look)
// 1.0 = metals lose their diffuse response entirely (physically correct)
#define PBR_METAL_DIFFUSE 1.0 // [0.0 0.25 0.5 0.75 1.0]

// The main switch. It is defined for the block atlas programs (see PBR_ATLAS in
// the gbuffers wrappers), whose coordinates index into the block atlas grid, and
// for the ones that opt in through PBR_MATERIALS_ANY_TEXTURE - a program whose
// own texture already is the material's texture, so the coordinate indexes it
// directly without needing to know anything about an atlas. The player, its
// armour and whatever it holds are drawn by such a program, and this is how
// Mellow and Sundial give them materials too.
//
// Held items and Distant Horizons terrain deliberately do not opt in: what they
// sample is not the texture their coordinate belongs to.
//
// When neither is defined, every declaration below is removed by the
// preprocessor and no PBR data is read or paid for.
#if (defined(PBR_ATLAS) || defined(PBR_MATERIALS_ANY_TEXTURE)) && PBR_FORMAT != PBR_OFF
	#define PBR_SURFACE

	// Height field shadowing reuses the parallax height sampling, so it needs
	// both switches. Nested rather than combined with defined() so that both
	// macros are referenced with a real #ifdef, which is what registers them as
	// options in the first place.
	#ifdef PBR_PARALLAX
		#ifdef PBR_PARALLAX_SHADOW
			#define PBR_PARALLAX_SHADOWING
		#endif
	#endif

	// Iris reports the PBR format that the resource pack declares in its
	// texture.properties. It cannot be declared from the shader side, so this
	// is purely informational - if the pack says nothing, we still sample and
	// rely on the neutral defaults below.
	#if defined(MC_TEXTURE_FORMAT_LAB_PBR_1_3) || defined(MC_TEXTURE_FORMAT_LAB_PBR)
		#define LABPBR_1_3
	#endif
#endif

// The decoded material properties of a fragment.
struct PbrSurface {
	// Perceptual roughness, where 0.0 is a mirror and 1.0 is fully diffuse.
	float roughness;
	// Reflectance at normal incidence.
	vec3 f0;
	// 1.0 for hardcoded and albedo-based metals, 0.0 for dielectrics.
	float metalness;
	// Which metal, as the byte the specular map's green channel carried: 230-237
	// for the hardcoded ones, 238 for the albedo-based ones, and 0 for a
	// dielectric. metalness above says whether there is a metal here; this says
	// which one, which is what PbrMetalF82 needs for the colour it reflects at a
	// grazing angle. It is carried rather than recomputed because the byte it
	// came from is gone by the time the reflection is applied - the deferred pass
	// reads a reflectance and a roughness, and nothing else.
	float metalID;
	// Emission strength, 0.0 when the material does not emit.
	float emission;
	// 1.0 when f0 has to be taken from the surface albedo rather than from the
	// specular map, which is how LabPBR stores albedo-based metals.
	// PbrResolveAlbedo() folds this in once the surface color is known.
	float albedoMetal;
	// How much of the direct light reaches this fragment through the height
	// field, where 1.0 means nothing is in the way. Only the direct light is
	// affected: the height field does not occlude the sky.
	float selfShadow;
	// The ambient occlusion baked into the material's normal map, where 1.0
	// means the texel is open to the sky and 0.0 means it sits in a crevice.
	// Only indirect light is scaled by it, and only while PBR_MATERIAL_AO is
	// on; see PbrMaterialOcclusion. Surfaces with no material data carry 1.0,
	// which is the neutral value.
	float materialAO;
	// How much of the light that reaches this surface scatters through it
	// instead of reflecting off it, where 0.0 means none of it does. Read from
	// the upper range of the specular map's blue channel, and only used while
	// PBR_SUBSURFACE is on. A surface with no material data carries 0.0, which
	// is what keeps the scattered light out of every other material.
	float sss;
	// How porous this material is, from 0.0 (not porous) to 1.0 (fully porous),
	// normalised from the lower half of the same channel as sss above. Only used
	// while PBR_POROSITY_WETNESS is on, and 0.0 for a surface with no material
	// data.
	float porosity;
};

// The neutral material: fully rough, no specular reflection, no emission,
// nothing in the way of the light, and no occlusion. This is what lighting
// paths without PBR data use, and it reproduces Steadfast's original
// appearance exactly.
PbrSurface PbrNone() {
	return PbrSurface(1.0, vec3(0.0), 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0);
}

// The factor that the indirect lighting is scaled by for this fragment.
//
// This is a function rather than a plain field of PbrSurface so that the
// strength control and the "this surface has no material data" case live in one
// place. PbrNone() carries an occlusion of 1.0, which makes the whole thing the
// identity, so every lighting path that is not a block atlas surface keeps the
// original rendering untouched. With PBR_MATERIAL_AO off, the compiler removes
// the multiplication entirely.
//
// Declared outside the PBR_SURFACE guard below on purpose: the struct and this
// helper have to exist for every program, if only so that the non-PBR callers
// can pass PbrNone() through them.
float PbrMaterialOcclusion(PbrSurface pbr) {
	#ifdef PBR_MATERIAL_AO
		return mix(1.0, pbr.materialAO, PBR_MATERIAL_AO_STRENGTH);
	#else
		return 1.0;
	#endif
}

// Whether a sample from the specular atlas carries no material data at all.
//
// Where a sprite has no specular map - which is the normal state of affairs for
// anything a resource pack does not cover, modded foliage and grass included -
// the atlas holds whatever it was built with, and both colours it can be are
// meaningless as materials:
//
//   - Black means no reflectance, no scattering and no porosity.
//   - White means total reflectance on every channel at once, which is a
//     material that reflects everything, scatters everything and is porous
//     everywhere - not something a pack authors.
//
// The alpha is meaningless too, whichever end of the range the atlas left it at.
// Emission happens to survive that on its own: a missing sprite reads as
// transparent black, and LabPBR defines an alpha of zero as "emits nothing".
// The porosity and the scattering do not - they read the blue channel - so
// telling an empty atlas region apart from a real material is what the two
// rejected colours above are for. Rejecting both with any alpha, rather than
// only the opaque pair, is what keeps a block the pack never covered from
// scattering all of the light or darkening as though it were porous everywhere.
//
// The price is that a material which really is fully emissive and has exactly
// zero reflectance, zero scattering and zero porosity is read as having no data
// instead, and the same for a material that is exactly white on all three. Both
// are indistinguishable from an empty atlas region, so a pack that authors them
// has to move one of those three channels off the extreme.
bool PbrMissingSpecular(vec4 specularSample) {
	vec3 rgb = specularSample.rgb;

	float maxChannel = max(max(rgb.r, rgb.g), rgb.b);
	float minChannel = min(min(rgb.r, rgb.g), rgb.b);

	// Black, with any alpha: nothing recorded on any channel.
	if (maxChannel < 1.0e-3) {
		return true;
	}

	// White, with any alpha: every channel at its maximum at once.
	if (minChannel > 0.999) {
		return true;
	}

	return false;
}

// Deliberately not named PI, as the sky and water code both declare local
// constants with that name.
const float PBR_PI = 3.14159265359;

// The weights used wherever a reflectance has to be reduced from a colour to a
// single number. Rec. 709, matching what the rest of the pack uses for luma.
const vec3 PBR_LUMINANCE = vec3(0.2126, 0.7152, 0.0722);

// Schlick's approximation of the Fresnel term: reflectance rises towards 1.0 at
// grazing angles.
//
// Declared out here rather than next to the BRDF below, which is where it
// belongs thematically, because the environment reflection is applied in the
// deferred pass - a program that has no block atlas and therefore no
// PBR_SURFACE - and needs this. Everything it depends on is a constant.
vec3 F_Schlick(vec3 f0, float u) {
	float f = 1.0 - u;
	float f2 = f * f;
	float f5 = f2 * f2 * f;
	return f0 + (vec3(1.0) - f0) * f5;
}

#ifdef PBR_SURFACE

// Declared as plain, top-level uniforms on purpose. Iris and OptiFine detect
// that a shader pack wants PBR material data by scanning its source for these
// two declarations, and only then build and bind the normal and specular
// atlases.
uniform sampler2D normals;
uniform sampler2D specular;

#ifdef PBR_POROSITY_WETNESS
	// The wetness of the terrain, where 0.0 is dry and 1.0 is soaked.
	//
	// Iris and OptiFine both track this from the weather and provide it without
	// anything being declared in the pack's properties, so this is only a
	// declaration and not a request. Declared inside the feature's own guard so
	// that it is not paid for in programs that never compile the code below.
	//
	// The cloud layer wants the same value - it uses it for how thick the clouds
	// are - so the macro tells it that this has already been declared.
	#define WETNESS_DECLARED
	uniform float wetness;
#endif

// The screen-space derivatives that the material decoding needs.
//
// These have to be taken once, unconditionally, at the top of main(): dFdx and
// dFdy have undefined results after a discard or in non-uniform control flow,
// and a texture sample that relies on implicit derivatives (which is to say,
// any sample outside the parallax ray march) has the same restriction. Passing
// them around also lets the parallax march sample with an explicit level of
// detail from inside its loop.
struct PbrGradients {
	vec2 ddxTexCoord;
	vec2 ddyTexCoord;
	vec3 ddxPosition;
	vec3 ddyPosition;
	// The mip level the material maps would be sampled at. Recorded here because
	// it cannot be recovered from the gradients once they have been scaled, and
	// the normal map's fade is driven by it.
	float lod;
};

// The mip level a texture with these gradients is sampled at.
//
// The atlas size comes from the sampler itself, so this makes no assumption
// about the resource pack. Note that the level depends on the texture's size as
// well as on distance, which is why anything that goes wrong at a particular
// mip level moves closer as the resource pack gets sharper.
float PbrMaterialLOD(PbrGradients gradients) {
	vec2 atlasSize = vec2(textureSize(normals, 0));
	vec2 ddx = gradients.ddxTexCoord * atlasSize;
	vec2 ddy = gradients.ddyTexCoord * atlasSize;

	return log2(max(max(length(ddx), length(ddy)), 1.0e-8));
}

// Scales the gradients so that no sample lands deeper than PBR_MATERIAL_MAX_LOD.
//
// This deliberately depends on nothing but the option: an earlier version of
// this used the sprite's bounds to allow deeper mips in the middle of a sprite,
// but fell back to doing nothing when those bounds were not usable, and a fix
// that can silently do nothing is worse than no fix at all.
//
// The position gradients are left alone - they are the true derivatives of the
// surface, and the tangent frame needs them unmodified.
PbrGradients PbrMaterialGradients(PbrGradients gradients) {
	float scale = exp2(
		min(gradients.lod, PBR_MATERIAL_MAX_LOD) - gradients.lod);

	return PbrGradients(
		gradients.ddxTexCoord * scale,
		gradients.ddyTexCoord * scale,
		gradients.ddxPosition,
		gradients.ddyPosition,
		gradients.lod);
}

PbrGradients PbrSampleGradients(vec2 texCoord, vec3 position) {
	PbrGradients gradients = PbrGradients(
		dFdx(texCoord),
		dFdy(texCoord),
		dFdx(position),
		dFdy(position),
		0.0);

	gradients.lod = PbrMaterialLOD(gradients);

	return gradients;
}

// The metal ID the albedo-based metals carry, since they have no byte of their
// own to carry - LabPBR gives 238-255 all the same meaning.
//
// 238 rather than 255 so that it sits just past the hardcoded table, which is
// the range it belongs to, and is a constant rather than a #define because it is
// not a setting: nothing about it is worth offering to a user.
const float PBR_METAL_ALBEDO = 238.0;

// F0 values for the LabPBR hardcoded metals, looked up by the byte value stored
// in the green channel of the specular map.
//
// This is a branch, and the two comparisons in the fallback path are the cost
// of a material not using the feature, which is why the common dielectric case
// never reaches this function at all.
vec3 PbrMetalF0(int metalID) {
	if (metalID == 230) return vec3(0.78, 0.77, 0.74); // Iron
	if (metalID == 231) return vec3(1.00, 0.90, 0.61); // Gold
	if (metalID == 232) return vec3(1.00, 0.98, 1.00); // Aluminum
	if (metalID == 233) return vec3(0.77, 0.80, 0.79); // Chrome

	if (metalID == 234) return vec3(1.00, 0.89, 0.73); // Copper
	if (metalID == 235) return vec3(0.79, 0.87, 0.85); // Lead
	if (metalID == 236) return vec3(0.92, 0.90, 0.83); // Platinum
	if (metalID == 237) return vec3(1.00, 1.00, 0.91); // Silver

	return vec3(0.0);
}

// Builds a tangent frame around the surface normal from the screen-space
// derivatives of the world position and the texture coordinate. This is the
// technique from Christian Schüler's "Normal Mapping Without Precomputed
// Tangents".
//
// This is the fallback frame, used for geometry that carries no tangent of its
// own - Minecraft's entity format has none, and some mods leave the attribute at
// zero. Everywhere else PbrAttributeFrame below is preferred, because this one
// depends on differentiating a position that had to be reconstructed from the
// depth buffer first, and the depth buffer's precision runs out at a distance.
//
// Note that it derives the frame from the UV mapping, which is also why it stays
// correct for modded models that Steadfast knows nothing about - a modded model
// that supplies no tangent still gets a usable frame this way.
//
// The frame is also what the parallax mapping uses to turn a view ray into a
// displacement along the texture coordinates, so it is built whenever either
// feature needs it. When neither does, the compiler discards the whole thing.
mat3 PbrCotangentFrame(vec3 worldNormal, PbrGradients gradients) {
	vec3 dp1 = gradients.ddxPosition;
	vec3 dp2 = gradients.ddyPosition;
	vec2 duv1 = gradients.ddxTexCoord;
	vec2 duv2 = gradients.ddyTexCoord;

	// Project the position derivatives onto the plane of the surface and pair
	// them with the texture coordinate derivatives. The results are
	// perpendicular to the normal by construction, so this replaces the
	// Gram-Schmidt orthogonalization that a precomputed tangent would need.
	vec3 dp2perp = cross(dp2, worldNormal);
	vec3 dp1perp = cross(worldNormal, dp1);

	vec3 tangent = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 bitangent = dp2perp * duv1.y + dp1perp * duv2.y;

	// Normalize both vectors with a single reciprocal square root.
	float maxLength = max(dot(tangent, tangent), dot(bitangent, bitangent));

	if (maxLength < 1.0e-12) {
		// Degenerate UV mapping (a zero-area triangle, or a fragment where the
		// derivative was lost). Fall back to an arbitrary but consistent frame
		// so that we never produce NaNs.
		vec3 helper = abs(worldNormal.y) < 0.99
			? vec3(0.0, 1.0, 0.0)
			: vec3(1.0, 0.0, 0.0);

		tangent = normalize(cross(helper, worldNormal));
		return mat3(tangent, cross(worldNormal, tangent), worldNormal);
	}

	float invLength = inversesqrt(maxLength);
	return mat3(tangent * invLength, bitangent * invLength, worldNormal);
}

#ifdef PBR_TANGENT_ATTRIBUTE
	// The same frame, built from the tangent the geometry itself carries.
	//
	// worldTangent is that tangent in world space, with the handedness in w, and
	// it is degenerate for geometry that has no tangent at all - Minecraft's
	// entity format does not carry one, and some mods leave it at zero. That
	// case falls back to the derivative frame above rather than producing a
	// frame full of NaNs, so that a mob or a modded model still gets the
	// material response it can get.
	//
	// The handedness exists because a tangent alone does not say which way the
	// bitangent points; it is what the loader stores in w for exactly this
	// purpose. For Minecraft's texture convention the result is the direction
	// the texture's V axis increases in, which is the axis the normal map's
	// green channel describes, so the green channel lands on it without a flip.
	mat3 PbrAttributeFrame(
		vec3 worldNormal,
		vec4 worldTangent,
		PbrGradients gradients
	) {
		vec3 tangent = worldTangent.xyz;

		if (dot(tangent, tangent) < 1.0e-8) {
			return PbrCotangentFrame(worldNormal, gradients);
		}

		tangent = normalize(tangent);

		vec3 bitangent = cross(worldNormal, tangent) * worldTangent.w;

		return mat3(tangent, bitangent, worldNormal);
	}
#endif

#ifdef PBR_PARALLAX
	// How far the height field is displaced, and how far the effect reaches.
	// Shared by the view ray march and the height field shadowing so that the
	// two cannot drift apart.
	float PbrParallaxStrength(vec3 cameraRelativePos) {
		return clamp(
			(PBR_PARALLAX_DISTANCE - length(cameraRelativePos))
				/ (PBR_PARALLAX_DISTANCE * 0.25),
			0.0,
			1.0);
	}

	// An axis whose length squared is below this is one the screen-space
	// derivatives could not resolve: what comes out of the Jacobian for it is
	// then not a short direction but noise, so it is dropped rather than used.
	const float MIN_AXIS_SQUARED = 1.0e-10;

	// Inverts the texture coordinate Jacobian to get the world-space direction
	// and size of one unit of texture coordinate along each axis.
	//
	// It is asked for both and only the direction is used, because the two do not
	// stand or fall together here: a vector that came out pointing the wrong way
	// is one whose direction is still describable, while a vector that came out
	// the wrong length has a length that nothing can trust. That length is what
	// the caller stopped dividing by - see the note on the offset in
	// PbrParallaxUV - and it is measured here anyway, because an axis that is
	// nearly zero has no direction to give either, which is what the guard below
	// reads.
	//
	// Returns false only when both axes are dropped, ie, when there is no
	// direction left to trace along at all. See the note inside the function.
	//
	// That is a weaker promise than it sounds, and the one caller has to read it
	// as the weaker thing it is: one axis on its own does not say which way the
	// other one runs, so what PbrParallaxUV needs is a *pair* of them, and it
	// tests the two lengths itself rather than trusting this return value. A
	// dropped axis is exactly zero, and the caller normalizes the axes - so
	// taking this return value at face value there would put a NaN in the ray.
	//
	// The two are the route the depth used to take, which is why they are worth
	// reading: a distance in blocks was turned into texture coordinates through
	// these axes, so the axes come from screen-space derivatives, a face whose
	// mapping those derivatives cannot resolve had an axis dropped here or left
	// enormous, and the depth that came out was zero on some faces and far past
	// the surface on others with no change to either parallax setting.
	// The half of that route that did the dividing - projecting a displacement
	// measured in blocks onto these axes - went with the depth that fed it. The
	// axes stayed, because their direction is still what says which way the
	// texture's u and v point, and the tangent frame does not. See PbrParallaxUV.
	bool PbrTexCoordAxes(
		PbrGradients gradients,
		out vec3 dPdu,
		out vec3 dPdv
	) {
		float determinant = gradients.ddxTexCoord.x * gradients.ddyTexCoord.y
			- gradients.ddxTexCoord.y * gradients.ddyTexCoord.x;

		if (abs(determinant) < 1.0e-12) {
			dPdu = vec3(0.0);
			dPdv = vec3(0.0);
			return false;
		}

		dPdu = (gradients.ddyTexCoord.y * gradients.ddxPosition
			- gradients.ddxTexCoord.y * gradients.ddyPosition) / determinant;

		dPdv = (gradients.ddxTexCoord.x * gradients.ddyPosition
			- gradients.ddyTexCoord.x * gradients.ddxPosition) / determinant;

		// A determinant that is not zero is not enough on its own. A mapping can
		// flatten one axis almost to nothing while keeping the other, which leaves
		// the determinant perfectly finite and the vectors above enormous. What
		// divided by them again and turned that into a displacement was the old
		// conversion of a depth in blocks into texture coordinates, and the offset
		// then came out massive: the march ran far past the crossing it should
		// have found, and the surface read as one layer too deep or simply as
		// broken - which is what "part of the face is missing" turned out to be
		// when it was looked at closely: the depth was not absent, it had been
		// walked past. Which faces this happens on depends on how their texture
		// happens to be laid out, so it shows up as particular sides of a block
		// misbehaving rather than as a general fault.
		//
		// That conversion is gone and nothing divides by either axis any more, so
		// what is left of the hazard is the direction. An axis that came out
		// enormous still points the right way; one that came out flat is a
		// direction that points nowhere at all, and a pair of axes is what says
		// which way the texture's own u and v run. That is what the caller tests
		// for below.
		//
		// What this used to do about it was give up on the whole face: both axes
		// were zeroed and the caller returned the coordinate it started with. That
		// does remove the overshoot, but it throws the face's depth away with it,
		// and it leaves nothing to tell a face whose resource pack has no height
		// data from one whose mapping simply could not be read.
		//
		// So the axes are dropped one at a time instead. The ones that could be
		// resolved still describe the surface - they are the same vectors they
		// always were, so a face with both axes intact is untouched by this - and
		// one that could not is dropped whole rather than used as a short
		// direction that points nowhere in particular. The caller then has a zero
		// where an axis was, which is the signal it reads as "this face's mapping
		// could not be read" and answers with the tangent frame.
		if (dot(dPdu, dPdu) < MIN_AXIS_SQUARED) {
			dPdu = vec3(0.0);
		}

		if (dot(dPdv, dPdv) < MIN_AXIS_SQUARED) {
			dPdv = vec3(0.0);
		}

		return dot(dPdu, dPdu) + dot(dPdv, dPdv) > 0.0;
	}

	// Whether a face's sprite bounds say anything usable at all.
	//
	// spriteBounds is xy: the centre of the sprite, zw: half of its size, both
	// in the same texture coordinate space as texCoord. A half-size of zero is
	// what the geometry that has no sprite of its own reports - the player, its
	// armour and whatever it holds, whose texture coordinate already indexes
	// its own texture rather than a sheet (see lit.vsh) - and a half-size above
	// half a texture cannot describe a sprite in any atlas.
	//
	// The test is written once here rather than at each of the callers because
	// both the view ray march and the height field shadowing need it, and
	// because a face without bounds has no local box to march in - see
	// PbrSpriteLocal. What the callers do about it is pass the coordinate
	// through untouched, which is what leaves the hand and the entities alone.
	bool PbrSpriteUsable(vec4 spriteBounds) {
		vec2 halfSize = spriteBounds.zw;

		return all(greaterThan(halfSize, vec2(0.0)))
			&& all(lessThanEqual(halfSize, vec2(0.5)));
	}

	// Maps a texture coordinate into the 0-1 box of the sprite it belongs to,
	// where 0 is one edge of that sprite and 1 is the other.
	//
	// This is the space both of the ray marches below run in, and it is one of
	// the two things taken from Sundial-Lite (libs/Parallax.glsl, calculateParallax,
	// lines 168-223) - the other is the growing step in PbrParallaxUV. Sundial
	// gets to the same place from the other side: it keeps atlas coordinates and
	// scales them by quadSize, the reciprocal of the sprite's size, as it marches.
	// Either way one unit of the local box is one sprite, whatever the atlas
	// resolution or the sprite's size in pixels happens to be.
	//
	// What Sundial's boundary treatment does next is *not* taken from it, and this
	// is the one place the march deliberately parts company with the reference:
	// Sundial wraps a sample that leaves the sprite round to its far side, and
	// this pack does not - see PbrFadeOffsetToSprite. The local box is still the
	// space; it is what happens at the edge of it that differs.
	//
	// Working here rather than in atlas coordinates is what makes the rest of
	// the march resolution-independent. A displacement measured in atlas
	// coordinates is a different fraction of the surface in a 256-wide atlas
	// than in a 4096-wide one, and a different fraction again for a sprite that
	// covers two blocks rather than one; measured against the sprite, it is the
	// same fraction of the material in every case.
	//
	// Callers must have checked PbrSpriteUsable first: this divides by the
	// sprite's size.
	vec2 PbrSpriteLocal(vec2 texCoord, vec4 spriteBounds) {
		return (texCoord - (spriteBounds.xy - spriteBounds.zw))
			/ (2.0 * spriteBounds.zw);
	}

	// Maps a coordinate in that local box back into the atlas, holding anything
	// outside the box at the box's own edge.
	//
	// This wrapped, and the wrap was this pack's rule until 2026-09-22, when it
	// was replaced with this by the pack's author. The reason is material the face
	// does not have: a ray that walks off the right edge of a sprite and comes
	// back in on the left is reading the far side of a feature that belongs where
	// it left, and where a sprite's two edges are not the same height - a door's
	// window in its frame, a brick's mortar line, a plank's seam - the geometry
	// the fragment is drawing and the texel it reads disagree. That is how a
	// doorway's window was being read through the frame beside it. Stopping at the
	// edge is the smaller lie, because a sample that stays put never claims to be
	// the surface somewhere it has not been.
	//
	// Clamping on its own is what this march used to do and what it was taken out
	// for: every sample that leaves the sprite repeats its border texel, so the
	// outermost strip of the face freezes there and the parallax visibly stops, as
	// if the surface had a flat rim. The fade in PbrParallaxUV is what answers
	// that, and it is why this is a safety net rather than the mechanism: the
	// offset is scaled down by the room the fragment has left, so a ray arrives at
	// this boundary with no displacement remaining and the two effects cancel at
	// the edge instead of meeting it. Whatever the arithmetic above this does,
	// what comes back from here is inside the fragment's own sprite.
	//
	// Callers must have checked PbrSpriteUsable first.
	vec2 PbrClampToSprite(vec2 localCoord, vec4 spriteBounds) {
		vec2 halfSize = spriteBounds.zw;
		vec2 clamped = clamp(localCoord, vec2(0.0), vec2(1.0));

		return spriteBounds.xy - halfSize + clamped * (2.0 * halfSize);
	}

	// The offset, scaled down to what this fragment has room for before its sample
	// would leave the sprite.
	//
	// This is the pack's rule as of 2026-09-22, set by its author: a sample that
	// would leave the sprite is not wrapped round to the other side of it, which
	// is what both marches used to do. Neither is it enough to stop the sample at
	// the edge, because a ray clamped over the last stretch of its travel freezes
	// the whole edge strip of the face at one texel - the flat rim the wrap was
	// brought in to get rid of, and no improvement on it. Instead the displacement
	// is scaled down by exactly the room that is there, so it shrinks to nothing
	// as the ray reaches the edge and the two meet at the boundary without either
	// being visible. PbrClampToSprite is the backstop for whatever is left after
	// this: with the offset faded, nothing should reach it, and if the arithmetic
	// above ever does, the sample still stays inside the face's own material.
	//
	// The room is measured from the fragment's own local coordinate and taken per
	// axis, and the smaller of the two axes decides, because the ray has to fit in
	// both. The sign of each component says which of that axis's two edges the
	// sample is heading for, which is the distance it is measured against. A
	// fragment with no room at all - one already on the boundary of its box, which
	// is what a face whose box collapsed to a line reports - comes out at zero and
	// is drawn undisplaced on its own texel rather than sliding along the edge.
	//
	// Shared by the view ray and the height field shadow for the reason
	// PbrParallaxStrength is: one height field, one boundary, and two rules for it
	// would put the shadow halfway out of the face its lighting is measured on.
	vec2 PbrFadeOffsetToSprite(vec2 localCoord, vec2 localOffset) {
		vec2 room = localCoord;

		if (localOffset.x > 0.0) {
			room.x = 1.0 - localCoord.x;
		}

		if (localOffset.y > 0.0) {
			room.y = 1.0 - localCoord.y;
		}

		float reach = 1.0;

		if (abs(localOffset.x) > 1.0e-8) {
			reach = min(reach, room.x / abs(localOffset.x));
		}

		if (abs(localOffset.y) > 1.0e-8) {
			reach = min(reach, room.y / abs(localOffset.y));
		}

		// Clamped at one, so an offset that already fits is left exactly as it was:
		// that is every fragment far enough from its box's edges, which is most of
		// every face.
		return localOffset * clamp(reach, 0.0, 1.0);
	}

	// One texel of the height channel, held inside the fragment's own sprite.
	//
	// This is the rule above applied to each of the four corners of a bilinear
	// sample rather than once to the sample coordinate, because a bilinear sample
	// reaches half a texel past the coordinate in every direction and it is the
	// corners, not the coordinate, that can leave the sprite.
	//
	// What gets clamped is the *texel index* rather than the coordinate, and those
	// are not the same thing: a coordinate held at the sprite's far edge sits
	// exactly on that edge, and flooring it there lands one texel past the
	// sprite's last - which is the neighbouring block's material, the leak this
	// exists to prevent. Clamping the index is exact, and it is what makes the
	// corner fetches safe with nothing leaving the sprite.
	//
	// Callers must have checked PbrSpriteUsable: this divides by the sprite's
	// size, and a face with no sprite of its own has no box to hold a texel in.
	// See the fallback in PbrHeight for what such a face gets instead.
	float PbrHeightTexel(vec2 texCoord, vec4 spriteBounds, vec2 atlasSize) {
		vec2 count = spriteBounds.zw * 2.0 * atlasSize;
		vec2 first = floor((spriteBounds.xy - spriteBounds.zw) * atlasSize);

		vec2 texel = clamp(
			floor(texCoord * atlasSize), first, first + count - 1.0);

		return texelFetch(normals, ivec2(texel), 0).a;
	}

	// The height channel at a coordinate, interpolated between the four texels
	// around it by hand.
	//
	// This exists because the atlas cannot be relied on to interpolate it. A block
	// atlas is sampled with a nearest filter as it is magnified - that is what
	// keeps a block's texels sharp, and it is the same setting the material maps
	// are built and sampled under - so one fetch of this channel is a *point*
	// sample, and a resource pack that draws a slope into its height channel is
	// read back as a staircase from one texel to the next rather than as the
	// slope. The march then traces that staircase: the crossing it finds sits on a
	// step, so as the view moves the displaced coordinate jumps by the height of
	// that step and the fetch lands on a different texel all at once. That jump is
	// what the flicker on an ordinary block surface is made of.
	//
	// Two settings look like they should already fix that, and it is worth being
	// exact about why neither does, because the reference packs describe them as
	// if they did:
	//
	//   - The layer count decides only how wide the interval handed to the
	//     refinement is, so more layers resolve the staircase *better* - as a
	//     denser set of finer steps. It re-arranges this error rather than
	//     removing it, which is why the same artifact reads as a few bands at a
	//     low count and as fine grain at a high one.
	//   - The refinement converges on the crossing of whatever field it is given,
	//     to a 2^-PBR_PARALLAX_REFINE fraction of the interval. Given a staircase
	//     it therefore resolves the staircase exactly, which is as faithful a
	//     rendering of the wrong thing as it is possible to make. It cannot
	//     smooth a step, and no number of steps in it can.
	//
	// Which is why the interpolation belongs here rather than in the march.
	// Measured on SPBR-21_2's own height channels at a 45 degree view, a single
	// fetch leaves 0.38 texel steps in the displaced coordinate where this leaves
	// 0.001, and the per-pixel roughness of the material sampled at that
	// coordinate comes out four to fifteen times the undisturbed surface's with
	// the single fetch - how much depending on how close the surface is - and
	// level with it here.
	//
	// The arithmetic is the hardware's own - the two texel centres either side of
	// the coordinate, mixed by the fraction of the coordinate between them - so on
	// a resource pack whose atlas *is* filtered linearly this reproduces the sample
	// the hardware would have taken, and the only thing it costs there is the
	// work. Where the atlas is nearest it supplies the interpolation that was
	// missing either way. It cannot be worse in either case, which is the property
	// that makes it worth doing without knowing which of the two this pack is
	// running against.
	//
	// What it deliberately does not do is ask for a deeper mip level, which is the
	// cheaper way to the same blur. A mip level is chosen per sample, so it cannot
	// be kept inside a sprite: a deeper level mixes in the neighbouring block's
	// material, which is the failure PBR_MATERIAL_MAX_LOD is set to 0 to avoid.
	// Holding four corners inside the sprite individually is what a mip level
	// cannot express, and it is the whole of the reason this costs four fetches
	// instead of one.
	//
	// Sundial's SMOOTH_PARALLAX is this same construction - heightGather and
	// bilinearHeightSample, libs/Parallax.glsl:61-80 - and it is on by default
	// there; its settings menu describes it as making the parallax show a slope
	// rather than individual cubes, which is exactly the step this removes.
	//
	// A textureGather would fetch the same four texels in one instruction and is
	// deliberately not used: its footprint is the 2x2 block of texels around the
	// coordinate as the hardware picks it, with no way to hold a corner inside the
	// sprite, so it would bring the bleed back at every sprite's edge - the one
	// thing the four separate fetches exist to prevent.
	float PbrHeightBilinear(vec2 texCoord, vec4 spriteBounds) {
		vec2 atlasSize = vec2(textureSize(normals, 0));
		vec2 texelSize = 1.0 / atlasSize;

		// The two texel centres that straddle the coordinate - the same pair, and
		// the same weight between them, that a linear filter uses. Adding half a
		// texel to the lower one lands exactly on the upper one's centre, so the
		// four corners below are a proper 2x2 block and the mix is a proper
		// bilinear.
		vec2 lower = texCoord - 0.5 * texelSize;
		vec2 upper = texCoord + 0.5 * texelSize;
		vec2 weight = fract(lower * atlasSize);

		float lowerLeft = PbrHeightTexel(
			vec2(lower.x, lower.y), spriteBounds, atlasSize);
		float lowerRight = PbrHeightTexel(
			vec2(upper.x, lower.y), spriteBounds, atlasSize);
		float upperLeft = PbrHeightTexel(
			vec2(lower.x, upper.y), spriteBounds, atlasSize);
		float upperRight = PbrHeightTexel(
			vec2(upper.x, upper.y), spriteBounds, atlasSize);

		return mix(
			mix(lowerLeft, lowerRight, weight.x),
			mix(upperLeft, upperRight, weight.x),
			weight.y);
	}

	// Samples the height channel of the normal map, interpolated between the four
	// texels around the coordinate by hand - see PbrHeightBilinear above for why
	// that is not something the atlas can be asked to do.
	//
	// A height of exactly zero is read as the reference height instead of as the
	// deepest point. This follows Sundial, which clamps it the same way in all
	// four places it reads a height (Parallax.glsl:124, 182, 199, 214), and it is
	// the one substantive difference between its march and this one. What its
	// picture of a door looks like was not verified here - only that its code
	// reads a zero this way and this pack's did not.
	//
	// LabPBR does say that 0 is the deepest point a height field can reach, and
	// on a texel that has a material that is what it means. The problem is the
	// texels that have no material at all: the transparent pixels a resource pack
	// keeps inside a cutout sprite, of which a door's window is one. Those have
	// no height to report and report 0 for the same reason a missing map reports
	// 0 everywhere, and the two cases cannot be told apart from the value alone.
	//
	// Which of the two readings the march gets decides what it does with such a
	// texel, and it decides it completely. Read as "deepest" it is a pit the ray
	// is guaranteed to fall into: the march's last layer sits below zero whatever
	// the height there is, so a ray that reaches one is caught by it, and the
	// coordinate it returns is inside the window - where the albedo is
	// transparent, the alpha test throws the fragment away, and the sky shows
	// through the middle of the door. Read as "flat" the same texel is a wall the
	// ray stops at the near edge of, half a texel into the wood.
	//
	// The cost is one texel of depth on a resource pack that really does draw the
	// bottom of a pit as exactly 0, which is the trade Sundial makes as well.
	//
	// The single fetch below is reached in two cases, and they are different
	// things wearing the same shape. With PBR_PARALLAX_SMOOTH on it is the
	// fallback for a fragment with no sprite to interpolate inside, which is the
	// hand and the entities: a face drawn through PBR_MATERIALS_ANY_TEXTURE
	// reports a zero half-size (see lit.vsh), and four corners cannot be held
	// inside a box that is not there. Exactly one of this function's six callers
	// reaches it that way - PbrParallaxShadow's first sample, which is taken
	// before that function's own bounds check - and what it gets there is the same
	// undecoded height it has always got. The others have all checked by then, and
	// a face without bounds never reaches the march at all (see PbrParallaxUV).
	// With the option off it is the whole of the sample instead, which not only
	// reads the pack's hard edges exactly as they were drawn but takes the
	// interpolation and its four fetches out of the program entirely.
	float PbrHeight(vec2 texCoord, PbrGradients gradients, vec4 spriteBounds) {
		float height;

		#ifdef PBR_PARALLAX_SMOOTH
			// Interpolated, wherever there is a sprite to interpolate inside. A
			// face with no sprite of its own - the hand and the entities, which
			// report a zero half-size - has no box to hold four corners in, and
			// takes the single fetch below like everything else.
			if (PbrSpriteUsable(spriteBounds)) {
				height = PbrHeightBilinear(texCoord, spriteBounds);
			} else {
				height = textureGrad(
					normals,
					texCoord,
					gradients.ddxTexCoord,
					gradients.ddyTexCoord).a;
			}
		#else
			// Straight from the atlas. This is the whole of the sample and not a
			// fallback, and it is what keeps the option free to turn off: with the
			// block above compiled out, nothing calls the interpolating functions
			// at all, so the driver discards them and their four fetches per
			// sample are not paid for.
			height = textureGrad(
				normals,
				texCoord,
				gradients.ddxTexCoord,
				gradients.ddyTexCoord).a;
		#endif

		return height + clamp(1.0 - height * 1.0e10, 0.0, 1.0);
	}
#endif

// Returns the texture coordinate to sample the material from, displaced by the
// height field along the view ray.
//
// This is parallax occlusion mapping: rather than displacing geometry (which we
// cannot do, as the depth buffer has already been written by the time this
// runs), it walks along the view ray in layers and finds where the ray passes
// below the surface. The result is that deep parts of the texture appear to sit
// further back than shallow ones.
//
// Without this, a height field can only be faked by shifting the whole surface
// uniformly, which does not produce occlusion between the near and far parts of
// the surface and therefore does not read as depth at all.
//
// The march itself follows Sundial-Lite's calculateParallax
// (libs/Parallax.glsl, lines 168-223). Its structure, and what came with it:
//
//   - The ray runs in the sprite's own 0-1 box rather than in atlas
//     coordinates, so that a displacement is always the same fraction of the
//     material. See PbrSpriteLocal.
//   - The step grows from small to large as the ray descends, by the fixed
//     increment 2 / PBR_PARALLAX_STEPS. A step that grew linearly would make
//     the ray's depth depend on the layer count; this way the layers sum to the
//     full depth range whatever that count is, which is what turns the step
//     count into a quality knob instead of a second depth knob.
//   - The depth is measured relative to the sprite, which is the same as
//     Sundial's * quadSize and takes the screen-space derivatives out of the
//     depth entirely. See PBR_PARALLAX_DEPTH for what that fixed.
//   - The offset is faded to the room the fragment has left before a sample would
//     leave the sprite, which is this pack's own rule rather than one taken from
//     the reference: it wrapped, and the reason this does not is set out in
//     PbrFadeOffsetToSprite.
//
// What was deliberately not taken from it is the refinement: this pack bisects
// between the two layers that bracket the crossing, with PBR_PARALLAX_REFINE
// deciding how many times, and that is left as it was.
vec2 PbrParallaxUV(
	mat3 frame,
	vec3 cameraRelativePos,
	vec2 texCoord,
	PbrGradients gradients,
	// xy: the centre of this face's sprite, zw: half of its size.
	vec4 spriteBounds,
	// How far the ray was displaced before the march ran, in texture
	// coordinates. Nothing reads this outside PBR_DEBUG_PARALLAX; it exists so
	// that the diagnostic can show the offset and the displacement separately,
	// which is what tells a zero offset apart from a march that found nothing.
	out float offsetLength
) {
	offsetLength = 0.0;

	#ifndef PBR_PARALLAX
		return texCoord;
	#else
		#ifdef PBR_HAND_ITEMS
			// The hand traces badly and is left out of this one thing.
			//
			// PBR_HAND_ITEMS is only ever defined by gbuffers_hand's own two
			// shaders, so this is the hand and nothing else - no new option, and
			// nothing to keep in sync between stages.
			//
			// The reason is that a held block answers to neither of the two things
			// the trace needs: its view ray comes from a projection the mod scales
			// by MC_HAND_DEPTH rather than the world projection the rest of this
			// file assumes, and mc_midTexCoord - the attribute that says where a
			// face's sprite is - is terrain only, so the bounds below are not a
			// sprite's bounds at all. What came out was a smear laid diagonally
			// across the surface. See PBR_PORTING.md §54.
			//
			// Only the displacement is skipped. The material decode, the normal
			// map and the height field's self shadow are all left alone, so a held
			// block still reads as the material it is made of - it simply has no
			// parallax depth of its own.
			return texCoord;
		#endif

		// A face whose sprite bounds say nothing has no local box to march in,
		// so the coordinate is passed through and the face is drawn with no
		// displacement. This is the hand above and the entities - everything
		// drawn with PBR_MATERIALS_ANY_TEXTURE reports a zero half-size, because
		// its coordinate indexes its own texture rather than a sheet (see
		// lit.vsh). Nothing here depends on what the boundary treatment is, which
		// is why the hand and the entities went through the wrap, the clamp and
		// the fade without any of them changing what they look like: a face with
		// no box is returned before any of it runs.
		//
		// One thing is worth recording about that: entities used to be marched
		// anyway, in atlas coordinates, with no bounds to keep the samples
		// inside anything - the clamp had nothing to clamp against and passed
		// every sample through. Skipping them is the smaller of the two
		// changes, and it is the one the note claimed was already happening.
		if (!PbrSpriteUsable(spriteBounds)) {
			return texCoord;
		}

		// The view direction, expressed in the tangent space of this fragment.
		vec3 viewDirection = normalize(-cameraRelativePos);
		vec3 viewTangent = vec3(
			dot(viewDirection, frame[0]),
			dot(viewDirection, frame[1]),
			dot(viewDirection, frame[2]));

		// The surface faces away from the eye, so there is no sensible ray to
		// trace through the height field.
		//
		// The test is against zero rather than against a small positive number,
		// which is what it used to be, and it is the same mistake the height field
		// shadow carried (see PbrParallaxShadow). A surface being viewed at a
		// shallow angle is precisely where parallax mapping has the most to show -
		// the ray runs a long way across the field - and a threshold above zero
		// switched the effect off entirely there instead of letting it fall off
		// with the angle. The rate below has a floor, so nothing divides by zero
		// and the offset stays bounded.
		if (viewTangent.z <= 0.0) {
			return texCoord;
		}

		// The displacement grows without bound as the view direction approaches
		// the plane of the surface, which at the very least would drag samples
		// across the neighbouring sprites of the atlas. Clamp how shallow the
		// trace is allowed to get, ie, how far a point at full depth can be
		// dragged sideways.
		float depthRate = max(viewTangent.z, 0.25);

		// Fade the effect out with distance rather than spending up to
		// PBR_PARALLAX_STEPS samples per pixel on shimmer.
		float strength = PbrParallaxStrength(cameraRelativePos);

		if (strength <= 0.0) {
			return texCoord;
		}

		// The height at the fragment itself, which is where the ray starts.
		//
		// Everything below is measured on the same axis as this: LabPBR stores
		// 1.0 for "not displaced", so a texel's *depth* is 1.0 minus its height,
		// and the ray starts at the top of that range and descends through it.
		//
		// Sampled at the coordinate the fragment arrived with rather than through
		// PbrClampToSprite, because a fragment is inside its own sprite by
		// construction - and rounding at the very edge of one is exactly what
		// clamping the coordinate would hold at the edge instead of at the
		// fragment's own texel. The interpolation's own four corners are a
		// different matter: on a fragment sitting on the sprite's outermost texel
		// each of them can be half a texel outside it, which is why PbrHeightTexel
		// holds them individually rather than trusting the coordinate to be far
		// enough in.
		float startHeight = PbrHeight(texCoord, gradients, spriteBounds);

		// A resource pack whose height channel is flat costs this one sample and
		// produces no displacement: there is nothing above the reference height
		// for the ray to meet, so the march would stop on its first layer every
		// time. Sundial skips it in the same place and for the same reason.
		if (startHeight >= 1.0 - 1.0e-4) {
			return texCoord;
		}

		// The displacement, in sprite-relative units, of a point that sits
		// PBR_PARALLAX_DEPTH below the reference surface, seen along the view
		// ray. One unit is one sprite width, so the depth no longer depends on
		// the atlas resolution or on the surface's UV axes - see
		// PBR_PARALLAX_DEPTH for what that fixed, and PbrSpriteLocal for where
		// the units come from.
		//
		// A point that is further away from the eye than the surface appears to
		// be is the one that gets sampled: looking down at a recessed point, the
		// ray from the eye reaches it further along the surface, away from the
		// eye. Since viewTangent points *towards* the eye, the negation below is
		// what turns "towards the eye" into "away from the eye", which is the
		// direction the ray march then travels in.
		//
		// The direction comes from the surface's UV axes rather than from the
		// tangent frame, and that was this march's first mistake: a tangent
		// frame built from at_tangent, as this pack's is, is not obliged to
		// point the same way as the atlas's u and v. Its axes can be swapped or
		// reversed against the texture, and taking viewTangent.xy for the
		// direction then sends the ray the other way - which reads as the
		// surface's relief being inside out, or as a floor showing the face you
		// would see from above it. Sundial's frame is built from the texture
		// coordinates' own screen derivatives, so its axes line up with u and v
		// by construction and it can use them directly; this pack cannot, and
		// has to say which way u and v point.
		//
		// The axes come from the screen-space derivatives, which is the only
		// place the answer exists, and they are read for their direction alone -
		// see the note on the offset below for why the length half of them is
		// not used. A face whose derivatives cannot resolve them falls back to
		// the tangent frame instead of giving up: being told the direction
		// approximately is worth more than having no parallax at all on that
		// face.
		vec3 dPdu;
		vec3 dPdv;

		// Both axes or neither. PbrTexCoordAxes' own return value only says that
		// one of them survived, which is not enough here on two counts: a single
		// axis does not say which way the other one runs, and the one it drops is
		// exactly zero, so normalizing it below would put a NaN in the ray - and
		// a NaN coordinate is not something the samples inside the march can
		// recover from, since only the value the march returns is checked.
		if (!PbrTexCoordAxes(gradients, dPdu, dPdv)
			|| dot(dPdu, dPdu) <= 0.0
			|| dot(dPdv, dPdv) <= 0.0) {
			dPdu = frame[0];
			dPdv = frame[1];
		}

		vec3 worldOffset = -strength * PBR_PARALLAX_DEPTH
			* (viewTangent.x * frame[0] + viewTangent.y * frame[1])
			/ depthRate;

		// The offset in the sprite's local box, where one unit is one sprite
		// across and one unit of z is the whole height range. Projecting it onto
		// the texture's own axes is the whole of the conversion.
		//
		// The axes are used for their direction only. Their lengths were in the
		// divisor when the direction was first taken from them - a divisor of
		// 2 * zw * |dPdu|, which is the width of the sprite in blocks - and that
		// divisor is exactly 1.0 on an ordinary one-block face, so dropping it
		// leaves every face that already looked right bit for bit as it was.
		// Where it was not 1.0 it was worse than useless: a face that squeezes a
		// whole sprite into less than a block divides by that fraction and so
		// multiplies the displacement instead, by eight on a face an eighth of a
		// block across, which walks the ray round and round the sprite. See the
		// paragraph below for why that length cannot be trusted anyway.
		//
		// The length is not merely redundant either, it is the half of the axis
		// the depth buffer spoils. Both axes are built from dFdx and dFdy of
		// cameraRelativePos, which lit.fsh reconstructs out of the depth buffer,
		// and the depth buffer quantizes: every fragment of a 2x2 quad that lands
		// in the same depth quantum reconstructs its position with the same
		// error along the view ray, which scales both position derivatives by a
		// common factor. An axis therefore comes out pointing the right way and
		// measuring the wrong length, and how wrong changes from quad to quad as
		// the camera moves. Dividing the whole displacement by that length is
		// what turns it into per-quad shimmer over the surface, and no step count
		// or refinement can take it back out, because the march is being handed a
		// different ray rather than a less accurate one.
		//
		// Sundial and Mellow both scale their step by a length taken from these
		// same derivatives and neither has this problem, because the position
		// they differentiate is one the vertex stage interpolated - Sundial's
		// viewPos, Mellow's ViewPos - and not one reconstructed from the depth
		// buffer. This pack's note on PBR_TANGENT_ATTRIBUTE is the same story
		// about the same route.
		vec2 localOffset = vec2(
			dot(worldOffset, normalize(dPdu)),
			dot(worldOffset, normalize(dPdv)));

		// Shallow view angles divide by a small slope, which on its own would
		// drag the sample far enough to leave the sprite it belongs to. The
		// material read from a neighbouring part of the atlas describes a
		// different block, and the boundary where that starts happening is
		// visible as a line across the ground at a fixed distance from the
		// player.
		float localOffsetLength = length(localOffset);

		if (localOffsetLength > PBR_PARALLAX_MAX_OFFSET) {
			localOffset *= PBR_PARALLAX_MAX_OFFSET / localOffsetLength;
		}

		// The second cap, at half a sprite per axis, which is as far as the ray
		// can travel and still be reading the material it started in. This is a
		// look rather than a guard - see PBR_PARALLAX_MAX_OFFSET - and it is no
		// longer what keeps the ray inside the sprite: the fade below is.
		localOffset = clamp(localOffset, vec2(-0.5), vec2(0.5));

		// The point the ray starts at, in the sprite's local box, and the depth
		// it starts at: the top of the height range, depth 0.
		vec2 startCoord = PbrSpriteLocal(texCoord, spriteBounds);
		vec3 parallaxCoord = vec3(startCoord, 1.0);

		// The offset is then scaled down to the room this fragment has before its
		// sample would leave the sprite - the rule PbrFadeOffsetToSprite sets out,
		// and the reason the march needs no wrap. PbrClampToSprite on the samples
		// themselves is the backstop behind it.
		localOffset = PbrFadeOffsetToSprite(startCoord, localOffset);

		// What the diagnostic reports: the offset as it stands once both caps and
		// the fade have had their say, converted back into texture coordinates so
		// that it is the same quantity it has always been. The PBR_DEBUG_PARALLAX
		// view divides it by the sprite's half-size to show a fraction of a
		// sprite, and that division only comes out right if the offset is in
		// texture coordinates when it gets there.
		//
		// Nothing reads it outside that view.
		offsetLength = length(localOffset * 2.0 * spriteBounds.zw);

		// The direction and the length of one step: localOffset is the
		// horizontal travel of the *whole* ray and -1.0 its whole descent, so
		// this divides both by the layer count and then lets stepScale change
		// the length of each layer as the march goes.
		vec3 stepSize = vec3(localOffset, -1.0) / float(PBR_PARALLAX_STEPS);
		float stepScale = 2.0 / float(PBR_PARALLAX_STEPS);

		// The two layers that bracket the crossing, kept as the ray goes rather
		// than found again afterwards: they are the last point the ray was still
		// above the surface at and the first one it was below, and both the
		// refinement and the unrefined interpolation further down need them.
		vec2 previousCoord = startCoord;
		float previousHeight = startHeight;
		float previousZ = 1.0;
		float sampleHeight = startHeight;
		bool crossed = false;

		// Walk along the ray in layers until it passes below the surface it is
		// tracing.
		//
		// The step scale is what makes the layer count a quality knob rather
		// than a depth knob. It starts at 2 / steps and grows by the same amount
		// every layer, so the layers are small near the reference surface - where
		// a resource pack's height channel has nearly all of its variation - and
		// large at the bottom of the range, while the descent still adds up to
		// the full depth range whatever the layer count is. A fixed step would
		// make the ray travel 1 / steps of the range per layer instead, so
		// lowering the count would flatten the surface rather than coarsen it,
		// and PBR_PARALLAX_STEPS would be a second depth control fighting the
		// real one.
		for (int i = 0; i < PBR_PARALLAX_STEPS; i++) {
			previousCoord = parallaxCoord.xy;
			previousHeight = sampleHeight;
			previousZ = parallaxCoord.z;

			parallaxCoord += stepSize * stepScale;

			sampleHeight = PbrHeight(
				PbrClampToSprite(parallaxCoord.xy, spriteBounds),
				gradients,
				spriteBounds);

			// The surface is above the ray here, so the two have crossed
			// somewhere between this layer and the one before it.
			if (sampleHeight > parallaxCoord.z) {
				crossed = true;
				break;
			}

			stepScale += 2.0 / float(PBR_PARALLAX_STEPS);
		}

		if (!crossed) {
			// The height channel is at its deepest along the whole ray, which is
			// the one case where there is no crossing to find. The answer is
			// then the furthest point the march reached.
			return PbrClampToSprite(parallaxCoord.xy, spriteBounds);
		}

		#if PBR_PARALLAX_REFINE > 0
			// Find the crossing point properly, by bisecting the interval
			// between the two layers that bracket it.
			//
			// This matters more than it sounds like it should. The march places
			// a fixed number of layers across the entire height range, but a
			// resource pack's height channel usually covers only a fraction of
			// that range, so only one or two layers tend to fall inside the
			// actual variation. Interpolating between two such distant layers is
			// not enough to hide them, and the texture snaps between a handful
			// of positions, which reads as the surface being built out of
			// stacked layers rather than following a continuous slope.
			//
			// The two ends stay on the ray as they move, in the local box and
			// possibly outside it, and only the samples are clamped - so the
			// interval is a straight piece of the ray even when it has left the
			// sprite, and the bisection cannot be confused by a coordinate that
			// folded back on itself partway along it. The fade above is what keeps
			// this a corner case rather than the normal one: with the offset scaled
			// to the room available, the ray only reaches the boundary as its
			// displacement reaches zero.
			vec2 lowCoord = previousCoord;
			vec2 highCoord = parallaxCoord.xy;
			float lowZ = previousZ;
			float highZ = parallaxCoord.z;

			for (int i = 0; i < PBR_PARALLAX_REFINE; i++) {
				vec2 midCoord = 0.5 * (lowCoord + highCoord);

				// The ray's height at the midpoint, which needs no sample to
				// know: the ray travels in a straight line in this space - the
				// direction of a step is the same for every layer and only its
				// length grows - so its height is linear in its position along
				// it, and the midpoint of the two heights is the height at the
				// midpoint of the two coordinates.
				float midZ = 0.5 * (lowZ + highZ);

				if (PbrHeight(
						PbrClampToSprite(midCoord, spriteBounds),
						gradients,
						spriteBounds)
					> midZ) {
					// The surface is above the ray here, so the crossing is
					// between the low end and this point.
					highCoord = midCoord;
					highZ = midZ;
				} else {
					// The ray is still above the surface here, so the crossing
					// is further along the ray.
					lowCoord = midCoord;
					lowZ = midZ;
				}
			}

			return PbrClampToSprite(0.5 * (lowCoord + highCoord), spriteBounds);
		#else
			// Without refinement, at least interpolate between the two layers.
			//
			// Each gap is the distance between the ray and the surface at one of
			// the two points - height minus height, so its sign says which side
			// of the crossing that point is on - and the crossing is the same
			// fraction of the way along the interval as the low point's gap is
			// of the two of them together. The floor under the denominator is
			// what keeps two points that landed on the crossing at the same time
			// from dividing by nothing.
			float lowGap = previousHeight - previousZ;
			float highGap = sampleHeight - parallaxCoord.z;
			float weight = clamp(
				lowGap / min(lowGap - highGap, -1.0e-4),
				0.0,
				1.0);

			return PbrClampToSprite(
				mix(previousCoord, parallaxCoord.xy, weight), spriteBounds);
		#endif
	#endif
}

#ifdef PBR_PARALLAX_SHADOWING
	// How much of the sunlight reaches this point through the height field.
	//
	// This is what makes the height field read as depth rather than as a
	// picture sliding around on the block. Parallax mapping on its own only
	// moves the texture; nothing about it says that the side of a bump should
	// be darker than the surrounding flat ground, so the eye reads the result
	// as a flat layer that happens to move. Marching the height field against
	// the light and darkening whatever is behind a bump is what turns that into
	// something with visible sides.
	//
	// Note that this can only ever darken. The shape of the block is still a
	// cube: nothing here can make the height field stick out past the block's
	// own edges, because the fragment shader has no way to move geometry.
	float PbrParallaxShadow(
		// The displaced texture coordinate, ie, the point being shaded.
		vec2 texCoord,
		mat3 frame,
		vec3 lightDirection,
		vec3 cameraRelativePos,
		PbrGradients gradients,
		// xy: the centre of this face's sprite, zw: half of its size.
		vec4 spriteBounds
	) {
		// Interpolated exactly as the view ray's heights are, and that is not a
		// coincidence: the two marches are tracing one height field, so a shadow
		// measured against a differently filtered copy of it would be cast by
		// geometry the displacement does not show. This is also the one call that
		// can arrive without usable bounds - see the note on PbrHeight's fallback
		// - because the bounds are checked a few lines below rather than here.
		float surfaceHeight = PbrHeight(texCoord, gradients, spriteBounds);

		// A point sitting at the reference height cannot be shadowed by the
		// height field, because nothing in it is tall enough to rise above the
		// ray that leaves this point towards the light. This is what makes a
		// resource pack with a flat height channel cost a single sample, as the
		// ray march below is skipped entirely.
		if (surfaceHeight >= 1.0 - 1.0e-4) {
			return 1.0;
		}

		// The light direction, expressed in the tangent space of this fragment.
		vec3 lightTangent = vec3(
			dot(lightDirection, frame[0]),
			dot(lightDirection, frame[1]),
			dot(lightDirection, frame[2]));

		// The light is behind this surface, so the surface is unlit anyway and
		// there is nothing to shadow.
		//
		// The test is against zero rather than against a small positive number,
		// which is what it used to be. A surface the light rakes across at a very
		// shallow angle is exactly the one whose height field casts the longest
		// shadows - the side of a bump and the wall behind it both live in the
		// light's plane - and a threshold above zero threw all of that away. The
		// march is safe there: the rate below has a floor, so the ray length stays
		// bounded.
		if (lightTangent.z <= 0.0) {
			return 1.0;
		}

		float depthRate = max(lightTangent.z, 0.25);

		// The sprite bounds have to be usable here for the same reason the view
		// ray needs them: the march below runs in the sprite's local box, and a
		// face without bounds has no box to run in. Nothing is shadowed there,
		// which is the same answer as a flat height channel above.
		if (!PbrSpriteUsable(spriteBounds)) {
			return 1.0;
		}

		// The ray towards the light rises by one layer of height per step, so
		// the horizontal distance it covers over the whole march is one full
		// depth range measured along the light's direction. Note that there is
		// no negation here: this ray travels towards the light, unlike the view
		// ray above, which travels away from the eye and into the surface.
		//
		// The depth is the same PBR_PARALLAX_DEPTH the view ray uses and in the
		// same sprite-relative units, so that the two rays are tracing one
		// height field rather than two of different depths. A light ray that
		// reached further horizontally than the geometry is deep would darken
		// stretches of surface that no view ray could ever be displaced to, and
		// the shadow would land where the shape it belongs to is not.
		vec2 localOffset = PBR_PARALLAX_DEPTH * lightTangent.xy / depthRate;

		float localOffsetLength = length(localOffset);

		if (localOffsetLength > PBR_PARALLAX_MAX_OFFSET) {
			localOffset *= PBR_PARALLAX_MAX_OFFSET / localOffsetLength;
		}

		// Capped the same way the view ray's displacement is, and for the same
		// reason - see PbrParallaxUV.
		localOffset = clamp(localOffset, vec2(-0.5), vec2(0.5));

		// The point this ray starts from, in the sprite's local box, and the offset
		// it will travel - faded to the room this fragment has, by the same rule
		// and the same function the view ray's offset is put through. A light ray
		// that left the sprite would be occluded by material belonging to another
		// block, and one held at the edge would darken the face's whole edge strip;
		// see PbrFadeOffsetToSprite.
		vec2 localTexCoord = PbrSpriteLocal(texCoord, spriteBounds);
		localOffset = PbrFadeOffsetToSprite(localTexCoord, localOffset);
		vec2 stepOffset = localOffset / float(PBR_PARALLAX_STEPS);

		// The height range that this ray actually travels through. A resource
		// pack's height channel normally covers only a fraction of its range, so
		// measuring the occlusion against the full range would leave subtle
		// height maps casting no shadow at all - which is exactly what happened
		// before this was measured locally.
		float farHeight = PbrHeight(
			PbrClampToSprite(localTexCoord + localOffset, spriteBounds),
			gradients,
			spriteBounds);
		float variation = max(surfaceHeight, farHeight)
			- min(surfaceHeight, farHeight);
		float variationScale = 1.0 / max(variation, 0.05);

		float layerStep = 1.0 / float(PBR_PARALLAX_STEPS);
		float rayHeight = surfaceHeight;
		vec2 currentCoord = localTexCoord;

		// How far the ray ends up buried underneath the height field is what
		// decides how much light gets through. Counting the blocked layers
		// instead would dilute the result across the whole march: a crevice is
		// open along most of the ray and only blocked close in.
		//
		// Unlike the view ray, this one steps evenly. What it is measuring is
		// how deep the surface is at its worst point along the ray, and that is
		// a maximum over the whole ray rather than a crossing that has to be
		// found, so there is nothing here for a steplength that varies with
		// depth to buy.
		float deepest = 0.0;

		for (int i = 0; i < PBR_PARALLAX_STEPS; i++) {
			currentCoord += stepOffset;
			rayHeight += layerStep;

			deepest = max(
				deepest,
				PbrHeight(
					PbrClampToSprite(currentCoord, spriteBounds),
					gradients,
					spriteBounds)
					- rayHeight);
		}

		float occlusion = clamp(deepest * variationScale, 0.0, 1.0);
		float shadow = 1.0 - occlusion * PBR_PARALLAX_SHADOW_STRENGTH;

		// Fade the shadowing out with distance along with the rest of the
		// parallax effect.
		return mix(1.0, shadow, PbrParallaxStrength(cameraRelativePos));
	}
#endif

// The tangent-space XY of the normal map at this coordinate, decoded to the
// -1 to 1 range.
//
// LabPBR normals use the DirectX convention, where green points down in the
// texture - which is exactly the direction that the texture coordinate's V axis
// increases in Minecraft, so the green channel maps straight onto the bitangent
// with no flip.
vec2 PbrTangentNormalXY(vec2 texCoord, PbrGradients gradients) {
	vec2 encoded = textureGrad(
		normals,
		texCoord,
		gradients.ddxTexCoord,
		gradients.ddyTexCoord).xy;

	return encoded * 2.0 - 1.0;
}

// Perturbs the interpolated face normal using the normal map.
vec3 PbrNormal(mat3 frame, vec2 texCoord, PbrGradients gradients) {
	#ifndef PBR_NORMAL_MAP
		return frame[2];
	#else
		vec2 tangentNormalXY = PbrTangentNormalXY(texCoord, gradients);

		// Past a certain distance the normal map is finer than a pixel, so the
		// perturbation it describes cannot be resolved and sampling it only
		// produces shimmer. Fade it out to the flat surface normal instead,
		// which is what a correctly filtered normal map converges to anyway.
		//
		// The level this is keyed on is the true one rather than the level
		// actually sampled, so the fade still applies when PBR_MATERIAL_MAX_LOD
		// holds the sample at a sharp level.
		float detail = 1.0 - smoothstep(
			PBR_NORMAL_FADE_LOD * 0.4,
			PBR_NORMAL_FADE_LOD,
			gradients.lod);

		// Scaling the tangent plane components tips the normal further away
		// from the surface for the same texture, which is how the strength
		// control works. Z is reconstructed from the scaled components below,
		// so a normal that ends up longer than one is simply renormalized.
		tangentNormalXY *= PBR_NORMAL_STRENGTH * detail;

		// LabPBR leaves Z out of the texture and requires reconstructing it,
		// since the blue channel stores material ambient occlusion instead.
		// Clamping keeps the vector valid if a resource pack over-saturates the
		// XY channels.
		float tangentNormalZ = sqrt(max(
			0.0,
			1.0 - dot(tangentNormalXY, tangentNormalXY)));

		// A resource pack without normal maps yields a flat normal here, which
		// decodes to (0, 0, 1) and reproduces the original face normal exactly.
		return normalize(frame * vec3(tangentNormalXY, tangentNormalZ));
	#endif
}

// Decodes the material properties of a fragment from the specular map.
//
// The albedo is deliberately not an input: albedo-based metals use the surface
// color as their reflectance, and this has to be called before the surface
// color is known (see the ordering note in lit.fsh). PbrResolveAlbedo()
// finishes that case off later.
PbrSurface PbrDecode(vec2 texCoord, PbrGradients gradients) {
	PbrSurface pbr = PbrNone();

	#if defined(PBR_SPECULAR) || defined(PBR_EMISSION) || defined(PBR_SUBSURFACE)
		vec4 specularSample = textureGrad(
			specular,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord);
	#endif

	#ifdef PBR_SPECULAR
		// A resource pack that ships no specular map for a sprite leaves the
		// atlas either black or white there, depending on how the atlas is
		// built. Neither is usable: black decodes to "no reflectance and fully
		// rough" and white to "perfect mirror", and the first of those is what
		// makes a block look like it has no surface response at all.
		//
		// Note the assumption that a missing sprite is opaque; a transparent
		// black would be indistinguishable from a fully emissive material.
		#ifdef PBR_DEFAULT_MATERIAL
			bool missingSpecular = PbrMissingSpecular(specularSample);
		#else
			bool missingSpecular = false;
		#endif

		if (missingSpecular) {
			pbr.roughness = PBR_DEFAULT_ROUGHNESS;
			pbr.f0 = vec3(PBR_DEFAULT_F0);
		} else {
			// Smoothness is stored perceptually, so square it to get a
			// roughness that behaves linearly in the shading math.
			pbr.roughness = pow(1.0 - specularSample.r, 2.0);

			// Rescale the green channel back to the byte value that the artist
			// stored. Texture filtering can leave the sampled value between two
			// bytes, so the boundaries are placed half-way between neighboring
			// IDs, as LabPBR specifies.
			float green255 = specularSample.g * 255.0;

			bool hardcodedMetal = false;
			#ifdef PBR_METALS
				hardcodedMetal = green255 >= 229.5 && green255 < 237.5;
			#endif

			if (green255 < 229.5) {
				// Dielectric. F0 is stored linearly as of LabPBR 1.3, where the
				// dielectric range tops out at 229/255 (~0.898) - which is high
				// enough for gemstones, so it is deliberately not clamped lower.
				//
				#ifdef PBR_DEFAULT_MATERIAL
					// Floored: a resource pack that leaves the green channel
					// near zero is not describing a real material, as no
					// dielectric reflects nothing, and the result would be a
					// perfectly smooth surface with no reflection at all.
					pbr.f0 = vec3(max(specularSample.g, PBR_DEFAULT_F0));
				#else
					pbr.f0 = vec3(specularSample.g);
				#endif
			} else if (hardcodedMetal) {
				// Hardcoded metal, looked up from the table.
				pbr.f0 = PbrMetalF0(int(green255 + 0.5));
				pbr.metalness = 1.0;
				pbr.metalID = float(int(green255 + 0.5));
			} else {
				// Albedo-based metal. f0 is filled in from the surface color by
				// PbrResolveAlbedo(). This is also where hardcoded metals land
				// when the metal lookup is turned off, which approximates them
				// far better than treating them as dielectrics would - and it is
				// why they are given the albedo metal's ID rather than their own:
				// the table that ID would index is the one that is turned off.
				pbr.metalness = 1.0;
				pbr.albedoMetal = 1.0;
				pbr.metalID = PBR_METAL_ALBEDO;
			}
		}
	#endif

	#ifdef PBR_EMISSION
		// LabPBR stores emission as alpha directly: 0 is 0% and 254 is 100%.
		// 255 is not "more than 100%", it is the no-data value - an RGB image
		// with no alpha channel at all loads as 255 everywhere, so a pack that
		// never touched the channel has to read as "does not emit" rather than
		// as a lamp. That is the whole reason the useful range stops one short
		// of the top, and it is why this is a multiply and not a subtraction.
		// See PBR_PORTING.md 165.
		//
		// The albedo supplies the color; this only supplies the amount.
		//
		// Still behind PbrMissingSpecular: a sprite with no specular map reads
		// as transparent black, and while its alpha of zero already decodes to
		// no emission, the same guard is what keeps the porosity and the
		// scattering off data that is not there (see the block below).
		if (!PbrMissingSpecular(specularSample)) {
			pbr.emission = specularSample.a * step(specularSample.a, 0.999);
		}
	#endif

	#if defined(PBR_SUBSURFACE) || defined(PBR_POROSITY_WETNESS)
		// LabPBR packs two things into one channel and splits them at 64 out of
		// 255: below that the value is porosity, above it the surface lets that
		// much of the light through. The boundary is placed half-way between the
		// two ranges so that texture filtering between neighbouring texels
		// cannot land on it.
		//
		// Both readings are skipped for a sprite the resource pack gives no
		// specular map, since the atlas value there is an artefact rather than a
		// material - taking it at face value would make every such block scatter
		// all of the light or darken as if it were porous everywhere. See
		// PbrMissingSpecular.
		if (!PbrMissingSpecular(specularSample)) {
			#ifdef PBR_SUBSURFACE
				pbr.sss = specularSample.b * 255.0 > 64.5 ? specularSample.b : 0.0;
			#endif

			#ifdef PBR_POROSITY_WETNESS
				pbr.porosity = specularSample.b * 255.0 > 64.5
					? 0.0
					: specularSample.b * 255.0 / 64.0;
			#endif
		}
	#endif

	#ifdef PBR_MATERIAL_AO
		// The normal map is sampled here not for the normal - PbrNormal takes
		// care of that - but for the occlusion LabPBR stores in its blue
		// channel. The arguments are identical to the ones PbrNormal uses (same
		// sampler, same coordinate, same gradients), so the two fetches are
		// expected to be merged into one; if materials visibly cost more with
		// PBR_MATERIAL_AO on, that merge is the first thing to check.
		pbr.materialAO = textureGrad(
			normals,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).b;
	#endif

	return pbr;
}

// Applies the albedo-based metal case, which can only be resolved once the
// surface color has been computed. This is a single mix, so it is affordable to
// call unconditionally.
PbrSurface PbrResolveAlbedo(PbrSurface pbr, vec3 albedo) {
	pbr.f0 = mix(pbr.f0, albedo, pbr.albedoMetal);
	return pbr;
}

#ifdef PBR_SUBSURFACE
	// How strongly a thin material scatters the light that enters it forwards,
	// for the Henyey-Greenstein phase function below. 0.6 is the value the
	// effect was tuned at in the pack it was modelled on, and it concentrates
	// the glow around the direction of the sun rather than spreading it evenly.
	const float PBR_SSS_PHASE_G = 0.6;

	// How quickly the glow falls off as the surface turns away from the light.
	// Higher values keep it closer to the silhouette of the leaf.
	const float PBR_SSS_EDGE_FALLOFF = 5.0;

	// The floor under the phase term, so that a thin surface still scatters
	// something when the sun is not directly behind it. Without it, a leaf lit
	// from the side would show no scattering at all, since the phase function
	// above is very nearly zero once the light is more than a few degrees off
	// the direction towards the viewer.
	const float PBR_SSS_ISOTROPIC_PHASE = 0.1;

	// The Henyey-Greenstein phase function, which describes what fraction of the
	// light that scatters inside a material comes out in a given direction.
	//
	// cosTheta is the cosine of the angle between the light's direction of travel
	// and the direction towards the viewer, so 1.0 is light that carries straight
	// on towards the camera - the sun behind a leaf, seen through it - and -1.0
	// is light that has to turn all the way around to be seen. g is how strongly
	// the material scatters forwards, where 0.0 spreads the light evenly in every
	// direction and values approaching 1.0 send nearly all of it straight on.
	float PbrPhaseHG(float cosTheta, float g) {
		float g2 = g * g;
		float denominator = 1.0 + g2 - 2.0 * g * cosTheta;

		return (1.0 - g2)
			/ (4.0 * PBR_PI * denominator * sqrt(max(denominator, 1.0e-4)));
	}

	// The light that reaches the viewer through the surface rather than off it.
	//
	// Three things decide how much of it there is, and the first is what keeps
	// the effect from touching anything that is not thin:
	//
	//   - The amount the resource pack stored, which is zero for every material
	//     that does not scatter.
	//   - How edge-on the surface is to the light. A leaf facing the sun is lit
	//     like any other surface and shows no glow; the glow belongs to the
	//     leaves seen edge-on and to the rim of the canopy.
	//   - How closely the viewer is looking along the light, which is what makes
	//     the glow appear when the sun is behind the leaves.
	//
	// visibility is the shadow map result for this fragment, passed in so that
	// the glow cannot pass through a wall the direct light itself is blocked by.
	float PbrSubsurfaceScatter(
		PbrSurface pbr,
		vec3 worldNormal,
		vec3 lightDirection,
		vec3 viewDirection,
		float visibility
	) {
		// The scattered light is a fraction of the light that arrives, so where
		// none arrives there is nothing to scatter. This also skips the phase
		// function for every material that does not scatter in the first place.
		if (pbr.sss <= 0.0 || visibility <= 0.0) {
			return 0.0;
		}

		float NdotL = dot(worldNormal, lightDirection);

		// A material that scatters more also keeps the glow over a wider range
		// of angles, so the same value drives both how bright the glow is and
		// how quickly it fades away from the silhouette.
		float phase = max(
			PBR_SSS_ISOTROPIC_PHASE,
			PbrPhaseHG(dot(viewDirection, lightDirection), PBR_SSS_PHASE_G));

		return PBR_SSS_STRENGTH * pbr.sss * visibility * phase
			* exp(-(1.0 - pbr.sss) * PBR_SSS_EDGE_FALLOFF * abs(NdotL));
	}
#endif /* PBR_SUBSURFACE */

// A visualisation of the material data behind the PBR settings.
//
// This is the quickest way to tell whether a resource pack actually provides
// what an effect needs. If Height comes out flat grey for the block being
// looked at, that pack has no height channel there, and no amount of parallax
// tuning will produce displacement - the effect is not broken, there is simply
// nothing to displace.
vec3 PbrDebugColor(
	mat3 frame,
	vec2 texCoord,
	PbrSurface pbr,
	PbrGradients gradients,
	// Whether the world's own lighting treats this face as a light source. Only
	// the calling shader can work that out, from the lightmap, and only the
	// emission view below reads it.
	float lightSourceSignal
) {
	#if PBR_DEBUG == PBR_DEBUG_HEIGHT
		return vec3(textureGrad(
			normals,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).a);
	#elif PBR_DEBUG == PBR_DEBUG_SMOOTHNESS
		return vec3(1.0 - pbr.roughness);
	#elif PBR_DEBUG == PBR_DEBUG_F0
		return pbr.f0;
	#elif PBR_DEBUG == PBR_DEBUG_NORMAL
		return PbrNormal(frame, texCoord, gradients) * 0.5 + 0.5;
	#elif PBR_DEBUG == PBR_DEBUG_MIP
		// The mip level this fragment's material samples land on, as a greyscale
		// ramp from level 0 (black) to level 8 (white). Blockier bands are
		// expected - the level steps once per doubling of distance.
		//
		// This is the level the distance calls for, before PBR_MATERIAL_MAX_LOD
		// clamps it, which is what decides where the normal map fades out.
		return vec3(clamp(gradients.lod / 8.0, 0.0, 1.0));
	#elif PBR_DEBUG == PBR_DEBUG_TANGENT_NORMAL
		// The normal map exactly as authored, decoded but before the surface's
		// tangent frame is applied - so it shows the texture's own content and
		// nothing this shader does to it. A flat normal reads as the light blue
		// of a straight-up vector.
		//
		// A tangent-space view is the way to tell a bad sample apart from a bad
		// frame: if the colour stays correct with distance but the shading does
		// not, the sample is fine and the frame is at fault. Anything that comes
		// out black is a texel outside the sprite, which decodes to a (-1, -1)
		// direction rather than a flat one.
		vec2 tangentXY = PbrTangentNormalXY(texCoord, gradients);
		float tangentZ = sqrt(max(0.0, 1.0 - dot(tangentXY, tangentXY)));

		return vec3(tangentXY, tangentZ) * 0.5 + 0.5;
	#elif PBR_DEBUG == PBR_DEBUG_MATERIAL_AO
		// The occlusion channel of the normal map exactly as the resource pack
		// authored it, and sampled independently of PBR_MATERIAL_AO so that it
		// can be inspected with the feature switched off - which is the state
		// the decision to switch it on has to be made in.
		//
		// Flat white means the pack ships no occlusion data for this block and
		// PBR_MATERIAL_AO has nothing to apply. Anything darker, especially
		// shading inside a sprite away from its edges, is the occlusion itself.
		return vec3(textureGrad(
			normals,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).b);
	#elif PBR_DEBUG == PBR_DEBUG_SUBSURFACE
		// The blue channel of the specular map, which is where both of the
		// things LabPBR packs into it live: values up to 64 out of 255 are
		// porosity, anything above that is how much the material scatters. Both
		// therefore appear in this one picture - a scattering surface reads as a
		// mid to bright colour, a porous one as a dark colour, and one that is
		// neither as black.
		//
		// Sampled independently of PBR_SUBSURFACE, so that a pack can be checked
		// before the option is switched on.
		return vec3(textureGrad(
			specular,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).b);
	#elif PBR_DEBUG == PBR_DEBUG_EMISSION
		// Red: the emission the material is putting on this fragment, after the
		// decoding has decided whether its data is usable at all. Green: whether
		// the world's own lighting treats this face as a light source, which is
		// what the emission is weighed against.
		//
		// This is the view to open when a block glows that should not, and the
		// two channels answer it between them:
		//
		//   - Red bright means the material's specular map is being read as
		//     emissive, and the material data is what to look at next.
		//   - Green bright means the lightmap is calling this face a light
		//     source, which is the block self-emission rather than the material.
		//   - Both black means neither is putting light here, and a glow that is
		//     still visible comes from somewhere else again - the light bleed
		//     spreading a nearby source's colour, or something outside the
		//     material model entirely.
		return vec3(pbr.emission, lightSourceSignal, 0.0);
	#else
		return vec3(0.0);
	#endif
}

#ifdef PBR_POROSITY_WETNESS
	// How much darker this fragment is because it is wet, as a fraction of its
	// light, from 0.0 for a dry or non-porous surface to 1.0 for one that is
	// soaked through.
	//
	// Three things scale it, and each is a reason for a surface to be left
	// alone: how porous the material is (a mirror or a metal has no pores for
	// water to fill), how wet it currently is, and how much sky light reaches
	// it. That last one is what keeps a lit cellar the same in the rain as out
	// of it, and it matches how the rest of the pack treats weather.
	float PbrWetnessDarkening(PbrSurface pbr, float skyLight) {
		return clamp(
			pbr.porosity * wetness * PBR_WETNESS_DARKENING * skyLight,
			0.0,
			1.0);
	}
#endif

#ifdef PBR_SPECULAR
	// Half the angle the sun covers seen from the ground, in radians: its disc is
	// about 0.53 degrees across, so its radius is a little under a quarter of a
	// degree. This is the size a light that is not a point has in the lobe below,
	// scaled by PBR_LIGHT_SIZE.
	const float PBR_SUN_ANGULAR_RADIUS = 0.0046;

	// The GGX / Trowbridge-Reitz normal distribution function, which controls
	// the size and shape of the specular lobe.
	float D_GGX(float NdotH, float roughness) {
		float a = roughness * roughness;
		float a2 = a * a;
		float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
		return a2 / (PBR_PI * d * d);
	}

	// Smith's visibility function with the height-correlated form of the
	// geometric term, divided by the 4 * NdotL * NdotV denominator of the
	// microfacet BRDF. The division is kept inside so that the caller can
	// multiply the pieces together directly.
	float V_SmithGGXCorrelated(float NdotL, float NdotV, float roughness) {
		float a2 = roughness * roughness * roughness * roughness;
		float lambdaV = NdotL * sqrt((-NdotV * a2 + NdotV) * NdotV + a2);
		float lambdaL = NdotV * sqrt((-NdotL * a2 + NdotL) * NdotL + a2);
		return 0.5 / max(lambdaV + lambdaL, 1.0e-6);
	}

	// Schlick's approximation of the Fresnel term lives above, outside the
	// PBR_SURFACE guard, because the deferred pass needs it too.

	#ifdef PBR_ENERGY_CONSERVATION
		// The fraction of the light arriving at this angle that goes into the
		// surface rather than bouncing off it, which is what the diffuse term
		// has to be weighted by.
		//
		// This is the same Fresnel term the specular lobe above uses, read the
		// other way round: what is not reflected is transmitted, and the
		// transmitted light is what lights the material from the inside.
		//
		// Reflectance is a colour and a diffuse weight has to be a single
		// number, so it is reduced to its luminance. For a dielectric that
		// hardly matters, since the reflectance is within a few percent of
		// neutral; for a metal it produces exactly the behaviour that makes
		// metals look like metals, because a bright metal then has almost no
		// diffuse response left.
		float PbrDiffuseWeight(vec3 f0, float cosTheta) {
			vec3 fresnel = F_Schlick(f0, cosTheta);
			return 1.0 - dot(fresnel, PBR_LUMINANCE);
		}

		// The same weight for the light that arrives from the environment rather
		// than from the sun. The angle that decides the split there is the one
		// between the surface and the viewer, since that is the direction the
		// light has to leave in to be seen.
		float PbrAmbientDiffuseWeight(
			PbrSurface pbr,
			vec3 worldNormal,
			vec3 viewDirection
		) {
			float NdotV = max(dot(worldNormal, viewDirection), 1.0e-4);

			return PbrDiffuseWeight(pbr.f0, NdotV);
		}

		// The weight for the direct light, evaluated at the half angle so that
		// it uses the same reflectance the specular lobe above reflects with.
		float PbrDirectDiffuseWeight(
			PbrSurface pbr,
			vec3 lightDirection,
			vec3 viewDirection
		) {
			vec3 H = normalize(viewDirection + lightDirection);

			return PbrDiffuseWeight(pbr.f0, max(dot(viewDirection, H), 0.0));
		}
	#endif /* PBR_ENERGY_CONSERVATION */

	// Direct specular reflection for the sun / moon.
	//
	// The light term is passed in pre-multiplied by the shadow map result and
	// the pack's existing sky light falloff, so that the highlight is occluded
	// in exactly the same way as the diffuse lighting, and so that we never
	// sample the shadow map twice.
	vec3 PbrSpecular(
		PbrSurface pbr,
		vec3 worldNormal,
		vec3 lightDirection,
		vec3 viewDirection,
		float lightTerm
	) {
		// A material with no reflectance at all cannot have a highlight. This
		// is the common case for resource packs without specular maps, and
		// skipping it also avoids the metal lookup above from having to be any
		// more careful.
		if (dot(pbr.f0, pbr.f0) < 1.0e-8 || lightTerm <= 0.0) {
			return vec3(0.0);
		}

		vec3 H = normalize(viewDirection + lightDirection);

		float NdotL = max(dot(worldNormal, lightDirection), 0.0);
		float NdotV = max(dot(worldNormal, viewDirection), 1.0e-4);
		float NdotH = max(dot(worldNormal, H), 0.0);
		float VdotH = max(dot(viewDirection, H), 0.0);

		// The light is behind this surface, so there is nothing to reflect.
		if (NdotL <= 0.0) {
			return vec3(0.0);
		}

		// A perfectly smooth surface collapses the specular lobe into a single
		// point and divides by zero while doing so, so keep a floor under the
		// roughness. At this value the highlight is still sharp enough to read
		// as a mirror on a polished block.
		float roughness = max(pbr.roughness, 2.0e-3);

		// The light is not a point, and this is where that shows: the sun's own
		// angular size widens the lobe, which is what turns the highlight on a
		// polished block from a single bright pixel into the disc the sun really
		// is.
		//
		// The angle is added to alpha itself and not to the roughness, because
		// alpha is the number the lobe's width is measured in: a distribution of
		// width alpha spreads the reflected light over about that angle. D_GGX
		// takes its square root, so the square root is what is passed in.
		//
		// Adding the angle to the roughness instead is the mistake this file made
		// first: alpha is the square of that, so half a degree would arrive as four
		// millionths of a radian - a change far too small to see on any surface,
		// which is exactly how it looked.
		//
		// With PBR_LIGHT_SIZE at 0.0 this is exactly the point light it used to
		// be, which is the setting to compare against.
		float alpha = roughness * roughness
			+ PBR_SUN_ANGULAR_RADIUS * PBR_LIGHT_SIZE;

		// A distribution is only meaningful up to a width of about a radian, so an
		// exaggerated light size is capped there rather than being left to describe
		// a lobe wider than the maths can.
		float lobe = min(sqrt(alpha), 1.0);

		float D = D_GGX(NdotH, lobe);
		float visibility = V_SmithGGXCorrelated(NdotL, NdotV, lobe);
		vec3 fresnel = F_Schlick(pbr.f0, VdotH);

		return PBR_SPECULAR_STRENGTH * D * visibility * fresnel * lightTerm;
	}

	// A crude stand-in for image-based lighting.
	//
	// The highlight above only exists where a light source is, and Steadfast
	// only has one: the sun or moon. Without the term below, a material would
	// therefore only ever look reflective when it happens to be in direct
	// sunlight - never in a cave, never indoors, never at night, never on a
	// side face, and never from the block light of a torch right next to it.
	// That is what makes a shader look like it has materials on some blocks and
	// not on others.
	//
	// Treating the ambient and block light around the fragment as a uniform
	// environment is not physically correct - a real reflection would be
	// blurred by roughness rather than faded by it, and would have a direction
	// to it - but it is cheap, it responds to the material and to the light
	// around it, and it is what makes every surface read as a material.
	//
	// PBR_REFLECTIONS is what supplies the direction and the roughness described
	// above, by reflecting the sky along the reflected ray (see
	// reflections.glsl). With it on, this term keeps only what the sky cannot
	// do - the light indoors and underground, which has no direction to
	// reflect.
	vec3 PbrAmbientSpecular(
		PbrSurface pbr,
		vec3 worldNormal,
		vec3 viewDirection,
		// The ambient and block light reaching this fragment, standing in for
		// the environment that it reflects.
		vec3 indirectLighting,
		// How much sky reaches this fragment; only read when PBR_REFLECTIONS is
		// on, where it decides how much of this term the directional reflection
		// in reflections.glsl has taken over.
		float skyLight
	) {
		float NdotV = max(dot(worldNormal, viewDirection), 1.0e-4);
		vec3 fresnel = F_Schlick(pbr.f0, NdotV);

		// A rough surface scatters the environment too broadly to show a
		// coherent reflection.
		float smoothness = 1.0 - pbr.roughness;

		#ifdef PBR_REFLECTIONS
			// PbrReflection reflects the sky with a direction and a roughness,
			// which is exactly what this term was standing in for. Wherever that
			// one is doing the job - a surface smooth enough to show a coherent
			// reflection, with a sky in front of it - this one steps back, so
			// that the same environment is not counted twice.
			//
			// The step-back is weighted by the same roughness that fades the sky
			// term, so a rough surface keeps this term in full rather than
			// losing its only environment response to a reflection it can barely
			// show. Underground and indoors the sky light is zero, so this is
			// untouched either way - which is what keeps a material reading as a
			// material in a cave.
			smoothness *= 1.0 - skyLight * (1.0 - pbr.roughness);
		#endif

		return PBR_SPECULAR_STRENGTH * smoothness * fresnel * indirectLighting;
	}
#endif /* PBR_SPECULAR */

#endif /* PBR_SURFACE */
