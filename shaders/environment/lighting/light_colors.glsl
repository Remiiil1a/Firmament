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

// The color of the light that each family of light-emitting blocks gives off.
//
// Recorded: Steadfast had one block light color for the whole world, a warm
// orange - a reasonable average, and completely wrong for a soul lantern or a
// redstone torch. The same history is written out at BlockLightTint in
// /environment/lighting/diffuse.glsl, which replaced that average for the light
// that falls on everything else. This file replaces it on the faces of the block
// that is doing the glowing, which is the only place where Minecraft tells us
// which light source we are looking at: its light map stores how much light
// arrived at a position, not what color it was or where it came from.
//
// The colors below are therefore not just the block's own texture tinted - a
// torch's texture is mostly a brown stick, and its light is not brown. They are
// chosen to match what the block actually lights its surroundings with.
//
// Where the light lands on everything else is carried by two routes that share
// this one palette. The main one since batch 696 is the flood fill in
// /environment/lighting/light_volume.glsl: the shadow program looks a block's
// color up here and writes it into a voxel grid, and the grid carries it through
// the air. The other is the light bleed in /program/post/light_bleed.fsh, which
// spreads the colors written here across nearby surfaces; its route is one call
// - LightSourceSurfaceColor is called once in the pack, in /program/world/
// lit.fsh, in the block self-emission section, and what it returns is written
// into the light source mask that pass reads. That pass holds no palette of its
// own and does not include this file, so these are the only colors in it.

// Whether light-emitting blocks take their real color, rather than being tinted
// by their own texture. Also what decides whether the light bleed pass is
// switched on: program.composite2.enabled in shaders.properties names this
// option, and composite2.fsh is the pass. The pass's own code carries no guard
// of ours, so turning the option off is what stops it being compiled rather than
// a branch inside it, and what the mask holds when the option is off is the
// plain texture color, because that is what LightSourceSurfaceColor returns.
#define COLORED_LIGHTS

// How far the color of a light source replaces the color of its texture.
//
// At 1.0 the emitter is lit purely by its own light color, keeping only the
// texture's brightness. Lower values blend back towards the texture, which is
// what to use if a resource pack's textures carry detail you would rather not
// lose on the emissive parts.
#define COLORED_LIGHTS_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0]

// The color of the light a block gives off, or black if it is not a light
// source.
//
// The range check comes first so that the overwhelming majority of surfaces -
// everything without an ID of its own - pay two comparisons and nothing else.
vec3 BlockLightColor(uint materialID) {
	// An early out rather than a range test. The light IDs used to be one band,
	// LIGHT_WARM through LIGHT_AMETHYST; the families added in batch 697 sit at
	// 40 to 43, above the geometry selector's field so that their numbers survive
	// to the shadow program intact. A band test would have to span 7 to 43, and
	// the IDs between those two sets - STAINED_GLASS, the geometry-selected
	// campfire, the portal - would be admitted only to fall through the chain
	// below. The early out is instead the comparison that was always there for
	// GENERIC, which is what nearly every fragment in the frame carries, and the
	// handful of other non-light IDs pay the chain and nothing more.
	if (materialID < LIGHT_WARM) {
		return vec3(0.0);
	}

	if (materialID == LIGHT_WARM) {
		// Torch flame, and the same warm glow from glowstone and lanterns.
		return vec3(1.0, 0.52, 0.20);
	} else if (materialID == LIGHT_SOUL) {
		// Soul fire burns cyan, and soul lanterns match it.
		return vec3(0.25, 0.72, 1.0);
	} else if (materialID == LIGHT_REDSTONE) {
		return vec3(1.0, 0.13, 0.08);
	} else if (materialID == LIGHT_LAVA) {
		// Deeper and redder than a torch, closer to blackbody glow.
		return vec3(1.0, 0.32, 0.06);
	} else if (materialID == LIGHT_SEA) {
		// Sea lanterns are very slightly cool rather than pure white.
		return vec3(0.72, 0.94, 1.0);
	} else if (materialID == LIGHT_END_ROD) {
		return vec3(0.88, 0.82, 1.0);
	} else if (materialID == LIGHT_CRYING) {
		return vec3(0.35, 0.55, 0.95);
	} else if (materialID == LIGHT_AMETHYST) {
		return vec3(0.72, 0.42, 1.0);
	} else if (materialID == LIGHT_FROGLIGHT_OCHRE) {
		// The froglight colors are the blocks' own glow - their textures carry
		// them - and the fill needs the family so that a froglight is an emitter
		// rather than a wall. These are the colors their textures glow in.
		return vec3(1.0, 0.78, 0.42);
	} else if (materialID == LIGHT_FROGLIGHT_VERDANT) {
		return vec3(0.50, 1.0, 0.52);
	} else if (materialID == LIGHT_FROGLIGHT_PEARLESCENT) {
		return vec3(1.0, 0.70, 0.92);
	} else if (materialID == LIGHT_COPPER) {
		// Copper fire burns green - that is what tells a copper torch from every
		// other torch in the game, and it is the whole reason this family exists.
		return vec3(0.40, 1.0, 0.78);
	}

	return vec3(0.0);
}

// The color of the light a BLOCK ENTITY gives off, by the number it arrives as.
//
// The palette above is written in material IDs because that is what the block
// path has: terrain arrives through mc_Entity and is decoded into a material. A
// block entity is drawn by its own renderer and has no mc_Entity at all - the
// only thing the game tells the shader about it is the number block.properties
// gave it, in the blockEntityId uniform - so the two portal surfaces, which are
// block entities, cannot name a material and are answered here by the raw number
// instead. This is the same question BlockLightColor answers, asked in the other
// space, which is why it lives beside the palette rather than in the shadow
// program that is its only caller today.
//
// The other half of their arrival is not in this file. A colour answer is worth
// nothing unless the geometry carrying it is drawn in the pass that writes the
// fill, and block entities are drawn there only because shaders.properties submits
// them (batch 719; the note on REAL_TIME_BLOCK_ENTITY_SHADOWS in
// /environment/materialIDs.glsl explains why that submission is tied to the fill
// rather than to their shadows). Between batch 697, which wrote the two answers
// below, and batch 719, they were answered and never asked: the shadow pass never
// drew a block entity, so the end portal's cold violet never entered the fill and
// the room it stands in was lit by the pack's warm block light tint instead.
//
// The end portal is the void itself. What it casts is the violet of the star
// field seen from inside it, taken cold: the blue channel is at peak, green sits
// above red so the tint reads as violet rather than as a dimmed purple, and the
// peak is 1.0 because every entry in this palette peaks at 1.0 - the propagation
// reads a voxel's brightest channel as how strong the light is, so a source whose
// color peaked lower would also be a weaker source.
//
// The gateway is an end rod: block.10012 gives it the end rod's own light number,
// and that one number is both its portal surface and its light, so its color is
// asked of that family rather than written out a second time.
//
// Every other block entity is not a light source and gets black, which is the
// answer BlockLightColor gives for a number that is not in the palette.
vec3 BlockEntityLightColor(float blockEntityId) {
	if (blockEntityId == END_PORTAL_BLOCK_ID) {
		return vec3(0.45, 0.55, 1.0);
	}

	if (blockEntityId == END_GATEWAY_BLOCK_ID) {
		return BlockLightColor(LIGHT_END_ROD);
	}

	return vec3(0.0);
}

// The color a light source's own surface should be lit with, given the color of
// its texture.
//
// Only the texture's brightness survives: the color is the light's own, taken
// from BlockLightColor above, and the texture contributes nothing but its
// luminance (so its saturation goes too, not only its hue). Glowing the whole
// face in a flat color instead would turn a torch into an orange rectangle,
// losing the shape of the flame that makes it read as a torch at all.
//
// The caller is what makes this the emitter's own face rather than every
// surface: lit.fsh uses the result only where the light map says the block is
// emitting, and only the emitter's own color is carried into the light source
// mask.
vec3 LightSourceSurfaceColor(uint materialID, vec3 surfaceColor) {
	#ifndef COLORED_LIGHTS
		return surfaceColor;
	#else
		vec3 lightColor = BlockLightColor(materialID);

		if (lightColor == vec3(0.0)) {
			return surfaceColor;
		}

		// Rec709 luminance, since the surface color is linear here.
		float brightness = dot(surfaceColor, vec3(0.2126, 0.7152, 0.0722));
		vec3 colored = lightColor * brightness;

		return mix(surfaceColor, colored, COLORED_LIGHTS_STRENGTH);
	#endif
}
