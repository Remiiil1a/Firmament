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

// Blocky volumetric clouds: a layer of cube-shaped cloud cells that is marched
// along the view ray, lit by the sun and by the sky, and drawn instead of
// Minecraft's own cloud geometry.
//
// Where this runs, and why there
// ------------------------------
// The march happens in the deferred pass (program/post/copy_and_fog.fsh), not
// where the sky is drawn. That is the first point at which the depth buffer is
// complete, which is what makes the layer possible at all: a sky pixel is a
// pixel with nothing in front of it, and "nothing in front of it" is exactly the
// condition the cloud layer needs, and it is also what lets the terrain occlude
// the layer rather than the other way round.
//
// How the shapes are built
// ------------------------
// The density field is quantised to a grid of CLOUD_CELL_SIZE block cells before
// anything is sampled, so every point inside a cell has the same density and the
// field is made of cubes rather than of a smooth blob. Cloud cells are therefore
// real boxes: they have a top and a bottom, they cast shadows on each other, and
// their edges are hard.
//
// The march walks that grid rather than the ray's length. Each step moves to the
// boundary of the next cell, which is the standard grid traversal ("DDA"), and
// it stops at the first cell that has cloud in it. Empty sky is therefore cheap
// - a single fetch per cell crossed - and the whole layer costs a bounded number
// of fetches no matter how far away it is.
//
// Once a cell is hit, the rest of the layer is treated as a slab of that
// density. That is the approximation that makes this cheap: instead of sampling
// every cell along the rest of the ray, the optical depth is computed in closed
// form from the density and the length of the ray through the layer, which is
// what makes the layer thicken towards the horizon the way a real one does.
//
// Cost
// ----
// Per sky pixel: one noise fetch per cell crossed, up to VOLUMETRIC_CLOUD_STEPS
// of them, and none at all for rays that do not enter the layer. Per cloud the
// march lands in: CLOUD_SUN_STEPS fetches more, for the light the layer lets
// through to it. Both counts are options or constants deliberately kept small.
//
// The layer costs nothing on terrain: an earlier version had it cast a shadow
// from the clouds onto the ground, and that was taken back out - see
// BlockyCloudTransmittance.

#ifndef VOLUMETRIC_CLOUDS_INCLUDED
#define VOLUMETRIC_CLOUDS_INCLUDED

// Whether to draw this pack's cloud layer instead of Minecraft's.
//
// The vanilla cloud geometry is switched off in shaders.properties while this is
// on, so that the two do not end up drawn on top of each other.
#define VOLUMETRIC_CLOUDS
#ifdef VOLUMETRIC_CLOUDS
	// The actual removal of the vanilla clouds is in shaders.properties, as
	// `clouds=off`: that is a game setting rather than a shader one, and the
	// shader mod is the only thing that can change it.
#endif

// The options this layer is tuned with. Every one of them is in the
// "Atmosphere & clouds" page of the settings menu.

// How big one cloud is, in blocks: the size of a cell, and the size the noise
// pattern is stretched to, so it moves both how chunky the cubes are and how
// large the masses they form are.
#define VOLUMETRIC_CLOUD_CELL_SIZE 24 // [8 12 16 20 24 32 48]

// The layer is CLOUD thickness blocks tall, and its bottom sits at the same
// height Minecraft's own clouds do in 1.18 and up, so that turning the vanilla
// clouds back on puts them in the same place.
#define VOLUMETRIC_CLOUD_THICKNESS 12 // [4 6 8 12 16 20 24]
#define VOLUMETRIC_CLOUD_HEIGHT 192 // [128 160 192 224 256]

// How many cells the view-ray march may cross before giving up. This is the
// main cost control: it is paid by every sky pixel, whether or not it finds a
// cloud, so lowering it is what to reach for first if the layer is expensive.
#define VOLUMETRIC_CLOUD_STEPS 12 // [4 8 12 16 24 32]

// How cloudy the sky is, from a nearly empty sky at the bottom to an overcast
// one at the top. 0.5 is where the layer was tuned.
//
// The weather thickens the layer on its own whatever this is set to, but it
// does so slowly - see the note on wetness below - so a change of weather takes
// a while to show up in the clouds, which is what makes it read as weather
// rather than as a switch being flipped.
#define VOLUMETRIC_CLOUD_COVERAGE 0.5 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

// How fast the layer drifts, as a multiplier on the same wind the planar clouds
// move with, so that the two agree if both are on.
#define VOLUMETRIC_CLOUD_SPEED 0.5 // [0.0 0.25 0.5 1.0 1.5 2.0]

// Whether this program can run the march at all.
//
// The Voxy terrain programs are handed a fixed set of uniforms by the mod that
// calls them and no depth of this pack's, so the layer is not available there -
// see the same test in /environment/dimension.glsl.
#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	#define CLOUD_MARCH_AVAILABLE
#endif

#ifdef CLOUD_MARCH_AVAILABLE

// 2D value noise, sampled from the shader mod's own noise texture. This is the
// same noise the planar clouds use, and for the same reason: a texture fetch is
// cheaper here than computing noise in the shader would be.
#include "/lib/valueNoise.glsl"

// EndDimension(), and the dimension and biome_category uniforms behind it.
//
// Included rather than assumed, because this file is reached from both the
// deferred pass and the surface programs and only one of them pulls the sky in,
// which is what otherwise brings this along. The include guard in that file
// makes a second inclusion a no-op.
#include "/environment/dimension.glsl"

// One cell of the grid, in blocks. This is the size of the cloud cubes, and the
// single number that decides how blocky the layer looks.
const float CLOUD_CELL_SIZE = float(VOLUMETRIC_CLOUD_CELL_SIZE);

// How many cells it takes to cross the noise texture's full width, which is also
// how far the cloud pattern travels before it repeats: 96 cells at 24 blocks
// each is a little over two thousand blocks. The texture is 64 texels across, so
// one cell advances it by a texel and a half - close enough for neighbouring
// cells to differ, far enough for the clouds to keep their shape across them.
const float CLOUD_CELLS_PER_TILE = 96.0;

// Where the edge between sky and cloud sits in clear weather and in rain, as
// values of the noise. A cell is cloud when its noise is above the edge, so a
// higher number means less of the sky covered.
//
// Both are high enough that a clear sky has real holes in it rather than a thin
// wash of cloud over everything, and far enough apart that weather is clearly
// visible as more cloud rather than as a slight thickening.
const float CLOUD_EDGE_CLEAR = 0.62;
const float CLOUD_EDGE_RAIN = 0.30;

// How wide the transition from empty sky to solid cloud is, in the same units.
// This is what gives a cloud an edge rather than a cliff.
const float CLOUD_EDGE_SOFTNESS = 0.22;

// How far the coverage option can move the edge, at either extreme.
const float CLOUD_COVERAGE_RANGE = 0.55;

// The bottom and top of the layer, in world Y.
//
// Fixed to the world, not to the camera. A layer that rides along with the
// camera keeps the same apparent distance, which is what makes it impossible to
// climb above - that is how Mellow Shader's clouds work (100 blocks above the
// camera at all times, get_clouds_blocky_volumetric) - but it also means the
// whole layer slides up and down the sky as the player changes altitude, which
// reads as the clouds moving with them. The layer stays where it is instead, and
// being able to see it from above is solved where the layer is drawn.
const float CLOUD_LAYER_BOTTOM = float(VOLUMETRIC_CLOUD_HEIGHT);
const float CLOUD_LAYER_TOP = CLOUD_LAYER_BOTTOM + float(VOLUMETRIC_CLOUD_THICKNESS);

// How much light a block of full-density cloud takes away. The layer being
// twelve blocks thick, a value around this makes a solid cell read as a solid
// cloud without turning the whole layer into a wall.
const float CLOUD_EXTINCTION = 0.55;

// How many places along the sun's ray the layer is read at, and so the number of
// times the loop below runs whether or not the segment needs that many. The step
// is a cell at most, so this is what bounds the cost of the light a cloud
// receives: four samples at 24 blocks each covers the length a sun ray crosses
// inside a twelve block layer at any sun angle worth looking at.
#define CLOUD_SUN_STEPS 4

// How fast the layer drifts, in blocks per second.
//
// Chosen to match the planar clouds, which move their sampling position by 0.04
// cloud heights per second - see cirrusCloudPlane - and a cloud height is about
// 192 blocks. The two layers therefore move together rather than against each
// other.
const float CLOUD_DRIFT_SPEED = 7.68;

// Where the layer starts fading out towards the horizon, and where it is gone.
// Without this, a ray that only just clears the horizon would look through
// thousands of blocks of cloud and the layer would end at a hard line.
const float CLOUD_FADE_START = 3000.0;
const float CLOUD_FADE_END = 7000.0;

// Light that bounces inside a cloud instead of passing straight through it.
//
// One pass of the light through the layer is what the transmittance of a cloud
// is: the fraction of the sun that reaches it without touching anything. The
// light that does touch something does not vanish, though - it scatters, and
// some of it comes out the far side, and out of the sides. Each further bounce
// has to cross less of the cloud than the last and carries less of the light
// than the last, so adding a few of them back is what keeps a thick cloud lit
// rather than letting it go black, while changing a thin one hardly at all.
//
// The octaves below are powers of the transmittance, which is the same thing as
// reducing the extinction: the light that crossed half as much cloud as the
// first pass is the square root of it. No exponentials, two multiplies each.
//
// It is deliberately not a phase function. What varies here is how much cloud
// the light is crossing, not which way it is going - and the direction is
// exactly what had to come out of this layer's lighting, see the note on
// CLOUD_PHASE_FLAT. Nothing here may put it back.
// The three settings come first, and they have to: a macro is expanded where it
// is written, so the function below cannot be written above the bounds it counts
// to. (Same rule as the includes elsewhere in the pack - the preprocessor reads
// the file in order and nothing more.)
//
// How much of the bounces are used, against the flat transmittance the layer
// applies on its own. At zero this is the layer as it was.
#define CLOUD_MULTIPLE_SCATTER 0.5 // [0.0 0.25 0.5 0.75 1.0]

// How many bounces to add up.
#define CLOUD_MULTIPLE_SCATTER_OCTAVES 2 // [1 2 3]

// What each bounce keeps of the one before it: how much of the light there is
// left, and how much of the cloud it has to cross. Halving both is what makes
// each octave the square root of the last.
#define CLOUD_MULTIPLE_SCATTER_FALLOFF 0.5 // [0.25 0.4 0.5 0.6 0.75]

float CloudMultipleScatter(float transmittance) {
	float total = 0.0;
	float weight = 1.0;
	float exponent = 1.0;
	float weightSum = 0.0;

	for (int i = 0; i < CLOUD_MULTIPLE_SCATTER_OCTAVES; i++) {
		total += weight * pow(transmittance, exponent);
		weightSum += weight;

		weight *= CLOUD_MULTIPLE_SCATTER_FALLOFF;
		exponent *= 0.5;
	}

	// Normalised, so that a cloud the light crosses freely still comes out at
	// the same brightness it always did: only what is being held back by the
	// cloud changes.
	return total / weightSum;
}

// What the layer's direct light is multiplied by, in place of the phase
// function above.
//
// The phase function makes a cloud brighter or darker according to the angle
// between the direction it is being looked at from and the direction the light
// comes from - the bright rim around a cloud's lit side. The trouble is that
// that angle is what changes when the light hands over from the sun to the
// moon: the two sit in different parts of the sky, so the angle does not drift
// across the changeover, it reverses, and the phase function differed by a
// factor of forty between the two. A flat value has no angle in it, so there is
// nothing left there to jump.
//
// This is a deliberate trade rather than a fix: the layer loses the way its lit
// side used to stand out. It is one number, so it is also the dial for how
// bright the direct light on the clouds is at all.
#define CLOUD_PHASE_FLAT 0.25 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00]

// How much light reaches the bottom of the layer, as a fraction of what reaches
// the top. What is above a cell shades it, so the underside of a cloud deck is
// darker than its top - the same thing Mellow's blocky clouds do, to both the
// ambient and the direct light, from 0.3 at the bottom of the layer to 1.0 at
// the top.
//
// 1.0 turns the falloff off and leaves the layer evenly lit.
#define CLOUD_LAYER_FALLOFF_BASE 0.30 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]

// What the layer's direct light is multiplied by, in place of how much of it
// survives the cloud between the cell being shaded and the light.
//
// That fraction was the second thing that changed when the light handed over
// from the sun to the moon, for the same reason as the phase: it is measured
// along the line to the light, and that line points somewhere else afterwards.
// Taken out the same way, so that nothing in the layer's direct light depends
// on where the light is any more.
//
// What it costs is the difference between a thick cloud and a thin one: every
// cell is now lit by the same amount of light regardless of what stands between
// it and the sun. That is a flatter layer than before, deliberately.
#define CLOUD_TRANSMITTANCE_FLAT 1.00 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00]

// Clouds are animated over time.
//
// Declared behind a guard because more than one file in a program wants this and
// a repeated uniform declaration is an error. See the note in
// /environment/clouds/cirrus.glsl.
#if !defined(FRAME_TIME_COUNTER_DECLARED)
	#define FRAME_TIME_COUNTER_DECLARED
	uniform float frameTimeCounter;
#endif

// The pack's own cloud lighting, which already follows the sun, the moon, the
// time of day and the weather - see the "Cloud direct/ambient lighting" section
// of shaders.properties. Computing any of that here would be a second opinion
// that could disagree with the vanilla clouds the profiles can still use.
uniform vec3 cloudLightAmbient;
uniform vec3 cloudLightDirect;

// A diagnostic, on the same principle as the parallax one: paints the layer
// with the separate quantities its lighting is built from, so that a jump at a
// particular time of day can be attributed to one of them rather than guessed
// at. 0 is off and costs nothing - the branch below is compile-time.
//
//   1 - the direct light the layer is given, after everything that shapes it
//   2 - the fraction of that light which gets through the layer itself
//   3 - the phase function, ie, how much of it this viewing angle sees
#define CLOUD_DEBUG 0 // [0 1 2 3]

// The rest of the pack's cloud state. Declared only if the planar clouds are off,
// as they declare the same uniforms when they are on - nothing includes both,
// but a repeated declaration is an error, so the guard stays.
#ifndef CLOUDS_ENABLED
	uniform float cloudFade;
#endif

// The wetness of the terrain, which the shader mod tracks from the weather with
// a half-life of its own. This is the same value the material wetness feature
// uses, and it is what makes a change of weather take a while to reach the
// clouds rather than changing them the moment the rain starts or stops.
//
// Declared behind a guard because /environment/lighting/pbr.glsl declares it as
// well when the material wetness feature is on, and a repeated declaration is an
// error. That file defines the macro below for exactly this reason.
#if !defined(WETNESS_DECLARED)
	#define WETNESS_DECLARED
	uniform float wetness;
#endif

// The time the layer is animated with.
float CloudTime() {
	#ifdef FREEZE_ANIMATION_TIMER
		// Non-zero, as otherwise the drift term is cancelled out and the layer
		// would not move at all when the animation is frozen.
		return 500.0;
	#else
		return frameTimeCounter;
	#endif
}

// How far the layer has drifted from where it started, in blocks along X.
vec2 CloudDrift() {
	return vec2(CloudTime() * CLOUD_DRIFT_SPEED * VOLUMETRIC_CLOUD_SPEED, 0.0);
}

// Whether clouds belong in the dimension the player is in.
//
// The End has its own sky and its own look, which a layer of clouds would ruin,
// and the Nether has no sky at all to put them in.
//
// The Nether is asked about through its biome category as well as through the
// dimension itself, for the reason /environment/dimension.glsl gives about the
// End: a shader mod that provides no dimension uniform leaves it at zero, which
// reads as the overworld - and that is exactly how a cloud deck ends up hanging
// over the Nether, drawn on the pixels past the end of the terrain, where the
// depth buffer says there is nothing in front of the camera.
bool CloudDimension() {
	return dimension == 0
		&& biome_category != NETHER_BIOME_CATEGORY
		&& !EndDimension();
}

// How much cloud there is in one cell of the grid, where the cell is given by
// its index rather than by a position - the quantisation has already happened by
// the time this is called.
//
// One fetch per cell, and two of the noise texture's channels per fetch: the
// first gives the cloud masses, the second breaks up their edges. Sampling the
// texture is what keeps it to one fetch, since the hardware does the
// interpolation value noise needs.
float CloudCellDensity(vec2 cell) {
	// One sample per cell, taken at the same point inside every cell, which is
	// what makes the density constant across a cell rather than varying through
	// it.
	vec2 texcoord = (cell + 0.5) / CLOUD_CELLS_PER_TILE;

	float value = noise(vec3(0.75, 0.25, 0.0), texcoord);

	// Where the edge between sky and cloud sits right now.
	//
	// wetness rather than rain strength on purpose: it lags behind the weather,
	// so the layer fills in and clears out over the course of a minute instead
	// of changing the moment it starts or stops raining.
	float edge = mix(CLOUD_EDGE_CLEAR, CLOUD_EDGE_RAIN, wetness);

	// The coverage option moves the edge, and the softness spreads the
	// transition out, so that one cell can be partly cloud and the layer has
	// edges rather than holes cut out of a wall.
	edge += (0.5 - VOLUMETRIC_CLOUD_COVERAGE) * CLOUD_COVERAGE_RANGE;

	return smoothstep(edge, edge + CLOUD_EDGE_SOFTNESS, value);
}

// How much sunlight reaches `worldPos` without passing through the layer, where
// 1.0 is unobstructed and 0.0 is right behind a cloud.
//
// The layer uses this on itself: a cell is lit by how much light reaches it from
// the sun's side, which is what makes its top brighter than its underside and
// what stops a thick cloud from being lit the same as a thin one. It is not used
// to cast a shadow on the terrain - that was tried and taken back out, because
// the shadow could only ever fall on terrain this pack draws, and not on the
// level-of-detail terrain another mod draws.
float BlockyCloudTransmittance(vec3 worldPos, vec3 lightView) {
	if (!CloudDimension()) {
		return 1.0;
	}

	// The light direction, read out of view space against the world's axes.
	//
	// The obvious alternative - the pack's own worldLightVector - is this same
	// direction put through the inverse of the camera's matrix, and that inverse
	// is not quite the inverse of it while the view is bobbing. The error is
	// small, but the light the layer lets through is read a distance away that is
	// the layer's height divided by the sine of the sun's elevation, so a
	// direction that is a degree or two out slides the whole reading by a block or
	// two, back and forth at the walking bob: enough, when this fed the shadow the
	// layer cast on the ground, to make it shiver with every step. That is the
	// same failure the End's star had before its angle was taken from a normalised
	// direction - see the note in /environment/sky/end.glsl.
	//
	// gbufferModelView is the matrix the geometry here was drawn with, so the
	// world's axes taken from it are the axes this fragment was placed in.
	// Dotting the view-space direction against them is that matrix's transpose,
	// which for a rotation is its inverse - and unlike the inverse the shader mod
	// hands out, it is exact for this pair by construction.
	mat3 view = mat3(gbufferModelView);
	vec3 lightDir = normalize(lightView);
	vec3 lightWorld = vec3(
		dot(lightDir, view * vec3(1.0, 0.0, 0.0)),
		dot(lightDir, view * vec3(0.0, 1.0, 0.0)),
		dot(lightDir, view * vec3(0.0, 0.0, 1.0)));

	// A light below the layer cannot be blocked by it from above, and a ray from a
	// point to a light that does not cross the layer is not blocked at all.
	//
	// Written as a fade across the horizon rather than a branch on it, because
	// this is one of the two places the layer's lighting used to step. The branch
	// returned before any of the geometry below ran, so a light crossing the
	// horizon switched this whole function between "the layer blocks it" and "the
	// layer does not" inside one frame. What makes that visible rather than
	// academic is that the light here is whichever of the sun and the moon is
	// higher (see shadowLightPosition at the call site), so crossing the horizon
	// is also when that switches bodies - direction and all.
	//
	// The crossing itself is still computed, with the elevation held just above
	// zero so that the divisions below stay finite; it is faded out of the result
	// instead of being skipped, so nothing steps as the light passes through.
	float lightAbove = smoothstep(-0.02, 0.02, lightWorld.y);

	if (lightAbove <= 0.0) {
		return 1.0;
	}

	vec3 lightCrossing = vec3(
		lightWorld.x, max(lightWorld.y, 0.02), lightWorld.z);

	float tBottom = (CLOUD_LAYER_BOTTOM - worldPos.y) / lightCrossing.y;
	float tTop = (CLOUD_LAYER_TOP - worldPos.y) / lightCrossing.y;
	float tEnter = min(tBottom, tTop);
	float tExit = max(tBottom, tTop);

	if (tExit <= 0.0 || tEnter > CLOUD_FADE_END) {
		return 1.0;
	}

	tEnter = max(tEnter, 0.0);

	// Sampled a whole cell apart where the segment is long enough to need it, so
	// that the light cannot be walked past a cell between two samples, and
	// divided evenly where it is not. The loop runs a fixed number of times
	// either way, which is what keeps the cost of this predictable.
	//
	// Named sampleStep rather than step, because step is a GLSL built-in and a
	// variable of that name hides it for the whole function.
	float segment = tExit - tEnter;
	float sampleStep = min(CLOUD_CELL_SIZE, segment / float(CLOUD_SUN_STEPS));
	vec2 drift = CloudDrift();

	// The optical depth of everything the sun's light crosses on its way in.
	// Adding the cells up rather than keeping the densest one is what makes a
	// thick cloud darker than a thin one instead of both of them being equally
	// dark.
	//
	// The density is read a cell at a time, from the same quantised field the sky
	// layer is built of - so a cell's lit side and its shaded side meet at a hard
	// edge, which is the look the layer is made of. An earlier build averaged four
	// samples spread across the sun's ray instead, which softened that edge out to
	// about a cell's width. That was done to steady a shadow the layer cast on the
	// ground, and the ground shadow is gone (see PBR_PORTING.md §12.10), so the
	// softening only cost the look; this is the version before it.
	float tau = 0.0;

	for (int i = 0; i < CLOUD_SUN_STEPS; i++) {
		vec3 samplePos = worldPos
			+ lightCrossing * (tEnter + (float(i) + 0.5) * sampleStep);
		vec2 cell = floor((samplePos.xz - drift) / CLOUD_CELL_SIZE);

		tau += CloudCellDensity(cell) * sampleStep;
	}

	// Faded in over the horizon rather than switched on at it - see above.
	return mix(1.0, exp(-tau * CLOUD_EXTINCTION), lightAbove);
}

// The cloud layer as seen along a ray, ready to be composited over the sky: .rgb
// is the colour the layer is lit to in that direction and .a is how much of the
// sky it covers.
//
// `worldDir` is the direction of the ray and `cameraWorldPos` its origin, both
// in world space, and `lightView` is the direction the sun or moon is in, in
// view space, which is how the shader mod provides it and why it is read into
// the world here rather than passed that way. Zero is returned for a ray that
// cannot see the layer at all, which is most of them.
vec4 BlockyClouds(vec3 worldDir, vec3 cameraWorldPos, vec3 lightView) {

	if (!CloudDimension()) {
		return vec4(0.0);
	}

	// Turned into world axes for the reason given in BlockyCloudTransmittance
	// above: the direction the shader mod hands out has been through the inverse
	// of the camera's matrix, and that inverse is not quite the inverse of it
	// while the view is bobbing.
	mat3 view = mat3(gbufferModelView);
	vec3 lightDir = normalize(lightView);
	vec3 lightWorld = vec3(
		dot(lightDir, view * vec3(1.0, 0.0, 0.0)),
		dot(lightDir, view * vec3(0.0, 1.0, 0.0)),
		dot(lightDir, view * vec3(0.0, 0.0, 1.0)));

	// The layer is entered from below by a ray going up and from above by one
	// going down, so both are marched - the entry and exit below already work
	// either way round, and the grid traversal does not care about the sign of
	// the direction.
	//
	// This used to reject every ray below the horizon, on the grounds that a ray
	// that is not going up cannot reach the layer from below. True, but it is
	// not the only way in: flown above the clouds, every ray points downwards,
	// so the whole layer was rejected up there and the sky below was empty. Only
	// a ray parallel to the layer never reaches it, and that is all this needs
	// to turn away.
	if (abs(worldDir.y) < 1.0e-6) {
		return vec4(0.0);
	}

	// Where the ray enters and leaves the layer. When the camera is inside the
	// layer the entry is the camera itself, which is what the clamp to zero
	// gives; when it is above the layer, looking down is what enters it and the
	// two distances are simply the other way round.
	float tBottom = (CLOUD_LAYER_BOTTOM - cameraWorldPos.y) / worldDir.y;
	float tTop = (CLOUD_LAYER_TOP - cameraWorldPos.y) / worldDir.y;
	float tEnter = max(min(tBottom, tTop), 0.0);
	float tExit = min(max(tBottom, tTop), CLOUD_FADE_END);

	if (tEnter >= tExit) {
		return vec4(0.0);
	}

	// The march, in cell coordinates: one unit is one cell in the XZ plane, and
	// the ray's own length is the parameter being stepped along.
	vec3 entry = cameraWorldPos + worldDir * tEnter;
	vec2 drift = CloudDrift();
	vec2 planeOrigin = (entry.xz - drift) / CLOUD_CELL_SIZE;
	vec2 planeDir = worldDir.xz / CLOUD_CELL_SIZE;

	// A ray that is exactly axis-aligned has a zero component, and one divided
	// by that would be an infinity to carry around. Keeping the component
	// non-zero but absurdly small gives the same answer - that axis is simply
	// never the next boundary - without the infinity.
	vec2 safePlaneDir = sign(planeDir) * max(abs(planeDir), 1.0e-5);

	vec2 cell = floor(planeOrigin);
	vec2 cellStep = sign(planeDir);
	vec2 tDelta = abs(1.0 / safePlaneDir);
	vec2 tNext = (cell + max(cellStep, 0.0) - planeOrigin) / safePlaneDir;

	// Named marchDistance rather than distance, because distance is a GLSL
	// built-in and a variable of that name hides it for the whole function.
	float marchDistance = 0.0;
	float density = 0.0;

	for (int i = 0; i < VOLUMETRIC_CLOUD_STEPS; i++) {
		density = CloudCellDensity(cell);

		if (density > 0.0) {
			break;
		}

		// Which boundary the ray reaches first, on either axis, and only that
		// one: stepping to both at once would cut the corner and skip the cells
		// in between.
		if (tNext.x < tNext.y) {
			cell.x += cellStep.x;
			marchDistance = tNext.x;
			tNext.x += tDelta.x;
		} else {
			cell.y += cellStep.y;
			marchDistance = tNext.y;
			tNext.y += tDelta.y;
		}

		if (marchDistance >= tExit - tEnter) {
			density = 0.0;
			break;
		}
	}

	if (density <= 0.0) {
		return vec4(0.0);
	}

	// How far the sight line travels inside the layer, which for a shallow angle
	// is a long way - the same reason a real cloud deck thickens towards the
	// horizon.
	float slabLength = float(VOLUMETRIC_CLOUD_THICKNESS)
		/ max(abs(worldDir.y), 1.0e-4);

	// Where on the sight line the layer was found, which decides how much of the
	// sky this part of it sees: the top of the layer is lit by it, the underside
	// is not.
	vec3 hitPos = entry + worldDir * marchDistance;
	float vertical = clamp(
		(hitPos.y - CLOUD_LAYER_BOTTOM) / float(VOLUMETRIC_CLOUD_THICKNESS),
		0.0,
		1.0);

	// How much of the sun survives the cloud between this cell and the sun,
	// which is what stops a thick cloud from being lit the same as a thin one.
	float sunTransmittance = BlockyCloudTransmittance(hitPos, lightView);

	#if defined(CLOUD_DEBUG) && CLOUD_DEBUG > 0
		// The three quantities the layer's lighting is made of, each on its own.
		// Whichever of them changes across a jump is the one to go and fix; the
		// other two are there so that a channel that does *not* change rules
		// itself out.
		if (CLOUD_DEBUG == 1) {
			return vec4(cloudLightDirect, 1.0);
		} else if (CLOUD_DEBUG == 2) {
			return vec4(vec3(CLOUD_TRANSMITTANCE_FLAT), 1.0);
		} else {
			return vec4(vec3(CLOUD_PHASE_FLAT), 1.0);
		}
	#endif

	// The sky's light, and the sun's, in the proportions the vanilla clouds use
	// - see cloudColor in shaders.properties, which is the ambient term plus
	// half the direct one.
	// Light falls off towards the bottom of the layer: what stands above a cell
	// shades it, so the underside of the deck is darker than its top.
	float layerLight = CLOUD_LAYER_FALLOFF_BASE
		+ (1.0 - CLOUD_LAYER_FALLOFF_BASE) * vertical;

	// The sun's share now knows how much cloud it had to cross. `sunTransmittance`
	// above is the one pass, and the octaves are the light that bounced inside
	// instead - so a cloud the light has to fight through stays lit by its own
	// scattering, and one the light crosses freely is unchanged.
	//
	// This is what CloudMultipleScatter is for, and it is the last thing the
	// layer's lighting was missing: the transmittance it uses below is a flat
	// value, which is what a thick cloud and a thin one used to be lit alike by.
	float scattered = CloudMultipleScatter(sunTransmittance);

	vec3 lit = layerLight * (
		cloudLightAmbient * mix(0.55, 1.0, vertical)
		+ cloudLightDirect * 0.5 * CLOUD_PHASE_FLAT
			* mix(CLOUD_TRANSMITTANCE_FLAT, scattered, CLOUD_MULTIPLE_SCATTER));

	float tau = density * slabLength * CLOUD_EXTINCTION;
	float fade = 1.0 - smoothstep(
		CLOUD_FADE_START,
		CLOUD_FADE_END,
		tEnter + marchDistance);

	// cloudFade is the pack's own cloud state: it is zero underwater, and it
	// follows the sunrise, so the layer is dimmer at the times of day the
	// vanilla clouds are.
	float alpha = (1.0 - exp(-tau)) * fade * cloudFade;

	return vec4(lit, alpha);
}

#endif /* CLOUD_MARCH_AVAILABLE */

#endif /* VOLUMETRIC_CLOUDS_INCLUDED */
