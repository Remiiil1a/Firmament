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
// Uniforms: dimension, biome_category - as uniforms here; in a program that
// declares EXTERNALLY_DEFINED_UNIFORMS the file reads the dimension from the
// pack's own voxyDimension uniform instead, and supplies the category as a
// constant (BATCH_LOG.md b507).
#include "/environment/dimension.glsl"

uniform sampler2D gtexture;

in vec4 tinting;
in vec2 texcoord;

void main() {
	// End debug: paint everything this program draws in a flat color, so that an
	// effect whose program is not known can be traced to the program that draws
	// it by looking at what color it turns. See END_DEBUG in
	// /environment/dimension.glsl.
	//
	// At this point in the file the guard says something narrower than the
	// option. END_DEBUG is an Iris option and never a #define in this pack, and
	// its value is 0 or 1 either way, so the left-hand test is the option and
	// nothing else. END_DEBUG_TINT is the half that is checked: it is a macro
	// this program does not define, and the programs that do - see
	// gbuffers_block.fsh for one - are the ones that set this program's flat
	// color. Written without `defined(END_DEBUG_TINT)` the body would compile
	// against a name the preprocessor has never seen.
	//
	// At this point in the file the guard says something narrower than the
	// option. END_DEBUG is an Iris option and never a #define in this pack, and
	// its value is 0 or 1 either way, so the left-hand test is the option and
	// nothing else. END_DEBUG_TINT is the half that is checked: it is a macro
	// this program does not define, and the programs that do - see
	// gbuffers_block.fsh for one - are the ones that set this program's flat
	// color. Written without `defined(END_DEBUG_TINT)` the body would compile
	// against a name the preprocessor has never seen.
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
			// Only what is far away is dropped - at this point in the file the
			// test is gl_FragCoord.z > 0.99 - because these programs also draw
			// things worth keeping near the player. See the same check in
			// /program/world/lit.fsh for what the depth test means.
			//
			// Nothing defines SUPPRESS_END_FLASH and includes this file: it is
			// defined in gbuffers_weather.fsh alone, which includes lit.fsh, so
			// the copy here is dead as the pack stands. That is a code question,
			// recorded and not touched; see the same note in
			// /environment/dimension.glsl.
			//
			// Also note what this #if guard can see. SUPPRESS_END_FLASH is a
			// plain #ifdef, so it is a switch only where it is defined, and
			// MC_VERSION is not defined by every version the pack supports:
			// with it undefined the removal runs.
			if (EndDimension() && gl_FragCoord.z > 0.99) {
				discard;
			}
		#endif
	#endif

	vec4 srgb = tinting * texture(gtexture, texcoord);
	vec4 fragmentColor = SrgbToLinear(srgb);
	fragmentColor.rgb *= UNLIT_BRIGHTNESS;

	// Whether to keep only the part of this that is drawn at full opacity, which
	// is what the beacon beam's program asks for and what its own note explains.
	//
	// The test is on the alpha this fragment is about to be drawn with, which is
	// the vertex colour's own: the beam's texture carries no transparency at all
	// (every one of its 256 texels is alpha 255), so the soft edge of the beam is
	// the part of its geometry whose vertex colour is under one and its opaque
	// middle is the part where it is exactly one.
	//
	// Written with `#if defined` rather than `#ifdef`, so that it stays a switch
	// the program that wants it sets rather than a boolean option Iris registers:
	// it is not a setting, and a bare `#ifdef` on a name would put a checkbox in
	// the shader menu for it. Nothing else includes this file with it defined.
	#if defined(DROP_TRANSLUCENT_FRAGMENTS)
		if (fragmentColor.a < 0.999) {
			discard;
		}
	#endif

/* DRAWBUFFERS:0 */
	gl_FragData[0] = fragmentColor;
}
