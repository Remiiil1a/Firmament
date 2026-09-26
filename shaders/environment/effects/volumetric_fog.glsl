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
// drawn in, and the options for it. See PBR_PORTING.md 169.

// Which of the game's three media the camera is standing in, for the density
// below.
//
// isEyeInWaterFog rather than isEyeInWater: that alias is the pack's own, built
// in shaders.properties, and it is the one every stage is given. isEyeInWater
// itself is the mod's, and the composite stage does not have it - which is what
// left the underwater medium reading as air and the fog painted the grey
// underwater light. PBR_PORTING.md 174 is where that was found.
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
// wrong - which is how the two would drift apart. See PBR_PORTING.md 197.
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
// what Sundial does, and PBR_PORTING.md 172 is where that was worked out.
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
// PBR_PORTING.md 171. It multiplies this medium's density, and it is also what
// environment/fog.glsl scales the pack's own atmospheric fog by: a thicker
// medium barely shows in rain, because rain is what hides the shafts the medium
// scatters, while the distance fading out is what a viewer sees. Sundial does
// the same at its atmosphere's optical depth - see PBR_PORTING.md 177.
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
// - see PBR_PORTING.md 169.1, where that cost a round trip. The pass reads the
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
#define NETHER_PLUME_DENSITY 1.5 // [0.0 0.5 1.0 1.5 2.0 3.0]

// How much smoke gathers under the ceiling.
#define NETHER_CEILING_SMOKE 1.0 // [0.0 0.5 1.0 1.5 2.0 3.0]

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

// How far around the eye the smoke is held off, in blocks.
//
// ⚠️ Not a detail. Without it the player stands inside a column and the screen
// is a wall of orange; the effect has to be something seen from outside. Bliss
// clears a bubble for exactly this reason.
#define NETHER_PLUME_CLEAR 24.0

// What the smoke glows with, and how its brightness falls off.
//
// ⚠️ Nothing lights this medium, because there is nothing here to light it: the
// Nether has no sun, so the shadow-map march below has no light to trace and the
// glow is the smoke's own.
//
// ⚠️ The brightness is the density times an exp() of the density, and that is
// the shape of the effect rather than a detail of it: it makes the smoke
// brightest where it is THINNEST, so that a column reads as something with light
// behind it rather than as a solid bar of light. Bliss darkens its emission the
// same way. Its 15.0 is this same curve over a much smaller range, because its
// density is not normalised to one and this one is.
const vec3 NETHER_PLUME_COLOR = vec3(1.00, 0.40, 0.16);
const float NETHER_PLUME_ABSORPTION = 2.0;

// How much smoke there is per block, where the field is at its thickest.
//
// ⚠️ Of the same order as VOLUMETRIC_FOG_DENSITY above, and for the same reason:
// both are optical depths per block, so a ray of the same length through either
// comes out at a comparable brightness. Much above this the Nether stops being a
// place and becomes a lamp.
const float NETHER_PLUME_OPTICAL = 0.008;

// And the same for the smoke under the ceiling. It is a flat layer rather than
// columns, so it is charged separately and has a colour of its own - a dark
// neutral, which is what Bliss gives it and what smoke under a roof looks like.
const vec3 NETHER_CEILING_SMOKE_COLOR = vec3(0.10, 0.075, 0.070);
const float NETHER_CEILING_SMOKE_OPTICAL = 0.004;

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
	// with INDIRECT_BOUNCE in b311 and it is written down in PBR_PORTING.md
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
	// shadowDistance set in PBR_PORTING.md 171.
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
		float columns = VolumetricFogNoise(vec3(
			(worldPosition.xz + lean) / VOLUMETRIC_FOG_SCALE, 0.0));

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
		vec3 erosionAt = vec3(
			squashed.x * 0.22,
			squashed.z * 0.22,
			squashed.y * 2.4 + windTheta.w * 0.05);

		float erosion = VolumetricFogNoise(erosionAt) * 0.7 + 0.3;

		// ⚠️ Subtracted rather than multiplied, and that is what makes it smoke
		// rather than a sponge. Multiplying would only dim the field everywhere
		// the erosion is low; subtracting takes pieces of it away outright, so
		// that the gaps between columns are gaps and the light comes through them.
		//
		// ⚠️ And the square on the columns before that subtraction is what keeps
		// the field mostly empty. Unity noise is mid-range almost everywhere, so
		// subtracting a constant from it would leave a sheet of thin smoke and a
		// few holes; squaring first pushes the low half towards zero and leaves
		// the subtraction something to bite on.
		float plume = max(columns * columns - (1.0 - erosion), 0.0);

		return plume * layer;
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
#endif // NETHER_PLUMES
