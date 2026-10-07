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

// Modified 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

// This is an improved ray marching implementation inspired by a few ideas from
// Chocapic13's shaders:
//
// - Rapidly accelerate the ray through the scene to quickly find an initial hit
//   and then upon a hit step more slowly through the previous ray interval.
//   This enables aggressive undersampling to avoid spending steps on empty
//   space, which is very common in open-water scenes.
// - Yet, starting off slow permits good local reflections as well
//
// It also has a few of my own improvements on top of those:
//
// - Modify the thickness in a similar fashion to the ray velocity, so that
//   nearby reflections have a slow thickness in meters and far ones have a high
//   thickness. This avoids ugly local results while not making faraway ones too
//   noisy.
// - If we run out of steps while refining, return the last valid hit to avoid
//   returning MISS when we actually have a fairly good hit saved.
//
// Combined, this gives decent-quality reflections using simple, intuitive ray
// marching and a small number of steps, independent of screen resolution.

// The maximum permitted thickness (meters) of a reflection hit.
//
// Thickness allows for inherent imprecision and means that even if we do not
// have an exact perfect match, we can accept a fragment for the reflection.
//
// If this is too low, you will have holes and noise, and if this is too high,
// you will have ugly stretchy reflections.
#define MAX_THICKNESS 8.0

// More steps give extra opportunities for refinements and similar, but also
// come at a potential performance cost for rays that travel very far without
// making a hit or escaping the frustum.
//
// Even if we make a hit, we'll still take a lot of steps to refine
//
// Overridable, so that a caller can set its own budget before including this
// file. The water reflections trace the water and nothing else, and the material
// reflections trace every smooth pixel of the screen; asking both of them for
// the same number of steps would be wrong for one of them.
#ifndef RAYMARCH_STEPS
	#define RAYMARCH_STEPS 24
#endif

// How much to accelerate each step - this allows us to cover long distances
// with simple raymarching without excessive steps or excessive oversampling,
// in fact, it allows fairly aggressive undersampling, and if we overshoot
// (see below) we can retrace at a slower velocity.
#define ACCELERATION_FACTOR 2.0

// How many rounds of recursive refinement to attempt. Each refinement round
// results in us retracing the last traced interval at a slower speed, and may
// take multiple individual steps (see TAPS_PER_REFINEMENT).
//
// With 4 rounds of 4 taps, we're spending up to 20 steps on refinement: 1 step
// each refinement round on hitting and rolling back, and 4 steps on checking
// within that interval.
#define MAX_REFINEMENT_ROUNDS 4

// During each refinement round, we elect to dedicate a certain number of steps
// (TAPS_PER_REFINEMENT) to that individual round, and cover a certain
// percentage of the original step distance (REFINEMENT_DISTANCE) that lead us
// to the intersection. We deliberately do not cover the whole distance, as we
// save the last hit that was at the end of the distance and can use that in the
// worst case.
//
// Given a certain TAPS_PER_REFINEMENT, we reduce the velocity by a factor that
// is meant to make this round's taps cover the interval again in that many
// steps. With the values below the factor is 0.75 * 2^-(4+1) = 0.0234375, and
// since every step multiplies the velocity back up by ACCELERATION_FACTOR the
// round's taps are 0.047, 0.094, 0.188, 0.375 and 0.75 of the original step -
// four of them cover 0.703 of the interval, which is the 0.75 that
// REFINEMENT_DISTANCE asks for to within the rounding, and the fifth is what
// would overshoot it. So the formula does hold the round to TAPS_PER_REFINEMENT
// taps in the sense that matters - it does not run past the interval - and the
// coverage is REFINEMENT_DISTANCE rather than the whole interval either way.
//
// Then, we add one to the exponent, because we always multiply by
// ACCELERATION_FACTOR every step, including the one directly after initiating
// this refinement.
//
// Finally, we multiply in the REFINEMENT_DISTANCE at the very end - a value of
// 0.75 means that we cover 75% of the original distance in this refinement
// round.
#define TAPS_PER_REFINEMENT 4
#define REFINEMENT_DISTANCE 0.75
const float refinementDecelerationFactor = (REFINEMENT_DISTANCE
	* pow(1 / ACCELERATION_FACTOR, TAPS_PER_REFINEMENT + 1));

// thicknessControl impacts the base thickness and increase in thickness over
// distance during raytracing, effectively the tolerance of determinining
// whether we are going to accept a hit or not.
//
// At this point in the file the two components are what the caller passes: X is
// the thickness the first step starts with, in meters, and Y is the factor the
// thickness is multiplied by on every step, on top of the ACCELERATION_FACTOR
// the velocity itself gets. The caller's own values are in translucent.glsl -
// (1.0, 1.0) for water and (0.5, 1.0) for the mirror-like surfaces - so in
// practice the two differ in their first component and the second is 1.0. What
// the thickness actually ends up being on a given step is capped below.
//
// X: initial thickness in meters
// Y: additional increase in meters per raytracing step not directly related to
//    distance
bool Raytrace(
	sampler2D depthBuffer,
	mat4 gbufferProjection,
	mat4 gbufferProjectionInverse,
	vec3 viewPos,
	vec3 reflectDirection,
	vec2 thicknessControl,
	out vec2 hitPos,
	out vec3 hitViewPos
) {
	// State variables for refinement
	uint refinementRounds = uint(0);
	bool hasHitPos = false;


	// Initial velocity and thickness
	//
	// Stored together in case the shader compiler likes a single vec4
	// better than a vec3 + float.
	vec4 velocityAndThickness = vec4(reflectDirection, thicknessControl);

	// If the reflection is towards the viewer, immediately reject it since no
	// good reflection is really feasible here.
	if (dot(viewPos, reflectDirection) < 0.0) {
		return false;
	}

	// Whether the ray had already gone behind the surface the depth buffer holds at the
	// screen position it last sampled. The ray starts ON the water, and the buffer this
	// traces through holds what is behind the water rather than the water itself, so the
	// ray starts in front of it.
	bool behindSurface = false;

	for (uint i = uint(0); i < uint(RAYMARCH_STEPS); i++){
		// Each step, accelerate by a certain factor to avoid oversampling
		// near the end of the ray march.
		//
		// We also expand the thickness accordingly, as using a constant
		// thickness means that no thickness is actually ideal.
		//
		// But varying it means that we can use a very restrictive thickness
		// when doing small steps and then widen it when doing large strides.
		//
		// Starting small and then increasing prevents tree fragments above you
		// from being reflected in water in front of you.
		velocityAndThickness *= vec4(
			vec3(ACCELERATION_FACTOR),
			ACCELERATION_FACTOR * thicknessControl.y);

		// Prevent thickness from getting too large as that will mean far
		// distances have undesirable stretching.
		//
		// 鈿狅笍 This line is where this pack used to differ from Steadfast, and that
		// difference is the whole of why water lost its reflection in a band under the
		// horizon when the surface is viewed level. Upstream divides by the refinement
		// count outright. Before the first hit that count is zero, so upstream's divisor
		// is an infinity, min() keeps the step's own thickness, and the tolerance is
		// therefore as wide as the step - which is what catches the surface the ray
		// steps over at a grazing angle. This pack guarded the division with
		// max(count, 1), which pinned the tolerance at MAX_THICKNESS for every step
		// before the first hit; against steps of hundreds of metres that is nothing,
		// and the ray passed over its own reflection. See BATCH_LOG.md batch 489.
		//
		// The guard had a reason, kept here so that dropping it is a decision rather
		// than an accident: an unrefined hit then carries a tolerance as long as the
		// step that made it, so it can accept a surface it merely passed near, and the
		// reflection is drawn from a screen position away from the point actually being
		// reflected. That is the stretched, banded reflection. Water is where the trade
		// is made the other way, because a missing reflection is the more visible of
		// the two and because the user confirmed in game which one this was.
		//
		// Written as a test rather than as a division by zero: min(w, infinity) is w,
		// so saying that costs one comparison and does not depend on how the driver
		// answers a division the language leaves undefined.
		float thicknessM = refinementRounds == uint(0)
			? velocityAndThickness.w
			: min(velocityAndThickness.w, MAX_THICKNESS / float(refinementRounds));

		// The range of Z values we will permit lies between where we started
		// and where we are advancing to.
		//
		// Note that these view-space Z values are negative, so the thickness
		// +/- is widening the range, not narrowing it. See below for a more
		// detailed explanation on how this works.
		float minZ = viewPos.z + thicknessM;
		viewPos += velocityAndThickness.xyz;
		float maxZ = viewPos.z - thicknessM;

		// Convert view position to NDC (-1.0 to 1.0) coordinates.
		vec4 clipPos = gbufferProjection * vec4(viewPos, 1.0);
		vec3 ndcPos = clipPos.xyz / clipPos.w;

		// Check if the NDC coordinates still lie within the screen.
		// If any coordinate goes below -1 or above 1, it's definitely
		// outside of the screen.
		vec3 absNdcPos = abs(ndcPos);
		float maxNdc = max(max(absNdcPos.x, absNdcPos.y), absNdcPos.z);
		if (maxNdc > 1.0) {
			// We escaped the screen. Keep whatever was found rather than rejecting the
			// trace: a hit that has already been located is better than the sky the
			// caller falls back to, and this line used to throw it away - which is the
			// only place in this file that destroyed a hit (batch 515).
			return hasHitPos;
		}

		// Use the depth buffer and matrices to get the view Z coordinate for
		// this 2D screen position. We need the screen position to sample the
		// depth buffer, but otherwise we can remain in NDC space as much as
		// possible as we need the NDC position to get the view position.
		vec2 screenPos2D = ndcPos.xy * 0.5 + 0.5;

		// The depth buffer's own value, kept before it is turned into a view Z: it is what
		// says whether there is a surface here at all. One is the far plane, and a "hit"
		// on the far plane is a hit on the sky.
		float sampledDepth = texture(depthBuffer, screenPos2D).x;
		ndcPos.z = sampledDepth * 2.0 - 1.0;
		vec4 homogenousPos = gbufferProjectionInverse * vec4(ndcPos, 1.0);
		float sampledViewZ = homogenousPos.z / homogenousPos.w;

		// Intersections are odd because the Z values are all negative. What we
		// want is:
		// abs(minZ) - thickness < abs(sampledViewZ) < abs(maxZ) + thickness
		//
		// But what that really means is:
		// -minZ - thickness < -sampledViewZ < -maxZ + thickness
		//
		// This can be expanded as:
		// -(minZ + thickness) < -sampledViewZ
		// AND -sampledViewZ < -(maxZ - thickness)
		//
		// Using the rules of inequalities, we can rewrite this as:
		// minZ + thickness > sampledViewZ AND sampledViewZ > maxZ - thickness
		//
		// And we can pull the thickness calculations to above.
		//
		// The screen position is checked along with the depth, and it fails the
		// same way: the depth this reads can be a level-of-detail renderer's own
		// texture, which holds nothing past the edge of what it drew, and a trace
		// through that produces a position that is not a number. A hit is a
		// position the caller will sample a colour buffer at, and sampling at a
		// coordinate that is not a number is undefined - which is a black pixel.
		// See the same guard at the end of RefractTrace, which is where it was
		// first found.
		//
		// ⚠️ And the hit this window cannot see, which is what batch 489 left open. At a
		// grazing angle the acceleration above makes the far steps hundreds of metres
		// long, and a distant hill or wall is then stepped clean over: the sample at the
		// end of that step reads the depth of whatever is BEHIND it, which is outside
		// the window, so no hit is recorded and the caller falls back to the sky. That is
		// the missing band of reflection under the horizon when the water is viewed
		// level. Widening the window does not catch it either - the surface is not near
		// the sample, it is BETWEEN two of them.
		//
		// So the two samples' answers to "is the ray behind the surface here" are
		// compared as well. Both are view-space Z and both are negative, so the ray is
		// behind the surface when its own Z is the more negative of the two. If it is
		// behind it now and was in front of it at the previous sample, the surface lies
		// between the two samples, and that is a hit wherever it happens - and only
		// there, so this does not accept a surface the ray merely passed near, which is
		// what the guard removed in batch 489 was protecting against. The hit is recorded
		// at this sample's screen position and the refinement below backs it up and
		// closes in on the crossing, exactly as it does for a window hit.
		// See BATCH_LOG.md b513.
		bool wasBehindSurface = behindSurface;
		behindSurface = viewPos.z < sampledViewZ;
		bool crossedSurface = behindSurface && !wasBehindSurface;

		// ⚠️ And two more things an accepted sample has to be, neither of which this marcher
		// asked before batch 515. Sundial, Mellow and Bliss all ask both:
		//
		//  - it has to BE a surface. The far plane's depth is one, and with a tolerance as
		//    wide as the step the window reaches it once the ray is a third of the way to
		//    the far plane: the "hit" is then a sky pixel, which the caller fogs back to
		//    sky colour - a flat strip of nothing where a reflection should be.
		//  - it has to be BEYOND the surface the ray started on. The window's near bound
		//    reaches behind the start, and under a water fragment the depth buffer holds
		//    the bed a few metres below, so the fragment can accept its own pixel region
		//    and reflect the lake bed into itself, which is no reflection at all.
		vec3 candidateViewPos = vec3(homogenousPos.xy / homogenousPos.w, sampledViewZ);

		if ((minZ > sampledViewZ && sampledViewZ > maxZ || crossedSurface)
			&& sampledDepth < 1.0
			&& length(candidateViewPos) > length(viewPos)
			&& screenPos2D.x >= 0.0 && screenPos2D.x <= 1.0
			&& screenPos2D.y >= 0.0 && screenPos2D.y <= 1.0) {
			// This was a successful hit. Save it so that we will at least
			// return this hit if we don't find a better one.
			hasHitPos = true;
			hitPos = screenPos2D;
			hitViewPos = candidateViewPos;

			// Undo the last raymarch and decelerate so we can try to trace a
			// more precise hit.
			viewPos -= velocityAndThickness.xyz;
			velocityAndThickness *= refinementDecelerationFactor;

			// Refine for a certain number of steps at the end before declaring
			// a successful hit, to improve the accuracy of reflections.
			refinementRounds += uint(1);


			// If we've already refined sufficiently, return this result as-is.
			if (refinementRounds >= uint(MAX_REFINEMENT_ROUNDS)) {
				return true;
			}
		}
	}

	// No hit on this iteration, return the valid hit if we had one.
	return hasHitPos;
}
