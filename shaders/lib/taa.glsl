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
//  - TaaJitter() (below) is added to the clip position by the four world
//    vertex shaders - lit.vsh, unlit.vsh, sky.vsh and clouds.vsh, all with the
//    same `gl_Position.xy += TaaJitter() * gl_Position.w` - and that is what
//    offsets the sample position.
//  - The composite1 pass reprojects the previous frame's result onto the
//    current one and averages the two.
//
// The reprojection has no *object* motion in it - the shader mod hands a pack the
// previous camera and its matrices and nothing per entity or per vertex - so
// anything moving relative to the world is handled by rejecting history that
// does not match the current frame rather than by tracking it. What the pack does
// have is one shared, well-defined camera reprojection, in /lib/reproject.glsl,
// which the resolve, the reflection's history and the motion blur all take their
// movement from.

// What this pass does with the frames it is given. **Off by default.**
//
// ON is the anti-aliasing: the gbuffer programs render with a sub-pixel offset
// that walks one step of a low-discrepancy sequence per frame, and the pass
// averages consecutive frames after reprojecting them onto the current one.
//
// OFF is close to a copy, so that the buffer flow through the pipeline does not
// change: composite1.fsh takes `resolved = currentUsable ? current : vec3(0.0)`
// and writes it to both colortex0 and colortex3, rather than doing the
// reprojection, the clamp and the history blend. "Close to", because a pixel
// the geometry left not-a-number still comes out black rather than as itself.
//
// **Why Off is still the default: a black blot.** Recorded here as the history
// of the decision, not as a diagnosis: it was reported, reproduced by the user,
// and chased through many batches before the chain that carries it was found -
// see PBR_PORTING.md 136 onwards, and the guards in composite1.fsh that came
// out of it. What is established is only the shape of the experiment: with this
// pass on, a small black region appears in the frame every now and then and
// grows; with it off, none appears at all, over versions of testing. That is a
// correlation and not a diagnosis, and the eight attempts recorded at the time
// failed to turn it into one - so the choice made then was to leave the pass
// available to whoever wants to look at it and take it out of the default path.
// It is not deleted because the buffer it writes, colortex3, is also the picture
// the environment reflection is traced over (composite3.fsh reads it): removing
// the pass means keeping that write, and a mistake there breaks something else
// entirely.
//
// **Anti-aliasing does not need it.** SMAA is the supported answer and is on the
// effect menu; what is lost by leaving this off is the temporal averaging of the
// dither, so the screen-space shadows, the ambient occlusion and the godrays
// keep their noise. See the recorded note at PBR_PORTING.md 163.
//
// The two numbers are frozen. TAA_ON was 1 before a second mode existed at all,
// and Iris keeps the value an option was set to, so renumbering it would silently
// change what an existing configuration means.
//#define TAA

// How much of the accumulated history each frame keeps, for a pixel that did not
// move since the previous frame.
//
// This is the option that decides how much of the noise in the image averages
// away: the dither of the screen-space shadows in the distance, and the sky's
// own. Raising it leaves less noise and resolves more detail, because a longer
// history is the only thing that can average a per-frame sample out at all -
// with a still camera the frame is a weighted average over roughly
// 1 / (1 - TAA_STRENGTH) frames, which is 4 at the default 0.75.
//
// It is no longer also the weight for a pixel that *did* move: composite1 keeps
// less of the history where the pixel moved - historyWeight is this value times
// mix(0.7, 1.0, stillness) - so raising this does not buy ghosting behind
// anything that moves on its own.
#define TAA_STRENGTH 0.75 // [0.5 0.65 0.75 0.85 0.9 0.95]

// The radius of the sub-pixel jitter, in pixels.
//
// The sample is placed at `taaJitterX / viewWidth * TAA_JITTER` and the same in
// Y, and shaders.properties builds those from taaJitterX/Y, which each swing
// across the full range -1 to 1. The pixel offset is therefore half this option
// times that range: 0.5 (the default) puts the sample between the pixel centre
// and its edge, and 1.0 covers the whole pixel. Lower values trade smoothing
// for less visible flicker, and 0 turns the jitter off entirely - the resolve
// then has no sub-pixel offset to average, so the anti-aliasing is effectively
// disabled without the pass being skipped (what is left of it is the temporal
// averaging of the dither, which does not need a spatial offset).
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
//
// Recorded: this is a #define in the file and not an option in the effect menu,
// so nothing in the GUI can turn it on - TAA_DEBUG appears under
// screen.DEBUG_VIEWS in shaders.properties so that the debug-view switch can
// reach it, but what actually enables it is editing this line back to an active
// #define and rebuilding. It is read with plain #ifdef in composite1.fsh rather
// than compared against a value, so leaving it commented out is the normal
// state and costs nothing.
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
// that no reprojection can be correct for. shaders.properties hands it to Voxy
// through that pack's taaOffset field (see voxy.json) as well as declaring it
// as uniform.vec2.taaJitter; the TAA section there is the sequence it is built
// from. Declared here unconditionally, so the uniform exists whether or not
// TaaJitter() below ever returns it.
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
//
// At this point in the file the value is in normalized device coordinates and
// already carries TAA_JITTER's scaling (shaders.properties divides by viewWidth
// and viewHeight on the way in), and the answer is zero whenever the mode is not
// TAA_ON. The four world vertex shaders call this and scale it by w, so with the
// mode off they all add nothing and the shadow pass, which never calls it, stays
// unjittered either way.
vec2 TaaJitter() {
	#ifdef TAA
		return taaJitter;
	#else
		// With the anti-aliasing off there is nothing left to jitter for.
		return vec2(0.0);
	#endif
}
