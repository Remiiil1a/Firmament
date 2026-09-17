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

// Added 2026-09-16 by Remiiil1a for Firmament - v0.3 (edit of coderbot's Steadfast).

// Screen-space shadows.
//
// The shadow map only covers a fixed distance around the player, and terrain
// beyond it - Distant Horizons' level of detail terrain, Voxy's, and in general
// anything drawn past the shadow distance - gets light from the sun and casts
// none of its own. On a landscape with hills that is the most conspicuous thing
// about the distance: a valley sits in full sun no matter what stands between it
// and the sun.
//
// This walks a ray from the fragment towards the sun through the depth buffer
// instead. Whatever the buffer says is in the way, is in the way - and the depth
// buffer holds everything that writes depth, so terrain drawn by another mod
// casts shadows here just like the pack's own does.
//
// It is deliberately only used past the shadow map's reach. Inside that reach
// the shadow map is both more accurate and already paid for, and applying this
// on top of it would darken the same shadow twice.

// Whether to cast shadows for terrain the shadow map does not reach.
//
// On by default: without it the distance is lit flat, which reads as a seam at
// the edge of the shadow distance.
//
// The #ifdef is not decoration: Iris only treats a bare #define as a boolean
// option if the macro is referenced by an #ifdef or #ifndef somewhere.
#define SCREENSPACE_SHADOWS
#ifdef SCREENSPACE_SHADOWS
	// How dark the shadows get, where 1.0 is as dark as the sun's own
	// contribution could be. It is applied to the whole colour rather than to
	// the sunlight alone, because by the time this pass runs the two are already
	// added together - so a value near 1.0 also takes some sky light with it.
	#define SSS_STRENGTH 0.75 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.9 1.0]

	// How many steps the ray takes. More steps reach further without the gaps
	// between them growing wide enough to let terrain through.
	#define SSS_STEPS 12 // [4 6 8 12 16 24]

	// How far the ray reaches, in blocks. A valley floor sits below a ridge
	// several dozen blocks away, so this has to be generous to catch the shadow
	// that matters most; the cost is one depth sample per step.
	#define SSS_LENGTH 48.0 // [16.0 24.0 32.0 48.0 64.0 96.0 128.0]

	// How much of the distance to the receiver one step covers, as a fraction.
	//
	// The whole ray is this many steps of it, so a receiver 200 blocks away gets a
	// ray a few dozen blocks long and one 20 blocks away gets one a few blocks
	// long - which is the scale the shadow of a hill actually sits at, and, more
	// to the point, keeps the samples evenly spaced in pixels rather than in
	// blocks.
	#define SSS_SCREEN_STEP 0.02

	// The loop below needs a constant bound, so the option above selects how many
	// of a fixed set of iterations actually run.
	const int SSS_STEP_LIMIT = 24;
#endif

// The frame number, so that the dither below can move from frame to frame.
uniform int frameCounter;

// Cheap per-pixel value in 0..1, used to offset the first step of the ray so that
// neighbouring pixels do not march through the same sample positions.
//
// The offset also moves from one frame to the next, and that is the whole reason
// the temporal filter can do anything about this noise. A value that depended on
// the pixel alone is the *same* value in the history as it is in the current
// frame, so averaging the two averages the noise with itself and keeps it in
// full: it is a fixed pattern baked into the image, and no amount of history
// removes a pattern that never changes. Noise is only removable over time if it
// is different every frame, which is what the shift below makes it.
//
// Sundial does exactly this to the dither its own screen-space effects use
// (bayer64Temporal, in libs/Common.glsl): an ordered pattern shifted by an
// irrational fraction of its range per frame, so that a run of frames fills the
// range evenly instead of repeating. The constant here is the same golden-ratio
// step they approximate with sqrt(0.4), and the 64-frame wrap keeps the shifted
// value exactly representable in a float.
float SssScreenNoise(vec2 fragCoord) {
	float noise = fract(sin(dot(fragCoord, vec2(12.9898, 78.233))) * 43758.5453);
	float shift = float(frameCounter % 64) * 0.618034;
	return fract(noise + shift);
}

// The shadow at one fragment: 1.0 where the sun reaches it, 0.0 where something
// in the depth buffer is in the way.
//
// viewPos is this fragment's position in view space and lightDirection points
// from it towards the sun, also in view space. No surface normal is needed: the
// ray only asks whether something stands between this point and the light.
#ifdef SCREENSPACE_SHADOWS
	float ScreenSpaceShadow(
		sampler2D depthTexture,
		mat4 projection,
		mat4 projectionInverse,
		vec3 viewPos,
		vec3 lightDirection
	) {
		// The ray advances a fixed *fraction* of the distance to the receiver per
		// step, rather than a fixed number of blocks, and the option above caps the
		// total. Stepping fixed blocks made the sample spacing in *pixels* wildly
		// uneven: close in, one step crossed several pixels at once and the shadows
		// came out as streaks that did not line up with what was casting them; far
		// out, several steps landed inside one pixel and the ray kept sampling the
		// same piece of depth buffer. Both are the misalignment and the banding.
		// A fraction of the distance is even in screen space at every range. This is
		// how Mellow Shader's and Sundial's screen-space shadows both step, in
		// effect - they do it in projected coordinates, which is the same thing.
		float dither = SssScreenNoise(gl_FragCoord.xy);

		float stepLength = min(
			max(length(viewPos), 16.0) * SSS_SCREEN_STEP,
			SSS_LENGTH / float(SSS_STEPS));

		for (int i = 0; i < SSS_STEP_LIMIT; i++) {
			if (i >= SSS_STEPS) {
				break;
			}

			// The first sample is offset a random fraction of a step per pixel, so
			// that neighbouring pixels do not step through the same sample positions
			// and the shadow boundary does not quantise into bands. Both of the
			// packs this follows do the same thing, for the same reason.
			//
			// It moves every frame as well - see SssScreenNoise - which is what
			// leaves the temporal filter in composite1 something to average: with
			// the dither standing still, the noise reached the history unchanged
			// and stayed in the image in full.
			float travel = (float(i + 1) + dither) * stepLength;
			vec3 point = viewPos + lightDirection * travel;
			vec4 projected = projection * vec4(point, 1.0);

			if (projected.w <= 0.0) {
				break;
			}

			vec2 sampleCoord = (projected.xy / projected.w) * 0.5 + 0.5;

			// Leaving the screen ends the walk: there is nothing left to ask. The
			// ray also stops rather than treating the edge as an occluder, which
			// would draw a shadow along the sides of the screen.
			if (any(lessThan(sampleCoord, vec2(0.0)))
				|| any(greaterThan(sampleCoord, vec2(1.0)))) {
				break;
			}

			float sceneDepth = texture(depthTexture, sampleCoord).r;

			// The sky is nothing to be blocked by.
			if (sceneDepth >= 1.0) {
				continue;
			}

			vec4 sceneH = projectionInverse * vec4(
				sampleCoord * 2.0 - 1.0, sceneDepth * 2.0 - 1.0, 1.0);
			vec3 scenePos = sceneH.xyz / sceneH.w;

			// View space looks down the negative Z axis, so a gap is how much
			// closer to the camera the geometry at this sample is than the ray is.
			float gap = point.z - scenePos.z;

			// The occlusion only counts when what the ray found is *right there*,
			// within a thickness of it - not merely closer to the camera.
			//
			// That distinction is the whole difference between shadows cast by
			// terrain and shadows cast by everything else on screen. A hill the ray
			// runs into is a solid mass whose surface sits almost exactly where the
			// ray reaches it, so its gap is a block or two. An entity, a dropped
			// item, the held block, an animal walking past: all of those sit
			// hundreds of blocks nearer to the camera than the distant terrain the
			// ray is tracing towards, and treating "nearer" as "in the way" made
			// every one of them throw a shadow across the landscape behind it.
			//
			// The lower bound is the depth buffer's own precision, which is coarse
			// out here - every one of these values sits in the last percent of the
			// range - so it grows with how far the ray has travelled, or the surface
			// shadows itself and the distance fills with noise.
			float tolerance = max(0.05, travel * 0.02);
			float thickness = 2.0 + travel * 0.02;

			if (gap > tolerance && gap < thickness) {
				return 0.0;
			}
		}

		return 1.0;
	}
#endif
