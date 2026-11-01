// Water interaction waves.
//
// Ported from porting_kit/ (the effect Eclipse has, which that kit validated on
// Photon v1.4). The player - or the boat they are riding - stirs a two-step
// height field simulation, and the water programs read that field back as a
// tilt added to the normal they were about to use. So the water reacts to
// movement through it, and nothing about the surface geometry changes.
//
// The simulation is two compute programs (prepare1.csh and prepare2.csh at the
// pack root), which hand their field over through custom images. That is why
// this is Iris only: OptiFine has neither compute shaders nor images.
//
// Everything below is either compiled into those two programs (the
// simulation half, WATER_INTERACTION_SIM) or into the water programs (the
// shading half), and the two halves share only the constants.

#ifndef INCLUDE_ENVIRONMENT_WATER_WATER_INTERACTION
#define INCLUDE_ENVIRONMENT_WATER_WATER_INTERACTION

// Whether water reacts to the player moving through it.
//
// Off means the water programs never read the simulation at all: the call site
// in translucent.glsl is compiled out and the water is exactly the water this
// pack drew before.
#define WATER_INTERACTION
#ifdef WATER_INTERACTION
	// Referenced here so that Iris registers this as an option rather than a
	// plain define; the real use is in translucent.glsl.
#endif

// How far the simulated tilt is taken on top of the regular waves.
#define WATER_INTERACTION_STRENGTH 1.00 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00]

// Simulation grid resolution. The wave equation is stepped in grid space, and
// the quantities below are rescaled from the original implementation's grid to
// this one, so the wave speed and the apparent steepness are the same at every
// level: only the amount of spatial detail changes.
#define WATER_SIM_QUALITY 1 // [0 1 2]

// How often the wave simulation is stepped: 30 fps, 60 fps, or once per frame.
//
// The field is a state that evolves, so how often it is advanced is a real
// choice rather than a quality setting: at 30 the ripples travel in coarser
// steps and the simulation costs a third of what it does when it runs every
// frame at 120 fps, at 60 it is halved, and "every frame" is what the pack did
// before this option existed (it scales the step by the frame time, so the
// waves travel at the same speed whatever the frame rate is).
//
// This is Eclipse's arrangement, and so is the way the step is kept honest when
// it is limited: the lock is not "run less often and hope", it is "advance by
// the step that interval implies, and look two texels away instead of one when
// the interval doubles", which is what keeps the propagation speed the same at
// 30 as at 60. A time stamp in the state image is what makes the two compute
// passes agree on whether this frame is a step.
#define WATER_SIM_RATE 2 // [0 1 2]

// Half-width of the simulated area, in blocks. The original implementation's 25
// block radius.
const float WATER_SIM_RADIUS = 25.0;

#if WATER_SIM_QUALITY == 0
	const int WATER_SIM_RESOLUTION = 512;
#elif WATER_SIM_QUALITY == 1
	const int WATER_SIM_RESOLUTION = 1024;
#else
	const int WATER_SIM_RESOLUTION = 2048;
#endif

const float WATER_SIM_TEXEL_SIZE
	= 2.0 * WATER_SIM_RADIUS / float(WATER_SIM_RESOLUTION);

// Texel size of the original implementation's grid (25 blocks radius, 2048
// texels). Grid space quantities - source radius, surface gradient - are
// converted into blocks through it, which is what keeps the result independent
// of the quality level.
const float WATER_SIM_REFERENCE_TEXEL_SIZE = 0.0244140625;
const float WATER_SIM_GRID_SCALE
	= WATER_SIM_REFERENCE_TEXEL_SIZE / WATER_SIM_TEXEL_SIZE;

// Integration step of one sub-step: chosen so that the propagation speed
// (delta * texel * 60 blocks per second) is constant.
const float WATER_SIM_DELTA = WATER_SIM_GRID_SCALE;

// The minimum time between two steps, in seconds; zero means every frame.
#if WATER_SIM_RATE == 0
	const float WATER_SIM_STEP_INTERVAL = 1.0 / 30.0;
#elif WATER_SIM_RATE == 1
	const float WATER_SIM_STEP_INTERVAL = 1.0 / 60.0;
#else
	const float WATER_SIM_STEP_INTERVAL = 0.0;
#endif

// How far apart the neighbours a step reads are. At half the rate a step has to
// cover twice the ground to keep the wave speed the same, which is what this
// does - the original implementation's trick, kept exactly because any other
// way of compensating (a bigger delta) changes the spring term's balance as
// well and the waves stop looking like water.
#if WATER_SIM_RATE == 0
	const int WATER_SIM_STEP_OFFSET = 2;
#else
	const int WATER_SIM_STEP_OFFSET = 1;
#endif

// ---------------------------------------------------------------------------
//   Helpers both halves use
// ---------------------------------------------------------------------------

// Grid texel the field is centred on. The field follows the player but is
// anchored to a quantised world position, so what is stored stays fixed in the
// world and only ever shifts by whole texels.
ivec2 WaterInteractionAnchorTexel(vec2 playerWorldXZ) {
	return ivec2(floor(playerWorldXZ / WATER_SIM_TEXEL_SIZE));
}

// World position of the grid centre.
vec2 WaterInteractionAnchorWorld(vec2 anchorTexel) {
	return anchorTexel * WATER_SIM_TEXEL_SIZE;
}

// ---------------------------------------------------------------------------
//   The shading half, compiled into the water programs
// ---------------------------------------------------------------------------

#if !defined(WATER_INTERACTION_SIM) && defined(WATER_INTERACTION) \
	&& !defined(EXTERNALLY_DEFINED_UNIFORMS)

uniform sampler2D wave_sim_b_sampler;
uniform sampler2D wave_sim_info_sampler;

// One texel of the field, with everything outside the grid read as zero.
//
// Zero rather than a clamp for the reason the simulation itself reads zero at its
// edge: outside the simulated area is water that nothing has disturbed.
vec4 WaterInteractionTexel(ivec2 texel, int resolution) {
	if (any(lessThan(texel, ivec2(0)))
		|| any(greaterThanEqual(texel, ivec2(resolution)))) {
		return vec4(0.0);
	}
	return texelFetch(wave_sim_b_sampler, texel, 0);
}

// Adds the simulated ripple to the water normal.
//
// `normalTangent` is the pack's own water normal in the space WaterNormal returns
// it in - in-plane x and y, z out of the surface - which for water lying flat is
// the same frame the simulated field lives in: x is east and y is north, and the
// caller's swizzle turns that into world axes. So the ripple is added there, in
// the same space and at the same point as the pack's own wave normals, which is
// where the original implementation adds it as well.
//
// `worldXZ` is the fragment's world position, and it is deliberately the position
// *before* the parallax mapping moved the surface: parallax moves where the pack
// samples its own wave field, and a ripple sampled at the moved position slides
// with the parallax and reads as a pattern painted onto that surface rather than
// as water standing in the world. (Batch 685; the first version sampled after.)
//
// Only flat water calls this. A height field describes no standing face, and the
// caller already knows whether the face is flat.
vec3 WaterInteractionTangent(vec3 normalTangent, vec2 worldXZ) {
	// The first sub-step publishes the grid centre it used, the second a ready
	// flag. A frame in which the simulation did not run leaves the image zero, and
	// then the water is left exactly as it was - which is also the whole fallback
	// when compute shaders are unavailable, and the state of every frame the frame
	// rate limit skips.
	if (!(texelFetch(wave_sim_info_sampler, ivec2(1, 0), 0).z > 0.5)) {
		return normalTangent;
	}

	vec2 anchorWorld = texelFetch(wave_sim_info_sampler, ivec2(0, 0), 0).xy;

	int resolution = WATER_SIM_RESOLUTION;

	// Continuous texel coordinate: texel centres sit at integer values.
	vec2 coord = (worldXZ - anchorWorld) / WATER_SIM_TEXEL_SIZE
		+ 0.5 * float(resolution);

	if (any(isnan(coord))) { return normalTangent; }

	// The field is interpolated here rather than by the sampler, and that is batch
	// 688: the sampler behind a custom image is created by the loader, not by this
	// pack, and a nearest neighbour one turns the ripple into a blocky lattice whose
	// motion beats against the grid - patches that appear to advance more slowly
	// than the rest and then stand still, which is what the author reported. Four
	// fetches and the weights below depend on nothing but the field itself.
	vec2 base = coord - 0.5;
	ivec2 firstTexel = ivec2(floor(base));
	// `texelWeight`, not `weight`: the blend weight of the ripple against the
	// pack's own normal is also called weight, and one name for two quantities in
	// nested scopes is what the pack's declaration audit reports.
	vec2 texelWeight = base - vec2(firstTexel);

	vec4 wave = mix(
		mix(WaterInteractionTexel(firstTexel, resolution),
			WaterInteractionTexel(firstTexel + ivec2(1, 0), resolution), texelWeight.x),
		mix(WaterInteractionTexel(firstTexel + ivec2(0, 1), resolution),
			WaterInteractionTexel(firstTexel + ivec2(1, 1), resolution), texelWeight.x),
		texelWeight.y);

	// The pressure field is signed, crests positive and troughs negative, so the
	// blend weight uses its magnitude. This also rejects NaN.
	float pressure = abs(wave.r);
	if (!(pressure > 1.0e-4)) { return normalTangent; }

	float weight = clamp(
		WATER_INTERACTION_STRENGTH * sqrt(sqrt(pressure)),
		0.0,
		1.0);

	vec2 gradient = vec2(wave.b, wave.a);
	if (any(isnan(gradient))) { return normalTangent; }

	// The field behaves like a height: its normal tilts against the gradient, and
	// the grid factor keeps the tilt independent of the quality level.
	vec2 tilt = -gradient * WATER_SIM_GRID_SCALE;

	vec3 rippleNormal = normalize(vec3(tilt.x, tilt.y, 1.0));

	return normalize(mix(normalTangent, rippleNormal, weight));
}

#endif // shading half

#endif // INCLUDE_ENVIRONMENT_WATER_WATER_INTERACTION
