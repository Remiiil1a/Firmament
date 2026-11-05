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

// --- portal surfaces -------------------------------------------------------
//
// These live here rather than beside the code that reads them because BOTH stages
// need them. The pattern is built from a position the vertex stage interpolates,
// so the two stages have to agree on whether that varying exists at all - and a
// file only one stage includes cannot say so.
//
// THREE SWITCHES, ONE PER SURFACE (batch 617). They were one option, which made the
// pack all-or-nothing: an author who disliked the nether gate lost the end one with
// it. A surface whose look is a matter of taste should be switchable on its own.
//
// PORTAL_LIGHT additionally lets any enabled portal's colour spread onto what stands
// around it; it is off by default because it changes the light of the room, not just
// the look of the door. PORTAL_DEBUG paints all three flat so that the identification
// can be checked in game.
//
// THE NETHER GATE IS OFF BY DEFAULT (batch 620, the author's setting, not a defect).
// The end surfaces are on: they are the ones the author is shipping. A default-off
// boolean is spelt the way Iris reads one - commented out - and the #ifdef above
// the code is what makes it an option rather than dead text.
//#define PORTAL_NETHER
#define PORTAL_END
#define PORTAL_GATEWAY
//#define PORTAL_LIGHT
//#define PORTAL_DEBUG

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

// Blocks that do not cast shadows: glass, its panes, and fire, which is what
// block.properties gives this ID. "Glass and translucents" is how the rest of the
// pack refers to it - it is the material an unlisted translucent is handed - but
// it does not cover every translucent surface: stained glass was taken out of it
// deliberately, below.
const uint GLASS = 6u;

// Light-emitting blocks, grouped by the color of the light they give off.
//
// The colors are in /environment/lighting/light_colors.glsl, and the blocks
// that belong to each family are listed in block.properties.
//
// What this can and cannot do is worth being precise about. Minecraft's light
// map records how much light reaches a position, but not which block it came
// from or what color it was, so a surface cannot look up the color of whatever
// is lighting it. An emitter's own faces are the one place where a block's ID is known to
// the fragment stage, and these families used to be read only there and by the
// light bleed in /program/post/light_bleed.fsh. Since batch 696 they are also
// the flood fill's emitter list: /environment/lighting/light_volume.glsl
// carries the same colors through a voxel grid, and a block that is in no
// family is a wall to that fill rather than a source - which is why the list
// now includes blocks whose own texture is already the color they glow.
//
// Note that these IDs are only about color. Whether a face actually glows is
// still decided by the light map, so an unlit furnace that shares a family with
// a lit one does not glow.
const uint LIGHT_WARM = 7u;        // Torch, lantern, glowstone, jack o'lantern, shroomlight, furnaces
const uint LIGHT_SOUL = 8u;        // Soul torches, soul lanterns, soul fire
const uint LIGHT_REDSTONE = 9u;    // Redstone torches, redstone lamps
const uint LIGHT_LAVA = 10u;       // Lava, magma
const uint LIGHT_SEA = 11u;        // Sea lanterns, conduits, beacons
const uint LIGHT_END_ROD = 12u;    // End rods, end gateways
const uint LIGHT_CRYING = 13u;     // Crying obsidian, sculk catalysts
const uint LIGHT_AMETHYST = 14u;   // Respawn anchors, enchanting tables, amethyst clusters and large buds

// The light families added in batch 697.
//
// Their block.properties numbers are 10040 to 10043, which is ID 40 to 43: the
// high nibble is the geometry selector and 2 is a selector this pack does not
// define, so the whole number survives to whoever reads it instead of being
// decoded into a variant of another material. That slot is the one the nether
// portal has always used, and a light family has to live above 31 for a reason
// worth writing down: 16 to 31 are selector 1, the diagonal one, and lit.vsh
// answers GLASS or GENERIC for faces of a number in that range, which is not
// what a light source is allowed to look like in the gbuffers stage.
//
// Their own surfaces deliberately do not take these colors: a froglight is
// already the color it glows and a copper torch draws a green flame of its own.
// FetchMaterialID in lit.vsh reduces these four numbers to GENERIC before
// EncodePerFace can keep only their low nibble and hand the fragment stage a
// different family's color; see the note there. The observable trade of that
// reduction is worth stating: these blocks' own faces keep the texture look
// they have always had (which for a froglight is its glow and for a copper
// torch is a green flame), while the shadow program decodes the raw number and
// does see the family, so the flood fill still emits the right color from the
// same block. The faces and the light are coloured by different answers because
// the fragment stage cannot carry a number above 15 while the shadow program
// reads the number raw.
const uint LIGHT_FROGLIGHT_OCHRE = 40u;       // Ochre froglight
const uint LIGHT_FROGLIGHT_VERDANT = 41u;     // Verdant froglight
const uint LIGHT_FROGLIGHT_PEARLESCENT = 42u; // Pearlescent froglight
const uint LIGHT_COPPER = 43u;                // Copper torches and copper lanterns, every oxidation state

// Stained glass, in every colour, along with its panes and tinted glass.
//
// Deliberately a material of its own rather than another entry in GLASS: the
// colour of the light that passes through stained glass is what stained glass is
// for, and it is a colour this pack has to be able to look up, which it could
// not do if these blocks were culled from the shadow pass the way GLASS is -
// GLASS is thrown out of the map in shadow.vsh by sending its vertices to
// -1.0, which culls the primitive. Nothing does that to this ID.
// Adding it to GLASS, which exists precisely to mark the materials that do not
// cast shadows, would take that away.
//
// What it does share with GLASS is being a transparent surface with a specular
// response of its own, which is what this ID is here to let the translucent
// lighting treat it the same way - see translucent.glsl, which tests the two
// together.
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
// * the low four bits, 6, are GLASS, which is the material the portal already
// had and the only value the fragment stage will ever see it as. Two lines
// say so, and both are needed: in a program that defines TRANSLUCENT or
// TRANSLUCENT_LIGHTING, lit.vsh's FetchMaterialID returns GLASS outright for
// this ID; and in any program at all, lit.vsh hands the material to the
// fragment stage only through EncodePerFace, whose material field is the low
// nibble, bits 0-3, in /lib/encoding/face.glsl - so a program that never
// recognises the name still decodes 38 & 15 as 6. Numbering it this way means
// the portal decodes to the right material by construction. It does not mean
// FetchMaterialID always returns GLASS: outside the translucent programs it
// falls through the geometry selector and returns 38 unchanged, and the
// nibble is what makes that harmless.
// * the bits above them are the geometry selector's field, where this pack
// defines exactly one value, 1 (the +16 the diagonal selector adds). 2 is
// nothing at all: it is not a selector this pack defines, so a 38 is not a
// variant of GLASS but a slot of its own. It is where a number has to go when
// the whole number has to survive to the shadow program, and batch 697 put the
// four new light families there for the same reason; block.10019 and
// block.10022 are the only two entries that use selector 1.
//
// More than one entry in selector 2 is safe, and the reason is worth being
// exact about because the low four bits are read in two places: EncodePerFace
// keeps four bits of material and every gbuffers program goes through it (not
// only the translucent ones), and lit_voxy.fsh drops anything above 0xFu to
// GENERIC of its own accord. Neither ever sees these four families:
// FetchMaterialID in lit.vsh reduces them to GENERIC first, because their own
// faces are meant to keep their texture colors. The nether portal is the other
// entry and its low nibble is 6 by construction, which is the GLASS the
// fragment stage has always been handed for it.
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
// violet whose Rec709 luminance is 0.343, so about a third as bright as the
// ground it falls on, which is what a saturated colour costs. Lower
// COLORED_SHADOWS_STRENGTH to keep more of the light and less of the colour -
// that option is what mixes this with white.
const vec3 NETHER_PORTAL_TINT = vec3(0.60, 0.20, 1.0);

// The nether portal's own surface, which is a different colour from the light it
// casts. The author sampled the vanilla portal particles and asked for the surface to
// sit near that hue: sRGB (214, 63, 206), which in linear is what is written below.
//
// Deliberately NOT the same constant as NETHER_PORTAL_TINT. That one is a LIGHT
// colour: it is mixed into the sunlight under a portal, and it was chosen with a
// channel budget (peak at 1.0, Rec709 luminance 0.343) so that a saturated colour
// does not also dim the ground. This one is a pigment: it is the colour of the
// surface itself, seen directly and then tonemapped, so it can be as saturated as the
// particles are and needs none of that arithmetic.
const vec3 PORTAL_RIFT_TINT = vec3(0.67, 0.05, 0.62);
// The end gate's own palette. These are the End's colours - the same violet and teal
// the sky's nebula uses - but they live here rather than being read from the sky
// framework: the gate is not the sky and should not depend on a file that only some
// programs include. The star tint is its own too, a cool white that reads as starlight
// against the violet rather than as a copy of the sky's.
const vec3 PORTAL_VOID_VIOLET = vec3(0.34, 0.22, 0.62);
const vec3 PORTAL_VOID_TEAL = vec3(0.10, 0.42, 0.48);
const vec3 PORTAL_STAR_TINT = vec3(0.80, 0.86, 1.10);
// The gate's stars are brighter than the sky's AT THE SAME SETTING (batch 619),
// because they are seen against a lit room rather than against the End's black sky
// and the author asked for them to read as light rather than as dust. This is a
// gain ON TOP of END_STAR_BRIGHTNESS, not a replacement for it: the sky option still
// scales it, and the author set this to 3.0 in batch 620 after judging 1.7 too dim.
// scales the gate's stars proportionally, so turning the sky's stars down still
// turns the gate's down.
const float PORTAL_STAR_GAIN = 3.00;

// The two portal surfaces that are BLOCK ENTITIES keep their numbers raw.
//
// They arrive as the blockEntityId uniform rather than through mc_Entity, so
// DecodeMaterialID does not apply to them and they never become materials - these
// are the numbers block.properties gives them. 10039 is new and belongs to the end
// portal alone; 10012 is the light ID the end rod and the end gateway already
// shared, and the gateway is the one block that is both a light source and a portal
// surface, so it is the same uniform either way. See PORTAL_EFFECTS in
// /program/world/lit.fsh for what reads them.
const float END_PORTAL_BLOCK_ID = 10039.0;
const float END_GATEWAY_BLOCK_ID = 10012.0;

// Whether block entities draw into the shadow map, and - since batch 719 - also
// how much of the coloured light fill they are allowed to feed.
//
// Two things read it, in two places. shaders.properties asks the loader to submit
// block entity geometry to the shadow pass whenever this is on, or whenever
// COLORED_LIGHTS is (see shadowBlockEntities there, and the note on why). The
// shadow program then reads it in its vertex stage: with this off - and with
// COLORED_LIGHTS on, which is the only state that submits them without it - it puts
// every block-entity vertex outside the clip volume once the fill write has run, so
// the map gains no new shape; with it on the geometry draws as it always did.
//
// Batch 719 is where those two questions came apart. The fill's world image is
// written by the shadow program and by nothing else - see the write in
// /program/shadow/shadow.vsh and the b700 note in /shadowcomp.csh - so a block
// entity light source cannot reach the fill without its vertices being drawn there.
// The only two this palette can name are the end portal and the gateway. Until this
// batch they were not drawn, the end portal's authored cold colour never arrived, and
// the light around it fell back to the pack's warm block light tint. That was the
// author's report: an end portal that lit the room yellow.
//
// Declared here rather than in /environment/lighting/diffuse.glsl, where it sat
// until batch 719, because the program that now reads it is the shadow program and
// the shadow program's two stages include this file and not that one. A define a
// program does not include is a define that program does not have, and a branch on
// it then silently takes the false side - which is exactly how the block-entity
// write of batch 697 shipped without ever running.
//
// The line below has to stay in this exact shape: `//#define`, with no space
// between the slashes and the hash. That is how the loader recognises an option
// that exists and is off - it is the form every other default-off option in this
// pack uses - and it is also the line the loader edits when the author ticks the
// box. Batch 719 moved this declaration here and kept the space upstream's copy
// had (`// #define`), and the option disappeared from the shadows page entirely:
// a line the loader cannot read as a declaration is a line it cannot show, and it
// says nothing about that when it happens. Batch 720 puts the shape right.
//#define REAL_TIME_BLOCK_ENTITY_SHADOWS

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
// and what every fragment that is not a colour source writes into it: shadow.fsh
// starts its tint at vec3(1.0) and writes that buffer from every fragment it does
// not discard. A scene with no stained glass and no portal in it therefore reads
// back 1.0 everywhere and multiplies the direct light by exactly 1.0, which is a
// no-op down to the last bit.
//
// The clear is not something this file can show - it is shadowcolor1Clear in
// shaders.properties, whose note records that Iris clears the shadow colour
// buffers to white on its own and that the requirement is written down there
// rather than inherited.
#define COLORED_SHADOWS

#ifdef COLORED_SHADOWS
	// How much of the colour the light picks up, where 0.0 leaves the light as
	// it was and 1.0 gives it the full colour of its source.
	//
	// At 1.0 a pane of black stained glass puts the floor under it in the dark,
	// which is what black glass does - and the portal puts a violet on it. Lower
	// values keep the light and only take on the hue, which is the setting to
	// reach for if the patches look too saturated to sit alongside everything
	// else in the scene. Recorded: the lower range is said to be closer to what
	// Mellow and Sundial settle on; that is a comparison with two other packs and
	// nothing here stands behind it.
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
	// surfaces the pack calls GLASS, which is what stops a portal from colouring
	// its own faces and what "standing inside one should not tint you from the
	// inside" amounts to. It is GLASS specifically, not every translucent
	// material: water and stained glass are not faded, and stained glass carries
	// a filter colour that has to survive. See the write in
	// /program/shadow/shadow.fsh and the read in
	// /environment/lighting/shadowmap.glsl for how the two kinds of source are
	// told apart in the buffer.
	#define COLORED_SHADOWS_PORTAL
#endif

// Geometry selector: Diagonally horizontal geometry
// Add 16 to any material ID to apply this geometry selector - the selector is
// the ID shifted right by four (lit.vsh), so 16 is selector 1 and nothing else.
// 10019 and 10022 in block.properties are the entries that use it; the nether
// portal's 38 and the four light families added in batch 697 carry selector 2,
// which is not defined here at all.
const uint GEOMETRY_HORIZONTAL_DIAGONAL_ONLY = 1u;

// Standard Iris / OptiFine: IDs in block.properties via mc_Entity.x
uint DecodeMaterialID(float mc_EntityX) {
	return uint(max(0.0, mc_EntityX - 10000.0));
}

// Voxy: IDs in block.properties via VoxyFragmentParameters.customId
uint DecodeMaterialID(uint customId) {
	return customId > 10000u ? customId - 10000u : 0u;
}
