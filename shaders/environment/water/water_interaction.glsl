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

// How the simulation knows the player is in water differs by loader, because the
// uniforms that answer that question are new:
//
//  * Iris 1.10.4 and later use `vehicleInWater || feetInWater` - the loader's own
//    answer, and the one this effect was tested with.
//  * Older Iris has neither, so it measures the player against the coloured-light
//    voxel grid instead (Eclipse's method for those versions): eye, waist and feet
//    are looked up in the light volume's world image, where the shadow pass tags a
//    water block. That image only exists while COLORED_LIGHTS is on, so on an
//    older loader with coloured lights off there is no source and the water stays
//    calm.
//
// The eye's own answer (`isEyeInWater`) is not used by either: it says whether the
// block the eye is in is water, which is not the same question.

// What the simulation does in the End, which has no weather and no tide to speak
// of: nothing, the same waves as the overworld, or waves under a lighter pull.
//
// The last is the default, and it is a deliberate difference rather than a copy of
// the overworld: the End is a place with its own physics, and water pulled down at
// the overworld's strength there reads as a pond that came along with the player.
// Low gravity here means the ripples travel more slowly and settle more slowly,
// which is what a weaker pull does to a surface.
//
// The middle setting exists so the two can be compared directly, and so a player
// who wants one physics everywhere can have it.
#define WATER_SIM_END 2 // [0 1 2]

// Whether this program is compiled for the End, and under which setting.
//
// The End's compute programs are their own files under world1/, and that is what
// tells them apart: Iris looks a program up in the current dimension's folder
// first, so the End runs those and every other dimension runs the root ones. The
// files in world1/ set the define below.
#if defined(WATER_SIM_END_DIMENSION) && WATER_SIM_END == 2
	#define WATER_SIM_END_LOW_GRAVITY
#endif

// The spring, the velocity damping and the travel speed, as constants so that the
// two physics differ by them rather than by branches inside the step.
//
// A weaker pull does two things to a surface: the waves travel more slowly, and
// they keep going longer. The first is the travel factor, the second is a much
// smaller spring and damping - the overworld's ripples are tuned to die out, and
// under low gravity they should not.
#ifdef WATER_SIM_END_LOW_GRAVITY
	const float WATER_SIM_SPRING = 0.0005;
	const float WATER_SIM_VELOCITY_DAMPING = 0.0025;
	const float WATER_SIM_TRAVEL = 0.55;
#else
	const float WATER_SIM_SPRING = 0.0014;
	const float WATER_SIM_VELOCITY_DAMPING = 0.006;
	const float WATER_SIM_TRAVEL = 1.0;
#endif

// How far the simulated tilt is taken on top of the regular waves.
#define WATER_INTERACTION_STRENGTH 1.00 // [0.00 0.05 0.10 0.15 0.20 0.25 0.30 0.35 0.40 0.45 0.50 0.55 0.60 0.65 0.70 0.75 0.80 0.85 0.90 0.95 1.00 1.05 1.10 1.15 1.20 1.25 1.30 1.35 1.40 1.45 1.50 1.55 1.60 1.65 1.70 1.75 1.80 1.85 1.90 1.95 2.00]

// Simulation grid resolution, and it changes more than what the effect costs: it
// changes what the waves look like.
//
// A coarser grid resolves less of the surface, so its ripples come out broader and
// denser - the water reads as a close-knit texture of small swells. A finer grid
// carries more detail, so the ripples are crisper and read as finer water. The
// difference is visible while the water is still, before anything has disturbed
// it, which is why it is written down here and not filed under cost.
//
// The wave speed and the steepness are rescaled by the constants below so that
// they stay the same at every level; only the amount of detail changes. Low is the
// default because the low performance tier turns the effect off entirely, and the
// tiers that keep it are the ones with room to spare.
#define WATER_SIM_QUALITY 0 // [0 1 2]

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

// Adds the simulated ripple to the water normal.
//
// `normalTangent` is the pack's own water normal in the space WaterNormal returns
// it in - in-plane x and y, z out of the surface - which for water lying flat is
// the same frame the simulated field lives in: x is east and y is north, and the
// caller's swizzle turns that into world axes. So the ripple is added there, in
// the same space and at the same point as the pack's own wave normals, which is
// where the original implementation adds it as well (batch 685).
//
// `worldXZ` is the fragment's world position, and it is deliberately the position
// *before* the parallax mapping moved the surface: parallax moves where the pack
// samples its own wave field, and a ripple sampled at the moved position slides
// with the parallax and reads as a pattern painted onto that surface rather than
// as water standing in the world.
//
// Only flat water calls this. A height field describes no standing face, and the
// caller already knows whether the face is flat.
vec3 WaterInteractionTangent(vec3 normalTangent, vec2 worldXZ) {
	// The first sub-step publishes the grid centre it used, the second a ready
	// flag. A frame in which the simulation did not run leaves the image zero, and
	// then the water is left exactly as it was - which is also the whole fallback
	// when compute shaders are unavailable.
	if (!(texelFetch(wave_sim_info_sampler, ivec2(1, 0), 0).z > 0.5)) {
		return normalTangent;
	}

	vec2 anchorWorld = texelFetch(wave_sim_info_sampler, ivec2(0, 0), 0).xy;

	vec2 coord = (worldXZ - anchorWorld) / WATER_SIM_TEXEL_SIZE
		+ 0.5 * float(WATER_SIM_RESOLUTION);

	// Texel centres sit at integer coordinates, so the sampler's uv is one half
	// texel further in.
	vec2 uv = (coord + 0.5) / float(WATER_SIM_RESOLUTION);

	// Outside the simulated area there is nothing to read; NaN is rejected by the
	// same comparison.
	if (any(isnan(uv)) || any(greaterThan(abs(uv - 0.5), vec2(0.5)))) {
		return normalTangent;
	}

	vec4 wave = texture(wave_sim_b_sampler, uv);

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
