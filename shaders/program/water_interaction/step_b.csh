// Water interaction waves: sub-step 2
//
// Ported from porting_kit/ (Eclipse's effect). Integrates the second step from wave_sim_a into wave_sim_b and writes
the surface gradient the water programs read, then publishes the player
position and the ready flag for the next frame.
//
// The program is Iris only, and every part of it that touches an image is kept
// behind IS_IRIS: on a loader without custom images the body does nothing and
// the ready flag never rises, which is what leaves the water untouched.

// The simulation side: the shared constants plus the uniforms and helpers
// this pass runs on. See the note at the top of that file for why it is a
// separate file from the one the water programs include.
#include "/program/water_interaction/sim.glsl"

layout(local_size_x = 32, local_size_y = 32, local_size_z = 1) in;

#if WATER_SIM_QUALITY == 0
	const ivec3 workGroups = ivec3(16, 16, 1);
#elif WATER_SIM_QUALITY == 1
	const ivec3 workGroups = ivec3(32, 32, 1);
#else
	const ivec3 workGroups = ivec3(64, 64, 1);
#endif


#ifdef IS_IRIS
layout(rg16f) uniform readonly image2D wave_sim_a;
layout(rgba16f) uniform writeonly image2D wave_sim_b;
layout(rgba32f) uniform image2D wave_sim_info;
#endif

void main() {
#ifdef IS_IRIS
	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	int resolution = WATER_SIM_RESOLUTION;

	// The grid has already been re-anchored by the first sub-step, so this one
	// works on the current frame's grid directly.
	vec2 anchorWorld = imageLoad(wave_sim_info, ivec2(0, 0)).xy;

	ivec2 sampleCoord = clamp(coord, ivec2(1), ivec2(resolution - 2));

	// --- read the previous sub-step -----------------------------------------
	vec4 state = imageLoad(wave_sim_a, sampleCoord);
	float pressure = state.r;
	float pressureVelocity = state.g;

	float pLeft = imageLoad(wave_sim_a,
		clamp(sampleCoord + ivec2(-1, 0), ivec2(1), ivec2(resolution - 2))).r;
	float pRight = imageLoad(wave_sim_a,
		clamp(sampleCoord + ivec2(1, 0), ivec2(1), ivec2(resolution - 2))).r;
	float pUp = imageLoad(wave_sim_a,
		clamp(sampleCoord + ivec2(0, 1), ivec2(1), ivec2(resolution - 2))).r;
	float pDown = imageLoad(wave_sim_a,
		clamp(sampleCoord + ivec2(0, -1), ivec2(1), ivec2(resolution - 2))).r;

	// --- integrate -----------------------------------------------------------
	float dt = clamp(frameTime * 60.0, 0.25, 2.0);
	float delta = min(WATER_SIM_DELTA * dt, 1.4);

	pressureVelocity += delta * (-2.0 * pressure + pRight + pLeft) * 0.25;
	pressureVelocity += delta * (-2.0 * pressure + pUp + pDown) * 0.25;

	pressure += delta * pressureVelocity;

	pressureVelocity -= 0.0014 * delta * pressure;
	pressureVelocity *= 1.0 - 0.006 * delta;

	float distanceFromCentre
		= length(vec2(coord) - 0.5 * float(resolution));
	float borderFade = 1.0 - smoothstep(
		0.25 * float(resolution),
		0.49 * float(resolution),
		distanceFromCentre);
	pressure *= pow(0.985, dt) * borderFade;
	pressureVelocity *= borderFade;

	// --- inject energy where the player moves through the water -------------
	if (WaterInteractionSourceActive()) {
		vec2 playerWorldXZ
			= cameraPosition.xz - WaterInteractionCameraOffset();
		vec2 playerTexel = WaterInteractionTexelCoord(
			playerWorldXZ,
			cameraPosition,
			anchorWorld);
		vec2 offset = vec2(coord) - playerTexel;
		float sourceSize = WaterInteractionSourceSize();
		float injection;

#if defined IS_IRIS && defined IRIS_VERSION && IRIS_VERSION >= 11004
		if (WaterInteractionRiding()) {
			vec2 forward = vehicleLookVector.xz;
			float forwardLength = length(forward);
			forward = forwardLength > 1.0e-6
				? forward / forwardLength
				: vec2(1.0, 0.0);
			float along = clamp(
				dot(offset, forward),
				-0.73 * sourceSize,
				0.73 * sourceSize);
			float across = length(offset - forward * along);
			injection = (1.0 - smoothstep(0.7 * sourceSize, sourceSize, across))
				* (smoothstep(
					-0.75 * sourceSize,
					0.75 * sourceSize,
					along) * 2.0 - 1.0);
		} else
#endif
		{
			injection = 1.0
				- smoothstep(0.7 * sourceSize, sourceSize, length(offset));
		}

		pressure += injection * dt;
	}

	// Never let a divergence reach the water program.
	pressure = (pressure > -8.0 && pressure < 8.0) ? pressure : 0.0;
	pressureVelocity = (pressureVelocity > -64.0 && pressureVelocity < 64.0)
		? pressureVelocity
		: 0.0;

	// Surface gradient of the field, in texels per texel: this is what the water
	// program turns into the tilt of the normal.
	vec2 gradient = vec2(pRight - pLeft, pUp - pDown) * 0.5;

	imageStore(wave_sim_b, coord,
		vec4(pressure, pressureVelocity, gradient.x, gradient.y));

	// Publish the player position and the ready flag, for the next frame's grid
	// re-anchoring and for the water program.
	if (all(equal(coord, ivec2(0, 0)))) {
		imageStore(wave_sim_info, ivec2(1, 0),
			vec4(playerWorldXZ, 1.0, 0.0));
	}
#endif
}
