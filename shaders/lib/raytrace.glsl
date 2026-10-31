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

	// The reflection is refused only when it heads BEHIND the camera plane,
	// which is the one case the depth buffer can never answer: view space looks
	// down -Z, so a reflected direction with a positive Z is going back over the
	// camera's shoulder and every sample past the crossing would project to a
	// mirrored place on the wrong side of the screen.
	//
	// What used to stand here was `dot(viewPos, reflectDirection) < 0.0`, and it
	// is not that test. With V the view direction and N the normal,
	// dot(P, R) = |P| * (1 - 2 (V.N)^2), so it was true exactly when the view
	// ray was within 45 degrees of the surface normal - and on a floor or a
	// ceiling the reflected ray keeps the view's own Z, so nothing was going
	// behind anything. What it actually refused was every pixel where you look
	// down at more than 45 degrees: a conic on a plane, a disc on the screen,
	// 16% of the frame at a 30-degree pitch and 32% at 45. `_team_bfog/reflection_45deg_refusal.py`
	// counts it. On a wall the two tests agree by accident, which is why the
	// mistake could live this long. Batch 662 replaced it.
	if (reflectDirection.z > 0.0) {
		return false;
	}

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
			// We escaped the screen, reject the raytracing.
			return false;
		}

		// Use the depth buffer and matrices to get the view Z coordinate for
		// this 2D screen position. We need the screen position to sample the
		// depth buffer, but otherwise we can remain in NDC space as much as
		// possible as we need the NDC position to get the view position.
		vec2 screenPos2D = ndcPos.xy * 0.5 + 0.5;
		ndcPos.z = texture(depthBuffer, screenPos2D).x * 2.0 - 1.0;
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
		if (minZ > sampledViewZ && sampledViewZ > maxZ
			&& screenPos2D.x >= 0.0 && screenPos2D.x <= 1.0
			&& screenPos2D.y >= 0.0 && screenPos2D.y <= 1.0) {
			// This was a successful hit. Save it so that we will at least
			// return this hit if we don't find a better one.
			hasHitPos = true;
			hitPos = screenPos2D;
			hitViewPos = vec3(homogenousPos.xy / homogenousPos.w, sampledViewZ);

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

// How many bisections the screen-space trace may spend on a hit it has found.
//
// The coarse ladder says which interval the surface is in; this says how finely
// to place the answer inside it. Five halvings take a step-sized interval to a
// thirty-second of itself, which near the surface is centimetres, and at the
// far end of the world is about what the depth buffer itself can tell apart out
// there. It is not an option because it is not a trade: one bisection that is
// refused costs a depth fetch and changes nothing, and the count that matters
// for cost is the option above.
#define SCREEN_REFINEMENT_STEPS 5

// Where a projected coordinate leaves the [-1, 1] box, along a ray.
//
// The coordinate is (a + t * da) / (w + t * dw) - the projection's own
// arithmetic with the division still to be done - and setting it to either edge
// gives one candidate per edge. Only a positive candidate is anywhere the ray
// is going, and 1.0e30 is a stand-in for "neither edge": a ray parallel to an
// edge never leaves it, which is not an error and must not end the march.
float ScreenEdgeParameter(float a, float w, float da, float dw) {
	float t = 1.0e30;

	// Declared here rather than inside either branch, and for a reason the
	// project's harness enforces: a name declared inside a block and read
	// after it is the shape of the C1503 that shipped in batch 570, and the
	// check that catches it cannot tell a second declaration in a sibling
	// block from a leak out of the first. The two branches below assign this
	// one instead of each declaring their own.
	float candidate = 0.0;

	float denomination = da - dw;
	if (denomination != 0.0) {
		candidate = (w - a) / denomination;
		if (candidate > 0.0) {
			t = min(t, candidate);
		}
	}

	denomination = da + dw;
	if (denomination != 0.0) {
		candidate = (-w - a) / denomination;
		if (candidate > 0.0) {
			t = min(t, candidate);
		}
	}

	return t;
}

// One sample of the screen-space ladder: the ray parameter at the point of the
// march that is a fraction u of the way across the screen.
//
// u is a fraction of the SCREEN and not of the ray's length, which is the whole
// of what makes this ladder different from a march in metres. A screen
// coordinate is (start + t * direction) / (w + t * dw), so the parameter that
// puts a sample on it is one rearrangement. Placing the samples evenly in u and
// then solving each one is what makes them dense over the floor and sparse at
// the horizon: at a fixed step across the screen, the step across the world
// grows with the distance.
//
// The axis solved from is the one with the longer travel - see the caller - so
// that neither a ray crossing the screen sideways nor one crossing it
// vertically runs into a denominator of nearly zero. A ray exactly parallel to
// that axis has no solution, and the -1 it returns is refused by the caller's
// forward-progress test.
float ScreenLadderParameter(
	vec4 startClip,
	vec4 directionClip,
	float startAxis,
	float endAxis,
	float startOnAxis,
	float directionOnAxis,
	float u
) {
	float axis = mix(startAxis, endAxis, u);
	float axisDenomination = directionClip.w * axis - directionOnAxis;

	if (axisDenomination == 0.0) {
		return -1.0;
	}

	return (startOnAxis - axis * startClip.w) / axisDenomination;
}

// The material reflection's trace, in the screen rather than in the world.
//
// Raytrace above marches in metres from the surface, and doubles: a 24-step
// budget puts its samples at 2, 6, 14, 30, 62, 126 and 254 - seven of them
// inside a 256-block world, and the rest of the budget past the end of it. That
// is a water tracer. Water reflects the sky and the land beyond it, both of
// which are large, and whether a particular step landed on one of them barely
// matters; a block reflects a block four metres away, which falls between the
// second and third samples, and whether it is found comes down to whether the
// depth buffer disagrees with the ray by less than half a step. It usually does
// not, and the reflection shows sky where the block is.
//
// This one marches in the screen instead. Its samples are evenly spaced between
// the pixel the ray leaves and the pixel it runs into - the edge of the window,
// or the far plane if it never leaves - so the perspective divide does the
// spacing: samples crowd together over the floor, where the reflections people
// look at are, and spread out towards the horizon, where the geometry they
// would find is hundreds of blocks away and a step can afford to be large.
// The material reflections are the only caller: water keeps the march above,
// which is what its own thickness rule and its own history were tuned against.
//
// Three other things come from the same place and cannot be separated from it:
//
// - The tolerance is the depth one step of this ladder covers, not a number of
//   metres. A grazing ray covers almost no depth per step and is therefore
//   tested almost exactly; a ray that runs away from the camera is allowed to
//   be wrong by the amount its own step is already wrong by, and no more. This
//   is the difference between a reflection that is missing and one that is
//   drawn from the wrong place.
// - A hit is bisected onto the surface before it is sampled, so the colour
//   that comes back is the surface's own rather than the far side of the step
//   that went over it. Without this, a coarse ladder trades holes for stretched
//   reflections instead of closing them.
// - The ray stops at the edge of the window. There is nothing behind the window
//   to read, and a sample fetched there is whatever the texture's edge happens
//   to hold, which reads as a reflection of a place that does not exist.
//
// Measured in _team_bfog/ssr_step_model.py, over a cross-section of a world of
// one-metre steps and walls: of the reflections really present, the world-space
// ladder at this pack's 24 steps finds 37% and accepts a wrong surface for most
// of the rest; this one, at the same 24 and with the five bisections above,
// finds 97%.
bool ScreenSpaceRaytrace(
	sampler2D depthBuffer,
	mat4 gbufferProjection,
	mat4 gbufferProjectionInverse,
	vec3 viewPos,
	vec3 reflectDirection,
	vec2 windowToNdc,
	// Where in the first cell of the ladder to start, in [0, 1). See the note
	// on the ladder below: without this the ladder is a fixed lattice in the
	// screen, and a lattice plus a point sample is a moire.
	float dither,
	out vec2 hitPos,
	out vec3 hitViewPos
) {
	// No "points back at the viewer" test here, and that is deliberate (batch
	// 662 - see the note on the same test in Raytrace above). The case it was
	// meant to catch is a ray heading behind the camera plane, and this function
	// already answers that exactly: below, `directionClip.w < 0` is that
	// condition (`w` is -direction.z), and it clamps `maxT` to the camera plane;
	// a negative result makes `!(maxT > 0)` refuse the ray before the march
	// starts. Everything else the old test refused - the whole cone where you
	// look at a floor or a ceiling more squarely than 45 degrees - is a ray that
	// marches perfectly well forward and finds what is above or below.

	// The ray in the projection's own coordinates, where a point on it is
	// start + t * direction with the division by w still to be done. Keeping it
	// in that form is what lets the march below place a sample at a chosen
	// screen coordinate exactly: a screen coordinate is a ratio of two of these
	// components, so solving for the parameter that produces one is a single
	// linear equation, and nothing has to iterate or approximate to place it.
	vec4 startClip = gbufferProjection * vec4(viewPos, 1.0);
	vec4 directionClip = gbufferProjection * vec4(reflectDirection, 0.0);

	if (startClip.w <= 0.0) {
		return false;
	}

	// How far the ray may go before it is no longer on the screen: out of the
	// left or right, out of the top or bottom, past the far plane, or back
	// through the plane the camera sits on. Whichever comes first ends it.
	float maxT = min(
		ScreenEdgeParameter(startClip.x, startClip.w, directionClip.x, directionClip.w),
		ScreenEdgeParameter(startClip.y, startClip.w, directionClip.y, directionClip.w));

	// The far plane is the projection's own z = 1, which is the same solve.
	float farDenomination = directionClip.z - directionClip.w;
	if (farDenomination != 0.0) {
		float farCandidate = (startClip.w - startClip.z) / farDenomination;
		if (farCandidate > 0.0) {
			maxT = min(maxT, farCandidate);
		}
	}

	// And the plane through the camera, for a ray that turns back towards it:
	// past that point its w is negative and every sample of it projects to the
	// same place.
	if (directionClip.w < 0.0) {
		maxT = min(maxT, -startClip.w / directionClip.w);
	}

	if (!(maxT > 0.0)) {
		return false;
	}

	// Nothing in a world is a million blocks away, and a bound that far out
	// means the solve above found no edge and no far plane for this ray at all.
	// Marching to it would multiply the clip coordinates by a number that large
	// and lose every digit worth having.
	if (maxT > 1.0e6) {
		return false;
	}

	vec4 endClip = startClip + directionClip * maxT;

	// The pixel the ray leaves from. A sample that has not left it yet reads
	// the fragment's own surface, and accepting that would be a reflection of
	// the surface at its own pixel: invisible at best, and it would end the
	// march before it went anywhere.
	vec2 startNdc = startClip.xy / startClip.w;

	// The ladder is even in the SCREEN, and that is the whole difference from
	// the march above - not "more steps". Placing samples evenly along the ray
	// in metres is what the world-space ladder already did, and it is why its
	// second sample is six metres out. Solving each sample's parameter from a
	// screen coordinate instead is what crowds them onto the floor and lets
	// them thin out towards the horizon, because that is where a fixed step
	// across the screen becomes a large step across the world.
	//
	// The axis with the longer screen travel is the one solved from, so that a
	// ray crossing the screen sideways is not solved from a vertical delta of
	// nearly zero, and vice versa.
	vec2 endNdc = endClip.xy / endClip.w;
	bool alongX = abs(endNdc.x - startNdc.x) >= abs(endNdc.y - startNdc.y);
	float startAxis = alongX ? startNdc.x : startNdc.y;
	float endAxis = alongX ? endNdc.x : endNdc.y;
	float startOnAxis = alongX ? startClip.x : startClip.y;
	float directionOnAxis = alongX ? directionClip.x : directionClip.y;

	// Where the last sample that was still in front of the scene was, so that
	// a cornered surface can be bisected between the two. In front to begin
	// with, since the ray starts on a surface and not behind it.
	float frontU = 0.0;
	float frontPenetration = 0.0;

	// The view Z of the previous sample, which is what the tolerance below is
	// measured against. It has to be the step that was actually taken and not
	// the span divided by the count: this ladder is even in the screen, and one
	// step near the horizon covers hundreds of times the depth of one step over
	// the floor. A single average would be metres of slack where the reflections
	// are and centimetres where they are not.
	float previousZ = -startClip.w;

	// The first sample the ray went behind anything at, for the fallback at the
	// end of the function.
	bool hasBehind = false;
	float behindU = 0.0;

	for (int i = 1; i <= RAYMARCH_STEPS; i++) {
		// The ladder, offset by a fraction of a cell that differs per pixel and
		// per frame. This is not noise for its own sake: the ladder is a fixed
		// lattice in the screen, each cell is a large step at the far end, and
		// what the caller does with the answer is a single point sample of the
		// colour buffer - so without an offset, neighbouring pixels land on the
		// same lattice points and the reflection shows the lattice as bands.
		// Offsetting each pixel differently turns a coherent band into
		// per-pixel noise, which is what the temporal resolve downstream can
		// average; the three packs that were compared for this all do it.
		float u = (float(i) - dither) / float(RAYMARCH_STEPS);
		float sampleT = ScreenLadderParameter(
			startClip, directionClip,
			startAxis, endAxis, startOnAxis, directionOnAxis, u);

		// The solve puts the sample where the ladder says, and nothing has
		// bounded it yet: as the coordinate approaches the point the ray
		// converges to, the parameter runs away to an infinity the depth buffer
		// has no answer for. The march was given a bound when it computed where
		// the ray leaves the screen, and that is what this holds it to.
		if (!(sampleT > 0.0)) {
			break;
		}
		if (sampleT > maxT) {
			sampleT = maxT;
		}

		vec4 sampleClip = startClip + directionClip * sampleT;

		if (sampleClip.w <= 0.0) {
			break;
		}

		vec3 sampleNdc = sampleClip.xyz / sampleClip.w;
		vec2 sampleScreen = sampleNdc.xy * 0.5 + 0.5;

		if (sampleScreen.x < 0.0 || sampleScreen.x > 1.0
			|| sampleScreen.y < 0.0 || sampleScreen.y > 1.0) {
			break;
		}

		float rayZ = -sampleClip.w;
		float stepDepth = abs(rayZ - previousZ);

		// Still inside the pixel the ray left from, so not yet anywhere. The
		// depth is carried forward all the same, or the step that does count
		// would be measured from further back than it really is.
		//
		// Two pixels rather than one, because the surface itself is in the depth
		// buffer and a sample one pixel out is still standing on it: accepting
		// it draws the surface's own colour as its reflection, which reads as
		// the reflection being made of the surface. Bliss rejects a hit within
		// about two thousandths of the screen for the same reason.
		if (all(lessThan(abs(sampleNdc.xy - startNdc), windowToNdc * 2.0))) {
			frontU = u;
			frontPenetration = 0.0;
			previousZ = rayZ;
			continue;
		}

		// What the depth buffer holds at this pixel.
		float surfaceDepth = texture(depthBuffer, sampleScreen).x;

		// A pixel the world does not cover holds the clear value, and nothing
		// can be met there. That is not a reason to stop the march: a ray that
		// passes over the sky and comes back onto the world - over the edge of a
		// block and onto the wall behind it - still has the rest of the ladder
		// to walk, and stopping at the first sky pixel is what leaves the
		// reflection showing sky along every silhouette. The sample is skipped
		// instead, the way the surface's own pixels are, and the march carries
		// on.
		if (surfaceDepth >= 1.0) {
			frontU = u;
			frontPenetration = 0.0;
			previousZ = rayZ;
			continue;
		}

		// As a view Z.
		vec4 surfaceHomogeneous = gbufferProjectionInverse * vec4(
			sampleNdc.xy,
			surfaceDepth * 2.0 - 1.0,
			1.0);
		float surfaceZ = surfaceHomogeneous.z / surfaceHomogeneous.w;

		// Both are negative, and further from the eye is more negative, so the
		// ray being behind the surface is the surface's Z being the larger of
		// the two. How far behind is the penetration.
		//
		// The tolerance is the depth this one step covered: a sample is at most
		// one step behind the surface it has just crossed, so that is what it
		// takes to accept a crossing. A surface further behind than the step was
		// deep is not one this ray went through - it is something standing
		// further away than the place the ray has reached. The floor under it is
		// for a step so nearly parallel to the screen that it covers no depth at
		// all: the crossing still has to be inside the interval.
		float tolerance = max(stepDepth, 0.02);
		float penetration = surfaceZ - rayZ;

		// A surface the ray has gone behind, remembered in case nothing better
		// turns up. See the note where it is used, at the end of the function.
		if (!hasBehind && penetration > 0.0) {
			hasBehind = true;
			behindU = u;
		}

		if (penetration > 0.0 && penetration <= tolerance) {
			// The surface is somewhere between the last sample in front of it
			// and this one. Bisect that interval, keeping the two ends apart:
			// nothing here needs to assume the surface is flat, only that it
			// was in front at one end and behind at the other.
			float loU = frontU;
			float hiU = u;

			// A previous sample that was already behind has left no front end
			// to bisect towards - the ray went behind this surface in one step
			// and stayed there - so the coarse sample is the answer. Bisecting
			// an interval whose both ends are behind would only spend the five
			// fetches to arrive at the same place.
			if (frontPenetration <= 0.0) {
				for (int j = 0; j < SCREEN_REFINEMENT_STEPS; j++) {
					float midU = 0.5 * (loU + hiU);
					float midT = ScreenLadderParameter(
						startClip, directionClip,
						startAxis, endAxis, startOnAxis, directionOnAxis, midU);
					vec4 midClip = startClip + directionClip * midT;
					vec3 midNdc = midClip.xyz / midClip.w;
					vec2 midScreen = midNdc.xy * 0.5 + 0.5;

					vec4 midHomogeneous = gbufferProjectionInverse * vec4(
						midNdc.xy,
						texture(depthBuffer, midScreen).x * 2.0 - 1.0,
						1.0);
					float midSurfaceZ = midHomogeneous.z / midHomogeneous.w;

					if (-midClip.w < midSurfaceZ) {
						hiU = midU; // behind: the surface is nearer than this
					} else {
						loU = midU; // in front: it is further than this
					}
				}
			}

			// The near end of the last interval is the crossing itself.
			float hitT = ScreenLadderParameter(
				startClip, directionClip,
				startAxis, endAxis, startOnAxis, directionOnAxis, hiU);
			vec4 hitClip = startClip + directionClip * min(hitT, maxT);
			vec3 hitNdc = hitClip.xyz / hitClip.w;
			vec2 hitScreen = hitNdc.xy * 0.5 + 0.5;

			// The surface's own position, which is what the caller's history
			// and its edge fade are both about.
			vec4 hitHomogeneous = gbufferProjectionInverse * vec4(
				hitNdc.xy,
				texture(depthBuffer, hitScreen).x * 2.0 - 1.0,
				1.0);

			hitPos = hitScreen;
			hitViewPos = hitHomogeneous.xyz / hitHomogeneous.w;
			return true;
		}

		frontU = u;
		frontPenetration = penetration;
		previousZ = rayZ;
	}

	// Nothing was crossed cleanly, but the ray did go behind something. Take
	// that.
	//
	// This is the author's decision of 2026-10-22, and it is a trade rather than
	// a fix. The pixels it serves are the ones at a silhouette: the reflected
	// ray leaves the surface, immediately leaves what is on screen with it, and
	// finds nothing at all - so the caller's sky fallback fills them, and every
	// edge of every block picks up a rim of sky. A surface the ray has gone
	// behind is at least the thing standing there, so it is a better answer than
	// the sky even when it is not exactly on the ray. The three packs this was
	// compared against all make the same trade - Bliss accepts a surface up to
	// 0.19 to 0.90 of the distance behind the ray, uncapped, which is why its
	// reflections fill the silhouette and why it stretches.
	//
	// Deliberately not bisected. A bisected version of a wrong answer is still a
	// wrong answer, and the five fetches would buy an edge that is straighter
	// than the truth deserves; the coarse sample is what the same trade costs
	// everyone else.
	if (hasBehind) {
		float behindT = ScreenLadderParameter(
			startClip, directionClip,
			startAxis, endAxis, startOnAxis, directionOnAxis, behindU);
		vec4 behindClip = startClip + directionClip * min(behindT, maxT);
		vec3 behindNdc = behindClip.xyz / behindClip.w;

		// Clamped because a sample that landed a thousandth of a pixel outside
		// would otherwise fetch the texture's edge, which is not a place.
		vec2 behindScreen = clamp(
			behindNdc.xy * 0.5 + 0.5,
			vec2(0.0),
			vec2(1.0));

		vec4 behindHomogeneous = gbufferProjectionInverse * vec4(
			behindNdc.xy,
			texture(depthBuffer, behindScreen).x * 2.0 - 1.0,
			1.0);

		hitPos = behindScreen;
		hitViewPos = behindHomogeneous.xyz / behindHomogeneous.w;
		return true;
	}

	return false;
}
