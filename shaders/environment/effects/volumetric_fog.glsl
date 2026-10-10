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

// Added 2026-09-25 by Remiiil1a for Firmament - the medium the light shafts are
// drawn in, and the options for it. See BATCH_LOG.md 169.

// Which of the game's three media the camera is standing in, for the density
// below.
//
// isEyeInWaterFog rather than isEyeInWater: that alias is the pack's own, built
// in shaders.properties, and it is the one every stage is given. isEyeInWater
// itself is the mod's, and the composite stage does not have it - which is what
// left the underwater medium reading as air and the fog painted the grey
// underwater light. BATCH_LOG.md 174 is where that was found.
#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform int isEyeInWaterFog;
#endif

// The wind, for the medium to drift on: windTheta.w is its clock. The same
// custom uniform /environment/wind.glsl displaces the leaves with, so that the
// fog and the foliage move together. Uniforms: none
uniform vec4 windTheta;

// How much medium there is, by time of day: built in shaders.properties from the
// sun's height, because that is where the sun's position can be read. Uniforms:
// none
uniform float volumetricFogTimeFactor;

// And how much more of it there is in rain, built the same way and for the same
// reason. Uniforms: none
uniform float volumetricFogRainFactor;

// The pack's value noise, which the patches are built from. Uniforms: noisetex
#include "/lib/valueNoise.glsl"

// Which dimension this air is in, for the tint below.
#include "/environment/dimension.glsl"

// The End's palette: the colour its body is, and the colour its air takes.
#include "/environment/sky/end_palette.glsl"

// The colour the End's air is tinted with, and 1.0 everywhere else.
//
// Added in batch 340 at the user's request: the End has no sun, so what lights
// its air is the End's own body, and the air should therefore be the colour of
// that body rather than of the direct light. Which colour that is comes from
// environment/sky/end_palette.glsl, the same file the body itself reads, so the
// two cannot drift apart - the requirement was that they "stay consistent", and
// a second copy of the colour is not a way of staying consistent.
//
// ⚠️ It does NOT check whether the camera is under water, and that is on
// purpose. It is multiplied into the shafts' atmospheric colour only, never
// into their underwater one: the program that reads both already chooses
// between them with isEyeInWaterFog, so the water is excluded by where this is
// applied rather than by a second test here. Putting the test in both places
// would mean either one of them could be removed without anything looking
// wrong - which is how the two would drift apart. See BATCH_LOG.md 197.
vec3 VolumetricFogTint() {
	if (EndDimension()) {
		return EndPaletteColor();
	}

	return vec3(1.0);
}

// Volumetric fog: the air itself, and what the sun does inside it.
//
// Until b312 the shafts this pack drew were a screen-space trick - a blur that
// walked from each pixel towards the sun's position on screen, which is why
// they needed the sun to be on screen at all. This replaces that with what the
// effect actually is: a march through the air, asking the shadow map at each
// step whether the sun reaches that point of it. The consequences are worth
// stating, because they are what the change buys:
//
//   * The sun no longer has to be in view. Shafts come from light entering the
//     volume, and that light is there whether or not the thing giving it off is
//     on the screen - so the two fades the old version needed (one for looking
//     away from the sun, one for it going off the edge of the screen) are gone.
//   * The shafts stop at the same edges the world's shadows do, because they
//     are read from the same shadow map, with the same resolution.
//   * The medium has a height. Fog pools in valleys and thins with altitude,
//     which a blur along a screen-space ray cannot express at all.
//
// What it does not do, and this is deliberate rather than unfinished: it adds
// light and does not take any away. The extinction along the ray - the part
// that fades the far distance into the fog's colour - is the pack's existing
// fog model, which runs per fragment in the surface programs. Doing it here as
// well would count it twice. The split is therefore: the existing fog owns the
// colour and the fading, and this owns the light the medium scatters towards
// the eye. What a viewer sees is the two together, which is what fog looks
// like.
//
// Cost: VOLUMETRIC_FOG_STEPS shadow fetches per half-resolution pixel, plus a
// few instructions each. At the default of 16 that is about four full-resolution
// shadow fetches per pixel of the frame, which is roughly one full-screen pass.
// The buffer it writes is half resolution and three channels wide.

// Whether to draw the shafts and the medium that carries them.
//
// The name is the one the screen-space version used, and it is kept on purpose:
// it is referenced from the quality profiles in shaders.properties, from the
// menu, and from the lang files, and every one of those still means the same
// thing by it - whether this pack draws volumetric light. What changed is how.
#define GODRAYS

// How bright the scattered light is.
//
// Applied once, where the pass that draws the result reads the buffer, so that
// 1.0 is the value this pack has always drawn and the whole feature can be
// turned down to nothing without touching anything else. This is also the one
// option that is stored in the quality profiles, so changing what it means
// changes every profile at once - which is why it still means "how bright".
#define GODRAYS_STRENGTH 2.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]

// Whether the shafts are drawn with the camera under water.
//
// The colour and the brightness under water are already handled where every
// godrays colour is built - see godraysColor in shaders.properties, which
// switches to the underwater light and multiplies UNDERWATER_GODRAYS_STRENGTH
// in. What this switches is the medium itself, which is much denser down there.
#define UNDERWATER_GODRAYS

// How bright the shafts are under water, as a fraction of the same shafts above
// it. The medium is thicker under water, so this is usually set below 1.0 to
// keep the two comparable.
#define UNDERWATER_GODRAYS_STRENGTH 1.5 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]

// How thick the air is, per block, at the height the fog pools at.
//
// This is the master dial for how visible the whole effect is: raise it and
// valleys fill up, lower it and the shafts thin out. It is per block, so 0.01
// is an optical depth of one over a hundred blocks of the densest air.
#define VOLUMETRIC_FOG_DENSITY 0.004 // [0.0 0.002 0.004 0.006 0.008 0.010 0.015 0.025 0.04]

// How far up, in blocks, the fog has thinned to about a third of its density at
// the bottom. Larger values make a deeper layer that reaches higher.
#define VOLUMETRIC_FOG_HEIGHT 24.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0]

// The height the fog is measured from, in world blocks. 62 is Minecraft's sea
// level and where this was tuned, so the layer sits in valleys and along the
// water and thins out on hills. Raising it lifts the whole layer; lowering it
// puts the thick air below the surface, where only caves see it.
#define VOLUMETRIC_FOG_BASE 62.0 // [0.0 20.0 40.0 62.0 80.0 100.0 140.0]

// How far the march reaches, in blocks.
//
// Past this the medium is not sampled at all, which matters for cost as much as
// for looks: the steps are spread so that the last one covers the most ground,
// so the distance is nearly free to change. Beyond it the pack's own fog still
// fades the world out - that one is applied per fragment and has no distance
// limit, so shortening this does not leave a hole in the distance.
#define VOLUMETRIC_FOG_DISTANCE 96.0 // [32.0 48.0 64.0 96.0 128.0 192.0 256.0]

// How many steps the march takes. This is the cost.
//
// The steps are spread quadratically rather than evenly - see the pass - so
// most of them are spent in the first few dozen blocks, where the medium has
// its edges, and the far ones are allowed to be far apart.
//
// 24 rather than the 16 this started at, and it costs less than that did: the
// pass writes a quarter of the frame rather than half of it, so a step here is
// a quarter of the work it was. The extra steps are there because the medium
// now has patches of its own - see VOLUMETRIC_FOG_NOISE - and sampling them
// coarsely is what would put the bands back.
#define VOLUMETRIC_FOG_STEPS 24 // [8 12 16 24 32]

// How much structure the medium has.
//
// At 0 this is a smooth haze, which is what it was until the jumping was run
// down: a medium with no structure of its own leaves the shadow test as the
// only thing on screen that varies, so every discontinuity in it reads as the
// fog itself moving - and the shadow map is realigned in whole texels as the
// player walks. Giving the medium patches of its own, fixed to the world and
// drifting with the pack's wind, is what makes it read as fog instead. It is
// what Sundial does, and BATCH_LOG.md 172 is where that was worked out.
//
// At 0.6 the patches show; at 1.0 the medium is all holes and blobs.
#define VOLUMETRIC_FOG_NOISE 0.6 // [0.0 0.2 0.4 0.6 0.8 1.0]

// How large the patches are, in blocks. Larger is a softer, wider fog; smaller
// is a broken-up one.
#define VOLUMETRIC_FOG_SCALE 90.0 // [30.0 45.0 60.0 90.0 128.0 192.0 256.0]

// How many layers of noise are summed. More is finer detail, and each layer
// costs two noise fetches per step of the march.
#define VOLUMETRIC_FOG_OCTAVES 2 // [1 2 3]

// How much smaller each layer is than the one before, and how much weaker.
#define VOLUMETRIC_FOG_OCTAVE_SCALE 2.8 // [2.0 2.4 2.8 3.2]
#define VOLUMETRIC_FOG_OCTAVE_FADE 0.45 // [0.2 0.3 0.45 0.6]

// How much the fog follows the time of day.
//
// At 0 the medium is the same all day. At 1 it follows the curve built in
// shaders.properties: thickest at sunrise and sunset, thinning through the
// morning until noon is nearly bare, and building again through the night
// towards the next sunrise. Morning mist and evening mist are one thing seen
// from two sides, which is why a single curve covers both.
#define VOLUMETRIC_FOG_TIME_VARIATION 1.0 // [0.0 0.25 0.5 0.75 1.0]

// How much thicker the medium is in rain.
//
// At 0 the rain does not change anything. At 1 the fog is twice as thick at full
// rain, and the value scales from there. What it follows is the mod's weather
// strength rather than a flag, and it is squared, so a drizzle thickens the fog
// a little and a thunderstorm closes the view in, with no step between the two.
//
// It drives two things, and the second is the one that shows. The factor is
// built in shaders.properties, because rainStrength is a quantity that file can
// read and a shader cannot be sure of - the trap shadowDistance set in
// BATCH_LOG.md 171. It multiplies this medium's density, and it is also what
// environment/fog.glsl scales the pack's own atmospheric fog by: a thicker
// medium barely shows in rain, because rain is what hides the shafts the medium
// scatters, while the distance fading out is what a viewer sees. Sundial does
// the same at its atmosphere's optical depth - see BATCH_LOG.md 177.
#define VOLUMETRIC_FOG_RAIN_STRENGTH 0.5 // [0.0 0.5 1.0 1.5 2.0 3.0]

// Whether to march and store the fog at the full resolution of the frame.
//
// Off is a quarter of the frame, which is what this has always been and what
// the default step count is tuned for, and the size of the buffer is switched
// to match in shaders.properties.
//
// This is not a quality setting to reach for casually. The march is the most
// expensive thing this pack does, and at full resolution it costs sixteen times
// what it costs at a quarter - it stops being a pass's worth of work and
// becomes a second frame's. It is here because it is the only way to see what
// the upscale's blur was hiding: the shafts and the edges of the fog patches
// are what it sharpens.
//
// The #ifdef, and not #if defined, is what makes it a switch in the menu at all
// - see BATCH_LOG.md 169.1, where that cost a round trip. The pass reads the
// same macro to know which buffer it is looking at.
//#define VOLUMETRIC_FOG_FULL_RES

// The Nether's smoke columns.
//
// Requested in batch 344, after the user's verdict on batch 342's attempt at the
// same thing: that batch put a distance haze in environment/fog.glsl, and what
// they wanted was Bliss Shader's Nether plumes - a field of vertical columns of
// smoke, not a uniform reddening of everything with distance. The technique here
// is that shader's, ported onto this file's own noise and clock.
//
// ⚠️ Why it lives in this pass and not in fog.glsl, which is the obvious home
// for a dimension's fog. Two reasons, and the second is what decided it:
//
//   * this pass is a march through the air, which is what columns of smoke need
//     and what a per-fragment distance term cannot express at all;
//   * ⚠️ this pass runs over the finished frame. Batch 342's haze was applied in
//     the geometry programs, where "is this the Nether" is answered by the
//     dimension uniform - and Distant Horizons and Voxy compile their terrain
//     with EXTERNALLY_DEFINED_UNIFORMS, which makes that uniform a constant
//     zero. Their terrain was therefore told it was not in the Nether and got no
//     haze, while the game's own chunks did, and the seam between the two was
//     visible. A pass over the frame cannot have that problem: whatever it draws
//     is on top of every program's output, whoever drew it.
//
// ⚠️ What this pass cannot do is darken. It writes the light the medium scatters
// towards the eye, and that buffer is added to the frame - there is no
// transmittance term and no channel to carry one. So these columns are smoke
// that GLOWS rather than smoke that blots light out, which is the half of
// Bliss's effect that fits. The other half - a column darkening what is behind
// it - would need this pass to write a multiplier as well, and that is a change
// to the buffer and to the pass that reads it rather than something to add here.
//
// ⚠️ One switch covers all three of the Nether's media, and this key names only
// the first of them: the ceiling smoke and the thin haze sit inside the same
// #ifdef, because they are one picture - columns standing in a bed at the bottom,
// a layer under the roof, and a tint over the air between them - and there is no
// reading of the dimension that wants one of the three without the others. A
// reader looking for a switch for the haze on its own will not find one, and
// batch 534 left it that way on purpose: this key is referenced by every quality
// profile in shaders.properties, by the menu and by both lang files, so renaming
// it would reset a player's saved setting to change nothing about what it does.
// NETHER_HAZE_DENSITY at 0.0 is how to take the haze away and leave the columns
// standing.
#define NETHER_PLUMES

// How much of it there is.
//
// ⚠️ The shipped default is 2.0 as of batch 534, tuned in game by the author
// along with the rest of this page. The history is worth keeping, because each
// value answered a report: 1.0 is what this first shipped at, 1.5 was the v0.7
// release value, 3.0 came in with batch 529, and 2.0 is what batch 534 settles
// on - paired, now, with the emission NETHER_PLUME_OPTICAL carries. That 1.5 was
// the v0.7 release's value, and the v0.7 retune is what CHANGELOG.md lists under
// that version rather than these.
//
// ⚠️ What it multiplies is both halves of what smoke does, and both of them are
// in the pass: the emission (the line that builds `emission` in
// program/post/volumetric_fog.fsh) and the absorbance charged per block (the
// `absorbance *=` line under it). ⚠️ Not the field itself: NetherPlumeDensity
// below never reads this option, so what moves is the light the field carries
// and the optical depth of a sight line through it, not where a column is or how
// wide it is.
//
// ⚠️ And that is why no value of it moves DEBUG_PLUME_DENSITY, the view batch 527
// was diagnosed with: that view calls NetherPlumeDensity and nothing else, and
// that function never reads this option, so this dial cannot put one more pixel
// of density on it. The dials that DO move it are the ones inside that function:
// NETHER_PLUME_CLEAR, which multiplies the whole field at its source and is drawn
// into the view along with it, and NETHER_PLUME_HEIGHT_SCALE, whose default batch
// 534 took from 25 to 20 - at the roof fade's own start, thirty-eight blocks
// above the base, the rise falloff is 15.0% where the old 25 gave 21.9%, so that
// view comes out thinner at the top than it did and no brighter anywhere.
//
// ⚠️ The trade this option carries is the extinction with it, and it is priced
// here rather than discovered in game. A sight line's optical depth is the plume
// along it, times NETHER_PLUME_ABSORPTION, times this, times the distance, times
// NETHER_PLUME_EXTINCTION, and a transmittance is exp() of the negative of that.
// At the pair batch 534 ships - this 2.0, the extinction 0.03 - a column's core
// of 0.5 keeps 30.1% of what is behind it over twenty blocks and 0.31% over the
// whole 96-block march, and the field at its own mean plume of 0.353 keeps 42.9%
// and 1.71%.
//
// ⚠️ Every other figure that has stood in this note is an earlier pair's and is
// kept here as such: 2.7%, 7.9% and five parts in a million are batch 529's, this
// option at 3.0 with the extinction at 0.06; 16.5% and 28% are batch 528's at the
// 1.5 it shipped; and the 1.9%, 54%, 1.3%, 88%, 4.2% and 0.2% that collected here
// were several different pairs read as one. The extinction option's note names the
// pair behind each of those it can account for, and the 88% is the one it cannot,
// for a reason worth having in front of you: at the mean plume of 0.353 with this
// option at 3.0 and the extinction at 0.03, the twenty-, fifty- and 96-block rows
// are 28%, 4.2% and 0.2%, so the 88% is not that pair at any distance this note
// uses either.
//
// ⚠️ What it does not do is change the light a given amount of smoke puts out:
// that is NETHER_PLUME_OPTICAL, and the two are separate dials on purpose - this
// one thickens the medium and brightens it together, that one brightens it alone.
#define NETHER_PLUME_DENSITY 2.0 // [0.0 0.5 1.0 1.5 2.0 3.0 4.0 6.0]

// How much the plumes fade what is behind them, per block of column that the
// ray crosses.
//
// ⚠️ 0.0 is the null case: the columns still glow, and they take nothing out of
// what is behind them at all, which is exactly how this pass behaved before
// batch 521.
//
// ⚠️ The shipped value is 0.03 as of batch 534, and it has been 0.03, 0.06 and
// 0.03 again: batch 528 raised it because a column that leaves what is behind it
// alone has no edge to read against the lava, and the report was that the plumes
// read as a wash of haze with no outline to them; batch 534 brings it back down,
// where the author's tuning pairs it with a density of 2.0 - and the product of
// those two numbers is what every figure in this note is made of.
//
// ⚠️ What it does, exactly: a sight line's optical depth is the plume along it,
// times NETHER_PLUME_ABSORPTION, times NETHER_PLUME_DENSITY, times the distance,
// times this, and the transmittance is exp() of the negative of that. At the pair
// batch 534 ships - density 2.0, this 0.03, a product of 0.06 - a column's core
// of plume about 0.5 keeps 30.1% of the light behind it through twenty blocks and
// 5.0% through fifty, and 0.31% over the whole 96-block march; the field at its
// own mean plume of 0.353 keeps 42.9% and 1.71%. ⚠️ Batch 529's pair - density
// 3.0 with this at 0.06, a product of 0.18 - is three times that, and a
// transmittance is exp() of a negative depth, so every figure above is that
// pair's own raised to the power one third: the core's twenty blocks were 2.7%
// and its whole march was nothing measurable, and the mean's twenty blocks were
// 7.9% and its whole march five parts in a million.
//
// ⚠️ The rest of the figures this note has carried belong to the pairs that
// produced them, and keeping them apart is the point - reading them as one is
// what this note keeps getting wrong. Batch 528 measured 41% and 17% for a core's
// twenty blocks at density 1.5 with this at 0.03 and then 0.06, and 74% and 55%
// for the mean plume of 0.168 it had then, with 23% and 5.5% for the whole
// 96-block march at that same mean. Its 0.10 row - 5.0%, 36% and 0.8% - was the
// top of the range that batch was given, and it is the reason 0.10 is not the
// shipped value: a vista that transmits eight parts in a thousand is a wall
// rather than a place. The 1.9% it records for the whole march is the mean the
// contrast raise had just taken the field to, about 0.22, with this at 0.06 and
// the density at 1.5 - not the mean of 0.353 batch 529 measured afterwards. And
// the 28%, 4.2%, 54% and 0.2% that stood beside it in this note are pairs that
// never shipped at all: at the mean of 0.353 the twenty-, fifty- and 96-block rows
// are 28%, 4.2% and 0.2% with the density at 3.0 and this back at 0.03 - the
// density batch 529 raised and the extinction batch 528 had already left - and 54%
// is that same mean's twenty-block row at the density of 1.5 that this 0.03 was
// paired with before batch 528 raised it.
//
// ⚠️ NETHER_PLUME_SHADING below is the other dial on how much of a column's own
// glow survives to the eye at distance; this one is the dial for what is BEHIND
// the column.
#define NETHER_PLUME_EXTINCTION 0.03 // [0.0 0.01 0.02 0.03 0.06 0.08 0.12]

// How much of a column's own glow survives the smoke in front of it, as a power
// on the absorbance the march is holding.
//
// ⚠️ This is what gives a column a near face and a far face. Every term of the
// emission is a function of the local density and of nothing else, so on its own
// it cannot say where a sample sits inside the volume: a sample in the middle of
// a column and one at its near face come out identical, and what the eye is
// given is a soft blob with no form in it. Weighting the glow by the absorbance
// the ray has already paid puts the light on the outside of the column, where
// the smoke between it and the eye is thinnest - near face lit, far face dark -
// and the outline then comes out of the march rather than out of a blur.
//
// ⚠️ It weights the plume's emission only. The ceiling smoke and the haze go in
// at full weight, neither of them having an inside to have a near face - see the
// pass.
//
// ⚠️ The exponent the plume's light actually arrives with is this PLUS ONE,
// because batch 524 already multiplies the whole in-scatter by the absorbance
// once, in the front-to-back order the integral is written in. At the shipped
// 2.0 the combined exponent is 3.0: a column that has already taken half of what
// is behind it dims the glow behind it to an eighth, where one absorbance would
// leave it at a half.
//
// ⚠️ 0.0 is the null case and restores exactly what the pass did before this
// option existed - the two multiplies fall back to batch 524's one. 1.0 is one
// more factor of absorbance, and 3.0 is the far end, where only the skin of a
// column is lit and a thick one is dark inside. It shapes the glow and nothing
// else: it adds no extinction of its own, and it cannot brighten anything, since
// its weight is one at the eye and falls from there.
#define NETHER_PLUME_SHADING 2.0 // [0.0 0.5 1.0 1.5 2.0 3.0]

// How much of a column's light sits in its core rather than being spread evenly
// across its width: the core-to-edge gradient.
//
// ⚠️ What it is for, in the author's words: the plumes should be paler towards a
// column's edge and richer and deeper towards its middle. Until this option the
// emission was a function of the local density and of nothing else, and although
// that does make a core brighter than a gap it gives a column no shape of its own
// across its width: two points at the same density came out at the same colour
// whether one was at the middle of a column and the other at its rim, so a column
// read as a stripe of light with soft sides rather than as a mass with a middle.
//
// ⚠️ Where the shape comes from, and why it costs nothing. The density
// NetherPlumeDensity returns already peaks at a column's core: the pillar field
// is read in the horizontal plane only, lifted and clamped at one and then carved
// by the erosion, so a sample in the middle of a column comes back at the top of
// that range while a sample at the same column's thin outer edge comes back near
// zero. That number is in hand at every step of the march, so the gradient is one
// smoothstep of it and two mixes - no fetch, no extra step, and nothing added to
// the density function or to its signature, which the debug views call.
//
// ⚠️ The core is NETHER_PLUME_CORE_DENSITY, 0.5, and that is not an arbitrary
// number: it is the "column's own half density" every figure in the options above
// is quoted at, and the field's own measurements put a typical surviving pillar
// at a median of 0.51 while the layer as a whole averages 0.353. So coreness
// reaches one at a typical pillar's middle, is about 0.79 at the layer's mean and
// falls to zero in the gaps - which is the gradient that was asked for, with the
// thin parts of the field taken down and the cores left where they are.
//
// ⚠️ 0.0 is the null case, and exact rather than approximate: both mixes are
// written around the constants the pass already had, so at 0.0 the colour is
// exactly NETHER_PLUME_COLOR, the weight is exactly one, bit for bit, and the
// pass draws what it drew before this option existed. 0.6 is what ships, and it
// is a weight of 0.61 at the thin edge of a column, 0.65 on the bed at the foot
// of the layer - whose ceiling density is 0.10, so it is thin by construction -
// 0.92 at the layer's mean plume, and 1.00 from a column's half density upwards.
// 1.0 is the whole ramp, where the edge keeps NETHER_PLUME_EDGE_GAIN of its light
// and a core is the core colour.
//
// ⚠️ What it cannot do is put more light anywhere: the weight is one at coreness
// one and falls from there, so this only ever takes light away from the thin
// parts of the field, and it cannot raise the brightness of a core above what the
// options above set. That is the same rule NETHER_PLUME_SHADING and
// NETHER_PLUME_CONTRAST keep, and it is why the figures quoted in those options
// need no adjustment for this one: they are quoted at a plume of 0.5, where this
// option's weight is exactly one. What a viewer asking for more brightness wants
// is NETHER_PLUME_OPTICAL.
//
// ⚠️ It is not NETHER_PLUME_SHADING's job and the two do not overlap: shading
// weights the glow by what the ray has already crossed, which puts the light on a
// column's near face, and this weights it by where the sample sits across the
// column, which puts it in the middle. One is depth and the other is width. The
// pass says the same thing where the two are applied, and it is the reason the
// absorbance is deliberately not reused as a second ingredient here.
#define NETHER_PLUME_CORE_GRADIENT 0.6 // [0.0 0.2 0.4 0.6 0.8 1.0]

// How much smoke gathers under the ceiling: the amount of the flat layer, against
// that layer's own emission coefficient, NETHER_CEILING_SMOKE_OPTICAL below.
//
// ⚠️ Its key lost the bare "smoke" and gained "_DENSITY" in batch 534, and the
// reason is the name rather than the behaviour: this is a slider with an amount in
// it, and the old key read like the switch for the layer instead of like the
// quantity the slider sets. The three media on this page are now named the same
// way - a *_DENSITY for how much of it there is beside a *_OPTICAL for how much
// light a unit of it puts out - and this was the one of the three whose amount was
// not called one. The label in the menu moved with the key.
#define NETHER_CEILING_SMOKE_DENSITY 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]

// How thick the thin haze that fills the Nether's air is, as against the
// columns above it. It is the same everywhere in the dimension - no noise and
// no clock - and its colour is the game's own per-biome fog colour rather than
// anything of this pack's. See NetherHazeDensity below for both.
#define NETHER_HAZE_DENSITY 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]

// The height the columns stand on, and the height they thin out below, in world
// blocks.
//
// 32 is the Nether's lava sea level and where the smoke should start; 100 is
// under the bedrock roof.
//
// ⚠️ These are Bliss's numbers, 31 and 100, and they are first guesses for this
// pack rather than anything measured. If the smoke starts in the wrong place in
// game, this is the pair to move.
#define NETHER_PLUME_BASE 32.0
#define NETHER_PLUME_TOP 100.0

// How wide a column is, in blocks: the cell size of the field the columns are
// read from, and nothing else reads it.
//
// ⚠️ Its own number as of batch 527, and not the Overworld's VOLUMETRIC_FOG_SCALE
// that it was read at until then. That option is a scale for a fog bank: at its
// 90 blocks a cell, a 200-block vista of the Nether spans 2.2 cells, so the field
// the columns are made of had nothing in it to see at any distance a player
// stands at - one smooth gradient across the whole dimension, with the density
// varying by 1.4 to 1 over that vista and the light by 1.8 to 1. A test of the
// field that opened the batch came out at 0.00 to 0.02 of density along a
// 96-block sight line. The reference pack's own column field is about two orders
// of magnitude finer than 90, which is the other half of why this was never
// going to stand in columns.
//
// ⚠️ 26 is the default, and it is the middle of the list on purpose. It puts 7.7
// cells across a 200-block vista; with the contrast below, the pillar cores that
// come out of it measure a median of 27.6 blocks across with 10 of them in that
// vista and the widest at 49 - the 15-to-35-block columns this is for. Lower is a
// finer, more broken field of thin plumes, 8 being the finest here; higher is
// fewer and broader towers, and at the top of the list the cores merge into
// masses tens of blocks across, which is the flat wash this batch exists to take
// away. The Overworld's patches still move with VOLUMETRIC_FOG_SCALE and are not
// affected by this one.
#define NETHER_PLUME_SCALE 26.0 // [8.0 12.0 18.0 26.0 40.0 64.0]

// How far the columns are lifted before they are squared and carved, as a
// multiplier on the noise.
//
// ⚠️ The other half of batch 527, and the arithmetic is the argument. The plume
// is max(columns * columns - (1.0 - erosion), 0.0), with columns a value noise
// between zero and one whose square has a mean of about 0.27, while
// (1.0 - erosion) has a mean of 0.35. Subtracting the larger from the smaller
// takes most of the field below zero: 26.1% of the layer came out with any pillar
// density at all, and the median of what survived was 0.095. Against the haze,
// which is a flat 0.00025 of light per block, a median pillar's own light is
// 0.00010 - so the thin haze was two and a half times the columns at their
// median and nineteen times them averaged over the layer, which is exactly the
// report this batch answers: fog visible, no pillars. ⚠️ Those two light figures
// are batch 527's own and are quoted at batch 527's pair, optical 0.016 and
// density 1.5, with no absorbance weighting on either side - the haze carries
// none by construction and the column's figure here is emitted light, as the
// emission figures in this file are unless they say otherwise. At the pair batch
// 534 ships that same median pillar of 0.095 emits 0.0026 per block, which the
// core gradient's weight of 0.65 takes to 0.0017 - about seven times the haze
// rather than a third of it, before the march has weighted anything. Lifting the
// noise before the square moves the subtraction's bite down the distribution, so
// the erosion still carves and there is more field for it to carve: at the
// shipped 1.4, 64.6% of the layer carries pillar density instead of 26.1%, the
// mean plume goes from 0.034 to 0.168, the columns' own light comes out at 1.4
// times the haze instead of 0.35 times it, and the emission's 90th percentile
// goes up sixfold.
//
// ⚠️ Held at one after the lift, and that is what keeps this a shaping term
// rather than a second brightness option. Both NETHER_PLUME_OPTICAL and
// NETHER_PLUME_EXTINCTION are tuned against a density that tops out at 1.0 - the
// emission curve and the optical depth per block both read that number directly
// - and an unclamped lift puts the cores at 1.96 and drags both of them up with
// it. It is also what the plateau on a column's core is: a dense column seen
// from outside is a solid core with soft edges, not a spike.
//
// ⚠️ Batch 534 moved NETHER_PLUME_DENSITY again - from the 3.0 batch 529 raised
// it to, down to 2.0 - and did not touch this, so the measured figures above are
// still the shape's own, and so is the mean plume below, which no value of the
// density can move: it is batch 528's own measurement of the shape, 0.353 at the
// 1.7 that shipped with it against the 0.260 the same measurement gives at 1.4.
// NetherPlumeDensity never reads the density option, so what that option
// multiplies is the light the field carries - the emission and the optical depth
// in the pass - and not the field: a mean of two times 0.353 is not a state the
// clamp can produce, since the field stops at one. What the clamp guarantees is
// unchanged, and that is the reason the density could be moved either way without
// the contrast having to follow it.
//
// ⚠️ 1.0 is the null case, and it is the value to compare against when asking
// what this term did: the field is then exactly what it was before the option
// existed. 1.2 is a lighter touch - 4.6% of the layer in cores rather than 18.6%
// - and 2.0 and up is a wall of smoke rather than a field of columns.
//
// ⚠️ Raised from 1.4 to 1.7 in batch 528, and a measurement is what sets it,
// because what this term does is widen the cores rather than brighten them: the
// clamp holds a lifted core at one, so no value of this can put a column above
// the density the emission curve and the optical depth are tuned against, and
// what a higher value buys is that more of the layer sits at that ceiling.
// Measured on the noise itself, the fraction pinned at the clamped one goes from
// 20.0% at 1.4 to 36.8% at 1.7, the fraction carrying any pillar density from
// 62.5% to 72.7%, and the mean plume from 0.260 to 0.353 - that mean is the
// figure the paragraph above records as 0.168 at 1.4, so what 1.7 adds is about
// a third more smoke, spread over wider cores.
//
// ⚠️ And 1.7 is where it stops, which is the check batch 528 was asked to make
// before raising this. The ceiling takes 41.6% of the layer at 1.8, 49.9% at 2.0
// and 56.7% at 2.2: past that the columns' own noise is no longer shaping the
// field over most of the area, what is left is the erosion field, and the flat
// maximum the clamp exists to keep at a column's core has become the layer. 1.7
// is the highest value on the slider that still leaves more than a quarter of the
// layer empty - 27.3%, so the gaps between columns are still gaps - and it is the
// value that answers the report without taking the field apart.
#define NETHER_PLUME_CONTRAST 1.7 // [1.0 1.2 1.4 1.7 2.0 2.5]

// How far a column thins out as it rises, in blocks: its density falls to about
// a third of the base value over this height. ⚠️ It is exp() of the height above
// NETHER_PLUME_BASE divided by this, so one of these leaves exp(-1) = 36.8% of
// the density, which is the "about a third" - and half of one leaves 60.7%.
//
// ⚠️ Without it the columns are as thick between the lava and the roof fade as
// they are at the lava, because the only height term above that was the roof
// fade at seventy. A plume that does not thin as it rises reads as a bar rather
// than as smoke.
//
// ⚠️ The shipped value is 20.0 as of batch 534, down from the 25.0 that shipped
// from batch 525, and it moves the whole column above the lava: at 25 the smoke
// ten blocks up kept 67.0% of what it is at the lava and twenty blocks up 44.9%,
// and at 20 those are 60.7% and 36.8%. Where it shows most is the top of the
// layer, at the roof fade's own start thirty-eight blocks above the base - 21.9%
// at 25 against 15.0% at 20 - so the columns now thin out well before they meet
// the fade instead of arriving at it still half thick.
//
// ⚠️ It moves DEBUG_PLUME_DENSITY as well, and that is not true of every option
// on this page: the view calls NetherPlumeDensity, and this term is inside it -
// the density option's own note has the list of which dials reach that view and
// which do not. Every figure above is a figure of that field, before any light is
// put on it.
//
// ⚠️ A slider as of batch 525, and its two ends are the two failure modes. Low is
// a short plume - at 10 the smoke is down to 36.8% after ten blocks, so the
// columns are stubs standing on the bed - and high is a tall one: at 50 they keep
// 46.8% of their density all the way up to where the roof fade begins, which is
// the full-height bar this term was added to take away, so the top of the range
// is where batch 523 stops being visible.
#define NETHER_PLUME_HEIGHT_SCALE 20.0 // [10.0 15.0 20.0 25.0 35.0 50.0]

// The bed the columns stand in: how far up it reaches, in blocks, and how dense
// it is against the columns above it.
//
// ⚠️ The columns need it because the layer's floor fade is a ramp rather than a
// surface: without a bed they simply start part way up that ramp, which reads as
// columns standing in mid-air with the gaps between them empty all the way down
// to the lava. The bed fills those gaps at the bottom, so the columns rise out
// of something instead of starting in nothing.
//
// ⚠️ It is shaped by the erosion the columns are already eroded by, read from
// the same fetch - see NetherPlumeDensity - so the bed churns on the same clock
// as the smoke standing in it, at no cost of its own. And it is inside the same
// gates as the columns: the floor fade, the roof fade, the bubble around the eye
// and the rise fade all multiply it, so it cannot appear where they cannot.
//
// ⚠️ Both are sliders as of batch 525. The scale is how far up the bed reaches, in
// blocks: low is a skin of smoke lying on the lava, high is a bed that climbs far
// enough to meet the bottom of the columns. The amount is how dense the bed is
// against the columns: 0.0 takes the bed away and leaves the columns standing in
// mid-air again, exactly as they did before batch 524, and 1.0 makes the foot of
// the layer as thick as the columns standing in it.
//
// ⚠️ And the amount's default has come down twice: 0.55 to 0.25 in batch 527,
// and 0.25 to 0.10 in batch 528, because the masking it was doing was measured
// both times and both times it was the larger half of the report. The bed is
// this amount times the erosion, which is value noise brought into 0.3 to 1.0 -
// so at 0.55 it sits at a median of 0.36 before the height falloff, against a
// median surviving pillar of 0.095 at the same point; the bed was the thicker of
// the two over 88.9% of the layer, and what a player standing on the lava sea
// saw was the bed's own smooth mottling with the columns buried inside it: fog,
// and no pillars. At 0.25 it is 0.16 at its median against a median surviving
// pillar of 0.43, and it is the thicker of the two over 43% of the layer. At
// 0.10 it is 0.065 at its median, against a median surviving pillar of 0.51 at
// the contrast above - about eight times thinner.
//
// ⚠️ What settles the value is the light rather than the density, and that is
// why 0.10 is enough where 0.25 was not. The emission curve is quadratic this
// far down it, so at the pair batch 534 ships the bed at its 0.10 ceiling emits
// 0.0029 of a white frame per block where a typical pillar at 0.51 emits 0.0522
// - eighteen times as much, and about twenty-eight times once the core
// gradient's weight is on the bed, which at a density of 0.10 keeps 0.65 of its
// light because a thin sheet is exactly what that option fades. Read at the foot
// of the layer, where the height falloff is one and the bed is at its thickest,
// the bed is the thicker of the two over 31.8% of it against 38.1% at 0.25. (The
// 43% above is a figure through the layer; this one is at its foot.) Those 31.8%
// are the gaps between the columns low down, which is the whole job this was
// added for; everywhere else the columns are what is seen, and the bed is felt
// as the smoke they rise out of rather than as a sheet they stand in.
//
// ⚠️ The 0.000109 and 0.00196 this paragraph used to carry were two different
// pairs read as one - the bed's figure at optical 0.016 with density 1.5, and
// the pillar's at 0.032 with 3.0 - and the eighteen they come to was the right
// answer to a sum with two different scales in it, because the ratio depends on
// the shape of the emission curve alone: every pair gives eighteen before the
// gradient, and the two densities it is made of are the same in all of them.
#define NETHER_PLUME_FLOOR_SCALE 8.0 // [4.0 6.0 8.0 12.0 16.0]
#define NETHER_PLUME_FLOOR_AMOUNT 0.10 // [0.0 0.10 0.25 0.4 0.55 0.75 1.0]

// How fast the plumes churn, and how much a column's own density offsets its churn.
//
// ⚠️ The clock both of these scale is the pack's wind - windTheta - which is the one the
// leaves and the clouds move on. The reference pack drives its erosion from
// frameTimeCounter at a flat rate instead, so what differs here is not how much motion
// there is but where it comes from: this smoke moves on the world's wind, and it does not
// move as a single sheet - see the third term of erosionAt below.
//
// ⚠️ 0.0 on BOTH is the null case: the erosion then lands exactly where it landed before
// batch 520, which is how to tell the new terms apart from everything else on screen.
//
// ⚠️ Both are sliders as of batch 525. Churn is how fast the noise drifts past, and its
// shipped value is 1.5 as of batch 534: 0.0 is the flat pre-520 rate, which does move and
// moves too slowly to see; 1.0 is the rate this shipped at from batch 520 to batch 533,
// about half a slice a second; 1.5 is a third again that coefficient - the coefficient is
// 0.05 plus 0.2 per unit, so 0.35 against 0.25 - which is about 0.77 of a slice a second;
// and 3.0 is nearly twice that again, where the drift is plainly visible. (⚠️ 0.55 of a
// slice a second is a slice in under two seconds, so the "works through a slice in about
// half a minute" an earlier version of this note put beside it was never this arithmetic
// and is gone.)
//
// ⚠️ Churn offset is the per-column offset, and an offset in the erosion's own slice
// coordinate rather than in blocks: at 0.0 every column churns in step, which is the
// reference pack's rigid scroll, and 12.0 is the value that separates them. What 12.0
// comes to is worth having in front of you, because it is the figure that shows what this
// option is: the offset is this times the column's own density, and one slice of that
// coordinate is about twenty blocks of world height - see the 2.4 and the 48 where
// erosionAt is built - so a fully dense column reads the erosion about eighty-four blocks
// higher up its own axis than a gap between columns does. That is what makes neighbouring
// columns roll out of step instead of the whole layer sliding past as one sheet, and the
// top of the range pushes them further apart still.
//
// ⚠️ Its key ended in "_RISE" until batch 534 and its label read "plume rise", and
// both are renamed here: "rise" promised a height this option controls none of.
// Nothing about it lifts a column, and what a reader moving it is moving is the
// spread of the churn between columns. The note the pass keeps on that term says
// the same thing in the same words.
#define NETHER_PLUME_CHURN 1.5 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define NETHER_PLUME_CHURN_OFFSET 12.0 // [0.0 4.0 8.0 12.0 20.0 32.0]

// How far around the eye the smoke is held off, in blocks.
//
// ⚠️ Not a detail. Without it the player stands inside a column and the screen
// is a wall of orange; the effect has to be something seen from outside. Bliss
// clears a bubble for exactly this reason.
//
// ⚠️ And 24 was twice what this needs, which is what batch 529 found. The
// bubble is a linear ramp with two ends and they cost different things: what it
// guarantees at 24 is that nothing is drawn within 24 blocks of the eye, but
// what it also does is scale the whole term - emission and extinction alike -
// by the distance out to 24, and the distance a player actually stands from the
// lava sea is inside that. It was the one suspect batch 527 did not touch, and
// the report it left standing is the report this batch opened with: one thin
// stripe on the horizon and nothing around the player.
//
// ⚠️ 8 is the default because it is the range at which that guarantee is still
// kept and its cost is not. It does not put the eye outside a column - a core
// at the shipped twenty-six-block cell measures about twenty-eight blocks
// across, so the eye can be well inside one - but it does mean the smoke within
// eight blocks is faded rather than removed, and the surface of a core is then
// fifteen blocks away through air that is back at full strength.
//
// ⚠️ And the ramp is the clamp itself rather than a curve: the factor is
// length(samplePos) / this, held between zero and one, so with 8 it is 0% at the
// eye, 50% at four blocks and back to full weight from eight blocks out, where
// 24 gave 33% at eight blocks and did not reach full weight until twenty-four.
// What that means in the hand is that "full strength" now starts eight blocks
// from the eye rather than twenty-four, and everything nearer than that is faded
// in a straight line down to nothing at the eye.
//
// ⚠️ The cost it does not keep is the one the reference pack's own bubble is
// for, and it is why this is a slider rather than a new constant: a player who
// walks into a column has three blocks of it between the eye and the near face,
// and at the pair batch 534 ships those three blocks EMIT 0.152 of a white frame
// between them - six and a half times the 0.023 the batch-533 pair put there.
// ⚠️ The ramp itself is untouched by any of the retuned values, and the figures
// above are still its own: 0%, 50% and full weight at nought, four and eight
// blocks, and 33% at eight blocks under the old 24. What moved is the light the
// ramp is scaling, so a screen turning orange is more true of the new defaults
// than it was of the old, not less. The range is wide on purpose - 16 and 24 are
// the old behaviour, and 4 is close to no bubble at all.
#define NETHER_PLUME_CLEAR 8.0 // [4.0 6.0 8.0 12.0 16.0 24.0]

// What the smoke glows with, and how its brightness falls off.
//
// ⚠️ Nothing lights this medium, because there is nothing here to light it: the
// Nether has no sun, so the shadow-map march below has no light to trace and the
// glow is the smoke's own.
//
// ⚠️ The brightness is the density times an exp() of the density - the
// (1.0 - exp(-NETHER_PLUME_ABSORPTION * density)) * 0.25 * density that
// program/post/volumetric_fog.fsh writes - and that is the shape of the effect
// rather than a detail of it: the curve climbs with the density, so the core of
// a column is the brightest part of it and its edges fall away. What that buys
// is legibility of the churn: what rolls past is a lit mass rather than a moving
// outline.
//
// ⚠️ It said the opposite until batch 527, and the code it described had already
// changed: the comment still claimed the curve "makes the smoke brightest where
// it is THINNEST", which is what exp(-density) did before batch 520 inverted it
// to exp() of the negative density inside the same expression. The inversion is
// written down where the curve is, in program/post/volumetric_fog.fsh, under
// "Inverted in batch 520" - which is the file to read beside this one, since
// that is where the emission is actually built.
//
// ⚠️ Bliss darkens its emission the other way, so that its plumes read as ropes
// with light behind them, and that is what this pack drew until batch 520. Its
// 15.0 is this same curve over a much smaller range, because its density is not
// normalised to one and this one is - which is the invariant the clamp in
// NETHER_PLUME_CONTRAST keeps.
//
// ⚠️ And as of batch 528 the whole of the difference is one line: Bliss's plume
// is a dark core with a bright thin edge and nothing else, while this one is lit
// in the core - which is what batch 520 inverted the curve to get, and what
// makes the churn legible - and lit again on its near face, because the emission
// is weighted by the absorbance in front of it. See NETHER_PLUME_SHADING. Ours
// keeps the bright core and gains the outline back, and it gets the outline out
// of the march rather than by inverting the curve a second time.
//
// ⚠️ Recoloured in batch 525, from vec3(1.00, 0.40, 0.16) to something nearer the
// lava's own orange. The author's report was that the plumes read as "not very
// visible" and suspected the colour was too pale, and part of it was this: the old
// green and blue were high enough that a column came out a pale grey-orange
// against the Nether's own fog, which is not what a hot medium looks like. The red
// is unchanged; the other two are pulled down and towards the lava below.
//
// ⚠️ And it stays a constant while the seven around it become sliders, because
// this pack has no colour option to follow: every colour-bearing option it has -
// RAIN_COLOR_SATURATION, END_STAR_TINT, LIGHT_TINT_STRENGTH - is a scalar that
// moves a colour the shader already holds, and colorwheel.properties is the
// loader's OIT configuration rather than a colour picker. Inventing a picker for
// one constant would be a convention of one. See batch 525.
const vec3 NETHER_PLUME_COLOR = vec3(1.00, 0.32, 0.09);
const float NETHER_PLUME_ABSORPTION = 2.0;

// The two colours the core-to-edge gradient ramps between, the density that
// counts as a core, and the share of its light the thinnest edge of a column
// keeps at full strength.
//
// ⚠️ Constants rather than options, for the reason the note above gives: this pack
// has no colour option to follow, so what is exposed is how far the ramp is
// pulled - NETHER_PLUME_CORE_GRADIENT - and not the colours it is pulled between.
//
// ⚠️ NETHER_PLUME_COLOR is where the ramp is anchored: it is the colour of the
// whole column at gradient 0.0, and of a core at the shipped 0.6 it is still 40%
// of the mix, the other 60% being the core colour. All three colours keep a red
// of exactly 1.00, which is what lets every emission figure in the options above
// be read as the red channel without adjusting it for the ramp.
//
// ⚠️ NETHER_PLUME_CORE_COLOR is the deeper, hotter end: less green and a third of
// the blue, which is the direction batch 525 took the base colour in when the
// plumes read as too pale - towards the lava's own orange rather than away from
// it. NETHER_PLUME_EDGE_COLOR is the pale end, a thin warm orange-grey, which is
// what the outside of a column should look like where there is almost nothing
// between it and the eye.
const vec3 NETHER_PLUME_CORE_COLOR = vec3(1.00, 0.16, 0.03);
const vec3 NETHER_PLUME_EDGE_COLOR = vec3(1.00, 0.58, 0.34);

// ⚠️ 0.5 for the core density is not a number picked for the ramp: it is the half
// density every figure in the options above is quoted at, and the median a
// measured pillar carries, so it is the field's own definition of a core. 0.35
// for the edge's share is where the pale end stops - an edge at a third of a
// core's light is a rim rather than a hole - and the gradient option's note has
// the weight that comes out of it at each of the field's own densities.
const float NETHER_PLUME_CORE_DENSITY = 0.5;
const float NETHER_PLUME_EDGE_GAIN = 0.35;

// How bright the smoke is: the emission's overall multiplier, and nothing else.
//
// ⚠️ Not how much smoke there is - that is NETHER_PLUME_DENSITY above - and not
// how much of what is behind it the smoke takes away either, which is
// NETHER_PLUME_EXTINCTION. This is the one number that scales the light the
// medium adds to the frame, and it leaves the medium's shape and its coverage
// alone.
//
// ⚠️ Doubled in batch 525, from 0.008 to 0.016, which puts it four times
// VOLUMETRIC_FOG_DENSITY rather than of the same order as it. The old comparison
// is gone because the two are not doing the same job: the Overworld's fog is lit
// by the sun and so needs only enough medium to catch it, while this one is its
// own light seen against a fog that already glows, and it needs more of it to
// read. The author's report was that the plumes were "not very visible"; this is
// the half of that which is about amount.
//
// ⚠️ A slider as of the same batch, and it has been moved twice since. 0.016 is
// the value that shipped from batch 525 to batch 528; 0.032 is batch 529's, which
// this note recorded at the time as the point past which the Nether stops being a
// place and becomes a lamp; 0.32 is what batch 534 ships, the author's own tuning
// in game, and it is ten times the one before it. ⚠️ The list is built around that
// value rather than ending on it: 0.32 sits sixth of ten, with five steps below
// it and four above, the nearest steps are a quarter of its own size (0.24 and
// 0.40), and the bottom of the list, 0.04, is about what the pair before this one
// put out - so the range is two builds of brightness either side of the tuned
// value, with no dead tail of settings nobody can see.
//
// ⚠️ And the old list ENDED at 0.032, which is worth remembering when reading the
// note that used to stand here: "0.32 is ten times this default, loud without
// being the lamp the old note feared" was written while 0.32 was the top of the
// range and could not be the default at all.
//
// ⚠️ Every figure below is against a reference frame brightness of 1.0 - white as
// the tonemap sees it - and with the emission's colour left out of it. The red
// channel is one in all three of the colours the core ramp uses, so a figure here
// is what that channel receives; NETHER_PLUME_COLOR has been vec3(1.00, 0.32,
// 0.09) since batch 525 and the two colours added beside it keep the same red.
//
// ⚠️ The emission is `(1.0 - exp(-2.0 * p)) * 0.25 * p * OPTICAL * DENSITY` per
// block of plume crossed at a local plume of p, before the core gradient's weight
// goes on it. At the pair batch 534 ships - OPTICAL 0.32, DENSITY 2.0 - that is
// 0.0506 per block at a column's own half density of p = 0.5, against 0.0076 for
// the pair batch 533 shipped (0.032 and 3.0) and 0.0019 for the pair before that
// (0.016 and 1.5), which is the figure batch 528 recorded as 0.00196 at a plume
// of 0.51. Those three are EMITTED light: light leaving the sample, with no
// absorbance weighting on it.
//
// ⚠️ What arrives at the eye is not that, and the difference is the trap this note
// has fallen into twice. A sample's light is weighted by the smoke in front of it
// twice over - pow(absorbance, NETHER_PLUME_SHADING) here and batch 524's own
// absorbance on the scatter, which is one more factor of the same thing - so a
// column's light arrives as the emission times absorbance raised to 3.0, and the
// mean of that over a crossing whose transmittance is T is (1 - T^3)/(3 * -ln T).
// At the shipped pair a half-density crossing has T = 45.8% and keeps 38.6% of
// its light, so the thirteen blocks a sight line crosses a column through (five
// of the 24 quadratic steps, in the ladder's middle) carry 65.7% of a white frame
// EMITTED and 25.4% of it ARRIVING. ⚠️ Every "arriving" figure in this note's
// earlier versions was really emitted light divided by a round quarter, which is
// why the two bases disagreed by a factor of four when a reader took them for
// one: the only figures here that are emitted are the ones that say so.
//
// ⚠️ On the arriving basis, and at the pairs named: a half-density crossing is
// 25.4% of the reference now, against 1.4% at batch 533's pair and 0.6% at the
// pair before it - which is the figure batch 529 opened with, and the report
// along with it, "a column that is half a percent of the frame is a column nobody
// can see". At the field's own mean plume of 0.353 the same crossing is 18.2%
// against 1.1% at batch 533's pair; through a saturated core of 1.0 it is 38.1%
// against 1.9% there and 1.0% at the pair before it. ⚠️ Batch 529 published 1.7%
// for that saturated core on its own quarter basis rather than on this one, which
// is the same discrepancy in miniature.
//
// ⚠️ The 0.25 inside that expression is where batch 529's fault was, and it is
// left exactly where it is. It came from batch 520, where it was the constant
// that kept the inverted curve's brightest point at what exp(-density) had given
// it - see the note in the pass - and it has been carried ever since as a
// normalisation rather than as a brightness. What it normalises is a quantity
// nothing here reads. It is kept because it is the null case for the sliders that
// were tuned around it: a reader moving this option is moving the same thing at
// 0.32 as they were at 0.032.
//
// ⚠️ And the comparison that decides whether any of that is seen is not against
// white but against the thin haze the columns stand in, because the haze fills
// the whole sight line while a column crosses it in thirteen blocks. The haze
// emits 0.00025 per block at its own density - it has no density multiplier of
// its own, so its light per block is flat, and it carries no absorbance weighting
// either, so that one figure IS emitted light - which puts a half-density
// column's emitted light at 202 times the haze's own radiance per block and its
// arriving light at 78 times it. Over a whole crossing that ratio is the same 78,
// the haze putting 0.00325 across the same thirteen blocks; against the haze over
// the full 96-block march, 0.024 of it, the column's 0.254 is about eleven times
// as much. ⚠️ The "about twice the haze's own radiance to about four times it,
// with 7.6 times at a core" this note used to carry was three different
// quantities in one sentence: the two and the four were arriving figures at the
// 0.016/1.5 and 0.032/3.0 pairs, and the 7.6 was the EMITTED figure of the first
// of those, read as though it belonged to the second.
//
// ⚠️ What the two ends of the list do, so they are known rather than discovered:
// 0.80 is two and a half times the shipped value, which puts the same thirteen
// blocks at 63.5% arriving - one column crossing most of the frame's brightness -
// and 0.04 is an eighth of it, 3.2% arriving, which is a glow that can be seen
// but is not a plume. Neither end is what ships.
#define NETHER_PLUME_OPTICAL 0.32 // [0.04 0.08 0.12 0.16 0.24 0.32 0.40 0.48 0.64 0.80]

// And the same for the smoke under the ceiling. It is a flat layer rather than
// columns, so it is charged separately and has a colour of its own - a dark
// neutral, which is what Bliss gives it and what smoke under a roof looks like.
const vec3 NETHER_CEILING_SMOKE_COLOR = vec3(0.10, 0.075, 0.070);

// ⚠️ A slider as of batch 525, and left at the value it shipped with rather than
// doubled along with the plumes': this layer is a dark neutral that reads as the
// roof over the dimension rather than as the effect itself, and the report was
// about the columns. 0.001 makes the roof all but disappear into the fog, 0.004
// is the shipped value, and 0.010 fills the ceiling with smoke.
#define NETHER_CEILING_SMOKE_OPTICAL 0.004 // [0.001 0.002 0.004 0.006 0.010]

// And the haze's own, the smallest of the three because the haze is the
// thinnest thing here. ⚠️ 0.001 is the reference pack's own number for this
// medium, taken as it stands rather than measured: at the shipped haze density
// it is an optical depth of one over a thousand blocks, which is a tint rather
// than a veil.
const float NETHER_HAZE_OPTICAL = 0.001;

// The noise the patches are made of, in three dimensions.
//
// The pack's noise texture is two-dimensional, so the third is faked by reading
// two slices of it and mixing between them - the standard trick, and two
// fetches where a real three-dimensional lookup would take eight. The slices
// are pushed apart by a number sharing no factor with the texture's width, so
// consecutive slices are not the same noise shifted sideways.
float VolumetricFogNoise(vec3 at) {
	float slice = floor(at.z);
	float blend = at.z - slice;

	float below = smoothNoise2D(at.xy + vec2(0.0, slice * 17.0));
	float above = smoothNoise2D(at.xy + vec2(0.0, (slice + 1.0) * 17.0));

	return mix(below, above, blend);
}

// How much medium there is at a world position.
//
// Three things multiply into it: how high the point is, which is the layer's
// shape; how much noise is there, which is its structure; and the density
// option, which is its amount.
//
// The height falloff is exponential rather than a hard layer, because that is
// what fog does - it thins out gradually - and the max() is what keeps the
// layer above its base rather than below it: at and under VOLUMETRIC_FOG_BASE
// the density is the full value and it falls off upwards from there, so the
// caves under the base do not end up with the thickest fog in the world.
float VolumetricFogDensity(vec3 worldPosition) {
	// The #ifdef, and not #if defined, is what makes UNDERWATER_GODRAYS a
	// switch in the menu rather than a constant - the same mistake was made
	// with INDIRECT_BOUNCE in b311 and it is written down in BATCH_LOG.md
	// 169.1 because it cost a round trip twice.
	#ifdef UNDERWATER_GODRAYS
		// Water is not air: the same medium, several times as thick.
		float denseness = isEyeInWaterFog == 1 ? 6.0 : 1.0;
	#else
		float denseness = 1.0;
	#endif

	float layer = exp(-max(worldPosition.y - VOLUMETRIC_FOG_BASE, 0.0)
		/ max(VOLUMETRIC_FOG_HEIGHT, 1.0));

	// The medium drifts on the pack's own wind. windTheta.w is that wind's
	// clock - the same one the leaves and the clouds move on - so the fog and
	// the world it sits in do not run on two different clocks. The 0.05 is
	// what turns a phase in radians into a distance in cells, and it is small
	// because this offset grows with time rather than cycling.
	vec3 wind = vec3(1.0, 0.0, 0.6) * windTheta.w * 0.05;

	vec3 at = worldPosition / VOLUMETRIC_FOG_SCALE + wind;

	float noise = 0.0;
	float weight = 1.0;
	float total = 0.0;

	for (int i = 0; i < VOLUMETRIC_FOG_OCTAVES; i++) {
		noise += VolumetricFogNoise(at) * weight;
		total += weight;

		at = at * VOLUMETRIC_FOG_OCTAVE_SCALE + wind;
		weight *= VOLUMETRIC_FOG_OCTAVE_FADE;
	}

	noise /= total;

	// Carved into patches rather than used as it comes: value noise is mostly
	// mid-range, and taking a band out of the middle of it is what turns a
	// uniform dimming into holes and blobs.
	float patches = smoothstep(0.35, 0.75, noise);

	// And the time of day, as a single number built in shaders.properties from
	// the sun's height: at its largest at sunrise and sunset, at its smallest -
	// zero - at noon, and part way up again through the night. Doing it there
	// rather than here because the sun's position is one of the quantities the
	// property file can read and a shader cannot be sure of - the same trap
	// shadowDistance set in BATCH_LOG.md 171.
	return VOLUMETRIC_FOG_DENSITY * denseness * layer
		* volumetricFogTimeFactor * volumetricFogRainFactor
		* mix(1.0, patches, VOLUMETRIC_FOG_NOISE);
}

#ifdef NETHER_PLUMES
	// The Nether's smoke columns, as a density at a world position.
	//
	// Bliss Shader's cloudVol(), ported onto this file's own noise and clock.
	// What makes its result stand in columns rather than in clouds is two things,
	// and they are worth separating before changing anything here:
	//
	//   * the field that makes the columns is read in the horizontal plane only,
	//     so it cannot vary up a column's height. That is what a column is;
	//   * the field that erodes them is read in three dimensions, but the
	//     vertical axis of it is squashed 48 to one first - so the erosion is
	//     slow vertically too, and the holes it carves are holes in a column
	//     rather than slices across one.
	//
	// Take the first out and the columns go; take the second out and they become
	// pipes; un-squash the second and they become weather.
	//
	// ⚠️ clearArea is passed in rather than worked out here. It is the bubble
	// around the eye, and it is a parameter because this file does not declare
	// cameraPosition - the pass that includes it does - so reaching for the
	// position here would be a dependency this file has no way to state. Bliss
	// splits it the same way, for what that is worth.
	float NetherPlumeDensity(vec3 worldPosition, float clearArea) {
		// The two ends of the layer, because the Nether has a floor and a roof and
		// the smoke should thin at both.
		//
		// ⚠️ Asked before the noise rather than after. The march puts most of its
		// steps outside the layer - a camera on a hill is above all of it - and a
		// step out there should cost a comparison rather than the four texture
		// fetches the erosion takes. It is the same early out the Overworld path
		// gets from VolumetricFogDensity returning exactly zero.
		float floorFade = smoothstep(
			NETHER_PLUME_BASE - 4.0, NETHER_PLUME_BASE + 10.0, worldPosition.y);
		float roofFade = 1.0 - smoothstep(
			NETHER_PLUME_TOP - 30.0, NETHER_PLUME_TOP, worldPosition.y);
		float layer = floorFade * roofFade * clearArea;

		if (layer <= 0.0) {
			return 0.0;
		}

		// And the second half of the layer's shape: a column starts thinning as
		// soon as it leaves the lava, rather than staying as thick as it is at
		// the bottom until the roof fade above picks it up.
		//
		// ⚠️ On top of the roofFade rather than instead of it, and the two do
		// different jobs: this one falls with the whole height of the column,
		// from its base, while the roof fade is still what takes the top of the
		// layer to nothing.
		//
		// ⚠️ At the base this is exactly 1.0 - the max() keeps it from climbing
		// below the layer, the same guard VolumetricFogDensity's own height term
		// has - so the floor is unchanged and what the columns lose is their top.
		float riseFade = exp(-max(worldPosition.y - NETHER_PLUME_BASE, 0.0)
			/ NETHER_PLUME_HEIGHT_SCALE);

		vec3 squashed = vec3(
			worldPosition.x, worldPosition.y / 48.0, worldPosition.z);

		// The columns lean, and lean more the higher they are, which is what makes
		// them read as something rising rather than as wallpaper.
		float lean = pow(
			max(worldPosition.y - NETHER_PLUME_BASE, 0.0) / 16.0, 2.1);

		// ⚠️ Read in the horizontal plane, and that is the whole of why this is a
		// column field: the sample has no y in it at all.
		//
		// ⚠️ VolumetricFogNoise has an axis convention - it reads its noise in xy
		// and steps through its slices in z - and the two horizontal axes happen to
		// be the ones it wants in xy, so this one needs no reordering. The next one
		// does.
		//
		// ⚠️ At NETHER_PLUME_SCALE and no longer at VOLUMETRIC_FOG_SCALE, which is
		// the fix batch 527 is named for: see that option for what 90 blocks a cell
		// did to this field, which was to leave it with nothing in it at the
		// distance a player sees it from.
		float columns = VolumetricFogNoise(vec3(
			(worldPosition.xz + lean) / NETHER_PLUME_SCALE, 0.0));

		// The erosion: a second field eating into them, drifting on the pack's own
		// wind clock so that they churn rather than standing still. The wind is the
		// one the leaves and the clouds move on, so the smoke does not run on a
		// clock of its own.
		//
		// ⚠️ The axes are reordered on the way in, and that is not cosmetic. The
		// slice axis of that noise is its z, so handing it (x, y, z) would make the
		// slice index follow world z - which changes with every fraction of a block,
		// and consecutive slices are unrelated fields. What comes out of that is not
		// eroded smoke but static. Handing it (x, z, y) makes the slices horizontal
		// layers of the world, which is what a density field wants, and drifting its
		// z is then drifting in world height - so the rise of the smoke comes out of
		// the same term as its shape rather than needing a second one.
		//
		// ⚠️ And the three axes are scaled apart on purpose: the squash already
		// makes world height slow (48 to one), and the extra factor here sets how
		// many blocks a slice lasts - about twenty. A single uniform scale cannot do
		// both that and the four-block features the horizontal axes want.
		// ⚠️ The clock is the pack's wind, as the note above says, and this is what turns
		// it into motion in the units the erosion is sampled in. At the shipped 1.5 the
		// coefficient below is 0.35 against the 0.25 that 1.0 gives - a third again the
		// drift rate - so what was about 0.55 slices a second at the 1.0 that shipped
		// from batch 520 to batch 533 is about 0.77 of one now, where a slice is about
		// twenty blocks. Before batch 520 the coefficient here was a flat 0.05, which is
		// 0.36 blocks a second: the field did move, and it moved too slowly to see.
		float churnPhase = windTheta.w * (0.05 + NETHER_PLUME_CHURN * 0.2);

		// ⚠️ And the third term is what makes a column ROLL rather than slide. The denser
		// a column is, the further up it the erosion is sampled, so every column churns at
		// its own rate instead of the whole world sharing one sheet of noise going past.
		// That, and not the speed, is what separates this from the reference pack's
		// rigidly scrolled field - and it is what makes the motion read as boiling rather
		// than as a texture being panned. It is NETHER_PLUME_CHURN_OFFSET's own term, and
		// at 0.0 it is not there and every column churns in step.
		vec3 erosionAt = vec3(
			squashed.x * 0.22,
			squashed.z * 0.22,
			squashed.y * 2.4
				+ churnPhase
				+ NETHER_PLUME_CHURN_OFFSET * columns * 0.35);

		float erosion = VolumetricFogNoise(erosionAt) * 0.7 + 0.3;

		// The bed at the foot of the layer, from the erosion that is already in
		// hand: see the options above for what it is for. Read as a density of
		// its own rather than as something subtracted from the columns, which is
		// why it takes the erosion as it comes and not (1.0 - erosion).
		//
		// ⚠️ The same value, and that is the point of doing it here: the bed
		// costs no fetch and no second clock, and it churns exactly when the
		// columns standing in it do.
		//
		// ⚠️ erosion is in [0.3, 1.0] - it is value noise brought into that band
		// - so the bed sits between a third and all of the floor amount, and
		// never at nothing, wherever it is.
		//
		// ⚠️ exp() of the height above the base, with the max() that keeps it
		// flat at and below the base: the same guard every other height term in
		// this file has, and without it a cave under the lava would be given a
		// thicker bed than the lava sea it is under.
		float floorFalloff = exp(-max(worldPosition.y - NETHER_PLUME_BASE, 0.0)
			/ NETHER_PLUME_FLOOR_SCALE);
		float floorBed = NETHER_PLUME_FLOOR_AMOUNT * erosion * floorFalloff;

		// ⚠️ Subtracted rather than multiplied, and that is what makes it smoke
		// rather than a sponge. Multiplying would only dim the field everywhere
		// the erosion is low; subtracting takes pieces of it away outright, so
		// that the gaps between columns are gaps and the light comes through them.
		//
		// ⚠️ And the square on the columns before that subtraction is what keeps
		// the field mostly empty. Value noise is mid-range almost everywhere, so
		// subtracting a constant from it would leave a sheet of thin smoke and a
		// few holes; squaring first pushes the low half towards zero and leaves
		// the subtraction something to bite on.
		//
		// ⚠️ What the square has in front of it as of batch 527 is
		// NETHER_PLUME_CONTRAST, and it is on the columns rather than on the
		// squared field because it is the shape of the noise that is wrong and not
		// the amount of smoke: without it the square's mean of 0.27 sits under the
		// erosion's mean of 0.35 and the subtraction takes three quarters of the
		// layer to nothing. The clamp is on the lift and not on the result, so a
		// column's core is a plateau at one and the erosion still carves it.
		float bodied = clamp(columns * NETHER_PLUME_CONTRAST, 0.0, 1.0);

		float plume = max(bodied * bodied - (1.0 - erosion), 0.0);

		// ⚠️ max() rather than a sum, and that is what makes this a bed rather
		// than brighter feet. Added, it would raise the columns' own bases -
		// already the densest part of the layer - and leave the gaps between
		// them as empty as they were. A max fills those gaps instead, and where
		// a column is already denser than the bed the column is what comes out,
		// unchanged. An argument of a max() is never lowered by the other, so no
		// point in the layer is left thinner than it was before the bed.
		return max(plume, floorBed) * layer * riseFade;
	}

	// The smoke that gathers under the ceiling.
	//
	// A flat layer rather than a column field, which is why it shares nothing with
	// the function above but the clock: Bliss's has no noise in it at all, and
	// what gives it its shape is the third power of the height above y=40.
	float NetherCeilingSmokeDensity(vec3 worldPosition) {
		float layer = pow(
			clamp((worldPosition.y - 40.0) / 50.0, 0.0, 1.0), 3.0);

		return layer * NETHER_CEILING_SMOKE_DENSITY;
	}

	// A very thin haze that fills the Nether's air rather than gathering into columns.
	//
	// ⚠️ Its colour is the game's own fog colour, which is a per-biome value, so the
	// crimson forest, the warped forest, the soul sand valley and the basalt deltas each
	// get their own tint without this pack declaring a single new uniform. That is the
	// whole reason it is written this way rather than with a colour of our own.
	//
	// ⚠️ worldPosition is not read, and that is the rest of the same decision: the
	// density is a constant, so there is nothing about the point to ask. It is a
	// parameter so that this is called like the two functions above it.
	float NetherHazeDensity(vec3 worldPosition) {
		return NETHER_HAZE_DENSITY;
	}
#endif // NETHER_PLUMES
