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
#define NO_GTEXTURE

// Included in the debug view as a control: this program never samples the block
// atlas, so it cannot be what shows a block texture in the sky - if the patch
// turns black there, that reasoning is wrong somewhere. Black in the debug
// view. See gbuffers_spidereyes.fsh.
#define END_DEBUG_TINT vec3(0.0, 0.0, 0.0)

#include "/program/world/lit.fsh"
