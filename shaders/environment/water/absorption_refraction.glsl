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

// Apply a water absorption heuristic using the results of a refraction trace.
vec3 RefractionBasedWaterAbsorption(
	vec3 refractedScreenPos,
	vec3 viewPosRefracted,
	vec3 upVector,
	vec3 viewPos,
	bool verticalNormal,
	vec3 background,
	sampler2D skylightBuffer,
	// The sky light on this fragment's own surface, used instead of the buffer
	// above by programs that are not given one. See where it is read below.
	float surfaceSkyLight,
	// How deep into the water this fragment is, from 0.0 at the surface to 1.0
	// at the depth where skylight has been fully attenuated. Handed back rather
	// than kept here because the scattering below needs the same number, and it
	// has to be the one this function actually arrived at rather than a second
	// estimate of it.
	out float waterDepth
) {
	// Every path below overwrites this, but it is set here as well so that the
	// caller cannot be handed an uninitialised value if one ever stops doing
	// that.
	waterDepth = 1.0;

	if (refractedScreenPos.z < 1.0) {
		// The vertical distance between this fragment and what it refracts
		// gives a reasonable indication of the water depth only when this
		// fragment's own normal is vertical, that is, when we are looking at
		// water's top face. As a result, we use the sky light value of the
		// background when reflecting through water sides or when underwater,
		// since in those cases it is a more reliable heuristic.
		if (verticalNormal) {
			// `verticalNormal` is `worldNormal.y > 0.9999` at the call site,
			// so this branch really does mean the top face.
			//
			// We take the vector between the refracted position (the lake bed
			// the trace landed on) and this fragment's own position, and
			// project it onto `upVector` to get its vertical component. That is
			// not the same as the length of the vector unless the two positions
			// are exactly one above the other, but it is the number we want.
			//
			// `upVector` is world-up expressed in view space - the caller
			// passes `gbufferModelView[1].xyz` - so this dot product is the
			// world-space Y difference, without transforming either position
			// back to world space first.
			//
			// This only requires assuming that a straight line in world space
			// is also straight in view space, which we already assume in the
			// refraction trace & reflection tracing code.
			float depthInMeters = dot(viewPos - viewPosRefracted, upVector);

			// Batch 671: this is in metres now, not in a normalised 0..1
			// depth - the absorption is Beer's law and it wants the length
			// the light travelled. The cap is at sixteen metres because
			// that is where skylight has been fully attenuated, and this
			// file used to normalise to one at fifteen blocks.
			//
			// The clamp is not cosmetic: past sixteen blocks the falloff
			// would keep running exponentially off the top of the scale,
			// and the water would go blacker with depth than any of the
			// coefficients were chosen to do.
			waterDepth = clamp(depthInMeters, 0.0, 16.0);
		} else {
			// Skylight is attenuated by one level per vertical metre below
			// the surface, so the same number comes out of it directly as
			// metres (batch 671; upstream 0.9.0 writes it this way). Sixteen
			// levels of it are all the light the game carries, so sixteen is
			// the deepest this can describe, and it starts at one metre so
			// that water right at the surface is not unnaturally clear.
			//
			// Both arms of the #if below use the same arithmetic on purpose;
			// they differ only in where the skylight comes from.
			#if defined(EXTERNALLY_DEFINED_UNIFORMS)
				// This program was not given this pack's sky light buffer: Voxy
				// hands its shaders their own set of uniforms and textures, and
				// this one is not among them (see voxy.json). Sampling it anyway
				// returned nothing, which reads as a sky light of zero - and a
				// sky light of zero is the deepest water this heuristic can
				// describe, so distant Voxy water came out at full absorption
				// while the same water inside the render distance, which reads
				// the real buffer, came out shallow. That is what made water on
				// LOD terrain darker than the water next to it.
				//
				// The sky light on this fragment's own surface is what stands in
				// for it. The buffer is read for the sky light of the background
				// - the lake bed - and over open water the two agree closely,
				// which is also why the underwater absorption in
				// environment/lighting/diffuse.glsl makes the same substitution.
				waterDepth = (-16.0) * surfaceSkyLight + 16.0;
			#else
				float skylight = RefractionSafeSample(
					skylightBuffer,
					refractedScreenPos.xy
				).r;
				waterDepth = (-16.0) * skylight + 16.0;
			#endif
		}

		// TODO: Based on the render distance, fade away to the background to
		// have a smooth transition!
	} else {
		// In this case, we hit a sky fragment, and naturally there is no
		// skylight or reasonable world Y height available.
		//
		// Instead, we just have to assume that most of the time this means that
		// we went through a lot of water, that is, we are at full water depth.
		// This works most of the time, but sometimes (ie, looking at a
		// waterfall), the water is not actually that thick, so this looks off.
		//
		// To mitigate this, as a heuristic, if we are within 24 blocks of this
		// water surface, then we start to assume that the water is not actually
		// that thick and do not apply as much water absorption.
		//
		// Note: This is also required to see the sun/moon through less thick
		// volumes of water.
		//
		// `fadeFactor` measures depth along the camera's forward axis rather
		// than true distance: `viewPos.z` is negative in front of the camera,
		// so `-viewPos.z` is how far ahead of the camera this fragment is.
		// Looking down at a steep angle from high above, one screen pixel spans
		// many blocks of water, so this is not the distance to the water
		// surface itself and the fade is not tied to a block depth. The
		// denominator is 24.
		//
		// What `background` was scaled by here until batch 447 was
		// `1.0 - fadeFactor`, and that line is one half of what drew a flat black
		// band under the horizon on level-of-detail water. Past 24 blocks the
		// factor is exactly zero, so the light that came through the surface was
		// thrown away and the absorption below was left multiplying nothing. The
		// pixel was zero - not dark water, which the absorption is perfectly
		// capable of being: sixteen metres of it is exp(-16, -3, -1) for the
		// TROPICAL set, a deep blue-green with the red gone. That is what the
		// depth below is for, and what a second, unbounded darkening on top of a
		// bounded one took away.
		//
		// It was only half, and this file carried the other half wrongly for two
		// batches. Removing the line on its own changed nothing, because the light
		// it was multiplying was already black: the pixels this branch lands on
		// are pixels nothing ever drew - the game's sky quads do not cover the
		// view just below the horizon - so what is in them is the clear colour.
		// This pack's water is the first thing that ever sampled them, and the
		// other half of the fix is the fill in program/post/copy_and_fog.fsh
		// (batch 451), which gives those pixels the sky. With that in place the
		// absorption is handed the sky and the water comes out the deep
		// blue-green it should have been.
		// Batch 671: no estimate of the depth at all here. What the pixel
		// does get is the distance the ray travelled through the water - added
		// below, like every other path - so the water in front of the sky is
		// as thick as it actually was along the view ray, instead of being
		// assumed deep and then faded back for the first 24 blocks.
		waterDepth = 0.0;
	}

	// The length of the path through the water, which is the number Beer's law
	// wants. Batch 671: upstream 0.9.0 measures it as the difference along Z
	// rather than with distance(), and its own note explains why that is a
	// strong approximation - both ends of the segment are mostly along the view
	// direction, and distance() is more expensive.
	//
	// Which of the two forms applies is the camera's own position: in the water
	// the path starts at the eye, out of it the path starts at the surface.
	if (isEyeInWaterFog == 1) {
		waterDepth += abs(viewPos.z);
	} else {
		waterDepth += abs(viewPos.z - viewPosRefracted.z);
	}

	return background * WaterAttenuation(waterDepth);
}
