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

// Painted in the End by the debug view, to identify what draws the End's light
// flash - see gbuffers_spidereyes.fsh. Yellow.
#define END_DEBUG_TINT vec3(1.0, 1.0, 0.0)


// Whether held items get PBR materials too.
//
// A held block is drawn from the block atlas, so it carries exactly the same
// material data as the same block placed in the world, and turning this on is
// what stops a held stone from looking flat while the stone in the wall next to
// it does not. A held item that is not a block is drawn from the item atlas,
// where the material maps come from the resource pack if it ships them.
//
// On by default, so that the world is consistent: a held block carries the same
// materials as the one placed next to it.
#define PBR_HAND_ITEMS
#ifdef PBR_HAND_ITEMS
	// Keep this in sync with gbuffers_hand.vsh - it has to be defined in both
	// stages, or the sprite bounds varying that parallax mapping needs would
	// only exist on one side.
	#define PBR_ATLAS
#endif

#include "/program/world/lit.fsh"
