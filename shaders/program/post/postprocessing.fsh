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

// The fog is marched at a quarter of the frame's resolution, and the four taps
// below are what it takes to put a quarter-resolution buffer back on the frame
// without the blur that a plain bilinear read puts across a silhouette. See
// UpsampleVolumetrics.
#ifdef GODRAYS

// The depth the fog was marched from, and the matrix that turns a depth into the
// distance that march used. Declared behind the pack's duplicate guard, and here
// rather than beside the other uniforms because this is the only place in this
// pass that wants any of it - the motion blur next door declares the same matrix
// under its own option.
#if !defined(DEPTH_TEXTURE_DECLARED)
	#define DEPTH_TEXTURE_DECLARED
	uniform sampler2D depthtex0;
#endif

#if !defined(PROJECTION_INVERSE_DECLARED)
	#define PROJECTION_INVERSE_DECLARED
	uniform mat4 gbufferProjectionInverse;
#endif

uniform float viewWidth;
uniform float viewHeight;

// How far apart in distance two points have to be before the fog stops sharing
// between them, in blocks.
//
// This is the whole edge of the upscale. Each of the four taps is weighted by how
// close its own distance is to the fragment's, so a tap that belongs to a
// surface in front of or behind this one counts for less - and at a silhouette
// that is what stops the fog on the far side from being smeared on to the near
// one. 1.0 block is a compromise: much smaller and a flat wall whose four taps
// differ only by the depth buffer's own quantisation starts picking favourites
// between them, which brings the quarter-resolution grid back as a visible
// pattern; much larger and a silhouette against something several blocks behind
// it is blurred again, which is the artifact this exists to remove.
const float FOG_UPSAMPLE_DEPTH_SCALE = 1.0;

// How far the surface at one pixel is from the eye, in blocks, from the depth
// the fog pass marched to and the matrix it marched with.
//
// ⚠️ One copy, because both numbers the weights compare have to be the same
// quantity: the fog pass linearises the depth it stopped at exactly this way
// (see the top of /program/post/volumetric_fog.fsh), and a distance worked out
// any other way would be a different measurement of the same pixel.
float FogViewDistance(ivec2 pixel, float depth) {
	vec2 ndc = vec2(pixel) * 2.0 / vec2(viewWidth, viewHeight) - 1.0;

	vec4 viewPosH = gbufferProjectionInverse * vec4(ndc, depth * 2.0 - 1.0, 1.0);

	return length(viewPosH.xyz / viewPosH.w);
}

// The scattered light of the fog, read at this fragment rather than wherever a
// bilinear read of the quarter-resolution buffer happened to land.
//
// A plain texture() of that buffer takes the four texels around the fragment and
// mixes them by area alone, and one of those texels can easily straddle a
// silhouette: a quarter-resolution texel is four pixels across, so its centre can
// sit on the wall while the rest of it covers the sky behind. Bilinear then mixes
// the fog of the sky into the wall's pixels, and smears the mix over the few
// pixels between, which is the blurry edge this replaces.
//
// What separates the two surfaces is distance, so every tap is weighted by how
// far its own distance is from this fragment's - the same joint-bilateral idea
// the TAA resolve uses on colour. Both rgb - the light the medium scattered - and
// a - the absorbance through it - are mixed with the same weights.
//
// Three things worth knowing before reading it:
//
//  * The fog pass computes its own screen coordinate as gl_FragCoord.xy divided
//    by the frame size times 0.25, and reads its depth with an ordinary
//    normalized texture() of that coordinate. A quarter-resolution texel index i
//    therefore has its centre at (i + 0.5) / (view * 0.25), which is
//    (4i + 2) / view: the centre of full-resolution texel 4i + 2 exactly. So
//    fetching depthtex0 at ivec2(4i + 2) gives the very depth that texel's fog
//    was built from - no reconstruction, and no filter between the two.
//  * Each tap is fetched at its texel's own centre rather than left to the
//    sampler, so that what is mixed is exactly what was fetched: a texture() at
//    a coordinate inside a texel returns that texel's value, and the offsets
//    below are all half-texel ones.
//  * Mixing absorbance linearly is an approximation. Two layers do not add their
//    absorbances, they multiply their transmittances - but this blends four taps
//    that in a flat region hold the same value, where a linear and a
//    transmittance mix agree, and it is the flat end that has to stay exact.
//
// `depth` is this fragment's own depth from depthtex0, raw rather than
// linearised: this is the one place that conversion is written.
vec4 UpsampleVolumetrics(vec2 screenCoord, float depth) {
	#ifdef VOLUMETRIC_FOG_FULL_RES
		// Nothing to put back on the frame grid: with the fog marched at the
		// frame's own resolution one texel is one pixel, and the fetch the debug
		// views above make is already this fragment's own value.
		return texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0);
	#else
		// The quarter-resolution grid, in texels of it.
		vec2 fogTexel = screenCoord * vec2(viewWidth, viewHeight) * 0.25 - 0.5;

		ivec2 fogSize = ivec2(vec2(viewWidth, viewHeight) * 0.25);

		// ⚠️ Clamped into the buffer before anything is fetched from it (batch 530).
		// Near the screen edge floor() can put the base outside the fog buffer, and a
		// texelFetch outside a texture is undefined - which is how a garbage value, or a
		// NaN, reaches the frame as a black speck at a silhouette.
		ivec2 base = clamp(ivec2(floor(fogTexel)), ivec2(0),
			max(fogSize - ivec2(1), ivec2(0)));
		vec2 frac = fogTexel - vec2(base);

		// The full-resolution pixel that stands at the centre of each of the four
		// texels around this fragment - the point the fog in that texel was built
		// from, as the note above works out.
		ivec2 fullTexel = base * 4 + ivec2(2);

		float fragmentDistance = FogViewDistance(ivec2(gl_FragCoord.xy), depth);

		vec4 sum = vec4(0.0);
		float weightSum = 0.0;

		for (int i = 0; i < 2; i++) {
			for (int j = 0; j < 2; j++) {
				// The bilinear weight this tap would get from the sampler, and then
				// the depth weight that says whether the fog here belongs to this
				// fragment's surface at all. ⚠️ The second is not optional: the fog
				// buffer's own alpha is absorbance and not an edge signal, since it is
				// a flat 1.0 on every path but the Nether's plumes.
				float bilinear = (i == 0 ? 1.0 - frac.x : frac.x)
					* (j == 0 ? 1.0 - frac.y : frac.y);

				// ⚠️ Each tap's distance is taken through the tap's OWN pixel, not
				// through this fragment's: the ray that was marched to build this
				// texel's fog is the one through the centre pixel, and measuring the
				// distance along the fragment's ray instead tilts it and makes two of
				// the four taps disagree with a surface they are standing on.
				ivec2 tapPixel = fullTexel + ivec2(i, j) * 4;
				float tapDepth = texelFetch(depthtex0, tapPixel, 0).r;

				float tapDistance = FogViewDistance(tapPixel, tapDepth);

				// ⚠️ The difference is guarded rather than trusted (batch 530). A tap
				// whose depth is the far plane linearises to a distance that can come
				// back infinite, and Inf - Inf is a NaN - which makes every comparison
				// false, so the tap silently takes no weight and the whole weighted sum
				// can end up empty. Anything that is not a finite, non-negative distance
				// gets no weight here instead; a NaN fails both tests and lands in the
				// same place. The >= matters: equal depths are the flat case this has to
				// keep exact, and they are a gap of exactly zero.
				float depthGap = abs(tapDistance - fragmentDistance);

				float weight = bilinear
					* (depthGap >= 0.0 && depthGap < 1.0e5
						? exp(-depthGap / FOG_UPSAMPLE_DEPTH_SCALE) : 0.0);

				sum += texelFetch(colortex1, base + ivec2(i, j), 0) * weight;
				weightSum += weight;
			}
		}

		// Normalised, so the result is the weighted average of the taps rather than
		// their sum. With four equal depths every weight is the same and this reduces
		// to the bilinear read it replaces, exactly - which is what the flat majority
		// of the frame has to be.
		//
		// ⚠️ And when every weight has been refused - all four depths unreadable, or a
		// sum that came out zero or not a number - the fallback is the plain bilinear
		// read and NOT zero (batch 530). Zero is a hole in the fog, and a hole at a
		// silhouette is exactly the black speck this pass was reported for; the
		// bilinear read is what the pass did before the depth weighting existed, so the
		// worst case is now batch 525's behaviour rather than a hole. The comparison is
		// also the NaN guard: every comparison against a NaN is false, so a poisoned
		// sum takes this branch.
		return weightSum > 0.0 ? sum / weightSum : texture(colortex1, screenCoord);
	#endif
}

#endif

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
#define DEBUG_GODRAYS_UPSAMPLED 3
#define DEBUG_SKYLIGHT 4
#define DEBUG_DEPTH 5
#define DEBUG_PLUME_DENSITY 6
#define DEBUG DEBUG_NONE // Debugging [DEBUG_NONE DEBUG_GODRAYS_NOISY DEBUG_GODRAYS_SMOOTH DEBUG_GODRAYS_UPSAMPLED DEBUG_SKYLIGHT DEBUG_DEPTH DEBUG_PLUME_DENSITY]

#if DEBUG == DEBUG_GODRAYS_UPSAMPLED
	// The depth-weighted view below reads more than the buffer: it takes its own
	// distance and the distance of each texel around it as well, so it needs the
	// depth texture and the matrix that turns a depth into a distance. Declared
	// under the same duplicate guards the fog's own upsample uses, since the
	// motion blur next door may already have declared them.
	#if !defined(SCENE_TEXTURE_DECLARED)
		#define SCENE_TEXTURE_DECLARED
		uniform sampler2D colortex0;
	#endif

	#if !defined(DEPTH_TEXTURE_DECLARED)
		#define DEPTH_TEXTURE_DECLARED
		uniform sampler2D depthtex0;
	#endif

	#if !defined(PROJECTION_INVERSE_DECLARED)
		#define PROJECTION_INVERSE_DECLARED
		uniform mat4 gbufferProjectionInverse;
	#endif

	uniform float viewWidth;
	uniform float viewHeight;
#elif DEBUG == DEBUG_GODRAYS_NOISY || DEBUG == DEBUG_GODRAYS_SMOOTH
	// colortex1 needs no declaration here: it is declared above, unconditionally.
#elif DEBUG == DEBUG_SKYLIGHT
	uniform sampler2D colortex5;
#elif DEBUG == DEBUG_PLUME_DENSITY
	// The density view below asks the Nether's own field for itself, so it needs
	// the file that owns that field - and nothing else. The world position it asks
	// about is reconstructed from the depth texture and the projection inverse the
	// own upsample above already declared, under its duplicate guards.
	//
	// ⚠️ Included here rather than at the top of the file because this view is the
	// only thing in this pass that reads any of it, and DEBUG is a compile-time
	// constant: on every other setting this program's source is exactly what it
	// was before the view existed. What arrives with it is the whole of the
	// medium's settings file, so this is the one debug view whose cost is a
	// recompile of the option set rather than a few instructions.
	#include "/environment/effects/volumetric_fog.glsl"

	// ⚠️ cameraPosition and gbufferModelViewInverse are declared by motion_blur.glsl,
	// which this pass includes below, but only under that file's own MOTION_BLUR
	// option - and two declarations of one uniform in one program is an error on
	// the driver, which is what the note in lib/taa.glsl and BATCH_LOG.md 176 are
	// about. So they are declared here when the option is off and left to that file
	// when it is on: the same shape as the duplicate guards on the scene texture
	// and the depth texture above, with the option standing in for the guard macro.
	#ifdef MOTION_BLUR
		// Declared by motion_blur.glsl, below.
	#else
		uniform vec3 cameraPosition;
		uniform mat4 gbufferModelViewInverse;
	#endif
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
		#ifdef VOLUMETRIC_FOG_FULL_RES
			finalColor = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0).rgb;
		#else
			finalColor = texelFetch(colortex1, ivec2(gl_FragCoord.xy * 0.25), 0).rgb;
		#endif
	#elif DEBUG == DEBUG_GODRAYS_SMOOTH
		// And the same buffer sampled the way the picture samples it, which is
		// what the frame actually receives.
		finalColor = texture(colortex1, screenCoord).rgb;
	#elif DEBUG == DEBUG_GODRAYS_UPSAMPLED
		#ifdef GODRAYS
			// What the frame receives once the upscale has had its say: the same
			// four taps the picture gets, weighted by distance rather than by
			// area alone. Put beside the two above, the difference between them
			// at a silhouette is the whole of what this does.
			float ownDepth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;

			finalColor = UpsampleVolumetrics(screenCoord, ownDepth).rgb;
		#endif
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

			vec3 plumeWorldPos = cameraPosition
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

		#ifdef GODRAYS
			// The light the march collected, and the fraction of the frame that
			// reaches the eye through the medium it was collected in.
			//
			// ⚠️ Multiplied before it is added, rather than added on its own: the
			// fourth channel of that buffer carries what the march's medium let
			// through, and it is 1.0 on every path but the Nether's plumes - so
			// everywhere else this is still the addition it has always been, and
			// the fading of the distance remains the pack's own fog, applied per
			// fragment. See the note at the top of
			// /program/post/volumetric_fog.fsh.
			//
			// Read at this fragment rather than bilinearly off the fog buffer,
			// which mixes the fog of whatever is behind a silhouette into the
			// pixels in front of it. See UpsampleVolumetrics for what replaces
			// that and why: the weights compare the fog pass's own depth against
			// this pixel's, linearised the same way at both ends.
			float ownDepth = texelFetch(depthtex0, ivec2(gl_FragCoord.xy), 0).r;

			vec4 volumetrics = UpsampleVolumetrics(screenCoord, ownDepth);

			color = color * volumetrics.a + volumetrics.rgb;
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
