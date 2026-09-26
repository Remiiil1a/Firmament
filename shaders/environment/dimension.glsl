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

// Added 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

// Which dimension the player is in, as far as the pack needs to know.
//
// Only the End gets anything of its own - a sky, a light, a fog, and the
// removal of a vanilla effect that does not survive being shadered - so this is
// really just "is this the End", and everything else in the pack is unchanged.
//
// There is more than one way to ask, and no single one works everywhere, so
// both are asked. The dimension itself is the direct answer: 0 for the
// overworld, -1 for the nether, 1 for the End. Where that is not available, the
// category of the biome the player is standing in answers it just as well,
// because every biome in the End reports the End's category and nothing else
// does.
//
// A mod that provides neither leaves both at 0, which reads as "not the End".
// That is deliberate: the failure is an End sky that does not appear, never a
// space sky over the overworld.

#ifndef DIMENSION_INCLUDED
#define DIMENSION_INCLUDED

// Which dimension gets the End's sky, light and fog.
//
// AUTO is what almost everyone wants. ALWAYS and OFF are for checking the
// effect - ALWAYS draws it everywhere, which is the quickest way to confirm it
// works at all, and OFF turns it off without giving up the rest of the pack if
// you would rather keep the End you had.
#define END_SKY_AUTO 0
#define END_SKY_ALWAYS 1
#define END_SKY_OFF 2
#define END_SKY END_SKY_AUTO // [END_SKY_AUTO END_SKY_ALWAYS END_SKY_OFF]

#if defined(EXTERNALLY_DEFINED_UNIFORMS)
	// A program whose uniforms come from somewhere else cannot be given new
	// ones, so it is told it is not in the End. That is Voxy's terrain, which
	// draws into its own buffers and does not use this pack's sky.
	const int dimension = 0;
	const int biome_category = 0;
#else
	uniform int dimension;
	uniform int biome_category;
#endif

// The End's biome category, which is the value of the game's own biome category
// enum: the categories in order are none, taiga, extreme hills, jungle, mesa,
// plains, savanna, icy, the End, beach, forest, ocean, desert, river, swamp,
// mushroom, nether, making the End the ninth.
#define END_BIOME_CATEGORY 8

// The Nether's, from the same enum, where it is the seventeenth and last.
//
// Nothing the pack does is decided by this except that the cloud layer keeps out
// of the Nether - see CloudDimension in /environment/clouds/volumetric.glsl for
// why the dimension uniform alone is not enough to ask.
#define NETHER_BIOME_CATEGORY 16

// Whether this is the End, as the shader mod reports it.
//
// Everything the pack does for the End is decided by this and nothing else. In
// particular it does not depend on END_SKY: that option is about which sky to
// draw, and turning a sky off should not also turn off the dimension's light or
// bring back an effect that does not work under a shader.
bool EndDimension() {
	return dimension == 1 || biome_category == END_BIOME_CATEGORY;
}

// Whether this is the Nether.
//
// Added in batch 342, and asked exactly the way the End is asked: the dimension
// itself is -1, and every biome in the Nether reports the Nether's category. The
// two are mutually exclusive, which is why neither needs to check the other.
//
// ⚠️ It has no consumer at the moment, and that is deliberate rather than an
// oversight. Batch 342's first use of it was a distance haze in fog.glsl, and
// batch 343 took that back out: a haze uniform in distance is the wrong shape
// for this dimension, and the user's verdict on it was that the Nether's
// atmosphere came out strange - worst of all against Distant Horizons and Voxy,
// whose terrain is compiled with EXTERNALLY_DEFINED_UNIFORMS and is therefore
// told it is not in the Nether at all, so the fog stopped at the boundary
// between their chunks and the game's. What replaces it is a volumetric plume
// field, which is drawn over the finished frame and so cannot have that seam.
// See NETHER_PLUMES_PLAN.md.
bool NetherDimension() {
	return dimension == -1 || biome_category == NETHER_BIOME_CATEGORY;
}

// Whether to draw the End's sky. Same question, plus the option that can force
// the answer either way.
bool EndSkyDimension() {
	#if END_SKY == END_SKY_OFF
		return false;
	#elif END_SKY == END_SKY_ALWAYS
		return true;
	#else
		return EndDimension();
	#endif
}

// What the two checks actually returned, as a color. See END_DEBUG.
//
// Blue reports the dimension check itself rather than the sky option, so that
// it answers "is this the End" rather than "would the sky be drawn".
vec3 EndDebugColor() {
	return vec3(
		dimension == 1 ? 1.0 : 0.0,
		biome_category == END_BIOME_CATEGORY ? 1.0 : 0.0,
		EndDimension() ? 1.0 : 0.0);
}

// Whether to replace the sky with a report of what the two checks above
// actually returned.
//
// The two ways of asking are not equally available on every version, and there
// is no way to find out which of them works from here - a uniform the shader
// mod does not provide reads as 0, which is indistinguishable from "not the
// End". This turns the answer into a color, in the sky where it is easy to see:
//
//     red    the dimension uniform says 1
//     green  the biome category says the End
//     blue   the pack thinks this is the End
//
// So turning this on in the End gives white if both work, magenta or cyan if
// only one does, and black if neither does. Outside the End, red and green
// should be black and the sky should look normal.
//#define END_DEBUG
#ifdef END_DEBUG
	// Used by SkyColor in sky.glsl.
#endif

// The End's light flash - which Minecraft 1.21.9 and up draws as a second sun
// in the End's sky - is always dropped.
//
// It does not survive being shadered: it is a textured quad that the mod has no
// binding for, so it ends up sampling whatever texture was left bound - the
// block atlas - and shows up as a patch of some random block's texture in the
// sky. Nothing can be done with it from here: it is not the pack's sky and the
// pack cannot light it, so it is dropped rather than kept.
//
// This used to be an option, HIDE_END_FLASH. Batch 333 removed the switch and
// made the removal unconditional, on the user's report that turning it on or
// off made no visible difference and that the flash is not wanted either way.
// That matches what the code says: the End's sky is replaced by
// gbuffers_skytextured.fsh and then the whole sky is written again in
// composite1, so the quad is overwritten whether this ran or not - the switch
// was never what was hiding it.
//
// The removal itself is in lit.fsh and unlit.fsh, and only for the programs
// that draw the flash - each of those defines SUPPRESS_END_FLASH. The
// Minecraft 1.21.9 version check is kept, so that this cannot remove anything
// on a version that has no flash at all. See PBR_PORTING.md 189.

#endif /* DIMENSION_INCLUDED */
