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

// Final fragment shader that implements tonemapping, debugging visualization,
// and all other postprocessing shader effects. As this shader pack follows a
// forward-rendering architecture with most effects implemented directly
// rather in a deferred pass, this program is very minimal.

// This is a very compact floating-point color format using 32 bits just as
// RGBA8 does, while permitting HDR colors.
//
// Note that even though this format lacks an alpha channel, translucency is
// still supported, as translucent alpha blending does not actually require
// writing to the alpha channel as in all cases we are drawing against an opaque
// background.
const int R11F_G11F_B10F = 0;
const int colortex0Format = R11F_G11F_B10F;

#include "/lib/tonemap_uncharted2.glsl"
#include "/lib/tonemap_uchimura.glsl"
#include "/lib/srgb.glsl"

// GODRAYS BEGIN
#include "/lib/bayer8.glsl"

#define GODRAYS // Efficient screen-space light shafts.

// How bright the shafts are, as a multiple of what the pack draws on its own.
//
// This is the only place the setting is applied. It scales the exposure that is
// premultiplied into godraysColor, which is the value the pass below adds to the
// frame, so one line covers everything the option is about.
//
// It is deliberately not applied where the mask is built - see
// /program/post/noisy_godrays.fsh. That pass has an arm for the water and an arm
// for the air, and a factor multiplied into both of them is a factor that has to
// be kept in step in two places. Here there is one.
//
// 1.0 is what the pack has always drawn, exactly: the multiply is the last one
// in the chain, so at 1.0 all it does is multiply by one.
//
// 0.0 makes the exposure exactly zero, and the final pass then adds nothing - it
// does not even run the blur, because that whole branch is behind
// godraysExposure > 0.0. That is a frame with no shafts in it, the same as with
// the option above turned off. It is not quite the same amount of work: turning
// that one off also skips the pass that builds the mask, while a strength of zero
// leaves that pass running and writing zeros into a buffer nothing then reads.
// One half-resolution full-screen pass is the price of being able to take the
// shafts down to nothing without giving up the rest of the feature.
#define GODRAYS_STRENGTH 2.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]

uniform sampler2D colortex1;
uniform vec4 screenLightVector;
uniform float godraysExposure;

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
float SmoothGodrays(vec2 texCoord, vec2 ScreenLightPos) {
	// Constants for the godrays
	const float NUM_SAMPLES = 8.0;
	const float DENSITY = 0.75;
	const float DECAY = pow(0.0001, 1.0 / NUM_SAMPLES);

	// Calculate vector from pixel to light source in screen space.
	vec2 deltaTexCoord = (texCoord - ScreenLightPos);
	// Divide by number of samples and scale by control factor.
	deltaTexCoord *= 1.0f / NUM_SAMPLES * DENSITY;
	// NEW: Use noise to allow us to get away with a singificantly reduced
	// iteration count.
	texCoord += deltaTexCoord * 1.5 * Bayer8(-gl_FragCoord.xy);
	// Store initial sample.
	float accumulated = texture(colortex1, texCoord).r;
	// Set up illumination decay factor.
	float illuminationDecay = 1.0f;
	// Evaluate summation from Equation 3 NUM_SAMPLES iterations.
	for (uint i = uint(0); i < uint(NUM_SAMPLES); i++) {
		// Step sample location along ray.
		texCoord -= deltaTexCoord;
		// Retrieve sample at new location.
		float depthSample = texture(colortex1, texCoord).r;
		// Apply sample attenuation scale/decay factors.
		depthSample *= illuminationDecay;
		// Accumulate depth samples.
		accumulated += depthSample;
		// Update exponential decay factor.
		illuminationDecay *= DECAY;
	}
	// Output final accumulated sample with a further scale control factor.
	float exposure = pow(1.0 - 4.0 * length(deltaTexCoord)
		* (1.0 - 0.3 * Bayer8(-gl_FragCoord.xy)), 8.0);
	return exposure * accumulated / NUM_SAMPLES;
} 
// GODRAYS END

// Note: if we do not define all values used in GLSL expressions, we get the
// following error:
//
// > error: Bad token in expression: ==
//
// Code reference:
//
// https://github.com/IrisShaders/glsl-preprocessor
// Commit: 595a0b379256f68408f68d83285683243cab3187
// /src/main/java/io/github/douira/glsl_preprocessor/Preprocessor.java#L1454
#define DEBUG_NONE 0
#define DEBUG_GODRAYS_NOISY 1
#define DEBUG_GODRAYS_SMOOTH 2
#define DEBUG_SKYLIGHT 3
#define DEBUG_DEPTH 4
#define DEBUG DEBUG_NONE // Debugging [DEBUG_NONE DEBUG_GODRAYS_NOISY DEBUG_GODRAYS_SMOOTH DEBUG_SKYLIGHT DEBUG_DEPTH]

#if DEBUG == DEBUG_GODRAYS_NOISY || DEBUG == DEBUG_GODRAYS_SMOOTH
	//uniform sampler2D colortex1;
#elif DEBUG == DEBUG_SKYLIGHT
	uniform sampler2D colortex5;
#else
	#define SCENE_TEXTURE_DECLARED
	uniform sampler2D colortex0;
#endif

#include "/environment/tonemap_settings.glsl"

uniform vec2 windowToScreen;

// The opaque depth of the world, for the depth view below. Declared here rather
// than pulled in with one of the includes because that view is the only thing in
// this pass that wants the opaque depth: the motion blur next door uses the one
// with translucents in it.
uniform sampler2D depthtex1;

// MotionBlur(...), the blur the camera's own movement draws across the frame.
// See that file for what it is and why the hand is left out of it.
//
// Included after the declarations above because the scene texture it samples is
// one of them: a shader has to see a uniform's declaration before the code that
// uses it, even when the two end up in the same file once the includes are done.
#include "/environment/effects/motion_blur.glsl"

layout(location = 0) out vec3 finalColor;

uniform vec3 godraysColor;

// The vignette: the corners of the frame darkened, the way a lens does it.
//
// Applied to the linear light, before the tonemap, rather than to the finished
// image. A vignette put on after the curve would darken the corners twice over
// - once by the falloff, and again by the tonemap's own shoulder, which is
// already compressing everything up there - and what that produces is corners
// that go flat rather than corners that go dark.
#define VIGNETTE_ON 1
#define VIGNETTE_OFF 0
#define VIGNETTE VIGNETTE_ON // [VIGNETTE_OFF VIGNETTE_ON]

// How much of its light a corner loses. The centre of the screen is never
// touched; this is the falloff at its very edge.
#define VIGNETTE_STRENGTH 0.35 // [0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5 0.6 0.75 1.0]

// Where the falloff starts and where it reaches full strength, measured as a
// squared distance from the centre of the screen: 0 at the centre, 1 at the
// midpoint of each edge, 2 in the corners.
#define VIGNETTE_START 0.35 // [0.0 0.1 0.2 0.3 0.35 0.4 0.5 0.6 0.75 0.9 1.0]
#define VIGNETTE_END 1.6 // [0.8 1.0 1.2 1.4 1.6 1.8 2.0]

void main() {
	// Determine the position of this fragment on the screen in screen
	// coordinates (0.0 to 1.0).
	vec2 screenCoord = gl_FragCoord.xy * windowToScreen;

	#if DEBUG == DEBUG_DEPTH
		// What the scene actually has in the opaque depth buffer here.
		//
		// This exists to answer one question that decides whether a screen-space
		// effect can reach terrain this pack does not draw itself - the level of
		// detail terrain of a mod like Voxy. Such an effect works from the depth
		// buffer; if that terrain never writes into this one, it is invisible to
		// the effect and no amount of tuning will reach it.
		//
		// White is a depth of exactly 1.0: nothing was drawn here at all, which is
		// the sky and also what terrain looks like if its depth goes somewhere
		// this pass cannot see. Green is anything that did write depth. The red
		// channel climbs as the value approaches 1.0, so terrain sitting right at
		// the end of the range - which is where distant terrain lives - shows as
		// yellow-green rather than as a green too dark to judge.
		float depthHere = texelFetch(depthtex1, ivec2(gl_FragCoord.xy), 0).r;

		finalColor = depthHere >= 1.0
			? vec3(1.0)
			: vec3(clamp((depthHere - 0.99) * 100.0, 0.0, 1.0), 1.0, 0.0);

		return;
	#endif

	#if DEBUG == DEBUG_GODRAYS_NOISY
		finalColor = vec3(texture(colortex1, screenCoord).r);
	#elif DEBUG == DEBUG_GODRAYS_SMOOTH
		if (godraysExposure > 0.0) {
			float godrays = SmoothGodrays(screenCoord, screenLightVector.xy);
			finalColor = godraysColor * godrays;
		} else {
			finalColor = vec3(0.0);
		}
	#elif DEBUG == DEBUG_SKYLIGHT
		finalColor = vec3(texture(colortex5, screenCoord).r);
	#else
		vec3 color = texture(colortex0, screenCoord).rgb;

		// Blurred before the godrays are added and before the tonemap, so the
		// blur mixes linear light rather than the tonemapped image, and so the
		// shafts of light stay crisp while the world they shine through does not.
		#ifdef MOTION_BLUR
			color = MotionBlur(screenCoord);
		#endif

		#ifdef GODRAYS
		if (godraysExposure > 0.0) {
			float godrays = SmoothGodrays(screenCoord, screenLightVector.xy);

			// Note: godraysExposure is premultiplied into godraysColor
			color += godraysColor * godrays;
		}
		#endif

		#if VIGNETTE == VIGNETTE_ON
			// Squared distance from the centre of the screen, in the -1..1 space
			// the screen's edges are 1 away in: 0 at the centre, 1 at the middle
			// of an edge, 2 in a corner.
			vec2 vignetteOffset = screenCoord * 2.0 - 1.0;

			color *= 1.0 - VIGNETTE_STRENGTH * smoothstep(
				VIGNETTE_START,
				VIGNETTE_END,
				dot(vignetteOffset, vignetteOffset));
		#endif

		#if TONEMAP == TONEMAP_UNCHARTED2
			vec3 tonemapped = Uncharted2Tonemap(color);
		#else
			vec3 tonemapped = UchimuraTonemap(color);
		#endif

		finalColor = LinearToSrgb(tonemapped);
	#endif
}
