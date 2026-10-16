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
#define GODRAYS_STRENGTH 2.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]

// The fog is marched at a quarter of the frame's resolution by default, and the
// four taps below are what it takes to put a quarter-resolution buffer back on
// the frame without the blur that a plain bilinear read puts across a
// silhouette. ⚠️ Which buffer this reads - that quarter or the frame's own - is
// decided by the buffer's queried size at the top of UpsampleVolumetrics rather
// than by the option that sized it (batch 533), and the writer asks the same
// question of the same buffer. See that function.
#ifdef VOLUMETRIC_FOG

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

// The view size, which the distance below and the four taps of the upscale are
// worked out from. Guarded like the two declarations above it: the debug view
// of this same upsample declares the pair for itself, and so does the motion
// blur next door.
#if !defined(VIEW_SIZE_DECLARED)
	#define VIEW_SIZE_DECLARED
	uniform float viewWidth;
	uniform float viewHeight;
#endif

// How far apart in distance two points have to be before the fog stops sharing
// between them, in blocks.
//
// This is the whole edge of the upscale. Each tap's own distance is compared with
// the fragment's, and a tap whose surface is past this far from this pixel's is
// dropped rather than down-weighted - see FOG_UPSAMPLE_DEPTH_GATE below for why
// "dropped" and not "weighted by less", which is the difference that matters and
// is where this file's own history is worth reading.

// How far a tap's surface may be from this pixel's before the tap is dropped
// outright, in blocks.
//
// ⚠️ This is the GATE, and it is the part of Bliss Shader's bilateral upsample that
// the first port of it left out (batch 579). The constant above is a multiplier: it
// makes a tap from the other side of a silhouette count for less, and less is not
// nothing. Bliss tests the depth and keeps the tap or discards it, and the
// difference is measurable exactly where it matters - across a 1 to 3 block gap,
// which is a kerb, a step, a fence rail, a leaf:
//
//     depth gap      smooth exp(-gap)      this gate
//        1 block          18% of the far surface got through     none
//        2 blocks          7.5%                                  none
//        3 blocks          2.9%                                  none
//
// ⚠️ 1.0 block, and it is ABSOLUTE rather than a fraction of the distance - the
// same choice the scale above makes, and for the same reason: a fence rail one
// block in front of a wall is one block in front of it at any distance a player
// stands at, and a threshold that grew with distance would keep the two blended
// together in the far field, which is where a soft edge is most visible.
//
// ⚠️ Its cost is the far field and it is a real one: a slope crossed by one fog
// texel changes depth by more than a block, so on distant terrain the gate rejects
// taps that are legitimately on the same surface. The taps on the pixel's own
// texel survive - their gap is zero by construction - so the result degrades to
// the plain read rather than to nothing, and the fallback below catches the case
// where even that fails.
const float FOG_UPSAMPLE_DEPTH_GATE = 1.0;

// ⚠️ The two bounds the depth weighting needs so that it can never produce a
// value that is not a number. Both are read by FogViewDistance and by the sum at
// the bottom of UpsampleVolumetrics. Neither is a knob.

// The largest distance a weight comparison is ever given, in blocks.
//
// A depth at the far plane has no distance to contribute. The unprojection of
// depth 1.0 is the far end of the projection's own depth range: Minecraft sets a
// finite far plane, so that point is finite - depth 1.0 is "a point on the far
// plane", BATCH_LOG.md 1061 - but the same arithmetic on a projection whose far
// plane is at infinity divides by a w that reaches zero and gives +Inf, and two
// of those subtracted from each other are NaN rather than zero: a NaN weight, a
// NaN sum, and a black speckle on the frame.
//
// So the far plane is given this number instead, deliberately far past anything
// that can be drawn: the far plane is the vanilla view distance in blocks, 512
// at the 32 chunks the game allows (BATCH_LOG.md 3361), and no surface in the
// frame is anywhere near ten thousand blocks away. Two distances that are both
// clamped were both at the far plane, and the weights of such a pair come out
// equal - which is the flat case this upscale has to reproduce exactly. It is
// also 3.4e34 times below the largest float, so nothing on the way through the
// weights, the sum or the normalisation can overflow.
const float FOG_UPSAMPLE_MAX_DISTANCE = 1.0e4;

// The smallest weight sum the normalisation at the bottom may divide by. Below
// it the plain bilinear read is the answer - what this pass did before the depth
// weighting existed, and what the smooth debug view below calls the way the
// picture samples it.
//
// ⚠️ THE GATE MAKES THIS MORE LIKELY TO BE REACHED, not less, and that is worth
// understanding before touching either number (batch 579). With a gate, a tap is
// either fully in or fully out, so the sum is a sum of Gaussian weights over
// whichever taps passed - and at a silhouette against a distant background it is
// entirely possible for none of them to pass. `tapOnThisSurface` is deliberately
// not an exact test of the pixel's own texel, so this is a real case rather than a
// theoretical one.
//
// What that means for the answer: the plain bilinear read, which is what this pass
// did before any of this existed. That is the right fallback rather than a
// compromise - a pixel whose every neighbour is another surface should show the
// fog of its own surface, and the bilinear read is the one that is weighted by
// area alone and does not need a neighbour to agree about depth.
//
// ⚠️ 1e-30 sits eight decades above the smallest normal float (1.18e-38), so a sum
// that passes it is never denormal and the division keeps its full precision. Any
// smaller a bound and a sum of a few genuine weights could divide into noise;
// any larger and a legitimate single distant tap would be thrown away in favour of
// the bilinear read.
const float FOG_UPSAMPLE_WEIGHT_EPSILON = 1.0e-30;

// How far the surface at one pixel is from the eye, in blocks, from the depth
// the fog pass marched to and the matrix it marched with.
//
// ⚠️ One copy, because both numbers the weights compare have to be the same
// quantity: the fog pass linearises the depth it stopped at exactly this way
// (see the top of /program/post/volumetric_fog.fsh), and a distance worked out
// any other way would be a different measurement of the same pixel.
//
// ⚠️ And one guarantee: what comes back is always a finite number, inside
// FOG_UPSAMPLE_MAX_DISTANCE, for any depth at all. Every weight is a difference
// of two of these, and a difference needs both sides to be numbers: Inf - Inf is
// NaN, and a NaN weight is a NaN sum and a black speckle on the frame. There are
// two ways a distance could stop being a number and both are closed here.
float FogViewDistance(ivec2 pixel, float depth) {
	// The far plane - and the sky, which is drawn with depth writing off and so
	// sits at exactly this depth - is not a place with a distance. This is the
	// same threshold the two debug views further down use to mean "nothing was
	// drawn here", and the one copy_and_fog.fsh uses for the same thing.
	//
	// ⚠️ Written inverted, `!(depth < 1.0)`, for the reason the NaN guard in
	// copy_and_fog.fsh gives: a NaN fails every comparison, so an inverted test
	// catches it and `depth >= 1.0` does not. A depth that is not a number is
	// exactly the input that must not reach a subtraction.
	if (!(depth < 1.0)) {
		return FOG_UPSAMPLE_MAX_DISTANCE;
	}

	// Everything below the near plane is pulled up to it: a depth outside 0..1
	// cannot come out of a depth buffer, but this clamp is what makes the matrix
	// product below finite for every input rather than only for the inputs the
	// game happens to produce.
	depth = max(depth, 0.0);

	vec2 ndc = vec2(pixel) * 2.0 / vec2(viewWidth, viewHeight) - 1.0;

	vec4 viewPosH = gbufferProjectionInverse * vec4(ndc, depth * 2.0 - 1.0, 1.0);

	float viewDistance = length(viewPosH.xyz / viewPosH.w);

	// ⚠️ A ceiling, because the division above is by a w that reaches zero at the
	// far end of the depth range: with a finite far plane the point is the far
	// plane's own and this never bites; with the far plane at infinity it is the
	// only thing between here and +Inf.
	//
	// ⚠️ And written as a comparison rather than as min(), because min() cannot
	// order a NaN - a NaN fails this test and takes the ceiling. That is what
	// makes the guarantee above hold for every input rather than for the ones the
	// game produces.
	return viewDistance < FOG_UPSAMPLE_MAX_DISTANCE
		? viewDistance : FOG_UPSAMPLE_MAX_DISTANCE;
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
//    by the size it queries of this same buffer (batch 533 - the note in that
//    file's main() has it), and reads its depth with an ordinary normalized
//    texture() of that coordinate. At the quarter this pass ships at, a texel
//    index i therefore has its centre at (i + 0.5) / (view * 0.25), which is
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
//
// ⚠️ What comes back is always finite, and the three places that is enforced
// rather than assumed are the distance (FogViewDistance), the weight sum
// (FOG_UPSAMPLE_WEIGHT_EPSILON) and the result itself. A NaN or an infinity that
// reaches the frame is a black or a white speck that nothing downstream can
// repair, and the depth buffer and the fog buffer are both places one can come
// from.
vec4 UpsampleVolumetrics(vec2 screenCoord, float depth) {
	// ⚠️ What picks between the two reads below is the BUFFER'S OWN SIZE, asked
	// of the buffer, and not the option that sized it (batch 533). The two used
	// to be an #ifdef on VOLUMETRIC_FOG_FULL_RES here and a hand-written 0.25 in
	// the grid further down: two statements of one fact, and the author's report
	// is what that costs when they disagree - the properties side put the buffer
	// at the frame's own size, this reader's #ifdef did not take, and the fog
	// came out shrunken into a corner, which is the signature of a buffer written
	// at one resolution and read at another. The writer asks this same question
	// for its own screen coordinate now (see /program/post/volumetric_fog.fsh), so
	// the read follows the buffer wherever the properties put it.
	//
	// ⚠️ textureSize is a query and not a sample: it asks the texture for its own
	// dimensions and reads no texel, so it is legal here although a pass writes
	// this buffer, and it is the one statement of the size that the writer and
	// this reader cannot disagree about.
	ivec2 fogSize = textureSize(colortex1, 0);

	// Full resolution: one texel of the fog is one pixel of the frame, so there
	// is nothing to put back on the frame's grid and no depth weighting has
	// anything to weigh - the fetch is this fragment's own texel, which is what
	// the debug views above make too.
	//
	// ⚠️ Clamped into the buffer even though the two sizes are equal on this
	// path, for the reason every other fetch in this function is clamped:
	// texelFetch outside a texture is undefined rather than clamped, and a fact
	// about the loader is worth stating in the code that depends on it.
	if (fogSize == ivec2(viewWidth, viewHeight)) {
		return texelFetch(colortex1, clamp(ivec2(gl_FragCoord.xy), ivec2(0), fogSize - 1), 0);
	}

	// The fog grid, in texels of it. ⚠️ The buffer's queried size, and no longer
	// viewWidth * 0.25 written out here: at an exact quarter the two are the same
	// number, and at any other scale this one is the buffer's own grid rather than
	// a second guess at it.
	vec2 fogTexel = screenCoord * vec2(fogSize) - 0.5;

	// ⚠️ The base is deliberately NOT clamped into the buffer, although it is
	// outside it at the frame's edge: on the first column of the frame floor()
	// gives -1, and on the last it gives the last texel, whose upper tap is one
	// past the end. Moving the base would move frac with it, and frac is what
	// the bilinear weights are made of - a base pulled inward on the first
	// column leaves frac negative, which hands the tap on its right a NEGATIVE
	// weight, and a weight sum that can cancel to a small positive number is a
	// division that returns an extrapolation rather than a mix. The fetches are
	// clamped instead, at the point of each fetch, which leaves frac - and
	// therefore the weights - exactly the ones a CLAMP_TO_EDGE sampler would
	// have used for the read this replaces.
	ivec2 base = ivec2(floor(fogTexel));
	vec2 frac = fogTexel - vec2(base);

	// The last texel of each buffer, for those clamps. ⚠️ The fog buffer's is its
	// queried size less one now, where it used to be view * 0.25 truncated: the
	// buffer is the authority on how big it is, and an allocation the loader had
	// rounded up would have been one texel wider than that old figure, which the
	// clamp would then have cut short. The depth texture is the frame itself, so
	// its last is view less one, and that one is exact.
	ivec2 fogLast = fogSize - 1;
	ivec2 fullLast = ivec2(viewWidth, viewHeight) - 1;

	// The full-resolution pixel that stands at the centre of each of the four
	// texels around this fragment - the point the fog in that texel was built
	// from, as the note above works out.
	//
	// ⚠️ The 4 is the ratio between the two sizes at the quarter this pack ships
	// the buffer at, which is the only scale this branch can be reached with: 1.0
	// is the other setting shaders.properties offers, and that one is the return
	// above. Where the allocation is the exact quarter of the frame, that is the
	// writer's own depth pixel for this texel; a frame whose width or height is not
	// a multiple of four can leave the loader an integer allocation a fraction off
	// the quarter, which puts this a texel out at most - and a texel of error in a
	// depth WEIGHT is not a texel of error in the fog: the weights decide which
	// side of a silhouette a tap belongs to, and nothing else.
	ivec2 fullTexel = base * 4 + ivec2(2);

	float fragmentDistance = FogViewDistance(ivec2(gl_FragCoord.xy), depth);

	vec4 sum = vec4(0.0);
	float weightSum = 0.0;

	// ⚠️ NINE taps over the three-by-three of fog texels around this fragment, and
	// this is the fix for the "blurry mosaic" the author reported at the edges
	// (batch 572). The four-tap read this replaces is a BILINEAR upsample, and a
	// bilinear upsample of a quarter-resolution buffer can only ever mix the four
	// texels that straddle this pixel. That is exactly right while the picture is
	// flat - the majority of the frame, and it still is here, see the note on the
	// flat case below - but at an edge it is not enough, for a reason that is
	// visible in the geometry rather than in the code: a fragment at a silhouette
	// has some of those four texels belonging to the surface in front and some to
	// the surface behind, and there are only four of them to choose between. The
	// winning texel therefore changes in whole 4-pixel steps as the fragment
	// slides across the footprint, which is a mosaic on a 4-pixel grid.
	//
	// Nine taps do not remove that ambiguity - nothing read at this resolution
	// can - but they give it somewhere to go: three candidates along each axis
	// instead of two, weighted smoothly, so the transition between them is a fade
	// rather than a step.
	//
	// ⚠️ The weight is no longer bilinear, and that is the point rather than a
	// detail. frac was the right weight for a bilinear read and is the wrong one
	// here, because at frac near 0.5 it makes the two texels of a row contribute
	// almost equally while the third contributes nothing, which is a step in the
	// weights as frac crosses the taps. exp(-d^2) has no such step and gives every
	// tap a weight that is a continuous function of where the fragment is.
	//
	// ⚠️ d is measured in FOG TEXELS from this fragment's own position on the fog
	// grid, so it is the distance to the tap - not to the tap's centre pixel,
	// which is what the depth is measured at and is a different thing. One tap
	// away is 0.37 of the centre's weight and two away is 0.018, so the three-by-
	// three covers the footprint (which is two texels across) with a little room
	// to spare and nothing beyond it.
	for (int i = -1; i <= 1; i++) {
		for (int j = -1; j <= 1; j++) {
			// ⚠️ Skipped rather than clamped, unlike the four-tap read: with the
			// base able to sit at the buffer's edge, this ring reaches one texel
			// past it, and reading the edge texel twice there would weight that
			// texel three times over. The sum is normalised at the bottom, so
			// dropping a tap costs nothing but the tap.
			ivec2 tapTexel = base + ivec2(i, j);

			if (tapTexel.x < 0 || tapTexel.y < 0
				|| tapTexel.x > fogLast.x || tapTexel.y > fogLast.y) {
				continue;
			}

			vec2 offset = vec2(i, j) - frac;
			float spatial = exp(-dot(offset, offset));

			// ⚠️ Each tap's distance is taken through the tap's OWN pixel, not
			// through this fragment's: the ray that was marched to build this
			// texel's fog is the one through the centre pixel, and measuring the
			// distance along the fragment's ray instead tilts it and makes the
			// taps disagree with a surface they are standing on.
			//
			// ⚠️ Clamped into the depth texture, because texelFetch outside a
			// texture is undefined rather than clamped - a driver may return
			// anything, including a value that linearises to a NaN - and these
			// reach past the frame's edges near the border: fullTexel is 4*base+2,
			// which is already within six pixels of the frame's end at the last
			// base. The distance below is worked out at this same clamped pixel,
			// so the depth and the distance it belongs to stay the pair they were.
			ivec2 tapPixel = clamp(fullTexel + ivec2(i, j) * 4, ivec2(0), fullLast);
			float tapDepth = texelFetch(depthtex0, tapPixel, 0).r;

			float tapDistance = FogViewDistance(tapPixel, tapDepth);

			// ⚠️ The gap needs no guard of its own, and that is the point of the
			// bound FogViewDistance holds: both distances are finite and inside
			// FOG_UPSAMPLE_MAX_DISTANCE, so the gap is finite and between zero and
			// that bound - never Inf - Inf, which is the NaN this guards against.
			float depthGap = abs(tapDistance - fragmentDistance);

			// ⚠️ A GATE rather than a weight, and this is the part taken from Bliss
			// that the first port left out (batch 579). Its bilateral upsample tests
			// the depth and keeps a tap or discards it - `abs(gap) < threshold ? 1.0
			// : 1e-7` - where this pack multiplied by a smooth `exp(-gap/scale)`.
			//
			// ⚠️ The difference is not how sharp the falloff is; it is that a
			// MULTIPLIER NEVER REJECTS. Measured across a silhouette
			// (upsample_gap_sweep.py, and the sweep is the point - a first attempt
			// compared one 30-block gap where exp() underflows and both filters agree,
			// which proved nothing):
			//
			//     depth gap     smooth exp(-gap)   a gate
			//        1 block        18.0% of the far surface passes    0.0%
			//        2 blocks        7.5%                              0.0%
			//        3 blocks        2.9%                              0.0%
			//
			// A one-to-three block difference is a kerb, a step, a fence rail, a
			// leaf - the silhouettes a player actually walks past - and the smooth
			// weight was bleeding several per cent of the fog from BEHIND them onto
			// them. The fog there was built by a march that ended at ITS OWN surface,
			// so mixing the two is mixing two different rays, and a few per cent of
			// the wrong ray at every edge is what reads as the fog being soft and
			// smeared at exactly the places it should be crisp.
			//
			// ⚠️ The threshold is ABSOLUTE rather than Bliss's relative-to-distance,
			// and the reason is geometric: a fence rail one block in front of a wall
			// is one block in front of it whether the player is standing next to it
			// or two hundred blocks away, and a relative threshold would call the two
			// the same surface at distance - which is precisely the case the gate is
			// for. What it costs is the far field, where a slope crossed by one fog
			// texel changes depth by more than a block and its taps are dropped; the
			// fallback below catches that, and the alternative was to keep bleeding
			// at every edge in the frame.
			//
			// ⚠️ The gate is applied to the DEPTH and the Gaussian to the POSITION,
			// which is the division of labour between the two: the gate decides, and
			// the Gaussian makes the decision fade rather than step - a hard gate
			// with bilinear weights alone would bring back the four-pixel mosaic of
			// batch 572.
			bool tapOnThisSurface = depthGap <= FOG_UPSAMPLE_DEPTH_GATE;

			float weight = tapOnThisSurface
				? spatial
				: 0.0;

			sum += texelFetch(colortex1, tapTexel, 0) * weight;
			weightSum += weight;
		}
	}

	// Normalised, so the result is the weighted average of the taps rather than
	// their sum - which is now load-bearing rather than tidy: the nine weights are
	// a Gaussian kernel and do not add up to one, and the taps at the buffer's
	// edge are dropped outright, so the divisor is a different number in every
	// pixel.
	//
	// ⚠️ What this does NOT do any more is reduce exactly to the bilinear read.
	// With four equal depths the four-tap version did, and that was its best
	// property for the flat majority of the frame. Nine Gaussian weights do not:
	// they mix in the cross taps at 0.37 each, which softens the fog by about a
	// third of a fog texel - one and a third pixels of the frame - even where the
	// buffer is flat. That is a real cost and it is accepted deliberately: the
	// alternative is the four-pixel mosaic at every edge, which is far more
	// visible than a third of a texel of softness spread over the whole picture.
	// If the fog ever reads as too soft and no edge is blocky, the thing to do is
	// narrow this kernel, not to go back to four taps.
	//
	// ⚠️ And when the sum is too small to normalise - every weight underflowed to
	// zero, or every tap is dozens of blocks from this fragment - the fallback is
	// the plain bilinear read and NOT zero (batch 530). Zero is a hole in the fog,
	// and a hole at a silhouette is exactly the black speck this pass was reported
	// for: the picture multiplies the scene by this vector's alpha, so
	// `color * 0.0 + 0.0` is a black pixel rather than a pixel with no fog on it.
	// The bilinear read is what the pass did before the depth weighting existed,
	// so the worst case is batch 525's behaviour instead of a hole.
	//
	// ⚠️ The test is a bound rather than `> 0.0`, and it is written inverted. Both
	// parts are load-bearing: a sum just above zero is weights that all belong to
	// something else being divided by each other for no reason (see
	// FOG_UPSAMPLE_WEIGHT_EPSILON), and every comparison against a NaN is false,
	// so a sum that has somehow become a NaN takes this branch as well instead of
	// being divided.
	if (!(weightSum > FOG_UPSAMPLE_WEIGHT_EPSILON)) {
		return texture(colortex1, screenCoord);
	}

	vec4 result = sum / weightSum;

	// ⚠️ The last guard, and the rule it holds is worth holding at the function's
	// edge rather than three calls into it: whatever the fog buffer holds, nothing
	// that is not a number leaves this function. The division above cannot make
	// one on its own - the weights are never negative, so the quotient is bounded
	// by the largest tap - but a tap that is already a NaN or an infinity would
	// carry straight through it, and the fog buffer is RGBA16F, which holds both
	// (volumetric_fog.fsh declares the format). The test is the one the pack
	// trusts a history with (see the guards in composite1.fsh and ssao.glsl):
	// `!(dot(x, x) < 1.0e18)` catches a NaN, either infinity, and anything
	// absurdly large in a single expression. A finite sixteen-bit value can never
	// trip it - the largest is 65504, so the dot product of a fog colour cannot
	// reach even 2e10 - and that is what makes this line free for the fog pass.
	if (!(dot(result, result) < 1.0e18)) {
		// No fog rather than a black pixel: no scattered light and full
		// transmittance, which is the state the fog pass itself starts from and
		// the one the picture reads as "the scene, unchanged".
		return vec4(0.0, 0.0, 0.0, 1.0);
	}

	return result;
}

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

	#if !defined(VIEW_SIZE_DECLARED)
		#define VIEW_SIZE_DECLARED
		uniform float viewWidth;
		uniform float viewHeight;
	#endif
#elif DEBUG == DEBUG_GODRAYS_NOISY || DEBUG == DEBUG_GODRAYS_SMOOTH
	// colortex1 needs no declaration here: it is declared above, unconditionally.
	//
	// ⚠️ The frame's own size does need one, since batch 534 made this view ask
	// the buffer for its own grid rather than trusting an #ifdef to say what that
	// grid is. It sits behind the same guard the upsample's declaration uses: with
	// volumetric light on it is already there, and with it off this view still has
	// to compile - a view that fails to compile because the effect it diagnoses has
	// been switched off would be worse than useless, and it is the first thing a
	// reader tries.
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
		#ifdef VOLUMETRIC_FOG
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

		#ifdef VOLUMETRIC_FOG
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

			// ⚠️ The bloom fog mask, read out of that same fourth channel (batch
			// 576). What the channel holds depends on the dimension - the mask on
			// every path where the transmittance is exactly 1.0, and the plumes'
			// transmittance in the Nether, because a channel can hold one number -
			// and the note on the fog pass's output is where that is worked out.
			//
			// ⚠️ NOTHING HERE HAS TO KNOW WHICH OF THE TWO IT IS, and that is the
			// whole reason the split is workable: the mask is 1.0 in the Nether (the
			// smoke already fades what is behind it and should not be doing the
			// bloom's job as well) and the transmittance is 1.0 everywhere else, so
			// in both cases the channel is the smaller of the two and the blend
			// weight wants to be the smaller of the two. One clamp serves both.
			//
			// ⚠️ Read out here rather than after the multiply below, because
			// `volumetrics.a` is what that multiply consumes: reading it afterwards
			// would be reading it after it had already been used once.
			//
			// ⚠️ An earlier version of this line asked `NetherDimension()` instead,
			// which does not compile: that function comes in with
			// /environment/dimension.glsl, this program only includes that file
			// under the DEBUG_PLUME_DENSITY debug view, and a call in the ordinary
			// path is therefore an undeclared name. Nothing in the final pass may
			// depend on a uniform the final pass is not given - the same trap
			// BATCH_LOG.md 171 records for shadowDistance.
			float bloomFogMask = clamp(volumetrics.a, 0.0, 1.0);

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
