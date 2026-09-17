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

// The phase function's forward-scattering parameter: how much brighter a cell is
// when the sun is behind it than when it is beside it.
const float CLOUD_PHASE_G = 0.55;

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

// A Henyey-Greenstein phase function, normalised so that it is 1.0 when the
// viewer is looking straight into the sun and falls off to the side of it. That
// is what gives a cloud in front of the sun a bright rim and leaves the ones
// beside it flat.
float CloudPhase(float cosTheta) {
	float g = CLOUD_PHASE_G;

	// The normalisation constant of the standard function cancels out, leaving
	// this: the same shape, with 1.0 as the brightest it can be.
	return pow(
		(1.0 - g) / sqrt(1.0 + g * g - 2.0 * g * cosTheta),
		3.0);
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

	// A sun below the layer cannot be blocked by it from above, and a ray from a
	// point to a sun that does not cross the layer is not blocked at all.
	if (lightWorld.y <= 0.0) {
		return 1.0;
	}

	float tBottom = (CLOUD_LAYER_BOTTOM - worldPos.y) / lightWorld.y;
	float tTop = (CLOUD_LAYER_TOP - worldPos.y) / lightWorld.y;
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
			+ lightWorld * (tEnter + (float(i) + 0.5) * sampleStep);
		vec2 cell = floor((samplePos.xz - drift) / CLOUD_CELL_SIZE);

		tau += CloudCellDensity(cell) * sampleStep;
	}

	return exp(-tau * CLOUD_EXTINCTION);
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

	// The sky's light, and the sun's, in the proportions the vanilla clouds use
	// - see cloudColor in shaders.properties, which is the ambient term plus
	// half the direct one.
	vec3 lit = cloudLightAmbient * mix(0.55, 1.0, vertical)
		+ cloudLightDirect * 0.5 * CloudPhase(dot(worldDir, lightWorld))
			* sunTransmittance;

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
