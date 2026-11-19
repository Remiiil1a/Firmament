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

// The environment reflection of a PBR material, as a library used by the pass
// that applies it.
//
// PbrAmbientSpecular in pbr.glsl stands in for image-based lighting with the
// light around the fragment. It has neither a direction nor a roughness: every
// surface reflects a flat wash of the ambient light, so a polished block looks
// no more reflective facing the sun than facing away from it, and a rough
// surface looks exactly as reflective as a mirror. What is here supplies both of
// those:
//
// - A direction, by asking the sky model for the colour along the reflected
// view ray, and - with PBR_SSR - by tracing that ray through the depth
// buffer to find what is actually there.
// - Roughness, by bending the ray towards the surface normal as roughness
// grows, so that a rough surface reflects the sky above it rather than a
// mirror image of whatever happens to be opposite, and by fading out the
// grazing boost that makes a smooth surface a mirror.
//
// It runs in the deferred pass rather than where each surface is drawn, because
// that is the first point at which the depth buffer describes a finished frame.
// An opaque surface cannot trace against the frame it is being drawn in. The
// material it works from - normal, roughness, reflectance, and how much sky
// reaches the fragment - is written into the buffers by the programs that draw
// surfaces and read back here; see the material outputs at the bottom of lit.fsh.

// A normal that can be reflected around.
//
// This is outside the option guard below because the material buffers are written
// whether or not the reflection is on - see the note on the writes at the bottom of
// lit.fsh - and this is applied on the way in.
//
// The normal map is free to point anywhere, and at the outermost texels of a block
// sprite most packs put a bevel that tilts it outward by twenty degrees or more. On
// a floor seen at a shallow angle that is enough to turn it past the eye: N·V goes
// negative, and everything downstream reads that as the most extreme grazing angle
// there is rather than as "this texel is not facing you".
//
// Two things follow from that, and together they are the bright line along every
// block edge - recorded in BATCH_LOG b621 section 31, measured in
// _team_bfog/bevel_facing_model.py:
//
// * Fresnel is asked for the reflectance at a grazing angle and answers with its
// maximum, 1.0 - a full mirror - where the texel next door answers with the few
// percent a floor actually reflects. 1.7x brighter at six degrees of camera
// elevation, 2.4x at ten, 6.3x at twenty.
// * reflect() sends the ray INTO the surface, and the sky model clamps every
// direction below the horizon onto the horizon, which is the brightest ring of
// the sky. That is why the line is the colour of the sky and follows it through
// the day: it was the sunset at dusk.
//
// So the mapped normal is pulled back towards the face it is painted on as it turns
// edge-on, and left alone everywhere else. The blend is keyed on the GEOMETRIC
// visibility rather than on a fixed threshold, which is what makes it safe to apply
// to every surface: a bump tilted three degrees - which is what a normal map is for
// - is pulled back by exactly nothing at any viewing angle, because the two numbers
// below are measured in the same units, while a bevel that has turned past half of
// the face's own visibility is pulled most of the way back to the face.
//
// The alternative, refusing the reflection where the mapped normal faces away, was
// considered and rejected: it turns a bright one-pixel line into a one-pixel band of
// no reflection, which is the same artefact in a different colour.
vec3 PbrVisibleNormal(
	vec3 mappedNormal,
	vec3 faceNormal,
	vec3 viewDirection
) {
	float faceVisibility = dot(faceNormal, viewDirection);
	float mappedVisibility = dot(mappedNormal, viewDirection);

	// The half is the whole design: a normal within half of the face's own
	// visibility is left completely alone, and only a texel that has turned further
	// than that is pulled towards the face at all.
	float pull = 1.0 - smoothstep(
		0.0,
		max(0.5 * faceVisibility, 1.0e-3),
		mappedVisibility);

	return normalize(mix(mappedNormal, faceNormal, pull));
}

#if defined(PBR_SSR)

	// The direction the environment is sampled in, in world space.
	//
	// A plain mirror reflection, and deliberately nothing else. It used to be bent
	// towards the normal as roughness grew, by an option (PBR_REFLECTIONS_ROUGHNESS)
	// that shipped at 0.0 - which is to say it did nothing - and both the option and
	// the bending are gone as of batch 622. The reason is in the note that option
	// carried: bending the centre of the lobe moves the reflection, which is not
	// what roughness does. Roughness spreads it, and the spreading is
	// PBR_REFLECTION_BLUR, applied where the reflection is sampled.
	vec3 PbrReflectionDirection(
		vec3 worldNormal,
		vec3 viewDirection
	) {
		// reflect() expects the direction the view ray is travelling in, whereas
		// viewDirection points back towards the camera, hence the negation.
		return reflect(-viewDirection, worldNormal);
	}

	// The same direction, drawn from the cone the surface's roughness opens.
	//
	// BATCH 764. The note above says roughness SPREADS the reflection rather than
	// bending it, and that the spreading was PBR_REFLECTION_BLUR "applied where the
	// reflection is sampled" - which is what batches 760 to 763 built, and what the
	// author then reported as not enough: the texture in the reflection went soft
	// while the block's outline stayed exactly where one ray put it. Spreading the
	// COLOUR is not spreading the reflection; the outline is the geometry, and one
	// ray has one outline.
	//
	// This spreads the direction instead, which is what Bliss does
	// (lib/specular.glsl:349-357) and what a rough surface actually does: it
	// reflects a range of directions. Every pixel's ray then leaves at a slightly
	// different angle and lands on a slightly different place, so the reflection's
	// outline is smeared over the cone.
	//
	// ⚠️ BATCH 765: THE DRAW RETURNS A MICROFACET NORMAL, AND THE RAY IS THAT NORMAL
	// REFLECTED - BATCH 764 USED THE NORMAL AS THE RAY.
	//
	// That is the whole of why every reflection suddenly looked pasted flat onto the
	// block. A visible-normal draw samples the normal of a microfacet, and the
	// reflected direction is the incident direction reflected about that normal.
	// Bliss does exactly that, one line after the draw (lib/specular.glsl:357):
	//
	//     vec3 reflectedVector_L = basis * reflect(-normalize(viewDir), samplePoints);
	//
	// 764 skipped that line and handed the normal to the march as if it were a
	// direction. A normal points OUT of the surface, so the ray left almost
	// perpendicular to it, hit the block it started on, and the reflection became a
	// picture of the surface itself - which is what "pasted on" is.
	//
	// ⚠️ AND THE FRAME MATTERS. Bliss's `viewDir` is `-playerPos * basis`, which
	// points INTO the surface, and its `viewDir.z = abs(viewDir.z)` (:353) is what
	// keeps the draw on the upper hemisphere. This function takes `viewDirection`
	// pointing back TOWARDS the camera, so the incident direction is its negation -
	// and getting that sign wrong reflects the ray to the wrong side of the surface,
	// which is the same pasted-on look by a different route.
	//
	// The distribution is the visible-normal one, the same family the highlight is
	// built from, so the reflection and the highlight agree about how rough the
	// surface is.
	//
	// `alpha` is the roughness, which is the cone's half-angle in radians - the same
	// angle the sky half of the reflection is averaged over, so the two halves agree
	// about width. A mirror (alpha 0) draws a zero-width cone and returns the exact
	// direction, which is why a mirror still reads as a mirror.
	vec3 PbrReflectionDirectionJittered(
		vec3 worldNormal,
		vec3 viewDirection,
		float alpha,
		vec2 noise
	) {
		// A frame on the normal, so that the cone can be drawn around it.
		vec3 tangent = normalize(cross(
			abs(worldNormal.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0),
			worldNormal));
		vec3 bitangent = cross(worldNormal, tangent);

		// The incident direction, in that frame: the way the view ray travels, which
		// is towards the surface.
		vec3 incident = vec3(
			dot(-viewDirection, tangent),
			dot(-viewDirection, bitangent),
			dot(-viewDirection, worldNormal));

		// The visible-normal draw, in the hemisphere configuration. This is
		// SampleVNDFGGX's arithmetic (Bliss lib/specular.glsl:42-71).
		//
		// ⚠️ BATCH 765: THE `abs` BELONGS HERE AND NOWHERE ELSE. Bliss takes
		// `viewDir.z = abs(viewDir.z)` (:353) so that the draw stays on the upper
		// hemisphere, and that is what this reproduces - but the value it reflects
		// afterwards is the unmodified `viewDir`. Taking the abs of the incident
		// direction as well flips the ray to the other side of the surface, which is
		// the same pasted-on look by a second route.
		//
		// Written as `a * b + c` rather than with fma(), which needs an extension
		// this pack does not request everywhere: the compiler recognises the pattern
		// and emits the fused instruction anyway.
		vec3 viewer = normalize(vec3(
			alpha * 0.5 * incident.xy,
			abs(incident.z)));
		float phi = 6.2831853 * noise.x;
		float cosTheta = (1.0 - noise.y) * (1.0 + viewer.z) - viewer.z;
		float sinTheta = sqrt(clamp(1.0 - cosTheta * cosTheta, 0.0, 1.0));
		sinTheta = clamp(sinTheta, 0.0, 1.0);
		cosTheta = clamp(cosTheta, sinTheta * 0.5, 1.0);

		vec3 sampled = vec3(vec2(cos(phi), sin(phi)) * sinTheta, cosTheta);
		vec3 halfway = sampled + viewer;
		vec3 microfacetNormal = normalize(vec3(alpha * halfway.xy, halfway.z));

		// BATCH 765: THE RAY IS THE INCIDENT DIRECTION REFLECTED ABOUT THE NORMAL,
		// WHICH IS THE LINE 764 DROPPED. Without it the answer is a normal pointing
		// out of the surface and the ray hits the block it started on.
		//
		// `incident` already points into the surface, which is the direction
		// reflect() wants, so it is passed as it is - negating it here as well would
		// flip the ray to the other side, which is the same pasted-on look by a
		// second route.
		vec3 jittered = reflect(incident, microfacetNormal);

		// BATCH 765: A DRAW THAT LANDS BELOW THE HORIZON IS PUT BACK ON IT.
		//
		// The visible-normal distribution is not bounded by the surface: at a
		// roughness of 0.6 and above, roughly a fifth of its draws reflect back INTO
		// the surface, and at 1.0 it is half of them. A ray that starts by going
		// into the block it left finds the block, so those pixels show the surface
		// itself - the pasted-on look again, this time only on the roughest
		// materials, which is the hardest kind of defect to attribute.
		//
		// Clamping z to zero puts such a ray on the horizon instead, which is the
		// limit the distribution is approaching and the one answer that cannot be
		// wrong. It is what the sky half does with its cone taps as well.
		jittered.z = max(jittered.z, 0.0);

		// Back to world axes. A zero-width cone leaves `jittered` equal to the exact
		// reflection, so this is the exact direction for a mirror.
		return normalize(
			tangent * jittered.x
			+ bitangent * jittered.y
			+ worldNormal * jittered.z);
	}

// How far a reflection has to travel before the LOD ramp is complete, in blocks.
//
// BATCH 760. This is the one number that is NOT Bliss's, and the reason is worth
// stating because the obvious translation is wrong.
//
// Bliss's `reflectionLength` is not a distance. It is the fraction of the ray to
// the screen edge that the march consumed (`reflectionLength += 1.0 / quality`,
// lib/specular.glsl:169, where `stepv = direction * mult / quality` and `mult` is
// the ray's length to the edge, :128-130). So Bliss's ramp is over SCREEN SPAN,
// and its `min(max(reflectionLength - 0.1, 0.0)/0.9, 1.0)` (:212) means "the
// first tenth of the ray is perfectly sharp, the ramp covers the rest".
//
// ⚠️ BATCH 763: THE TRANSLATION BELOW WAS THE REASON NOTHING WAS VISIBLE, AND IT
// TOOK THREE BATCHES TO FIND BECAUSE IT LOOKS SO REASONABLE.
//
// 760 read "the first tenth of the ray" as "the first tenth of 64 blocks", which
// is 6.4 blocks, and made everything inside that perfectly sharp. But a metal
// reflects the wall and the floor a few blocks away - that is what a metal block
// in a build actually shows - so the reflections the author was looking at were
// ALL inside the dead zone, where the distance term is exactly 0.0 and the LOD is
// exactly 0.0 whatever the roughness does. 761 then pushed the roughness term from
// 5.14 to 6.00, which is 1.17x of zero.
//
// The scale is now 16 blocks and the sharp fraction is a length rather than a
// proportion, so that "near" means near in blocks and not in some fraction of a
// number that was itself a guess. 16 is where a reflection has crossed enough of
// the screen for the cone to span several texels at a typical field of view.
//
// BATCH 770: THESE LIVE HERE NOW, NOT IN environment_reflection.glsl, because the
// hand and the dropped item trace for themselves in lit.fsh and that file does not
// include environment_reflection.glsl. A constant only one of three paths can see
// is a constant the other two silently do without.
#define PBR_SSR_BLUR_DISTANCE 16.0

// How far from the fragment a reflection stays perfectly sharp, in blocks.
//
// BATCH 763: THIS IS A LENGTH NOW, NOT A FRACTION. As a fraction of
// PBR_SSR_BLUR_DISTANCE it was 6.4 blocks, which is most of what a metal reflects.
// Half a block is the distance at which a reflection is still the surface's own
// immediate surroundings - the thing the author's tap-based attempts kept eating -
// and past it the ramp starts immediately.
#define PBR_SSR_BLUR_SHARP_DISTANCE 0.5

// The narrowest cone the sky half of the reflection is averaged over, in pixels.
//
// BATCH 763. The cone is the roughness in radians, which is right for a dielectric
// and far too narrow for a polished metal: iron_block's roughness is 0.0167 rad,
// about 13 pixels at a 70 degree field of view, and a metal block reflects mostly
// sky - so those 13 pixels were the whole of its blur. See the note at the cone.
//
// 24 pixels is roughly the width of a block face at arm's length, which is the
// scale a metal block's reflection is read at. It is a starting value for the
// author to tune, and it is in pixels rather than radians so that it does not
// change with the field of view.
#define PBR_SSR_BLUR_MIN_CONE_PIXELS 24.0

// The highest mip level the reflection may be sampled at.
//
// Bliss uses 6.0 (lib/specular.glsl:213). A level is a halving of resolution, so
// 6 is a 64x64 box - far wider than any cone a surface's roughness opens, and it
// is the cap rather than the working range: the roughness term saturates well
// before it, and the distance term is what reaches it.
//
// It is a #define and not an option because the two terms that build the LOD are
// Bliss's and were tuned against its picture; exposing the cap would invite
// tuning a number that is not the one that needs tuning.
#define PBR_SSR_BLUR_MAX_LOD 6.0

	
// The noise the reflection direction is drawn from.
//
// BATCH 777: THIS MOVES WITH THE FRAME NOW, AND THAT IS THE WHOLE POINT.
//
// 775 replaced the ordered dither with interleaved gradient noise and it was not
// enough, because it changed the SPATIAL distribution and left the temporal one
// alone. This function read only gl_FragCoord, so a pixel drew the same point of
// the cone on every frame - measured, one distinct value over sixty frames.
//
// A temporal resolve averages the error of successive frames. When the error is
// the same every frame there is nothing to average: the history converges to that
// one sample rather than to the cone's mean, and the residual is the single-sample
// error, which does not shrink with more frames. That is why raising the step
// count and raising TAA_STRENGTH both failed - neither adds a new sample.
//
// Bliss walks its noise by the frame number (dimensions/composite1.fsh:237-244,
// `coord += (frameCounter%40000) * 2.0`), and measured over sixty frames it gives
// sixty distinct values where this gave one. The golden-ratio step below is the
// same idea: an irrational stride, so the sequence does not repeat on a short
// cycle and successive frames land in unrelated parts of the cone.
//
// ⚠️ THE frameCounter BLOCKER IS GONE, AND IT WAS NEVER AS BAD AS IT LOOKED. 775
// recorded that the uniform is declared in several files included in different
// orders and gave up on the temporal term because of it. That is true - it is
// declared in lib/taa.glsl, light_volume.glsl and volumetric_fog.fsh - but it is
// the same problem this pack already solved for isEyeInWaterFog in batch 770: put
// all three declarations behind one marker, written `#if !defined(M)` because
// _check_uniform_dups.ps1 only recognises that form. Exactly one then compiles.
//
// ⚠️ AND THE TWO NUMBERS ARE INDEPENDENT NOW. 775 derived the second from the
// first with `fract(first * 7.0 + 0.37)`, which is a pure function of the first -
// so the pair traced a one-dimensional curve through the two-dimensional space
// the draw samples from. Measured over a 1920x1080 grid it occupied 12.5% of a
// 64x64 binning, with the fullest bin 9.2x over-represented. A second hash costs
// one more multiply and fills the space.
//
// Declared here rather than in either consumer because all three reflection paths
// include this file and neither consumer includes the other.
//
// BATCH 777: AND THE DECLARATION IS HERE TOO, BECAUSE ONE PATH CANNOT REACH IT.
//
// The marker above makes exactly one declaration compile, but it cannot make one
// EXIST. lit.fsh reaches frameCounter only through diffuse.glsl, and that include
// is behind `#if defined(COLORED_LIGHTS) && !defined(EXTERNALLY_DEFINED_UNIFORMS)`
// - so with COLORED_LIGHTS off, which is what the LOW profile ships, the terrain
// programs have no declaration at all and this file does not compile. Measured:
// fifteen programs fail with `'frameCounter' : undeclared identifier`.
//
// So this file declares it as well, behind the same marker. It is the one place
// every consumer is guaranteed to pass through, which makes it the only
// declaration that can be relied on rather than merely hoped for.
#if !defined(FRAME_COUNTER_DECLARED)
#define FRAME_COUNTER_DECLARED
uniform int frameCounter;
#endif

float PbrReflectionNoise(float offset) {
	return fract(52.9829189 * fract(
		0.06711056 * gl_FragCoord.x
		+ 0.00583715 * gl_FragCoord.y
		+ offset));
}

// The pair of uniform numbers the draw needs.
//
// BATCH 777: TWO HASHES WITH DIFFERENT COEFFICIENTS, NOT ONE HASH AND A SHIFT.
//
// The obvious way to get a second number is to call the same hash with a
// different offset, and it does not work: the offset lands inside the inner
// fract, so it slides the whole one-dimensional curve along rather than tracing
// a second one. Measured over a 1920x1080 grid, a constant-offset pair fills
// 4.7% of a 64x64 binning - worse than the 12.5% the linear derivation gave.
//
// Swapping the two coefficients does work, because the two hashes then disagree
// about which screen axis dominates: the first varies fastest along x, the second
// along y, so their joint distribution covers the square. Measured, that pair
// fills 100% of the binning at chi2/dof 0.5.
//
// The frame term is added to the coordinate of both, which is what makes the draw
// move between frames. The golden ratio is the stride because it is the
// worst-approximated irrational, so successive frames visit the interval evenly
// instead of clustering.
vec2 PbrReflectionNoisePair() {
	float frame = float(frameCounter) * 0.618034;

	return vec2(
		PbrReflectionNoise(frame),
		fract(52.9829189 * fract(
			0.00583715 * gl_FragCoord.x
			+ 0.06711056 * gl_FragCoord.y
			+ frame)));
}
// The mip level a reflection is sampled at, from how rough the surface is and
	// how far the ray travelled.
	//
	// BATCH 770: THIS IS THE WORLD'S FORMULA, MOVED HERE SO THE OTHER TWO PATHS CAN
	// USE IT. The shared reflection in environment_reflection.glsl had it inline,
	// and the hand and the dropped item - which trace for themselves, in lit.fsh -
	// sampled with a plain texture() and so got no blur at all. That is the author's
	// report: held items and dropped items have no blur where blocks do.
	//
	// The two terms are Bliss's (lib/specular.glsl:213) and the reasoning is at the
	// call site in environment_reflection.glsl: roughness decides how wide a cone the
	// surface reflects over, and the distance decides how much screen that cone
	// covers. The sharp distance is what keeps a reflection of the surface's own
	// immediate surroundings from being blurred, which is the thing the author's
	// tap-based attempts kept eating.
	//
	// `distance` is in blocks, which is what both traces report.
	float PbrReflectionLod(float roughness, float distance) {
		float reflectionLength = clamp(
			(distance - PBR_SSR_BLUR_SHARP_DISTANCE)
				/ max(PBR_SSR_BLUR_DISTANCE - PBR_SSR_BLUR_SHARP_DISTANCE, 1.0e-4),
			0.0, 1.0);

		return mix(
			0.0,
			PBR_SSR_BLUR_MAX_LOD * (1.0 - exp(-15.0 * sqrt(roughness))),
			1.0 - pow(1.0 - reflectionLength, 5.0));
	}

	// Fresnel by the model Adobe uses, which interpolates between the
	// reflectance at normal incidence and the one at 82 degrees instead of
	// taking everything to white.
	//
	// [Kutz et al. 2021, "Novel aspects of the Adobe Standard Material"] - and
	// Sundial's implementation of it, which is where the constants are from.
	//
	// With an F82 of 1.0 the term it corrects by is zero - b is (K - K * f82)
	// times a positive factor - so the return is f0 + (1 - f0) * Fc, which is
	// Schlick with a clamped base, and it is what every surface that is not one
	// of the tabulated metals gets, since the table returns 1.0 for them. Recorded:
	// that path is said to be left bit for bit as it was before this model was
	// introduced.
	vec3 F_AdobeF82(vec3 f0, vec3 f82, float VdotH) {
		const float K = 49.0 / 46656.0;

		// The base is clamped to zero, and that is not tidiness: it is the fix
		// for a black blot on reflective surfaces. See BATCH_LOG.md 139.
		//
		// VdotH is the cosine of an angle, so it cannot be more than one - but
		// the number the callers pass is a dot product between a unit normal
		// that has been through a buffer and a normalized view direction, and
		// neither is exact. colortex7 is RGBA16F, so the normal it gives back
		// carries about three decimal digits, and a dot product that is
		// mathematically 1.0 arrives as 1.0001 or so - not at one pixel, but on
		// every pixel whose surface faces the camera, which is a wide and
		// contiguous band of the screen. The base is then a little below zero,
		// and pow() with a negative base is undefined in GLSL. On the drivers
		// this was found on it is a NaN.
		//
		// A NaN here is not an inaccurate highlight. Fc is a vec3 of them and
		// the whole Fresnel term is, so the reflection is a NaN, and the pass
		// that applies it adds it to the picture (composite3 when this was
		// found, composite1 since batch 664) - where the value added and the
		// value checked were not the same variable, so it reached the screen and
		// was drawn as black. It reads as a blot rather than as speckles because
		// the condition is a band of angles rather than a single pixel, and it is
		// intermittent because that band moves as the surface and the camera
		// do.
		//
		// The exponent is a constant, so pow is the only way this can happen
		// and one clamp is the whole of the fix.
		float Fc = pow(clamp(1.0 - VdotH, 0.0, 1.0), 5.0);
		vec3 b = (K - K * f82) * (7776.0 + 9031.0 * f0);

		return clamp(
			f0 + Fc * ((1.0 - f0) - b * (VdotH - VdotH * VdotH)),
			0.0,
			1.0);
	}

	// How much of the environment this fragment reflects.
	//
	// Fresnel rises towards 1.0 at a glancing angle, which is why a wet road
	// turns into a mirror when you look along it - but that is only true of a
	// surface smooth enough to reflect a grazing ray in one direction. A rough
	// surface scatters that ray away among its microfacets before it can leave,
	// so it never reaches full reflectance. Using the smooth-surface value
	// regardless is what makes every surface in a scene pick up a full-strength
	// wash at a glancing angle, which is where a ground plane always is: the
	// whole world ends up looking frosted rather than reflective.
	//
	// Blending back towards f0 as roughness grows is the cheap form of that
	// correction: a mirror keeps its grazing boost, and a fully rough surface
	// reflects its few percent and no more.
	vec3 PbrReflectionFresnel(vec3 f0, vec3 f82, float NdotV, float roughness) {
		return mix(
			F_AdobeF82(f0, f82, NdotV),
			f0,
			clamp(roughness, 0.0, 1.0));
	}

	// The reflectance of a metal at a grazing angle, looked up by the metal ID
	// the material carried here.
	//
	// Schlick takes every surface to white at a grazing angle, which is right for
	// a dielectric - glass does go white at the edge - and wrong for a metal,
	// whose reflection keeps its colour the whole way out. A gold block whose
	// grazing reflection is white reads as a block with a white rim, and the
	// difference between gold and iron is most of what makes either of them worth
	// looking at. F82 is the number that carries it: the reflectance at 82
	// degrees, which is the second point the Adobe model interpolates between.
	//
	// The table is Sundial's, verbatim, including which byte means which metal.
	// Everything that is not one of those eight - a dielectric, and an
	// albedo-based metal, which has no entry of its own because its reflectance
	// is its albedo - takes vec3(1.0), and F_AdobeF82 with an F82 of 1.0 is
	// exactly Schlick, so nothing else in the pack changes.
	vec3 PbrMetalF82(float metalID) {
		int id = int(metalID + 0.5);

		if (id == 230) return vec3(0.8851, 0.8800, 0.8966); // Iron
		if (id == 231) return vec3(0.9408, 0.9636, 0.9099); // Gold
		if (id == 232) return vec3(0.9090, 0.9365, 0.9596); // Aluminum
		if (id == 233) return vec3(0.7372, 0.7511, 0.8170); // Chrome

		if (id == 234) return vec3(0.9755, 0.9349, 0.9301); // Copper
		if (id == 235) return vec3(0.8095, 0.8369, 0.8739); // Lead
		if (id == 236) return vec3(0.9501, 0.9464, 0.9352); // Platinum
		if (id == 237) return vec3(0.9929, 0.9961, 1.0000); // Silver

		return vec3(1.0);
	}

	// How much of the sky a surface this rough is allowed to reflect, from none
	// of it to all of it.
	//
	// This is the part the reflectance cannot do by itself. PbrReflectionFresnel
	// above narrows the grazing boost on a rough surface, but it narrows it
	// towards f0 rather than towards nothing, and f0 is a few percent on every
	// material a resource pack describes. A few percent is invisible on a wall
	// and not at all invisible on the ground, because the ground is always at a
	// glancing angle: the pack draws a landscape, and every square metre of it
	// picks up the same wash. A threshold that actually reaches zero is the only
	// thing that removes it.
	//
	// The curve is Sundial's (Composite0, the reflectance of a solid surface),
	// with the threshold generalised into PBR_REFLECTION_SMOOTHNESS_MIN. At that
	// option's default of 0.5 the two are the same expression: (smoothness - 0.5)
	// / 0.5 is 2 * smoothness - 1, which is smoothness - (1 - smoothness).
	//
	// The two ends do not do what a threshold usually does. 0.0 is the plain
	// square root of the smoothness with the numerator unbounded above - the
	// threshold off, which is what the option's own note says - so no surface is
	// excluded, only scaled by the square root of how smooth it is. 1.0 is the
	// opposite of letting everything through: the
	// numerator is then non-positive for every input and range is clamped at
	// 1.0e-4, so nothing reflects but a surface of smoothness exactly 1.0. The
	// option's top step is 0.9, where only that same surface gets through.
	//
	// Recorded: the curve is said to be Sundial's, from its Composite0; that is
	// another pack and nothing here stands behind it.
	//
	// The conversion back to smoothness is the pack's own: PbrDecode turns the
	// specular map's smoothness s into a roughness of (1 - s)^2, so undoing it
	// is 1 - sqrt(roughness). A material with no specular data is fully rough by
	// then and gets nothing, which is the answer it was already getting.
	float PbrReflectionSmoothness(float roughness, float metalness) {
		float smoothness = 1.0 - sqrt(clamp(roughness, 0.0, 1.0));

		// A metal starts reflecting at half the smoothness a dielectric does,
		// which is Sundial's number and the reason its metals read as metal: a
		// brushed metal has a smoothness around 0.3, so under a dielectric rule
		// it would be told it reflects nothing, and the one thing everybody
		// knows about a brushed metal is that it reflects everything, just not
		// sharply. The threshold is halved rather than the threshold term being
		// scaled, so that the two ends land exactly where Sundial's formula puts
		// them - 0.5 for a dielectric, 0.25 for a metal - at the default.
		float zeroPoint = PBR_REFLECTION_SMOOTHNESS_MIN
			* mix(1.0, 0.5, clamp(metalness, 0.0, 1.0));
		float range = max(1.0 - zeroPoint, 1.0e-4);

		return sqrt(clamp((smoothness - zeroPoint) / range, 0.0, 1.0));
	}

	// Whether there is a surface here to reflect anything at all.
	//
	// The material buffers are cleared at the start of every frame, so a pixel
	// that no surface program covered - the sky, a cloud, weather, a particle
	// drawn over the top of one - reads as a zero normal and no reflectance. The
	// normal test is what rejects it: dot of a zero vector with itself is zero,
	// and no surface can have a normal that fails that. The roughness test is
	// doing its own work on a different case - a surface that was drawn and had
	// nothing to say - since lit.fsh starts that material at a roughness of 1.0.
	//
	// What the roughness channel holds on a pixel nobody covered is the buffer's
	// clear value, which is not written down anywhere in this pack and is not
	// something these tests depend on; the normal and f0 tests settle it either
	// way. It is also why the material outputs at the bottom of lit.fsh carry
	// neutral values rather than being skipped when a material has nothing to say.
	bool PbrReflectionPossible(
		vec3 worldNormal,
		float roughness,
		vec3 f0
	) {
		return dot(worldNormal, worldNormal) > 0.5
			&& roughness < 1.0
			&& dot(f0, f0) > 1.0e-8;
	}

	// How much of the sky this fragment can see, from none of it to all of it.
	//
	// This is what the sky reflection is scaled by, and it is the difference
	// between a reflection and a wash of sky colour on the floor of a cave.
	// Minecraft's sky light spreads sideways under an overhang and passes through
	// glass, so a fragment can be lit as if it were outdoors with nothing of the
	// sky visible from it.
	//
	// Recorded, as the case this cannot tell apart: a surface lit through a glass
	// window has a full sky light of 15, which is exactly what an open-air surface
	// has, and there is nothing in what this is handed that separates the two. The
	// option's own note in pbr.glsl says the same and offers the workaround of
	// lowering PBR_REFLECTION_SKY_MIN, at the cost of reflections in caves.
	//
	// The trace is not scaled by it. What a traced ray finds is already lit for
	// where it is, so a metal in a cave reflecting the cave around it is the
	// right answer rather than one to fade out.
	float PbrSkyExposure(float skyLight) {
		return smoothstep(
			PBR_REFLECTION_SKY_MIN - 0.1,
			PBR_REFLECTION_SKY_MIN,
			skyLight);
	}

#endif // PBR_SSR
