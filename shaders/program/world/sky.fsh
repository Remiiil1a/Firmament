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

// BATCH 800: THE GAME'S STAR FIELD IS DROPPED HERE, AND `renderStage` IS THE
// ONLY THING THAT CAN TELL IT APART.
//
// This program draws the generated sky for EVERY fragment of the sky-basic
// program, and the game submits several different quads to that program: the
// sky colour, the sunset band, the void plane, and the star field. They all
// arrive here with the same uniforms and no vertex colour this file reads, so
// from inside main() they are indistinguishable - which is why the two earlier
// attempts failed:
//
//   batch 155 tested for a flat colour, which is local knowledge from the
//   sky-textured program and cannot fire here.
//
//   batch 799 tested the vertex colour in gbuffers_skytextured, which is the
//   WRONG PROGRAM: the star field is drawn with POSITION_COLOR and no texture,
//   so Iris routes it to SKY_BASIC_COLOR - this program - not to sky-textured.
//
// `renderStage` is the loader's own statement about which draw is being
// submitted, and it is the discriminator Bliss uses for exactly this
// (Bliss-Shader-Unstable/shaders/world0/gbuffers_skytextured.fsh, which tests
// renderStage against MC_RENDER_STAGE_SUN / _MOON / _SKY). Iris defines the
// constants from its WorldRenderingPhase enum, whose order puts STARS at 6.
//
// The fallback is the same shape program/shadow/shadow.vsh uses for the stages
// it reads: `#ifndef` around the number, so a loader that does not define the
// name still compiles and still gets the right value, and a loader that does
// define it wins. The number is the enum's own ordinal and is written out here
// rather than derived, because a shader cannot read an enum.
#ifndef MC_RENDER_STAGE_STARS
	#define MC_RENDER_STAGE_STARS 6
#endif

// The pack draws its own stars in environment/sky/stars.glsl, so dropping this
// quad leaves one field rather than two. Nothing else is affected: the sky
// colour, the sunset band and the void plane are different stages and still
// reach the code below.
uniform int renderStage;

void main() {
	// The star field is the pack's own, drawn by SkyStars below. The game's is a
	// texture on a quad and is not wanted.
	if (renderStage == MC_RENDER_STAGE_STARS) {
		discard;
	}

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
