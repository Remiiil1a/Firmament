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

// The medium's settings, for the DEBUG_PLUME_DENSITY view below.
//
// ⚠️ Included HERE, unconditionally, rather than only inside the branch that
// reaches for it - and the difference cost a build (batch 577):
//
//     final.fsh: 0(174) : error C1503: undefined variable "BLOOMY_FOG"
//
// That batch put a multiplier in the bloom block whose #define lived in this
// file, while this program included it only under the debug view, so every
// ordinary setting compiled a name with nothing behind it. The multiplier is gone
// now, but the arrangement is kept: a program may not depend on a name arriving
// from a branch it compiles away, and the debug view below is such a branch.
//
// ⚠️ And the file is NOT included again where the view is. Two includes of a
// file with no guard of its own would be two copies of every declaration in it.
#include "/environment/effects/volumetric_fog.glsl"

// The two levels of the bloom, as composite7 and composite10 left them.
//
// Declared unconditionally rather than behind the option, because a uniform
// that the preprocessor removes is a uniform nothing reads, and a buffer
// nothing reads is a buffer the loader has no reason to allocate.
uniform sampler2D colortex12;
uniform sampler2D colortex13;

// VOLUMETRIC FOG BEGIN

// The shafts, as the volumetric fog pass left them: the light the medium
// scattered towards the eye, at half resolution.
//
// This used to be a mask that the final pass blurred towards the sun's position
// on screen, and it is now built by a march through the air instead - see
// /program/post/volumetric_fog.fsh, and BATCH_LOG.md 169 for why. What it
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

// Whether to draw the medium the light travels through, and the shafts it
// scatters towards the eye.
//
// One switch for both, because the pass it turns on is one march through the
// fog: the shafts are that march's scattering, so there is nothing to draw
// them from with the medium off. The name follows the medium the pass is about.
#define VOLUMETRIC_FOG

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
// ⚠️ Declared here as well as in the medium's own settings file, and the two must
// carry the same value and the same range or the option means two things at once.
// The long note on it - including why its default is 5.0 - is at the declaration in
// /environment/effects/volumetric_fog.glsl.
#define GODRAYS_STRENGTH 5.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0 5.0 6.0 8.0 10.0]

// The fog is marched at a quarter of the frame's resolution by default, and the
// depth-gated filter that puts it back on the frame lives in composite1.fsh - see
// it there, and see the note below for why this pass no longer has a copy.
#ifdef VOLUMETRIC_FOG

// The view size, which the first of the fog debug views asks the buffer for its
// own grid with - see the declaration block above, which is where it is guarded.
// colortex1 itself needs no declaration here: it is declared unconditionally with
// the other buffers, and the block this replaces used to declare the depth texture
// and the projection inverse as well, which nothing below the line needs any more.
#if !defined(VIEW_SIZE_DECLARED)
	#define VIEW_SIZE_DECLARED
	uniform float viewWidth;
	uniform float viewHeight;
#endif

// ⚠️ The depth texture, the projection inverse and the two functions that used to
// sit here are gone with the upscale (batch 581). This block used to be where the
// filter was declared and defined, and it is worth recording what replacing it
// with one buffer declaration means: the only thing left in this pass that touches
// the fog at all is the three DEBUG_GODRAYS_* views, and all three of them do a
// plain texture() of the buffer. Nothing here needs to know what is behind a
// silhouette any more, because nothing here draws the fog.

// ⚠️ The fog upscale used to be defined between this line and the #endif below -
// three constants and two functions, some four hundred lines of it. It is in
// composite1.fsh now, and the reason is the whole of batch 581: the fog is
// composited in front of the temporal resolve, so that is the pass where the filter
// is needed for the picture.
//
// ⚠️ It is NOT kept here as a second copy, and it is NOT in a file of its own. The
// second copy is refused because two copies of a filter are two places for the next
// fix to land in one of, which this work has already paid for twice; the file is
// refused because the pack holds one invariant above tidiness - no new file goes
// into `shaders/`.

#endif

// VOLUMETRIC FOG END

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
#define DEBUG_GODRAYS_UPSAMPLED 3
#define DEBUG_SKYLIGHT 4
#define DEBUG_DEPTH 5
#define DEBUG_PLUME_DENSITY 6
#define DEBUG DEBUG_NONE // Debugging [DEBUG_NONE DEBUG_GODRAYS_NOISY DEBUG_GODRAYS_SMOOTH DEBUG_GODRAYS_UPSAMPLED DEBUG_SKYLIGHT DEBUG_DEPTH DEBUG_PLUME_DENSITY]

#if DEBUG == DEBUG_GODRAYS_NOISY || DEBUG == DEBUG_GODRAYS_SMOOTH || DEBUG == DEBUG_GODRAYS_UPSAMPLED
	// ⚠️ The three views that read the fog buffer. Until batch 581 this was two
	// branches, because the third of them showed the depth-gated upscale's output
	// and that was the only thing in this pass that needed the depth texture, the
	// projection inverse and the frame's size. The upscale is in composite1.fsh now,
	// so all three do the same plain read of the same buffer and need the same one
	// declaration.
	//
	// colortex1 needs no declaration here: it is declared above, unconditionally.
	//
	// ⚠️ The frame's own size does need one, since batch 534 made the first of these
	// views ask the buffer for its own grid rather than trusting an #ifdef to say
	// what that grid is. With volumetric light on it is already there, and with it
	// off this view still has to compile - a view that fails to compile because the
	// effect it diagnoses has been switched off would be worse than useless, and it
	// is the first thing a reader tries.
	#if !defined(VIEW_SIZE_DECLARED)
		#define VIEW_SIZE_DECLARED
		uniform float viewWidth;
		uniform float viewHeight;
	#endif
#elif DEBUG == DEBUG_SKYLIGHT
	uniform sampler2D colortex5;
#elif DEBUG == DEBUG_PLUME_DENSITY
	// The density view below asks the Nether's own field for itself, and the file
	// that owns that field - /environment/effects/volumetric_fog.glsl - is now
	// included unconditionally at the top of this program, for the BLOOMY_FOG
	// multiplier the bloom needs. It is therefore already in scope here.
	//
	// ⚠️ It used to be included at this point instead, and that is what broke a
	// build: everything defined in it was visible to this view and to nothing else,
	// so every ordinary setting compiled with BLOOMY_FOG as an undefined name. See
	// the note on the include at the top.
	//
	// ⚠️ And it is NOT included again here. Two includes of one file would be two
	// copies of every declaration in it, which is a redefinition rather than a
	// waste - the file has no include guard of its own, and giving it one would be
	// a change to a file four other programs take.
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


	// ⚠️ cameraPosition and gbufferModelViewInverse are declared by motion_blur.glsl,
	// which this pass includes above, but only under that file's own MOTION_BLUR
	// option - and two declarations of one uniform in one program is an error on
	// the driver, which is what the note in lib/taa.glsl and BATCH_LOG.md 176 are
	// about. So they are declared here when the option is off and left to that file
	// when it is on: the same shape as the duplicate guards on the scene texture
	// and the depth texture above, with the option standing in for the guard macro.
	#ifdef MOTION_BLUR
		// Declared by motion_blur.glsl, above.
	#else
		uniform vec3 cameraPosition;
		uniform mat4 gbufferModelViewInverse;
	#endif
layout(location = 0) out vec3 finalColor;

uniform vec3 godraysColor;

// The vignette: the corners of the frame darkened, the way a lens does it.
//
// Applied to the linear light, before the tonemap, rather than to the finished
// image. A vignette put on after the curve would darken the corners twice over
// - once by the falloff, and again by the tonemap's own shoulder, which is
// already compressing everything up there - and what that produces is corners
// that go flat rather than corners that go dark.
#define VIGNETTE

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
		// ⚠️ The buffer's place on the frame is asked of the buffer, exactly as the
		// helper above asks it (batch 534), and no longer decided by an #ifdef on
		// VOLUMETRIC_FOG_FULL_RES with a hand-written 0.25 in the other branch: those
		// were two statements of one fact, and in the configuration where they
		// disagreed - the properties side sizing this buffer to the frame while the
		// macro did not take - this view read the wrong grid and smeared the
		// quarter-resolution fog over a full-resolution frame. Whatever size the
		// buffer is, this is its own texel grid and it cannot disagree with it.
		//
		// ⚠️ The mapping is written as integer division rather than as a scale factor,
		// and that is its one difference from the helper: every pixel of one texel's
		// footprint has to land on the SAME texel, and (pixel * fogTexels) / view is
		// exact in integers where a float quotient can come out a hair under the
		// integer it should be. The clamp is the helper's, for the helper's reason: a
		// fetch outside a texture is undefined rather than clamped, and the last column
		// of the frame is one pixel from the buffer's own edge.
		ivec2 fogTexels = textureSize(colortex1, 0);

		finalColor = texelFetch(colortex1, clamp(
			ivec2(gl_FragCoord.xy) * fogTexels / ivec2(viewWidth, viewHeight),
			ivec2(0), fogTexels - 1), 0).rgb;
	#elif DEBUG == DEBUG_GODRAYS_SMOOTH
		// And the same buffer sampled the way the picture samples it, which is
		// what the frame actually receives.
		finalColor = texture(colortex1, screenCoord).rgb;
	#elif DEBUG == DEBUG_GODRAYS_UPSAMPLED
		// ⚠️ This view used to show the depth-gated upscale’s own output. That
		// filter moved to composite1.fsh with the fog it exists for (batch 581), and
		// it is deliberately NOT kept here as a second copy — a second copy of a
		// filter is two places for the next fix to land in one of. So this view now
		// does the read its neighbour above does, and the two are identical.
		//
		// ⚠️ Kept rather than deleted because the debug view numbers are baked
		// into save files: removing one renumbers every view after it, and a player
		// who had 7 selected would silently be shown something else. The cost is one
		// duplicated view; the cost of deleting it would be a renumbering.
		//
		// What the upscale does is visible in the frame now, which is a better place
		// to judge it: turn the medium on and look at a silhouette.
		finalColor = texture(colortex1, screenCoord).rgb;
	#elif DEBUG == DEBUG_SKYLIGHT
		finalColor = vec3(texture(colortex5, screenCoord).r);
	#elif DEBUG == DEBUG_PLUME_DENSITY
		// The Nether's plume density itself: the field the columns are made of,
		// with no light on it and nothing else in the frame. It is the one question
		// the picture cannot answer - whether the columns are not there at all, or
		// are there and not visible - and it is what batch 527 was diagnosed with.
		//
		// ⚠️ Read at the world position this pixel shows, so the field is seen where
		// the picture sees it and nowhere else, and through the same bubble around
		// the eye that the march holds the smoke off with - which is why the first
		// blocks in front of the camera come out black in the Nether. A pixel with
		// nothing drawn in it (a depth of exactly 1.0) is left black as well, which
		// reads the same as no smoke; in the Nether the roof is bedrock and there
		// is no such pixel, but a camera looking into the void would have one.
		//
		// ⚠️ Black is no smoke and the plume's own colour is a density of one, the
		// top of the range NetherPlumeDensity is held at - see
		// NETHER_PLUME_CONTRAST for what holds it there. The ramp is linear, and it
		// is written without the tonemap like every other view in this pass, so it
		// is a measurement of the density rather than a picture of the plumes: a
		// column that is visible here and not in the frame is a shading problem,
		// and a column that is not here at all is a density problem.
		//
		// ⚠️ The colour it draws that measurement in is the plume's own base colour,
		// and the core gradient does not move it: that option scales the emission
		// away from this colour towards a paler edge and a deeper core, which is a
		// thing done to the light after the field is read. A column that is bright
		// here and dim in the frame can therefore be the gradient as easily as the
		// brightness - set the gradient to 0.0 to take the ramp out of the question
		// before blaming anything else.
		//
		// ⚠️ The whole of what this reads is conditional on the plumes being on, and
		// the option that switches them off is the one that removes the function
		// below from the same file this view includes - so the branch is not
		// decoration. With the plumes off there is no field to look at, and black is
		// the honest answer; a view that fails to compile because the effect it is
		// there to diagnose has been switched off would be worse than useless, and
		// it is the first thing a reader would try.
		#ifdef NETHER_PLUMES
			float plumeDepth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;

			vec4 plumeViewH = gbufferProjectionInverse
				* vec4(screenCoord * 2.0 - 1.0, plumeDepth * 2.0 - 1.0, 1.0);
			vec3 plumeViewPos = plumeViewH.xyz / plumeViewH.w;

			// The bubble, worked out the way the march works it out: what this reads
			// is then what the march reads at this surface rather than the raw field.
			float plumeClear = clamp(
				length(plumeViewPos) / NETHER_PLUME_CLEAR, 0.0, 1.0);

			// ⚠️ The 3x3 needs the inverse's fourth column beside it (batch 598):
			// `plumeViewPos` is measured from the eye the world was DRAWN from, and
			// view bobbing puts that eye away from `cameraPosition`, so without this
			// term this view reads the field at a point displaced by the bob - it
			// would jump with the player's step while the plume it is debugging does
			// not. The march places its samples the same way; see the note there.
			vec3 plumeWorldPos = cameraPosition + gbufferModelViewInverse[3].xyz
				+ mat3(gbufferModelViewInverse) * plumeViewPos;

			finalColor = plumeDepth >= 1.0
				? vec3(0.0)
				: NETHER_PLUME_COLOR * clamp(
					NetherPlumeDensity(plumeWorldPos, plumeClear), 0.0, 1.0);
		#else
			finalColor = vec3(0.0);
		#endif
	#else
		vec3 color = texture(colortex0, screenCoord).rgb;

		// Blurred before the godrays are added and before the tonemap, so the
		// blur mixes linear light rather than the tonemapped image, and so the
		// shafts of light stay crisp while the world they shine through does not.
		#ifdef MOTION_BLUR
			color = MotionBlur(screenCoord);
		#endif

		#ifdef VOLUMETRIC_FOG
			// ⚠️ THE FOG IS NOT ADDED HERE ANY MORE (batch 581). It is composited in
			// composite1, in front of the temporal resolve, which is the pass whose
			// history and motion vectors can average it - this pass has neither, so
			// adding it here meant the fog had never been resolved by anything but
			// its own quarter-resolution denoise.
			//
			// What arrives in colortex0 is therefore the frame WITH the fog already
			// in it, and the multiplication by the medium's transmittance happened
			// there too. Nothing below needs to know: the bloom, the vignette and the
			// tonemap all read one picture, which is the point of the move. See the
			// note in composite1.fsh for the placement, and its UpsampleVolumetrics
			// for the filter, which this pass no longer has a copy of.
			//
			// ⚠️ What this pass still does with the fog is SHOW it: the
			// DEBUG_GODRAYS_* views above read the buffer directly, and that is why
			// the medium's settings file is still included.
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

		#ifdef VIGNETTE
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
