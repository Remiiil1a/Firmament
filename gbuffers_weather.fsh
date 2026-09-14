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
#define WEATHER
#define NEVER_RECEIVES_SHADOWS

// What is left of the candidates for the End's light flash. It is drawn over the
// sky rather than as part of it - the pack's sky programs do not draw it, and
// removing it from the programs that draw particles, glowing parts, the block
// outline and the sun and moon did not get rid of it either - and this is the
// last program that draws late, samples the block atlas, and has nothing of its
// own to lose in a dimension with no weather at all.
//
// Magenta in the debug view. See HIDE_END_FLASH in /environment/dimension.glsl.
#define SUPPRESS_END_FLASH
#define END_DEBUG_TINT vec3(1.0, 0.0, 1.0)

#include "/program/world/lit.fsh"
