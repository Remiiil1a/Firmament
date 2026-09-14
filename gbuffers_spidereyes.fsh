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
#define UNLIT_BRIGHTNESS 5.0

// One of the programs that could be drawing the End's light flash, and so is
// painted in the debug view: it draws glowing geometry with no texture of its
// own, so it is the kind of program a new glowing sky effect lands in, and it
// samples the block atlas when nothing else is bound.
//
// Not dropped in the End, only painted: what it draws is worth keeping. Green
// in the debug view.
#define END_DEBUG_TINT vec3(0.0, 1.0, 0.0)

#include "/program/world/unlit.fsh"
