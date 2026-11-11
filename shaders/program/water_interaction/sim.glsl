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

// The material palette and the option that says whether the light volume exists.
//
// WHY THESE TWO INCLUDES ARE HERE, and not just light_volume.glsl. Iris applies a
// shader pack option by rewriting the source of the file that DECLARES it, and by
// nothing else: the option's value is baked into that file when it is assembled
// into a program (ShaderPackOptions -> IncludeGraph transform, then read per file
// by the program source provider). A `#if defined(COLORED_LIGHTS)` in a program
// whose include graph never reaches light_colors.glsl is therefore FALSE whatever
// the player chose - not "false because the option is off", but false because this
// WHO needs that declaration: the older-Iris branch of the source test below, which
// is the only thing here that reads the world image. The newer loaders answer the
// question with uniforms and never touch the image, but the file-level guard around
// the image still has to be evaluated, so the declaration is still what decides it.
// light_colors.glsl needs materialIDs.glsl's IDs for the functions it defines.
//
// This was found while writing batch 736, before the pack was run: the first
// version of this file tested COLORED_LIGHTS without the include. The compute
// check assembles a program from the same include graph the loader uses, so it
// would have taken the fallback branch for exactly the reason the game does -
// the green result would have been the fallback compiling, and the new test
// would never have run in either place.
#include "/environment/materialIDs.glsl"
#include "/environment/lighting/light_colors.glsl"

// The light volume's grid and its state table, from the one file all three ends
// of that feature include. The water test below asks that image where the water
// is, and the voxel coordinate it indexes with has to be the same one the shadow
// pass stored into - so the coordinate helper is included rather than copied.
#include "/environment/lighting/light_volume.glsl"

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform float frameTime;

// Whether the player is sneaking, which moves the feet up. It is one of the
// loader's per-frame uniforms and exists on every Iris this pack supports; the
// three heights use it the way Eclipse's test does (1.2 blocks instead of 1.5).
uniform bool is_sneaking;

// relativeEyePosition is NOT one of the 1.10.4 uniforms, and batch 734 is where
// that was found out the hard way. It has been in Iris since long before the
// version macro could be relied on - it is present in the 1.20.1, 1.21.1, 1.21.4
// and 1.21.11 branches alike - and the three-height test below and the camera
// offset both need it on every loader that has IS_IRIS at all. It used to sit
// inside the version test with the uniforms that really are new, so on Iris
// 1.8.14 the declaration was preprocessed away while the `#elif` branch still
// used it, and the whole pack failed to load with "undefined variable
// relativeEyePosition". Declaring it unconditionally is what makes the older
// path compile.
uniform vec3 relativeEyePosition;

#if defined IS_IRIS && defined IRIS_VERSION && IRIS_VERSION >= 11004
	// Iris 1.10.4 and later, and these five really are new there: none of them
	// exists in the 1.21.1 or 1.21.4 branches. Everything that uses them is kept
	// behind the same test - not just the declarations - because GLSL compiles a
	// runtime branch whether or not it is taken, which is the trap porting_kit's
	// GUIDE.md section 7 opens with. On an older Iris the effect degrades to the
	// ripple under a swimming player instead of failing to load.
	//
	// vehicleInWater and feetInWater are the pair that answers "is the player in
	// water"; see WaterInteractionSourceActive below, where they are the whole
	// test on these loaders. Batch 736 dropped them in favour of reading the
	// light volume on every loader, and batch 737 brought them back: the author's
	// game test showed the loader's answer is the right one where it exists, and
	// the light volume is only the stand-in for the loaders that have none.
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

// This frame's water, as the shadow pass stored it: the same image the coloured
// light's propagation reads, with the same state table - water is
// LIGHT_VOLUME_WATER_STATE there. It is read voxel by voxel rather than sampled,
// because the test wants one voxel's tag and no filtering across a boundary.
//
// The declaration sits inside the same test the writer uses to decide whether the
// image exists at all. With COLORED_LIGHTS off, shaders.properties does not
// declare the image, so a program that named it would be reading a name the
// loader never bound; the older-Iris branch of the test below then answers false
// instead, and the newer loaders do not read the image at all.
#if defined(COLORED_LIGHTS)
	layout(rgba16) uniform readonly image3D light_volume_world;

	// Whether the light volume says the block at a voxel is water.
	//
	// Out of range is not water: the grid is a cube cut out of the world, and a
	// position below it has no voxel to answer with. Reading outside the image is
	// undefined rather than zero, which is why the bounds test is here and not at
	// the call site.
	//
	// This helper is compiled out with the image, not just its call: its body
	// names the image, so leaving it in a build without the image would be the
	// same undeclared name the guard exists to avoid.
	bool WaterInteractionVoxelIsWater(ivec3 voxel) {
		if (any(lessThan(voxel, ivec3(0)))
			|| any(greaterThanEqual(voxel, ivec3(LIGHT_VOLUME_SIZE)))) {
			return false;
		}

		return abs(imageLoad(light_volume_world, voxel).a
			- LIGHT_VOLUME_WATER_STATE) < LIGHT_VOLUME_WATER_TOLERANCE;
	}
#endif

// Whether the player is in the water at all.
//
// Two implementations, chosen by the same version test that decides which uniforms
// exist, and the split is deliberate rather than a preference:
//
//  * Iris 1.10.4 and later answer it directly - vehicleInWater || feetInWater.
//    That is what this effect was tested with in game, and it is the answer the
//    loader computes from the player's body rather than from the eye.
//  * Every older Iris has neither uniform, so those loaders read the light
//    volume's world image instead. It is Eclipse's own test for the same versions
//    (Eclipse-Shader-Unstable/shaders/dimensions/prepare.csh, its pre-1.10.4
//    branch): measure the player from the eye down - eye, waist, feet - and call
//    it water when any of the three voxels is water.
//
// isEyeInWater is NOT part of either test. It answers "is the eye's own block
// water", which is a different question from "is the player's body in water": a
// player standing chest-deep with their head above the surface reads as dry, and
// an eye that dips under the surface reads as wet wherever the player is standing.
// Batch 736 had it as an extra OR for one build and the author saw exactly that
// second failure in game - waves on a surface the player was not in - so this file
// no longer declares it.
//
// What the older path costs: the world image exists only while COLORED_LIGHTS is
// on, so on an older loader with coloured lights off the simulation has no source
// and the water stays calm. That is the documented degradation, and the option's
// own note (environment/water/water_interaction.glsl) says the same thing.
bool WaterInteractionSourceActive() {
#if defined IS_IRIS && defined IRIS_VERSION && IRIS_VERSION >= 11004
	return vehicleInWater || feetInWater;
#elif !defined IS_IRIS || !defined(COLORED_LIGHTS)
	return false;
#else
	// Eclipse's three heights, and its two tallness values. The eye is the one
	// position the loader gives in every stage; the waist and the feet are
	// offsets from it, so the test follows the player and not the camera, which
	// is also what makes it work in third person and on a boat.
	float tallness = is_sneaking ? 1.2 : 1.5;

	vec3 eye = LightVolumeCoord(-relativeEyePosition, fract(cameraPosition));

	return WaterInteractionVoxelIsWater(ivec3(floor(eye)))
		|| WaterInteractionVoxelIsWater(
			ivec3(floor(eye - vec3(0.0, 0.5 * tallness, 0.0))))
		|| WaterInteractionVoxelIsWater(
			ivec3(floor(eye - vec3(0.0, tallness, 0.0))));
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
