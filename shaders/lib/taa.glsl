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

// What this pass does with the frames it is given. **Off by default.**
//
// ON is the anti-aliasing: the gbuffer programs render with a sub-pixel offset
// that walks one step of a low-discrepancy sequence per frame, and the pass
// averages consecutive frames after reprojecting them onto the current one.
//
// DENOISE averages each pixel with its own past, and with nothing else - the
// history is read at this pixel's index rather than at a reprojected one, and the
// average is only taken where the pixel has not moved, so nothing is averaged
// across a surface boundary and nothing is carried from one pixel to another.
//
// OFF is a copy, so that the buffer flow through the pipeline does not change.
//
// **Why Off is the default, and why all of this is grouped under the development
// menu as experimental: a black blot.** It has been reported, reproduced by the
// user, and chased through eight batches without the source being found - see
// PBR_PORTING.md 136 onwards. What is known about it is only the shape of the
// experiment: with this pass on, a small black region appears in the frame every
// now and then and grows; with it off, none appears at all, over versions of
// testing. That is a correlation and not a diagnosis, and eight attempts to turn
// it into one failed - so the honest thing is to leave the pass available to
// whoever wants to look at it and take it out of the default path. It is not
// deleted because the buffer it writes, colortex3, is also the picture the
// environment reflection is traced over: removing the pass means keeping that
// write, and a mistake there breaks something else entirely.
//
// **Anti-aliasing does not need it.** SMAA is the supported answer and is on the
// effect menu; what is lost by leaving this off is the temporal averaging of the
// dither, so the screen-space shadows, the ambient occlusion and the godrays
// keep their noise. See PBR_PORTING.md 163.
//
// The numbers are deliberately not in menu order: TAA_ON was 1 before DENOISE
// existed, and Iris keeps the value an option was set to, so renumbering it would
// silently change what an existing configuration means.
#define TAA_OFF 0
#define TAA_ON 1
#define TAA_DENOISE 2
#define TAA TAA_OFF // [TAA_OFF TAA_DENOISE TAA_ON]

// How much of the accumulated history each frame keeps, for a pixel that did not
// move since the previous frame.
//
// This is the option that decides how much of the noise in the image averages
// away: the dither of the screen-space shadows in the distance, and the sky's
// own. Raising it leaves less noise and resolves more detail, because a longer
// history is the only thing that can average a per-frame sample out at all.
//
// It is no longer also the weight for a pixel that *did* move: composite1 keeps
// less of the history where the pixel moved, so raising this does not buy
// ghosting behind anything that moves on its own.
#define TAA_STRENGTH 0.75 // [0.5 0.65 0.75 0.85 0.9 0.95]

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

// How dark the history is allowed to be, as a fraction of the mean of the current
// frame's neighbourhood.
//
// 0.0 is no floor at all, which is what the code did before this option existed.
// 0.25 means the history may never be darker than a quarter of what the current
// frame shows around this pixel.
//
// The statistical bound above is the one that fails, and this is what it fails at.
// Its lower end is "the neighbourhood mean minus TAA_CLAMP deviations", floored at
// zero, and at a block's edge the neighbourhood holds a bright face and whatever
// is dark beside it: the deviation is large, the lower end goes below zero, the
// floor catches it, and what is left is a lower bound of zero - which is to say,
// no lower bound at all.
//
// An earlier attempt at this put the floor at the neighbourhood's darkest value
// instead, and that is a no-op at exactly the place it was meant for: at an edge
// the darkest thing in the neighbourhood is the dark side of the edge, it sits
// below the statistical lower end, and the maximum of the two is therefore the
// statistical one. The floor has to be measured against something the blot cannot
// drag down, and the mean of the current frame's neighbourhood is that - the blot
// lives in the history, and this bound is read from the frame.
//
// What it is for is a blot that lives in the history *alone*. The observation that
// put it here is that the frame is clean on the side of the resolve that shows the
// frame, and dark on the side that shows the result: the black was never in the
// frame at all. A black history is fetched through a Catmull-Rom filter that
// reaches two texels, so the pixels beside it go dark the frame after, and each of
// those is again a black history over a clean frame. Nothing in that loop needs
// the frame to be wrong, so no bound read from the history can stop it and no
// amount of speed limiting can either - every step of it is small. A bound read
// from the frame, every frame, is what stops it.
//
// The cost is that a genuinely black feature on a bright surface is lifted to this
// fraction of its surroundings, which is why the option is a slider: 0.0 is the
// old behaviour, and lower values trade less lifting for less protection.
// See PBR_PORTING.md 157.
#define TAA_DARK_FLOOR 0.25 // [0.0 0.05 0.1 0.15 0.25 0.4 0.6 1.0]

// How much to sharpen the resolved image, to counter the softening that
// averaging frames together introduces.
#define TAA_SHARPEN 0.0 // [0.0 0.1 0.25 0.4 0.6 0.8 1.0]

// Show the picture this pass was handed on the left of the screen, and the
// picture it produced on the right.
//
// It exists because three attempts at the black blot that appears at a long
// history have all been made by reading the code for somewhere a value could stop
// being a number, and all three found real holes without the blot going away. The
// question that has never been answered is the cheap one: is the black already in
// the frame the geometry drew, or does this pass put it there? Everything
// upstream of this pass is the geometry's problem and everything downstream is
// the resolve's, and the two are worth telling apart before another guard is
// written for either.
//
// Left half: colortex0 as the geometry left it, before anything here touches it -
// including before the repair below, so that a value that is not a number shows
// as the black it is rather than as the patch this pass would have applied.
// Right half: the resolved frame, which is what the screen usually shows.
//
// Which side the blot is on is the whole reading: the left means the source is
// upstream, the right means it is this pass's history, and both means the source
// is upstream and the history is keeping it. See PBR_PORTING.md 133.
//#define TAA_DEBUG

uniform int frameCounter;
uniform float viewWidth;
uniform float viewHeight;

// This frame's sub-pixel offset, in normalized device coordinates, computed in
// shaders.properties rather than here.
//
// It is a custom uniform so that the very same number can reach geometry this
// file never sees. Voxy draws its own terrain from its own vertex shader, which
// cannot include this file, so a value computed here could only ever offset the
// geometry drawn by the shaders that do include it - and a frame whose geometry
// is jittered by two different amounts, or by one amount and not at all, is one
// that no reprojection can be correct for. See the TAA section of
// shaders.properties for the sequence it is built from.
uniform vec2 taaJitter;

// The offset to add to the clip position.
//
// The caller scales it by the clip position's w, so that it survives the
// perspective divide, which is what makes it a constant offset in pixels rather
// than in world space.
//
// Note that this is deliberately never applied in the shadow pass: the shadow
// map is a lookup table indexed by world position rather than something
// rendered from the camera, so jittering it would only add noise.
vec2 TaaJitter() {
	#if TAA == TAA_ON
		return taaJitter;
	#else
		// Both of the others: with the anti-aliasing off there is nothing to
		// jitter for, and in DENOISE the point of the mode is not to move the
		// sample at all.
		return vec2(0.0);
	#endif
}
