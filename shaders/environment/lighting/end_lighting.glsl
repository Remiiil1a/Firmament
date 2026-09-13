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

// The End's own light and haze.
//
// Steadfast lights a surface from its sky light, which means a dimension with
// no sky light at all is lit by nothing but the ambient floor, and the End is
// exactly that: stone islands floating in a void, close to black. Vanilla does
// not leave it there either - it gives the End its own dim light - and this is
// the same idea, tuned to the pack.
//
// Three things make the End read as the End rather than as an unlit overworld:
// a violet ambient light in place of the sky's, a faint glow from the void
// below that lights the undersides of the islands, and haze the color of the
// sky. The three are separate controls because they are what the dimension's
// mood is made of: turn the void glow off and the islands flatten into cutouts,
// turn the haze off and they stop sitting in the sky.

// Uniforms: none. This only needs to know which dimension it is in.
#include "/environment/dimension.glsl"

#ifndef END_LIGHTING_INCLUDED
#define END_LIGHTING_INCLUDED

// How much light the End has of its own, in linear light.
//
// Off by default, and left in place rather than removed because turning it up
// is all it takes to try it: it was reported as having no effect at all on the
// machine it was written for, and the cause was never found. Two things are
// known about that: the End's own sky and haze do work there, so the pack
// recognizes the dimension, and the debug view's version of this light - which
// is ten times brighter and ignores this value - does show up. So the code path
// runs and this number is the only thing in question, which points at the
// terrain rather than at this file: nothing here applies to terrain that is
// drawn by another mod, and a shader path belonging to one of those is given no
// biome information and would read this as the overworld.
//
// For how the number is scaled: Steadfast's tonemapper is close to the identity
// below 0.6 in linear light, so a value written here reaches the screen at
// roughly its own size after being multiplied by the surface's color. A torch
// lights a surface with 8.0 and the sun with one to three, so 0.35 is a dim
// light - but an earlier attempt at 0.14 was dim enough to be reported as no
// change at all, which is why the useful values are this large.
#define END_AMBIENT 0.0 // [0.0 0.1 0.2 0.35 0.5 0.7 1.0 1.5]

// How much light comes up from the void below the islands. It lights the
// undersides of everything, which is what stops the End's terrain from reading
// as flat, and is free everywhere else. Off by default along with the light
// above, and for the same reason.
#define END_VOID_GLOW 0.0 // [0.0 0.1 0.2 0.35 0.5 0.75 1.0]

// How far the End's haze takes the color of its sky. At 0.0 the End is fogged
// with the same color a cave is, which is what it did before.
#define END_FOG 1.0 // [0.0 0.25 0.5 0.75 1.0]

// The End's palette. Its light is a desaturated violet, the void below is a
// deeper and more saturated one, and its haze sits between the two - all three
// taken from the colors its own sky is built from in sky/end.glsl.
const vec3 END_AMBIENT_COLOR = vec3(0.62, 0.58, 0.82);
const vec3 END_VOID_COLOR = vec3(0.42, 0.26, 0.78);

// Slightly brighter than the sky itself, so that distance reads as haze rather
// than as a hole.
const vec3 END_FOG_COLOR = vec3(0.030, 0.028, 0.055);

// The End's own contribution to a surface's ambient light, in linear RGB.
//
// Zero everywhere that is not the End, so that nothing but this dimension pays
// for it.
vec3 EndAmbientLighting(float ambientStrength, vec3 worldNormal) {
	if (!EndDimension()) {
		return vec3(0.0);
	}

	#ifdef END_DEBUG
		// Part of the debug view: an unmistakable red, so that whether this
		// reached the terrain at all is answered by looking at it rather than by
		// guessing. See END_DEBUG in /environment/dimension.glsl.
		return vec3(1.0, 0.0, 0.0) * ambientStrength;
	#else
		// The base light is shaped by the face direction like the rest of the
		// pack's ambient, so that the islands keep their form.
		vec3 light = END_AMBIENT_COLOR * (END_AMBIENT * ambientStrength);

		// The void glow only reaches faces that point down into it.
		float facingVoid = max(-worldNormal.y, 0.0);
		light += END_VOID_COLOR * (END_VOID_GLOW * facingVoid);

		return light;
	#endif
}

#endif /* END_LIGHTING_INCLUDED */
