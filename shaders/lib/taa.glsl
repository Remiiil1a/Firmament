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

// Temporal anti-aliasing.
//
// TAA renders each frame with a small sub-pixel offset that cycles through a
// fixed sequence, then averages consecutive frames together. Every frame
// therefore samples the scene from a slightly different position inside each
// pixel, and the average over several frames resolves detail that no single
// frame can - which is far cheaper than rendering at a higher resolution.
//
// The two halves of that live here and in composite1:
//
//  - TaaJitter() (below) is added to the clip position by the vertex shaders,
//    which is what offsets the sample position.
//  - The composite1 pass reprojects the previous frame's result onto the
//    current one and averages the two.
//
// Note that Steadfast has no motion vectors - nothing in the gbuffer passes
// knows how fast anything is moving - so the history is reprojected with the
// camera matrices alone. Anything that moves relative to the world (entities,
// water, particles, the held item) cannot be reprojected correctly, and is
// handled by rejecting history that does not match the current frame rather
// than by tracking it. See TAA_CLAMP.

// Whether to anti-alias the image over time.
//
// Off by default: it is the only effect here that trades image stability for
// smoothness, and what it does to a scene is a matter of taste. Turn it on and
// tune the options below to see what it does.
#define TAA_OFF 0
#define TAA_ON 1
#define TAA TAA_OFF // [TAA_OFF TAA_ON]

// How much of the accumulated history each frame keeps.
//
// Higher values resolve more detail and leave less noise, at the cost of
// ghosting behind anything that moves on its own, since there are no motion
// vectors to reproject those with.
#define TAA_STRENGTH 0.5 // [0.5 0.65 0.75 0.85 0.9 0.95]

// The radius of the sub-pixel jitter, in pixels.
//
// One pixel places each frame's sample anywhere within the pixel, which is what
// an anti-aliasing filter wants. Lower values trade smoothing for less visible
// flicker, and 0 turns the jitter off entirely - the resolve then has nothing
// to average, so the anti-aliasing is effectively disabled without the pass
// being skipped.
#define TAA_JITTER 0.5 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5]

// How many standard deviations of the current frame's neighbourhood the
// history is allowed to fall outside of.
//
// This is what stops a moving object from dragging its previous positions
// behind it, and it is also what keeps textures from being averaged into a
// smudge: a sample only survives if it looks like a plausible value for this
// pixel. Too tight and the image flickers, because legitimate history gets
// thrown away every frame; too loose and moving objects smear.
#define TAA_CLAMP 0.5 // [0.5 0.75 1.0 1.25 1.5 2.0 3.0]

// How much to sharpen the resolved image, to counter the softening that
// averaging frames together introduces.
#define TAA_SHARPEN 0.0 // [0.0 0.1 0.25 0.4 0.6 0.8 1.0]

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

// The Halton (2, 3) sequence. Successive samples fill the pixel in a
// well-distributed order, which matters because it takes several frames to
// build up a good average.
const vec2 TAA_SAMPLES[8] = vec2[8](
	vec2(0.500000, 0.333333),
	vec2(0.250000, 0.666667),
	vec2(0.750000, 0.111111),
	vec2(0.125000, 0.444444),
	vec2(0.625000, 0.777778),
	vec2(0.375000, 0.222222),
	vec2(0.875000, 0.555556),
	vec2(0.062500, 0.888889));

// This frame's sub-pixel offset, in normalized device coordinates, ready to be
// added to the clip position.
//
// It is scaled by the clip position's w so that it survives the perspective
// divide, which is what makes it a constant offset in pixels rather than in
// world space.
//
// Note that this is deliberately never applied in the shadow pass: the shadow
// map is a lookup table indexed by world position rather than something
// rendered from the camera, so jittering it would only add noise.
vec2 TaaJitter() {
	#if TAA == TAA_OFF
		return vec2(0.0);
	#else
		vec2 offset = TAA_SAMPLES[frameCounter % 8] - 0.5;
		return offset * (TAA_JITTER * 2.0 / vec2(viewWidth, viewHeight));
	#endif
}
