// Water interaction waves: sub-step 1
//
// Ported from porting_kit/ (Eclipse's effect). Reads the previous full state from
// wave_sim_b and integrates one step of the wave equation into wave_sim_a. Runs in
// the prepare1 pass, that is after the shadow pass and before the gbuffer
// programs, so the water program can read the same frame's field.
//
// The program is Iris only, and every part of it that touches an image is kept
// behind IS_IRIS: on a loader without custom images the body does nothing and the
// ready flag never rises, which is what leaves the water untouched.
//
// The simulation side: the shared constants plus the uniforms and helpers this
// pass runs on. See the note at the top of that file for why it is a separate file
// from the one the water programs include.
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
layout(rgba16f) uniform readonly image2D wave_sim_b;
layout(rg16f) uniform writeonly image2D wave_sim_a;
layout(rgba32f) uniform image2D wave_sim_info;
#endif

void main() {
#ifdef IS_IRIS
	// --- is this frame a step? ----------------------------------------------
	//
	// The second sub-step stores the time of the last step in the state image, and
	// both passes read that same value here, so they always agree: either both
	// advance the field this frame or neither does. When neither does, both return
	// without writing anything - the images keep the state they hold, and the water
	// keeps reading it, which is what makes a limited simulation rate cost nothing
	// on the frames it skips.
	vec4 previousState = imageLoad(wave_sim_info, ivec2(1, 0));
	float lastStepTime = previousState.w;
	bool stepThisFrame = WATER_SIM_STEP_INTERVAL <= 0.0
		|| lastStepTime <= 0.0
		|| frameTimeCounter - lastStepTime >= WATER_SIM_STEP_INTERVAL;
	if (!stepThisFrame) { return; }

	ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
	int resolution = WATER_SIM_RESOLUTION;

	// --- keep the simulated area anchored to the world ----------------------
	vec2 playerWorldXZ
		= cameraPosition.xz - WaterInteractionCameraOffset();
	ivec2 anchorTexel = WaterInteractionAnchorTexel(playerWorldXZ);
	vec2 anchorWorld = WaterInteractionAnchorWorld(vec2(anchorTexel));

	// The previous player position is written by the previous frame's second
	// sub-step. Going through the image rather than previousCameraPosition is what
	// keeps the grid exact in third person and on a boat, where the
	// camera-to-player offset changes between frames.
	bool previousValid = previousState.z > 0.5
		&& !isnan(previousState.x) && !isnan(previousState.y)
		&& !isnan(previousCameraPosition.x) && !isnan(previousCameraPosition.z)
		// The stored position has to be near the previous camera, which rejects
		// garbage (and an all-zero image) without limiting how far from the world
		// origin the player may be.
		&& length(previousState.xy - previousCameraPosition.xz) < 64.0;

	ivec2 previousAnchorTexel = previousValid
		? WaterInteractionAnchorTexel(previousState.xy)
		: anchorTexel;

	// Whole texel shift between last frame's grid and this frame's.
	ivec2 shift = anchorTexel - previousAnchorTexel;

	// Teleports, dimension changes and coordinate wraps make the previous field
	// useless, so those restart from a calm surface.
	bool reset = !previousValid
		|| any(greaterThan(abs(shift), ivec2(resolution / 2)));
	shift = reset ? ivec2(0) : shift;

	// --- read the previous state ---------------------------------------------
	//
	// The four neighbours and the sample itself, read through the shift - and
	// *zero* where the shifted coordinate falls outside the grid.
	//
	// Zero rather than the clamped edge value, and that is one of the two things the
	// frame rate limit needed. The field is anchored to the world, so a step taken
	// after a longer pause re-anchors it by more texels at once; a clamped read then
	// repeats the edge of the old field into the strip the field has just moved into.
	// A copy of the edge is not water: it sits at full pressure, it carries no
	// velocity, and being re-created by every step it does not decay like the rest -
	// and the next wave that arrives beats against it. That is the "waves stuck in
	// some places, then interacting with the new ones" that was reported.
	//
	// Water that has only just entered the simulated area has not been disturbed, so
	// zero is also the true value rather than a patch over the problem.
	float pressure = 0.0;
	float pressureVelocity = 0.0;
	float pLeft = 0.0;
	float pRight = 0.0;
	float pUp = 0.0;
	float pDown = 0.0;

	if (!reset) {
		int offset = WATER_SIM_STEP_OFFSET;
		ivec2 origin = coord + shift;
		bool originInside = all(greaterThanEqual(origin, ivec2(0)))
			&& all(lessThan(origin, ivec2(resolution)));
		vec4 state = originInside ? imageLoad(wave_sim_b, origin) : vec4(0.0);
		pressure = state.r;
		pressureVelocity = state.g;

		pLeft = imageLoad(wave_sim_b,
			clamp(origin + ivec2(-offset, 0), ivec2(0), ivec2(resolution - 1))).r *
			float(originInside && origin.x - offset >= 0);
		pRight = imageLoad(wave_sim_b,
			clamp(origin + ivec2(offset, 0), ivec2(0), ivec2(resolution - 1))).r *
			float(originInside && origin.x + offset < resolution);
		pUp = imageLoad(wave_sim_b,
			clamp(origin + ivec2(0, offset), ivec2(0), ivec2(resolution - 1))).r *
			float(originInside && origin.y + offset < resolution);
		pDown = imageLoad(wave_sim_b,
			clamp(origin + ivec2(0, -offset), ivec2(0), ivec2(resolution - 1))).r *
			float(originInside && origin.y - offset >= 0);
	}

	// --- integrate -----------------------------------------------------------
	//
	// `dt` is the time this step covers, and it is what the time-based decay terms
	// use: the field should calm down at the same rate per second whatever the step
	// rate is.
	float dt = WATER_SIM_STEP_INTERVAL > 0.0
		? WATER_SIM_STEP_INTERVAL * 60.0
		: clamp(frameTime * 60.0, 0.25, 2.0);

	// How far one step advances the wave equation. At a locked rate this must NOT be
	// scaled by `dt`, and that was the other half of the reported bug: the wider
	// neighbour stencil above already covers the extra ground a coarser step spans,
	// so scaling the step as well advanced the equation by the interval AND by the
	// width - four times the propagation at 30 fps rather than half. That is not a
	// slower simulation, it is an unstable one, and an unstable one leaves patches
	// oscillating that then beat against the next waves to arrive.
	float delta = WATER_SIM_STEP_INTERVAL > 0.0
		? WATER_SIM_DELTA
		: min(WATER_SIM_DELTA * dt, 1.4);

	pressureVelocity += delta * (-2.0 * pressure + pRight + pLeft) * 0.25;
	pressureVelocity += delta * (-2.0 * pressure + pUp + pDown) * 0.25;

	pressure += delta * pressureVelocity;

	// A spring term, which is what makes the field behave like a water surface
	// rather than like a diffusing blur.
	pressureVelocity -= 0.0014 * delta * pressure;

	// Velocity damping, so the water eventually calms down.
	pressureVelocity *= 1.0 - 0.006 * delta;

	// Radial damping, so the border of the grid never reflects waves back in.
	float distanceFromCentre
		= length(vec2(coord) - 0.5 * float(resolution));
	// 1 inside a quarter of the grid, 0 outside 0.49 of it. The edges ascend
	// because smoothstep with edge0 >= edge1 is undefined.
	float borderFade = 1.0 - smoothstep(
		0.25 * float(resolution),
		0.49 * float(resolution),
		distanceFromCentre);
	pressure *= pow(0.985, dt) * borderFade;
	pressureVelocity *= borderFade;

	// --- inject energy where the player moves through the water -------------
	if (WaterInteractionSourceActive()) {
		vec2 playerTexel = WaterInteractionTexelCoord(
			playerWorldXZ,
			cameraPosition,
			anchorWorld);
		vec2 offset = vec2(coord) - playerTexel;
		float sourceSize = WaterInteractionSourceSize();
		float injection;

#if defined IS_IRIS && defined IRIS_VERSION && IRIS_VERSION >= 11004
		if (WaterInteractionRiding()) {
			// A boat pushes a long capsule rather than a disc, which is why its
			// source is measured along and across the hull instead of radially.
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

		// dt keeps the energy injected per second independent of the frame rate.
		pressure += injection * dt;
	}

	// Never let a divergence reach the water program.
	pressure = (pressure > -8.0 && pressure < 8.0) ? pressure : 0.0;
	pressureVelocity = (pressureVelocity > -64.0 && pressureVelocity < 64.0)
		? pressureVelocity
		: 0.0;

	imageStore(wave_sim_a, coord, vec4(pressure, pressureVelocity, 0.0, 0.0));

	// Publish the grid centre and the shift for the water program and for the next
	// frame's first sub-step. The time stamp is not written here: the second
	// sub-step owns it, so that both passes of one frame read the same value.
	if (all(equal(coord, ivec2(0, 0)))) {
		imageStore(wave_sim_info, ivec2(0, 0),
			vec4(anchorWorld.x, anchorWorld.y, vec2(shift)));
	}
#endif
}
