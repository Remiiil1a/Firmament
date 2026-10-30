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
// Where the light lands on everything else is approximated by the light bleed
// in /program/post/light_bleed.fsh, which spreads the colors written here across
// nearby surfaces. The route is one call: LightSourceSurfaceColor is called once
// in the pack, in /program/world/lit.fsh, in the block self-emission section, and
// what it returns is written into the light source mask that pass reads. That
// pass holds no palette of its own and does not include this file, so these are
// the only colors in it.

// Whether light-emitting blocks take their real color, rather than being tinted
// by their own texture. Also what decides whether the light bleed pass is
// switched on: program.composite2.enabled in shaders.properties is
// COLORED_LIGHTS || INDIRECT_BOUNCE, and composite2.fsh is the pass. Note that
// the pass's own code carries no guard of ours - with this off and
// INDIRECT_BOUNCE on it still runs, and what changes is the mask it reads, since
// LightSourceSurfaceColor returns the plain texture color when this is off.
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
	if (materialID < LIGHT_WARM || materialID > LIGHT_AMETHYST) {
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
