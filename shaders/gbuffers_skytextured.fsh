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
#include "/environment/tonemap_settings.glsl"
// The Uchimura and Uncharted 2 tonemaps have a much different white point, so
// for the sun and moon we need a bit of hardcoding per tonemap for now.
#if TONEMAP == TONEMAP_UNCHARTED2
	#define UNLIT_BRIGHTNESS 12.0
#else
	#define UNLIT_BRIGHTNESS 2.0
#endif

// The whole sky, rather than only the End's part of it, because the End's sky
// is asked for through the same SkyColor entry point everything else uses, so
// that the END_DEBUG view reaches here too.
#include "/environment/sky.glsl"

#if END_SKY == END_SKY_OFF
	#include "/program/world/unlit.fsh"
#else
	// This program draws every textured thing in the sky. In the overworld that
	// is the sun and the moon, which are just passed through - but the End draws
	// its sky as a texture on a box around the player rather than as the
	// generated sky the overworld uses, and that box arrives here. Left alone it
	// would be drawn as whatever texture it carries, so in the End this draws
	// the sky instead.
	#include "/lib/srgb.glsl"

	uniform sampler2D gtexture;

	in vec4 tinting;
	in vec2 texcoord;

	uniform mat4 gbufferModelViewInverse;
	uniform mat4 gbufferProjectionInverse;
	uniform vec2 windowToNdc;
	uniform float blindness;

	void main() {
		if (!EndSkyDimension()) {
			// The sun and moon, and anything else textured in the sky.
			//
			// This is /program/world/unlit.fsh, which is what this program uses
			// in every other dimension. It cannot be used here as well because a
			// program has only one main, so if it ever changes, this needs to
			// change with it.
			//
			// Note: the two bodies' images are the game's here, and are not
			// replaced with this pack's copies of them. That was tried, by
			// sampling img/sun.png and the phase row with this same texcoord
			// instead, and what it drew was a large, half-transparent body: the
			// coordinate this program is handed is not the sprite's own. See
			// PBR_PORTING.md 185.
			vec4 srgb = tinting * texture(gtexture, texcoord);
			vec4 fragmentColor = SrgbToLinear(srgb);
			fragmentColor.rgb *= UNLIT_BRIGHTNESS;

		/* DRAWBUFFERS:0 */
			gl_FragData[0] = fragmentColor;
			return;
		}

		// The direction is worked out from the pixel rather than from the box
		// the pixel came from, so that it agrees with the generated sky drawn by
		// the program next to this one, and so that the sun and moon cannot
		// appear in the End on top of it.
		vec2 ndcPos = gl_FragCoord.xy * vec2(windowToNdc) - 1.0;
		vec4 viewVecH = gbufferProjectionInverse * vec4(ndcPos, 1.0, 1.0);
		vec3 viewVec = normalize(viewVecH.xyz / viewVecH.w);

		// Note: w must be 0.0 in homogenous coordinates, as 1.0 means a point in
		// space rather than a vector.
		vec3 worldDir = (gbufferModelViewInverse * vec4(viewVec, 0.0)).xyz;

		// Asked for through SkyColor rather than directly, so that the END_DEBUG
		// view is visible here too - this is the path the End's own sky takes,
		// and a diagnostic that only worked in the overworld would not be much
		// of one.
		vec3 sky = SkyColor(worldDir);

	/* DRAWBUFFERS:0 */
		gl_FragData[0] = vec4(sky * max(0.0, 1.0 - 10.0 * blindness), 1.0);
	}
#endif
