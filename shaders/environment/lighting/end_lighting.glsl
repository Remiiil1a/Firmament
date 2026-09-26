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

// The End's own light.
//
// Steadfast lights a surface from its sky light, so a dimension with no sky
// light at all is left with nothing but the ambient floor, and the End is
// exactly that: stone islands floating in a void. Vanilla does not leave it
// there either - it gives the End its own dim light - and this is the same
// idea, tuned to the pack: a violet ambient light in place of the sky's, so
// that the dimension reads as somewhere else rather than as an unlit overworld.
//
// Batch 333 removed the two neighbours that used to live here. Neither had ever
// done anything, and the reasons are worth keeping:
//
//   - END_VOID_GLOW added light to faces whose normal pointed down. An island
//     is looked at from above and from the side, where the normal points up or
//     sideways, so the term was multiplied by zero on effectively every pixel
//     of a normal view. It could only ever be seen by looking up at the
//     underside of an island - which is not a thing anyone does.
//   - END_FOG recoloured the fog. The End has no sky light, and the pack turns
//     its atmospheric fog off wherever the eye's sky light is low (see
//     fogInCaveAdjustment in shaders.properties), which in the End is
//     everywhere. There was no fog left to recolour: all that remained was the
//     thin border band at the render distance, and the two colours it mixed
//     between are both very nearly black.
//
// The lesson, which is what the next attempt at the void has to be built on:
// a void that reads as a void has to be a function of where the geometry is,
// not of which of its faces happens to be pointing at the camera. See
// PBR_PORTING.md 189.

// Uniforms: none. This only needs to know which dimension it is in.
#include "/environment/dimension.glsl"

#ifndef END_LIGHTING_INCLUDED
#define END_LIGHTING_INCLUDED

// How much light the End has of its own, in linear light.
//
// Turned on as of batch 332. It sat at 0.0 until then because an early trial
// of it was reported as having no visible effect and the cause was assumed to
// be elsewhere; see PBR_PORTING.md 188 for why that reading was wrong - the
// trial was at 0.14, which is only about 1.8x the ambient floor and genuinely
// is hard to see, and the note about the debug view being "ten times brighter"
// is that same 0.14 against a debug value of 1.0. There was never a defect in
// this file.
//
// ⚠️ This is a brightening laid on top of a floor that is already visible. It
// is not what takes the End out of the dark: the pack's own
// MIN_AMBIENT_BRIGHTNESS (0.1) is, and upstream Steadfast does not have that
// option at all. Batch 332's report claimed the dimension had no light and
// that this turned it on, and the user corrected it: the End was already lit.
//
// For how the number is scaled: the pack's tonemapper is close to the identity
// below 0.6 in linear light, so a value written here reaches the screen at
// roughly its own size after being multiplied by the surface's color. A torch
// lights a surface with 8.0 and the sun with one to three, so 0.35 is a dim
// light - a readable End that is still clearly a night-like place.
//
// ⚠️ The shipped default is 1.0 as of v0.7, not the 0.35 this note was written
// around: the user's own settings were taken as the release's defaults, and
// theirs sits at the top of the range. At 1.0 the End reads as a lit place rather
// than a dim one, which is the look v0.7 was tuned to. The whole set of retuned
// defaults is listed in CHANGELOG.md under v0.7.
#define END_AMBIENT 1.0 // [0.0 0.1 0.2 0.35 0.5 0.7 1.0 1.5]

// The End's light is a violet.
//
// ⚠️ Saturated in batch 338, because until then it was not actually violet.
// It was vec3(0.62, 0.58, 0.82), which against the ambient floor the pack
// already gives the End - a near-neutral vec3(0.107, 0.116, 0.120) - came out
// as vec3(0.324, 0.319, 0.407), a ratio of 0.80 : 0.78 : 1.00. That is a
// blue-tinted grey, not a violet, and the reason is that the dimension has no
// sky light: the neutral floor is a large part of the total there rather than a
// small correction, so the coloured light added on top of it is the minority.
// The user's report was that the option "does not give the End a violet
// atmosphere". See PBR_PORTING.md 194.
//
// ⚠️ The numbers look odd because they are compensated: this is scaled so that
// its luminance is the same as the old near-neutral colour's - 0.606 either
// way. Saturating a colour by pulling its green down takes brightness with it,
// and the point of this change was to fix the hue, not to make the dimension
// darker. Change it and the End's brightness changes too.
const vec3 END_AMBIENT_COLOR = vec3(0.78, 0.48, 1.34);

// The End's own contribution to a surface's ambient light, in linear RGB.
//
// Zero everywhere that is not the End, so that nothing but this dimension pays
// for it.
vec3 EndAmbientLighting(float ambientStrength) {
	if (!EndDimension()) {
		return vec3(0.0);
	}

	#ifdef END_DEBUG
		// Part of the debug view: a readout of the value above, drawn as the
		// color of the End's terrain.
		//
		// Red is END_AMBIENT as a fraction of its largest step. That makes this
		// answer "did the setting arrive" rather than "is there light": a value
		// that never reached the shader draws nothing at all, while one that
		// did draws it at a brightness equal to the value. The version before
		// batch 332 returned a flat red and so could not tell those two apart -
		// which is exactly what let an unresolved "no effect" stand for a
		// hundred batches. See PBR_PORTING.md 188.
		//
		// Note that the result still passes through the fragment's own color,
		// so it reads as a tint over the texture rather than as a clean bar.
		// The user spotted exactly that in batch 332's report. Left as it is
		// because the question it answers gets answered anyway, but a proper
		// readout would bypass the surface color.
		return vec3(END_AMBIENT / 1.5, 0.0, 0.0) * ambientStrength;
	#else
		// Shaped by the face direction like the rest of the pack's ambient, so
		// that the islands keep their form.
		return END_AMBIENT_COLOR * (END_AMBIENT * ambientStrength);
	#endif
}

#endif /* END_LIGHTING_INCLUDED */
