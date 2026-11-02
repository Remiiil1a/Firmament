// Colored block light, by flood fill.
//
// Minecraft's light engine is a flood fill that carries a brightness and nothing
// else: every light source in the world arrives as the same warm average, so a
// soul lantern and a torch light a wall identically. This file is the other half
// of the fix for that - a second flood fill, over a grid of voxels around the
// player, that carries colour. Each frame one step of it runs in the prepare3
// pass, light spreads one voxel per step, and the terrain programs read the field
// back as the colour of their block light. There is one prepare3 entry point per
// dimension set - the root's, world-1/'s and world1/'s - because a worldN folder
// is a complete program set rather than a set of overrides; see
// world-1/prepare3.csh for what that means.
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
// half) or into the programs that write and sample the field (the shading half),
// and the two halves share only the constants and the two coordinate helpers in
// the middle of the file.

#ifndef INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME
#define INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME

///////////////////////////////////////////////////////////////////////////////
//   What a voxel of the world image means
///////////////////////////////////////////////////////////////////////////////

// The world image is the propagation pass's whole input: one voxel per block,
// written by the shadow pass this frame and read by program/light_volume/step.csh
// afterwards. It has exactly four states, and alpha is the tag that tells them
// apart. They are written down here because this file is what both ends include,
// so this is the only place the two can be held to the same table.
//
//   air      rgb 0               a 0.0   nothing here; light crosses freely
//   emitter  rgb light colour    a 0.0   a light source stands here
//   filter   rgb pane tint       a 0.5   stained glass; light that crosses takes
//                                        the pane's colour
//   solid    rgb 0               a 1.0   an opaque block; light neither enters
//                                        nor leaves
//
// The propagation reads the thresholds as `a > 0.75` solid, `a > 0.25` filter,
// and anything else as air or emitter. Air and emitter share an alpha because an
// emitter is air that happens to carry a colour, and the difference between them
// is only what the step does below itself: an emitter adds its own rgb, which is
// how a source is at full strength in the frame it appears.
//
// A filter is the third state and the only one that changes light on the way
// through: its rgb is multiplied into the value crossing it, so a red pane puts
// red light on the floor. It is a state of its own rather than a colour packed
// into an emitter's slot because a pane is not a source - it must not inject
// light of its own - and because a pane with no colour (black stained glass)
// would otherwise be indistinguishable from air. Alpha 0.5 is the middle of the
// range and far from both thresholds, so no rounding in the writer can move a
// filter into the solid or the air state; the image is RGBA16 unsigned, so 0.5
// is exactly representable.
//
// Why alpha rather than a convention on rgb: the writer and the reader are
// separate programs and the image is the only thing they share. A convention
// that could be read two ways would compile on both ends and produce a different
// picture, and the failure would show up as a colour that is wrong rather than
// as anything that fails. The two thresholds and the writer's branches are the
// whole of the encoding, and both are in this batch's contract.

///////////////////////////////////////////////////////////////////////////////
//   The grid
///////////////////////////////////////////////////////////////////////////////

// The two options, declared here rather than in a settings header because this
// is the only file the propagation pass and the terrain programs both include:
// a declaration in either end's own files could be visible to one and not the
// other, and then the two would disagree about the size of the grid - which is
// the kind of disagreement that compiles everywhere.
//
// COLORED_LIGHT_RANGE is the grid's side in blocks, and it is one of the two
// options in this pack that change what a feature costs in memory rather than
// only what it looks like (the water simulation's detail option is the other:
// it moves the size of the two wave images). The images here are declared at
// this size in shaders.properties, and the propagation pass writes one whole
// volume every frame; the numbers are at LIGHT_VOLUME_SIZE just below and
// repeated where the images are declared.
#define COLORED_LIGHT_RANGE 64 // [48 64 96 128]

// How saturated the colour the fill contributes is, applied where the field is
// turned back into a tint in LightVolumeBlockLight below. 1.0 is the colour the
// light arrives in. Below 1.0 the hue is pulled towards its own luminance and the
// fill's colour counts for proportionally less, and at 0.0 it counts for nothing:
// the block light is then the pack's own colour again (BlockLightTint, the same
// value the fallback path returns). Above 1.0 exaggerates the hue. It is not a
// brightness control - the output peak is renormalised to the fallback's
// brightness after the mix, so the light stays as bright at every setting.
#define COLORED_LIGHT_SATURATION 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5]

// Voxels per side, chosen by COLORED_LIGHT_RANGE above, and the same number
// halved.
//
// One voxel is one block, so the grid is LIGHT_VOLUME_SIZE blocks across and
// covers half of that in every direction from the player. The default 64 is
// twice Minecraft's own block light range of 15, which leaves the colour's whole
// falloff inside the grid and gives the edge fade below room to run before the
// boundary is reached. The smallest setting still reaches 24 blocks from the
// camera, which is outside the reach of any single block light, so no setting
// cuts through the light of a source standing near the player.
//
// The size is an option because of what it costs. The volumes are RGBA16, eight
// bytes a voxel, so one of them is 0.84 MiB at 48, 2 MiB at 64, 7 MiB at 96 and
// 16 MiB at 128 - and there are three (the world image and the two fields). The
// info image is 48 bytes at every setting (RGBA32F, three texels: the grid's
// anchor and ready flag, the sub-block offset and current field, and the hand
// program's held-light slot). The propagation pass also writes a whole volume
// each frame, so a larger grid costs bandwidth as well.
#if COLORED_LIGHT_RANGE == 48
	#define LIGHT_VOLUME_SIZE 48
#elif COLORED_LIGHT_RANGE == 96
	#define LIGHT_VOLUME_SIZE 96
#elif COLORED_LIGHT_RANGE == 128
	#define LIGHT_VOLUME_SIZE 128
#else
	#define LIGHT_VOLUME_SIZE 64
#endif
#define LIGHT_VOLUME_RADIUS (LIGHT_VOLUME_SIZE / 2)

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
// would be visible as exactly that. The fade runs from 0.70 to 0.95 of the
// half-size, so the last five percent of the radius is spent fading: 1.2 blocks
// at the smallest range and 3.2 blocks at the largest. It is a fraction of the
// radius rather than a distance so that the fade keeps the same shape at every
// setting, which is the point of the option being a size rather than a look.
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
//   The simulation half: compiled into the prepare3 entries only
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
//
// The info image is three texels wide, not two: texel (2, 0) is a slot the hand
// program writes the colour of whatever the player is holding into, and the
// propagation pass injects it at the player's own voxel. This side does not read
// it - the width is noted here only so it is not a mystery - and the two texels
// below are fetched by index rather than by width, so adding the third moved
// neither of them.
uniform sampler3D light_volume_a_sampler;
uniform sampler3D light_volume_b_sampler;
uniform sampler2D light_volume_info_sampler;

// What the propagation pass published this frame.
//
// texel 0 is (the grid's lower corner in the world, ready), and texel 1 is (the
// sub-block part of the camera position, which field is current). The shading
// side needs nothing else from the pass, and in particular it does not read
// frameCounter itself: the parity of the ping-pong is decided in exactly one
// place, by the pass that does the pong. Texel 2 is the held-light slot and is
// not read here at all; see the note above.
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
// lightHere is how much light is at this fragment at all - the larger of the
// game's block light level and the held light level, combined by BlockLighting
// in diffuse.glsl - and it is the third of the three weights below. The other two
// are how strong the field is here and how close the fragment is to the edge of
// the grid.
vec3 LightVolumeBlockLight(
	vec3 fallbackTint,
	vec3 cameraRelativePos,
	vec3 worldNormal,
	float lightHere,
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
	//  - something has to be lighting this surface already. This is what bounds
	//    the one real weakness of a voxel fill: light that leaks through a wall
	//    can change the colour of a surface the game says is lit, but it cannot
	//    make a dark surface visible, because the brightness is not the field's
	//    to give. The light counted here is block light or held light, whichever
	//    is larger - the fill's job is "is there light here at all", and a held
	//    source is light. The smoothstep starts at zero rather than at one level
	//    so that a surface one step out of the dark still takes the colour of the
	//    light that reaches it.
	float strengthAtField = smoothstep(
		LIGHT_VOLUME_MINIMUM, LIGHT_VOLUME_FADE_IN, amount);

	vec3 gridDistance = abs(cameraRelativePos)
		/ float(LIGHT_VOLUME_RADIUS);
	float strengthAtEdge = 1.0 - smoothstep(
		LIGHT_VOLUME_EDGE_FADE_START,
		LIGHT_VOLUME_EDGE_FADE_END,
		max(gridDistance.x, max(gridDistance.y, gridDistance.z)));

	float strengthAtLight = smoothstep(0.0, 0.05, lightHere);

	strength = strengthAtField * strengthAtEdge * strengthAtLight;

	// The option's lower half also scales how much of the fill's colour is mixed
	// in, and zero means not at all. The fill's only contribution is a colour, so
	// "no saturation" and "no fill" are the same picture: at 0.0 this factor
	// takes the early out below, which returns the fallback itself
	// (BlockLightTint, the pack's own block light colour) rather than a greyed
	// version of it. Above 1.0 the factor is one, because the upper half
	// exaggerates the hue instead - see the hue below.
	strength *= clamp(COLORED_LIGHT_SATURATION, 0.0, 1.0);

	if (strength <= 0.0) {
		return fallbackTint;
	}

	// Hue only, at the fallback's own brightness. The field is normalised and then
	// scaled by the fallback's brightest channel rather than its luminance, which
	// is the same rule BlockLightTint uses: the brightest channel is what the
	// lightmap's own hue was normalised against, so the two agree.
	vec3 hue = field / amount;

	// The saturation option, applied to the hue and before the brightness is
	// restored, so that it moves the colour of the light and not the amount of
	// it. 1.0 leaves the fill's colour exactly as the propagation carried it -
	// the default, and at 1.0 the mix below is the identity. Below 1.0 the hue is
	// pulled towards its own luminance, and above 1.0 it is pushed away from it,
	// which is a stronger tint. 0.0 by itself would leave a grey to mix in; the
	// strength factor above is what turns that end of the scale into the fallback
	// colour, so what a surface gets there is the pack's own block light and not
	// a pale one.
	//
	// The luma weights are Rec709, the same triple the field's own magnitude and
	// BlockLightTint use, so "desaturated" means the same thing here as it does
	// everywhere else in the pack.
	vec3 grey = vec3(dot(hue, vec3(0.2126, 0.7152, 0.0722)));
	hue = mix(grey, hue, COLORED_LIGHT_SATURATION);

	// Re-normalise to the peak the hue arrived with, which is exactly 1.0 because
	// the field was divided by its brightest channel just above. Mixing a colour
	// with its own luminance lowers that peak - half saturation turns a pure hue
	// into a paler one - and mixing past 1.0 raises it by extrapolation. Without
	// this division the slider would also change how bright the fill's colour is,
	// which would break the design's promise that the flood fill changes hue and
	// not brightness and make "a colour control, not a brightness one" false in
	// the option's own description. A negative channel can appear above 1.0
	// (extrapolation takes a dark channel below zero); light has no negative
	// intensity, so it is clamped rather than kept.
	hue /= max(max(hue.r, max(hue.g, hue.b)), 1.0e-4);
	hue = max(hue, vec3(0.0));

	float brightness = max(fallbackTint.r, max(fallbackTint.g, fallbackTint.b));
	vec3 tint = hue * brightness;

	// Both ends of the mix are now at the fallback's own brightness - the fallback
	// by definition, the tint because its peak was just restored - so no setting
	// of the option can make block light brighter or darker, only a different
	// colour. That is the property DESIGN.md section 7 is about.
	return mix(fallbackTint, tint, strength);
}

#endif // INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME
