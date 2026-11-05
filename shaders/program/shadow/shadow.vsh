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

	// The two stage constants, with the loader's own definitions winning.
	//
	// Iris supplies these names to every program it compiles; this project's front
	// end does not, so without a fallback the block-entity branch below - and the
	// cull that ends main() - would be the parts of this program no check ever
	// compiles. `#ifndef` keeps the loader's own definition whenever there is one,
	// and in game there always is.
	//
	// The two numbers are the ones this file carried before batch 719. They could
	// not be confirmed here: no Iris or OptiFine source or documentation is on this
	// machine, and the claims about the table disagree with each other, so replacing
	// them would be a second guess rather than a correction. In the only case that
	// reaches the game - the loader defines the names - none of this matters. A
	// wrong fallback costs the local model only: a block-entity draw would be
	// written as terrain (see case 3 at the write) and the cull below would not
	// fire for it. Both are noted in BATCH_LOG.md b719.
	#ifndef MC_RENDER_STAGE_ENTITIES
		#define MC_RENDER_STAGE_ENTITIES 3
	#endif
	#ifndef MC_RENDER_STAGE_BLOCK_ENTITIES
		#define MC_RENDER_STAGE_BLOCK_ENTITIES 4
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

	// A block entity's voxel.
	//
	// Only the block entities whose light this pack can name have a colour to
	// write, and which those are is BlockEntityLightColor's business rather than
	// this file's: it answers black for everything else, and a block entity that
	// is not a light must write nothing at all rather than writing a solid voxel.
	// A chest that blocked light would put a black hole in the colour field in
	// exactly the place an entity used to.
	//
	// A block entity supplies no at_midBlock, so the voxel comes from the vertex
	// position. The portal models are drawn in the block they belong to, so the
	// store lands in that block - or, for a vertex exactly on a block boundary, in
	// the block on the far side of it. That is a few voxels of spill along the edge
	// of an end portal, and it is the harmless side of the trade for a state that
	// only adds light.
	void LightVolumeWriteBlockEntity(vec3 cameraRelativePos) {
		vec3 emitted = BlockEntityLightColor(float(blockEntityId));

		if (any(greaterThan(emitted, vec3(0.0)))) {
			LightVolumeStore(cameraRelativePos, vec4(emitted, 0.0));
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
	// Then the materials light passes through, which are air to the fill.
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

		if (material == WATER || material == ICE || material == GLASS) {
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
	// WHO MAY WRITE, which is the whole of the fix for the entities that the b696
	// build drew as solid blocks - and, in batch 698, the whole of the fix for the
	// b697 build writing nothing at all.
	//
	// The rule is: exclude only what can be named, and write everything else. A
	// feature whose failure mode is "no colour anywhere" must not be gated on a
	// signal that cannot be proved. b697 gated the write on at_midBlock (with
	// entityId as a second test) and the effect disappeared completely in game,
	// which says those two do not carry the values the documentation suggests in
	// this pass - and a gate that fails closed turns a lighting feature off.
	//
	//   1. A block-entity draw (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES):
	//      only the glowing ones write, and which those are is
	//      BlockEntityLightColor's answer. A chest or a sign writes nothing - it is
	//      not a light, and its voxel is empty space as far as the colour field is
	//      concerned.
	//   2. An entity draw (renderStage == MC_RENDER_STAGE_ENTITIES): nothing at
	//      all, neither a light nor an occluder. This is the fix for the orange
	//      patch in the report. Entities have no mc_Entity, so their material was
	//      GENERIC, which the writer treats as "blocks light"; every mob, item and
	//      armour stand wrote a solid black voxel where it stood, carved a hole
	//      into the colour field, and then its own faces sampled that voxel, found
	//      no light and fell back to the lightmap's warm colour.
	//   3. Everything else: a terrain write. Everything else in a shadow pass is
	//      chunk terrain, and the bias is deliberate - if the stage number is one
	//      this file has not heard of, or reads 0 because the loader did not fill
	//      it, the write still happens. A voxel written that should not be there
	//      costs a slightly wrong occlusion; a voxel not written costs the whole
	//      effect, which is what b697 shipped and the author saw.
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
	// the end of main() and the fail-open rule above are therefore checked by
	// reading them and by an explicit expand-and-glslang run, never by the standing
	// chain: b719 closed that gap for itself by expanding this program with
	// `--define IRIS_FEATURE_CUSTOM_IMAGES=1` (818 -> 1357 lines) and compiling the
	// result, which is green. Every later change inside this guard needs the same
	// run, because "frontend 0 errors" says nothing at all about it.
	// The fail-open shape is what keeps an unpopulated uniform harmless when the
	// loader does compile it.
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
	} else {
		// Chunk terrain, and anything else this file cannot name - see case 3.
		// Iris documents the block centre as `position + at_midBlock.xyz / 64.0`.
		// Where the attribute is populated this lands the voxel exactly on the
		// block; where it is not, the vertex's own position is used, which is the
		// approximation the b696 build shipped and which still lands in the right
		// part of the world.
		vec3 blockCenter = cameraRelativePos.xyz + at_midBlock.xyz / 64.0;
		LightVolumeWriteTerrain(materialID, blockCenter);
	}

	// Block entities leave the map as soon as their voxel is written.
	//
	// Batch 719 submits them to this pass for that voxel and for nothing else. The
	// fill's world image has no other writer, so the end portal's light can only be
	// coloured cold if its geometry is drawn here - and the map itself must not
	// gain a shape it never had, or a chest, a sign and the portal's own plane
	// would all start casting shadows the pack has never drawn.
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
	#if !defined(REAL_TIME_BLOCK_ENTITY_SHADOWS)
		if (renderStage == MC_RENDER_STAGE_BLOCK_ENTITIES) {
			gl_Position = vec4(2.0, 2.0, 2.0, 1.0);
		}
	#endif
#endif
}
