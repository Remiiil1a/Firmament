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
#define HAS_BLOCK_ATTRIBUTES
#define HAS_WAVING_FOLIAGE
#define NORMALS_ARE_IN_WORLD_SPACE
// Keep this in sync with gbuffers_terrain.fsh - it has to be defined in both
// stages, or the sprite bounds varying that parallax mapping needs would only
// exist on one side.
#define PBR_ATLAS
#include "/program/world/lit.vsh"
