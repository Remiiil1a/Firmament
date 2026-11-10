// Steadfast is a fast and high-quality graphical overhaul for Minecraft (JE)
// Copyright (C) 2026 coderbot
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// The shadow pass: the depth map, and the coloured light fill's world image.
//
// The map itself is the upstream program - water heights for the caustics, the
// glass cull, and the material ID the fragment stage reads. Since batch 696 this
// stage also writes light_volume_world, and since batch 719 the loader submits
// block entities to this pass whenever COLORED_LIGHTS is on (see shadowBlockEntities
// in shaders.properties). That is not for their shadows: the world image has no
// other writer, and the two block-entity portals are light sources, so their
// geometry has to be drawn here for the fill to learn their colour. Once the write
// has run, main() puts every block-entity vertex outside the clip volume, so the
// map keeps exactly the shape it had and they feed the fill only.
// REAL_TIME_BLOCK_ENTITY_SHADOWS is what turns the cull off and the shadows on.
#include "/lib/distort.glsl"

in vec4 mc_Entity;
in vec3 at_midBlock;

out vec2 texcoord;
out float waterHeight;

// The material this fragment belongs to, which the fragment shader needs to pick
// the one material whose colour the light passing through it should take on.
// Flat, because a material is not something to interpolate across a face.
//
// This was a local until colored shadows arrived; see COLORED_SHADOWS in
// /environment/materialIDs.glsl for what the fragment shader does with it.
flat out uint materialID;

uniform mat4 shadowModelViewInverse;

#include "/environment/materialIDs.glsl"

// The palette the world image's colour comes from, and the grid the voxel index
// is computed with.
//
// materialIDs.glsl above has to stay first: the palette is written as ranges over
// those IDs. light_colors.glsl is also where COLORED_LIGHTS is defined, so the
// guard for the write below can only come after both includes - which is why the
// write is not simply compiled out by a test at the top of the file.
//
// light_volume.glsl is the grid's only definition. The propagation pass and the
// terrain programs that sample the field include the same file, so all three ends
// of the feature agree about where a position sits in the volume; a copy of the
// formula here is the kind of second source of truth that goes stale in silence.
#include "/environment/lighting/light_colors.glsl"

#if defined(COLORED_LIGHTS) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
	#include "/environment/lighting/light_volume.glsl"

	// The camera's world position, for the part of it that is inside a block: the
	// grid is snapped to whole blocks (see LightVolumeCoord), so the voxel a
	// position lands in must not move while the camera moves within one block.
	uniform vec3 cameraPosition;

	// What kind of geometry is being drawn, which is what decides whether this
	// vertex may write a voxel at all.
	//
	// renderStage is the loader's own number for the draw being submitted, with a
	// constant per kind (MC_RENDER_STAGE_TERRAIN_SOLID and friends for the chunk
	// passes, MC_RENDER_STAGE_ENTITIES for mobs and items,
	// MC_RENDER_STAGE_BLOCK_ENTITIES for block entities). It is the test this uses,
	// for the reason written at the write below: it is the loader's own statement
	// about what it is drawing, it is the same one Eclipse's LPV and Mellow's
	// coloured lights both use, and it does not depend on an attribute being
	// present on the geometry - which is exactly what made batch 697 lose the whole
	// effect in game.
	uniform int renderStage;

	// The stage constants, with the loader's own definitions winning.
	//
	// Iris supplies these names to every program it compiles; this project's front
	// end does not, so without a fallback the branches below - and the cull that
	// ends main() - would be the parts of this program no check ever compiles.
	// `#ifndef` keeps the loader's own definition whenever there is one, and in
	// game there always is.
	//
	// The numbers are the loader's, read off its own rendering-phase enumeration in
	// batch 728: NONE 0, SKY 1, SUNSET 2, CUSTOM_SKY 3, SUN 4, MOON 5, STARS 6,
	// VOID 7, TERRAIN_SOLID 8, TERRAIN_CUTOUT_MIPPED 9, TERRAIN_CUTOUT 10,
	// ENTITIES 11, BLOCK_ENTITIES 12, DESTROY 13, OUTLINE 14, DEBUG 15,
	// HAND_SOLID 16, TERRAIN_TRANSLUCENT 17, TRIPWIRE 18, PARTICLES 19, CLOUDS 20,
	// RAIN_SNOW 21, WORLD_BORDER 22, HAND_TRANSLUCENT 23. Note the order of the two
	// cutout stages: MIPPED is 9 and CUTOUT is 10, not the other way round.
	//
	// WHAT THIS DOES AND DOES NOT DO. The loader defines all twenty-four of these
	// names in every program it compiles: it builds the list from that same
	// enumeration and hands it to the preprocessor ahead of each program source, so
	// `#ifndef` is false in game and these lines are dead there. The numbers below
	// were therefore already the ones being compared in game, before this batch as
	// well as after it. Correcting them changes what this project's own front end
	// compiles, which is the only build that ever read them - it is not, and never
	// was, the picture.
	//
	// WHICH IS WHY THE BRANCHES BELOW COMPARE NAMES, NEVER NUMBERS. The literals
	// live here and nowhere else. If a future loader renumbers its enumeration, the
	// game keeps working and only this project's own front end is stale, which is
	// the failure mode that costs a compile error here instead of a wrong picture
	// there.
	#ifndef MC_RENDER_STAGE_TERRAIN_SOLID
		#define MC_RENDER_STAGE_TERRAIN_SOLID 8
	#endif
	#ifndef MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED
		#define MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED 9
	#endif
	#ifndef MC_RENDER_STAGE_TERRAIN_CUTOUT
		#define MC_RENDER_STAGE_TERRAIN_CUTOUT 10
	#endif
	#ifndef MC_RENDER_STAGE_ENTITIES
		#define MC_RENDER_STAGE_ENTITIES 11
	#endif
	#ifndef MC_RENDER_STAGE_BLOCK_ENTITIES
		#define MC_RENDER_STAGE_BLOCK_ENTITIES 12
	#endif
	#ifndef MC_RENDER_STAGE_TERRAIN_TRANSLUCENT
		#define MC_RENDER_STAGE_TERRAIN_TRANSLUCENT 17
	#endif

	// blockEntityId is the loader's number for the block entity being drawn, from
	// the pack's own block.properties (10039 the end portal, 10012 the end
	// gateway), so it is a number this pack controls and can count on. It is used
	// only to pick which of the two gets a colour - the decision whether this draw
	// may write at all is renderStage's, above.
	//
	// entityId is deliberately not declared: the loader fills it from
	// entity.properties, this pack ships no entity.properties, and batch 697
	// shipped a version that tested it and lost the whole effect in game. The
	// stage test replaces it.
	uniform int blockEntityId;

	// This frame's emitters, filters and occluders, written here and read by the
	// propagation pass later in the same frame. writeonly is what this stage does
	// with it - the shadow program is the only writer (this stage for the
	// geometry, its fragment stage for the colour of stained glass) and the
	// compute pass is the only reader - and the loader clears it every frame (see
	// its declaration in shaders.properties), which is what makes "no vertex
	// reached this voxel" mean "nothing was drawn there this frame" rather than
	// "nothing was drawn since the pack loaded".
	layout(rgba16) uniform writeonly image3D light_volume_world;

	// The voxel this vertex's block landed in, for the fragment stage.
	//
	// Stained glass takes its tint from the pane's own texture, which only the
	// fragment stage can sample, so the fragment stage is what stores the filter
	// state - and it has to store it into the same cell this stage classified.
	// Passing the voxel across rather than reconstructing it there keeps one
	// definition of where a position sits in the grid (LightVolumeCoord), and
	// avoids a reconstruction that would have to undo distort() and assume the
	// shadow projection. (-1, -1, -1) means "no voxel": the vertex was not chunk
	// terrain, or it was outside the grid, and the fragment stage must not store
	// with it. Integer varyings must be flat on both sides; program/shadow/shadow.fsh
	// declares it flat in behind the same guard.
	flat out ivec3 lightVolumeVoxel;

	// Where a camera-relative position sits in the grid, and whether it is inside
	// it at all. The coordinate function is the one from light_volume.glsl; this
	// only adds the bounds test, which is the same one the shading side uses when
	// it samples the field.
	bool LightVolumeVoxelAt(vec3 cameraRelativePos, out ivec3 voxel) {
		voxel = ivec3(floor(LightVolumeCoord(
			cameraRelativePos,
			fract(cameraPosition))));

		return !any(lessThan(voxel, ivec3(0)))
			&& !any(greaterThanEqual(voxel, ivec3(LIGHT_VOLUME_SIZE)));
	}

	// One voxel of the world image, if the position is inside the grid, plus the
	// bookkeeping the fragment stage needs. The caller decides the value; this
	// only holds the bounds test and the one place the varying is written.
	void LightVolumeStore(vec3 cameraRelativePos, vec4 value) {
		ivec3 voxel;

		if (!LightVolumeVoxelAt(cameraRelativePos, voxel)) {
			lightVolumeVoxel = ivec3(-1);
			return;
		}

		lightVolumeVoxel = voxel;
		imageStore(light_volume_world, voxel, value);
	}

	// The centre of the voxel a block-entity vertex lands in, in the camera-relative
	// space the store takes.
	//
	// A block entity supplies no at_midBlock, so its voxel comes from the vertex
	// position - and a portal's vertices sit exactly on block boundaries, which
	// makes the coordinate an exact integer and leaves floor() to be decided by the
	// round-trip error of shadowModelViewInverse * viewPos. That error changes as
	// the camera moves, so the emitter could land in either of two neighbouring
	// voxels from one frame to the next, and the light it casts jumped a block and
	// back. That is the author's report of a portal whose colour strobes while the
	// camera moves.
	//
	// Two things fix it and both are needed. The bias resolves the tie the same way
	// every frame; it is a thousandth of a voxel, so it moves nothing that was not
	// already sitting on a boundary. Storing at the voxel's centre then leaves the
	// coordinate half a block from every boundary, so no later rounding can carry
	// it across one either.
	//
	// The grid anchor is not part of this. LightVolumeCoord adds fract(cameraPosition)
	// to a position that is already camera-relative, and those two cancel exactly
	// (cameraRelativePos + fract(cameraPosition) is worldPos - floor(cameraPosition)),
	// so moving within a block does not re-anchor the grid at all.
	vec3 LightVolumeBlockCentre(vec3 cameraRelativePos) {
		vec3 gridPos = LightVolumeCoord(cameraRelativePos, fract(cameraPosition));
		vec3 voxel = floor(gridPos + 1.0e-3);

		return voxel + 0.5
			- fract(cameraPosition)
			- vec3(float(LIGHT_VOLUME_GRID_RADIUS));
	}

	// A block entity's voxel.
	//
	// Only the block entities whose light this pack can name have a colour to
	// write, and which those are is BlockEntityLightColor's business rather than
	// this file's: it answers black for everything else, and a block entity that
	// is not a light must write nothing at all rather than writing a solid voxel.
	// A chest that blocked light would put a black hole in the colour field in
	// exactly the place an entity used to.
	//
	// Batch 730 took the end portal out of that list; the gateway is the one block
	// entity that still answers with a colour. See the long note on
	// BlockEntityLightColor for why, and note that the portal's own look is
	// unaffected - it is drawn by PORTAL_END in /program/world/lit.fsh, which is a
	// surface effect and needs nothing from this pass.
	//
	// The position is snapped to the centre of its voxel first; see
	// LightVolumeBlockCentre for why a raw vertex position is not stable enough to
	// store with. A gateway model is drawn in the block it belongs to, so the store
	// lands there - or, for a vertex exactly on a block boundary, in the block the
	// bias picks. That is a voxel of spill along the edge of a gateway, and it is
	// the harmless side of the trade for a state that only adds light. It used to
	// be the end portal's problem, and the end portal is where the spill was
	// reported; with the portal out of the list only the gateway can reach this
	// line, and a gateway is one block with no neighbours to speak of.
	void LightVolumeWriteBlockEntity(vec3 cameraRelativePos) {
		vec3 emitted = BlockEntityLightColor(float(blockEntityId));

		if (any(greaterThan(emitted, vec3(0.0)))) {
			LightVolumeStore(LightVolumeBlockCentre(cameraRelativePos), vec4(emitted, 0.0));
		}
	}

	// A chunk-terrain voxel.
	//
	// The cases, in this order, and the order is the meaning. An emitter is
	// tested first so that a light source always gets its own colour into the
	// fill: a source whose voxel was marked solid would light nothing, because the
	// colour starts in this voxel and the fill spreads out of a voxel into its
	// neighbours. The nether portal is an emitter too even though the palette has
	// no entry for it - its material deliberately has no light colour of its own,
	// because BlockLightColor is also what colours the emitter's own face and the
	// portal surface has its own tint - and NETHER_PORTAL_TINT from
	// materialIDs.glsl is authored for exactly this.
	//
	// Then the materials light passes through, which are air to the fill. Water is
	// the one that gets a tag of its own - see the state table in light_volume.glsl
	// and the write below - and the tag is chosen so that it stays air to the fill.
	//
	// Stained glass is the exception and is handled before them: its voxel is a
	// filter, and the fragment stage is its only writer. This stage must not store
	// the transparent value for it first, because "fragments come after vertices"
	// orders the two stages only within one primitive - within one draw, a vertex
	// of a later primitive can run after the fragment of an earlier one, and that
	// transparent store would put the filter voxel back to air. The voxel is still
	// published through the varying, because the fragment is what needs it. The
	// tint itself cannot be written from here at all: it comes from the pane's
	// texture, which this stage does not read.
	//
	// Everything else, leaves included, blocks the fill and emits nothing. Leaves
	// are the interesting member of that set: they are not an opaque cube to the
	// eye, but the game's own light engine treats them as a block that dims what
	// crosses it, and that is the question this image is answering.
	void LightVolumeWriteTerrain(uint material, vec3 centerCameraRelative) {
		vec3 emitted = BlockLightColor(material);

		if (any(greaterThan(emitted, vec3(0.0)))) {
			LightVolumeStore(centerCameraRelative, vec4(emitted, 0.0));
			return;
		}

		if (material == NETHER_PORTAL) {
			LightVolumeStore(centerCameraRelative, vec4(NETHER_PORTAL_TINT, 0.0));
			return;
		}

		if (material == STAINED_GLASS) {
			// No store from this stage; see the note above. The voxel is still
			// published for the fragment stage.
			ivec3 voxel;
			lightVolumeVoxel = LightVolumeVoxelAt(centerCameraRelative, voxel)
				? voxel
				: ivec3(-1);
			return;
		}

		if (material == WATER) {
			// Water has a tag of its own since batch 736, and the reader is the
			// water interaction's source test: it asks this image whether the voxel
			// at the player's feet is water (program/water_interaction/sim.glsl).
			// The fill reads 0.125 as air and rgb stays zero, so the value it
			// computes here is the one the 0.0 this branch stored before produced.
			LightVolumeStore(
				centerCameraRelative,
				vec4(0.0, 0.0, 0.0, LIGHT_VOLUME_WATER_STATE));
			return;
		}

		if (material == ICE || material == GLASS) {
			LightVolumeStore(centerCameraRelative, vec4(0.0));
			return;
		}

		LightVolumeStore(centerCameraRelative, vec4(0.0, 0.0, 0.0, 1.0));
	}
#endif

void main() {
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
	vec4 cameraRelativePos = shadowModelViewInverse * viewPos;
	materialID = DecodeMaterialID(mc_Entity.x);

	// TODO: Deduplicate this, copied from lit.fsh
	//
	// At this point in the file this is water-surface detection for the shadow
	// map's waterHeight output. It was copied from lit.fsh, which uses the same
	// test for its own water effects, so the two have to be changed together.
	if (materialID == WATER &&
		// Only water faces that are facing directly up or down are eligible
		// for standard water effects. Otherwise, we will fall back to vanilla
		// flowing water tecture.
		abs(gl_Normal.y) > 0.9999 &&
		// If flat, this face must also be high enough that it is not just
		// the flat center of flowing water as well.
		//
		// At this point in the file at_midBlock.y (the third component of the
		// loader's attribute; the declaration above takes only the three xyz,
		// so nothing here can read the fourth) is the offset from the middle
		// of the block to this vertex, in 1/64 block units. The attribute is a
		// vec4 because its w carries the block's light level, which this file
		// does not use. The top face of still
		// water sits above the middle of the block, so its offset is negative -
		// the middle is below the surface. So, this actually means: is this
		// vertex more than 23/64th of a block above its center?
		//
		// If you look at still water in vanilla, the surface lies 2 pixels
		// below the top of a nearby solid block. Those 2 pixels are 2/16 of a
		// block, so the surface stands 14/16 = 0.875 of a block above the
		// block's floor, which is 24/64 above its center - the half block plus
		// 8/64. So 23/64 (0.359375 as an offset from the center) just allows
		// for some imprecision, without allowing a still center of flowing
		// water, which is below this threshold (3 pixels below the block top,
		// a 20/64 offset). Read the two as offsets-from-center throughout:
		// 0.875 is a height above the floor, 0.359375 an offset from the
		// middle.
		at_midBlock.y < -23.0
	) {
		float y = cameraRelativePos.y;
		waterHeight = 0.5 - 0.5 * clamp(y / 1024.0, -1.0, 1.0);
	} else {
		waterHeight = 1.0;
	}

	texcoord = gl_MultiTexCoord0.xy;
	gl_Position = gl_ProjectionMatrix * viewPos;
	gl_Position.xyz = distort(gl_Position.xyz);

	// Prevent some blocks from casting shadows for aesthetic reasons.
	// See the definition in block.properties for more details.
	//
	// Everything at the vertex ends up at -1.0, which is outside the clip
	// volume, so the triangle is culled and nothing is written to the map for
	// it - with all three vertices gone, the primitives are gone with them.
	// The buffer's own depth is therefore unchanged where the glass was, and a
	// fragment that the map holds as lit stays lit.
	if (materialID == GLASS) {
		gl_Position = vec4(-1.0);
	}

	// The world image write, after every decision this file makes about the
	// vertex.
	//
	// It comes last on purpose. The glass cull above sends a GLASS vertex to
	// vec4(-1.0) so that its triangle writes nothing to the depth buffer, but the
	// vertex itself still runs; a write placed before that decision could mark a
	// voxel for a surface that is not in the map. Below it, glass still writes - as
	// the transparent voxel it is - so the two paths agree instead of one silently
	// undoing the other.
	//
	// WHO MAY WRITE. This is the whole of the fix for the entities that the b696
	// build drew as solid blocks, and - since batch 728 - the whole of the fix for
	// the hole they still left beside a block entity.
	//
	// The rule is now: write only on a positive terrain signal. A voxel is written
	// when the phase is one of the four terrain phases, or when mc_Entity.x says
	// this vertex belongs to a block. Everything else writes nothing.
	//
	// WHY IT USED TO BE THE OTHER WAY ROUND, AND WHY THAT WAS THE BUG. Batch 698
	// wrote the rule as "exclude only what can be named, and write everything
	// else", on the argument that a feature whose failure mode is "no colour
	// anywhere" must not be gated on a signal that cannot be proved: b697 had gated
	// the write on at_midBlock and the effect disappeared completely in game. That
	// argument was right about the danger and wrong about the cure. It made the
	// unknown case write a solid voxel, and an unknown case is exactly what an
	// entity turned out to be - so the fail-open did not protect the feature, it
	// manufactured the hole the feature was accused of. The evidence that the
	// terrain signal is trustworthy is that terrain is drawn under a phase the
	// loader sets by name (see the note on the branch below); the evidence that the
	// fail-open was not is a snow golem standing next to an end portal.
	//
	//   1. A block-entity draw (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES):
	//      only the glowing ones write, and which those are is
	//      BlockEntityLightColor's answer. A chest or a sign writes nothing - it is
	//      not a light, and its voxel is empty space as far as the colour field is
	//      concerned.
	//   2. An entity draw (renderStage == MC_RENDER_STAGE_ENTITIES): nothing at
	//      all, neither a light nor an occluder. This is the fix for the orange
	//      patch in the b696 report. Entities have no mc_Entity, so their material
	//      was GENERIC, which the writer treats as "blocks light"; every mob, item
	//      and armour stand wrote a solid black voxel where it stood, carved a hole
	//      into the colour field, and then its own faces sampled that voxel, found
	//      no light and fell back to the lightmap's warm colour.
	//   3. A terrain phase (TERRAIN_SOLID, TERRAIN_CUTOUT_MIPPED, TERRAIN_CUTOUT,
	//      TERRAIN_TRANSLUCENT), or mc_Entity.x > 0.0: a terrain write.
	//   4. Anything else - NONE, particles, text, a stage this file has not heard
	//      of - writes nothing.
	//
	// WHY CASE 4 IS SAFE, WHICH IS THE ONE THING THIS RULE RESTS ON. In the shadow
	// pass the loader draws opaque terrain immediately, under TERRAIN_SOLID, before
	// it sets the entity phase; entities and block entities are only submitted
	// there and are flushed together afterwards, and translucent terrain is drawn
	// after that flush. So during the flush the only draws are entity batches and
	// block-entity batches, and a NONE seen there can only be an entity. That is
	// the case this rule exists to catch, and it is the only case it catches.
	//
	// The phase is per batch, but a clear is not: setting the phase to NONE only
	// marks it for removal, and it becomes NONE on the next read - which is the
	// next shader bind. A block-entity batch therefore leaves NONE behind it, and
	// an entity batch drawn after one inherits it. That is why the hole appeared
	// beside a block entity and not on its own: with no block entity in the pass
	// the entity batch still sees ENTITIES and case 2 catches it, and only a block
	// entity's clear can hand it a NONE.
	//
	// mc_Entity.x is the second signal and the weaker of the two. It is kept
	// because it is what still writes an unmapped block when the phase is not what
	// this file expects, and it is trustworthy here for a reason at_midBlock is
	// not: it is baked into the terrain vertex format itself, and materialID -
	// which every coloured light in this pack already depends on - is decoded from
	// the same attribute. at_midBlock is the one b697 proved empty in this pass.
	// Entities carry no mc_Entity at all; their format has iris_Entity instead, so
	// this signal cannot fire for one.
	//
	// THE RISK THIS ACCEPTS, WRITTEN DOWN SO IT IS NOT A SURPRISE. If a future
	// loader stops naming a terrain phase in the shadow pass, the fill goes dark
	// instead of wrong. That is the trade: a dark fill is a feature that visibly
	// does not work, and a wrong fill is a hole in the world that looks like a
	// rendering bug in something else. The detector is LIGHT_VOLUME_DEBUG_WORLD,
	// which paints a solid block dark grey and air black - a world that reads as
	// uniformly solid is this rule firing on nothing.
	//
	// renderStage is the loader's own statement about what it is drawing, one
	// constant per kind, and it is the same test Eclipse's LPV and Mellow's
	// coloured lights both use. It is Iris-only - OptiFine has no such uniform -
	// and this feature is Iris-only already.
	//
	// None of this is compiled by this project's front end, and that is a fact
	// rather than a convenience: the block needs both COLORED_LIGHTS and
	// IRIS_FEATURE_CUSTOM_IMAGES, and the second one is a loader feature flag that
	// nothing in the pack or in the local tooling defines. The write, the cull at
	// the end of main() and the rule above are therefore checked by reading them
	// and by an explicit expand-and-glslang run, never by the standing chain: b719
	// closed that gap for itself by expanding this program with
	// `--define IRIS_FEATURE_CUSTOM_IMAGES=1` (818 -> 1357 lines) and compiling the
	// result, which is green. Every later change inside this guard needs the same
	// run, because "frontend 0 errors" says nothing at all about it.
	//
	// One store per terrain vertex, not one per quad. Stained glass is the one
	// terrain material that stores nothing here and the note on the writer says
	// why; for every other terrain material the four vertices of a quad all
	// resolve to the same voxel, because the position used below is the block's
	// centre and not the vertex's own, so three of the four stores are repeats;
	// but geometry is also submitted as triangles, where no vertex is the first of
	// a run of four, and a light source that went unwritten would be a light that
	// does not exist for the fill. A wasted store is the cheaper mistake.
#if defined(COLORED_LIGHTS) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
	// No voxel unless a branch below finds one. The fragment stage reads this for
	// stained glass, so it has to be defined on every path.
	lightVolumeVoxel = ivec3(-1);

	if (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES) {
		// Only reachable because shaders.properties submits block entity geometry
		// to this pass - see shadowBlockEntities there, and the cull at the end of
		// this function for what is done with the shape it would otherwise add.
		LightVolumeWriteBlockEntity(cameraRelativePos.xyz);
	} else if (renderStage == MC_RENDER_STAGE_ENTITIES) {
		// An entity: no voxel, by design. See case 2 above.
	} else if (renderStage == MC_RENDER_STAGE_TERRAIN_SOLID
		|| renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT_MIPPED
		|| renderStage == MC_RENDER_STAGE_TERRAIN_CUTOUT
		|| renderStage == MC_RENDER_STAGE_TERRAIN_TRANSLUCENT
		|| mc_Entity.x > 0.0) {
		// Chunk terrain. The phase is the primary signal; mc_Entity.x is the
		// fallback for a block the phase did not name. See cases 3 and 4 above for
		// why everything outside this test writes nothing.
		//
		// Iris documents the block centre as `position + at_midBlock.xyz / 64.0`.
		// Where the attribute is populated this lands the voxel exactly on the
		// block; where it is not, the vertex's own position is used, which is the
		// approximation the b696 build shipped and which still lands in the right
		// part of the world.
		vec3 blockCenter = cameraRelativePos.xyz + at_midBlock.xyz / 64.0;
		LightVolumeWriteTerrain(materialID, blockCenter);
	}
	// Everything else writes nothing: NONE, particles, text, and any stage this
	// file has not heard of. See case 4 above for why that is the safe direction.

	// Block entities leave the map as soon as their voxel is written.
	//
	// Batch 719 submits them to this pass for that voxel and for nothing else. The
	// fill's world image has no other writer, so a block entity light source can
	// only reach it if its geometry is drawn here - and the map itself must not
	// gain a shape it never had, or a chest, a sign and a gateway's own plane
	// would all start casting shadows the pack has never drawn.
	//
	// The end portal used to be the reason this paragraph existed. It is not any
	// more: batch 730 stopped treating it as a light source, so the only block
	// entity that still writes a voxel here is the gateway. The cull stays because
	// the gateway needs it, and because a block entity that answers black writes
	// nothing and must still not cast a shadow it never cast.
	//
	// The cull is the shape of the glass one from the top of this function, applied
	// later and for the opposite reason: every vertex of the draw goes to the same
	// point, that point is outside the clip volume on all three axes at once, and
	// a triangle whose every vertex is out of the volume never reaches the fragment
	// stage. No fragment, no depth, so the map keeps what it had. The write above
	// has already run by then, and it does not care where the vertex ends up.
	//
	// Not while the option is on, and then the geometry is there for the shadows
	// rather than for the fill. This sits inside the fill's own guard because that
	// is where renderStage is declared; when COLORED_LIGHTS is off,
	// shaders.properties submits block entities only if REAL_TIME_BLOCK_ENTITY_SHADOWS
	// is on, and then no cull is wanted. A loader that had COLORED_LIGHTS without
	// custom images would submit them for a fill that does not exist; the write
	// above needs the same images, so that state is not one this pack has ever met.
	// `#ifndef`, not `#if !defined(...)`: a boolean option is only recognized by the
	// loader if some shader file tests it with `#ifdef` or `#ifndef` (shaders.properties
	// reference, "Boolean Options"). This test and the one beside the declaration in
	// /environment/materialIDs.glsl are what make the shadows page list the option at
	// all; the meaning is unchanged.
	#ifndef REAL_TIME_BLOCK_ENTITY_SHADOWS
		if (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES) {
			gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
		}
	#endif
#endif
}
