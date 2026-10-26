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
// beyond it gets light from the sun and casts none of its own. On a landscape
// with hills that is the most conspicuous thing about the distance: a valley
// sits in full sun no matter what stands between it and the sun.
//
// This walks a ray from the fragment towards the sun through the depth buffer
// instead, and whatever the buffer says is in the way is in the way.
//
// ---- batch 654: this file is a PORT, not our own design ----
//
// Everything from here down is Sundial-Lite's `screenSpaceShadow`, taken from
// programs/deferred/Deferred11.frag:169-258 together with its screen-edge helper
// in libs/GbufferData.glsl:444-458, and adapted to this pack's buffers. It is
// kept structurally identical on purpose: the pack is being aligned against that
// reference, and batches 636 to 653 were spent discovering - one symptom at a
// time - that our own implementation did not work. Its symptoms were flat grey
// shadows, then banded slopes that shadowed themselves, then stripes that the
// step count did not change. Rather than keep diagnosing our own arithmetic, the
// arithmetic is now the reference's.
//
// What was adapted, and nothing else:
//
//  * the depth buffer. Sundial reads a packed float32 depth out of colortex6 and
//    has a negative-depth branch for its LOD terrain. In this pack the LOD
//    terrain (Voxy) writes the same depth textures as the vanilla world - see
//    BATCH_LOG 3090, and the note in voxy.json that refuses
//    excludeLodsFromVanillaDepth for exactly this reason - so the plain depth
//    texture can be sampled and the LOD branch is not needed.
//  * the hand. Sundial remaps the hand's depth with MC_HAND_DEPTH and offsets it.
//    This pack's receiver is the opaque surface, where the hand is not present at
//    all, so both are dropped rather than carried as dead weight.
//  * porosity. Sundial's occlusion test is `shadow *= clamp(absorption - hit, 0, 1)`
//    where absorption is 1.0 exactly for a non-porous surface, which makes it a
//    hard binary decision for solid terrain. This pack has roughness where Sundial
//    has porosity, and roughness is not the same quantity, so porosity is passed
//    as zero and the expression collapses to the solid case - which is what the
//    effect is for here. Foliage translucency is a separate feature in this pack
//    (PBR_SUBSURFACE) and is not this file's business.
//  * the sub-texel refinement. Sundial re-reads the depth with textureGather and
//    bilinearly reconstructs the four taps around a hit. textureGather needs GLSL
//    4.0 and this pack is #version 150, so the refinement is a plain bilinear
//    texture fetch at the sample coordinate, which asks the same question.
//  * the noise. Sundial reads two values from a blue-noise texture; this pack has
//    no such texture bound for this pass, so SssScreenNoise below provides the one
//    value the march uses, in the same 0..1 role.
//
// The shadow's own distance fade is INSIDE the function (shadowWeight below), and
// that is why the caller no longer applies one of its own: batches 645-651 each
// added a fade, a reach or a threshold at the call site, and every one of them was
// a substitute for this.

// Whether to cast shadows for terrain the shadow map does not reach.
//
// On by default: without it the distance is lit flat, which reads as a seam at
// the edge of the shadow distance.
//
// The #ifdef is not decoration: Iris only treats a bare #define as a boolean
// option if the macro is referenced by an #ifdef or #ifndef somewhere.
#define SCREENSPACE_SHADOWS
#ifdef SCREENSPACE_SHADOWS
	// How much of the result to apply, where 1.0 would apply all of it. It is
	// applied to the whole colour rather than to the sunlight alone, because by the
	// time this pass runs the two are already added together - so a value near 1.0
	// also takes some sky light with it. Sundial applies its version to the sun term
	// only; this pass does not have that option.
	#define SSS_STRENGTH 0.6 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.9 1.0]

	// The most this effect may darken a pixel by, as a fraction of its own colour.
	#define SSS_DARK_LIMIT 0.55 // [0.0 0.25 0.4 0.5 0.55 0.6 0.7 0.8 0.9]

	// How many samples the ray takes. Sundial's default is 12 and the step length
	// is fixed independently of this, so raising it samples the same ray more
	// finely rather than reaching further.
	#define SSS_SAMPLES 12 // [6 8 9 10 12 14 16 18 20 25 30]

	// The step, as a fraction of the screen, from Sundial's
	// `stepSize *= 0.003 * 12.0 / SCREEN_SPACE_SHADOW_SAMPLES`. The 12 is their
	// reference sample count, and it stays here so that the total reach is the same
	// 0.036 of the screen at any setting of SSS_SAMPLES - which is what makes the
	// shadow's length independent of the step count, and independent of the field
	// of view.
	const float SSS_SCREEN_STEP = 0.003;

	// Sundial's shadowDistance, used by the effect's own fade at the end. The
	// caller's shadow distance is a different number and is not consulted.
	const float SSS_DISTANCE = 120.0;
#endif

// The frame number, so that the dither below can move from frame to frame.
uniform int frameCounter;

// The size of one texel, for the origin nudge in ScreenSpaceShadow. Declared here
// rather than assumed: this file is included by more than one program and not all
// of them declare it themselves.
uniform vec2 texelSize;

// This frame's sub-pixel offset, in the same units the vertex programs add to the
// clip position (lib/taa.glsl computes it, shaders.properties exposes it as a
// custom uniform). The deferred pass does not include lib/taa.glsl, so it is
// declared here; this file is only included from that one program, so there is no
// second declaration to collide with.
uniform vec2 taaJitter;

// Cheap per-pixel value in 0..1, used to offset the first step of the ray so that
// neighbouring pixels do not march through the same sample positions.
//
// The offset also moves from one frame to the next, and that is the whole reason
// the temporal filter can do anything about this noise. A value that depended on
// the pixel alone is the *same* value in the history as it is in the current
// frame, so averaging the two averages the noise with itself and keeps it in
// full. Noise is only removable over time if it is different every frame, which
// is what the shift below makes it.
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

#ifdef SCREENSPACE_SHADOWS
	// How far along the ray it gets before it reaches one of the screen's four
	// edges, taken from Sundial (libs/GbufferData.glsl:444-458).
	//
	// The parameter is where `origin + direction * t` projects to x = target on the
	// x axis, and the same on y; SssTraceLength asks for all four combinations and
	// keeps the smallest.
	//
	// Sundial compares the four answers as float bit patterns, because a division by
	// zero produces an infinity or a NaN and a plain min would keep the NaN - every
	// comparison with a NaN is false, so a NaN silently wins. That trick needs
	// floatBitsToUint, which this pack's #version 150 does not have without an
	// extension, so the same guarantee is spelled out instead: `t > 0.0` is false
	// both for a NaN and for a non-positive answer, so each becomes the sentinel and
	// can never win the min. The behaviour is the reference's; the spelling is not.
	float SssAxisReach(
		float origin, float direction, float originW, float directionW, float target
	) {
		float t = (target * originW - origin) / (direction - target * directionW);
		return t > 0.0 ? t : 1.0e6;
	}

	// How far along the ray it may travel before it leaves the screen, or reaches
	// the far plane's neighbourhood.
	float SssTraceLength(vec4 origin, vec4 direction) {
		float reach = SssAxisReach(origin.x, direction.x, origin.w, direction.w, 1.0);
		reach = min(reach, SssAxisReach(origin.x, direction.x, origin.w, direction.w, -1.0));
		reach = min(reach, SssAxisReach(origin.y, direction.y, origin.w, direction.w, 1.0));
		reach = min(reach, SssAxisReach(origin.y, direction.y, origin.w, direction.w, -1.0));

		// Sundial caps this at `far + 32.0`: a ray that reaches the far plane has
		// nothing left behind it that could occlude it.
		return min(reach, far + 32.0);
	}

	// The shadow at one fragment, as a fraction of the light that reaches it: 1.0
	// where nothing is in the way, and 0.0 where the ray is blocked by something
	// that is plausibly the occluder.
	//
	// viewPos is this fragment's position in view space; lightDirection points from
	// it towards the sun, also in view space. NdotL and noise are what Sundial's
	// function takes and what the fade and the first-sample offset need; NdotL is
	// the *geometric* normal's, in whatever space lightDirection is in, and the
	// caller is responsible for that - the note at the call says how.
	float ScreenSpaceShadow(
		sampler2D depthTexture,
		mat4 projection,
		mat4 projectionInverse,
		vec3 viewPos,
		vec3 lightDirection,
		float NdotL,
		float noise
	) {
		// Sundial projects the ray's ends through the projection matrix by hand
		// rather than with a matrix multiply, because it needs the clip-space
		// direction as a separate vector to intersect with the screen edges. The
		// arithmetic is theirs, term for term.
		vec4 originProjPos = vec4(
			vec3(projection[0].x, projection[1].y, projection[2].z) * viewPos,
			-viewPos.z);
		originProjPos.z += projection[3].z;
		originProjPos.xy += projection[2].xy * viewPos.z;

		// Sundial's TAA compensation, which the first version of this port dropped
		// and which is very likely why the stripes survived the port (batch 655).
		//
		// The geometry in the depth buffer was rasterised with this frame's jitter
		// added to its clip position, so the surface this fragment belongs to is not
		// where the unjittered projection puts it - it is half the jitter away, in
		// screen units. Without this line the ray starts from a slightly different
		// point than the depth samples it compares against, and at a grazing sun
		// every sample then lands on the neighbouring surface instead of on the ray:
		// the whole slope reads as occluded in bands, which is exactly the report.
		//
		// Adding `jitter * w` before the perspective divide is Sundial's own
		// formulation; ours is the same number in our units. taaJitter is the NDC
		// offset the vertex programs add (lib/taa.glsl, shaders.properties), so the
		// screen offset is half of it.
		originProjPos.xy += taaJitter * originProjPos.w;

		float projScale = 0.5 / originProjPos.w;
		vec4 originCoord = vec4(originProjPos.xyz * projScale + 0.5, 0.0);

		vec4 projDirection = vec4(
			vec3(projection[0].x, projection[1].y, projection[2].z) * lightDirection,
			-lightDirection.z);
		projDirection.xy += projection[2].xy * lightDirection.z;

		float traceLength = SssTraceLength(originProjPos, projDirection);

		vec4 targetProjPos = originProjPos + projDirection * traceLength;
		float targetProjScale = 0.5 / targetProjPos.w;
		vec4 targetCoord = vec4(targetProjPos.xyz * targetProjScale + 0.5, 0.0);

		// The direction of the ray in screen space, normalised in xy, and the origin
		// pushed one and a half texels along it so that the first sample is not the
		// surface the ray starts on.
		vec4 stepSize = targetCoord - originCoord;
		stepSize *= inversesqrt(dot(stepSize.xy, stepSize.xy));
		originCoord += stepSize * max(texelSize.x, texelSize.y) * 1.5;

		float shadow = 1.0;

		// The step is a fixed fraction of the screen, so the total reach is fixed at
		// SSS_SCREEN_STEP * 12 whatever SSS_SAMPLES is: the count changes how finely
		// the same ray is sampled, never how long it is. This is the property that
		// makes the shadow shorten under zoom instead of dissolving into stripes.
		stepSize *= SSS_SCREEN_STEP * 12.0 / float(SSS_SAMPLES);

		targetCoord = originCoord + stepSize * float(SSS_SAMPLES);

		// Sundial works in reciprocal distance, which is what view-space depth is
		// proportional to: 1/length rather than length.
		float viewLength = inversesqrt(dot(viewPos, viewPos));

		// The effect fades out at the shadow distance, and fades out again where the
		// surface faces the sun - the latter because a face the sun is lighting
		// squarely is where the shadow map is at its most reliable, and where the
		// screen-space guess would be at its least. Both terms are Sundial's.
		float shadowWeight = clamp(1.0 - abs(NdotL) * 10.0, 0.0, 1.0)
			* clamp(1.0 - 1.1 / viewLength / SSS_DISTANCE, 0.0, 1.0);

		vec4 sampleCoord = originCoord + noise * stepSize;
		sampleCoord.z -= 2.0e-7;

		// The thickness window, in the projected depth the comparison is made in. It
		// shrinks with distance because the depth buffer's precision does: at a
		// hundred blocks a fixed window would accept the sky.
		float maximumThickness = 0.0005 * viewLength;
		sampleCoord.z -= maximumThickness;

		for (int i = 0; i < SSS_SAMPLES; i++) {
			// Sundial compares these as bit patterns for the NaN reason noted on
			// SssAxisReach; #version 150 has no floatBitsToUint here, and a plain
			// comparison is enough at this point: sampleCoord is built from finite
			// values and a NaN that did slip through would only cost one extra sample
			// before the guard below stops the loop anyway.
			if (any(greaterThan(sampleCoord.xy, vec2(1.0)))
				|| shadow < 0.01) {
				break;
			}

			float sampleDepth = texture(depthTexture, sampleCoord.xy).r;

			bool hit = abs(sampleCoord.z - sampleDepth) < maximumThickness
				&& sampleDepth < 1.0;

			// Sundial's `shadow *= clamp(absorption - float(hit), 0.0, 1.0)` with
			// absorption at its solid-surface value of 1.0, which makes this a hard
			// decision: one hit and the ray is done.
			shadow *= clamp(1.0 - float(hit), 0.0, 1.0);

			sampleCoord += stepSize;
		}

		return clamp(mix(shadow, 1.0, shadowWeight), 0.0, 1.0);
	}
#endif
