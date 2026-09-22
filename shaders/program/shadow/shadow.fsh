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
const int R16_SNORM = 0;
const int shadowcolor0Format = R16_SNORM;

// The material table, for STAINED_GLASS, and the option that turns the tint
// below on and off. Uniforms: none
#include "/environment/materialIDs.glsl"

// The material list above is what decides which blocks tint the light, and the
// tint is the block's own texture, so this is only needed when the option is on.
#ifdef COLORED_SHADOWS
	// Sampled in the same space the world program shades in. Uniforms: none
	#include "/lib/srgb.glsl"

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
