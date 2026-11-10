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
// translation unit never saw the declaration. The test below has to know whether
// the world image exists, so it needs that declaration, and light_colors.glsl
// needs materialIDs.glsl's IDs for the functions it defines.
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
uniform int isEyeInWater;

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
	// Iris 1.10.4 and later, and these three really are new there: none of them
	// exists in the 1.21.1 or 1.21.4 branches. Everything that uses them is kept
	// behind the same test - not just the declarations - because GLSL compiles a
	// runtime branch whether or not it is taken, which is the trap porting_kit's
	// GUIDE.md section 7 opens with. On an older Iris the effect degrades to the
	// ripple under a swimming player instead of failing to load.
	//
	// vehicleInWater and feetInWater used to be here too, and batch 736 removed
	// them from this list along with their declarations: the water test no longer
	// asks the loader whether the player is in water, it reads the water out of
	// the light volume's world image (see WaterInteractionSourceActive below).
	// They are deliberately not kept as extra signals - the test is the same one
	// Eclipse uses on every loader, so there is one answer and not two.
	uniform bool isRiding;
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
// loader never bound; the fallback in the function below is what runs then, and
// it needs no image.
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
// Batch 736 replaced the loader's answer with Eclipse's, which is the same test
// on every Iris version: measure the player from the eye down - eye, waist,
// feet - and call it water when any of the three voxels is water. It is the test
// in Eclipse-Shader-Unstable/shaders/dimensions/prepare.csh, the branch it takes
// before Iris 1.10.4 - the one that needs no 1.10.4 uniforms, and therefore the
// one that can be the only test here.
//
// Why the eye's own answer is not enough: isEyeInWater is about the camera, so a
// player standing chest-deep in a pool reads as dry, and the waves their legs
// make are exactly what the simulation is for. The uniforms that fixed that on
// recent Iris (feetInWater, vehicleInWater) do not exist on the versions this
// pack still loads, so using them meant two different tests and a version
// branch. The image exists on all of them.
//
// The eye's answer is kept, and it is tested first. It is a subsystem that cannot
// be wrong, it costs one comparison, and it is the only answer there is when the
// light volume is switched off. The three heights are therefore an addition
// rather than a replacement: nothing that used to ripple stops rippling because
// the image did not happen to say water this frame.
bool WaterInteractionSourceActive() {
	if (isEyeInWater == 1) {
		return true;
	}

#if defined(COLORED_LIGHTS)
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
#else
	return false;
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
