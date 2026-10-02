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

// Applies parallax mapping to a smooth water surface. Given a position in 2D
// world space, a time in seconds, and the view ray's direction in the frame
// described below, it returns a shifted version of worldPos that gives depth to
// the water surface.
//
// The only oddity is viewVector and which frame it is in. There is no matrix
// here and nothing converts anything, so the frame is whatever the caller
// passes. `posStep` below only ever uses `viewVector.xy / abs(viewVector.z)`,
// so the frame has to be one whose Z points out of the water surface, with
// `ddxWorldPos` / `ddyWorldPos` expressed in its X and Y. The current caller,
// parallaxWaterNormal in translucent.glsl, passes `facing * incident.xzy`,
// where `incident` is the view-space incident vector (the normalized
// camera-relative position). That swizzle moves view-space Z into the third
// component, so this component's sign is the difference between seeing the
// surface from above and from below: view space looks down -Z, so a surface
// above the camera gives a negative Z here and one below gives a positive Z.
// The `abs` in `posStep` discards that distinction, so a down-facing surface
// is traced with the same step as an up-facing one.
//
// The side case is handled by the caller, not here: parallaxWaterNormal gates
// parallax off with `clamp(..., 0.0, float(verticalNormal))`, and it can also
// make the surface non-horizontal itself by folding world Y into the XZ
// coordinate it passes in. The water plane handed to this function is 2D, so
// nothing in this file can express a surface that is not.
//
// This function relies solely on a previously-defined WaterHeight function. It
// calls the five-argument approximate form,
// `WaterHeightApproximate(worldPos, ddxWorldPos, ddyWorldPos, time)`, which is
// `WaterHeight(..., true)` in both surface files. The height returned from that
// function MUST be in the range 0.0 to 1.0.
vec2 WaterSurfaceParallaxMapping(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time,
	vec3 viewVector
) {
	// We are tracing through a surface of height range 0.0 to 1.0, which the
	// water height function is required to return. That is not automatically
	// one block: the range is whatever the height function's own amplitudes sum
	// to, and nothing here multiplies by a block size. One factor that
	// is slightly modified from traditional parallax mapping is that we work
	// with a height function rather than a depth function. As a result, the
	// trace starts at a height of 1.0 and continually lowers that height as it
	// goes, rather than starting at depth 0.0 and increasing it.
	//
	// For a traditional depth approach, we would have started at a depth of 0.0
	// and have went "deeper" into the surface by increasing the current depth
	// value.
	float currentHeight = 1.0;

	// We use a much lower number of iterations than most parallax methods which
	// use 16-32 iterations and scarcely go below 8 iterations. This is possible
	// because we are working with a smooth surface and can apply a strong
	// approximation - details within the loop.
	const float ITERATIONS = 4;

	// Scale the view vector such that the Z component is -1.0. Once we do this,
	// we can drop the Z component, because it is always -1.0.
	//
	// Why -1.0? With our convention of decreasing height rather than increasing
	// depth, certainly Z cannot be positive as otherwise we are not actually
	// tracing into the surface! And since this fragment is on-screen and from
	// a face that faces the camera, we certainly must be tracing into the
	// surface.
	vec2 posStep = viewVector.xy / abs(viewVector.z);

	for (uint i = uint(0); i < uint(ITERATIONS); i++) {
		// Determine the height of the surface at the current position.
		float sampleHeight = WaterHeightApproximate(
			worldPos,
			ddxWorldPos,
			ddyWorldPos,
			time);

		// We have scaled the view vector such that adding it to the current
		// position would take us from the top of the surface to the bottom of
		// the surface if we added XY to the texture coordinate and Z to the
		// height.
		// 
		// Since we are doing multiple iterations, scale the step length such
		// that an unscaleable step would cross the whole height range over the
		// course of all iterations. What actually crosses the range is the sum
		// of the four scaled steps, and each is scaled by how far above the
		// surface the trace still is, so the loop usually stops well short of
		// the bottom - that shortfall is why the loop breaks on the intersection
		// test below rather than running all four iterations.
		float stepLength = 1.0 / ITERATIONS;

		// The critical improvement over standard parallax techniques is that at
		// every iteration, we scale the step length by our distance above the
		// surface.
		//
		// Essentially, as we approach the surface, we slow down. If we are only
		// 0.1 units above the surface at the very start, this means that we
		// will use our 4 iterations to step through that 0.1 unit distance,
		// rather than blowing right past it.
		// 
		// Since the surface is smooth at the nearby distances we are applying
		// parallax mapping, this approximation appears to work very well.
		//
		// Note that if currentHeight <= sampleHeight, we do not want to step
		// backwards, so in that case set the step length to 0.0.
		stepLength *= max(currentHeight - sampleHeight, 0.0);

		// Finally, advance along the ray. This is written out like a fused
		// multiply-add but is equivalent to:
		//
		// worldPos += posStep * stepLength
		worldPos = (posStep * stepLength) + worldPos;

		// Since we already scaled the view vector by Z such that Z is -1.0, we
		// can just subtract the step length from the height.
		currentHeight -= stepLength;

		// As in Steep Parallax Mapping, if we are now intersecting the surface,
		// we immediately return that new position.
		if (currentHeight <= sampleHeight) {
			break;
		}
	}

	return worldPos;
}
