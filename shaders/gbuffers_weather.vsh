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
// WEATHER, and it has to be here as well as in the .fsh.
//
// program/world/lit.vsh writes two extra varyings under #if defined(WEATHER)
// that lit.fsh reads under the same guard - the sprite's own coordinate and its
// size in the atlas, which is what RAIN_DROP_AMOUNT needs to tile the rain
// inside its sprite rather than across the atlas. The .fsh raised the guard by
// itself and this file did not, so the fragment side declared two inputs that
// nothing ever wrote: they read as zero, and a sprite size of zero makes the
// drop-width band a constant that only happens to sit on the keep side at the
// default of 1.0. Any other value of either option moved it to the discard
// side, and every rain particle in the world vanished at once.
#define WEATHER
#define NEVER_RECEIVES_SHADOWS
#include "/program/world/lit.vsh"
