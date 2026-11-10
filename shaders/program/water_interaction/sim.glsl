// The simulation side of the water interaction waves (batch 682).
//
// Only the two compute programs include this: it declares the uniforms those
// passes read and the helpers that describe the wave source, and it pulls the
// shared constants in with WATER_INTERACTION_SIM switched on so that the file
// it shares with the water programs is compiled for the simulation here.
//
// It is kept apart from that shared file on purpose. The water programs are
// reachable from every root program this pack has, so anything declared in the
// shared file is checked against the rest of the pack; a uniform that only the
// compute passes use has no business appearing in that comparison.

#ifndef INCLUDE_PROGRAM_WATER_INTERACTION_SIM
#define INCLUDE_PROGRAM_WATER_INTERACTION_SIM

#define WATER_INTERACTION_SIM
#include "/environment/water/water_interaction.glsl"

// ---------------------------------------------------------------------------
//   The simulation half, compiled into the two compute programs
// ---------------------------------------------------------------------------
#ifdef WATER_INTERACTION_SIM

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float frameTime;
uniform int isEyeInWater;

// relativeEyePosition is NOT one of the 1.10.4 uniforms, and batch 734 is where
// that was found out the hard way. It has been in Iris since long before the
// version macro could be relied on - it is present in the 1.20.1, 1.21.1, 1.21.4
// and 1.21.11 branches alike - and the fallback path below needs it on every
// loader that has IS_IRIS at all. It used to sit inside the version test with the
// five uniforms that really are new, so on Iris 1.8.14 the declaration was
// preprocessed away while the `#elif` branch still used it, and the whole pack
// failed to load with "undefined variable relativeEyePosition". Declaring it
// unconditionally is what makes the older path compile.
uniform vec3 relativeEyePosition;

#if defined IS_IRIS && defined IRIS_VERSION && IRIS_VERSION >= 11004
	// Iris 1.10.4 and later, and these five really are new there: none of them
	// exists in the 1.21.1 or 1.21.4 branches. Everything that uses them is kept
	// behind the same test - not just the declarations - because GLSL compiles a
	// runtime branch whether or not it is taken, which is the trap porting_kit's
	// GUIDE.md section 7 opens with. On an older Iris the effect degrades to the
	// ripple under a swimming player instead of failing to load.
	uniform bool isRiding;
	uniform bool vehicleInWater;
	uniform bool feetInWater;
	uniform vec3 vehicleLookVector;
	uniform vec3 relativeVehiclePosition;
#endif

// How far the player (or the vehicle) is from the camera, in world xz. Third
// person and riding put it a few blocks away from the eye, and the wave source
// belongs under the player, not under the camera.
vec2 WaterInteractionCameraOffset() {
#if defined IS_IRIS && defined IRIS_VERSION && IRIS_VERSION >= 11004
	return (isRiding ? relativeVehiclePosition : relativeEyePosition).xz;
#elif defined IS_IRIS
	return relativeEyePosition.xz;
#else
	return vec2(0.0);
#endif
}

// Whether the player is in the water at all. The original implementation asks
// `vehicleInWater || feetInWater`; without those (older Iris) the eye's own
// answer is the only one available, so the effect degrades to the ripple under
// a swimming player.
bool WaterInteractionSourceActive() {
#if defined IS_IRIS && defined IRIS_VERSION && IRIS_VERSION >= 11004
	return vehicleInWater || feetInWater;
#else
	return isEyeInWater == 1;
#endif
}

bool WaterInteractionRiding() {
#if defined IS_IRIS && defined IRIS_VERSION && IRIS_VERSION >= 11004
	return isRiding;
#else
	return false;
#endif
}

// Radius of the source, in texels. The faster the player moves the larger the
// disturbed area, which is what makes swimming and boating leave a wake.
float WaterInteractionSourceSize() {
	vec3 movement = cameraPosition - previousCameraPosition;
	movement.y *= 1.2;
	float speed = length(movement) / max(frameTime, 1.0e-4);

	float size = 10.0;

	if (WaterInteractionRiding()) {
		size += 23.0;

		// A boat that is not moving must not keep the water churning, which is
		// the original implementation's rule as well.
		if (speed < 0.15) { size = 0.01; }
	} else {
		size += 10.0 * smoothstep(0.1, 13.0, speed);
	}

	return size * WATER_SIM_GRID_SCALE;
}

#endif // WATER_INTERACTION_SIM

// Camera relative world xz -> continuous simulation texel coordinate.
vec2 WaterInteractionTexelCoord(
	vec2 worldXZ,
	vec3 cameraPos,
	vec2 anchorWorld
) {
	// (cameraPos - anchorWorld) is a small number, which is what keeps full
	// precision far away from the world origin.
	return (worldXZ - anchorWorld) / WATER_SIM_TEXEL_SIZE
		+ 0.5 * float(WATER_SIM_RESOLUTION);
}


#endif // INCLUDE_PROGRAM_WATER_INTERACTION_SIM
