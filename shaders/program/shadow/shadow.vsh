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
}
