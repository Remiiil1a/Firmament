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

// Generic material without special effects
const uint GENERIC = 0u;

// Connected Waving + Subsurface Scattering (Leaves)
const uint LEAVES = 1u;

// Disconnected Waving + Subsurface Scattering (Ground Foliage)
const uint GROUND_FOLIAGE = 2u;

// Subsurface Scattering Only No Waving
const uint SUBSURFACE_SCATTERING = 3u;

// Water
const uint WATER = 4u;

// Ice
const uint ICE = 5u;

// Blocks that do not cast shadows (Glass and translucents)
const uint GLASS = 6u;

// Light-emitting blocks, grouped by the color of the light they give off.
//
// The colors are in /environment/lighting/light_colors.glsl, and the blocks
// that belong to each family are listed in block.properties.
//
// What this can and cannot do is worth being precise about. Minecraft's light
// map records how much light reaches a position, but not which block it came
// from or what color it was, so a surface cannot look up the color of whatever
// is lighting it. An emitter's own faces are the one place where the source is
// known - the block being shaded is the block that glows - so that is where
// these are used, to give each source its own color instead of leaving it to
// the average color of its texture. Everything further away is approximated in
// /program/post/light_bleed.fsh.
//
// Note that these IDs are only about color. Whether a face actually glows is
// still decided by the light map, so an unlit furnace that shares a family with
// a lit one does not glow.
const uint LIGHT_WARM = 7u;        // Torches, lanterns, glowstone, furnaces, fire
const uint LIGHT_SOUL = 8u;        // Soul torches, soul lanterns, soul fire
const uint LIGHT_REDSTONE = 9u;    // Redstone torches, redstone lamps
const uint LIGHT_LAVA = 10u;       // Lava, magma
const uint LIGHT_SEA = 11u;        // Sea lanterns, conduits, beacons
const uint LIGHT_END_ROD = 12u;    // End rods, end gateways
const uint LIGHT_CRYING = 13u;     // Crying obsidian, sculk catalysts
const uint LIGHT_AMETHYST = 14u;   // Respawn anchors, enchanting tables

// Stained glass, in every colour, along with its panes and tinted glass.
//
// Deliberately a material of its own rather than another entry in GLASS: stained
// glass casts a shadow, and that shadow is what carries the colour of the light
// passing through it (see the colored shadow code in the shadow program and in
// light_colors.glsl). Adding it to GLASS, which exists precisely to mark the
// materials that do not cast shadows, would take that away.
//
// What it does share with GLASS is being a transparent surface with a specular
// response of its own, which is what this ID is here to let the translucent
// lighting treat it the same way.
const uint STAINED_GLASS = 15u;

// Geometry selector: Diagonally horizontal geometry
// Add 16 to any material ID to apply this geometry selector
const uint GEOMETRY_HORIZONTAL_DIAGONAL_ONLY = 1u;

// Standard Iris / OptiFine: IDs in block.properties via mc_Entity.x
uint DecodeMaterialID(float mc_EntityX) {
	return uint(max(0.0, mc_EntityX - 10000.0));
}

// Voxy: IDs in block.properties via VoxyFragmentParameters.customId
uint DecodeMaterialID(uint customId) {
	return customId > 10000u ? customId - 10000u : 0u;
}
