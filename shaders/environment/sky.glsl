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
// added under PBR_REFLECTIONS, and more than one of those can apply to the same
// program. There is no other guard in this pack's includes because every other
// one is only ever reached once per file.
#ifndef SKY_GLSL_INCLUDED
#define SKY_GLSL_INCLUDED

#define MINISHITA 1
#define GRADIENT 2
// The atmosphere (sun) color contribution from the sun during the day.
#define ATMOSPHERE_MODEL MINISHITA // [MINISHITA GRADIENT]

#if ATMOSPHERE_MODEL == GRADIENT
	#include "sky/gradient.glsl"
#else
	#include "sky/minishita.glsl"
#endif

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

// Returns a darkening or brightening factor for the given fragment / pixel
// coordinate on the screen.
//
// Credit to MakeUp Ultra Fast for the idea of dithering the sky gradient -
// it really helped fix the otherwise obvious banding.
vec3 SkyDither(vec2 fragCoord, vec3 skyColor) {
	// Intensity of sky dithering.
	#define SKY_DITHER 0.075 // [0.0 0.025 0.05 0.075 0.1 0.125 0.15]

	float ditherFactor = SKY_DITHER;
	
	#if NIGHT_ATMOSPHERE == RETRO && ATMOSPHERE_MODEL == GRADIENT
		// Workaround for near-black sky colors in combination with filmic
		// tonemaps. In these cases, the filmic tonemap will exaggerate the
		// contrast of the black colors, but our adaptive code below will not
		// dither sufficiently.
		//
		// This isn't perfect but seems to be an OK workaround for the only case
		// where this happens, the Retro profile at night, without impacting any
		// other situation.
		float skyColorLuminance = dot(skyColor, vec3(0.2126, 0.7152, 0.0722));
		ditherFactor *=
			1.0 + 3.0 * (1.0 - smoothstep(0.0, 0.5, skyColorLuminance));
	#endif

	// Basically just darkening or brightening the color relative to its
	// existing brightness, to automatically adapt to colors of any brightness.
	float dither = 1.0 + ditherFactor * (Bayer8(fragCoord) * 2.0 - 1.0);
	return skyColor * dither;
}

#endif // SKY_GLSL_INCLUDED
