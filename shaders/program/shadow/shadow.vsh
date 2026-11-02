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

	// What kind of geometry is being drawn.
	//
	// blockEntityId is the loader's number for the block entity being drawn, and
	// block.properties is what gives the two this pack knows their numbers
	// (10039 the end portal, 10012 the end gateway). It is a mapping the pack
	// supplies, so it can be counted on as far as those two entries are
	// concerned.
	//
	// entityId is the same shape for non-block entities, but this pack ships no
	// entity.properties, and without one the loader has no number of ours to
	// report - so the uniform may be 0 for every entity. The test on it below is
	// kept as defence in depth and never as the fix; see the note at the write
	// for which test the fix actually is.
	uniform int blockEntityId;
	uniform int entityId;

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
	// WHO MAY WRITE. The attribute test in case 3 is the fix for the entities
	// that the b696 build drew as solid blocks; case 2 is defence in depth and
	// may never fire on this pack. Read them in that order, because only the
	// first is what a player sees change:
	//
	//   1. A block entity (blockEntityId != 0): only the glowing ones write, and
	//      which those are is BlockEntityLightColor's answer. A chest or a sign
	//      writes nothing - it is not a light, and its voxel is empty space as far
	//      as the colour field is concerned.
	//   2. An entity (entityId != 0): nothing at all, neither a light nor an
	//      occluder. This is a safety net, not the fix. The loader fills entityId
	//      in from entity.properties, and this pack ships no entity.properties,
	//      so the uniform may be 0 for every entity and this test may never fire.
	//      It is kept because a false positive here is expensive - an entity
	//      written as an occluder is the b696 bug back - and the test costs one
	//      comparison.
	//   3. Chunk terrain, by the attribute: a vertex carrying at_midBlock writes a
	//      voxel, and a vertex not carrying it falls to case 4 and writes nothing.
	//      This is the branch the fix rests on. at_midBlock is the offset from the
	//      middle of the block to the vertex, in 1/64 block units; Iris documents
	//      it as available to this program, but only chunk geometry supplies it -
	//      Sodium and the vanilla chunk renderer fill it from the packed chunk
	//      vertex, while entities, block entities, hand geometry and weather are
	//      drawn without it. A cube corner is half a block from the middle, +/-32
	//      in those units, so for terrain the attribute is never the zero vector.
	//      The test is therefore about the geometry that is actually being drawn,
	//      and it is the same attribute the water height test above relies on.
	//   4. Anything else: nothing. Read case 3 the other way round, this is where
	//      entities land - their vertices supply no at_midBlock, so they write
	//      nothing. That is the fix: their own surfaces then sample the light
	//      around them instead of a black voxel their own geometry wrote, and the
	//      field around them stays intact instead of gaining a hole. A false
	//      occlusion is a black hole in a picture that is otherwise colour, and
	//      that is exactly what the solid branch used to do for every entity.
	//
	// What the bug looked like, and why: entities have no mc_Entity, so their
	// material was GENERIC, which the b696 writer treated as "blocks light". Every
	// mob, item and armour stand therefore wrote a solid black voxel where it
	// stood. Two things followed - the entity carved a hole into the colour field,
	// and its own faces sampled the voxel they had written, found no light, fell
	// back to the lightmap's warm colour and came out orange. That is the orange
	// patch under the player in the report. Both halves are fixed by not writing
	// the voxel, and the entityId test does not have to fire for that.
	//
	// Why renderStage was not used instead: Iris has a uniform that says which
	// stage is being drawn, and testing it for the terrain stage would have been
	// the direct way to write this. It is not used because it is an Iris-only
	// symbol - OptiFine has no such uniform - and because nothing in this project
	// can give it a value: the front end in _team_bfog assembles each program
	// without a stage number, and the source checkers know the name only as one a
	// loader injects. Neither side of the branch would ever be exercised by a check
	// here, and a write path nothing tests is the class of change this batch exists
	// to remove. The attribute test is the opposite case: at_midBlock is documented
	// for this stage and is really present on the geometry that writes, so the
	// compiled path the front end checks is the path the game runs.
	//
	// One store per terrain vertex, not one per quad. Stained glass is the one
	// terrain material that stores nothing here and the note on the writer says
	// why; for every other terrain material the four vertices of a quad all
	// resolve to the same voxel, because the position used below is the block's
	// centre and not the vertex's own, so three of the four stores are repeats;
	// but other geometry is submitted as triangles, where no vertex is the first
	// of a run of four, and a light source that went unwritten would be a light
	// that does not exist for the fill. A wasted store is the cheaper mistake, and
	// a grid this size is small enough that it is not worth the risk.
#if defined(COLORED_LIGHTS) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
	// No voxel unless a branch below finds one. The fragment stage reads this for
	// stained glass, so it has to be defined on every path.
	lightVolumeVoxel = ivec3(-1);

	if (blockEntityId != 0) {
		LightVolumeWriteBlockEntity(cameraRelativePos.xyz);
	} else if (entityId != 0) {
		// An entity: no voxel. This safety net may be inert on this pack - see
		// case 2 - and when it is, cases 3 and 4 are what stop the write.
	} else if (any(notEqual(at_midBlock, vec3(0.0)))) {
		// Iris documents the block centre as `position + at_midBlock.xyz / 64.0`,
		// and this file already depends on that sign further up: at_midBlock.y is
		// negative for a vertex above the middle of its block, which is what the
		// water height test reads. Applied to the camera-relative vertex position
		// the shadow map works in, it gives the centre of the block this vertex
		// belongs to, and the grid wants one point per block rather than one per
		// vertex.
		vec3 blockCenter = cameraRelativePos.xyz + at_midBlock.xyz / 64.0;
		LightVolumeWriteTerrain(materialID, blockCenter);
	}
#endif
}
