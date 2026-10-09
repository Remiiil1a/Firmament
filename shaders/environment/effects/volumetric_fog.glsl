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
#define NETHER_PLUMES

// How much of it there is.
//
// ⚠️ The shipped default is 1.5 as of v0.7: the user raised it from the 1.0 this
// first shipped at, and that is the setting the release uses. The retuned
// defaults are listed in CHANGELOG.md under v0.7.
//
// ⚠️ Raised to 3.0 in batch 529. What that batch answered was not a shortage of
// smoke - it was the opposite of what the sliders suggested had been tried. The
// emission's own scale was the fault (see NETHER_PLUME_OPTICAL), but this dial
// was being asked for and the arithmetic now backs it: a typical column's
// radiance doubles along with it, and so does every optical depth below.
//
// ⚠️ What it does NOT change is the debug view that batch was diagnosed with,
// and that is worth saying plainly: DEBUG_PLUME_DENSITY calls NetherPlumeDensity
// and nothing else, and that function never reads this option at all. The two
// places that do are the emission and the absorbance in the pass
// (program/post/volumetric_fog.fsh:337 and :435), so 3.0 brightens and thickens
// every column without putting one more pixel of density on that view. The dial
// that does move it is NETHER_PLUME_CLEAR, which multiplies the whole field at
// its source and is drawn into the view along with it.
//
// ⚠️ It doubles the extinction with it and that is a real trade, priced here so
// it is not discovered in game. The optical depth of a sight line is this
// times the plume it crosses - plume * NETHER_PLUME_ABSORPTION * this *
// blocks * NETHER_PLUME_EXTINCTION - so at the column core of 0.5 the
// twenty-block transmittance goes from 16.5% to 2.7% and the whole 96-block
// march from 0.018% to nothing measurable; at the field's own mean plume of
// 0.353 the same twenty blocks go from 28% to 7.9% and the same march from 0.2%
// to nothing measurable either. ⚠️ The four figures this sentence used to carry
// beside those were four different pairs read as one: the 1.9% was the whole
// march at the mean the contrast raise had just taken the field to - about
// 0.22 - so it is a figure of the density before this one; the 54% was the
// twenty-block row at 0.353 with the extinction still at 0.03, which is the
// pair before batch 528; the 1.3% was the core's own 96-block row with the
// extinction still at 0.03; and the 88% paired with the 54% is not this pair's
// transmittance at any distance this note uses - twenty blocks is 28%, fifty is
// 4.2% and the whole march is 0.2%. The worst of those is a wall a player sees
// at distance rather than the veil the layer is meant to be, and the recovery
// is NETHER_PLUME_EXTINCTION at 0.03, which is half of the number this is
// paired with and restores every one of those percentages exactly - the
// emission NETHER_PLUME_OPTICAL was raised for is untouched by it.
#define NETHER_PLUME_DENSITY 3.0 // [0.0 0.5 1.0 1.5 2.0 3.0 4.0 6.0]

// How much the plumes fade what is behind them, per block of column that the
// ray crosses.
//
// ⚠️ 0.0 is the null case: the columns still glow, and they take nothing out of
// what is behind them at all, which is exactly how this pass behaved before
// batch 521.
//
// ⚠️ Raised from 0.03 to 0.06 in batch 528, and it is the half of that batch
// which is about the background: a column that leaves what is behind it alone
// has no edge to read against the lava, and the report was that the plumes read
// as a wash of haze with no outline to them. The arithmetic is a transmittance
// through twenty blocks at the shipped density, an optical depth of plume *
// NETHER_PLUME_ABSORPTION * NETHER_PLUME_DENSITY * 20 * this: through a core of
// plume about 0.5 that is 0.90 at 0.03, so 41% of the light behind it arrives,
// and 1.80 at 0.06, which is 17%. Through the field at its own mean plume of
// 0.168 the same twenty blocks go from 74% to 55%, and over the whole 96-block
// march distance from 23% to 5.5%.
//
// ⚠️ 0.06 is the bottom of the range batch 528 was given, and the top of it is
// the reason: at 0.10 those three figures are 5.0%, 36% and 0.8%, and a vista
// that transmits eight parts in a thousand is a wall rather than a place.
// ⚠️ NETHER_PLUME_CONTRAST rose in the same batch, which raises the field's mean
// density by about a third, and the two compound at distance: the 96-block
// figure the shipped pair lands on is 1.9% rather than 5.5%. That is the number
// to watch in game, and this is the dial for it - the step below is 0.03, which
// is what this shipped at. NETHER_PLUME_SHADING below is the other dial, since
// it is the other thing that thins the glow at distance.
// ⚠️ Neither of the two paragraphs above is the shipped arithmetic any more,
// because batch 529 doubled NETHER_PLUME_DENSITY and every figure in them is a
// product of that. What the pair actually stands at now: a sight line that
// carries the field's own mean plume of 0.353 keeps 7.9% of what is behind it
// over twenty blocks and five parts in a million over the whole 96-block march,
// and one that carries a column's core of 0.5 keeps 2.7% and nothing measurable
// at all. ⚠️ Neither of the two figures that stood in this sentence was that
// pair's own: the 54% was the twenty-block row with the extinction still at
// 0.03, which is the pair before batch 528, and the 0.2% was the whole march at
// the mean of 0.353 with the density still at 1.5, which is the pair before
// this one. The twenty-block figure is recoverable without touching the light:
// at 0.03 - the step below - every one of them returns to what it was at the
// shipped 1.5, because a density doubled and an extinction halved are the same
// optical depth.
#define NETHER_PLUME_EXTINCTION 0.06 // [0.0 0.01 0.02 0.03 0.06 0.08 0.12]

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

// How much smoke gathers under the ceiling.
#define NETHER_CEILING_SMOKE 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]

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
// report this batch answers: fog visible, no pillars. Lifting the noise before
// the square moves the subtraction's bite down the distribution, so the erosion
// still carves and there is more field for it to carve: at the shipped 1.4,
// 64.6% of the layer carries pillar density instead of 26.1%, the mean plume goes
// from 0.034 to 0.168, the columns' own light comes out at 1.4 times the haze
// instead of 0.35 times it, and the emission's 90th percentile goes up sixfold.
//
// ⚠️ Held at one after the lift, and that is what keeps this a shaping term
// rather than a second brightness option. Both NETHER_PLUME_OPTICAL and
// NETHER_PLUME_EXTINCTION are tuned against a density that tops out at 1.0 - the
// emission curve and the optical depth per block both read that number directly
// - and an unclamped lift puts the cores at 1.96 and drags both of them up with
// it. It is also what the plateau on a column's core is: a dense column seen
// from outside is a solid core with soft edges, not a spike.
//
// ⚠️ Batch 529 doubled NETHER_PLUME_DENSITY and did not touch this, so the
// measured figures above are still the shape's own - and so is the mean plume
// below, which no value of the density can move: it is batch 528's own
// measurement of the shape, 0.353 at the 1.7 that shipped with it against the
// 0.260 the same measurement gives at 1.4. NetherPlumeDensity never reads the
// density option, so what it doubles is the light the field carries - the
// emission and the optical depth in the pass - and not the field: a mean three
// times 0.353 is not a state the clamp can produce, since the field stops at
// one. What the clamp guarantees is unchanged, which is the reason the density
// could be raised without the contrast having to follow it.
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
// a third of the base value over this height.
//
// ⚠️ Without it the columns are as thick between the lava and the roof fade as
// they are at the lava, because the only height term above that was the roof
// fade at seventy. A plume that does not thin as it rises reads as a bar rather
// than as smoke.
//
// ⚠️ A slider as of batch 525. Low is a short plume - over ten blocks the smoke
// is down to a third of what it is at the lava, so the columns are stubs standing
// on the bed - and high is a tall one: at 50 they keep most of their density all
// the way to the roof fade, which is the full-height bar this term was added to
// take away, so the top of the range is where batch 523 stops being visible.
#define NETHER_PLUME_HEIGHT_SCALE 25.0 // [10.0 15.0 20.0 25.0 35.0 50.0]

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
// far down it, so the bed at its 0.10 ceiling glows 0.000109 where a typical
// pillar at 0.51 glows 0.00196 - eighteen times as much - and read at the foot
// of the layer, where the height falloff is one and the bed is at its thickest,
// the bed is the thicker of the two over 31.8% of it against 38.1% at 0.25. (The
// 43% above is a figure through the layer; this one is at its foot.) Those 31.8%
// are the gaps between the columns low down, which is the whole job this was
// added for; everywhere else the columns are what is seen, and the bed is felt
// as the smoke they rise out of rather than as a sheet they stand in.
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
// ⚠️ Both are sliders as of batch 525. Churn is how fast the noise drifts past:
// 0.0 is the flat pre-520 rate, which does move and moves too slowly to see; 1.0
// is the rate this shipped at, about half a slice a second; 3.0 is about two and a
// half times that, where the drift is plainly visible. Rise is the per-column
// offset: at 0.0 every column churns in step, which is the reference pack's rigid
// scroll, and 12.0 is the value that separates them; the top of the range pushes
// them further apart still.
#define NETHER_PLUME_CHURN 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]
#define NETHER_PLUME_RISE 12.0 // [0.0 4.0 8.0 12.0 20.0 32.0]

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
// walks into a column now has three blocks of it between the eye and the near
// face, and at the shipped pair that is a screen turning orange. The range is
// wide on purpose - 16 and 24 are the old behaviour, and 4 is close to no
// bubble at all.
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
// ⚠️ A slider as of the same batch. 0.004 is smoke that barely lights anything,
// 0.016 is the value that shipped from batch 525 to batch 528, and 0.032 was
// recorded here as the point past which the Nether stops being a place and
// becomes a lamp.
//
// ⚠️ Batch 529 doubled it to 0.032, and the reason is that 0.032 was never the
// lamp that note claims: it was about a seventh of one, and the note was written
// against a curve nobody had put numbers on. The numbers, at the shipped march
// of 24 quadratic steps over VOLUMETRIC_FOG_DISTANCE's 96 blocks, against a
// reference frame brightness of 1.0 - white as the tonemap sees it. The
// emission is `(1.0 - exp(-2.0 * p)) * 0.25 * p * OPTICAL * DENSITY` per block
// of plume crossed, so at a column's own half density of p = 0.5 and the pair
// that shipped - OPTICAL 0.016, DENSITY 1.5 - that expression comes out at
// 0.0019 per block, which is the figure batch 528 recorded as 0.00196 at the
// same pair and a plume of 0.51. ⚠️ 0.00047 is not that number and must not be
// read as it: it is the quarter of it that arrives at the eye once the
// absorbance weighting is on the glow - pow(absorbance, NETHER_PLUME_SHADING)
// at the emission in the pass, and batch 524's second absorbance on the scatter
// - so it is light DELIVERED per block rather than light emitted per block.
// Everything below inherits that basis: the 13 blocks a sight line crosses a
// column through (five of the 24 steps, in the quadratic ladder's middle) carry
// 0.0061, 0.6% of the frame. A column that is half a percent of the frame is a
// column nobody can see, which is the report this batch opened with.
//
// ⚠️ The 0.25 inside that expression is where the fault was, and it is left
// exactly where it is. It came from batch 520, where it was the constant that
// kept the inverted curve's brightest point at what exp(-density) had given it
// - see the note in the pass - and it has been carried ever since as a
// normalisation rather than as a brightness. What it normalises is a quantity
// nothing here reads. It is kept because it is the null case for the sliders
// that were tuned around it: a reader moving this option is moving the same
// thing at 0.032 as they were at 0.016, and the value below is the whole of
// what changed.
//
// ⚠️ What the new pair buys, on the same arithmetic: 0.00095 per block against
// 0.00047, and the same 13-block crossing at 0.0123 of the reference against
// 0.0061 - 1.2% of the frame at a column's half density, 2.8% at the field's
// own mean of 0.353, and 6.7% through a saturated core where the old pair gave
// 0.3%, 0.7% and 1.7%.
//
// ⚠️ Every one of those is light ARRIVING, on the basis the 0.00047 above is
// on, and not one of them is the emission itself: the expression above yields
// 0.0019 per block at the old pair and 0.0038 at the shipped one, which over
// the same thirteen blocks is 2.5% of the frame before and 9.9% after. ⚠️ And
// the 0.6% above is exactly twice this 0.3% at the same plume and
// the same pair, so the two are one question with two answers: the 0.6% is a
// quarter of that 2.5%, and the three here are an eighth of it at the half
// density, a half at the field's mean and a quarter at a core. Neither sentence
// said which was which, and a reader who wants one basis for the lot should take
// the quarter - the arriving fraction the note above works out - throughout.
//
// ⚠️ And the comparison that decides whether any of that is seen is not against
// white but against the haze the columns stand in, because the haze fills the
// whole sight line while a column crosses it in thirteen blocks. The haze emits
// 0.00025 per block at its own density - it has no density multiplier of its
// own, so its light per block is flat, and it carries no absorbance weighting
// either, so that one figure IS emitted light - and a column at its half density
// goes from 0.00047 to 0.00095 per block of plume crossed, both of those the
// arriving figure rather than the emitted 0.0019 and 0.0038: from about twice
// the haze's own radiance to about four times it, with 7.6 times at a core. Over
// a whole crossing against the whole haze the light is what the report is about,
// and it is the columns that now have the larger share of it.
//
// ⚠️ And the same crossing at the top of the list, 0.32, is 0.123 of the
// reference - ten times this default, and a tenth of a white frame for one
// crossing of one column, which is loud without being the lamp the old note
// feared.
#define NETHER_PLUME_OPTICAL 0.032 // [0.004 0.008 0.016 0.032 0.064 0.128 0.32]

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
		// it into motion in the units the erosion is sampled in. At the shipped
		// NETHER_PLUME_CHURN that is about 0.55 slices a second, where one slice is
		// about twenty blocks - so the field works through a slice in about half a
		// minute. Before batch 520 the coefficient here was a flat 0.05, which is
		// 0.36 blocks a second: the field did move, and it moved too slowly to see.
		float churnPhase = windTheta.w * (0.05 + NETHER_PLUME_CHURN * 0.2);

		// ⚠️ And the third term is what makes a column ROLL rather than slide. The denser
		// a column is, the further up it the erosion is sampled, so every column churns at
		// its own rate instead of the whole world sharing one sheet of noise going past.
		// That, and not the speed, is what separates this from the reference pack's
		// rigidly scrolled field - and it is what makes the motion read as boiling rather
		// than as a texture being panned.
		vec3 erosionAt = vec3(
			squashed.x * 0.22,
			squashed.z * 0.22,
			squashed.y * 2.4
				+ churnPhase
				+ NETHER_PLUME_RISE * columns * 0.35);

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

		return layer * NETHER_CEILING_SMOKE;
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
