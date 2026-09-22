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

// Noisy godrays implementation

#include "/lib/bayer8.glsl"

// Whether the light shafts are drawn under water as well as in air.
//
// Above the waterline the shafts are made from a mask of where the sky is
// visible, and under water that mask is empty. The surface of the water is
// drawn into the depth buffer this pass reads - the composite stage runs after
// the translucent pass - and from below it is a plane above the camera that
// covers the whole of the upper view, so there is no sky anywhere on screen
// for the mask to count. Every sample fails the test, the mask is zero
// everywhere, and the shafts simply do not appear. Nothing is broken; the
// question the march asks has no answer down there.
//
// This puts them back, by asking the same question of the water: what the
// light comes through is the surface instead of the sky, and what gets in the
// way is the terrain. See UnderwaterGodrays below for the march.
//
// The shafts run along the sun's own direction, the same axis as above the
// waterline. Light really does bend as it enters water and would come down
// steeper, so there was a version of this that refracted the axis - and it had
// to go, because the sun drawn in the sky here is placed without that bend:
// refracting the shafts on their own aimed them at a point the sun is not drawn
// in, and the two visibly did not belong to each other. Neither of the packs
// this one quotes - Mellow Shader and Sundial Lite - refracts the light either;
// they march along the sun's own direction under water exactly as they do above
// it, and so does this.
//
// Only in water. In lava and in powder snow there is no surface overhead for
// the light to come through, and the fog is opaque enough that nothing would
// be seen through it anyway.
#define UNDERWATER_GODRAYS

// How bright the shafts are under water, as a multiple of the ones above it at
// the same time of day. At 0.0 they are off, which leaves the shafts above the
// waterline exactly as they were.
#define UNDERWATER_GODRAYS_STRENGTH 1.5 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]

// The sky should have a depth value of 1.0. This is one of the few places
// where == works reliably.
const float SKY_DEPTH = 1.0;

// Sample a depth texture with depth comparison. This is a hack because we
// cannot use sampler objects to sample the depth texture with comparison mode
// enabled.
//
// This is effectively allowing us to use the sampler like a shadow sampler,
// without having that enabled:
// https://www.khronos.org/opengl/wiki/Sampler_(GLSL)#Shadow_samplers
//
// TODO(engine): Add PCF sampling for the main depth texture in Iris
uniform sampler2D depthtex0;

float DepthCompareSample(vec3 texCoord) {
	// Equivalent GL_TEXTURE_COMPARE_FUNC: GL_LEQUAL
	return float(texCoord.z <= texture(depthtex0, texCoord.xy).r);
}

// Godrays function based on GPU Gems 3:
//
// "Chapter 13. Volumetric Light Scattering as a Post-Process"
// https://developer.nvidia.com/gpugems/gpugems3/part-ii-light-and-shadows
//
// Tweaks:
// - Moved to sampling the depth map instead of the color map
//   (DepthCompareSample)
// - By varying the starting position using noise, we can get away with a
//   much-reduced sample count
float NoisyGodrays(vec2 texCoord, vec2 ScreenLightPos) {
	// Constants for the godrays
	const float NUM_SAMPLES = 8.0;
	const float DENSITY = 0.83;
	const float DECAY = pow(0.5, 1.0 / NUM_SAMPLES);

	// Calculate vector from pixel to light source in screen space.
	vec2 deltaTexCoord = (texCoord - ScreenLightPos);
	// Divide by number of samples and scale by control factor.
	deltaTexCoord *= 1.0f / NUM_SAMPLES * DENSITY;
	// NEW: Use noise to allow us to get away with a singificantly reduced
	// iteration count.
	texCoord += deltaTexCoord * 1.5 * Bayer8(gl_FragCoord.xy);
	// Store initial sample.
	float accumulated = DepthCompareSample(vec3(texCoord, SKY_DEPTH));
	// Set up illumination decay factor.
	float illuminationDecay = 1.0f;
	// Evaluate summation from Equation 3 NUM_SAMPLES iterations.
	for (uint i = uint(0); i < uint(NUM_SAMPLES); i++) {
		// Step sample location along ray.
		texCoord -= deltaTexCoord;
		// Retrieve sample at new location.
		float depthSample = DepthCompareSample(vec3(texCoord, SKY_DEPTH));
		// Apply sample attenuation scale/decay factors.
		depthSample *= illuminationDecay;
		// Accumulate depth samples.
		accumulated += depthSample;
		// Update exponential decay factor.
		illuminationDecay *= DECAY;
	}
	// Output final accumulated sample with a further scale control factor.
	return accumulated / NUM_SAMPLES;
} 

#ifdef UNDERWATER_GODRAYS
	// The water caustics, which is what the ripples do to the light that comes
	// through them. Included for WaterSurfaceRipple below, which says why it is
	// the right thing to reach for rather than a wave function written here.
	#include "/environment/water/caustics_noise.glsl"

	// 1 when the camera is in water, 2 in lava, 3 in powder snow.
	uniform int isEyeInWater;

	// The opaque depth - everything except the translucent pass. Under water
	// that means the water is not in this buffer, which is the whole reason it
	// is the one the march below asks: the water is what the light comes
	// through here, so it must not read as an obstruction.
	uniform sampler2D depthtex1;

	// For turning a sample of the surface back into a place on the world, so
	// that the ripples on it can be read - see WaterSurfaceRipple.
	uniform vec3 cameraPosition;
	uniform mat4 gbufferProjectionInverse;
	uniform mat4 gbufferModelViewInverse;

	// Drives the ripples.
	uniform float frameTimeCounter;

	// How much light the ripples let through at one point on the underside of
	// the surface, as a multiple of what a flat, still surface would let
	// through.
	//
	// This is the pack's own water caustics - the pattern the seafloor is
	// dappled with - read on the surface rather than on the sand. It is the
	// right function to reach for because it is not a decoration standing in
	// for the ripples: it is what the ripples do to the light, and it is a
	// projection along the world Y axis, so the same wave is overhead and on
	// the sand below it. The shafts and the dappling therefore come out of one
	// pattern instead of two, which is also the only way the two can agree.
	//
	// texCoord and depth are the screen position and the depth of a sample that
	// landed on the surface, which together say where on the world's water it
	// is.
	float WaterSurfaceRipple(vec2 texCoord, float depth) {
		vec3 ndcPos = vec3(texCoord * 2.0 - 1.0, depth * 2.0 - 1.0);
		vec4 viewPosH = gbufferProjectionInverse * vec4(ndcPos, 1.0);
		vec3 worldPos = (gbufferModelViewInverse
			* vec4(viewPosH.xyz / viewPosH.w, 1.0)).xyz + cameraPosition;

		// Note: the development option that freezes the animations is not
		// consulted here. It is defined in the surface programs, so a condition
		// on it in this file would be a branch this pass can never take, and it
		// would read as the freeze reaching the shafts when it does not.
		float caustics = WaterCaustics(worldPos, frameTimeCounter);

		// The same shape as SampleWaterCaustics in
		// environment/lighting/shadowmap.glsl: the caustic comes back as a
		// shift around one that can be negative, and a negative shift would
		// mean a surface taking away light that was never there, so it is
		// floored at nothing.
		return max(0.0, 1.0 + caustics);
	}

	// The shafts below the waterline. The same march as NoisyGodrays, and the
	// same question - how much of the path from this pixel to the light is
	// clear - asked of the water rather than of the sky.
	//
	// What is in the way is read from depthtex1, the opaque depth. It is the
	// buffer the water is not in, and under water that is what makes it the
	// right one: the light comes through the water, so the water must not count
	// as an obstruction, and what does obstruct is the terrain and the seafloor
	// standing in the way.
	//
	// Where the path meets the surface, the light it brings down is modulated
	// by the ripples - see WaterSurfaceRipple. A still surface lowers a smooth
	// sheet of light; a rippling one gathers it into the bright lines that make
	// the light read as shafts rather than as a glow around the sun.
	//
	// ScreenLightPos is the sun's own screen position, handed in unchanged from
	// the call below: the shafts run along one axis on both sides of the
	// waterline, so that they converge on the sun that is actually drawn in the
	// sky above. The reasoning is written out on the option at the top of this
	// file.
	float UnderwaterGodrays(vec2 texCoord, vec2 ScreenLightPos) {
		// Constants for the godrays
		const float NUM_SAMPLES = 8.0;
		const float DENSITY = 0.83;
		const float DECAY = pow(0.5, 1.0 / NUM_SAMPLES);

		// Calculate vector from pixel to light source in screen space.
		vec2 deltaTexCoord = (texCoord - ScreenLightPos);
		// Divide by number of samples and scale by control factor.
		deltaTexCoord *= 1.0f / NUM_SAMPLES * DENSITY;
		// The same noise, for the same reason: it is what lets the sample count
		// stay this low.
		texCoord += deltaTexCoord * 1.5 * Bayer8(gl_FragCoord.xy);

		// How much of the path to the light is clear of solid geometry.
		float accumulated = 0.0;
		// What the surface is doing where the path crosses it. There is exactly
		// one such place - light enters the water once - so it is looked for
		// once and then left alone. Left at 1.0, no modulation at all, if no
		// sample landed on the surface.
		float surface = 1.0;
		bool crossed = false;

		// Set up illumination decay factor.
		float illuminationDecay = 1.0f;

		for (uint i = uint(0); i < uint(NUM_SAMPLES); i++) {
			// Step sample location along ray.
			texCoord -= deltaTexCoord;

			// Nothing opaque here means open water, or the sky above it, and
			// the light gets through either way.
			if (texture(depthtex1, texCoord).r >= SKY_DEPTH) {
				if (!crossed) {
					// depthtex0 is the one with the translucent pass in it, so
					// a translucent surface standing in front of open water is
					// the water's own surface seen from below. This is the same
					// test composite1 makes when it asks whether a pixel is
					// being looked at through something.
					float translucent = texture(depthtex0, texCoord).r;

					if (translucent < SKY_DEPTH) {
						surface = WaterSurfaceRipple(texCoord, translucent);
						crossed = true;
					}
				}

				// Accumulate the samples the light gets through.
				accumulated += illuminationDecay;
			}
			// Anything else is solid geometry, which stops the light: it adds
			// nothing to the sum and the decay carries on.

			// Update exponential decay factor.
			illuminationDecay *= DECAY;
		}

		return accumulated / NUM_SAMPLES * surface;
	}
#endif

uniform vec2 windowToScreenGodrays;
uniform vec4 screenLightVector;
uniform float godraysExposure;

// Output format is just a single color channel, 8 bits is enough.
//
// Originally I used 16 bits, but it turns out that if we do not scale the
// result, since we are smoothing the result anyways and the noise acts as a
// dither, there is actually zero noticeable difference between 8 bits and 16
// bits. So switching to 8 bit halves the required memory bandwidth on both ends
// basically for free, compared to using 16 bits.
const int R8 = 0;
const int colortex1Format = R8;

/* DRAWBUFFERS:1 */
out float godrays;

void main() {
	if (godraysExposure <= 0.0) {
		// Prevent the buffer from getting filled with garbage
		// unitialized garbage - not visible without debug view,
		// but avoiding undefined behavior is good.
		godrays = 0.0;
		return;
	}

	// Determine the position of this fragment on the screen in screen
	// coordinates (0.0 to 1.0).
	vec2 screenCoord = gl_FragCoord.xy * windowToScreenGodrays;

	#ifdef UNDERWATER_GODRAYS
		// Under water the mask is built from what the water lets through
		// instead of from where the sky is - see UnderwaterGodrays. The light
		// axis is not one of the differences: it is the same vector the line
		// below uses. The exposure has already been chosen for the case by
		// shaders.properties, so the early out above covers both.
		if (isEyeInWater == 1) {
			godrays = UnderwaterGodrays(screenCoord, screenLightVector.xy);
			return;
		}
	#endif

	// While we check whether godrays are exposed above to avoid
	// additional computation cost, to fully use the 8 bits of
	// precision do not scale the value here.
	godrays = NoisyGodrays(screenCoord, screenLightVector.xy);
}
