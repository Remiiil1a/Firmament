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

#version 150 compatibility
#define MIX_ENTITY_COLOR
#define AFTER_DEFERRED

// Painted in the End by the debug view, to identify what draws the End's light
// flash - see gbuffers_spidereyes.fsh. Purple.
#define END_DEBUG_TINT vec3(0.6, 0.0, 1.0)

// Whether entities get PBR materials.
//
// This is the program the third-person player is actually drawn by - a player
// is drawn as a translucent entity, because its skin's outer layer is one, so
// the player, its armour and whatever it is holding all arrive here rather than
// at gbuffers_entities the way a mob does.
//
// On, through PBR_MATERIALS_ANY_TEXTURE rather than PBR_ATLAS.
//
// The first attempt at this defined PBR_ATLAS, which is wrong here for a reason
// that only shows up at runtime: PBR_ATLAS also pulls in mc_midTexCoord, the
// attribute that says where this face's sprite sits. Entities do not have it,
// so the value the sprite bounds were built from was garbage, the albedo lookup
// got boxed into an arbitrary square of the skin, and the parts of the skin that
// are transparent came back with it - which is what the armour and the held item
// showing the world through them was.
//
// PBR_MATERIALS_ANY_TEXTURE is the same material path without that assumption:
// the sprite bounds carry a zero half-size, which the clamp reads as "nothing
// usable here" and leaves the coordinate alone.
#define PBR_ENTITIES
#ifdef PBR_ENTITIES
	#define PBR_MATERIALS_ANY_TEXTURE
#endif

#include "/program/world/lit.fsh"
