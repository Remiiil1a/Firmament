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

// Added 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

#version 150 compatibility

// The colored light bleed, and the indirect bounce that shares its gather.
//
// This program is the pass itself, which lives in /program/post/light_bleed.fsh;
// what is here is only the wrapper that gives it a name in the pass chain.
//
// It was composite2 until batch 666. That pass is the temporal resolve now - the
// reflection's trace was split out of it into composite1 and the resolve took its
// place - so the light bleed moved one step along the chain rather than being
// renumbered behind it. Iris runs composite, composite1, composite2, composite3 in
// that order, and the light bleed has to stay after the resolve: it reads the
// frame the resolve leaves in colortex0 and writes that frame back.
#include "/program/post/light_bleed.fsh"
