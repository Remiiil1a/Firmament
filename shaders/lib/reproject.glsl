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

// Added 2026-09-26 by Remiiil1a for Firmament - v0.8.

// Where a world point was on the screen in the previous frame, and how far this
// pixel has moved since.
//
// This is the pack's motion vector, and there is exactly one of it. Before batch
// 353 the same arithmetic was written out in more than one place - in composite1's
// anti-aliasing mode, in composite3 for the reflection's own history, and in the
// motion blur - and three copies of a reprojection is three places to fix the next
// time one of them is found to be wrong. They are one function now; see
// PBR_PORTING.md 211 and MOTION_VECTORS_TAA_PLAN.md. (The batch number is recorded
// as it stands and is not evidence either way for the count; what the code shows
// is the three callers listed at the bottom of this note.)
//
// ⚠️ What this is NOT is object motion. The shader mod hands a pack the previous
// camera and the previous matrices and nothing else - no previous position per
// vertex and none per entity - so a thing that moved relative to the world cannot
// be reprojected from here. Motion relative to the world is dealt with by
// rejecting history that does not match the current frame, not by tracking it.
// That is a limit of the interface rather than of this file, and the plan records
// it as one.
//
// ⚠️ What it does NOT need, and must not be given:
//
//  * The previous frame's depth. The history is reprojected by position, not by
//    comparing two depth buffers, so nothing here reads one.
//  * **The sub-pixel jitter, subtracted.** The arithmetic makes it look as though
//    the current frame's jitter should be taken back out of the coordinate first.
//    It must not be. Doing so makes the position the history is read from depend
//    on this frame's jitter, and since the history accumulates at the pixel's own
//    index, the picture held in it is displaced further every frame in that
//    frame's jitter direction. It does not settle - under a still camera it
//    becomes an oscillation of about the jitter times 1 / (1 - TAA_STRENGTH), and
//    it reads as the whole picture shaking. It was tried and reverted; see
//    PBR_PORTING.md 119, and the full note where the anti-aliasing mode calls
//    this.
//
// ⚠️ This file declares no uniforms of its own, on purpose: the programs that
// include it already declare these, and a second declaration of the same uniform
// in one program does not compile. It must therefore be included *after* the
// caller has declared:
//
//     mat4 gbufferPreviousProjection
//     mat4 gbufferPreviousModelView
//     vec3 previousCameraPosition
//     float viewWidth, viewHeight
//
// This replaces two measurements that used to be added together - a translation
// projected by hand and a rotation compared by direction - and with them the turn
// dead zone the rotation half needed. MOTION_BLUR_TURN_MIN_PIXELS, which the note
// next to this one used to cite for that dead zone, is not in the pack any more;
// what is left of the split is `travelView` in motion_blur.glsl, which is the
// rotation-only part.
//
// Three programs do that: composite1 (both of its modes - the previous-frame
// matrices and previousCameraPosition are declared right above the include, and
// viewWidth and viewHeight arrive through lib/taa.glsl, which composite1 includes
// before this file), composite3 (the reflection's history, same declarations), and
// environment/effects/motion_blur.glsl. That last one is the exception the note
// here used to say did not exist: it includes this file too, at the point where it
// has all four names in hand, and it takes `previousCoord` from it and derives its
// own screen-space displacement instead of using `velocityPixels` - because its
// offset is a fraction of the screen rather than pixels. The reason recorded for
// keeping it out was that the blur reprojects a *direction* under the previous
// frame's rotation with the camera's translation left out; what the code does now
// is hand this function a point whose translation has been cancelled
// (worldPos + (previousCameraPosition - cameraPosition), guarded by
// MOTION_BLUR_HAND_DEPTH) rather than avoiding the function.

#ifndef REPROJECT_INCLUDED
#define REPROJECT_INCLUDED

// One reprojection's worth of answers.
//
// `previousCoord` is where the world point was on screen a frame ago, in the
// 0.0-to-1.0 space the scene textures are sampled in. `velocityPixels` is how far
// this pixel has moved since, in pixels of the current frame.
//
// The two flags are kept apart rather than folded into one, because the callers
// fold them differently: composite1 asks each on its own and only then combines
// them with the frame counter, while composite3 wants the single question "is
// there a history to read at all". Folding them here would decide that for both.
struct Reprojection {
	vec2 previousCoord;
	vec2 velocityPixels;
	bool offScreen;
	bool behindCamera;
};

// `worldPosition` is absolute - camera position not subtracted - because that is
// what makes the reprojection survive the camera moving: the point stays where it
// is and the previous camera is the thing that changed. Both callers build it
// this way for the same reason.
Reprojection ReprojectWorldPosition(vec3 worldPosition, vec2 screenCoord) {
	Reprojection result;

	vec3 previousCameraRelativePos = worldPosition - previousCameraPosition;
	vec4 previousClipPos = gbufferPreviousProjection
		* (gbufferPreviousModelView * vec4(previousCameraRelativePos, 1.0));

	result.previousCoord =
		(previousClipPos.xy / previousClipPos.w) * 0.5 + 0.5;

	result.behindCamera = previousClipPos.w <= 0.0;

	// Written as "is it inside the frame", then negated, rather than as "is it
	// outside it". The two say the same thing about a number and different things
	// about a NaN, which is the whole point of spelling it this way: every
	// comparison against a NaN is false, so a coordinate that came out of a
	// division by zero is neither less than zero nor greater than one, and an
	// outside test written the other way round lets it through. What is then
	// sampled is not a colour, and the history buffer does not fade - the resolve
	// writes its own result back for the next frame to read - so a value that is
	// not a number spreads outward through the Catmull-Rom taps until it covers
	// the screen. It is intermittent because it needs the reprojection to land on
	// a w of zero, which is why it reads as a black blot that comes and goes as
	// the view turns. See PBR_PORTING.md 129.
	//
	// What this does and does not do: a NaN coordinate sets offScreen, so a caller
	// that tests offScreen is safe from it. A caller that uses previousCoord
	// without testing sets its own trap - see how composite1 treats the same value
	// before it reaches HistorySample.
	result.offScreen =
		!(all(greaterThanEqual(result.previousCoord, vec2(0.0)))
			&& all(lessThanEqual(result.previousCoord, vec2(1.0))));

	result.velocityPixels =
		(screenCoord - result.previousCoord) * vec2(viewWidth, viewHeight);

	return result;
}

#endif /* REPROJECT_INCLUDED */
