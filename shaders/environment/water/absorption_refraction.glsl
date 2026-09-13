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
	sampler2D skylightBuffer
) {
	float waterDepth = 1.0;

	if (refractedScreenPos.z < 1.0) {
		// The incident vector only gives a reasonable indication of the water
		// depth when hitting water's top face. As a result, we use the sky
		// light value of the background when reflecting through water sides or
		// when underwater, since in those cases it is a more reliable
		// heuristic.
		if (verticalNormal) {
			// We take the vector between the refracted position (sea floor) and
			// the origin position (ocean surface), and then use the dot product
			// to measure the vertical distance between the two, as the upVector
			// in view space is equivalent to (0, 1, 0) in world space.
			//
			// This is equivalent to subtracting the Y components in world
			// space, but avoids some matrix transformations and similar.
			//
			// This only requires assuming that a straight line in world space
			// is also straight in view space, which we already assume in the
			// refraction trace & reflection tracing code.
			float depthInMeters = dot(viewPos - viewPosRefracted, upVector);

			// This is the reference equation for water depth, where the depth
			// starts at 0.0 at the surface, and goes to a maximum of 1.0 at 15
			// blocks below the water surface, which is intentionally within the
			// same range as sky light attenuation (see details below.
			waterDepth = clamp(
				depthInMeters * (1.0 / 16.0) + 1.0 / 16.0,
				0.0,
				1.0);
		} else {
			// This is an optimized form of the calculation:
			//
			// (1.0 - skylight) * (15.0 / 16.0) + 1.0 / 16.0
			//
			// Which is equivalent to the calculation above, as skylight
			// attenuates overhe 15 blocks.
			//
			// For example, 1 block of depth will have a skylight level of 14.
			// This will be encoded in a lightmap coordinate of 14.5 / 16.0.
			// This is then passed to the following calculation:
			//
			// skylight = (lmcoord.y - (0.5 / 16.0)) * (16.0 / 15.0)
			//
			// This results in a value of 14.0 / 15.0, which, when plugged into
			// the equation above, gives a waterDepth of 0.125.
			//
			// When we plug 1.0 (distance between water surface and bottom) into
			// the original equation based on water height instead of skylight,
			// we get 1/16 + 1/16, or 1/8, which is also equivalent to 0.125,
			// a match.
			//
			// Here is how it is optimized:
			//
			// (1.0 - skylight) * (15.0 / 16.0) + 1.0 / 16.0
			// 15.0 / 16.0 - (15.0 / 16.0) * skylight + 1.0 / 16.0
			// 1.0 - (15.0 / 16.0) * skylight
			// (-15.0 / 16.0) * skylight + 1.0
			//
			// This final form is in the format of a fused multiply-add, which
			// is a single instruction.
			float skylight = RefractionSafeSample(
				skylightBuffer,
				refractedScreenPos.xy
			).r;
			waterDepth = (-15.0 / 16.0) * skylight + 1.0;
		}

		// TODO: Based on the render distance, fade away to the background to
		// have a smooth transition!
	} else {
		// In this case, we hit a sky fragment, and naturally there is no
		// skylight or reasonable world Y height available or reasonable world
		// Y height available.
		//
		// Instead, we just have to assume that most of the time this means that
		// we went through a lot of water, that is, we are at full water depth
		// (ie, full water depth). This works most of the time, but sometimes
		// (ie, looking at a waterfall), the water is not actually that thick,
		// so this looks off.
		//
		// To mitigate this, as a heuristic, if we are within 40 meters of this
		// water surface, then we start to assume that the water is not actually
		// that thick and do not apply as much water absorption.
		//
		// Note: This is also required to see the sun/moon through less thick
		// volumes of water.
		float fadeFactor = min(-viewPos.z / 24.0, 1.0);
		waterDepth = 0.25 + 0.75 * fadeFactor;
		background *= 1.0 - fadeFactor;
	}

	return background * WaterAbsorption(waterDepth);
}
