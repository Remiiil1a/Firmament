// Water interaction waves.
//
// Ported from porting_kit/ (the effect Eclipse has, which that kit validated on
// Photon v1.4). The player - or the boat they are riding - stirs a two-step
// height field simulation, and the water programs read that field back as a
// tilt added to the normal they were about to use. So the water reacts to
// movement through it, and nothing about the surface geometry changes.
//
// The simulation is two compute programs (world0/prepare1.csh and
// world0/prepare2.csh), which hand their field over through custom images. That
// is why this is Iris only: OptiFine has neither compute shaders nor images.
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

// Adds the simulated ripple to a water normal.
//
// `normalWorld` is this pack's water normal, which is a world space (world
// aligned, y up) one, and `worldXZ` the fragment's world position - the field
// is a top-down height map, so only its horizontal position can index it.
//
// The simulation writes a signed pressure field; its gradient is the slope of
// the surface it stands for, and a surface's normal tilts against its gradient.
// That is the whole of the shading: no geometry is moved, and the tilt is
// blended in by the pressure's own magnitude (sqrt(sqrt()), which is the
// original implementation's curve), so still water is untouched.
vec3 WaterInteractionNormal(vec3 normalWorld, vec2 worldXZ) {
	// A height field only describes water that lies flat, so a waterfall's side
	// keeps the normal it had. The absolute value covers water seen from below.
	if (abs(normalWorld.y) < 0.5) { return normalWorld; }

	// The first sub-step publishes the grid centre it used, the second a ready
	// flag. A frame in which the simulation did not run leaves the image zero,
	// and then the water is left exactly as it was - which is also the whole
	// fallback when compute shaders are unavailable.
	if (!(texelFetch(wave_sim_info_sampler, ivec2(1, 0), 0).z > 0.5)) {
		return normalWorld;
	}

	vec2 anchorWorld = texelFetch(wave_sim_info_sampler, ivec2(0, 0), 0).xy;

	vec2 coord = (worldXZ - anchorWorld) / WATER_SIM_TEXEL_SIZE
		+ 0.5 * float(WATER_SIM_RESOLUTION);

	// Texel centres sit at integer coordinates, so the sampler's uv is one half
	// texel further in.
	vec2 uv = (coord + 0.5) / float(WATER_SIM_RESOLUTION);

	// Outside the simulated area there is nothing to read; NaN is rejected by
	// the same comparison.
	if (any(isnan(uv)) || any(greaterThan(abs(uv - 0.5), vec2(0.5)))) {
		return normalWorld;
	}

	vec4 wave = texture(wave_sim_b_sampler, uv);

	// The pressure field is signed, crests positive and troughs negative, so the
	// blend weight uses its magnitude. This also rejects NaN.
	float pressure = abs(wave.r);
	if (!(pressure > 1.0e-4)) { return normalWorld; }

	float weight = clamp(
		WATER_INTERACTION_STRENGTH * sqrt(sqrt(pressure)),
		0.0,
		1.0);

	vec2 gradient = vec2(wave.b, wave.a);
	if (any(isnan(gradient))) { return normalWorld; }

	// The grid factor keeps the tilt independent of the quality level.
	vec2 tilt = -gradient * WATER_SIM_GRID_SCALE;

	// Water seen from below has a normal pointing down, and its ripple has to
	// point the same way or the blend would flatten the surface towards the sky.
	float sign = normalWorld.y < 0.0 ? -1.0 : 1.0;

	vec3 rippleNormal = normalize(vec3(tilt.x, sign, tilt.y));

	return normalize(mix(normalWorld, rippleNormal, weight));
}

#endif // shading half

#endif // INCLUDE_ENVIRONMENT_WATER_WATER_INTERACTION
