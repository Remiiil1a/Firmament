// Coloured block light: one step of the flood fill.
//
// Included by the three shadowcomp entries - shadowcomp.csh at the root and the two
// under world-1/ and world1/ - which supply the #version line and the note on where
// this pass sits in the frame. What runs here is the shading half's other end, from
// /environment/lighting/light_volume.glsl: every voxel of the grid takes the
// strongest neighbour that carries light in the previous frame's field, one step
// down, and then adds whatever its own voxel of the world image is - a light
// source, a pane that tints, or a block that stops it.
//
// BATCH 739 REWROTE THIS PASS. What changed, and why each change is not a patch:
//
//  * The field is stored logarithmically. A voxel is a normalised colour in rgb
//    and log2(level + 1) / LIGHT_VOLUME_LEVEL_RANGE in alpha, so the level decays
//    by a constant per voxel in the stored space and the quantisation error does
//    not compound. The old field was linear and carried a colour with no level at
//    all. See the encoding section of light_volume.glsl - including why the
//    channels stayed sixteen bits rather than dropping to eight.
//
//  * A source's reach is its own light level, not one constant for the whole
//    game. BlockLightRange in /environment/lighting/light_colors.glsl answers how
//    far a family reaches - a torch 14, a magma block 3, an amethyst bud 5 - and
//    that number is what the voxel emits. The old fill emitted a fixed value and
//    let one decay constant decide every source's reach, which is why a magma
//    block lit as far as a glowstone.
//
//  * The world image holds a block's ID rather than a five-state tag. The table
//    below turns an ID into a colour and a range; the old encoding had five
//    states and a palette compiled into the shader, and could not express "this
//    block reaches three blocks" at all.
//
// What is deliberately kept from the old fill, against Eclipse's own choice: the
// level is the MAXIMUM over the neighbours, not their average. Eclipse averages
// (dimensions/shadowcomp.csh:90-103), which is a diffusion field and is the right
// shape for the global-illumination approximation it feeds. This pack's field is
// block light, and batch 703 already tested the average here: the author reported
// that the falloff flattened out and a lit area read as one broad wash instead of
// a cone around its source. The maximum is the shape that was confirmed in game,
// so it stays; what the average was wanted for - two colours meeting head-on
// coming out as the brighter of each channel - is solved below by weighting the
// colour by the level that carried it, which mixes the colours without touching
// the falloff.
//
// One step per frame, not a loop that converges inside one dispatch. The field is
// a recurrence, not something solved: it arrives at the frame as an image,
// advances by one voxel, and is stored again. Spreading and fading are not
// symmetric: a source is full strength in its own voxel in the frame it appears and
// takes fifteen frames to reach fifteen blocks, while a removed one decays by the
// step every frame and is only gone once it is below LIGHT_VOLUME_MINIMUM.
//
// The program is Iris only, and every part of it that touches an image is kept
// behind IS_IRIS: on a loader without custom images the body does nothing, the
// images are never written, the field samples as black, and block light stays the
// colour it has always had. Nor does it run at all when COLORED_LIGHTS is off -
// see program.shadowcomp.enabled in shaders.properties - because with the option
// off nothing reads the field.

// The material IDs first, then the palette and the per-family range.
//
// The order is not cosmetic and it is LESSONS 107: light_colors.glsl is written as
// branches over the material IDs, so it needs materialIDs.glsl in the same
// translation unit before it. Until batch 739 this pass did not include the
// palette at all - the world image carried the colour and the propagation only
// spread it - so the palette's own dependency was never this file's problem. It is
// now, and the compute check caught it: the three shadowcomp entries failed with
// `'LIGHT_WARM' : undeclared identifier` while the front end stayed green, because
// the front end does not compile compute programs.
//
// light_colors.glsl is the one place a light's colour is written down, and since
// batch 739 it is also the one place its reach is: BlockLightRange sits beside
// BlockLightColor so that a family cannot have a colour and no range, or the other
// way round.
#include "/environment/materialIDs.glsl"
#include "/environment/lighting/light_colors.glsl"

// The shared constants, the encoding and the one definition of where a position
// sits in the grid. The file has no simulation-only section at this version, so
// this is the same source the terrain programs include: the grid's geometry, the
// encoding and the voxel index the shadow pass writes with all come from one
// place, and the three ends of the feature cannot drift apart.
//
// The consumer-side samplers and functions in that file are compiled out here,
// because this program does not define LIGHT_VOLUME_CONSUMER; what this pass
// needs from the shared file is the grid, the encoding and frameCounter. Its own
// images are declared below, for the reason sim.glsl gives for the same
// arrangement in the water simulation: they exist only for the compute pass and
// have no business in the comparison the terrain programs are checked against.
#include "/environment/lighting/light_volume.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

// 8 invocations per axis and one group per eight voxels of the grid: the whole
// volume in one dispatch, one invocation per voxel. The count follows the grid,
// which follows COLORED_LIGHT_RANGE - 4 groups per axis at 32, then 6, 8, 12, 16
// and 32 at 256 - so the dispatch is 32,768 invocations a frame at the smallest
// setting and 16,777,216 at the largest.
//
// The six declarations below are literal integers, one branch per setting, and
// they have to stay literal. The loader reads the work group count out of this
// source before the program runs, so it has to be a number it can see there; what
// it does with an expression is not something this machine can observe. What this
// project has observed is the outcome: batch 704 had ivec3(16, 16, 16) written out
// and the field was shaded in game, batches 705 and 706 had ivec3(LIGHT_VOLUME_SIZE
// / 8) and ivec3(COLORED_LIGHT_RANGE / 8) here and the field was black in game
// twice, while every check in this project stayed green in all three batches -
// a GLSL compiler folds either form and reports nothing. Those two batches changed
// other things as well, so this is not a proof about the mechanism; it is the one
// shape every build known to work in game uses. The other compute passes shipped in
// this pack (program/water_interaction/step_a.csh and step_b.csh) select theirs per
// branch too, and so does the reference this feature was built from (Eclipse's
// dimensions/shadowcomp.csh picks its LPV grid, 6/7/8, the same way), which is
// where this shape comes from.
//
// What a mistake costs is the whole feature, silently: this one dispatch is what
// advances the entire grid, so a dispatch that does not run writes nothing, the
// field samples as black, and every surface just takes the fallback tint - the same
// picture as "coloured lights off".
#if COLORED_LIGHT_RANGE == 32
const ivec3 workGroups = ivec3(4, 4, 4);
#elif COLORED_LIGHT_RANGE == 48
const ivec3 workGroups = ivec3(6, 6, 6);
#elif COLORED_LIGHT_RANGE == 64
const ivec3 workGroups = ivec3(8, 8, 8);
#elif COLORED_LIGHT_RANGE == 96
const ivec3 workGroups = ivec3(12, 12, 12);
#elif COLORED_LIGHT_RANGE == 128
const ivec3 workGroups = ivec3(16, 16, 16);
#elif COLORED_LIGHT_RANGE == 256
const ivec3 workGroups = ivec3(32, 32, 32);
#else
const ivec3 workGroups = ivec3(16, 16, 16);
#endif

#ifdef IS_IRIS
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
// frameCounter is declared by light_volume.glsl above, shared with the consumer.

// What the shadow pass wrote this frame: one voxel per block, holding the block's
// material ID in red and, for a stained pane, the colour it tints light with in
// green, blue and alpha.
//
// The ID is stored as id / 255.0 in the red channel. The image is RGBA16, so the
// channel has far more resolution than the 47 IDs this pack assigns need - the
// division and the reader's `uint(r * 255.0 + 0.5)` are exact for every integer
// from 0 to 255, and the extra bits are simply unused. The format is the one the
// field images use, which keeps the three declarations identical.
//
// This is the one image of the three that the loader clears every frame, and it
// has to be, because the shadow pass only draws what the sun can see: a voxel no
// vertex reached this frame means nothing was drawn there, not "nothing is
// there". A value left over from the frame before would be an occluder that has
// since been mined, or a light that has since been taken down, and the fill would
// trust it for one frame. readonly, because a fill reads the world and never
// writes it back.
layout(rgba16) uniform readonly image3D light_volume_world;

// The two fields: the recurrence itself. One is this frame's output and the other
// is the frame before's, and which is which flips every frame - the pass reads
// the one it wrote last frame and writes the other.
//
// Both are declared read-write rather than one readonly and one writeonly,
// because the roles are a function of frameCounter and not of the declaration:
// the parity is decided once, in main, and it decides both the read and the write
// from that one answer. A pair of one-way declarations would have to name the
// same image twice under two qualifiers.
//
// Neither is cleared by the loader, and neither can be: the field is the state
// this pass carries between frames, and clearing it would reset the fill to black
// every frame - a light would never get past the voxel next to its source. What
// the first frame reads out of them is whatever the loader's allocation holds,
// which decays below LIGHT_VOLUME_MINIMUM within the same frames a light takes to
// fade out.
layout(rgba16) uniform image3D light_volume_a;
layout(rgba16) uniform image3D light_volume_b;

// A stored voxel, decoded into the colour it carries and the level it carries.
//
// The two are separate here and were one in the old field: rgb is the colour
// normalised so that its brightest channel is one, and the level is the number of
// blocks of reach. Keeping them apart is what lets the level be combined by
// maximum while the colour is combined by a level-weighted average - see the note
// at the top of the file for why those are different questions.
vec4 LightVolumeDecode(vec4 stored) {
	// BATCH 790: THE SAME GUARD AS THE CONSUMER'S, AND FOR THE SAME REASON.
	//
	// This decodes the field the pass is about to read - the one written on the
	// previous frame - and on the first frame after a world load there is no
	// previous frame. The images are allocated with a null data pointer and
	// nothing clears them, so what comes back is whatever the driver had there.
	//
	// `exp2(a * 15) - 1` turns an alpha of 1.0 into 32767 and anything above it
	// into an infinity, and a NaN alpha into a NaN. Here that would be spread
	// across the whole grid by the flood fill rather than shown directly, which
	// is worse: one bad voxel becomes every voxel it reaches.
	//
	// The range is the encoder's own - `log2(level + 1) / 15` for a level in
	// [0, 15] gives [0, 0.2667], NOT [0, 1] - so an alpha outside it was never
	// written by this pass. Treated as no light, which is what an unwritten voxel
	// means. The bound is the encoder's own expression so the two cannot drift.
	if (!(stored.a >= 0.0
		&& stored.a <= log2(LIGHT_VOLUME_LEVEL_RANGE + 1.0)
			/ LIGHT_VOLUME_LEVEL_RANGE)) {
		return vec4(0.0);
	}

	float level = exp2(stored.a * LIGHT_VOLUME_LEVEL_RANGE) - 1.0;
	return vec4(stored.rgb, level);
}

// The inverse: a colour and a level, stored as the encoding section of
// light_volume.glsl defines them.
//
// The colour is normalised to its brightest channel before it is stored, so that
// the eight bits of each channel are spent on the hue rather than on a magnitude
// that the alpha channel already carries. A colour that is black - which is what a
// voxel with no light holds - normalises to black, and its level is zero, so the
// decode gives back zero rather than a division by a rounding error.
vec4 LightVolumeEncode(vec3 colour, float level) {
	float peak = max(colour.r, max(colour.g, colour.b));
	vec3 hue = peak > 1.0e-4 ? colour / peak : vec3(0.0);

	float encoded = log2(max(level, 0.0) + 1.0) / LIGHT_VOLUME_LEVEL_RANGE;

	return vec4(hue, clamp(encoded, 0.0, 1.0));
}

// The previous frame's field at a voxel, or black outside the grid.
//
// Out of range reads as black rather than as a clamped sample: the grid is a cube
// cut out of the world, so a read that falls off the edge is a position the
// previous field has nothing to say about, and folding the border voxels back in
// would make the edge of the cube a wall of light that the fill then carries
// inwards. Which image to read is fromA, passed in, so that the parity is still
// decided in one place.
vec4 LightVolumePreviousField(ivec3 pos, bool fromA) {
	if (any(lessThan(pos, ivec3(0)))
		|| any(greaterThanEqual(pos, ivec3(LIGHT_VOLUME_SIZE)))) {
		return vec4(0.0);
	}

	return LightVolumeDecode(fromA
		? imageLoad(light_volume_a, pos)
		: imageLoad(light_volume_b, pos));
}

// What the world image says about a voxel: the material ID and the tint.
//
// The tint is white for everything that is not a stained pane, which is the value
// that leaves light unchanged when it is multiplied in. A pane stores its own
// texture colour, normalised to its brightest channel by the fragment stage that
// writes it, so a red pane puts red light on the floor and a black one puts
// almost none.
vec4 LightVolumeWorldAt(ivec3 voxel) {
	vec4 stored = imageLoad(light_volume_world, voxel);

	// The ID back out of the eight-bit channel. The round trip is exact for every
	// integer the writer can store, so this is a decode and not an estimate.
	uint id = uint(stored.r * 255.0 + 0.5);

	return vec4(stored.gba, float(id));
}
#endif

void main() {
#ifdef IS_IRIS
	// One invocation per voxel. The dispatch is exactly the grid, but the bound is
	// kept because a write past the last voxel is undefined rather than ignored,
	// and because the bound is what the formula means: outside the grid there is
	// no voxel of the fill to advance.
	ivec3 voxel = ivec3(gl_GlobalInvocationID);

	if (any(greaterThanEqual(voxel, ivec3(LIGHT_VOLUME_SIZE)))) {
		return;
	}

	// The ping-pong: even frames write the first field and read the second, odd
	// frames the reverse. The consumer derives its side from the same number the
	// same way (see light_volume.glsl, and Eclipse's own pair -
	// dimensions/shadowcomp.csh:169-172 and lib/lpv_render.glsl:16). The two must
	// agree or the field flickers between two images, a failure a still screenshot
	// cannot show.
	bool writeToA = (frameCounter % 2) == 0;

	// The grid is snapped to whole blocks, so the camera moving within a block
	// does not move it, and a frame in which the camera crosses a block boundary
	// moves it by a whole block. A world position that is voxel p in this frame's
	// grid was voxel p + shift in the grid the previous field was written in -
	// that shift is the whole of the re-anchoring, and it is what keeps the fill
	// attached to the world instead of to the screen.
	//
	// The frame before's camera position, which is a standard uniform both frames
	// agree on. Within one dispatch, one invocation's imageStore is not ordered
	// against another invocation's imageLoad, so a value published through an
	// image and read back in the same dispatch would be a race; there is nothing
	// to publish here, because the shift is derived from the two camera positions
	// the loader supplies.
	ivec3 shift = ivec3(floor(cameraPosition) - floor(previousCameraPosition));

	// This frame's world image at this voxel: the block's ID and its tint.
	vec4 world = LightVolumeWorldAt(voxel);
	uint blockId = uint(world.a + 0.5);
	vec3 tint = world.rgb;

	// How much of the level survives this voxel. One for everything that is not a
	// filter: a non-filter leaves light alone, and the step at the spread below is
	// the only thing that shortens the reach.
	float tintLevel = 1.0;

	// The block's own light, from the palette. A block that is not a source
	// answers black and a range of zero, and then the two branches below are the
	// air branch and nothing else.
	vec3 emitted = BlockLightColor(blockId);
	float emittedRange = BlockLightRange(blockId);

	// What the block does to light crossing it. A wall stops it, a filter tints
	// it, and everything else leaves it alone - see LightVolumeOpaque and
	// LightVolumeFilters in light_volume.glsl for why those are questions about
	// the block rather than states of the image.
	bool opaque = LightVolumeOpaque(blockId);

	if (!LightVolumeFilters(blockId)) {
		// The tint in the image is only meaningful for a filter. Everything else
		// leaves light unchanged, whatever the image happens to hold - which is
		// what keeps a stale tint from a pane that has since been broken from
		// colouring the air it used to stand in.
		tint = vec3(1.0);
	} else if (blockId == STAINED_GLASS) {
		// BATCH 746: A PANE TINTS THE COLOUR AND LEAVES THE LEVEL ALONE.
		//
		// Batch 745 split the pane's stored colour into a hue and a peak, tinted
		// with the hue and shortened the reach by the peak. The author saw the
		// result and described it exactly: the coloured light came out as TWO
		// PATCHES.
		//
		// A pane is one voxel thick, so the peak multiplied the level once - but
		// once is a step. Light arrives at the pane at level L and leaves at
		// L * peak, so there is a discontinuity at the pane's own voxel: a bright
		// patch on the near side, a dimmer one beyond, and a visible edge between
		// them. Eclipse never does this; it multiplies the tint into the COLOUR and
		// leaves the level alone (dimensions/shadowcomp.csh:150-154:
		// `lightMixed.rgb *= tintColor`), so its falloff stays continuous.
		//
		// The colour is normalised by the writer again (see program/shadow/shadow.fsh),
		// so what arrives here is a hue at full strength and there is nothing to
		// split. The cost is recorded there rather than hidden: a pane whose
		// brightest channel is low normalises towards white and tints very little.
		tint = max(tint, vec3(0.0));
	} else {
		// The constant tints - foliage and the three non-cube shapes. These are
		// Eclipse's mixWeight, and they go to the LEVEL rather than to the colour.
		//
		// BATCH 745 MOVED THEM, AND THAT IS A FIX RATHER THAN A REFINEMENT. Batch
		// 744 multiplied them into the colour, which was a no-op: the encode
		// normalises the colour to its brightest channel, so a uniform scalar is
		// divided straight back out and the block passed light at full strength.
		// The level is the only channel that can carry "less light got through".
		// See LightVolumeFilterTint. The function returns a colour so that a filter
		// with a hue could use it; every constant it returns today is grey, so the
		// red channel is the scalar.
		tintLevel *= LightVolumeFilterTint(blockId).r;
	}

	// The neighbours, one step down, and the two ways they are combined.
	//
	// The level is the maximum: light travels in straight lines and the strongest
	// neighbour is the one it came from, which is the shape batch 702 shipped and
	// the author confirmed. The colour is a level-weighted average of the same
	// neighbours, which is the part the old fill got wrong - it took a per-channel
	// maximum, so two colours meeting head-on came out as the brighter of each
	// channel rather than as a blend. Weighting by the level means the blend is
	// dominated by whichever light is actually stronger there, which is what the
	// eye expects and what a plain average would lose.
	//
	// A solid block is not a special case here: it is a block whose tint is black,
	// so the light that crosses it is multiplied to nothing. That is Eclipse's
	// arrangement (dimensions/setup.csh:1214, where mixWeight becomes the tint) and
	// it is why this pass has no state table to keep in step with the writer.
	ivec3 previous = voxel + shift;
	bool readFromA = !writeToA;

	float level = 0.0;
	vec3 colourSum = vec3(0.0);
	float weightSum = 0.0;

	// The six neighbours, in the order LIGHT_VOLUME_FACE_* names them. Written out
	// rather than looped because the offsets are constants and a loop over an
	// array of ivec3 is the kind of thing a driver may or may not unroll.
	vec4 n;

	n = LightVolumePreviousField(previous + ivec3(1, 0, 0), readFromA);
	level = max(level, n.a);
	colourSum += n.rgb * n.a;
	weightSum += n.a;

	n = LightVolumePreviousField(previous + ivec3(-1, 0, 0), readFromA);
	level = max(level, n.a);
	colourSum += n.rgb * n.a;
	weightSum += n.a;

	n = LightVolumePreviousField(previous + ivec3(0, 1, 0), readFromA);
	level = max(level, n.a);
	colourSum += n.rgb * n.a;
	weightSum += n.a;

	n = LightVolumePreviousField(previous + ivec3(0, -1, 0), readFromA);
	level = max(level, n.a);
	colourSum += n.rgb * n.a;
	weightSum += n.a;

	n = LightVolumePreviousField(previous + ivec3(0, 0, 1), readFromA);
	level = max(level, n.a);
	colourSum += n.rgb * n.a;
	weightSum += n.a;

	n = LightVolumePreviousField(previous + ivec3(0, 0, -1), readFromA);
	level = max(level, n.a);
	colourSum += n.rgb * n.a;
	weightSum += n.a;

	// The spread: one step of the falloff, and the tint of the block the light is
	// crossing.
	//
	// BATCH 745 SPLIT THE IMAGE TINT INTO A HUE AND A PEAK. Until this batch the
	// writer normalised a pane's colour to its brightest channel before storing it,
	// so the image only ever carried the hue - and a black pane arrived as pure
	// white, tinted nothing and passed light at full strength. Measured on the
	// vanilla textures: black stained glass is linear 0.0097 and grey is 0.0723, and
	// both normalise to (1, 1, 1). That is the author's second report.
	//
	// The writer now stores the pane's colour raw, and this is where the two halves
	// are separated:
	//
	//   * the HUE (colour / peak) tints the light, which is the part the old code
	//     was after and the part that makes a red pane put red light on the floor;
	//   * the PEAK shortens the reach, which is the part that was missing. A pane
	//     that transmits a tenth of the light should not let a torch reach as far as
	//     it would through air.
	//
	// The peak goes to the LEVEL because the colour is normalised by the encode
	// below and a magnitude put there is discarded - the level is the only channel
	// that can carry "less light got through". This is Eclipse's shape: it multiplies
	// its tint into the colour and its encoding keeps the magnitude in the V channel
	// (dimensions/shadowcomp.csh:150-154, 163-166), which is the same quantity this
	// pack keeps in alpha.
	//
	// A pale pane has a peak of one and is unchanged, which is the property the old
	// normalisation was protecting; a black pane has a peak near zero and now stops
	// the light, which is what black glass does.
	//
	// The falloff itself is additive - one level per voxel - for the reason written
	// out at LIGHT_VOLUME_STEP: this pack's consumer compares the field against the
	// game's own block light level, which drops by one per block, so a
	// multiplicative decay would give a torch thirty-three blocks of reach where the
	// game says fourteen. The pane's peak is a separate factor applied on top of
	// that step, not instead of it.
	vec3 spreadColour = weightSum > 1.0e-4 ? colourSum / weightSum : vec3(0.0);
	float spreadLevel = max(level - LIGHT_VOLUME_STEP, 0.0);

	spreadColour *= tint;
	spreadLevel *= tintLevel;

	// The voxel's own light, if it is a source. A source is at full strength in
	// the frame it is drawn rather than one step away from where it is, which is
	// what makes a torch's own block read as its brightest point.
	//
	// The two are combined by maximum rather than by addition: the level is a
	// number of blocks of reach, and adding two of them would let a source and its
	// own spread sum to a level neither of them has. The colour follows whichever
	// of the two carries the level, so a source's own colour wins in its own voxel
	// and the incoming light's colour wins just outside it.
	vec3 nextColour;
	float nextLevel;

	if (emittedRange > spreadLevel) {
		nextColour = emitted;
		nextLevel = emittedRange;
	} else {
		nextColour = spreadColour;
		nextLevel = spreadLevel;
	}

	// A block whose tint is black stops the light: nothing crosses it and nothing
	// leaves it. This is the "solid" state of the old encoding, expressed as a
	// question about the block rather than as a tag in the image - see
	// LightVolumeOpaque in light_volume.glsl.
	if (opaque) {
		nextColour = vec3(0.0);
		nextLevel = 0.0;
	}

	vec4 stored = LightVolumeEncode(nextColour, nextLevel);

	if (writeToA) {
		imageStore(light_volume_a, voxel, stored);
	} else {
		imageStore(light_volume_b, voxel, stored);
	}

#endif
}
