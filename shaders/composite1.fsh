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
const int colortex3Format = R11F_G11F_B10F;

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

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

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

// The sky light the reflection is faded out by, written by the surface programs
// and not touched since.
uniform sampler2D colortex2;

// Declared once, unconditionally and outside the conditional below: Iris reads
// this directive from the raw source text, so having one in each branch of an
// #if would leave it unclear which one applies.
//
// colortex3 is written whether anti-aliasing is on or off. It used to be skipped
// when it was off, on the grounds that nothing read the buffer in that case -
// which stopped being true when the environment reflection moved into a pass of
// its own, because that pass reads this one for the world to trace over. See the
// note at the write itself.
/* DRAWBUFFERS:03 */

// The previous frame's resolved image at the given screen position, read with a
// Catmull-Rom filter rather than with the bilinear one that a plain texture()
// would use.
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

	vec3 color = texture(colortex3, vec2(middle.x, middle.y)).rgb * (w12.x * w12.y)
		+ texture(colortex3, vec2(middle.x, low.y)).rgb * (w12.x * w0.y)
		+ texture(colortex3, vec2(low.x, middle.y)).rgb * (w0.x * w12.y)
		+ texture(colortex3, vec2(high.x, middle.y)).rgb * (w3.x * w12.y)
		+ texture(colortex3, vec2(middle.x, high.y)).rgb * (w12.x * w3.y);

	// The taps left out have weight too, so the result is normalised by the sum
	// of the ones that were kept rather than trusting them to add up to one.
	float total = w12.x * w12.y
		+ w12.x * w0.y + w0.x * w12.y
		+ w3.x * w12.y + w12.x * w3.y;

	return color / max(total, 1.0e-4);
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
	// negation is the check. See PBR_PORTING.md 131.
	bool currentUsable = dot(current, current) < 1.0e18;

	vec3 resolved;

	#if TAA == TAA_OFF
		// The pass runs even with anti-aliasing switched off, so that the buffer
		// flow through the pipeline does not change; with it off, this is just a
		// copy.
		resolved = currentUsable ? current : vec3(0.0);
	#elif TAA == TAA_DENOISE
		// Denoising: a pixel averaged with the same surface point from the frame
		// before, by one tap and with no bound on what that sample may say.
		//
		// This is the whole of what the dither needs. The screen-space shadows, the
		// ambient occlusion and the godrays scatter their samples differently every
		// frame *at a given pixel*, so averaging a pixel over frames is what removes
		// the noise - the same reason the mode below does it, reached without most
		// of what that mode needs.
		//
		// What is left out, and why: there is no neighbourhood and there is no
		// clamp, so nothing here has to decide which history values are plausible
		// and there is no bound for a bad one to pass or fail; and the history
		// arrives through one bilinear tap rather than through the Catmull-Rom
		// filter the mode below uses, which reaches two texels and is what carries
		// a dark pixel into the pixels beside it. A bad sample here can therefore
		// only sit at the point it was sampled at. It also cannot lock: every frame
		// mixes it with a current frame, so it fades over the frames that follow.
		//
		// The reprojection is kept, and that is the one piece of the mode below this
		// does take. Without it the average is between this pixel and whatever used
		// to be behind it, and since the camera moves that is a different surface
		// from one frame to the next: the two are mixed and what is seen is a double
		// image, which is far worse than the softening it costs the denoising. See
		// PBR_PORTING.md 161.
		//
		// TAA_STRENGTH is how long the average is in both modes.
		vec3 denoiseHistory;

		float denoiseDepth = texelFetch(depthtex0, pixel, 0).r;
		vec3 denoiseNdc = vec3(screenCoord * 2.0 - 1.0, denoiseDepth * 2.0 - 1.0);
		vec4 denoiseViewH = gbufferProjectionInverse * vec4(denoiseNdc, 1.0);
		vec3 denoiseViewPos = denoiseViewH.xyz / denoiseViewH.w;
		vec3 denoiseWorldPos =
			(gbufferModelViewInverse * vec4(denoiseViewPos, 1.0)).xyz + cameraPosition;
		vec4 denoiseClip = gbufferPreviousProjection * (gbufferPreviousModelView
			* vec4(denoiseWorldPos - previousCameraPosition, 1.0));
		vec2 denoiseCoord = (denoiseClip.xy / denoiseClip.w) * 0.5 + 0.5;

		// Written as "is it inside the frame", then negated, so that a coordinate
		// that is not a number fails it - the same test the mode below makes, and
		// for the same reason.
		bool denoiseOffScreen =
			!(all(greaterThanEqual(denoiseCoord, vec2(0.0)))
				&& all(lessThanEqual(denoiseCoord, vec2(1.0))))
			|| denoiseClip.w <= 0.0;

		// Fetched at this pixel's own index, and not at denoiseCoord.
		//
		// The reprojected coordinate is still computed, because how far it lies
		// from this pixel is the only measure of "did this pixel move" there is
		// without motion vectors - but the sample comes from where this pixel is.
		// That is the whole of what keeps a dark value where it is: whatever goes
		// wrong upstream, what this reads is the same pixel's own past, so a good
		// reprojection and a bad one both leave it here.
		denoiseHistory = (frameCounter < 2) ? current : texelFetch(colortex3, pixel, 0).rgb;

		// The same two tests the mode below applies to its history: a value that is
		// not a number would be carried forward for ever, and an exact zero is the
		// shape this buffer leaves of a value it could not store - it is
		// R11F_G11F_B10F, which has no encoding for a NaN.
		if (!(dot(denoiseHistory, denoiseHistory) < 1.0e18)) {
			denoiseHistory = current;
		}

		if (denoiseHistory == vec3(0.0)) {
			denoiseHistory = current;
		}

		// And how much of it to keep: nothing at all where the pixel moved.
		//
		// This is what makes the mode usable. Averaging a pixel with its own past
		// is only an average of one thing while the pixel is showing the same
		// surface; the moment the camera turns, the thing behind the pixel is
		// another surface, and averaging the two is a double image - which is what
		// the previous version of this mode did, and it was reported as severe.
		// The reprojected coordinate answers it: if it and this pixel are in the
		// same place, whatever is here was here last frame too. Where it is not,
		// the current frame is passed through on its own - no denoising while
		// moving, and nothing smeared either.
		//
		// Guarded because it is built from the reprojected coordinate, and a
		// coordinate that is not a number would make the weight one, which is a NaN
		// written into both buffers.
		float denoiseWeight = 0.0;

		if (!denoiseOffScreen) {
			vec2 denoiseVelocity =
				(screenCoord - denoiseCoord) * vec2(viewWidth, viewHeight);
			denoiseWeight = TAA_STRENGTH * exp(-dot(denoiseVelocity, denoiseVelocity));
		}

		if (!(denoiseWeight >= 0.0 && denoiseWeight <= 1.0)) {
			denoiseWeight = 0.0;
		}

		resolved = mix(current, denoiseHistory, denoiseWeight);
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
	// PBR_PORTING.md 119.
	//
	// The jitter belongs to the current frame's sampling, not to the history's
	// indexing: the frames that carry it are the ones being averaged, and the
	// average is what removes it.
	vec3 ndcPos = vec3(screenCoord * 2.0 - 1.0, depth * 2.0 - 1.0);
	vec4 viewPosH = gbufferProjectionInverse * vec4(ndcPos, 1.0);
	vec3 viewPos = viewPosH.xyz / viewPosH.w;
	vec3 cameraRelativePos = (gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;
	vec3 worldPos = cameraRelativePos + cameraPosition;

	// Where this point was on screen last frame.
	vec3 previousCameraRelativePos = worldPos - previousCameraPosition;
	vec4 previousClipPos = gbufferPreviousProjection
		* (gbufferPreviousModelView * vec4(previousCameraRelativePos, 1.0));
	vec2 previousScreenCoord =
		(previousClipPos.xy / previousClipPos.w) * 0.5 + 0.5;

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
	// again as the view turns. See PBR_PORTING.md 129.
	bool offScreen = !(all(greaterThanEqual(previousScreenCoord, vec2(0.0)))
		&& all(lessThanEqual(previousScreenCoord, vec2(1.0))));
	bool behindCamera = previousClipPos.w <= 0.0;

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

	// No usable neighbour at all leaves it at its starting value, which is not a
	// bound a colour can be clamped to. The centre pixel is the one value that is
	// certainly here.
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
	// this buffer cannot store: colortex3 is R11F_G11F_B10F, which has no encoding
	// for a NaN or an infinity, so a value that is not a number is written as an
	// ordinary zero and read back the next frame looking like a pixel that is
	// black. Nothing in the clamp below can tell that zero from a real one, because
	// every bound there is built to allow black - a shadow is black, and the lower
	// end is floored at zero on purpose.
	//
	// An exact zero is what it is looking for and not "very dark", because very
	// dark is a shadow and this is not: it is the shape a value takes when the
	// buffer had to round it away. A pixel that was genuinely black last frame
	// takes the current frame here instead of the history, so it stops
	// accumulating for as long as it stays black - a little of the dither is left
	// in the darkest parts of the image, which is the price of a blot that
	// otherwise never stops. See PBR_PORTING.md 159.
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
	// pass and not the geometry. See PBR_PORTING.md 134.
	vec3 historyLower = max(neighborhoodMean - TAA_CLAMP * deviation, vec3(0.0));
	vec3 historyUpper = neighborhoodMean + TAA_CLAMP * deviation;

	// A floor under the lower bound, measured against the current frame's mean and
	// not against its darkest value - see TAA_DARK_FLOOR in lib/taa.glsl for why
	// the darkest value is a no-op here, and for the loop in the history alone that
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
	historyLower = max(historyLower, neighborhoodMean * TAA_DARK_FLOOR);
	historyUpper = min(historyUpper, neighborhoodMaximum);

	history = clamp(history, historyLower, historyUpper);

	// How far this pixel moved since the previous frame, in pixels.
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
	// So TAA_STRENGTH is now the weight for a pixel that did not move at all, and
	// a pixel that moved at walking speed keeps seven tenths of it. That is what
	// lets the option default high: raising it buys noise reduction while standing
	// still without buying ghosting while moving.
	float stillness = exp(-dot(velocity, velocity));
	float historyWeight = TAA_STRENGTH * mix(0.7, 1.0, stillness);

	// The weight is checked before it is used, and this is the last place in this
	// pass where a value that is not a number can still get in.
	//
	// The frames either side of this pass cannot carry one, and that is not an
	// assumption about the effects upstream - it is the buffer formats. colortex0
	// and colortex3 are both R11F_G11F_B10F, an unsigned format with no encoding
	// for a NaN or an infinity, so whatever the surfaces write arrives here finite
	// and so does the history. Everything that could produce one is therefore
	// arithmetic inside this function, and velocity is the arithmetic left:
	// previousScreenCoord is previousClipPos.xy / previousClipPos.w, and a clip
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
	// that starts somewhere and grows. See PBR_PORTING.md 158.
	//
	// Zero rather than anything else: a weight of zero means this pixel is taken
	// from the current frame and not from the history at all, which is the one
	// answer that cannot be wrong about a frame that is known to be finite.
	if (!(historyWeight >= 0.0 && historyWeight <= 1.0)) {
		historyWeight = 0.0;
	}

	resolved = mix(current, history, historyWeight);

	// And the result, before it is written to either buffer - the same guard the
	// reflection's own history has in composite3, and missing here until now.
	// Everything above is finite by the argument in the note, so this cannot fire
	// today; it is here because "everything above is finite" is a claim about six
	// other expressions, and the cost of being wrong about one of them is a black
	// blot that the clamps are structurally unable to catch.
	if (!(dot(resolved, resolved) < 1.0e18)) {
		resolved = current;
	}

	// Averaging frames together softens the image, which is the price of the
	// anti-aliasing; a little sharpening puts the edge definition back without
	// reintroducing the aliasing.
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

			resolved = SkyDither(gl_FragCoord.xy, SkyColor(worldDir))
				* max(0.0, 1.0 - 10.0 * blindness);
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
	gl_FragData[1] = vec4(resolved, 1.0);
}
