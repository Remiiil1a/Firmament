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
	vec3 PbrReflectionFresnel(vec3 f0, float NdotV, float roughness) {
		return mix(
			F_Schlick(f0, NdotV),
			f0,
			clamp(roughness, 0.0, 1.0));
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
