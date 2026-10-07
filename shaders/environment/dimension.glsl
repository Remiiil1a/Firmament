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
// The End is where nearly all of it is spent - a sky, a light, a fog, and the
// removal of a vanilla effect that does not survive being shadered - so the
// question is mostly "is this the End". The Nether is asked about for one thing
// only, the plumes in /environment/effects/volumetric_fog.glsl, and neither
// question changes anything else in the pack.
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
	// A program whose uniforms come from somewhere else cannot be given the
	// shader mod's own dimension uniform: Voxy's terrain draws into its own
	// buffers, and Iris hands that pipeline a fixed set of uniforms which does
	// not include `dimension`. It IS told which dimension it is in - through one
	// of this pack's own uniforms, which that pipeline does carry. See
	// VoxyDimensionValue below and BATCH_LOG.md b507.
	//
	// ⚠️⚠️ Batches 348 and 349 both tried to give this an answer, and both are
	// recorded here so that neither is tried again.
	//
	// Batch 348 answered it at compile time, with a per-dimension voxy.json that
	// defined a macro and included the shared one - a shape copied from another
	// pack. Voxy answered with "Failed to parse patch data gson, dumping json".
	// It reads those files as JSON, and neither of the two packs that do use
	// per-dimension files includes the root voxy.json, which is what this pack
	// has. Whether the shape is possible at all was never established, because
	// the shape that was tried had that mistake in it.
	//
	// Batch 349 answered it with a uniform instead, adding "dimension" to
	// voxy.json's "uniforms" array. ⚠️ That array is not a list of names a pack
	// may ask for: it is the subset of a fixed set that Voxy knows how to fill,
	// and dimension is not in it. Voxy said so outright -
	//
	//     [IrisVoxyRenderPipelineData]: The following uniforms could not be
	//     found: [dimension]
	//     0(3989) : error C1503: undefined variable "dimension"
	//
	// - and then failed to compile its patched pipeline in EVERY dimension and
	// fell back to the unpatched one, which is why level-of-detail terrain
	// stopped matching the pack at all. So: an unsupported name here is worse
	// than a missing one. A name the array does not list and this file declares
	// reads zero; a name the array lists but Voxy cannot fill is not declared at
	// all, and every use of it fails to compile.
	//
	// ⚠️⚠️ Batch 351 tried a third route - the per-dimension file done the way
	// the packs that support Voxy do it, with the real Voxy programs moved into
	// a subfolder and thin shims at the root and in world1/ carrying the flag as
	// a macro - and it broke the End outright: every block vanished and the sky
	// went to noise.
	//
	// ⚠️ The reason is worth more than the attempt. A shaders/world1/ folder is
	// not "some programs for this dimension". Once it exists, Iris takes it as
	// the End's program set, and the programs it does not contain stop working
	// there. That is why the packs that use this mechanism ship a shim for EVERY
	// program in that folder - around sixty files - and it is the thing to
	// notice before adding one: a folder holding two files disables the other
	// forty. Reverted in batch 352.
	//
	// ⚠️ So this is not "untested". Batches 348, 349 and 351 all tried, and all three are
	// recorded above so that none of them is tried again.
	//
	// ✅ Batch 507 found the way out that the note above asks for: not through
	// shaders/world1, and not by asking for a STANDARD uniform - but by asking for one
	// of this pack's OWN, which is what the forty names already in voxy.json are.
	// `voxyDimension` is computed in shaders.properties, where `dimension` is real, and
	// arrives here as -1.0 the Nether, 1.0 the End, 0.0 anywhere else. The three
	// questions below read it instead of the constant, and the constant is gone.
	//
	// ⚠️ It must NOT be declared here: the names in voxy.json are declared BY the patch,
	// and declaring one again is the duplicate-declaration mistake batch 291's first
	// version made with `lightmap`.
	//
	// ⚠️ And END_BIOME_CATEGORY is defined below this block, so the category cannot be
	// compared here: 0 is what this branch has for it, and 0 is not the End's.
	float VoxyDimensionValue() {
		return voxyDimension > 0.5 ? 1 : (voxyDimension < -0.5 ? -1 : 0);
	}
	#define DIMENSION_IS_END (VoxyDimensionValue() == 1)
	#define DIMENSION_IS_NETHER (VoxyDimensionValue() == -1)
	const int biome_category = 0;
#else
	uniform int dimension;
	uniform int biome_category;
	#define DIMENSION_IS_END (dimension == 1)
	#define DIMENSION_IS_NETHER (dimension == -1)
#endif

// The End's biome category, which is the value of the game's own biome category
// enum: the categories in order are none, taiga, extreme hills, jungle, mesa,
// plains, savanna, icy, the End, beach, forest, ocean, desert, river, swamp,
// mushroom, nether, making the End the ninth.
#define END_BIOME_CATEGORY 8

// The Nether's, from the same enum, where it is the seventeenth and last.
//
// Two things are decided by this. The cloud layer keeps out of the Nether - see
// CloudDimension in /environment/clouds/volumetric.glsl, which tests this
// constant directly, for why the dimension uniform alone is not enough to ask -
// and NetherDimension() below reads it, which is how the Nether's plumes ask
// their question in /program/post/volumetric_fog.fsh.
#define NETHER_BIOME_CATEGORY 16

// Whether this is the End, as the shader mod reports it.
//
// This is the End question for everything the pack does there except the sky.
// Where what is being decided is which sky SkyColor returns, the question is
// EndSkyDimension() below instead - this, plus the END_SKY option - and that is
// what /environment/sky.glsl, gbuffers_skytextured.fsh and the End's water
// reflection in /environment/lighting/translucent.glsl ask. The debug view
// further down reports the two raw checks rather than either predicate.
//
// This itself does not depend on END_SKY: that option is about which sky to
// draw, and turning a sky off should not also turn off the dimension's light or
// bring back an effect that does not work under a shader.
bool EndDimension() {
	return DIMENSION_IS_END || biome_category == END_BIOME_CATEGORY;
}

// Whether this is the Nether.
//
// Added in batch 342, and asked exactly the way the End is asked: the dimension
// itself is -1, and every biome in the Nether reports the Nether's category. The
// two are mutually exclusive, which is why neither needs to check the other.
//
// ⚠️ Its one consumer is the Nether's plumes: /program/post/volumetric_fog.fsh
// asks it once per pixel, under #ifdef NETHER_PLUMES. That the route there is a
// pass over the finished frame is the whole point of the history below.
//
// Recorded, in the order it happened. Batch 342's first use of this was a
// distance haze in fog.glsl, and batch 343 took that back out: a haze uniform in
// distance is the wrong shape for this dimension, and the user's verdict on it
// was that the Nether's atmosphere came out strange - worst of all against
// Distant Horizons and Voxy, whose terrain is compiled with
// EXTERNALLY_DEFINED_UNIFORMS, which until b507 that path was told it was not in
// the Nether at all, so the fog stopped at the boundary between their chunks and
// the game's. (b507 gave that path the dimension, so a haze there could work
// today; it was still taken out, because a haze uniform in distance is the wrong
// shape for this dimension - see BATCH_LOG.md 343.)
// What replaced it is the volumetric plume field, which is drawn over the
// finished frame and so cannot have that seam. See BATCH_LOG.md 201.
bool NetherDimension() {
	return DIMENSION_IS_NETHER || biome_category == NETHER_BIOME_CATEGORY;
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
// Red is the dimension uniform's own test and green the biome category's; blue
// is EndDimension() above, the pack's verdict, rather than EndSkyDimension(), so
// that it answers "is this the End" rather than "would the sky be drawn".
vec3 EndDebugColor() {
	return vec3(
		DIMENSION_IS_END ? 1.0 : 0.0,
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
	// Encloses no code: EndDebugColor above is used by SkyColor in
	// /environment/sky.glsl, which asks for it under this same guard. The block
	// is here so that END_DEBUG is also tested with #ifdef in this file, which
	// the files that only write #if defined(END_DEBUG) do not do. Recorded, not
	// established: whether the option system needs that test here has not been
	// traced.
#endif

// The End's light flash - which Minecraft 1.21.9 and up draws as a second sun
// in the End's sky - is always dropped.
//
// Recorded as the finding it was, since nothing here can re-derive it: it does
// not survive being shadered, because it is a textured quad the mod has no
// binding for, so it ends up sampling whatever texture was left bound - the
// block atlas - and shows up as a patch of some random block's texture in the
// sky. Nothing can be done with it from here: it is not the pack's sky and the
// pack cannot light it, so it is dropped rather than kept.
//
// Recorded: this used to be an option, HIDE_END_FLASH, and batch 333 removed the
// switch and made the removal unconditional, on the user's report that turning
// it on or off made no visible difference and that the flash is not wanted
// either way. What the code here can say about that is the shape of composite1's
// overwrite: the End's sky is drawn by gbuffers_skytextured.fsh through SkyColor,
// and composite1.fsh then writes the sky again over any pixel in the End whose
// depthtex0 is exactly 1.0 - the far plane, where nothing wrote depth - so a
// flash quad left at that depth is overwritten whether this ran or not, and one
// that wrote a nearer depth is not. That nearer case is what the removal covers.
//
// ⚠️ The removal is written in lit.fsh and unlit.fsh, but only lit.fsh's copy is
// compiled by anything in the pack: SUPPRESS_END_FLASH is defined in exactly one
// place, gbuffers_weather.fsh, which includes lit.fsh. Nothing defines it and
// includes unlit.fsh, so the copy there is dead as the pack stands. That is a
// code question, reported and not touched.
//
// The version test kept around it reads !defined(MC_VERSION) || MC_VERSION >=
// 12109, so it holds the removal back only on a version that reports itself as
// older than 1.21.9: with MC_VERSION undefined the removal does run. See
// BATCH_LOG.md 189.

#endif /* DIMENSION_INCLUDED */
