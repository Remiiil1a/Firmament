// Coloured block light, by flood fill, in Eclipse's shape.
//
// Minecraft's light engine carries a brightness and nothing else: every light
// source in the world arrives as the same warm average, so a soul lantern and a
// torch light a wall identically. This file is the other half of the fix - a
// second flood fill over a grid of voxels around the player that carries colour
// and a range of its own. Each frame one step of it runs in the shadowcomp pass,
// light spreads one voxel per step, and the terrain programs read the field back
// as the block light itself.
//
// BATCH 739 REWROTE THIS FROM ECLIPSE'S LPV, AND THE REWRITE IS THE POINT.
// Batches 696 to 738 built a fill that carried a colour and nothing else: the
// field's magnitude was a distance weight, the colour was normalised and then
// multiplied back up to whatever brightness the lightmap had already decided, and
// the lightmap's own pow(blockLight, 4) stayed the only thing that set how bright
// a surface was. That is not what the reference does, and it is why the effect
// read as a tint rather than as light. Eclipse's LPV carries a light level: a
// source enters the field at its own range, the field decays by a fixed factor
// per voxel, and the shading side uses the field's own magnitude as the block
// light. The author asked for that shape, not for a patch on the old one.
//
// What is taken from Eclipse (Eclipse-Shader-Unstable/shaders):
//
//  * the encoding. The field is stored logarithmically - hue and saturation in
//    rgb, log2(level + 1) / range in alpha - so that eight bits per channel cover
//    a range of fifteen with usable resolution near the source. See the encoding
//    section below; this is the "our field is not logarithmic" the author named.
//  * the propagation. Six neighbours, each masked by the block it stands in, each
//    weighted by a per-block mix weight, averaged and multiplied by one falloff
//    constant. Not a per-channel maximum, which is what the old fill did and what
//    made two colours meeting head-on come out as the brighter of each channel.
//  * the per-source range. A source's reach is its own light level, not one
//    constant for every block in the game, and the range is carried in the same
//    logarithmic channel as the field so that a fifteen-block source and a
//    three-block one can be stored side by side.
//  * the world image. One voxel per block holding the block's own ID, written by
//    the shadow pass, and a per-ID table of light colour, range, tint and mix mask
//    built once per frame by a setup pass. The old fill had five states and a
//    hardcoded palette; this one has a table, which is what lets a stained pane
//    tint the light and a slab pass it in five directions instead of six.
//
// What is deliberately NOT taken: Eclipse's photonics stage, its voxel
// reflections, its handheld light and its sky light channel. Those are separate
// features that happen to share the grid; this pack has its own answers for the
// first two and does not want the third. The field here carries block light only.
//
// Iris only, for the same reason the water simulation is: custom images and
// compute shaders. On a loader without them the images are not there, the
// samplers read zero, the field samples as black, and every program that includes
// this file draws exactly what it drew before the file existed.

#ifndef INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME
#define INCLUDE_ENVIRONMENT_LIGHTING_LIGHT_VOLUME

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
// genuinely black are the same picture, and both mean "no colour here", which is
// exactly what the consumer falls back on.
//
// WORLD shows what the writer put in the world image at this fragment's voxel:
// the block's ID as a grey level, with the states this pack tags called out in
// their own colours. Read together: a black FIELD over a non-black WORLD means
// the writer works and the propagation is the fault; a black WORLD means nothing
// is being written at all, and the other two layers are not worth looking at
// first. The one case the two cannot separate is a loader that cannot allocate
// the images at all: then both views are black, which is the same picture as an
// empty volume.
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
// only file the propagation pass, the setup pass and the terrain programs all
// include: a declaration in either end's own files could be visible to one and
// not the other, and then the two would disagree about the grid - which is the
// kind of disagreement that compiles everywhere.
//
// COLORED_LIGHT_RANGE is the side, in blocks, of the cube the colour lives in:
// 32, 48, 64, 96 or 128. It sizes the grid itself - the three images, the number
// of voxels the propagation advances each frame and the number of invocations its
// dispatch runs - so it is the option that buys performance, not only a fade. The
// side of a cube rather than a radius because that is the number the images and the
// dispatch are counted in, and because the memory is the cube of it; half of this
// value is how far from the player the colour can actually reach.
//
// The cost of each setting, for the whole feature. One voxel is one invocation a
// frame, and the three images are RGBA16 - the logarithmic encoding is what the
// field carries, but it did not make eight bits enough; see the encoding section
// below for the measurement that settled it.
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
// turned back into light in LightVolumeBlockLight below. 1.0 is the colour the
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

///////////////////////////////////////////////////////////////////////////////
//   The encoding
///////////////////////////////////////////////////////////////////////////////

// The field is stored logarithmically, and this is the section the author's
// "our field is not logarithmic" is about.
//
// A voxel of the field is four channels. rgb is the light's colour as hue and
// saturation - the value is normalised so that its brightest channel is one
// before it is stored, so rgb carries the direction of the colour and nothing
// about its strength. Alpha carries the strength, as
//
//     a = log2(level + 1) / LIGHT_VOLUME_LEVEL_RANGE
//
// where level is the light level in blocks of reach. The inverse is
//
//     level = exp2(a * LIGHT_VOLUME_LEVEL_RANGE) - 1
//
// and both live in this file so that the writer, the propagation and the shading
// side cannot disagree about them.
//
// WHY LOGARITHMIC, AND WHY SIXTEEN BITS RATHER THAN EIGHT. The logarithm is the
// author's requirement and it is the right shape: the propagation subtracts one
// level per voxel, and in the stored space that becomes a subtraction of a
// constant, so the quantisation error does not compound the way it does when a
// linear value is multiplied by a falloff every frame. It also puts the same
// number of steps between every doubling of the level, so the resolution is
// finest where the light is brightest.
//
// What the logarithm does NOT do is make eight bits enough, and this is worth
// recording because it is the opposite of what the reference implies. Eclipse
// stores its field in RGBA8 (shaders.properties:1038) and gets away with it
// because its consumer treats the field as a brightness and mixes it in directly;
// a step of 1/255 in the stored value is a step of about 1/255 in the output.
// This pack's consumer treats the field as a LIGHT LEVEL and raises it to the
// fourth power (pow(level / 15, 4), the envelope BlockLighting has always used),
// which multiplies every error near the top of the range by four and then by the
// level itself. Measured over levels 0 to 15 against that envelope, the worst
// error in the final brightness is:
//
//     logarithmic,  8 bits   0.0776   <- visible banding in a lit room
//     logarithmic, 16 bits   0.0003
//     linear,       8 bits   0.0071
//     linear,      16 bits   0.00003  <- what this pack shipped before batch 739
//
// So eight bits is worse than the linear encoding it would replace, and the
// logarithmic form only pays off at sixteen. The field stays RGBA16, the encoding
// becomes logarithmic, and the memory does not change. The probe
// _team_bfog/light_field_739.py asserts these numbers rather than trusting this
// comment.
//
// The range is fifteen because that is the game's own block light span: a torch
// is level 14, glowstone 15, and nothing in the game reaches further. A source
// with a shorter reach - a magma block at 3, an amethyst bud at 5 - stores a
// smaller level in the same channel and simply runs out sooner.
#define LIGHT_VOLUME_LEVEL_RANGE 15.0

// How much of a voxel's level survives one step of the fill.
//
// ADDITIVE, one level per voxel, and that is a deliberate departure from Eclipse.
// Eclipse multiplies by 0.96 per step (dimensions/shadowcomp.csh:17), which is the
// right shape for its own consumer: it treats the field as a brightness and mixes
// it straight into the light, so a geometric falloff is what it wants.
//
// This pack's consumer treats the field as a LIGHT LEVEL - it is compared against,
// and mixed with, the game's own block light level, which is an integer that drops
// by one per block. A multiplicative falloff does not produce that number. Measured
// against this pack's own envelope (pow(level / 15, 4), the one BlockLighting has
// always used), 0.96 per step gives a torch 33 blocks of visible reach where the
// game says 14, and a magma block 0 blocks where the game says 3 - the curve is
// wrong at both ends at once. One level per voxel gives 15, 14, 10, 7 and 3 for
// glowstone, torch, soul torch, redstone torch and magma block, which is exactly
// what the game's own light engine says, because it is the same rule.
//
// The consequence worth stating: where the fill sees the same world the lightmap
// sees, the two agree, and the mix in the consumer is a no-op in brightness and
// only changes colour. That is the safe direction - the fill cannot make a room
// brighter than the game says it is, only a different colour - and it is what
// makes "a source reaches as far as its own level" true rather than approximate.
#define LIGHT_VOLUME_STEP 1.0

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

// How far inside the grid the fade starts, in blocks, for the consumer's own
// edge test. Eclipse measures this in metres from the boundary rather than as a
// fraction of the radius (lib/diffuse_lighting.glsl:131), and the reason is worth
// keeping: the fade is about the boundary, so its width should not change when
// the grid does. Ten metres is Eclipse's value and it is a tenth of the largest
// grid, which is the proportion that keeps the fade invisible at every setting.
#define LIGHT_VOLUME_EDGE_FADE_LENGTH 10.0

///////////////////////////////////////////////////////////////////////////////
//   What a block does to light
///////////////////////////////////////////////////////////////////////////////

// The world image holds a block's material ID, and these two functions say what
// an ID means to the fill.
//
// WHY FUNCTIONS AND NOT A TABLE IMAGE. Eclipse builds a 2048-entry table in a
// setup pass and reads it from the propagation (dimensions/setup.csh, and
// lib/lpv_blocks.glsl for the image). That is the right shape for Eclipse, which
// has to answer for several hundred block IDs and needs the mix mask that lets a
// slab pass light in five directions rather than six. This pack does not: its
// material list is 47 IDs long, it has no partial-shape materials at all - no
// slab, stair, wall, trapdoor or carpet is given an ID in block.properties - so a
// six-bit face mask would have nothing to act on, and a table image would cost a
// program, an image and a dispatch to answer a question a switch answers for free.
//
// What is taken from Eclipse's table is the part that matters: the answer is a
// property of the block rather than a state of the image. The old encoding had
// five states in the world image's alpha channel and a palette compiled into the
// shader; a block could be air, an emitter, water, a filter or solid, and that was
// the whole vocabulary. Here the image carries the block and these functions say
// what it does - which is what lets a source have its own reach, and what removed
// the special case that stained glass needed in the propagation.
//
// The two questions, and the reason they are separate:
//
//  * LightVolumeTint answers what the block does to light crossing it. White
//    leaves it alone, black stops it, and a stained pane's own colour tints it.
//    The pane's colour is not known here - it comes from the pane's texture, which
//    only the shadow program's fragment stage can read - so the image carries it
//    and this function only says whether the block is a filter at all.
//  * LightVolumeEmits answers whether the block is a source. Its colour and reach
//    are BlockLightColor and BlockLightRange in light_colors.glsl, which is the
//    one place a family is written down.
//
// Both are compiled into the propagation and into the writer, and neither is
// compiled into the terrain programs: the consumer half below reads the field,
// which already has the answers baked into it.

// Whether a block stops light.
//
// BATCH 744 REWROTE THIS, AND THE OLD FIRST BRANCH WAS THE BUG. It read
//
//     if (materialID == GENERIC) { return false; }
//
// with a comment arguing that treating GENERIC as a wall "would make most of the
// world a wall to the fill", because the pack's material list is short and stone,
// planks and bricks all arrive as GENERIC. That reasoning is backwards twice
// over. Most of the world IS a wall - that is what a world is - and the fill is
// supposed to stop at it. What the old branch actually did was make every
// unlisted solid transparent, so a torch's light crossed stone, dirt and planks
// as if they were air. That is the author's first screenshot.
//
// The reason it could not simply be flipped is the other half of the same
// problem, and it is why this batch also changed the writer. The world image is
// cleared to zero every frame and air is never drawn, so an air voxel holds zero
// - and GENERIC is zero too. Air and stone were the same value in the image, so
// no answer for GENERIC could be right: "opaque" would have walled off every
// empty voxel and stopped the fill dead, and "transparent" is what shipped. The
// writer now stores SOLID_UNLISTED for an unlisted solid, which leaves the
// cleared zero meaning air and nothing else. See that constant in
// /environment/materialIDs.glsl and LightVolumeWriteTerrain in
// /program/shadow/shadow.vsh.
//
// So the rule is now the one that reads correctly: a block stops light unless it
// is named below as something light crosses.
bool LightVolumeOpaque(uint materialID) {
	if (materialID == GENERIC) {
		// Nothing was drawn in this voxel, which is air. The writer never stores
		// GENERIC: an unlisted solid stores SOLID_UNLISTED, below.
		return false;
	}

	if (materialID == SOLID_UNLISTED) {
		// An ordinary solid block the pack gives no material of its own: stone,
		// dirt, planks, bricks. This is the branch batch 744 added, and it is what
		// makes a wall a wall.
		return true;
	}

	if (materialID == WATER || materialID == ICE || materialID == GLASS) {
		// Transparent. Water is here rather than being opaque because the game's
		// own light engine lets block light through water, and a pool that stopped
		// a torch's light would be a visible disagreement with the lightmap.
		//
		// BATCH 745: WATER NOW DIMS AS WELL AS PASSES. Eclipse gives water a
		// mixWeight of 0.8 (dimensions/setup.csh:74-76) rather than letting it
		// through untouched, and the author asked for Eclipse's table to be
		// followed. A pool that dims light slightly is more correct than one that
		// does not: water does absorb, and the game's own light engine does not
		// model that at all, so this is the pack adding the part the game leaves
		// out. The value is applied through LightVolumeFilterTint, which is why
		// water is now also a filter below.
		return false;
	}

	if (materialID == STAINED_GLASS) {
		// A filter, not a wall: light crosses it and takes its colour.
		return false;
	}

	if (materialID == NETHER_PORTAL) {
		// A source, and light crosses its surface.
		return false;
	}

	// Foliage, which is batch 744's report 5.
	//
	// These three materials are the pack's own names for plants: LEAVES is the
	// connected-waving canopy, GROUND_FOLIAGE the disconnected ground cover, and
	// SUBSURFACE_SCATTERING the no-waving set that block.properties gives grass
	// blocks, flowers and saplings. None of them was mentioned here, so all three
	// fell through to the `return true` at the bottom and a sapling blocked light
	// like a stone block. The author's fifth report is exactly that.
	//
	// They are not air either. Eclipse passes them with a mix weight rather than
	// treating them as empty (dimensions/setup.csh:65-97: BLOCK_SSS_* and
	// BLOCK_GRASS_* get 0.85, BLOCK_GROUND_WAVING and BLOCK_SAPLING 0.9), which is
	// the right shape: a canopy does dim what passes through it, it just does not
	// stop it. That weight is applied as a tint below rather than as a third state
	// here, because the fill already has a way to dim light - the tint channel -
	// and a second mechanism for the same thing would be one more thing to keep in
	// step. See LightVolumeFilters.
	if (materialID == LEAVES
		|| materialID == GROUND_FOLIAGE
		|| materialID == SUBSURFACE_SCATTERING) {
		return false;
	}

	// The non-cube shapes, which are batch 745's report 6.
	//
	// A sign, a door, a carpet and a fence are not solid cubes, so light crosses
	// them - but they are not air either, and the amount they obstruct differs by
	// shape. They pass here and take a tint below, which is the same arrangement
	// the foliage uses one branch up.
	//
	// ⚠️ THIS BRANCH IS THE ONE THAT MATTERS FOR THE FAILURE DIRECTION. Since
	// batch 744 the fill fails CLOSED: a block with an ID that is not named here
	// is a wall. So giving these blocks an ID in block.properties without adding
	// them here would have made every sign and door in the world opaque to the
	// fill - a worse bug than the one being fixed, and one that would look like
	// "the coloured light stopped working near my house".
	if (materialID == THIN_FLAT
		|| materialID == THIN_VERTICAL
		|| materialID == DOOR) {
		return false;
	}

	if (BlockLightRange(materialID) > 0.0) {
		// A light source is not a wall. A source whose voxel was marked solid
		// would light nothing, because the colour starts in this voxel and the
		// fill spreads out of a voxel into its neighbours.
		return false;
	}

	return true;
}

// Whether a block tints the light that crosses it, and with what.
//
// The tint itself is not returned: for a stained pane it is the pane's own
// texture, which the shadow program's fragment stage writes into the world image,
// and for everything else it is white. This function answers the question the
// propagation needs - "is the tint in the image meaningful here" - so that a
// block which is not a filter cannot accidentally tint by holding a stale colour.
//
// BATCH 744 ADDED FOLIAGE, AND THE VALUE IS A JUDGEMENT RATHER THAN A READING.
// The three plant materials pass light (see LightVolumeOpaque) but they should
// not pass all of it: a canopy that left a torch's light at full strength would
// read as a hole in the leaves, and one that stopped it would be the sapling
// shadow the author reported. Eclipse's answer is a mix weight of 0.85 for grass
// and 0.9 for ground cover and saplings (dimensions/setup.csh:65-97), applied as
// a multiplier on the light that crosses.
//
// The value here is 0.85 for all three, and the reasoning is:
//
//  * It is Eclipse's grass number, which is the material most of these blocks
//    actually are - block.properties gives 10019 (grass blocks, flowers, saplings)
//    and 10003 (vines, tall grass, ferns) to the same two families.
//  * It is a dimming, not a stop: 0.85 per block means a two-block canopy keeps
//    72% and a four-block one 52%, which is the "shade under a tree" reading
//    rather than either extreme.
//  * It is applied to the COLOUR only, never to the level. That is the same rule
//    the stained pane follows and for the same reason: the level is a number of
//    blocks of reach, and a leaf that shortened a torch's reach would disagree
//    with the game's own light engine, which does not attenuate through leaves at
//    all. What the eye reads as shade is the colour dimming, and that is what
//    this is.
//
// The tint is a constant here rather than a texture read because a leaf's colour
// is not what it transmits - a green leaf does not put green light on the ground,
// it puts less light on the ground. Tinting by the leaf's own texture would make
// a canopy cast coloured light, which is a different effect and not one the
// author asked for.
bool LightVolumeFilters(uint materialID) {
	return materialID == STAINED_GLASS
		|| materialID == WATER
		|| materialID == LEAVES
		|| materialID == GROUND_FOLIAGE
		|| materialID == SUBSURFACE_SCATTERING
		|| materialID == THIN_FLAT
		|| materialID == THIN_VERTICAL
		|| materialID == DOOR;
}

// The tint a filter applies, for the filters whose tint is not in the image.
//
// A stained pane's colour comes from its texture and is written into the world
// image by the shadow program's fragment stage, so the propagation reads it from
// there. Everything else here has no colour to read and takes a constant.
//
// BATCH 745 TOOK THESE FROM ECLIPSE, ON THE AUTHOR'S INSTRUCTION. He asked for
// Eclipse's table to be followed rather than for values invented here, and the
// numbers below are Eclipse's `mixWeight` (dimensions/setup.csh:61-97, 989-1062,
// 1156), which multiplies its tint (setup.csh:1214). 1.0 passes light unchanged
// and 0.0 blocks it; Eclipse's default is 0.0, which is the same conclusion
// batch 744 reached independently for an unlisted block.
//
// ⚠️ THE VALUE IS APPLIED TO THE LEVEL, NOT TO THE COLOUR, AND THAT IS A FIX.
// Batch 744 multiplied these constants into the colour. That was a no-op: the
// encode normalises the colour to its brightest channel (LightVolumeEncode), so a
// uniform scalar is divided straight back out and the block passed light at full
// strength. The level is the only channel that can carry "less light got through",
// which is why the pane's peak goes there too. See the spread in
// program/light_volume/step.csh.
//
// WHICH ECLIPSE CATEGORY EACH OF OUR THREE FOLIAGE MATERIALS IS:
//
//  * LEAVES -> BLOCK_AIR_WAVING (0.9). Eclipse puts leaves in block.56, which is
//    BLOCK_AIR_WAVING, and that is 0.9. This is the one that changed: batch 744
//    used 0.85 for all three, which was Eclipse's grass value applied to the
//    wrong material.
//  * GROUND_FOLIAGE -> BLOCK_GROUND_WAVING (0.9). block.54 in Eclipse's
//    block.properties is fern, short_dry_grass, bush, firefly_bush and the like,
//    which is what this pack's 10002 holds.
//  * SUBSURFACE_SCATTERING -> BLOCK_GRASS_SHORT (0.85). This pack's 10003 holds
//    vine, tall_grass, saplings and flowers; Eclipse splits those across
//    BLOCK_GRASS_SHORT (0.85), BLOCK_SAPLING (0.9) and BLOCK_VINE (1.0).
//
// ⚠️ OUR THREE MATERIALS CANNOT EXPRESS ECLIPSE'S FIVE VALUES. Eclipse separates
// grass 0.85, sapling 0.9, ground-waving 0.9, vine 1.0 and vine-other 0.5; this
// pack's 10003 lumps vines, tall grass, saplings and flowers into one material.
// Rather than silently average them, SUBSURFACE_SCATTERING takes 0.85 - the
// grass value, which is the largest single group in that list - and the
// difference is recorded here. Splitting it would cost a new material ID and a
// block.properties entry, which is a decision for a batch that is asked for it.
//
// Eclipse also gives doors, trapdoors, slabs, stairs and walls a six-bit face
// mask so a slab passes light in five directions rather than six. This pack has
// no per-face data in the field and does not add one here; the mixWeight is the
// part that was asked for. That is a known difference, not an oversight.
vec3 LightVolumeFilterTint(uint materialID) {
	if (materialID == WATER) {
		// Eclipse's water, 0.8 (setup.csh:74-76). See the note on the transparent
		// branch of LightVolumeOpaque for why water dims rather than passing
		// untouched.
		return vec3(0.8);
	}

	if (materialID == LEAVES) {
		return vec3(0.9);
	}

	if (materialID == GROUND_FOLIAGE) {
		return vec3(0.9);
	}

	if (materialID == SUBSURFACE_SCATTERING) {
		return vec3(0.85);
	}

	if (materialID == THIN_FLAT) {
		// Carpet 0.9 and pressure plate 0.9 (setup.csh:991, 1025). Snow layers
		// and the daylight detector are 0.5 in Eclipse (setup.csh:1036), but they
		// share this material with carpet, so the group takes the value of the
		// majority and the difference is recorded rather than averaged away.
		return vec3(0.9);
	}

	if (materialID == THIN_VERTICAL) {
		// Sign 0.9 (setup.csh:1156). Eclipse gives buttons 1.0 (setup.csh:69-71)
		// and has no entry for ladders, chains, fences, rails or levers - those
		// stay opaque there, and the author's instruction is to follow Eclipse.
		// They are grouped here because they are the same shape as a sign and the
		// author named them; 0.9 is the sign's value.
		return vec3(0.9);
	}

	if (materialID == DOOR) {
		// Door 0.8 and trapdoor 0.8 (setup.csh:1008, 1041).
		return vec3(0.8);
	}

	return vec3(1.0);
}

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

// The field at a position, as the light level it carries and the colour it
// arrives in.
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
//
// The decode is the inverse of the encoding section above: the stored alpha is
// turned back into a light level, and the stored rgb - which is a normalised
// colour - is scaled by it. That is Eclipse's SampleLpvLinear
// (lib/lpv_render.glsl:20-24) with the same two steps in the same order.
vec4 LightVolumeSample(vec3 cameraRelativePos, vec3 subBlockOffset) {
	vec3 uv = LightVolumeCoord(cameraRelativePos, subBlockOffset)
		/ float(LIGHT_VOLUME_SIZE);

	if (any(lessThan(uv, vec3(0.0))) || any(greaterThan(uv, vec3(1.0)))) {
		return vec4(0.0);
	}

	vec4 stored = (frameCounter % 2) == 0
		? texture(light_volume_a_sampler, uv)
		: texture(light_volume_b_sampler, uv);

	// The level the alpha channel encodes, and the colour scaled by it. A stored
	// alpha of zero decodes to a level of zero, so a voxel the fill has nothing
	// to say about comes back black rather than as a colour at zero strength.
	float level = exp2(stored.a * LIGHT_VOLUME_LEVEL_RANGE) - 1.0;

	return vec4(stored.rgb * level, level);
}

// The colour of block light at this position, as a mix between the fallback and
// the light the flood fill put there.
//
// fallbackTint is the colour this pack would light the surface with if there were
// no flood fill at all - the lightmap's hue moved by BLOCKLIGHT_TEMPERATURE (see
// BlockLightTint in diffuse.glsl). It is the value returned where the fill has
// nothing to say, and it is the colour the fill's own colour is mixed with at the
// edge of the grid.
//
// BATCH 739 CHANGED WHAT THE SECOND RETURN VALUE MEANS. It used to be a strength
// in [0, 1] that the caller multiplied a lightmap-derived brightness by; the
// fill decided hue and the lightmap decided brightness. Now the fill decides
// both, and the out parameter is the light level itself - the number of blocks of
// reach the field carries here, already faded at the grid's edge. The caller adds
// it to the lightmap's own level rather than replacing it, which is what keeps a
// surface lit by a source the fill cannot see (outside the grid, or behind
// geometry the shadow pass did not draw) from going dark.
//
// subBlockOffset is passed through to LightVolumeSample; see the note there for
// why it is an argument rather than fract(cameraPosition) read here.
//
// lightHere is the game's own block light level at this fragment. It is no longer
// a gate - the fill's light is real light and does not need the lightmap's
// permission to exist - but it is still the floor: a surface the game says is lit
// stays lit even where the field is empty.
vec3 LightVolumeBlockLight(
	vec3 fallbackTint,
	vec3 cameraRelativePos,
	vec3 worldNormal,
	vec3 subBlockOffset,
	float lightHere,
	out float levelOut
) {
	levelOut = 0.0;

	// Offset along the normal first, then sample - see LIGHT_VOLUME_NORMAL_OFFSET
	// for why sampling where the fragment actually is does not work.
	vec4 field = LightVolumeSample(
		cameraRelativePos + worldNormal * LIGHT_VOLUME_NORMAL_OFFSET,
		subBlockOffset);

	float level = field.a;

	if (level < LIGHT_VOLUME_MINIMUM) {
		return fallbackTint;
	}

	// How much of the fill's colour this fragment takes, from two independent
	// things, and both of them have to agree:
	//
	//  - the field has to be strong enough here to mean something;
	//  - the fragment has to be well inside the grid, or the edge of the
	//    coloured cube would be visible as exactly that.
	//
	// The third weight the old version had - "something has to be lighting this
	// surface already" - is gone, and its removal is the point of the rewrite:
	// the fill's light is now light in its own right, so a surface the lightmap
	// calls dark but a torch reaches is lit by that torch. That is what Eclipse
	// does and what the author asked for.
	float strengthAtField = smoothstep(
		LIGHT_VOLUME_MINIMUM, LIGHT_VOLUME_FADE_IN, level);

	// The edge fade, measured in blocks from the boundary rather than as a
	// fraction of the radius: the fade is about the boundary, so its width should
	// not change when the grid does. Eclipse's shape
	// (lib/diffuse_lighting.glsl:131-134), with the same ten metres.
	vec3 gridPos = LightVolumeCoord(cameraRelativePos, subBlockOffset);
	vec3 cubicRadius = clamp(min(
		(vec3(float(LIGHT_VOLUME_SIZE)) - gridPos) / LIGHT_VOLUME_EDGE_FADE_LENGTH,
		gridPos / LIGHT_VOLUME_EDGE_FADE_LENGTH), 0.0, 1.0);
	float strengthAtEdge = cubicRadius.x * cubicRadius.y * cubicRadius.z;
	strengthAtEdge = 1.0 - pow(1.0 - pow(strengthAtEdge, 1.5), 3.0);

	float strength = strengthAtField * strengthAtEdge;

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

	// The level the caller adds to the lightmap's own, faded at the edge. It is
	// reported before the colour is normalised, because the level is what the
	// caller needs and the colour is what this function returns.
	levelOut = level * strengthAtEdge;

	// Hue only, at the fallback's own brightness. The field is normalised and then
	// scaled by the fallback's brightest channel rather than its luminance, which
	// is the same rule BlockLightTint uses: the brightest channel is what the
	// lightmap's own hue was normalised against, so the two agree.
	vec3 hue = field.rgb / max(level, 1.0e-4);

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
