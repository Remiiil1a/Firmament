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

// Painted in the End by the debug view, to identify what draws the End's light
// flash - see gbuffers_spidereyes.fsh. Magenta.
#define END_DEBUG_TINT vec3(1.0, 0.0, 1.0)

// Whether entities get PBR materials.
//
// Read the following before turning this on, because unlike the block atlas
// this one is not certain to work.
//
// The note in gbuffers_terrain.fsh says the block atlas is the only atlas Iris
// and OptiFine build normal and specular maps for. If that is the whole story,
// then an entity's material samples land on whatever texture was bound before,
// and every mob will be shaded with some arbitrary block's materials - which
// looks worse than no materials at all. If instead the loaders bind the _n and
// _s textures that a resource pack ships next to the entity texture (which is
// what the suffix convention implies, and what many packs assume), then this
// gives mobs the same material response the terrain has.
//
// It is cheap to find out which: turn this on, look at a mob, and pick the
// Occlusion channel under the material debug view. A uniform picture means no
// material data is bound and this should be turned back off; varying detail
// that matches the mob's own texture means it works.
//
// On by default: if a resource pack ships no material maps for entities there is
// nothing for it to read, which costs a little and shows nothing. Turn it off if
// the check above shows it picking up materials that are not the entity's own.
#define PBR_ENTITIES
#ifdef PBR_ENTITIES
	// Keep this in sync with gbuffers_entities.vsh - it has to be defined in
	// both stages, or the sprite bounds varying that parallax mapping needs
	// would only exist on one side.
	#define PBR_ATLAS
#endif

#include "/program/world/lit.fsh"
