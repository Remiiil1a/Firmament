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

#version 150 compatibility

// The temporal anti-aliasing resolve.
//
// The gbuffer programs render the world with a sub-pixel offset that walks one
// step of a low-discrepancy sequence per frame (see /lib/taa.glsl, and the TAA
// section of shaders.properties for the sequence itself), and this pass is what
// turns those offset frames into a single smoother image, by averaging each one
// with a history of the ones before it.
//
// The history is reprojected with the previous frame's camera matrices, so that
// it lands in the right place while the camera moves. There are no motion
// vectors to reproject anything that moves on its own with, so instead the
// history is rejected wherever it disagrees with the current frame.
//
// This pass runs before the final one, so all of this happens in linear HDR
// light rather than on the tonemapped image.

#include "/lib/taa.glsl"

// The history buffer keeps its contents between frames, so that there is
// something to accumulate onto. If it were cleared every frame, this pass would
// only ever average the current frame with the clear color, which shows up as a
// dark, flat, smeared image rather than as anti-aliasing.
//
// The flag is declared here as well as in shaders.properties because the two
// loaders read it from different places.
const bool colortex3Clear = false;

const int R11F_G11F_B10F = 0;
const int RGBA16F = 0;
const int colortex3Format = RGBA16F;

uniform sampler2D colortex0;

// The previous frame, resolved, which is what this pass accumulates onto.
//
// It is also the buffer the environment reflection traces over, one pass later.
// Nothing may be added to what is written into it here: a reflection in the
// history would be pulled back out again by the neighbourhood clamp below, whose
// neighbourhood is read from colortex0 and has no reflection in it. See
// composite3.fsh.
uniform sampler2D colortex3;

// The depth buffer that includes translucents, so that it matches what is
// actually in colortex0. (depthtex1 is the opaque-only depth, which the water
// reflections use.)
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;

// The matrix the geometry was drawn with, for the anchor dots of the temporary
// END_SHAKE_PROBE above. Nothing else in this pass reads it.
uniform mat4 gbufferModelView;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

// The one copy of the previous-frame reprojection. See /lib/reproject.glsl, and
// BATCH_LOG.md 210 for why this is a file and not three.
#include "/lib/reproject.glsl"

uniform vec2 windowToScreen;
uniform float blindness;

// The pack's sky, which this pass uses to take back the sky pixels in the End.
// Uniforms: dimension, biome_category, the atmosphere's own
#include "/environment/sky.glsl"

// The material model, for the option switches the environment reflection is
// built on, and the reflection helpers it calls.
#include "/environment/lighting/pbr.glsl"
#include "/environment/lighting/reflections.glsl"

// The trace's step budget, which is an option rather than the water reflections'
// constant. Has to be set before the include below, which only falls back to its
// own default if nobody has chosen one.
#define RAYMARCH_STEPS PBR_SSR_STEPS

#include "/lib/raytrace.glsl"

// The environment reflection used to be applied by this pass. It now has a pass
// of its own, one later, because the buffer it has to read is the resolved image
// - which is the buffer this pass writes. See composite3.fsh.

// TEMPORARY DIAGNOSTIC (b501): the End's sky and the view bob.
//
// Draws, over the End's sky, three pairs of dots at three fixed world directions.
// The bright dot of each pair is that direction taken through the matrix the
// geometry was drawn with; the dim one is the same direction taken through the
// shader mod's inverse of that matrix. They are one direction computed two ways:
//
//   * while the two matrices agree, the dim dot sits exactly behind the bright
//     one and is never seen;
//   * where they disagree - which is what the view bob is suspected of - the dim
//     dot slides out from behind the bright one, and how far it slides is the
//     disagreement itself.
//
// A white dot marks the direction the End's giant is placed at (worldSunVector), and
// a cyan one the same direction built through the geometry's matrix, so that the body,
// its lens, and the two ways of placing them, can all be read against the anchors.
// so that the body and its lens can be compared against the same anchors.
//
// The dots are welded to the terrain by construction, which is what makes them
// anchors: they are built the way the geometry was built.
//
// Remove this option, its pick in screen.DEBUG_VIEWS and its two lang entries
// once the question is answered. See BATCH_LOG.md b501.
//#define END_SHAKE_PROBE

// The sky light the reflection is faded out by, written by the surface programs
// and not touched since.
uniform sampler2D colortex2;

// Declared once, unconditionally and outside the conditional below: Iris reads
// this directive from the raw source text, so having one in each branch of an
// #if would leave it unclear which one applies. The list names the buffers in
// the order their gl_FragData outputs are written: index 0 is the colour,
// index 1 the history. Both are written whether anti-aliasing is on or off.
// colortex3 used to be skipped when it was off, because nothing read the
// buffer in that case - which stopped being true when the environment
// reflection moved into a pass of its own: that pass reads this one for the
// world to trace over.
/* DRAWBUFFERS:03 */

// The resolved image of the previous frame, at the given screen position,
// fetched with a Catmull-Rom filter rather than with the bilinear one that a
// plain texture() would use.
//
// Wherever the reprojected coordinate lands between texels - which is everywhere
// the camera is moving - a bilinear fetch blends the four neighbours around it,
// and the result is what gets accumulated and blended again next frame, and
// again the frame after that. The history is therefore low-pass filtered once
// per frame, and a moving camera slowly softens the picture it is accumulating.
// Catmull-Rom interpolates rather than approximates and carries small negative
// lobes, so detail that falls between texels passes through instead of being
// averaged away. This is how Mellow Shader's temporal filter fetches its history
// (texture_catmullrom_fast in global/post/taa.glsl, and its TAA_MODE 3); the
// neighbourhood clamp in main() is what keeps the overshoot at an edge from
// ringing.
//
// The two axes are resolved separately and only five of the sixteen taps that
// would take are kept, which is what makes it affordable.
// Whether a history texel may be allowed to contribute to the filtered sample.
//
// ⚠️ The test is "exactly zero, or not a number", and not "dark". colortex3 is
// R11F_G11F_B10F, which has no encoding for a NaN, so a value that could not be
// stored comes back as a literal black pixel - that is the signature this looks
// for, and it is the same one main() uses when it treats an exactly-zero history
// as no history at all. A genuinely dark pixel is not exactly zero and passes.
bool HistoryTapUsable(vec3 tap) {
	return (dot(tap, tap) < 1.0e18) && (tap != vec3(0.0));
}

vec3 HistorySample(vec2 coord) {
	vec2 size = vec2(viewWidth, viewHeight);
	vec2 position = coord * size;

	// The texel the coordinate sits in, and the offset within it.
	vec2 center = floor(position - 0.5) + 0.5;
	vec2 f = position - center;
	vec2 f2 = f * f;
	vec2 f3 = f2 * f;

	// The tension: 0.65 is Mellow's value, between the 0.5 of a Catmull-Rom
	// spline and the 1.0 of a linear one.
	float c = 0.65;
	vec2 w0 = -c * f3 + 2.0 * c * f2 - c * f;
	vec2 w1 = (2.0 - c) * f3 - (3.0 - c) * f2 + 1.0;
	vec2 w2 = -(2.0 - c) * f3 + (3.0 - 2.0 * c) * f2 + c * f;
	vec2 w3 = c * f3 - c * f2;

	vec2 w12 = w1 + w2;
	vec2 invSize = 1.0 / size;

	// Clamped, because the taps reach a texel or two past the coordinate and the
	// history is not to be read from outside itself.
	vec2 middle = clamp((center + w2 / w12) * invSize, 0.0, 1.0);
	vec2 low = clamp((center - 1.0) * invSize, 0.0, 1.0);
	vec2 high = clamp((center + 2.0) * invSize, 0.0, 1.0);

	// ⚠️ Each tap is checked before it is allowed to contribute, and that is the
	// guard against the black blot growing. It belongs here rather than in the
	// clamp in main(), because this is where the growing happens: the filter
	// reaches two texels and carries negative lobes, so one black texel is not
	// merely read - it is spread into the pixels around it with a weight, and each
	// of those is a black history over a clean frame the frame after. The
	// statistical clamp cannot stop that, because every step of it is small and
	// plausible. Never letting the black into the sum can.
	vec3 color = vec3(0.0);
	float total = 0.0;
	float weight;

	vec4 tap4;
		tap4 = texture(colortex3, vec2(middle.x, middle.y)).rgba;
	weight = w12.x * w12.y * tap4.a;
	if (HistoryTapUsable(tap4.rgb)) { color += tap4.rgb * weight; total += weight; }

		tap4 = texture(colortex3, vec2(middle.x, low.y)).rgba;
	weight = w12.x * w0.y * tap4.a;
	if (HistoryTapUsable(tap4.rgb)) { color += tap4.rgb * weight; total += weight; }

		tap4 = texture(colortex3, vec2(low.x, middle.y)).rgba;
	weight = w0.x * w12.y * tap4.a;
	if (HistoryTapUsable(tap4.rgb)) { color += tap4.rgb * weight; total += weight; }

		tap4 = texture(colortex3, vec2(high.x, middle.y)).rgba;
	weight = w3.x * w12.y * tap4.a;
	if (HistoryTapUsable(tap4.rgb)) { color += tap4.rgb * weight; total += weight; }

		tap4 = texture(colortex3, vec2(middle.x, high.y)).rgba;
	weight = w12.x * w3.y * tap4.a;
	if (HistoryTapUsable(tap4.rgb)) { color += tap4.rgb * weight; total += weight; }

	// ⚠️ Every tap unusable is the one case this cannot answer, and it is a real
	// one: a frame in which the whole neighbourhood was not a number leaves the
	// history black at all five. Returning black there would keep it black, but the
	// caller's own exactly-zero test replaces a black sample with the current
	// frame - which is the value that has to win that case. So black is returned on
	// purpose, as a signal rather than as a colour.
	//
	// ⚠️ And the same is done for a *negative* or vanishing total, which the
	// arithmetic allows now that the sum is over the taps that survived rather than
	// over all five. The weights carry negative lobes, so a set in which only those
	// survive sums below zero - and dividing by it would produce a large, entirely
	// plausible-looking colour, which is worse than an obvious black because the
	// exactly-zero test downstream would not catch it. Treating the unusable sum as
	// "no history" sends it down the same path as the all-black case.
	if (total < 1.0e-4) {
		return vec3(0.0);
	}

	// The taps left out have weight too, so the result is normalised by the sum of
	// the ones that were kept - now including any dropped for being black - rather
	// than trusting them to add up to one.
	return color / total;
}

void main() {
	ivec2 pixel = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = gl_FragCoord.xy * windowToScreen;

	vec3 current = texelFetch(colortex0, pixel, 0).rgb;

	// Kept as it arrived, for the debug view below: the repair further down would
	// otherwise hide exactly what that view exists to show.
	vec3 currentRaw = current;

	// Whether what the geometry wrote here is a colour at all.
	//
	// This is the one place a bad value can be caught before it becomes permanent.
	// Everything downstream reads this buffer back - the neighbourhood below, the
	// clamp that is built from it, and the history this pass writes - so a pixel
	// that is not a number does not just spoil one frame: it spoils the average of
	// everything around it, and then it is written into the history for the next
	// frame to read. That is what a black blot that grows until it covers the
	// terrain is, and it needs no help from any one effect: with a long enough
	// history the clamp's own neighbourhood is black too, mean and deviation are
	// both zero, and the region holds itself in place until the view turns far
	// enough for the reprojection to fall off the screen and reset it.
	//
	// One bound rather than three tests, because a NaN fails every comparison:
	// "is this inside the range I can use" is false of it, which is why the
	// negation is the check. See BATCH_LOG.md 131.
	bool currentUsable = dot(current, current) < 1.0e18;

	vec3 resolved;

	#ifndef TAA
		// The pass runs even with anti-aliasing switched off, so that the buffer
		// flow through the pipeline does not change; with it off, this is just a
		// copy.
		resolved = currentUsable ? current : vec3(0.0);
	#else
	ivec2 screenSize = ivec2(viewWidth, viewHeight);

	// Reconstruct the absolute world position of this fragment, so that the
	// previous frame's camera can be applied to it. Working in absolute terms
	// rather than camera-relative is what makes this survive the camera moving.
	float depth = texelFetch(depthtex0, pixel, 0).r;

	// The sub-pixel jitter is deliberately NOT taken back out here, and this is
	// worth spelling out, because the arithmetic makes it look as though it
	// should be.
	//
	// It is true that the depth at this pixel belongs to a surface the jittered
	// camera moved by up to half a pixel, so reconstructing from this pixel's own
	// coordinate does land slightly to the side of the surface that was actually
	// sampled. What that costs is a sub-pixel error in one lookup.
	//
	// Subtracting TaaJitter() costs more, and not in a way the subtraction itself
	// shows: it makes the position the history is read from depend on this frame's
	// jitter. The history is accumulated at the pixel's own index, so the picture
	// held in it is displaced a little further every frame, in the direction of
	// that frame's jitter. That offset does not settle. Under a still camera it
	// settles into an oscillation of roughly the jitter times 1 / (1 - TAA_STRENGTH)
	// - several times the sub-pixel error it was meant to remove - and it reads as
	// the whole picture shaking. It grows with TAA_JITTER, so that option is what
	// makes it visible first, and it is why the subtraction was reverted in
	// BATCH_LOG.md 119.
	//
	// The jitter belongs to the current frame's sampling, not to the history's
	// indexing: the frames that carry it are the ones being averaged, and the
	// average is what removes it.
	// ⚠️ The depth this is reprojected from is not necessarily this pixel's own.
	//
	// At a silhouette this pixel's depth belongs to whatever is behind the edge,
	// while the pixel is mostly showing the thing in front of it - and reprojecting
	// the surface behind the edge drags the history of the front surface along with
	// it. What the pixel actually shows is best guessed by the nearest of its
	// neighbours, so that is the depth the reprojection is built from, and the
	// offset that comes back is applied to this pixel's own coordinate.
	//
	// Mellow Shader (get_closest_depth in global/post/taa.glsl), Bliss
	// (closestToCamera5taps in dimensions/composite5.fsh) and Sundial
	// (getClosestDepth in Composite7.frag) each arrived at this separately, and
	// that agreement is the strongest thing the survey found. See
	// BATCH_LOG.md 210.3.
	vec2 anchorCoord = screenCoord;
	float anchorDepth = depth;

	for (int ti = -1; ti <= 1; ti++) {
		for (int tj = -1; tj <= 1; tj++) {
			// The centre of the 3x3 is this pixel, whose depth is already in
			// anchorDepth: it was read from this very texel above, and the clamp
			// below is an identity on this pixel's own coordinate. Reading it again
			// could only compare that value with itself, and the test below is
			// strict, so the iteration cannot change anything - it is skipped rather
			// than paid for. Written against the loop counters, so that the eight
			// that remain keep the order they had: with a strict test it is the
			// first of two equally near neighbours that wins, and which one that is
			// decides the coordinate the history is reprojected from.
			if (ti == 0 && tj == 0) {
				continue;
			}

			ivec2 at = clamp(pixel + ivec2(ti, tj), ivec2(0), screenSize - 1);
			float candidate = texelFetch(depthtex0, at, 0).r;

			if (candidate < anchorDepth) {
				anchorDepth = candidate;
				anchorCoord = (vec2(at) + 0.5) * windowToScreen;
			}
		}
	}

	vec3 anchorNdc = vec3(anchorCoord * 2.0 - 1.0, anchorDepth * 2.0 - 1.0);
	vec4 anchorViewH = gbufferProjectionInverse * vec4(anchorNdc, 1.0);
	vec3 anchorViewPos = anchorViewH.xyz / anchorViewH.w;
	vec3 anchorWorldPos =
		(gbufferModelViewInverse * vec4(anchorViewPos, 1.0)).xyz + cameraPosition;

	// ⚠️ The held item is not reprojected like the world, because it does not move
	// like the world: it is attached to the camera, so it stays put relative to it
	// while the world slides past. Reprojecting it with the camera's translation
	// makes it drag its own history along with the walking, which is the smearing
	// you see on a sword mid-swing.
	//
	// The trick is to cancel the translation without a second function: the shared
	// reprojection subtracts previousCameraPosition from whatever it is given, so
	// handing it the point *plus* (previousCameraPosition - cameraPosition) leaves
	// it holding the camera-relative position - which is rotation only. Mellow
	// Shader does the same thing by skipping the delta above a hand depth
	// (global/post/taa.glsl), and Bliss zeroes the held item's vector outright.
	//
	// ⚠️ The threshold is on the game's own non-linear depth, so it is an
	// empirical number rather than a distance, and it is Mellow's. Getting it
	// wrong is not catastrophic - world geometry nearer than it gets reprojected
	// by rotation alone, which is a small error in a small part of the frame.
	const float TAA_HAND_DEPTH = 0.56;

	vec3 reprojectFrom = anchorDepth > TAA_HAND_DEPTH
		? anchorWorldPos
		: anchorWorldPos + (previousCameraPosition - cameraPosition);

	// Where that point was on screen last frame. Both halves of the answer come
	// from the one copy of that arithmetic, in /lib/reproject.glsl.
	Reprojection reprojection =
		ReprojectWorldPosition(reprojectFrom, anchorCoord);
	vec2 previousScreenCoord =
		screenCoord + (reprojection.previousCoord - anchorCoord);

	// Both the neighbourhood and the history are read from the current frame's
	// screen space, so anything that was off screen or behind the camera last
	// frame has no usable history at all.
	//
	// Written as "is it inside the frame", then negated, rather than as "is it
	// outside it". The two say the same thing about a number and different things
	// about a NaN, which is the whole point of spelling it this way: every
	// comparison against a NaN is false, so a coordinate that came out of a
	// division by zero is neither less than zero nor greater than one, and an
	// outside test written the other way round lets it through. What is then
	// sampled is not a colour, and this buffer does not fade - the resolve writes
	// its own result back for the next frame to read, so a value that is not a
	// number spreads outward through the Catmull-Rom taps until it covers the
	// screen. It is intermittent because it needs the reprojection to land on a
	// w of zero, which is why it reads as a black blot that appears and goes away
	// again as the view turns. See BATCH_LOG.md 129.
	bool offScreen = reprojection.offScreen;
	bool behindCamera = reprojection.behindCamera;

	// Gather the neighbourhood of the current frame, which serves two purposes:
	// it bounds what the history is allowed to say, and it provides the blurred
	// version used for sharpening below.
	vec3 neighborhoodSum = vec3(0.0);
	vec3 neighborhoodSquareSum = vec3(0.0);
	float neighborhoodCount = 0.0;

	// The brightest value the current frame shows in this pixel's own
	// neighbourhood, which the clamp below uses to tighten its upper end.
	vec3 neighborhoodMaximum = vec3(-1.0e18);

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			// The centre of the 3x3 is this pixel, whose colour was read once at the
			// top of the pass. Fetching it here would return that same texel - same
			// texture, same level, same coordinate, since the clamp below is an
			// identity on this pixel's own coordinate - under the same test, so it
			// is folded in after the loop (see the note there) and the iteration is
			// skipped rather than paid for. The loop counters make the test constant,
			// so no branch survives compilation.
			if (x == 0 && y == 0) {
				continue;
			}

			ivec2 offsetPixel = clamp(pixel + ivec2(x, y),
				ivec2(0), screenSize - 1);
			vec3 neighbor = texelFetch(colortex0, offsetPixel, 0).rgb;

			// The same test as on the centre pixel, and for the same reason: one
			// pixel that is not a number would otherwise make the mean, the
			// deviation and the clamp that is built from them all NaN, which turns
			// a single bad pixel into a region of them. A neighbour that cannot be
			// used is left out of both sums and counted as nothing.
			if (!(dot(neighbor, neighbor) < 1.0e18)) {
				continue;
			}

			neighborhoodSum += neighbor;
			neighborhoodSquareSum += neighbor * neighbor;
			neighborhoodCount += 1.0;
			neighborhoodMaximum = max(neighborhoodMaximum, neighbor);
		}
	}

	// The centre's own contribution, which the loop above skips. This pixel is
	// one of its own nine neighbours, and currentUsable is the very test the loop
	// applies to a neighbour - the same expression, on the value that loop would
	// have read - so both sums, the count and the maximum are made of the same
	// nine values, and of the same number of them, as before.
	//
	// ⚠️ What is not the same, and cannot be while the fetch is saved, is the
	// order the sum is added up in: the centre was the fifth of nine addends and
	// is now the ninth, and floating-point addition is not associative. Both sums,
	// and what is derived from them - the mean, the variance, and the two bounds
	// the history is clamped to - can therefore differ in their last few bits.
	// The maximum is not in that list: colortex0 is R11F_G11F_B10F, an unsigned
	// format with no negative zero in it, so the largest of the nine is the
	// largest of the nine whichever order they arrive in.
	if (currentUsable) {
		neighborhoodSum += current;
		neighborhoodSquareSum += current * current;
		neighborhoodCount += 1.0;
		neighborhoodMaximum = max(neighborhoodMaximum, current);
	}

	// No usable neighbour at all would leave the maximum at its starting
	// value, which is not a bound a colour can be clamped to. The loop cannot
	// leave it there: the clamped pixel coordinates make it at least one.
	if (neighborhoodCount < 1.0) {
		neighborhoodMaximum = current;
	}

	// Divided by how many neighbours were usable rather than by nine: a skipped
	// neighbour is not a zero, and counting it as one would pull the mean down.
	float neighborDivisor = max(neighborhoodCount, 1.0);
	vec3 neighborhoodMean = neighborhoodSum / neighborDivisor;

	// The centre pixel repaired from its neighbourhood, when the geometry wrote
	// something that is not a colour there. The mean of the pixels around it is a
	// plausible value and a finite one, which is all this has to be: it is read by
	// the clamp, by the resolve and by the write to the history below, and any of
	// those three would carry a value that is not a number into the next frame.
	if (!currentUsable) {
		current = neighborhoodMean;
	}

	// Variance clipping, from Salvi's "An Excursion in Temporal Supersampling".
	//
	// Bounding the history by the minimum and maximum of the neighbourhood
	// sounds reasonable but is far too permissive on textured surfaces: a 3x3
	// box around a detailed block texture already spans most of its contrast,
	// so almost any stale sample is accepted and the texture slowly averages
	// itself into a smudge. Bounding by the neighbourhood's mean plus or minus
	// a multiple of its standard deviation follows the actual distribution of
	// the pixels instead, which keeps detail while still rejecting samples that
	// do not belong.
	//
	// The standard deviation is derived from the mean and the mean of the
	// squares, which the loop above accumulates as it goes.
	vec3 variance = max(
		neighborhoodSquareSum / neighborDivisor - neighborhoodMean * neighborhoodMean,
		vec3(0.0));
	vec3 deviation = sqrt(variance);

	// The history is fetched only when there is a coordinate to fetch it with.
	// HistorySample's floor, clamp and texture are all undefined for a coordinate
	// that is not a number - and a driver is free to answer one with a perfectly
	// ordinary colour from the edge of the texture, which would then sail past
	// every check below because it looks exactly like a valid history.
	bool historyUsable = !offScreen && !behindCamera && frameCounter >= 2;
	vec3 history = historyUsable ? HistorySample(previousScreenCoord) : current;

	// A history that is not a number, or is infinite, is replaced rather than left
	// to the clamp. The clamp does happen to save a -Inf - clamp(-Inf, a, b) is a -
	// but that is the arithmetic being kind rather than a decision this code made,
	// and it does nothing at all for a NaN. One bound asks the whole question:
	// a NaN fails every comparison, so "is this inside the range I can use" is
	// false of it and of both infinities.
	if (!(dot(history, history) < 1.0e18)) {
		history = current;
	}

	// A history that is exactly black is treated as no history at all.
	//
	// This is Mellow Shader's guard, and it is taken from there because it is the
	// one thing in that resolve this pack did not have - see `if (PrevColor ==
	// vec3(0)) return Color;` in global/post/taa.glsl. What it is for is the value
	// held here is colortex3, which is RGBA16F: no encoding for a NaN or an
	// infinity, so a value that is not a number is written as an ordinary zero
	// and read back the next frame looking like a pixel that is black. Nothing
	// in the clamp below can tell that zero from a real one, because every
	// bound there is built to allow black - a shadow is black, and the lower
	// end is floored at zero on purpose.
	//
	// An exact zero is what it is looking for and not "very dark", because very
	// dark is a shadow and this is not: it is the shape a value takes when the
	// buffer had to round it away. A pixel that was genuinely black last frame
	// takes the current frame here instead of the history, so it stops
	// accumulating for as long as it stays black - a little of the dither is left
	// in the darkest parts of the image, which is the price of a blot that
	// otherwise never stops. See BATCH_LOG.md 159.
	if (history == vec3(0.0)) {
		history = current;
	}

	if (frameCounter < 2 || offScreen || behindCamera) {
		// Nothing trustworthy has been accumulated yet, or the pixel was not on
		// screen last frame.
		history = current;
	}

	// The lower bound is floored at zero, and that is not tidiness.
	//
	// The history is fetched with Catmull-Rom, whose negative lobes undershoot on
	// the bright side of an edge - and a specular highlight on a metal is exactly
	// that shape: a bright line lying on a dark surface. The neighbourhood there
	// has a low mean and a large deviation, so "the mean minus TAA_CLAMP
	// deviations" is itself negative, the clamp has nothing to pull the undershoot
	// back to, and a negative colour is drawn as black. It reads as sparse dark
	// speckles along the edge of the highlight, which is where it was found - and
	// only on the resolved side of the split view, which is what says it is this
	// pass and not the geometry. See BATCH_LOG.md 134.
	vec3 historyLower = max(neighborhoodMean - TAA_CLAMP * deviation, vec3(0.0));
	vec3 historyUpper = neighborhoodMean + TAA_CLAMP * deviation;

	// A floor under the lower bound, measured against the current frame's mean and
	// not against its darkest value, which is a no-op here: the loop this bounds
	// lives in the history alone, and a bound read from there cannot stop it.
	// this exists to stop.
	//
	// The upper end is tightened by the neighbourhood's brightest value as well,
	// which can only ever reject a history brighter than anything the frame shows
	// nearby.
	//
	// The two cannot cross: the mean times a fraction of at most one is at or below
	// the mean, the mean is at or below the statistical upper end, and the
	// neighbourhood's brightest value is at or above its mean - so the lower end is
	// never above the upper one, whatever the deviation does.
	historyUpper = min(historyUpper, neighborhoodMaximum);

	history = clamp(history, historyLower, historyUpper);

	// How far this pixel moved since the previous frame, in pixels.
	// Measured from this pixel to where this pixel's history was - the anchor's own
	// velocity is a different quantity, since the anchor is a neighbouring texel.
	vec2 velocity = (screenCoord - previousScreenCoord) * vec2(viewWidth, viewHeight);

	// How much of the history is kept is decided by how much the pixel moved, the
	// way Mellow Shader's temporal filter does it (global/post/taa.glsl: its blend
	// factor runs from exp(-|velocity|^2) scaled between two limits).
	//
	// This is what makes a long history usable. A long history is the only way to
	// average the noise out of an image - the dither in the screen-space shadows
	// moves every frame precisely so that this can - but a long history is also
	// what smears anything that moves on its own, and there are no motion vectors
	// here to reproject those with. Splitting the two by motion gives the noise
	// reduction where the picture is holding still and drops back to a short
	// history where it is not.
	//
	// So TAA_STRENGTH is the weight for a pixel that did not move at all, and
	// what multiplies it is not bounded below by 0.7. The mix() runs downward
	// towards 0.7 as stillness falls, and stillness is exp(-|velocity|^2), so
	// one pixel of motion already scores 0.37 - about a third of the option.
	float stillness = exp(-dot(velocity, velocity));
	float historyWeight = TAA_STRENGTH * mix(0.7, 1.0, stillness);

	// The weight is checked before it is used, and this is the last place in
	// this pass where a value that is not a number can still get in.
	//
	// The frames either side of this pass cannot carry one, and that is not an
	// assumption about the effects upstream - it is the buffer formats. colortex0
	// and colortex3 are both R11F_G11F_B10F, an unsigned format with no encoding
	// for a NaN or an infinity, so whatever the surfaces write arrives here finite
	// and so does the history. Everything that could produce one is therefore
	// arithmetic inside this function, and velocity is the arithmetic left:
	// previousCoord came out of a clip-space division by its own w, and a clip
	// position that is zero in both is 0/0.
	//
	// offScreen does catch that coordinate, and history is replaced by current for
	// it. The weight is built from the same velocity and was never checked, and
	// mix(current, current, NaN) is a NaN.
	//
	// Why a NaN here is worse than one frame of one pixel: it does not stay a NaN.
	// Neither buffer can hold one, so what the next frame reads back is an ordinary
	// zero - black, finite, and inside every bound the clamp below can put on it.
	// That is a black pixel in the history that the current frame does not have,
	// and the Catmull-Rom fetch hands it to the pixels beside it, which is a blot
	// that starts somewhere and grows. See BATCH_LOG.md 158.
	//
	// Zero rather than anything else: a weight of zero means this pixel is taken
	// from the current frame and not from the history at all, which is the one
	// answer that cannot be wrong about a frame that is known to be finite.
	if (!(historyWeight >= 0.0 && historyWeight <= 1.0)) {
		historyWeight = 0.0;
	}

	resolved = mix(current, history, historyWeight);

	// And the result, before it reaches the history - the same guard the
	// reflection's own history has in composite3. It is a hedge: resolved is
	// built from the expressions above, and every one of them is finite by the
	// argument in the note, but if a black blot is what follows from being
	// wrong - and it does, because the buffer cannot hold a NaN and turns one
	// into a zero the next frame reads as a black history - it is one test.
	if (!(dot(resolved, resolved) < 1.0e18)) {
		resolved = current;
	}

	// Averaging frames together softens the image, which is the price of the
	// anti-aliasing; a little sharpening puts the edge definition back without
	// reintroducing the aliasing. The reference is the neighbourhood mean.
	resolved += TAA_SHARPEN * (resolved - neighborhoodMean);
	#endif

	#if END_SKY != END_SKY_OFF
		// The End's sky belongs to this pack, and this is the last point at which
		// that can be enforced.
		//
		// Anything drawn into the sky by something else survives everything the
		// pack's own sky programs do, because it is drawn after them: the light
		// flash added in Minecraft 1.21.9 is one example, and it arrives as a
		// patch of whatever texture was left bound rather than as anything
		// recognizable. Rather than chase down which program draws each such
		// thing, anything at all left in the sky is replaced with the sky, which
		// is also the only answer that stays correct when the next version adds
		// another one.
		//
		// A depth of exactly 1.0 means nothing was drawn here at all, which is
		// what the sky is - the sky programs paint color without touching depth.
		if (EndDimension() && texelFetch(depthtex0, pixel, 0).r >= 1.0) {
			vec3 ndcPos = vec3(screenCoord * 2.0 - 1.0, 1.0);
			vec4 viewVecH = gbufferProjectionInverse * vec4(ndcPos, 1.0);
			vec3 viewVec = normalize(viewVecH.xyz / viewVecH.w);

			// Note: w must be 0.0 in homogenous coordinates, as 1.0 means a
			// point in space rather than a vector.
			vec3 worldDir = (gbufferModelViewInverse * vec4(viewVec, 0.0)).xyz;

			#ifdef END_SHAKE_PROBE
				// TEMPORARY (b501). See the note on the option near the top of this file.
				//
				// Three pairs of dots at three fixed world directions, plus a white dot at
				// the direction the giant is placed at. In each pair the bright dot is the
				// direction through the matrix the geometry was drawn with and the dim one
				// through the shader mod's inverse of it, so where the two matrices agree
				// the dim dot is hidden exactly behind the bright one.
				vec3 sky = SkyDither(gl_FragCoord.xy, SkyColor(worldDir));

				mat3 drawnBy = mat3(gbufferModelView);
				vec3 geometryDir = normalize(vec3(
					dot(viewVec, drawnBy * vec3(1.0, 0.0, 0.0)),
					dot(viewVec, drawnBy * vec3(0.0, 1.0, 0.0)),
					dot(viewVec, drawnBy * vec3(0.0, 0.0, 1.0))));
				vec3 inverseDir = normalize(worldDir);

				const float PROBE_RADIUS = 0.011;   // radians: about 0.63 degrees

				float geometryX = acos(clamp(dot(geometryDir, vec3(1.0, 0.0, 0.0)), -1.0, 1.0));
				float geometryY = acos(clamp(dot(geometryDir, vec3(0.0, 1.0, 0.0)), -1.0, 1.0));
				float geometryZ = acos(clamp(dot(geometryDir, vec3(0.0, 0.0, 1.0)), -1.0, 1.0));
				float inverseX = acos(clamp(dot(inverseDir, vec3(1.0, 0.0, 0.0)), -1.0, 1.0));
				float inverseY = acos(clamp(dot(inverseDir, vec3(0.0, 1.0, 0.0)), -1.0, 1.0));
				float inverseZ = acos(clamp(dot(inverseDir, vec3(0.0, 0.0, 1.0)), -1.0, 1.0));

				sky += vec3(0.5, 0.0, 0.0) * (1.0 - smoothstep(PROBE_RADIUS * 0.45, PROBE_RADIUS, inverseX));
				sky += vec3(0.0, 0.5, 0.0) * (1.0 - smoothstep(PROBE_RADIUS * 0.45, PROBE_RADIUS, inverseY));
				sky += vec3(0.0, 0.0, 0.5) * (1.0 - smoothstep(PROBE_RADIUS * 0.45, PROBE_RADIUS, inverseZ));
				sky += vec3(4.0, 0.0, 0.0) * (1.0 - smoothstep(PROBE_RADIUS * 0.45, PROBE_RADIUS, geometryX));
				sky += vec3(0.0, 4.0, 0.0) * (1.0 - smoothstep(PROBE_RADIUS * 0.45, PROBE_RADIUS, geometryY));
				sky += vec3(0.0, 0.0, 4.0) * (1.0 - smoothstep(PROBE_RADIUS * 0.45, PROBE_RADIUS, geometryZ));

				float axisAngle = acos(clamp(dot(geometryDir, normalize(worldSunVector)), -1.0, 1.0));
				sky += vec3(4.0) * (1.0 - smoothstep(PROBE_RADIUS * 0.6, PROBE_RADIUS * 1.2, axisAngle));
				// The direction the giant is placed at, built the geometry's way rather than
				// the shader mod's: sunPosition arrives in the camera's own frame, so which
				// matrix turns it into a world direction is part of what is in question.
				vec3 sunByGeometry = normalize(vec3(
					dot(sunPosition, drawnBy * vec3(1.0, 0.0, 0.0)),
					dot(sunPosition, drawnBy * vec3(0.0, 1.0, 0.0)),
					dot(sunPosition, drawnBy * vec3(0.0, 0.0, 1.0))));
				float sunByGeometryAngle = acos(clamp(dot(geometryDir, sunByGeometry), -1.0, 1.0));
				sky += vec3(0.0, 4.0, 4.0) * (1.0 - smoothstep(PROBE_RADIUS * 0.6, PROBE_RADIUS * 1.2, sunByGeometryAngle));

				resolved = sky * max(0.0, 1.0 - 10.0 * blindness);
			#else
				resolved = SkyDither(gl_FragCoord.xy, SkyColor(worldDir))
					* max(0.0, 1.0 - 10.0 * blindness);
			#endif
		}
	#endif

	// The environment reflection is not applied here.
	//
	// It has a pass of its own, one later, because the buffer it has to read is
	// the resolved image - the one this pass is about to write - and a pass
	// cannot read what it is writing. Applying it here would also put it into
	// the history below, where the neighbourhood clamp pulls it back out again
	// every frame: that clamp is bounded by the variance of colortex0, and
	// colortex0 has no reflection in it.
	//
	// See composite3.fsh.

	// What the screen shows, which is the resolved frame unless the debug view
	// below is on. The history written underneath is the resolved frame either
	// way: a diagnostic must not change what it is diagnosing.
	vec3 shown = resolved;

	#ifdef TAA_DEBUG
		// Left half, what this pass was handed; right half, what it made of it.
		// See the note on TAA_DEBUG in lib/taa.glsl for how to read it.
		shown = gl_FragCoord.x < viewWidth * 0.5 ? currentRaw : resolved;
	#endif

	gl_FragData[0] = vec4(shown, 1.0);

	// The history written here is the resolved image, not the raw frame:
	// accumulating already-resolved frames is what gives the effect its
	// temporal reach.
	//
	// Written whether anti-aliasing is on or off. It used to be written only when
	// it was on, because nothing read the buffer otherwise - which stopped being
	// true when the environment reflection moved to its own pass, since that pass
	// reads this one for the world to trace over. Skipping the write left it
	// holding whatever the last frame with anti-aliasing on had put there. With
	// anti-aliasing off nothing below reads it, so this is a plain copy of the
	// current frame: the same thing the resolve produces when it has nothing to
	// accumulate onto.
	gl_FragData[1] = vec4(
		max(resolved, vec3(1.0e-7)),
		currentUsable ? 1.0 : 0.0);
}
