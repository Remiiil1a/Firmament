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

// Guarded against a second inclusion: this file is pulled in by the sky drawing
// itself, by fog, by the water reflections, and by the material reflections
// added under PBR_REFLECTIONS. As the pack stands, every program that wants it
// names it once - lit.fsh (under TRANSLUCENT or APPLY_FOG), composite1.fsh,
// composite3.fsh, copy_and_fog.fsh, gbuffers_skytextured.fsh, sky.fsh,
// clouds.vsh and lit_voxy.fsh - so the guard is what would make a second
// inclusion harmless rather than something the pack relies on today.
//
// It is not the only include guard in the pack: dimension.glsl, the cloud march
// in /environment/clouds/volumetric.glsl, end_lighting.glsl, motion_blur.glsl,
// sky/bodies.glsl, sky/stars.glsl, sky/end_palette.glsl, lib/reproject.glsl and
// lib/bayer8.glsl all carry one, and bayer8.glsl is the one that is genuinely
// reached twice in a single program - sky.fsh includes it directly and then
// again through this file.
#ifndef SKY_GLSL_INCLUDED
#define SKY_GLSL_INCLUDED

#define MINISHITA 1
#define GRADIENT 2
// Which atmosphere model draws the sky: the physical scattering one in
// sky/minishita.glsl, or the gradient in sky/gradient.glsl. It chooses the
// include below, and is tested again in SkyDither. Both names are defined above.
#define ATMOSPHERE_MODEL MINISHITA // [MINISHITA GRADIENT]

#if ATMOSPHERE_MODEL == GRADIENT
	#include "sky/gradient.glsl"
#else
	#include "sky/minishita.glsl"
#endif

// The sun and the moon as discs in the sky, for the reflections to use. The
// model above is atmosphere only and has neither of them in it, so this reads
// its sun direction and has to come after it.
#include "sky/bodies.glsl"

// The star field. Included here rather than only where the sky is drawn,
// because a reflection of the sky needs it for the same reason it needs the two
// discs above: it is part of the sky, and what a reflection is handed is this
// model alone, which has no stars in it either.
#include "sky/stars.glsl"

// The End's own sky, which is not an atmosphere at all.
#include "sky/end.glsl"

// The color of the sky in the given direction, in linear RGB.
//
// This is the single entry point every program uses - the sky itself, fog, and
// water reflections all ask for the sky through it - which is what keeps them
// agreeing with each other, and what means the End's sky only has to be chosen
// in one place.
vec3 SkyColor(vec3 worldDir) {
	#ifdef END_DEBUG
		// See END_DEBUG in /environment/dimension.glsl. Replaces the sky with
		// what the dimension checks returned, so that they can be read off the
		// screen instead of guessed at.
		return EndDebugColor();
	#elif END_SKY == END_SKY_OFF
		return SkyColorModel(worldDir);
	#else
		if (EndSkyDimension()) {
			return EndSkyColor(worldDir);
		}

		return SkyColorModel(worldDir);
	#endif
}

#include "/lib/bayer8.glsl"

// Returns the sky color it was handed, dithered for the given fragment / pixel
// coordinate on the screen. It is not a factor: the color comes back multiplied.
//
// Recorded: credit to MakeUp Ultra Fast for the idea of dithering the sky
// gradient - it really helped fix the otherwise obvious banding.
vec3 SkyDither(vec2 fragCoord, vec3 skyColor) {
	// Intensity of sky dithering.
	#define SKY_DITHER 0.075 // [0.0 0.025 0.05 0.075 0.1 0.125 0.15]

	float ditherFactor = SKY_DITHER;
	
	#if NIGHT_ATMOSPHERE == RETRO && ATMOSPHERE_MODEL == GRADIENT
		// Workaround for near-black sky colors under a filmic tonemap: the
		// tonemap exaggerates the contrast of the black colors, and the adaptive
		// term added below does not dither them enough on its own.
		//
		// ⚠️ The guard tests the night atmosphere and the model, not the tonemap,
		// so once NIGHT_ATMOSPHERE is RETRO this fires under whichever TONEMAP is
		// selected. Today that means the Retro profiles, which are what set the
		// value (shaders.properties, profile.RETRO_MEDIUM and the two that derive
		// from it), and they select a filmic tonemap alongside it - but the guard
		// does not say so.
		//
		// ⚠️ Both names in the guard come from the model included above. Under
		// MINISHITA neither NIGHT_ATMOSPHERE nor RETRO is defined, so the first
		// test reads 0 == 0 and is true, and it is the ATMOSPHERE_MODEL test that
		// makes the whole condition false. Dropping that second test would turn
		// this on with the physical model as well.
		//
		// Recorded: this is not perfect, but it was judged an OK workaround for
		// the only case where this happens, the Retro profile at night, without
		// impacting any other situation.
		float skyColorLuminance = dot(skyColor, vec3(0.2126, 0.7152, 0.0722));
		ditherFactor *=
			1.0 + 3.0 * (1.0 - smoothstep(0.0, 0.5, skyColorLuminance));
	#endif

	// Basically just darkening or brightening the color relative to its
	// existing brightness, to automatically adapt to colors of any brightness.
	//
	// Bayer8 is read here as if it ran 0 to 1. It very nearly does: lib/bayer8.glsl
	// divides its matrix by 1.3, which leaves a range of about 0 to 1.0096, so the
	// dither is skewed bright by at most a hundredth of ditherFactor. (The NB
	// above Bayer8 in that file quotes the undivided range, 0 to 1.3125.)
	float dither = 1.0 + ditherFactor * (Bayer8(fragCoord) * 2.0 - 1.0);
	return skyColor * dither;
}

#endif // SKY_GLSL_INCLUDED
