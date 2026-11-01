// Colored block light: one step of the flood fill.
//
// Included by the three prepare3 entries - prepare3.csh at the root and the two
// under world-1/ and world1/ - which supply the #version line and the note on where
// this pass sits in the frame. What runs here is the shading half's other end, from
// /environment/lighting/light_volume.glsl: every voxel of the grid takes the
// brightest of its six neighbours out of the previous frame's field, one step
// down, and then whatever light source stands in the voxel itself.
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
// behind IS_IRIS: on a loader without custom images the body does nothing and the
// ready flag the shading side reads never rises, which is what leaves block light
// the colour it has always had. Nor does it run at all when COLORED_LIGHTS is
// off - see program.prepare3.enabled in shaders.properties - because with the
// option off nothing reads the field.

// The shared constants, and the one definition of where a position sits in the
// grid. The file has no simulation-only section at this version, so this is the
// same source the terrain programs include: the grid's geometry, the decay and
// the voxel index the shadow pass writes with all come from one place, and the
// three ends of the feature cannot drift apart.
//
// The samplers it declares for the shading half are harmless here - nothing in
// this program samples them, and the uniforms this pass owns are declared below
// rather than there, for the reason sim.glsl gives for the same arrangement in
// the water simulation: they exist only for the compute pass and have no business
// in the comparison the terrain programs are checked against.
#include "/environment/lighting/light_volume.glsl"

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;

// 8 invocations per axis and 8 groups per axis: the 64-voxel grid in one
// dispatch, one invocation per voxel.
//
// A shader constant rather than a line in shaders.properties, which is how this
// pack declares work groups (see program/water_interaction/step_a.csh). The count
// follows from the algorithm - one invocation per voxel - and has no quality
// level to expose: a smaller grid would be a shorter reach for the colour, not a
// cheaper version of the same picture.
const ivec3 workGroups = ivec3(8, 8, 8);

#ifdef IS_IRIS
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;
uniform int frameCounter;

// What the shadow pass wrote this frame: rgb is the colour of a light source in
// the voxel, alpha is 1.0 for a voxel that blocks light (see
// program/shadow/shadow.vsh for which material writes which).
//
// This is the one image of the four that the loader clears every frame, and it
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

// Where the grid is this frame and which field is current, for the terrain
// programs: texel (0, 0) is (floor(cameraPosition), ready) and texel (1, 0) is
// (fract(cameraPosition), currentIsB).
//
// Written here and read there, and never cleared - it is how the shading side
// samples the right field without deciding the parity for itself, which is the
// rule that keeps the parity decided in one place in the whole pack. rgba32
// because it holds a world position: a half float would round the anchor to whole
// blocks over a few tens of thousands of blocks from the origin, which is exactly
// where a shader still has to be right.
layout(rgba32f) uniform image2D light_volume_info;

// The previous frame's field at a voxel, or black outside the grid.
//
// Out of range reads as black rather than as a clamped sample: the grid is a cube
// cut out of the world, so a read that falls off the edge is a position the
// previous field has nothing to say about, and folding the border voxels back in
// would make the edge of the cube a wall of light that the fill then carries
// inwards. Which image to read is fromA, passed in, so that the parity is still
// decided in one place.
vec3 LightVolumePreviousField(ivec3 pos, bool fromA) {
	if (any(lessThan(pos, ivec3(0)))
		|| any(greaterThanEqual(pos, ivec3(LIGHT_VOLUME_SIZE)))) {
		return vec3(0.0);
	}

	return fromA
		? imageLoad(light_volume_a, pos).rgb
		: imageLoad(light_volume_b, pos).rgb;
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

	// The ping-pong, and the only place in the pack where it is decided: the store
	// below takes its side from this, and the terrain programs read the same
	// answer back out of light_volume_info rather than counting frames of their
	// own. Nothing else may ask about the frame count, or the two sides could
	// disagree about which field is the current one for one frame.
	bool writeToA = (frameCounter % 2) == 0;

	// The grid is snapped to whole blocks, so the camera moving within a block
	// does not move it, and a frame in which the camera crosses a block boundary
	// moves it by a whole block. A world position that is voxel p in this frame's
	// grid was voxel p + shift in the grid the previous field was written in -
	// that shift is the whole of the re-anchoring, and it is what keeps the fill
	// attached to the world instead of to the screen.
	//
	// previousCameraPosition and not the anchor published in light_volume_info:
	// within one dispatch, one invocation's imageStore is not ordered against
	// another invocation's imageLoad, so a thread reading the texel the thread at
	// voxel zero is about to write would be reading a race, not a value. The water
	// simulation publishes its grid through an image instead because it has two
	// dispatches to get the value across; this pass has one, and a standard
	// uniform is the value both frames agree on.
	ivec3 shift = ivec3(floor(cameraPosition) - floor(previousCameraPosition));

	// This frame's world image at this voxel. alpha says the voxel is solid, rgb
	// says what colour of light the block in it emits, if any.
	vec4 world = imageLoad(light_volume_world, voxel);

	// A solid voxel is black and stays black: light does not enter a block and
	// does not come out of one. Everything else takes the brightest of the six
	// neighbours from the frame before, one step down, and then the emitter that
	// stands in the voxel itself - a light source is full strength in the frame it
	// is drawn, not one step away from where it is.
	vec3 next = vec3(0.0);

	if (world.a <= 0.5) {
		ivec3 previous = voxel + shift;
		bool readFromA = !writeToA;

		vec3 spread = LightVolumePreviousField(previous + ivec3(1, 0, 0), readFromA);
		spread = max(spread, LightVolumePreviousField(previous + ivec3(-1, 0, 0), readFromA));
		spread = max(spread, LightVolumePreviousField(previous + ivec3(0, 1, 0), readFromA));
		spread = max(spread, LightVolumePreviousField(previous + ivec3(0, -1, 0), readFromA));
		spread = max(spread, LightVolumePreviousField(previous + ivec3(0, 0, 1), readFromA));
		spread = max(spread, LightVolumePreviousField(previous + ivec3(0, 0, -1), readFromA));

		// A maximum per channel, not a sum and not last-writer-wins: two colours
		// that meet in a voxel come out as the brighter of each channel, which is
		// what makes a red light beside a green one read as yellow where they
		// overlap. The decay alone decides how far a colour reaches, so a voxel
		// that has never been near a source stays black without a cutoff of its
		// own.
		next = max(spread * LIGHT_VOLUME_STEP, world.rgb);
	}

	// The fourth channel is stored as 1.0 because there is nothing to put in it:
	// the colour is the whole of the state this image carries, and the flag the
	// shading side needs - has the pass ever run - lives in light_volume_info, not
	// here. It is written rather than left undefined so that a texel has one
	// meaning on every driver.
	if (writeToA) {
		imageStore(light_volume_a, voxel, vec4(next, 1.0));
	} else {
		imageStore(light_volume_b, voxel, vec4(next, 1.0));
	}

	// Publish the grid and the parity for the shading side, once per dispatch.
	// The thread at the grid's corner does it because exactly one writer is what
	// this needs - there is nothing to combine, and every thread would store the
	// same two texels.
	//
	// The first texel's alpha is the ready flag: it is 1.0 from the first time this
	// pass runs, and it is what the shading side tests before it samples a field.
	// On a loader where the images or this program do not exist it stays zero, and
	// every surface keeps the block light colour it had before any of this
	// existed. The second texel's alpha is the parity in the form the shading side
	// wants it: 1.0 means the current field is light_volume_b.
	if (all(equal(voxel, ivec3(0)))) {
		imageStore(light_volume_info, ivec2(0, 0),
			vec4(floor(cameraPosition), 1.0));
		imageStore(light_volume_info, ivec2(1, 0),
			vec4(fract(cameraPosition), writeToA ? 0.0 : 1.0));
	}
#endif
}
