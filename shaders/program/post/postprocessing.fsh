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

// The bloom's options, and its weights for the two levels the blur produces.
//
// Included here as well as in the four passes that build the blur, for two
// reasons: this is the pass that adds the result to the frame, and this is the
// one program that always runs, so the options are registered even when the
// bloom is off and its passes are skipped.
#include "/lib/bloom.glsl"

// The two levels of the bloom, as composite7 and composite10 left them.
//
// Declared unconditionally rather than behind the option, because a uniform
// that the preprocessor removes is a uniform nothing reads, and a buffer
// nothing reads is a buffer the loader has no reason to allocate.
uniform sampler2D colortex12;
uniform sampler2D colortex13;

// GODRAYS BEGIN

// The shafts, as the volumetric fog pass left them: the light the medium
// scattered towards the eye, at half resolution.
//
// This used to be a mask that the final pass blurred towards the sun's position
// on screen, and it is now built by a march through the air instead - see
// /program/post/volumetric_fog.fsh, and PBR_PORTING.md 169 for why. What it
// carries changed with it: a colour rather than a single channel, because a
// blur towards a point on the screen can only ever produce a brightness, while
// light actually scattered inside a volume has the colour of the light that
// scattered.
//
// The screen-space fades went with the technique that needed them, and that is
// the one thing worth knowing when reading shaders.properties: godraysColor is
// still built there, and godraysViewAngleFade and godraysOffscreenFade are
// still computed there, but the value the pass reads is the un-faded
// fogSunColor. A shaft whose sun has left the screen is the case the volumetric
// version exists for and the one the old version could not draw.
uniform sampler2D colortex1;

// Whether to draw the shafts and the medium that carries them.
//
// The name is the one the screen-space version used, kept on purpose: the
// quality profiles in shaders.properties, the menu and both lang files all
// reference it, and every one of them still means the same thing by it -
// whether this pack draws volumetric light. What changed is how it is drawn.
#define GODRAYS

// How bright the shafts are.
//
// Applied in shaders.properties, where the light's colour and the exposure are
// built: GODRAYS_STRENGTH multiplies into godraysColor there, and the pass
// reads that with the screen-space fades taken back out. One place applies it,
// which is what makes 1.0 harmless - at 1.0 the extra term multiplies by one.
//
// 0.0 zeroes the exposure, and therefore godraysColor and fogSunColor, so the
// pass adds nothing. It does not skip the march: the pass that builds the
// buffer still runs and writes zeros into it. One half-resolution full-screen
// pass is the price of being able to take the shafts down to nothing without
// turning the medium off with them.
#define GODRAYS_STRENGTH 2.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]

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
		// The scattered light as the pass wrote it, at the buffer's own
		// resolution: what the march left between its steps shows up here as
		// banding, which is what the dither and the step count are for.
		#ifdef VOLUMETRIC_FOG_FULL_RES
			finalColor = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0).rgb;
		#else
			finalColor = texelFetch(colortex1, ivec2(gl_FragCoord.xy * 0.25), 0).rgb;
		#endif
	#elif DEBUG == DEBUG_GODRAYS_SMOOTH
		// And the same buffer sampled the way the picture samples it, which is
		// what the frame actually receives.
		finalColor = texture(colortex1, screenCoord).rgb;
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
			// The light the march collected, added on top of the frame.
			//
			// Added rather than mixed, and with no transmittance term, because
			// the fading of the distance is the pack's own fog and it has
			// already been applied per fragment. See the note at the top of
			// /program/post/volumetric_fog.fsh.
			color += texture(colortex1, screenCoord).rgb;
		#endif

		#ifdef BLOOM
			// Both levels of the blur, at their own weights: the
			// half-resolution one is the tight core of the halo, and the
			// quarter-resolution one, which is blurred twice, is the part that
			// spreads. See lib/bloom.glsl for why there are two.
			//
			// Added before the vignette rather than after it, so that the
			// corners darken the glow along with everything else. That is what
			// a lens does: the light that scattered inside the glass on its way
			// to a corner is dimmed by the same falloff as the light that went
			// straight there.
			vec3 bloom = textureLod(colortex12, screenCoord, 0.0).rgb * BLOOM_TIGHT_WEIGHT
				+ textureLod(colortex13, screenCoord, 0.0).rgb * BLOOM_WIDE_WEIGHT;

			color += bloom * BLOOM_STRENGTH;
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
