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
// The gbuffer programs render the world with a sub-pixel offset that cycles
// through a Halton sequence (see /lib/taa.glsl), and this pass is what turns
// those offset frames into a single smoother image, by averaging each one with
// a history of the ones before it.
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

// Declared once, unconditionally and outside the conditional below: Iris reads
// this directive from the raw source text, so having one in each branch of an
// #if would leave it unclear which one applies.
//
// colortex3 is left untouched when anti-aliasing is off, which costs nothing
// since nothing reads it in that case.
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

	vec3 resolved;

	#if TAA == TAA_OFF
		// The pass runs even with anti-aliasing switched off, so that the buffer
		// flow through the pipeline does not change; with it off, this is just a
		// copy.
		resolved = current;
	#else
	ivec2 screenSize = ivec2(viewWidth, viewHeight);

	// Reconstruct the absolute world position of this fragment, so that the
	// previous frame's camera can be applied to it. Working in absolute terms
	// rather than camera-relative is what makes this survive the camera moving.
	float depth = texelFetch(depthtex0, pixel, 0).r;

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
	bool offScreen = any(lessThan(previousScreenCoord, vec2(0.0)))
		|| any(greaterThan(previousScreenCoord, vec2(1.0)));
	bool behindCamera = previousClipPos.w <= 0.0;

	// Gather the neighbourhood of the current frame, which serves two purposes:
	// it bounds what the history is allowed to say, and it provides the blurred
	// version used for sharpening below.
	vec3 neighborhoodSum = vec3(0.0);
	vec3 neighborhoodSquareSum = vec3(0.0);

	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			ivec2 offsetPixel = clamp(pixel + ivec2(x, y),
				ivec2(0), screenSize - 1);
			vec3 neighbor = texelFetch(colortex0, offsetPixel, 0).rgb;

			neighborhoodSum += neighbor;
			neighborhoodSquareSum += neighbor * neighbor;
		}
	}

	vec3 neighborhoodMean = neighborhoodSum / 9.0;

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
		neighborhoodSquareSum / 9.0 - neighborhoodMean * neighborhoodMean,
		vec3(0.0));
	vec3 deviation = sqrt(variance);

	vec3 history = HistorySample(previousScreenCoord);

	if (frameCounter < 2 || offScreen || behindCamera) {
		// Nothing trustworthy has been accumulated yet, or the pixel was not on
		// screen last frame.
		history = current;
	}

	history = clamp(
		history,
		neighborhoodMean - TAA_CLAMP * deviation,
		neighborhoodMean + TAA_CLAMP * deviation);

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

	resolved = mix(current, history, historyWeight);

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

	gl_FragData[0] = vec4(resolved, 1.0);

	#if TAA != TAA_OFF
		// The history written here is the resolved image, not the raw frame:
		// accumulating already-resolved frames is what gives the effect its
		// temporal reach.
		gl_FragData[1] = vec4(resolved, 1.0);
	#endif
}
