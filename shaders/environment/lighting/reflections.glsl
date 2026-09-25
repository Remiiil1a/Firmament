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
//   - A direction, by asking the sky model for the colour along the reflected
//     view ray, and - with PBR_SSR - by tracing that ray through the depth
//     buffer to find what is actually there.
//   - Roughness, by bending the ray towards the surface normal as roughness
//     grows, so that a rough surface reflects the sky above it rather than a
//     mirror image of whatever happens to be opposite, and by fading out the
//     grazing boost that makes a smooth surface a mirror.
//
// It runs in the deferred pass rather than where each surface is drawn, because
// that is the first point at which the depth buffer describes a finished frame.
// An opaque surface cannot trace against the frame it is being drawn in. The
// material it works from - normal, roughness, reflectance, and how much sky
// reaches the fragment - is written into the buffers by the programs that draw
// surfaces and read back here; see the material outputs at the bottom of lit.fsh.

#if defined(PBR_REFLECTIONS) || defined(PBR_SSR)

	// The direction the environment is sampled in, in world space.
	//
	// A rough surface scatters the reflection over too wide a range of directions
	// to show a mirror image, so the ray is bent towards the normal as roughness
	// grows. At full roughness it looks straight up, which is the average of the
	// sky over the surface rather than a reflection of anything in particular.
	//
	// The mixture is renormalized because mixing two unit vectors does not
	// produce one, and both the sky model and the raytracer need a direction.
	vec3 PbrReflectionDirection(
		vec3 worldNormal,
		vec3 viewDirection,
		float roughness
	) {
		// reflect() expects the direction the view ray is travelling in, whereas
		// viewDirection points back towards the camera, hence the negation.
		vec3 reflected = reflect(-viewDirection, worldNormal);

		return normalize(mix(
			reflected,
			worldNormal,
			clamp(roughness * PBR_REFLECTIONS_ROUGHNESS, 0.0, 1.0)));
	}

	// Fresnel by the model Adobe uses, which interpolates between the
	// reflectance at normal incidence and the one at 82 degrees instead of
	// taking everything to white.
	//
	// [Kutz et al. 2021, "Novel aspects of the Adobe Standard Material"] - and
	// Sundial's implementation of it, which is where the constants are from.
	//
	// With an F82 of 1.0 the term it corrects by is zero and this is Schlick
	// exactly, which is why it can replace Schlick outright rather than being a
	// branch: every surface that is not one of the tabulated metals takes that
	// path and is left bit for bit as it was.
	vec3 F_AdobeF82(vec3 f0, vec3 f82, float VdotH) {
		const float K = 49.0 / 46656.0;

		// The base is clamped to zero, and that is not tidiness: it is the fix
		// for a black blot on reflective surfaces. See PBR_PORTING.md 139.
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
		// the whole Fresnel term is, so the reflection is a NaN, and composite3
		// adds it to the picture - where the value added and the value checked
		// were not the same variable, so it reached the screen and was drawn as
		// black. It reads as a blot rather than as speckles because the
		// condition is a band of angles rather than a single pixel, and it is
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
	// with the threshold generalised into PBR_REFLECTION_SMOOTHNESS_MIN: at its
	// default the two are the same expression, smoothness - (1 - smoothness),
	// and at either extreme it degenerates as expected - 1.0 lets everything
	// through, 0.0 is the plain square root of the smoothness.
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
	// drawn over the top of one - reads as a zero normal, a roughness of one and
	// no reflectance. Rejecting those here is what keeps a reflection from being
	// computed from whatever happened to be left in the buffer, and it is also
	// why the material outputs at the bottom of lit.fsh carry neutral values
	// rather than being skipped when a material has nothing to say.
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
	// sky visible from it; see PBR_REFLECTION_SKY_MIN for the option and for the
	// one case this cannot tell apart.
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

#endif // PBR_REFLECTIONS || PBR_SSR
