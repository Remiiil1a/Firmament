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

	// This frame's emitters and occluders, written here and read by the
	// propagation pass later in the same frame. writeonly is what this stage does
	// with it - the shadow pass is the only writer and the compute pass is the
	// only reader - and the loader clears it every frame (see its declaration in
	// shaders.properties), which is what makes "no vertex reached this voxel" mean
	// "nothing was drawn there this frame" rather than "nothing was drawn since
	// the pack loaded".
	layout(rgba16) uniform writeonly image3D light_volume_world;

	// What this voxel means to the fill.
	//
	// Three cases, in this order, and the order is the meaning. An emitter is
	// tested first so that a light source always gets its own colour into the
	// fill: a source whose voxel was marked solid would light nothing, because the
	// colour starts in this voxel and the fill spreads out of a voxel into its
	// neighbours. The alpha is "blocks light" - 1.0 is a solid block, 0.0 is air
	// or anything light passes through - which is not what alpha means anywhere
	// else in this pass, and is why the convention is written down once, here.
	void LightVolumeWriteWorld(uint material, vec3 centerCameraRelative) {
		ivec3 voxel = ivec3(floor(LightVolumeCoord(
			centerCameraRelative,
			fract(cameraPosition))));

		if (any(lessThan(voxel, ivec3(0)))
			|| any(greaterThanEqual(voxel, ivec3(LIGHT_VOLUME_SIZE)))) {
			return;
		}

		vec3 emitted = BlockLightColor(material);

		if (any(greaterThan(emitted, vec3(0.0)))) {
			imageStore(light_volume_world, voxel, vec4(emitted, 0.0));
			return;
		}

		// The materials light passes through. GLASS is on this list as well as
		// being culled from the shadow map at the end of main, and the two are not
		// the same statement: the cull says the map should hold no depth for a
		// pane, this says the fill should not treat it as a wall. Stained glass is
		// air here for the same reason - its colour belongs to the coloured
		// shadows, which read it from shadow.fsh, while this image carries only
		// what the flood fill should spread through.
		if (material == WATER || material == ICE || material == GLASS
			|| material == STAINED_GLASS || material == NETHER_PORTAL) {
			imageStore(light_volume_world, voxel, vec4(0.0));
			return;
		}

		// Everything else, leaves included: it blocks the fill and emits nothing.
		// Leaves are the interesting member of that set - they do not cast a
		// shadow in the game, but they do stop light, which is the question this
		// image is answering.
		imageStore(light_volume_world, voxel, vec4(0.0, 0.0, 0.0, 1.0));
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
	// One store per vertex, not one per quad. The four vertices of a terrain quad
	// all resolve to the same voxel, because the position used below is the
	// block's centre and not the vertex's own, so three of the four stores are
	// repeats; but other geometry is submitted as triangles, where no vertex is the
	// first of a run of four, and a light source that went unwritten would be a
	// light that does not exist for the fill. A wasted store is the cheaper
	// mistake, and a 64 cubed grid is small enough that it is not worth the risk.
#if defined(COLORED_LIGHTS) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
	// Iris documents the block centre as `position + at_midBlock.xyz / 64.0`, and
	// this file already depends on that sign further up: at_midBlock.y is negative
	// for a vertex above the middle of its block, which is what the water height
	// test reads. Applied to the camera-relative vertex position the shadow map
	// works in, it gives the centre of the block this vertex belongs to, and the
	// grid wants one point per block rather than one per vertex.
	vec3 blockCenter = cameraRelativePos.xyz + at_midBlock.xyz / 64.0;
	LightVolumeWriteWorld(materialID, blockCenter);
#endif
}
