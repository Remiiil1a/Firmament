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
// Deliberately a material of its own rather than another entry in GLASS: the
// colour of the light that passes through stained glass is what stained glass is
// for, and it is a colour this pack has to be able to look up, which it could
// not do if these blocks were culled from the shadow pass the way GLASS is.
// Adding it to GLASS, which exists precisely to mark the materials that do not
// cast shadows, would take that away.
//
// What it does share with GLASS is being a transparent surface with a specular
// response of its own, which is what this ID is here to let the translucent
// lighting treat it the same way.
const uint STAINED_GLASS = 15u;

// The nether portal, which is the one block that gets an ID here without being
// a material the world programs can be told about.
//
// The number is the whole story. It has to be a material of its own because the
// shadow program is what has to recognise it, and the shadow program is the one
// place in this pack that reads mc_Entity.x raw instead of asking lit.vsh what
// it means. What lit.vsh does with it is the opposite: the portal is drawn in
// the translucent pass and arrives there as an unlisted block, which this pack
// has always called GLASS - see the demotion at the top of FetchMaterialID - and
// that is the material it has to keep having, because the alternative is a
// portal that shades like something else.
//
// 38 is 32 + 6, and both halves are chosen:
//
//  * the low four bits, 6, are GLASS, which is the material the portal already
//    had and the only value the fragment stage will ever see it as - lit.vsh
//    packs the material into four bits on its way there, through EncodePerFace
//    in /lib/encoding/face.glsl. Numbering it this way means the portal decodes
//    to the right material by construction, whether or not anything else
//    recognises the name.
//  * the bits above them are the geometry selector's field, where this pack
//    defines exactly one value, 1 (the +16 the diagonal selector adds). 2 is
//    nothing at all, so a 38 is not a variant of GLASS - it is a slot of its
//    own, and no block.properties entry in this pack has ever used one.
//
// Nothing else is allowed to point at it: it is not a filter, it is not a
// material the lit path branches on, and everything that is not the shadow
// program's tint buffer is expected to keep treating the portal exactly as it
// treats an unlisted translucent. See FetchMaterialID in lit.vsh for the one
// line that says so, and block.properties for the block itself.
const uint NETHER_PORTAL = 38u;

// The colour of the nether portal's glow, which is the colour the light under a
// portal is tinted with.
//
// Authored here rather than sampled from the portal's texture, which is the one
// place this departs from what stained glass does, and the departure is the
// point: a pane of stained glass is a filter, so the colour of the light that
// gets through it really is the colour of the pane's own texture, while the
// portal is a light source, and this pack already has a rule about those. Read
// the head of /environment/lighting/light_colors.glsl: "a torch's texture is
// mostly a brown stick, and its light is not brown". A portal is the same case,
// with a texture that darkens and flickers as its animation runs - and a patch
// of ground that dimmed and brightened with it would read as a light leak rather
// than as light.
//
// The peak channel is 1.0, so no channel of the sunlight that lands under a
// portal is amplified, and the rest is the hue of a portal: what survives is a
// violet about a third as bright as the ground it falls on, which is what a
// saturated colour costs. Raise COLORED_SHADOWS_STRENGTH's complement - lower it
// - to keep more of the light and less of the colour.
const vec3 NETHER_PORTAL_TINT = vec3(0.60, 0.20, 1.0);

// Whether the light that has passed through stained glass arrives coloured, so
// that a red pane puts a red patch of sunlight on the floor rather than a
// shadow with a hole in it. Also the switch for the nether portal's own glow -
// see COLORED_SHADOWS_PORTAL below for turning that off on its own.
//
// The colour travels in shadowcolor1, a buffer of its own rather than part of
// shadowcolor0, which holds the water heights the caustics are built from and
// which this therefore does not touch at any setting. The shadow program writes
// it (see /program/shadow/shadow.fsh) and the world program reads it back while
// it shades a surface (see /environment/lighting/shadowmap.glsl).
//
// What makes the feature safe to leave on is that white is the value that means
// "nothing coloured is in the way", and white is both what the buffer clears to
// and what every fragment that is not a colour source writes into it. A scene
// with no stained glass and no portal in it therefore reads back 1.0 everywhere
// and multiplies the direct light by exactly 1.0, which is a no-op down to the
// last bit.
#define COLORED_SHADOWS

#ifdef COLORED_SHADOWS
	// How much of the colour the light picks up, where 0.0 leaves the light as
	// it was and 1.0 gives it the full colour of its source.
	//
	// At 1.0 a pane of black stained glass puts the floor under it in the dark,
	// which is what black glass does - and the portal puts a violet on it. Lower
	// values keep the light and only take on the hue, which is closer to what
	// Mellow and Sundial settle on, and is the setting to reach for if the
	// patches look too saturated to sit alongside everything else in the scene.
	#define COLORED_SHADOWS_STRENGTH 1.0 // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

	// Whether a nether portal tints the light around it with the colour of its
	// own glow, which is the same colour the light under a pane of stained glass
	// gets, from the same buffer, and switched separately because it is a
	// different kind of thing.
	//
	// A portal is not a filter. It is a light source standing in a frame, its
	// texture animates, and the light that lands under one was never going
	// through anything - so the colour is authored rather than sampled (see
	// NETHER_PORTAL_TINT above), and a portal's glow is deliberately kept off
	// translucent surfaces, which is what stops a portal from colouring its own
	// faces and what "standing inside one should not tint you from the inside"
	// amounts to. See the write in /program/shadow/shadow.fsh for how the two
	// kinds of source are told apart in the buffer.
	#define COLORED_SHADOWS_PORTAL
#endif

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
