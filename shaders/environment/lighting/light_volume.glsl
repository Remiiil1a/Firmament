// Colored block light, by flood fill.
//
// Minecraft's light engine is a flood fill that carries a brightness and nothing
// else: every light source in the world arrives as the same warm average, so a
// soul lantern and a torch light a wall identically. This file is the other half
// of the fix for that - a second flood fill, over a grid of voxels around the
// player, that carries colour. Each frame one step of it runs in the shadowcomp
// pass, light spreads one voxel per step, and the terrain programs read the field
// back as the colour of their block light. There is one shadowcomp entry point per
// dimension set - the root's, world-1/'s and world1/'s - because a worldN folder
// is a complete program set rather than a set of overrides; see
// world-1/shadowcomp.csh for what that means.
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
// compute shaders. On a loader without them the images are not there: the
// samplers read zero, the field samples as black, and every program that
// includes this file draws exactly what it drew before the file existed.
//
// Everything below is either compiled into the propagation pass (the simulation
// half) or into the programs that sample the field (the shading half, which
// diffuse.glsl turns on by defining LIGHT_VOLUME_CONSUMER before it includes
// this file), and the halves share only the constants and the coordinate helper
// in the middle of the file.

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
//   The diagnostic
///////////////////////////////////////////////////////////////////////////////

// A view of the fill for the menu, and the reason it is two views rather than
// one.
//
// "The coloured light does nothing" has three possible layers, and one picture
// cannot tell them apart:
//
//  * the propagation pass is not running, or the custom images do not exist, so
//    the field the shading side samples is black;
//  * the writer is not filling the world image, so there is nothing for the
//    propagation to spread even though the pass itself runs;
//  * both of those work and the shading side still finds nothing, which is a
//    question about the consumer rather than about the feature.
//
// FIELD shows exactly what BlockLighting samples: the same function, the same
// parity, the same anchor offset and the same normal offset, multiplied by four
// so that a faint field is visible. There is no ready flag to report, and the
// picture does not need one: a fill that has never run and a fill that is
// genuinely black are the same picture, and both mean "no colour here", which
// is exactly what the consumer falls back on.
//
// WORLD shows what the writer put in the world image at this fragment's voxel:
// emitters as their colour times four, a solid block as dark grey, a stained
// glass filter as dark blue and air as black.
//
// Read together: a black FIELD over a coloured WORLD means the writer works and
// the propagation is the fault; a black WORLD means nothing is being written at
// all, and the other two layers are not worth looking at first. The one case the
// two cannot separate is a loader that cannot allocate the images at all: then
// both views are black, which is the same picture as an empty volume.
//
// NONE is the shipped state. It compiles the view in lit.fsh out of the terrain
// programs, so the default build is exactly the build it was.
#define LIGHT_VOLUME_DEBUG_NONE 0
#define LIGHT_VOLUME_DEBUG_FIELD 1
#define LIGHT_VOLUME_DEBUG_WORLD 2
#define LIGHT_VOLUME_DEBUG LIGHT_VOLUME_DEBUG_NONE // [LIGHT_VOLUME_DEBUG_NONE LIGHT_VOLUME_DEBUG_FIELD LIGHT_VOLUME_DEBUG_WORLD]

///////////////////////////////////////////////////////////////////////////////
//   The grid
///////////////////////////////////////////////////////////////////////////////

// The options, declared here rather than in a settings header because this is the
// only file the propagation pass and the terrain programs both include: a
// declaration in either end's own files could be visible to one and not the
// other, and then the two would disagree about the grid - which is the kind of
// disagreement that compiles everywhere.
//
// COLORED_LIGHT_RANGE is the side, in blocks, of the cube the colour lives in:
// 32, 48, 64, 96 or 128. It sizes the grid itself - the three images, the number
// of voxels the propagation advances each frame and the number of invocations its
// dispatch runs - so it is the option that buys performance, not only a fade. The
// side of a cube rather than a radius because that is the number the images and the
// dispatch are counted in, and because the memory is the cube of it; half of this
// value is how far from the player the colour can actually reach.
//
// The cost of each setting, for the whole feature: one voxel is one invocation a
// frame, one volume is eight bytes a voxel (RGBA16), and there are three volumes.
//
//   32 ->      32,768 invocations a frame, 0.75 MiB of images
//   48 ->     110,592 invocations a frame, 2.5 MiB
//   64 ->     262,144 invocations a frame, 6 MiB
//   96 ->     884,736 invocations a frame, 20 MiB
//   128 ->  2,097,152 invocations a frame, 48 MiB
//
// Three separate readers take this one value and none of them can see the others:
// the image declarations in shaders.properties, which are what the loader
// allocates; the #if chain below, which is the voxel count the shader indexes
// with; and the literal work group counts in program/light_volume/step.csh, which
// is where the dispatch size comes from. All three have to be edited together.
#define COLORED_LIGHT_RANGE 64 // [32 48 64 96 128]

// How saturated the colour the fill contributes is, applied where the field is
// turned back into a tint in LightVolumeBlockLight below. 1.0 is the colour the
// light arrives in. Below 1.0 the hue is pulled towards its own luminance and the
// fill's colour counts for proportionally less, and at 0.0 it counts for nothing:
// the block light is then the pack's own colour again (BlockLightTint, the same
// value the fallback path returns). Above 1.0 exaggerates the hue. It is not a
// brightness control - the output peak is renormalised to the fallback's
// brightness after the mix, so the light stays as bright at every setting.
#define COLORED_LIGHT_SATURATION 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5]

// Voxels per side of the three volumes, from the option above, and the same
// number halved.
//
// One voxel is one block, so the grid is LIGHT_VOLUME_SIZE blocks across and
// covers LIGHT_VOLUME_GRID_RADIUS blocks in every direction from the player. What
// the fill can reach is therefore half the option's number: 16 blocks at 32, 24 at
// 48, 32 at 64, 48 at 96 and 64 at 128. The default 64 reaches 32, twice the game's
// own block light span of 15, which keeps the colour's whole falloff inside the
// grid and leaves the edge fade below room to run before the boundary is reached.
//
// This chain and the one in shaders.properties are the same five values in the
// same order, and the final #else is the default value in both files: Iris reads
// an image's side from the properties file, so a shader that resolved a different
// size would index a grid the images do not have. The third chain - the dispatch
// size - is in program/light_volume/step.csh, and it is written as literal
// integers there for the reason given at that declaration.
#if COLORED_LIGHT_RANGE == 32
	#define LIGHT_VOLUME_SIZE 32
#elif COLORED_LIGHT_RANGE == 48
	#define LIGHT_VOLUME_SIZE 48
#elif COLORED_LIGHT_RANGE == 96
	#define LIGHT_VOLUME_SIZE 96
#elif COLORED_LIGHT_RANGE == 128
	#define LIGHT_VOLUME_SIZE 128
#else
	#define LIGHT_VOLUME_SIZE 64
#endif

// Half the grid, in voxels. This is the grid's centre in its own coordinates and
// nothing else: LightVolumeCoord adds it to put the player at the middle of the
// grid, which is also the voxel the player stands in. It is what the consumer's
// edge fade is measured against, now that the grid is exactly the cube the fill
// uses and there is no smaller "active" radius inside it.
#define LIGHT_VOLUME_GRID_RADIUS (LIGHT_VOLUME_SIZE / 2)

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

// Where the colour fades out, as a fraction of the grid radius.
//
// Without this the edge of the grid would be visible as exactly that cut: the
// fill's own decay never reaches zero at the boundary, so what is beyond it is a
// hard end to the colour rather than a falloff. The fade runs from 0.70 to 0.95 of
// the radius, so the last quarter of the radius is spent fading: about 4 blocks at
// the 32 setting, 6 at 48, 8 at 64, 12 at 96 and 16 at 128. A fraction rather than
// a distance keeps the fade the same shape at every setting.
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
// moving within a block must not move the grid. All three ends take it from
// fract(cameraPosition) - the writer when it stores a block, the consumer when it
// samples the field, and the compute pass is given the same value by the shift it
// applies - so none of them can disagree about where the grid sits. This is
// Eclipse's anchor formula with the same term, lib/lpv_common.glsl:12-19.
vec3 LightVolumeCoord(vec3 cameraRelativePos, vec3 subBlockOffset) {
	return cameraRelativePos + subBlockOffset
		+ vec3(float(LIGHT_VOLUME_GRID_RADIUS));
}

///////////////////////////////////////////////////////////////////////////////
//   The simulation half: compiled into the shadowcomp entries only
///////////////////////////////////////////////////////////////////////////////

// The propagation pass declares its own images and entry point: they have no
// business being visible to the terrain programs, and the terrain programs are
// the ones the pack's uniform comparison looks at. See
// program/light_volume/step.csh.
//
// One uniform is shared instead of private: frameCounter, declared below. The
// pass needs it to decide which field it writes this frame, and the consumer
// needs it to decide which field it reads - and there is no third place that
// publishes the answer. That is Eclipse's arrangement: its compute and its
// consumer both read frameCounter and nothing else (dimensions/shadowcomp.csh:
// 169-172, lib/lpv_render.glsl:16).

///////////////////////////////////////////////////////////////////////////////
//   The shading half: compiled into the programs that sample the field
///////////////////////////////////////////////////////////////////////////////

// The frame the recurrence is on, read by the compute pass to pick the field it
// writes and by the consumer half below to pick the field it samples.
//
// Declared here because the terrain programs do not otherwise have it: their
// include graph has no declaration of frameCounter, and Iris provides it in
// every stage. Eclipse declares it in the same two places - its compute pass and
// its consumer.
uniform int frameCounter;

// The consumer half, compiled only for the programs that define
// LIGHT_VOLUME_CONSUMER before including this file. diffuse.glsl is the only
// place that does, and it is the only place that samples the field; the writer
// and the compute pass include this file for its constants and its coordinate
// helper only.
//
// cameraPosition is deliberately not used here at all: its fractional part,
// the grid's sub-block offset, is passed in by the two call sites instead,
// from the declaration their own translation unit already has. This file
// cannot declare cameraPosition itself, because the writer includes it too and
// declares its own copy, and a second declaration in one translation unit is a
// redefinition. Eclipse reads fract(cameraPosition) directly in its consumer
// because its cameraPosition comes from one shared header (lib/lpv_common.glsl:
// 12-19); the arithmetic here is the same, only the declaration is the caller's.
#ifdef LIGHT_VOLUME_CONSUMER
// The two fields of the recurrence.
//
// The compute pass writes one and reads the other, and which is which flips
// every frame: even frames write the first and read the second, odd frames the
// reverse (see step.csh). The consumer reads the one the pass wrote this frame,
// so even frames sample the first and odd frames the second.
uniform sampler3D light_volume_a_sampler;
uniform sampler3D light_volume_b_sampler;

// The field at a position, or black outside the grid.
//
// subBlockOffset is the fractional part of cameraPosition, which the caller
// passes in for the reason above. Outside the grid the field is not defined,
// and the sampler's own behaviour there is the loader's business rather than
// this file's - clamping would smear the edge voxels outwards, which is worse
// than nothing.
//
// The parity is derived here rather than published, and it is Eclipse's
// SampleLpvLinear convention (lib/lpv_render.glsl:16): even frames read the
// first field and odd frames the second. The compute pass mirrors it by
// writing the first on even frames (dimensions/shadowcomp.csh:169-172). The
// two must agree or the field flickers between two images, which is a failure
// a still screenshot cannot show.
vec3 LightVolumeSample(vec3 cameraRelativePos, vec3 subBlockOffset) {
	vec3 uv = LightVolumeCoord(cameraRelativePos, subBlockOffset)
		/ float(LIGHT_VOLUME_SIZE);

	if (any(lessThan(uv, vec3(0.0))) || any(greaterThan(uv, vec3(1.0)))) {
		return vec3(0.0);
	}

	return (frameCounter % 2) == 0
		? texture(light_volume_a_sampler, uv).rgb
		: texture(light_volume_b_sampler, uv).rgb;
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
// subBlockOffset is passed through to LightVolumeSample; see the note there for
// why it is an argument rather than fract(cameraPosition) read here.
//
// lightHere is the game's own block light level at this fragment, and it is the
// third of the three weights below. The other two are how strong the field is
// here and how close the fragment is to the edge of the grid.
vec3 LightVolumeBlockLight(
	vec3 fallbackTint,
	vec3 cameraRelativePos,
	vec3 worldNormal,
	vec3 subBlockOffset,
	float lightHere,
	out float strength
) {
	strength = 0.0;

	// Offset along the normal first, then sample - see LIGHT_VOLUME_NORMAL_OFFSET
	// for why sampling where the fragment actually is does not work.
	vec3 field = LightVolumeSample(
		cameraRelativePos + worldNormal * LIGHT_VOLUME_NORMAL_OFFSET,
		subBlockOffset);

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
	//  - the fragment has to be well inside the grid, or the edge of the
	//    coloured cube would be visible as exactly that;
	//  - something has to be lighting this surface already. This is what bounds
	//    the one real weakness of a voxel fill: light that leaks through a wall
	//    can change the colour of a surface the game says is lit, but it cannot
	//    make a dark surface visible, because the brightness is not the field's
	//    to give. The light counted here is the game's block light level, which
	//    is the only light the fill's colours come from. The smoothstep starts at
	//    zero rather than at one level so that a surface one step out of the dark
	//    still takes the colour of the light that reaches it.
	float strengthAtField = smoothstep(
		LIGHT_VOLUME_MINIMUM, LIGHT_VOLUME_FADE_IN, amount);

	vec3 gridDistance = abs(cameraRelativePos)
		/ float(LIGHT_VOLUME_GRID_RADIUS);
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
#endif // LIGHT_VOLUME_CONSUMER

#endif // INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME
