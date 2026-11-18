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

// Implementation of a decently good looking procedural water surface using
// coherent (value) noise.
//
// These waves work by stretching and scrolling various layers of smooth value
// noise of varying frequency, and then adding them together into a heightmap.
// To add additional variation, some waves are designated as "crest waves" where
// we replace the uniform high and low areas with intermittent crests on an
// otherwise flat surface. We call the other waves "ripple waves".
//
// Adding a few layers of ripple and crest waves together gives a decent
// heightmap to work with.
//
// Then, we analytically compute the gradient (partial derivatives) of the
// heightmap, resulting in a function that gives the surface normal vector for
// any given position on the water surface. Since the derivative of the sum of
// two functions is the sum of each function's derivative, we can analytically
// compute the gradient of each wave layer individually and then add them
// together at the end. In this implementation, computing the gradient (and
// therefore, the normal vector) is nearly as fast as computing the height at a
// given location on the water.
//
// Finally, this heightmap-first formulation of the surface with accompanying
// gradient-based normal maps gives us a surface to apply a variation of
// parallax mapping to. Adding this parallax mapping gives the water surface
// meaningful depth, significantly boosting the quality of the waves, and the
// inherent smoothness in the surface allows us to only use a few iterations
// in the parallax mapping for a minimal performance hit.
//
// This implementation primarily supports smooth, calm, swell-like waves.
// It does not support water surfaces with stormy or high-wind conditions (foam
// / spray / etc), which would be present in more advanced models such as
// Tessendorf's FFT waves as used in Sea of Thieves and similar.
//
// References:
//
// - Value noise (Wikipedia): https://en.wikipedia.org/wiki/Value_noise
// - Value Noise and Procedural Patterns (Scratchapixel): 
//   https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds
//   /procedural-patterns-noise-part-1/introduction.html
// - Analytical derivatives of Perlin noise:
//   https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds
//   /perlin-noise-part-2/perlin-noise-computing-derivatives.html
//     - Note that we use value noise but the idea is essentially the same

// We use the smoothNoise2D variant of our value noise as that function results
// in a continuous, smooth gradient, available as gradSmoothNoise2D. For the
// water to look smooth, the noise must be smooth too - the bilinear
// interpolation in noise is not acceptable, which is why we use the
// smooth "fade" interpolation from Perlin noise instead.
#include "/lib/valueNoise.glsl"

// Whether to compute the gradient based on the slower finite gradient method
// rather than using analytical derivatives.
//#define PREFER_FDM_GRADIENT
#ifndef PREFER_FDM_GRADIENT
	// If we are not using the finite-difference method, we will need the
	// analytical derivatives of value noise. This define signals that they
	// should be enabled.
	//
	// Currently, value noise derivatives require MC_GL_ARB_texture_gather
	// (core in GLSL 4.00).
	//
	// FDM is a fallback for when textureGather is not available.
	#ifdef MC_GL_ARB_texture_gather
		#include "/lib/valueNoiseDerivatives.glsl"
	#else
		// textureGather is not available, we must fall back to FDM.
		#define USE_FDM_GRADIENT
	#endif
#else
	// A developer explicitly enabled FDM, useful for testing the slightly
	// tricker analytical derivative approach.
	#define USE_FDM_GRADIENT
#endif

// This function reshapes the original smooth transitions
// between different wave levels into more visible "crests"
// on the transitions between different wave levels, such that
// most of the area is flat and there are raised crests at regular grid
// transition points.
float crest(float h) {
	const float PI = 3.14159265359;

	// 0.5 - 0.5 * cos written out to explicitly have it as
	// mul -> cos -> fma
	return (-0.5 * cos(h * (PI * 2.0))) + 0.5;
}

// Computes the derivative of the above crest function.
// 
// How to use this:
// 
// Assuming you have a function like this, and you want the gradient of H:
// H(x, y) = crest(N(x, y)) = crest(smoothNoise2D(x, y))
//
// First, let us differentiate over x, applying the chain rule:
// dH/dx = (dCrest/dN)(N(x, y)) * (dN/dx)(x, y)
//
// Given this, the gradient would be (given N = smoothNoise2D):
// gradH(x, y) = crestDerivative(smoothNoise2D(x, y)) * gradSmoothNoise2D(x, y)
float crestDerivative(float h) {
	const float PI = 3.14159265359;

	// mul -> sin -> mul
	return PI * sin(h * (PI * 2.0));
}

// Weaken the gradient since otherwise the waves look way too intense
// otherwise.
//
// TODO: Find a mathematical interpretation of this... I chose this because
//       it looked good but it is probably not appropriate for all possible
//       waves.
const float GRADIENT_STRENGTH = 0.15;

// Define each wave as a set of intuitive measurements which the compiler can
// convert to more direct scaling and offset values, for easy tweaking.
// Beware the parallel definition in caustics_noise.glsl: `CausticNoiseWave`
// repeats the field names `tileSize`, `shearAngle`, `speed`, `heading` and
// `weight` with the same meanings, and adds an `exponent`. The two files are
// never included together, so the names do not collide, but the caustics file's
// comments were copied from this one and its constants are scaled - a
// "Tile Dimensions" or "Speed" figure quoted there is not this struct's value.
struct NoiseWave {
	// The size of each tile in the grid on the X axis and the Y axis in meters.
	//
	// The area covered by each tile is mapped to the area of a single pixel in
	// the value noise texture, and therefore this directly controls the visible
	// size of the visible trough and peak shapes of this wave.
	//
	// Due to the shear mapping below, each tile is actually a parallelogram.
	// However, shear mapping preserves the length along each axis that each
	// tile occupies in the grid, it just slants the tile.
	vec2 tileSize;

	// Shear angle for the vertical shear mapping of the tile grid:
	// https://en.wikipedia.org/wiki/Shear_mapping
	// 
	// This is the angle in radians between the former horizontals and the
	// vertical (Z) axis. 90 degrees = no shear, 0 degrees = maximum shear
	// (not defined as tan(0) = 0)
	//
	// The shear angle may be negative, in which case the shear is in the
	// opposite direction as a  positive shear. Therefore, the acceptable range
	// of values is from -Pi/2 to Pi/2 (-90 degrees to 90 degrees), not
	// inclusive of either -90 degrees or 90 degrees.
	//
	// Diagrams for intuition:
	// 
	// Z
	// |
	// |+--H--+
	// ||     |
	// ||     |
	// |+--H--+
	// | Angle between Z and current horizontal: 90 degrees (shear angle)
	// | The shape is tilted by 0 degrees
	// +--------------X
	//
	// Z
	// |   /|
	// |  / |
	// | FH |
	// |/   /
	// ||  /
	// || FH (Former horizontal)
	// ||/
	// | Angle between Z and FH: 30 degrees (shear angle)
	// | The shape is tilted by 60 degrees
	// +--------------
	//
	float shearAngle;

	// The speed that the wave travels torwards its heading direction in meters
	// (blocks) per second.
	float speed;

	// The heading of the wave, in radians. This follows the unit circle except
	// our Z coordinate is the Y on the unit circle.
	float heading;

	// The weight of this particular wave. The height of each wave is multiplied
	// by its weight and then the sum of all wave weights is divided by the
	// total weight, such that the actual magnitude of this wave is given by
	// weight divided by totalWeight.
	float weight;
};

// Actual wave definitions - these values are converted in the boilerplate code
// below into the actual scales and offsets used at runtime.
#include "/environment/water/surface_noise_waves.glsl"

// We must take the inverse of the tile size (meters per noise pixel) to get the
// scaling factor from world space (noise pixels per meter).
//
// With shearing, the diagonal of the scale matrix remains unmodified, but we
// apply the shearing after scaling, so we multiply the X scale with the
// computed shearing factor. The shearing factor (m) is given by
// cot(shearAngle), equivalently, as GLSL lacks cotangent, 1.0 / tan(shearAngle)
//
// Since we only support X/Z scaling in combination with a vertical shear, while
// we can represent this as a 2D transformation matrix one of the elements will
// always be zero, so we store it as a vector instead where the first two
// components are the diagonal (X/Z scale) and the third element is the first
// column, second row value - in other words, the scaling factor applied to the
// X coordinate that gets added to the final Y position.
// 
// We could expand this to a mat2 like so: 
// mat2(stretch.x, stretch.z, 0.0, stretch.y)
//
// Mathematica / Mathics code useful for validating the shear multiplication:
//
// VerticalShearMatrix[T_] := {{1.0, 0.0}, {T, 1.0}}
// Simplify[Dot[VerticalShearMatrix[Shear], Dot[{{XScale, 0.0}, {0.0, YScale}},
//     {X, Y}]] // MatrixForm]
// Simplify[Dot[Dot[VerticalShearMatrix[Shear], {{XScale, 0.0}, {0.0, YScale}}],
//     {X, Y}] // MatrixForm]
// Simplify[Dot[VerticalShearMatrix[Shear], {{XScale, 0.0}, {0.0, YScale}
//     ] // MatrixForm]
const vec3 rippleStretch[4] = vec3[](
	vec3(1.0 / RIPPLES[0].tileSize.x, 1.0 / RIPPLES[0].tileSize.y,
		(1.0 / tan(RIPPLES[0].shearAngle)) / RIPPLES[0].tileSize.x),
	vec3(1.0 / RIPPLES[1].tileSize.x, 1.0 / RIPPLES[1].tileSize.y,
		(1.0 / tan(RIPPLES[1].shearAngle)) / RIPPLES[1].tileSize.x),
	vec3(1.0 / RIPPLES[2].tileSize.x, 1.0 / RIPPLES[2].tileSize.y,
		(1.0 / tan(RIPPLES[2].shearAngle)) / RIPPLES[2].tileSize.x),
	vec3(1.0 / RIPPLES[3].tileSize.x, 1.0 / RIPPLES[3].tileSize.y,
		(1.0 / tan(RIPPLES[3].shearAngle)) / RIPPLES[3].tileSize.x));

const vec3 crestStretch[2] = vec3[](
	vec3(1.0 / CRESTS[0].tileSize.x, 1.0 / CRESTS[0].tileSize.y,
		(1.0 / tan(CRESTS[0].shearAngle)) / CRESTS[0].tileSize.x),
	vec3(1.0 / CRESTS[1].tileSize.x, 1.0 / CRESTS[1].tileSize.y,
		(1.0 / tan(CRESTS[1].shearAngle)) / CRESTS[1].tileSize.x));

// Convert the speed and heading into the horizontal offset vector to multiply
// by time - we call this the "scroll" vector as it is the vector used to scroll
// the waves across the world as time passes.
//
// Essentially, we convert the speed and heading into a vector in world space,
// and then transform into the coordinate system of this particular wave.
//
// Finally, we multiply by negative 1. Why? Well, to make it look like the wave
// at (0, 0) moved 1 unit towards positive X, we must subtract 1 unit to make
// the wave that was at (0, 0) now appear at (1, 0) because (1 - 1, 0) is
// (0, 0), the original position of the wave.
const vec2 rippleScroll[4] = vec2[](
	-mat2(
		rippleStretch[0].x, 
		rippleStretch[0].x / tan(RIPPLES[0].shearAngle),
		0.0,
		rippleStretch[0].y)
	 * RIPPLES[0].speed
	 * vec2(cos(RIPPLES[0].heading), sin(RIPPLES[0].heading)),
	-mat2(
		rippleStretch[1].x, 
		rippleStretch[1].x / tan(RIPPLES[1].shearAngle),
		0.0,
		rippleStretch[1].y)
	 * RIPPLES[1].speed
	 * vec2(cos(RIPPLES[1].heading), sin(RIPPLES[1].heading)),
	-mat2(
		rippleStretch[2].x,
		rippleStretch[2].x / tan(RIPPLES[2].shearAngle),
		0.0,
		rippleStretch[2].y)
	 * RIPPLES[2].speed
	 * vec2(cos(RIPPLES[2].heading), sin(RIPPLES[2].heading)),
	-mat2(
		rippleStretch[3].x,
		rippleStretch[3].x / tan(RIPPLES[3].shearAngle),
		0.0,
		rippleStretch[3].y)
	 * RIPPLES[3].speed
	 * vec2(cos(RIPPLES[3].heading), sin(RIPPLES[3].heading)));

const vec2 crestScroll[2] = vec2[](
	-mat2(
		crestStretch[0].x,
		crestStretch[0].x / tan(CRESTS[0].shearAngle),
		0.0,
		crestStretch[0].y)
	 * CRESTS[0].speed
	 * vec2(cos(CRESTS[0].heading), sin(CRESTS[0].heading)),
	-mat2(
		crestStretch[1].x,
		crestStretch[1].x / tan(CRESTS[1].shearAngle),
		0.0,
		crestStretch[1].y)
	 * CRESTS[1].speed
	 * vec2(cos(CRESTS[1].heading), sin(CRESTS[1].heading)));

// Compute the magnitude of each wave layer at compile time by dividing each
// weight by the total weight, so we do not need to do this at runtime.
const float totalWeight = 0.0
	#if NUM_RIPPLES > 0
		+ RIPPLES[0].weight
	#endif
	#if NUM_RIPPLES > 1
		+ RIPPLES[1].weight
	#endif
	#if NUM_RIPPLES > 2
		+ RIPPLES[2].weight
	#endif
	#if NUM_RIPPLES > 3
		+ RIPPLES[3].weight
	#endif
	#if NUM_CRESTS > 0
		+ CRESTS[0].weight
	#endif
	#if NUM_CRESTS > 1
		+ CRESTS[1].weight
	#endif
	;

const float crestMagnitude[2] = float[](
	#if NUM_CRESTS > 0
		CRESTS[0].weight / totalWeight
	#else
		0.0
	#endif
	#if NUM_CRESTS > 1
		,CRESTS[1].weight / totalWeight
	#else
		,0.0
	#endif
	);

const float rippleMagnitude[4] = float[](
	#if NUM_RIPPLES > 0
		RIPPLES[0].weight / totalWeight
	#else
		0.0
	#endif
	#if NUM_RIPPLES > 1
		,RIPPLES[1].weight / totalWeight
	#else
		,0.0
	#endif
	#if NUM_RIPPLES > 2
		,RIPPLES[2].weight / totalWeight
	#else
		,0.0
	#endif
	#if NUM_RIPPLES > 3
		,RIPPLES[3].weight / totalWeight
	#else
		,0.0
	#endif
	);

// Avoiding excessive aliasing in our procedural water surface:
//
// From a quick survey of the waves in most existing shader packs, essentially
// everyone  anti-aliases water surface/reflections temporally (TAA), with FXAA,
// or applies both. But, both of these methods have meaningful tradeoffs to both
// performance and quality. FXAA and TAA are both ultimately really advanced
// screen-wide blurs, and even the best implementations have artifacts and can
// cause negative impact to clarity. At worst, TAA turns distant geometry into a
// mess of blurry jittering, and FXAA can be almost as bad, essentially blurring
// everything. 3kliksphilip made a great video that mentions the shortcomings of
// FXAA here: https://www.youtube.com/watch?v=nEbAJHd84ug&t=224s)
//
// With procedural water surfaces, there is some truly awful aliasing when no
// attempt is made to mitigate it. While it is tempting to jump immediately to
// TAA/FXAA, that is not the best way! While these methods or other ones like
// MSAA are the solution for removing aliasing on surface edges, aliasing within
// a surface indicates problems in how we are sampling the surface that we can
// and should fix. We want the surface to look decent without TAA/FXAA, such
// that TAA/FXAA are an enhancement rather than a requirement for a good image.
//
// Essentially, for each individual layer of noise, our goal is to determine if
// the ratio of pixels in the 64x64 noise texture to pixels visible on the
// screen in a given area of the scene is too high. Certainly, if we are at a
// 1:1 ratio or higher, such that a noise pixel only covers one pixel or part of
// a pixel on the screen, then we will have severe aliasing as in that case our
// coherent noise will degrade to white noise on the screen. But we will still
// get aliasing at lower ratios. As it turns out, we can base this on the
// https://en.wikipedia.org/wiki/Nyquist_rate.
//
// So, our goal here is to widen the area each layer is sampled over once that
// layer's detail stops fitting on the screen. Widening is a box filter: it
// removes the detail that cannot be represented at that distance and keeps the
// large waves. That is the opposite of fading a layer to its average, and the
// note on antialiasFootprint below is where the difference is argued.
//
// The noise texture is 64x64 - see `noiseTextureResolution` in
// lib/valueNoise.glsl, which is the constant this comment's "64x64" means.
//
// What decides the width is the fragment's DISTANCE FROM THE CAMERA, and that is
// the whole point of batch 756. The ratio this used to be built from was a
// screen-space quantity, so the sub-pixel jitter TAA adds to gl_FragCoord moved
// it every frame, the sample coordinate moved with it, and distant water
// flickered. Distance is a world quantity; the jitter cannot reach it.
//
// References:
//
// - Section "One Last Very Important Thing to Know" of 
//   https://www.scratchapixel.com/lessons/procedural-generation-virtual-worlds
//   /procedural-patterns-noise-part-1/creating-simple-1D-noise.html
//
// Further work:
//
// - If we support cone-traced rough/glossy reflections in the future, we can
//   forward some sort of roughness value out of here instead of leaving the
//   reflection as smooth as the widened sample makes it.
//
// BATCH 756: THE SCREEN-SPACE RATIO IS GONE, AND THE FOOTPRINT IS A DISTANCE.
//
// What used to be here was `antialiasFactor(ddxWorldPos, ddyWorldPos, stretch)`.
// It built the Jacobian of the noise coordinate with respect to the screen from
// the world-space screen derivatives, took the largest absolute element, and
// returned that as a ratio of noise pixels to screen pixels - a Nyquist metric,
// after "Detail Synthesis for Image-based Texturing" (Ismert/Bala/Greenberg).
//
// That metric was correct about aliasing and wrong about time. It is a
// SCREEN-SPACE quantity, so it moves whenever the sample moves on the screen,
// and this pack's TAA moves the sample every frame: the sub-pixel jitter is
// added to gl_FragCoord, gl_FragCoord is what the fragment rebuilds its position
// from, and the derivatives are built from that position. So the ratio changed
// every frame, the footprint changed with it, the sample coordinate changed with
// it, and the wave normal jumped every frame. Distant water flickered.
//
// The author's report dates the symptom to batch 754, and that is right: before
// 754 the ratio only fed `smoothstep(0.45, 0.55, ratio)`, which is saturated at
// 1.0 for every ratio past 0.55 - so the jitter was invisible. 754 replaced the
// fade with `clamp(ratio, 1.0, 4.0)`, which varies continuously over exactly the
// range the jitter moves the ratio through, and the jitter became a visible jump.
//
// Neither reference pack reads a screen-space quantity here. Bliss
// (lib/waterBump.glsl, getWaveNormal) widens by `length(playerpos)`, a world
// distance; Sundial (libs/Water.glsl) has no distance term at all. So the
// footprint is now built from the fragment's distance to the camera, which is
// also a world quantity: the jitter cannot reach it, and the normal becomes a
// function of world position and time alone, the way both references are.

// The distance, in blocks, at which the sample footprint is at its widest.
//
// This is the one number that decides how much wave detail survives at distance,
// and it is a starting value for the author to tune in game rather than a
// measurement: 64 blocks is roughly where the pack's smallest ripple tiles (15 x
// 20 cm) stop fitting a pixel at a typical field of view, so it is where the
// widening has to be complete. The footprint is at its narrowest at a quarter of
// this distance - see antialiasFootprint below.
#define WATER_FOOTPRINT_DISTANCE 64.0

// How much wider than one texel the wave field should be sampled at this distance.
//
// BATCH 754 introduced this as the replacement for the fade, and it is Bliss's
// formula with this pack's units: `min(distance / (16 * 24), 3)` in Bliss, where
// the 16 is its own wave scale. Here the distance is already in blocks and the
// wave field is indexed in blocks, so the divisor is the distance at which the
// widest footprint is reached.
//
// THE CAP MATTERS AND IS BLISS'S. Without it the footprint would keep growing
// and the far water would go flat again - which is the defect being fixed,
// reached by a different route. At the cap the waves stop changing with distance,
// so the far water keeps the surface it had at the cap rather than losing it.
//
// The value is a multiplier on the sample offset, not a fade: 1.0 is the
// unmodified wave field and 4.0 is a footprint four times as wide.
//
// BATCH 756 changed the INPUT, not the shape. `distanceToCamera` is
// `length(cameraRelativePos)`, a world quantity, so TAA's jitter cannot move it -
// see the note above. The factor of four is the ratio between the two ends of the
// ramp: the footprint is one texel wide up to a quarter of
// WATER_FOOTPRINT_DISTANCE and four texels wide from there outwards.
float antialiasFootprint(float distanceToCamera) {
	return clamp(
		distanceToCamera * (4.0 / WATER_FOOTPRINT_DISTANCE), 1.0, 4.0);
}

// BATCH 754: THE TWO HELPERS THAT FADED A LAYER TO ITS AVERAGE ARE GONE.
//
// They were `antialiasHeight(aa, height) = mix(height, 0.5, aa)` and
// `antialiasGradient(aa, gradient) = gradient * (1 - aa)`. Both do the same thing
// to a wave: they shrink its variation towards zero, and at aa = 1 the layer is a
// constant - no height, no gradient, no tilt. That is the mirror.
//
// The replacement is not a helper at all: the footprint widens the SAMPLE, so the
// layer keeps its full variation and simply gets averaged over a wider area by the
// texture filter. See antialiasFootprint above and the `footprint` argument of the
// functions below.

// Returns water height between 0.0 and 1.0, with 0.0 being the lowest and 1.0
// being the highest.
//
// This function is responsible for adding together each wave layer into the
// final heightmap.
//
// Inputs: world position on the water plane in meters, the world-space screen
// derivatives of it, time in seconds, the fragment's distance to the camera, and
// `approximate`.
//
// The screen derivatives are accepted and NOT read, and that is batch 756: the
// sample footprint is built from `distanceToCamera` now, because a screen-space
// quantity is what TAA's jitter moved every frame. They stay in the signature
// because the caller computes them for the parallax mapping and because
// surface_basic.glsl has to keep the same one - see the note above
// antialiasFootprint.
//
// On the space of `worldPos`: the X and Z are world space, but for a face that
// is standing up the caller has already folded world Y into both of them - see
// parallaxWaterNormal in translucent.glsl, which does
// `waterWorldPos += vec2(cameraRelativePos.y + cameraPosition.y)` when the face
// is sideways. So worldPos.y contributes to the noise coordinate on a vertical
// face, and "in meters" is the units of the input, not a promise that the two
// components are both horizontal.
//
// `approximate` truncates the ripple loop to NUM_BIG_RIPPLES; see the comment
// on that loop below.
float WaterHeight(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time,
	float distanceToCamera,
	bool approximate
) {
	float height = 0.0;

	// BATCH 756: the footprint is the same for every layer, so it is built once.
	//
	// It used to be built inside both loops, because it was derived from the
	// layer's own `stretch` - the ratio was per-layer by construction. A distance
	// is not: every layer of the field is sampled at the same distance from the
	// camera, so the widening is one number for the whole function.
	float footprint = antialiasFootprint(distanceToCamera);

	// === A note on dot products and fused multiply add (FMA) ===
	//
	// Note for this function as well as the gradient function that 
	// dot(worldPos, stretch.zy) is just equivalent to:
	//
	//   worldPos.y * stretch.y + worldPos.x * stretch.z
	//
	// It's just that the way it is written compiles to 2 instructions: fma, mul
	//
	// Essentially every GPU offers FMA (A * B + C) as a single instruction
	// so you benefit from using dot and arranging your math in FMA form
	// (A * B + C). The compiler can't always find these patterns so it's best
	// to help it along!

	// Ripple waves - Scrolled and stretched smooth value noise
	//
	// During parallax mapping, the last two ripples contribute minimally, and
	// it is possible to get a decent FPS boost from ignoring them.
	uint ripples = uint(NUM_RIPPLES);

	if (approximate) {
		ripples = min(uint(NUM_BIG_RIPPLES), uint(NUM_RIPPLES));
	}

	for (uint i = uint(0); i < ripples; i++) {
		vec3 stretch = rippleStretch[i];
		vec2 scroll = rippleScroll[i];

		vec2 stretched = vec2(
			worldPos.x * stretch.x,
			dot(worldPos, stretch.zy));
		vec2 at = time * scroll + stretched;

		// BATCH 754: THE FOOTPRINT WIDENS THE SAMPLE, IT DOES NOT FADE THE LAYER.
		//
		// Dividing the coordinate by the footprint is the same as sampling the
		// field over a footprint-times-wider area: the texture filter then
		// averages that area, which removes the detail that cannot be resolved at
		// this distance and keeps the large waves. The layer's own variation is
		// untouched, so the normal still tilts.
		//
		// The scroll is divided by the same factor so that the wave does not
		// appear to speed up as the footprint grows - the pattern is being
		// magnified, and its motion has to be magnified with it or distant water
		// would crawl faster than near water.
		vec2 atScaled = (time * scroll + stretched) / footprint;

		height += rippleMagnitude[i] * smoothNoise2D(atScaled);
	}

	// Crest waves - Like ripple waves, but we use crest around the result of
	// the smoothed value noise.
	for (uint i = uint(0); i < uint(NUM_CRESTS); i++) {
		vec3 stretch = crestStretch[i];
		vec2 scroll = crestScroll[i];
		
		vec2 stretched = vec2(
			worldPos.x * stretch.x,
			dot(worldPos, stretch.zy));
		vec2 at = time * scroll + stretched;

		// Same footprint as the ripple loop above, and for the same reason.
		vec2 atScaled = (time * scroll + stretched) / footprint;

		height += crestMagnitude[i] * crest(smoothNoise2D(atScaled));
	}

	return height;
}

float WaterHeight(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time,
	float distanceToCamera
) {
	return WaterHeight(
		worldPos, ddxWorldPos, ddyWorldPos, time, distanceToCamera, false);
}

float WaterHeightApproximate(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time,
	float distanceToCamera
) {
	return WaterHeight(
		worldPos, ddxWorldPos, ddyWorldPos, time, distanceToCamera, true);
}

#if !defined(USE_FDM_GRADIENT)

// Computes the negative gradient of the water surface using analytic
// derivatives.
//
// In other words, we found the derivative / gradient function ahead of time
// using calculus, simplifying the computations that need to be done each frame.
//
// This function returns -gradient (negative gradient) since the normal is
// perpendicular to the actual gradient, and we can bake the multiplication by
// -1 into one of the existing multiplies so that it is free.
vec2 WaterNGradientAnalytic(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time,
	float distanceToCamera
) {
	vec2 gradient = vec2(0.0);

	// BATCH 756: one footprint for every layer, built from the distance.
	//
	// It used to be built inside both loops from the layer's own `stretch`, which
	// made it per-layer; a distance is not per-layer. See the note above
	// antialiasFootprint.
	float footprint = antialiasFootprint(distanceToCamera);

	// Ripple waves - Scrolled and stretched smooth value noise
	for (uint i = uint(0); i < uint(NUM_RIPPLES); i++) {
		vec3 stretch = rippleStretch[i];
		vec2 scroll = rippleScroll[i];

		// Same notes here as in the WaterHeight function
		vec2 stretched = vec2(
			worldPos.x * stretch.x,
			dot(worldPos, stretch.zy));
		vec2 at = time * scroll + stretched;

		// BATCH 754: THE FOOTPRINT SCALES THE GRADIENT, IT DOES NOT FADE IT.
		//
		// Sampling the field over a footprint-times-wider area divides the
		// gradient by the footprint - a wider box filter has a gentler slope for
		// the same underlying wave. That is the chain rule, not a fade: the wave
		// is still there, it is just being read at a coarser scale. The old
		// `antialiasGradient` multiplied by (1 - aa), which went to ZERO at full
		// fade and took the tilt with it.
		vec2 waveGradient = (GRADIENT_STRENGTH * rippleMagnitude[i])
			* gradSmoothNoise2D(at / footprint);

		// This part is the main tricky part of the analytic gradient - we have
		// the scaled gradient of the value noise at this position, but due to
		// the coordinate stretching caused by adding worldPos.x into the Y
		// value of the noise, the partial derivative with respect to X is
		// actually a directional derivative.
		//
		// The Y part is simple enough - just multiplying the Y scale factor
		// with the corresponding part of the gradient as a part of applying the
		// chain rule. Adding in X as a part of stretching has no impact because
		// we are only interested in the partial derivative with respect to Y,
		// so that X term is a constant.
		//
		// For the X part, though in the original coordinate transform we allow
		// X to influence the Y value, this means that the impact is actually to
		// the X partial derivative. As we vary the value of X, we move
		// diagonally across the value noise, in other words, along a given
		// direction.
		//
		// Luckily, directional derivatives are simple - it is just the dot of
		// the direction and magnitude vector in that direction with the
		// gradient vector, which is exactly what we have here.
		//
		// Finally, as this is the negative gradient, we subtract when
		// accumulating.
		//
		// The division by the footprint is the chain rule for the wider sample:
		// the coordinate was divided by it above, so the derivative is divided by
		// it too. See the note at the top of this loop.
		gradient -= vec2(dot(stretch.xz, waveGradient), waveGradient.y * stretch.y)
			/ footprint;
	}

	// Crest waves - Like ripple waves, but we use crest around the result of
	// the smoothed value noise.
	for (uint i = uint(0); i < uint(NUM_CRESTS); i++) {
		vec3 stretch = crestStretch[i];
		vec2 scroll = crestScroll[i];
		
		vec2 stretched = vec2(
			worldPos.x * stretch.x,
			dot(worldPos, stretch.zy));
		vec2 at = time * scroll + stretched;

		// BATCH 754: the crest loop takes the same footprint as the ripple loop.
		//
		// The old code inlined both halves of the fade here - `mix(noise, 0.5, aa)`
		// for the height and `(1 - aa)` for the gradient - which is the same
		// flattening by another route. Now the coordinate is divided by the
		// footprint and the gradient by the same factor, so the crest keeps its
		// shape and only its scale changes.
		//
		// The height the crest function is evaluated at, at the widened scale.
		float heightAt = smoothNoise2D(at / footprint);

		// The main complexity here is that we need to apply the chain rule due
		// to the crest function.
		//
		// Other than that, this is fairly similar to above.
		vec2 waveGradient = (GRADIENT_STRENGTH * crestMagnitude[i])
			* gradSmoothNoise2D(at / footprint) * crestDerivative(heightAt);

		// Same notes apply as above: the division is the chain rule for the wider
		// sample, not a fade.
		gradient -= vec2(dot(stretch.xz, waveGradient), waveGradient.y * stretch.y)
			/ footprint;
	}

	return gradient;
}

#endif

// Computes the negative gradient of the water surface using the finite
// difference method (FDM):
// https://en.wikipedia.org/wiki/Finite_difference_method
//
// This function returns -gradient (negative gradient) since the normal is
// perpendicular to the actual gradient, and we can bake the multiplication by
// -1 into one of the existing multiplies so that it is free:
//
// https://en.wikipedia.org/wiki/Normal_(geometry)#Calculating_a_surface_normal
//
// This should be slower than the analytic method, but it is useful as a
// fallback to debug and diagnose issues since the complexity of FDM is a lot
// more manageable than the analytic method. In addition, FDM is useful when
// developing new wave shapes as it makes it possible to experiment
// without needing to do hours of error-prone calculus to get your results.
//
// But, for something widely-distributed in production, it makes sense to use
// the more efficient analytical method to get maximum performance.
// This is a real runtime path and not only a debugging tool: `PREFER_FDM_GRADIENT`
// above is commented out, so `USE_FDM_GRADIENT` is defined either by that
// developer switch or, at the top of this file, when
// MC_GL_ARB_texture_gather is missing - in which case the analytic derivatives
// are not included at all and this is what the pack runs on. Selection is the
// `#if defined(USE_FDM_GRADIENT)` in WaterNormal at the bottom of the file.
vec2 WaterNGradientFDM(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time,
	float distanceToCamera
) {
	// This is about the lowest I could go without major artifacts. The lower
	// you can go the better, but at some point we run out of floating-point
	// precision or hit limitations of the underlying sampling going on in the
	// wave funciton. Play around with this as needed.
	//
	// Units: this is an offset added to a `worldPos` that is in meters, so it is
	// a distance in meters too - 5 cm. It is not a fraction of the wave height,
	// which is why it is a fixed constant and not scaled by the wave size.
	const float delta = 0.05;

	vec2 ddxPos = ddxWorldPos;
	vec2 ddyPos = ddyWorldPos;
	float h00 = WaterHeight(
		worldPos, ddxPos, ddyPos, time, distanceToCamera);
	float hX0 = WaterHeight(
		worldPos + vec2(delta, 0.0), ddxPos, ddyPos, time, distanceToCamera);
	float h0Y = WaterHeight(
		worldPos + vec2(0.0, delta), ddxPos, ddyPos, time, distanceToCamera);

	return (-GRADIENT_STRENGTH / delta) * (vec2(hX0, h0Y) - vec2(h00));
}

// Returns the normal map for the water surface computed from the gradient of
// the water surface heightmap.
//
// Same input contract as WaterHeight above: world position with the caller's
// possible folding of world Y into it, world-space screen derivatives, time in
// seconds, and the fragment's distance to the camera.
//
// Output: normal vector in tangent space (X/Y = in-plane, Z = up out of the
// plane). Z is a constant 1.0 before the normalize, so this is a perturbed
// normal whose tilt is bounded by the size of the gradient.
vec3 WaterNormal(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time,
	float distanceToCamera
) {
	#if defined(USE_FDM_GRADIENT)
		vec2 minusGradient = WaterNGradientFDM(
			worldPos, ddxWorldPos, ddyWorldPos, time, distanceToCamera);
	#else
		vec2 minusGradient = WaterNGradientAnalytic(
			worldPos, ddxWorldPos, ddyWorldPos, time, distanceToCamera);
	#endif

	return normalize(vec3(minusGradient, 1.0));
}
