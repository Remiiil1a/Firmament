// Colored block light, by flood fill.
//
// Minecraft's light engine is a flood fill that carries a brightness and nothing
// else: every light source in the world arrives as the same warm average, so a
// soul lantern and a torch light a wall identically. This file is the other half
// of the fix for that - a second flood fill, over a grid of voxels around the
// player, that carries colour. Each frame one step of it runs (prepare3.csh at
// the pack root), light spreads one voxel per step, and the terrain programs read
// the field back as the colour of their block light.
//
// The two references this was built from are Eclipse's LPV and Mellow's flood
// fill. What is taken from them is the shape: a voxel grid snapped to whole
// blocks around the player, written by the shadow pass, propagated one step per
// frame by a compute program, read back with a filter. What is deliberately not
// taken is their treatment of brightness - both let the voxel field decide how
// bright a surface is, and this pack keeps that on the lightmap (see BlockLighting
// in diffuse.glsl), because the lightmap's falloff is what every other option in
// this pack is tuned against. See LIGHT_VOLUME_STEP below for what that means for
// the reach of the colour.
//
// Iris only, for the same reason the water simulation is: custom images and
// compute shaders. On a loader without them the field never gets written, the
// ready flag in light_volume_info never rises, and every program that includes
// this file draws exactly what it drew before the file existed.
//
// Everything below is either compiled into the propagation pass (the simulation
// half, LIGHT_VOLUME_SIM) or into the terrain programs (the shading half), and the
// two halves share only the constants and the two coordinate helpers in the
// middle of the file.

#ifndef INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME
#define INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME

///////////////////////////////////////////////////////////////////////////////
//   The grid
///////////////////////////////////////////////////////////////////////////////

// Voxels per side, and the same number halved.
//
// One voxel is one block, so the grid is 64 blocks across and covers 32 blocks in
// every direction from the player. That is twice Minecraft's own block light
// range of 15, which leaves the colour's whole falloff inside the grid and gives
// the edge fade below room to run before the boundary is reached.
//
// It is a constant rather than an option at this version: 64 cubed at the format
// the images are declared with (RGBA16) is 2 MiB each, the pass that fills it is
// one dispatch, and there is no quality level below this one that would still be
// the same effect.
#define LIGHT_VOLUME_SIZE 64
#define LIGHT_VOLUME_RADIUS 32

// How much of a voxel's value survives one step of the fill.
//
// The field carries a light level, not a colour, so this is what sets its reach:
// a source enters the grid at full value and is 0.85^distance after that, which
// is 0.44 at five blocks, 0.20 at ten and 0.087 at fifteen - the same fifteen
// blocks the game's own block light spans.
//
// Both references are much shorter than this on purpose, and the reason is
// written out at the top of the file: they let the field decide brightness, so a
// long reach would mean a long falloff competing with their own light model.
// Here the brightness stays on the lightmap, and the colour has to reach exactly
// as far as the light it is colouring - otherwise a wall fifteen blocks from the
// only torch in a room would take the average warm tint for the whole room while
// the lightmap says it is lit by that torch.
#define LIGHT_VOLUME_STEP 0.85

// The value a voxel has to carry before the colour it holds is worth using.
//
// Below this the field is either far from every source or decaying after one was
// removed, and what it holds is a rounding error in the format rather than a
// colour. The band above it is the fade-in, so that a source coming into range
// does not step the tint on in one frame.
#define LIGHT_VOLUME_MINIMUM 0.02
#define LIGHT_VOLUME_FADE_IN 0.12

// How far along its own normal a fragment looks for the light that reaches it.
//
// Every fragment of a surface sits on a voxel boundary, and the fill keeps light
// out of solid voxels - light cannot be inside a block. Sampling at the
// fragment's own position would therefore land in the solid side of the boundary
// as often as the empty one, and the result is a dark seam along every block
// face, which is the same trap Eclipse's implementation notes. Half a block along
// the normal is in the empty voxel whatever the surface is.
#define LIGHT_VOLUME_NORMAL_OFFSET 0.55

// Where the grid fades out, as a fraction of its half-size.
//
// The grid is a cube of light cut out of the world, and without this the cut
// would be visible as exactly that. The colour is at its faded value by 0.95 of
// the half-size, which is two blocks inside the boundary.
#define LIGHT_VOLUME_EDGE_FADE_START 0.70
#define LIGHT_VOLUME_EDGE_FADE_END 0.95

///////////////////////////////////////////////////////////////////////////////
//   Where a position sits in the grid
///////////////////////////////////////////////////////////////////////////////

// Camera-relative position -> continuous voxel coordinate.
//
// Voxel i spans [i, i + 1) and its centre is at i + 0.5, which is the convention
// a linearly filtered sampler wants: sample at this coordinate divided by the
// grid size and the filter lands on the voxel centres.
//
// subBlockOffset is the part of the camera's world position that is not a whole
// block, which the caller supplies: the grid is snapped to whole blocks, so
// moving within a block must not move the grid. It reaches here one of two ways,
// and both are the same number - the simulation half computes it from
// cameraPosition, and the shading half reads it back out of light_volume_info,
// which is what keeps the two from ever disagreeing.
vec3 LightVolumeCoord(vec3 cameraRelativePos, vec3 subBlockOffset) {
	return cameraRelativePos + subBlockOffset
		+ vec3(float(LIGHT_VOLUME_RADIUS));
}

///////////////////////////////////////////////////////////////////////////////
//   The simulation half: compiled into prepare3.csh only
///////////////////////////////////////////////////////////////////////////////

// The propagation pass declares its own images, uniforms and entry point: they
// have no business being visible to the terrain programs, and the terrain
// programs are the ones the pack's uniform comparison looks at. See
// program/light_volume/step.csh.

///////////////////////////////////////////////////////////////////////////////
//   The shading half: compiled into the terrain programs
///////////////////////////////////////////////////////////////////////////////

// The three images the propagation pass hands over.
//
// The two fields are the frame-to-frame state, and which one is current changes
// every frame - the pass reads one and writes the other, because a step of the
// fill needs its neighbours' values from before it started. The info image is
// how this side knows which is which, and it is also where the ready flag comes
// from: on a loader that cannot allocate these, the sampler is left with nothing
// bound to it, an unbound sampler reads zero, the flag never rises, and the
// fallback below is what every surface gets.
uniform sampler3D light_volume_a_sampler;
uniform sampler3D light_volume_b_sampler;
uniform sampler2D light_volume_info_sampler;

// What the propagation pass published this frame.
//
// texel 0 is (the grid's lower corner in the world, ready), and texel 1 is (the
// sub-block part of the camera position, which field is current). The shading
// side needs nothing else from the pass, and in particular it does not read
// frameCounter itself: the parity of the ping-pong is decided in exactly one
// place, by the pass that does the pong.
vec4 LightVolumeAnchorAndReady() {
	return texelFetch(light_volume_info_sampler, ivec2(0, 0), 0);
}

vec4 LightVolumeOffsetAndSide() {
	return texelFetch(light_volume_info_sampler, ivec2(1, 0), 0);
}

// The field at a position, or black outside the grid.
//
// Outside the grid the field is not defined, and the sampler's own behaviour
// there is the loader's business rather than this file's - clamping would smear
// the edge voxels outwards, which is worse than nothing.
vec3 LightVolumeSample(vec3 cameraRelativePos, vec3 subBlockOffset, bool currentIsB) {
	vec3 uv = LightVolumeCoord(cameraRelativePos, subBlockOffset)
		/ float(LIGHT_VOLUME_SIZE);

	if (any(lessThan(uv, vec3(0.0))) || any(greaterThan(uv, vec3(1.0)))) {
		return vec3(0.0);
	}

	return currentIsB
		? texture(light_volume_b_sampler, uv).rgb
		: texture(light_volume_a_sampler, uv).rgb;
}

// The colour of block light at this position, as a mix between the fallback and
// the colour the flood fill put there.
//
// fallbackTint is the colour this pack would light the surface with if there were
// no flood fill at all - the lightmap's hue moved by BLOCKLIGHT_TEMPERATURE (see
// BlockLightTint in diffuse.glsl). It is both the value returned where the fill
// has nothing to say and the brightness donor for the colour it does have: the
// field's own magnitude is a distance weight, not a light level, so the colour
// that comes out of here is exactly as bright as the one that went in. That is
// what keeps this from changing how bright the world is - only what colour it is.
//
// blockLight is the game's own block light level for this fragment, and it is
// the third of the three weights below. The other two are how strong the field is
// here and how close the fragment is to the edge of the grid.
vec3 LightVolumeBlockLight(
	vec3 fallbackTint,
	vec3 cameraRelativePos,
	vec3 worldNormal,
	float blockLight,
	out float strength
) {
	strength = 0.0;

	vec4 anchorAndReady = LightVolumeAnchorAndReady();
	if (anchorAndReady.w < 0.5) {
		return fallbackTint;
	}

	vec4 offsetAndSide = LightVolumeOffsetAndSide();

	// Offset along the normal first, then sample - see LIGHT_VOLUME_NORMAL_OFFSET
	// for why sampling where the fragment actually is does not work.
	vec3 field = LightVolumeSample(
		cameraRelativePos + worldNormal * LIGHT_VOLUME_NORMAL_OFFSET,
		offsetAndSide.xyz,
		offsetAndSide.w > 0.5);

	// The magnitude of the field is how much light is here, and the direction of
	// it is the colour that light arrives in.
	float amount = max(field.r, max(field.g, field.b));

	if (amount < LIGHT_VOLUME_MINIMUM) {
		return fallbackTint;
	}

	// How much of the flood fill's colour this fragment takes, from three
	// independent things, and all three of them have to agree:
	//
	//  - the field has to be strong enough here to mean something;
	//  - the fragment has to be well inside the grid, or the edge of the grid
	//    would be visible as a cube of differently coloured light;
	//  - the game has to say this surface is lit by block light at all. This is
	//    what bounds the one real weakness of a voxel fill: light that leaks
	//    through a wall can change the colour of a surface the lightmap says is
	//    lit, but it cannot make a dark surface visible, because the brightness
	//    is not the field's to give. The smoothstep starts at zero rather than
	//    at one level so that a surface one step out of the dark still takes the
	//    colour of the light that reaches it.
	float strengthAtField = smoothstep(
		LIGHT_VOLUME_MINIMUM, LIGHT_VOLUME_FADE_IN, amount);

	vec3 gridDistance = abs(cameraRelativePos)
		/ float(LIGHT_VOLUME_RADIUS);
	float strengthAtEdge = 1.0 - smoothstep(
		LIGHT_VOLUME_EDGE_FADE_START,
		LIGHT_VOLUME_EDGE_FADE_END,
		max(gridDistance.x, max(gridDistance.y, gridDistance.z)));

	float strengthAtLight = smoothstep(0.0, 0.05, blockLight);

	strength = strengthAtField * strengthAtEdge * strengthAtLight;

	if (strength <= 0.0) {
		return fallbackTint;
	}

	// Hue only, at the fallback's own brightness. The field is normalised and then
	// scaled by the fallback's brightest channel rather than its luminance, which
	// is the same rule BlockLightTint uses: the brightest channel is what the
	// lightmap's own hue was normalised against, so the two agree.
	vec3 hue = field / amount;
	float brightness = max(fallbackTint.r, max(fallbackTint.g, fallbackTint.b));
	vec3 tint = hue * brightness;

	return mix(fallbackTint, tint, strength);
}

#endif // INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME
