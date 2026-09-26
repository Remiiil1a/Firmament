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

// Modified 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

#include "/lib/srgb.glsl"

// Which dimension this is, for the two checks below.
// Uniforms: dimension, biome_category
#include "/environment/dimension.glsl"

uniform sampler2D gtexture;

in vec4 tinting;
in vec2 texcoord;

void main() {
	// End debug: paint everything this program draws in a flat color, so that an
	// effect whose program is not known can be traced to the program that draws
	// it by looking at what color it turns. See END_DEBUG in
	// /environment/dimension.glsl.
	#if defined(END_DEBUG) && defined(END_DEBUG_TINT)
		if (EndDimension()) {
			gl_FragData[0] = vec4(END_DEBUG_TINT, 1.0);
			return;
		}
	#endif

	#if defined(SUPPRESS_END_FLASH)
		#if !defined(MC_VERSION) || MC_VERSION >= 12109
			// The End's light flash (Minecraft 1.21.9) is drawn as a quad in the
			// sky with no texture that the mod knows to bind, so it samples the
			// block atlas and shows up as a patch of a random block's texture.
			// There is nothing to be done with it from here, so it is dropped.
			//
			// Unconditional as of batch 333; it used to sit behind the removed
			// option HIDE_END_FLASH. See the note in /environment/dimension.glsl.
			//
			// Only what is far away is dropped, because these programs also draw
			// things worth keeping near the player. See the same check in lit.fsh
			// for what the depth test means.
			if (EndDimension() && gl_FragCoord.z > 0.99) {
				discard;
			}
		#endif
	#endif

	vec4 srgb = tinting * texture(gtexture, texcoord);
	vec4 fragmentColor = SrgbToLinear(srgb);
	fragmentColor.rgb *= UNLIT_BRIGHTNESS;

/* DRAWBUFFERS:0 */
	gl_FragData[0] = fragmentColor;
}
