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

in vec2 texcoord;
in float waterHeight;
flat in uint materialID;

uniform sampler2D gtexture;
uniform float alphaTestRef;

// TODO: Pick a better format. R16 is not in OpenGL 3, R16_SNORM is but might
// not be the best option.
//
// The value stored is waterHeight, above - the R channel is all of it, and the
// 1.0s written into the other three channels of gl_FragData[0] below are there
// because a vec4 has four of them, not because anything reads them.
const int R16_SNORM = 0;
const int shadowcolor0Format = R16_SNORM;

// The material table, for STAINED_GLASS, and the option that turns the tint
// below on and off. Uniforms: none
//
// What the table exposes to this program is STAINED_GLASS and, under
// COLORED_SHADOWS_PORTAL, NETHER_PORTAL. The option itself is a bare #define in
// that file, which is what makes it a switch - the rule is written down at the
// top of /lib/smaa.glsl.
#include "/environment/materialIDs.glsl"

// The palette the flood fill's filter voxels are coloured from, and the option
// that says whether the fill exists at all. Uniforms: none
#include "/environment/lighting/light_colors.glsl"

// The world image, for the filter voxel written below.
//
// The voxel is not computed in this stage. The vertex half of this program
// computes it - it is the stage that has the block centre - and passes it
// across, so LightVolumeCoord stays the one definition of the formula. What
// only this stage has is the block's texture, which is the colour the pane
// transmits.
#if defined(COLORED_LIGHTS) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
	// The voxel shadow.vsh put this block's centre in, or (-1, -1, -1) where it
	// stored nothing at all. Only terrain can be stained glass, so the fragment
	// below always finds either a voxel the writer already bounds-checked or that
	// sentinel, and it needs nothing else from the light volume module - not even
	// the grid's size.
	flat in ivec3 lightVolumeVoxel;

	// The write side of the image the fill reads. writeonly, because this stage
	// only stores into it, and the declaration matches the one in shadow.vsh,
	// which is the same uniform declared in the other stage of this program.
	layout(rgba16) uniform writeonly image3D light_volume_world;
#endif

// The sRGB decode, for the coloured-shadow tint below and for the filter
// voxel above. Sampled in the same space the world program shades in.
// Uniforms: none
#if defined(COLORED_SHADOWS) || (defined(COLORED_LIGHTS) && defined(IRIS_FEATURE_CUSTOM_IMAGES))
	#include "/lib/srgb.glsl"
#endif

#ifdef COLORED_SHADOWS
	// The buffer the colour of the light that passed through stained glass is
	// written into, which the world program reads back - see the note on
	// COLORED_SHADOWS in /environment/materialIDs.glsl.
	//
	// A buffer of its own rather than the spare channels of shadowcolor0, which
	// holds the water heights the caustics are built from: sharing it would mean
	// widening that buffer's format from R16_SNORM, and a height that is compared
	// against a fade of a sixteenth of a block cannot afford to lose a bit of its
	// sixteen.
	//
	// RGBA8 because this is a colour rather than a distance - eight bits per
	// channel is more than the R3_G3_B2 Mellow carries the same quantity in, and
	// the buffer costs 16 MiB at the default shadow map resolution of 2048 where
	// a sixteen bit format would cost 64.
	const int RGBA8 = 0;
	const int shadowcolor1Format = RGBA8;
#endif

void main() {
	vec4 surfaceColor = texture(gtexture, texcoord);

	if (surfaceColor.a < alphaTestRef) {
		discard;
		return;
	}

	// The stained-glass filter voxel.
	//
	// This is the only writer a stained-glass voxel has: the vertex stage
	// deliberately writes nothing at all for STAINED_GLASS, because the tint can
	// only be read from the pane's texture and this stage is the one holding it.
	// The filter state therefore has exactly one writer, and this is it.
	//
	// What would go wrong if a vertex store came back is worth writing down,
	// because it would look harmless: within one draw there is no ordering
	// between one primitive's vertex stage and another primitive's fragment
	// stage, so an "air" store from a later primitive's vertices could land
	// after this filter store and quietly erase it. The pane would then stop
	// tinting the fill, per block and per frame, with nothing to see in any
	// buffer - which is why LightVolumeWriteTerrain in shadow.vsh leaves
	// STAINED_GLASS out.
	//
	// The colour is normalised to its brightest channel. The fill multiplies the
	// light leaving this voxel by the rgb, so an unnormalised tint would dim it
	// as well, and a pale pane - which most stained glass is - would starve the
	// colour of the surfaces behind it while the lightmap still says they are
	// lit. Normalising keeps the hue, which is the part being asked for. The
	// floor under the division is what keeps a near-black pane from dividing by
	// a rounding error: a pane whose brightest channel is under it has almost no
	// colour to give, so the filter comes out dark and both tints and passes
	// very little, which is the honest answer for black glass.
	//
	// This reaches the panes the shadow pass draws. A pane it draws no fragment
	// for - outside the shadow map's coverage, or culled from the light's view -
	// keeps the frame's cleared air state and does not tint the fill: a
	// limitation of writing the filter out of the shadow map's own geometry, and
	// the alternative would be reading every pane's texture again inside the
	// fill itself.
	#if defined(COLORED_LIGHTS) && defined(IRIS_FEATURE_CUSTOM_IMAGES)
		if (materialID == STAINED_GLASS) {
			vec3 filterTint = SrgbToLinear(surfaceColor.rgb);
			float filterPeak = max(filterTint.r, max(filterTint.g, filterTint.b));
			filterTint /= max(filterPeak, 1.0e-4);

			// The writer leaves (-1, -1, -1) in the varying where it stored
			// nothing, and every voxel it did store is inside the grid by
			// construction, so the sentinel is the whole test.
			if (all(greaterThanEqual(lightVolumeVoxel, ivec3(0)))) {
				imageStore(light_volume_world, lightVolumeVoxel, vec4(filterTint, 0.5));
			}
		}
	#endif

	#ifdef COLORED_SHADOWS
		// Every fragment writes this buffer, not only the ones that have a colour
		// to give. White is the colour that leaves the direct light alone, and
		// letting the depth test decide which fragment gets to write is what makes
		// the tint follow occlusion rather than the outline of the shadow map:
		//
		// only the nearest surface along a light ray survives the depth test at a
		// texel. An opaque block between the sun and a pane is nearer than the
		// pane and is drawn before it, so that texel comes back white; a pane
		// between the sun and the ground is nearer than the ground and drawn after
		// it, so it overwrites the white with its own colour. A surface that reads
		// a colour here is therefore one the light really does reach through
		// glass, and one that reads white is not.
		//
		// Writing white rather than leaving the white the buffer was cleared to
		// also means the buffer cannot carry a colour over from the frame before,
		// when the shadow map was looking at a different part of the world.
		vec3 tintColor = vec3(1.0);

		// The alpha is not transparency: it says what kind of source put the
		// colour there, which the world program needs in order to treat the two
		// differently. 0.0 is a filter and 1.0 is an emitter; see ShadowMapping
		// for what it does with that, and NETHER_PORTAL_TINT in
		// /environment/materialIDs.glsl for why the two are not the same thing.
		float tintKind = 0.0;

		if (materialID == STAINED_GLASS) {
			// A filter: the colour of the light that gets through is the colour of
			// the pane, so the pane's own texture is exactly the right thing to
			// read it from, and a resource pack that recolours its glass recolours
			// the light with it.
			tintColor = mix(vec3(1.0), SrgbToLinear(surfaceColor.rgb), COLORED_SHADOWS_STRENGTH);
		}

		#ifdef COLORED_SHADOWS_PORTAL
			if (materialID == NETHER_PORTAL) {
				// An emitter: the colour is authored rather than sampled, for the
				// reasons written out on NETHER_PORTAL_TINT, and it is marked as an
				// emitter so that the world program can keep it off translucent
				// surfaces - a portal's own faces among them.
				tintColor = mix(vec3(1.0), NETHER_PORTAL_TINT, COLORED_SHADOWS_STRENGTH);
				tintKind = 1.0;
			}
		#endif

		gl_FragData[1] = vec4(tintColor, tintKind);
	#endif

/* DRAWBUFFERS:01 */
	gl_FragData[0] = vec4(waterHeight, 1.0, 1.0, 1.0);
}
