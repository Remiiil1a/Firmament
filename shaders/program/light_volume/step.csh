// Colored block light: one step of the flood fill.
//
// Included by the three shadowcomp entries - shadowcomp.csh at the root and the two
// under world-1/ and world1/ - which supply the #version line and the note on where
// this pass sits in the frame. What runs here is the shading half's other end, from
// /environment/lighting/light_volume.glsl: every voxel of the grid blends the
// neighbours that carry colour in the previous frame's field, one step down, and
// then adds whatever state its own voxel of the world image is in - air, an
// emitter, stained glass, or an opaque block. The four states and their encoding
// are the table at the top of that file; this is the only place they are read.
//
// One step per frame, not a loop that converges inside one dispatch. The field is
// a recurrence, not something solved: it arrives at the frame as an image,
// advances by one voxel, and is stored again. Spreading and fading are not
// symmetric: a source is full strength in its own voxel in the frame it appears and
// takes fifteen frames to reach fifteen blocks, while a removed one decays by the
// step every frame and is only gone once it is below LIGHT_VOLUME_MINIMUM - 0.85^15
// is still 0.087, so that is twenty-five frames rather than fifteen. See
// LIGHT_VOLUME_STEP for why fifteen blocks is the distance it has to reach at all;
// advance it faster and the colour would run ahead of the lightmap that is supposed
// to be deciding brightness.
//
// The program is Iris only, and every part of it that touches an image is kept
// behind IS_IRIS: on a loader without custom images the body does nothing, the
// images are never written, the field samples as black, and block light stays the
// colour it has always had. Nor does it run at all when COLORED_LIGHTS is off -
// see program.shadowcomp.enabled in shaders.properties - because with the option
// off nothing reads the field.

// The shared constants, and the one definition of where a position sits in the
// grid. The file has no simulation-only section at this version, so this is the
// same source the terrain programs include: the grid's geometry, the decay and
// the voxel index the shadow pass writes with all come from one place, and the
// three ends of the feature cannot drift apart.
//
// The consumer-side samplers and functions in that file are compiled out here,
// because this program does not define LIGHT_VOLUME_CONSUMER; what this pass
// needs from the shared file is the grid, the decay and frameCounter. Its own
// images are declared below, for the reason sim.glsl gives for the same
// arrangement in the water simulation: they exist only for the compute pass and
// have no business in the comparison the terrain programs are checked against.
#include "/environment/lighting/light_volume.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

// 8 invocations per axis and 16 groups per axis: the whole 128-cubed grid in one
// dispatch, one invocation per voxel. That is 2,097,152 invocations a frame, and it
// is the same number at every setting of COLORED_LIGHT_RANGE - the option limits
// how much of the grid is used, not what the dispatch costs.
//
// A shader constant rather than a line in shaders.properties, which is how this
// pack declares work groups (see program/water_interaction/step_a.csh). The grid
// is a fixed 128 cubed - the images are declared at that size unconditionally in
// shaders.properties - so the count is written out rather than derived from an
// option: 16 groups of 8 invocations is exactly the grid, and a build-time
// constant is what the loader requires of it.
const ivec3 workGroups = ivec3(16, 16, 16);

#ifdef IS_IRIS
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
// frameCounter is declared by light_volume.glsl above, shared with the consumer.

// What the shadow pass wrote this frame: the four-state table at the top of
// environment/lighting/light_volume.glsl is what rgb and alpha mean here. It is
// written by two programs - the vertex stage (program/shadow/shadow.vsh) for the
// geometry, and the fragment stage (program/shadow/shadow.fsh) for the tint of
// stained glass, which only the fragment stage can read from the texture.
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
// which decays by the step above below LIGHT_VOLUME_MINIMUM within the same
// twenty-five frames a light takes to fade out.
layout(rgba16) uniform image3D light_volume_a;
layout(rgba16) uniform image3D light_volume_b;


// The previous frame's field at a voxel, or black outside the grid.
//
// Out of range reads as black rather than as a clamped sample: the grid is a cube
// cut out of the world, so a read that falls off the edge is a position the
// previous field has nothing to say about, and folding the border voxels back in
// would make the edge of the cube a wall of light that the fill then carries
// inwards. Which image to read is fromA, passed in, so that the parity is still
// decided in one place.
//
// rgb is the field's colour and a is 1.0 when this neighbour carries any colour at
// all, 0.0 when it is black. The blend below divides by that count, so it has to
// come from the same read as the colour.
vec4 LightVolumePreviousField(ivec3 pos, bool fromA) {
	if (any(lessThan(pos, ivec3(0)))
		|| any(greaterThanEqual(pos, ivec3(LIGHT_VOLUME_SIZE)))) {
		return vec4(0.0);
	}

	vec3 colour = fromA
		? imageLoad(light_volume_a, pos).rgb
		: imageLoad(light_volume_b, pos).rgb;

	return vec4(colour, max(colour.r, max(colour.g, colour.b)) > 0.0 ? 1.0 : 0.0);
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

	// This frame's world image at this voxel: the four-state table at the top of
	// light_volume.glsl is what rgb and alpha mean here. alpha is the state, and
	// it is tested in the order the table gives - solid first, then filter,
	// because a solid is the one state that must not even read its neighbours.
	vec4 world = imageLoad(light_volume_world, voxel);

	// A solid voxel is black and stays black: light does not enter a block and
	// does not come out of one. Everything else blends the six neighbours from
	// the frame before, one step down, and then adds what its own state does.
	vec3 next = vec3(0.0);

	if (world.a > 0.75) {
		// Solid. `next` stays black - not even a read of the neighbours, which
		// would be six image loads to compute a value that is then thrown away.
		next = vec3(0.0);
	} else {
		ivec3 previous = voxel + shift;
		bool readFromA = !writeToA;

		vec3 spread = LightVolumePreviousField(
			previous + ivec3(1, 0, 0), readFromA).rgb;
		spread = max(spread, LightVolumePreviousField(
			previous + ivec3(-1, 0, 0), readFromA).rgb);
		spread = max(spread, LightVolumePreviousField(
			previous + ivec3(0, 1, 0), readFromA).rgb);
		spread = max(spread, LightVolumePreviousField(
			previous + ivec3(0, -1, 0), readFromA).rgb);
		spread = max(spread, LightVolumePreviousField(
			previous + ivec3(0, 0, 1), readFromA).rgb);
		spread = max(spread, LightVolumePreviousField(
			previous + ivec3(0, 0, -1), readFromA).rgb);

		// Per-channel maximum, which is what this batch went back to. Batch
		// 703 replaced it with the mean of the contributing neighbours to make
		// two colours mix; the author tested it and reported that it broke the
		// effect - the falloff flattened out and a lit area read as one broad
		// wash instead of a cone around its source. The reasoning that made the
		// mean look safe was wrong somewhere, and rather than keep tuning it
		// blind, the maximum is back: it is the shape the pack shipped in 702
		// and the one the author confirmed.
		//
		// What that costs is mixing: two colours meeting head-on come out as
		// the brighter of each channel rather than an average. Where that
		// matters it is a real limitation, and the place to solve it is a
		// proper energy-preserving blend, not the denominator.
		//
		// A filter is stained glass, and it is the one state that changes the
		// light rather than adding to it: what crosses a pane takes the pane's
		// colour, so the value from the neighbours is multiplied by the tint
		// before it is stored. There is deliberately no self-injection here - a
		// pane is not a source, and adding its own rgb would make the pane
		// itself glow. Air and emitters are everything else, and they differ
		// only in whether the voxel adds its own colour: an emitter is at full
		// strength in the frame it is drawn, not one step away from where it is.

		if (world.a > 0.25) {
			next = spread * world.rgb * LIGHT_VOLUME_STEP;
		} else {
			next = max(spread * LIGHT_VOLUME_STEP, world.rgb);
		}
	}

	// The option's radius, and the extent mask that makes it real: a voxel further
	// than the active radius from the centre of the fixed grid stores black. The
	// field is a 128-cubed image whatever the option says, and the option only
	// decides how much of it the fill may use. The consumer fades the colour out
	// towards the same radius, so the edge of what is used is a fade and not a
	// cut.
	//
	// Chebyshev distance and not Euclidean: the grid is a cube and the mask has to
	// cut it to a cube, so the farthest axis decides.
	ivec3 fromCentre = abs(voxel - ivec3(LIGHT_VOLUME_GRID_RADIUS));

	if (max(fromCentre.x, max(fromCentre.y, fromCentre.z))
		> LIGHT_VOLUME_ACTIVE_RADIUS) {
		next = vec3(0.0);
	}



	// The fourth channel is stored as 1.0 because there is nothing to put in it:
	// the colour is the whole of the state this image carries. It is written
	// rather than left undefined so that a texel has one meaning on every driver.
	if (writeToA) {
		imageStore(light_volume_a, voxel, vec4(next, 1.0));
	} else {
		imageStore(light_volume_b, voxel, vec4(next, 1.0));
	}

#endif
}
