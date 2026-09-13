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

struct CausticNoiseWave {
	// The size of each tile in the grid on the X axis and the Y axis in meters.
	vec2 tileSize;

	// Shear angle for the vertical shear mapping of the tile grid:
	// https://en.wikipedia.org/wiki/Shear_mapping
	float shearAngle;

	// The speed that the wave travels torwards its heading direction in meters
	// (blocks) per second.
	float speed;

	// The heading of the wave, in radians. This follows the unit circle except
	// our Z coordinate is the Y on the unit circle.
	float heading;

	// The weight of this particular wave. The height of each wave is multiplied
	// by its weight and then the sum of all wave weights is divided by the
	// total weight, such that the actual magnitude of this wave is given by
	// weight divided by totalWeight.
	float weight;

	// The exponent applied to the wave.
	float exponent;
};

#include "/environment/water/caustics_noise_waves.glsl"

// Boilerplate code roughly the same as noise waves
const vec3 causticsStretch[6] = vec3[](
	vec3(1.0 / CAUSTICS[0].tileSize.x, 1.0 / CAUSTICS[0].tileSize.y,
		(1.0 / tan(CAUSTICS[0].shearAngle)) / CAUSTICS[0].tileSize.x),
	vec3(1.0 / CAUSTICS[1].tileSize.x, 1.0 / CAUSTICS[1].tileSize.y,
		(1.0 / tan(CAUSTICS[1].shearAngle)) / CAUSTICS[1].tileSize.x),
	vec3(1.0 / CAUSTICS[2].tileSize.x, 1.0 / CAUSTICS[2].tileSize.y,
		(1.0 / tan(CAUSTICS[2].shearAngle)) / CAUSTICS[2].tileSize.x),
	vec3(1.0 / CAUSTICS[3].tileSize.x, 1.0 / CAUSTICS[3].tileSize.y,
		(1.0 / tan(CAUSTICS[3].shearAngle)) / CAUSTICS[3].tileSize.x),
	vec3(1.0 / CAUSTICS[4].tileSize.x, 1.0 / CAUSTICS[4].tileSize.y,
		(1.0 / tan(CAUSTICS[4].shearAngle)) / CAUSTICS[4].tileSize.x),
	vec3(1.0 / CAUSTICS[5].tileSize.x, 1.0 / CAUSTICS[5].tileSize.y,
		(1.0 / tan(CAUSTICS[5].shearAngle)) / CAUSTICS[5].tileSize.x));

const vec2 causticsScroll[6] = vec2[](
	-mat2(
		causticsStretch[0].x,
		causticsStretch[0].x / tan(CAUSTICS[0].shearAngle),
		0.0,
		causticsStretch[0].y)
	 * CAUSTICS[0].speed
	 * vec2(cos(CAUSTICS[0].heading), sin(CAUSTICS[0].heading)),
	-mat2(
		causticsStretch[1].x,
		causticsStretch[1].x / tan(CAUSTICS[1].shearAngle),
		0.0,
		causticsStretch[1].y)
	 * CAUSTICS[1].speed
	 * vec2(cos(CAUSTICS[1].heading), sin(CAUSTICS[1].heading)),
	-mat2(
		causticsStretch[2].x,
		causticsStretch[2].x / tan(CAUSTICS[2].shearAngle),
		0.0,
		causticsStretch[2].y)
	 * CAUSTICS[2].speed
	 * vec2(cos(CAUSTICS[2].heading), sin(CAUSTICS[2].heading)),
	-mat2(
		causticsStretch[3].x,
		causticsStretch[3].x / tan(CAUSTICS[3].shearAngle),
		0.0,
		causticsStretch[3].y)
	 * CAUSTICS[3].speed
	 * vec2(cos(CAUSTICS[3].heading), sin(CAUSTICS[3].heading)),
	-mat2(
		causticsStretch[4].x,
		causticsStretch[4].x / tan(CAUSTICS[4].shearAngle),
		0.0,
		causticsStretch[4].y)
	 * CAUSTICS[4].speed
	 * vec2(cos(CAUSTICS[4].heading), sin(CAUSTICS[4].heading)),
	-mat2(
		causticsStretch[5].x,
		causticsStretch[5].x / tan(CAUSTICS[5].shearAngle),
		0.0,
		causticsStretch[5].y)
	 * CAUSTICS[5].speed
	 * vec2(cos(CAUSTICS[5].heading), sin(CAUSTICS[5].heading)));

// We are not actually doing any calculation here, so technically we do not need
// this intermediate array from a structural standpoint. However, the macOS
// driver appears to dislike when we reference a field in a struct in an array
// in combination with another array access, and this intermediate array
// avoids the problem without any further disruption to code style.
const float causticsExponents[6] = float[](
	CAUSTICS[0].exponent,
	CAUSTICS[1].exponent,
	CAUSTICS[2].exponent,
	CAUSTICS[3].exponent,
	CAUSTICS[4].exponent,
	CAUSTICS[5].exponent);

// The number of waves to use in water caustics.
#define NUM_CAUSTICS 6 // [0 1 2 3 4 5 6]

const float causticsTotalWeight = 0.0
	#if NUM_CAUSTICS > 0
		+ CAUSTICS[0].weight
	#endif
	#if NUM_CAUSTICS > 1
		+ CAUSTICS[1].weight
	#endif
	#if NUM_CAUSTICS > 2
		+ CAUSTICS[2].weight
	#endif
	#if NUM_CAUSTICS > 3
		+ CAUSTICS[3].weight
	#endif
	#if NUM_CAUSTICS > 4
		+ CAUSTICS[4].weight
	#endif
	#if NUM_CAUSTICS > 5
		+ CAUSTICS[5].weight
	#endif
	;

const float causticsLogMagnitude[6] = float[](
	#if NUM_CAUSTICS > 0
		log(CAUSTICS[0].weight / causticsTotalWeight)
	#else
		0.0
	#endif
	#if NUM_CAUSTICS > 1
		,log(CAUSTICS[1].weight / causticsTotalWeight)
	#else
		,0.0
	#endif
	#if NUM_CAUSTICS > 2
		,log(CAUSTICS[2].weight / causticsTotalWeight)
	#else
		,0.0
	#endif
	#if NUM_CAUSTICS > 3
		,log(CAUSTICS[3].weight / causticsTotalWeight)
	#else
		,0.0
	#endif
	#if NUM_CAUSTICS > 4
		,log(CAUSTICS[4].weight / causticsTotalWeight)
	#else
		,0.0
	#endif
	#if NUM_CAUSTICS > 5
		,log(CAUSTICS[5].weight / causticsTotalWeight)
	#else
		,0.0
	#endif
	);

// TODO: Copied from surface_noise.glsl
//
// This function reshapes the original smooth transitions
// between different wave levels into more visible "crests"
// on the transitions between different wave levels, such that
// most of the area is flat and there are raised crests at regular grid
// transition points.
float crestCaustics(float h) {
	const float PI = 3.14159265359;

	// 0.5 - 0.5 * cos written out to explicitly have it as
	// mul -> cos -> fma
	return (-0.5 * cos(h * (PI * 2.0))) + 0.5;
}

// We use the smoothNoise2D variant of our value noise.
#include "/lib/valueNoise.glsl"

float WaterCaustics(vec3 worldPos, float time) {
	// Project the 2D caustics on to the 3D underwater surface.
	//
	// While potentially unintuitive, projecting this as we would with the
	// shadow map looks bad. Perhaps we can rotate this with the light position
	// but this simple approach seems to be completely fine.
	worldPos.xz += vec2(-2.0 / 3.0, 2.0 / 3.0) * worldPos.y;

	// Deform the coordinates with a sine wave to add some additional animation,
	// which is a rough analog to the changing refraction which causes the
	// caustics to vary. This helps avoid the it looking like we just scrolled
	// a texture over the terrain.
	worldPos.xz += 0.15 * sin(worldPos.zx * vec2(0.30, 0.25) + time);

	float caustics = 0.0;

	// This is pretty similar to the noise waves code, but adjusted for caustics
	for (uint i = uint(0); i < uint(NUM_CAUSTICS); i++) {
		vec3 stretch = causticsStretch[i];
		vec2 scroll = causticsScroll[i];
		
		vec2 stretched = vec2(
			worldPos.x * stretch.x,
			dot(worldPos.xz, stretch.zy));
		vec2 at = time * scroll + stretched;

		// The "crest" function combined with raising to a power happens to work
		// nicely for these caustics.
		float noise = crestCaustics(smoothNoise2D(at));
		float exponent = causticsExponents[i];

		// This is equivalent to: C * x^P
		//
		// First, we apply the identity that the shader compiler would have used
		// to implement the pow(x, P) function:
		// C * x^P = C * e^(P * ln(x))
		//
		// Then, we apply additional identity to pull in the C:
		// C * e^(P * ln(x)) = e^(ln C) * e^(P * ln(x))
		// C * e^(P * ln(x)) = e^(P * ln(x) + ln C)
		//
		// This compiles down to 3 operations (log, fused multiply-add, exp)
		caustics += exp(exponent * log(noise) + causticsLogMagnitude[i]);
	}

	// Allow anywhere between 66% brightness to 250% brightness. Square it
	// so that caustics are more intermittent.
	return (caustics * caustics) * (1.5 + 0.33) - 0.33;
}
