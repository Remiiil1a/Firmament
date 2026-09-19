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

// Trivial program that draws the sky color on to the full screen.

#include "/lib/bayer8.glsl"
#include "/environment/sky.glsl"
// vec3 SkyStars(vec3 worldDir)
#include "/environment/sky/stars.glsl"
#include "/environment/clouds/cirrus.glsl"

uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjectionInverse;
uniform vec2 windowToNdc;
uniform float blindness;

// Moves the sky dither pattern across the screen rapidly to reveal excessive
// dithering
// #define SKY_DITHER_DEBUG

void main() {
	// Project back to view space from the fragment coordinates. For this case,
	// it is easier to start off with a position on the far plane and then
	// normalize to a vector than to try to get a vector out of the screen
	// position directly.
	vec2 ndcPos = gl_FragCoord.xy * vec2(windowToNdc) - 1.0;
	vec4 viewVecH = gbufferProjectionInverse * vec4(ndcPos, 1.0, 1.0);
	vec3 viewVec = normalize(viewVecH.xyz / viewVecH.w);

	// Note: w must be 0.0 in homogenous coordinates, as 1.0 means a point in
	// space rather than a vector.
	vec3 worldSpaceVector = (gbufferModelViewInverse * vec4(viewVec, 0.0)).xyz;

	// Dithering 
	vec2 ditherCoord = gl_FragCoord.xy;

	#ifdef SKY_DITHER_DEBUG
		ditherCoord += 500.0 * cos(frameTimeCounter);
	#endif

	// The flat-colour sky quads - the star field, and the dark plane the game
	// draws below the horizon - arrive here with a single colour and no texture,
	// so there is no sky in them to draw; this pack has no star texture of its
	// own either. They used to be filled with pure white here, which is what a
	// star field would be if the stars were points rather than a texture, and
	// because the test that recognizes them is "is this colour flat?", it did
	// not only fire on them.
	//
	// The game's own sky-colour quad is flat too whenever all three of its
	// channels come out equal, and a thunderstorm drives its colour to exactly
	// that: rain desaturates the sky colour until the channels meet. For the few
	// seconds the colour sits on that equality, the whole dome took the star
	// branch and went solid white - with the clouds still drawn over it
	// afterwards, and the horizon band, which is drawn as its own quad, left
	// alone. That is the white sky that appeared at moonrise and at sunrise in
	// rain.
	//
	// So the sky colour is drawn for these quads as well. When the test does not
	// fire - every clear night - this is the same statement it has always been.
	vec3 sky = SkyDither(
		ditherCoord,
		SkyColor(worldSpaceVector) + SkyStars(worldSpaceVector));

	// If clouds are enabled, blend them into the sky gradient.
	#if defined(CLOUDS_ENABLED)
		sky = BlendClouds(sky, worldSpaceVector);
	#endif

/* DRAWBUFFERS:0 */

	// Fade away the sky during blindness
	gl_FragData[0] = vec4(sky * max(0.0, 1.0 - 10.0 * blindness), 1.0);
}
