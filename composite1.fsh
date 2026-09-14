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

	vec3 history = texture(colortex3, previousScreenCoord).rgb;

	if (frameCounter < 2 || offScreen || behindCamera) {
		// Nothing trustworthy has been accumulated yet, or the pixel was not on
		// screen last frame.
		history = current;
	}

	history = clamp(
		history,
		neighborhoodMean - TAA_CLAMP * deviation,
		neighborhoodMean + TAA_CLAMP * deviation);

	resolved = mix(current, history, TAA_STRENGTH);

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
