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

#version 150 compatibility

// Keep this in sync with gbuffers_entities_translucent.fsh - it has to be
// defined in both stages, or the sprite bounds varying that the material path
// needs would only exist on one side - and it has to be the same name in both,
// or the two stages would disagree about what that varying means.
#define PBR_ENTITIES
#ifdef PBR_ENTITIES
	#define PBR_MATERIALS_ANY_TEXTURE
#endif

#include "/program/world/lit.vsh"
