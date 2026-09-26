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

// This program is the one the game hands its lines and boxes to, which makes it
// the one that draws the block selection outline.
//
// ⚠️ Named for what it is rather than for the outline, because it is not only
// the outline: entity hitboxes, structure block bounds and anything else on a
// line render type arrive here too, and there is no material to tell them apart.
// The selection box options therefore apply to all of them, which is written
// down where the options are.
//
// The world shader tests this with #ifdef, so the block that reads it is
// compiled in this program and nowhere else - which is the point of a define
// rather than a runtime test: the other fourteen programs that include lit.fsh
// never see it.
#define DRAWING_LINES

// The outline's own options, and the colour helper the world shader calls.
// Before lit.fsh, because that file is where the helper is used.
#include "/environment/lighting/selection_box.glsl"

#include "/program/world/lit.fsh"
