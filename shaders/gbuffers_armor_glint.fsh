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

// The enchantment's own layer, which is what this program is for.
//
// It is the only program in the pack that draws the glint, and the glint is the
// only part of an enchanted item that can be told apart from the item itself.
// Minecraft has one glint render type and the shader mods have one program for
// it - there is no gbuffers_hand_glint - so this single file draws the sparkle
// on the item in the first-person hand, on the item a player is holding in
// third person, and on the armour they are wearing. Nothing here tries to
// separate those: there is no uniform that says which one this is.
//
// It is also the only way to find an enchanted item at all. No uniform reports
// whether an item is enchanted - the ID uniforms report *which* item, out of a
// properties file this pack does not ship, and heldBlockLightValue only ever
// moves for a held block that emits light. That this program was called is the
// exact and only signal, and it is exact: an item with no enchantment never
// reaches this file, so nothing below can change how one looks.

// How much brighter than vanilla the glint is drawn.
//
// 1.0 is the glint exactly as this pack draws it today, and it is the first
// value in the list, so the option can always be put back to no effect at all.
//
// Stronger than it looks: Minecraft blends the glint with
// blendFunc(SRC_COLOR, ONE), which adds the *square* of what is written here,
// so the light this contributes grows with the square of the number and 2.0
// adds four times what the glint adds today. It scales the whole layer by the
// same amount and leaves the pattern's own contrast where it was, so this is a
// brightness control rather than a contrast one - what it produces is a
// brighter sparkle, not a flat white smear.
//
// 2.0 is the default: four times the glint, which is unmistakable in a cave and
// still reads as a sparkle rather than as a glow in daylight. Step down to 1.5
// if the item's own surface washes out around the streaks; step up to 3.0 if it
// turns out to be too subtle to notice at all.
#define GLINT_BRIGHTNESS 2.0 // [1.0 1.5 2.0 3.0 4.0 6.0]

// There was a colour option here - the glint tinted cold, violet or gold - and
// it was removed on 2026-09-22, after the user tried it and reported that it
// made almost no difference. The reason is worth keeping, because it is a
// property of the layer rather than of that option.
//
// The vanilla glint is already drawn in the enchantment's colour, the purple
// everyone pictures, and Minecraft has multiplied it in before this program
// ever sees it: the colour arrives inside `tinting` and inside the texture this
// file samples as gtexture. Multiplying that by a second colour can only take
// one of the channels that are already there away, so "violet" landed on a
// layer that was already violet and came out as a slightly dimmer glint rather
// than as a differently coloured one - which is exactly what was seen. Colour
// is not what this layer is missing, so no colour option replaced it.

// What unlit.fsh multiplies its colour by - the name it reads is this one.
//
// Defined here rather than changed there: each of the five programs that include
// unlit.fsh gives this name its own value before including it, and this file is
// where the glint's is chosen.
#define UNLIT_BRIGHTNESS GLINT_BRIGHTNESS

// One of the programs that could be drawing the End's light flash - see the
// note in gbuffers_spidereyes.fsh. Painted, not dropped. Blue in the debug view.
#define END_DEBUG_TINT vec3(0.0, 0.0, 1.0)

#include "/program/world/unlit.fsh"
