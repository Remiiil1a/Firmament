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

// Screen-space ray marching, for the reflections and the refraction.
//
// ⚠️ Rewritten in batch 514, and the reason is worth keeping. The version this replaces
// was Steadfast's: it doubled every step and accepted a hit when the depth sampled at the
// END of a step fell inside a window that widened with the step. At a grazing angle -
// water seen level - the far steps are hundreds of metres long,
// so a distant hill or wall is stepped clean over: the sample at the end of that step
// reads the depth of whatever is BEHIND it, which is outside the window, and no hit is
// recorded. The caller then silently falls back to the sky, and that is the missing band
// of water reflection just under the horizon.
//
// Batch 489 widened the window to match upstream and batch 513 added a crossing test, and
// the band survived both, because the fault is in the step schedule rather than in the
// test: a surface that lies BETWEEN two samples cannot be found by looking harder at the
// samples. So the structure here is now the one Sundial-Lite uses, which does not have
// the fault:
//
// - The ray is projected and the distance to where it leaves the screen is solved for, and
//   the step budget is spread EVENLY over exactly that much of the ray. No step is wasted
//   off screen, and no step is long enough to swallow a surface.
// - A hit is a place where the ray is BEHIND the surface the depth buffer holds there:
//   one comparison of two numbers that came out of the same buffer, with no window and no
//   tolerance of its own.
// - That sample is then bisected (MAX_REFINEMENT_ROUNDS) to find where the ray and the
//   surface actually meet, and only then is a thickness asked for, as confirmation that
//   the two met rather than the ray passing near - which is the thing the window in the
//   old version was trying, and failing, to express.
//
// Sundial-Lite is GPLv3 like this pack; the credit is in NOTICE.md and in BATCH_LOG.md
// batch 514.
//
// The march runs in the space the depth buffer is read in: screen position in x and y and
// the buffer's own 0..1 depth in z. That is what makes the comparison above meaningful.
// It is also why stepping along the projected line is not an approximation: both the
// position and the depth of a straight line in view space are projective functions of the
// distance along it, so its image under the perspective divide is still a straight line.

// How many steps the march is given before it gives up. Overridable, so that a caller can
// set its own budget before including this file: the water reflections trace the water and
// nothing else, and the material reflections trace every smooth pixel of the screen, so
// asking both of them for the same number of steps would be wrong for one of them.
#ifndef RAYMARCH_STEPS
	#define RAYMARCH_STEPS 24
#endif

// How many times the hit is halved on its way to the meeting point. Each round re-reads
// the depth buffer once, so this is the budget the accuracy is bought with: five rounds
// put the hit inside a thirty-second of a step.
#define MAX_REFINEMENT_ROUNDS 5

// The smallest thickness a hit may be confirmed with, in the depth buffer's own units.
// The step's own depth is normally larger than this and is what the test uses; this is the
// floor for the steps that are almost parallel to the screen and so have almost no depth
// in them.
#define MIN_REFLECTION_THICKNESS 0.002

// The longest trace, in metres. The screen edge normally ends the march long before this;
// it is here so that a ray almost parallel to the screen cannot ask for a step the size of
// the world.
#define MAX_TRACE_DISTANCE 512.0

// Where along the ray its projection leaves the screen, as a distance in metres.
//
// The ray is a line in clip space: `origin` is where it starts and `direction` is its
// direction, and because the clip space is linear in the distance travelled, the parameter
// that lands on an edge IS that distance. Each of the four edges is solved for in turn, and
// a solution that is behind the start, or not a number at all (which is what a direction
// parallel to an edge gives), is passed over rather than allowed to win the minimum.
float RaytraceScreenEdgeLength(vec4 origin, vec4 direction) {
	vec2 atRight = (vec2(1.0) * origin.w - origin.xy) / (direction.xy - vec2(1.0) * direction.w);
	vec2 atLeft = (vec2(-1.0) * origin.w - origin.xy) / (direction.xy + vec2(1.0) * direction.w);

	float t = MAX_TRACE_DISTANCE;
	t = min(t, atRight.x > 0.0 ? atRight.x : MAX_TRACE_DISTANCE);
	t = min(t, atRight.y > 0.0 ? atRight.y : MAX_TRACE_DISTANCE);
	t = min(t, atLeft.x > 0.0 ? atLeft.x : MAX_TRACE_DISTANCE);
	t = min(t, atLeft.y > 0.0 ? atLeft.y : MAX_TRACE_DISTANCE);
	return t;
}

bool Raytrace(
	sampler2D depthBuffer,
	mat4 gbufferProjection,
	mat4 gbufferProjectionInverse,
	vec3 viewPos,
	vec3 reflectDirection,
	float thicknessScale,
	out vec2 hitPos,
	out vec3 hitViewPos
) {
	// If the reflection is towards the viewer, immediately reject it since no good
	// reflection is really feasible here.
	if (dot(viewPos, reflectDirection) < 0.0) {
		return false;
	}

	// The ray as a line in clip space. `P * (viewPos, 1)` is where it starts and
	// `P * (reflectDirection, 0)` is its direction; the second one's parameter is the same
	// distance in metres as the first one's, which is what makes the length limit a number
	// of metres rather than an arbitrary number.
	vec4 originProj = gbufferProjection * vec4(viewPos, 1.0);
	vec4 directionProj = gbufferProjection * vec4(reflectDirection, 0.0);

	vec4 endProj = originProj + directionProj * RaytraceScreenEdgeLength(originProj, directionProj);

	// Into the space the depth buffer lives in.
	vec4 originCoord = vec4(originProj.xy / originProj.w * 0.5 + 0.5,
		originProj.z / originProj.w * 0.5 + 0.5, 0.0);
	vec4 endCoord = vec4(endProj.xy / endProj.w * 0.5 + 0.5,
		endProj.z / endProj.w * 0.5 + 0.5, 0.0);

	// A ray that starts outside the depth range has no on-screen path to march over.
	// Only the start is checked: the end of a ray that leaves the screen while still
	// climbing has a depth of nearly one, and rejecting that would throw away exactly the
	// long, level traces this marcher exists for. NaNs are caught below instead, by tests
	// written so that a NaN fails them.
	if (!(originCoord.z > 0.0 && originCoord.z < 1.0)) {
		return false;
	}

	vec4 stepSize = (endCoord - originCoord) / float(RAYMARCH_STEPS - 1);

	// The tolerance a hit is confirmed with: one step of depth, or the floor, whichever is
	// larger, scaled by the caller - water tolerates more than a mirror does, because a
	// missing reflection is more visible there than a stretched one.
	float minimumThickness = max(MIN_REFLECTION_THICKNESS, abs(stepSize.z)) * thicknessScale;

	// One step in, so that the surface the ray starts on cannot be taken as its own hit.
	vec4 sampleCoord = originCoord + stepSize;

	for (int i = 0; i < RAYMARCH_STEPS; i++) {
		// Past the edge of the screen, or off the near end of the depth range: stop. What
		// was found is kept - the version this replaces returned a miss here, which threw
		// away hits that had already been found. The tests are written as negated
		// comparisons so that a coordinate that is not a number fails them rather than
		// slipping through and being sampled.
		if (!(abs(sampleCoord.x * 2.0 - 1.0) <= 1.0)
			|| !(abs(sampleCoord.y * 2.0 - 1.0) <= 1.0)
			|| !(sampleCoord.z >= 0.0 && sampleCoord.z <= 1.0)) {
			break;
		}

		float sampleDepth = texture(depthBuffer, sampleCoord.xy).x;

		// The whole of the hit test. Both are depths from the same buffer, so the ray is
		// behind the surface exactly when its own depth is the larger of the two - and
		// `sampleDepth < 1.0` is what asks whether there is a surface there at all.
		if (sampleCoord.z > sampleDepth && sampleDepth < 1.0) {
			// Walk the sample back to where the ray and the surface meet: every round
			// halves the step and goes whichever way the last comparison pointed.
			vec4 refined = sampleCoord;
			float refinedDepth = sampleDepth;
			float scale = 0.5;
			for (int j = 0; j < MAX_REFINEMENT_ROUNDS; j++) {
				refined += sign(refinedDepth - refined.z) * scale * stepSize;
				refinedDepth = texture(depthBuffer, refined.xy).x;
				scale *= 0.5;
			}

			// Accept when the two really did meet: within a step of depth of each other,
			// on a surface that exists, on the screen, and ahead of the start rather than
			// behind it.
			if (abs(refined.z - refinedDepth) < minimumThickness
				&& refinedDepth < 1.0
				&& all(lessThan(abs(refined.xy * 2.0 - 1.0), vec2(1.0)))
				&& dot(stepSize.xy, refined.xy - originCoord.xy) > 0.0) {
				hitPos = refined.xy;

				// Back to view space, which is where the callers shade the hit.
				vec4 homogenousPos = gbufferProjectionInverse
					* vec4(refined.xy * 2.0 - 1.0, refinedDepth * 2.0 - 1.0, 1.0);
				hitViewPos = homogenousPos.xyz / homogenousPos.w;
				return true;
			}
		}

		sampleCoord += stepSize;
	}

	return false;
}
