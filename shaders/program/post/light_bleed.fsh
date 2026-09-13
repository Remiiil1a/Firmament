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

// Colored light bleed.
//
// Steadfast lights the whole world with a single block light color, so a soul
// lantern and a torch light a wall exactly the same way. Fixing that properly
// means knowing which light source is responsible for the light arriving at a
// position, which Minecraft does not tell a shader - its light map records how
// much light arrived, not what color it was or where it came from.
//
// What this pass does instead is spread the color of the light sources that are
// actually visible across the pixels around them, using the mask that the
// terrain shaders write into colortex6. A soul lantern therefore tints the wall
// beside it blue, and lava tints the stone around it orange.
//
// Two things it deliberately does not do, so that they are not mistaken for
// bugs:
//
//  * It adds light rather than recoloring what is already there. A surface that
//    block light has already lit strongly orange keeps that orange; the bleed
//    makes it less saturated rather than turning it fully blue.
//  * It works on what is on screen. A light source just off the edge of the
//    screen, or hidden behind something, contributes nothing.
//
// Being a screen-space effect it is also the reason a source can tint a surface
// it is not actually lighting, which is what the depth test below is for.

// The light source mask is colortex6, written by the terrain shaders and read
// here as the color of the light each visible light source gives off, black
// where nothing glows.
//
// Its format is declared in /program/world/lit.fsh, which is the program that
// writes it. That is where the rest of the pack declares its buffer formats as
// well, and the format name has to be declared as a constant alongside it - see
// the comment there.

uniform sampler2D colortex0;
uniform sampler2D colortex6;
uniform sampler2D depthtex0;

uniform vec2 windowToScreen;
uniform float viewHeight;

// How far the light of a source spreads, in pixels at 1080p.
//
// This is scaled to the actual resolution, so that the effect looks the same on
// any display. Larger values reach further but cost nothing extra - the tap
// count below is what sets the cost.
#define LIGHT_BLEED_RADIUS 12.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0]

// How much light the sources spread onto their surroundings.
//
// This is added on top of the lighting, so it brightens as well as colors. If
// surfaces near a light source look washed out rather than tinted, lower this;
// if the color is not visible at all against the block light, raise it.
#define LIGHT_BLEED_STRENGTH 3.0 // [0.0 0.5 1.0 1.5 2.0 3.0 4.0 6.0 8.0 10.0]

// How far a surface takes the color of the light sources near it, rather than
// keeping its own color and having theirs added on top.
//
// Adding light alone cannot turn an orange-lit wall blue: the wall already has
// a strong orange under it, and the result of pouring blue on top is a paler
// orange, not a blue wall. This pulls the surface's own color towards the color
// of the light around it at the same time, which is what a surface lit by a
// blue light actually does - it reflects mostly blue.
//
// The amount fades out with distance from the sources on its own, because it is
// driven by how much light source is in the neighborhood.
#define LIGHT_TINT_STRENGTH 0.7 // [0.0 0.25 0.5 0.7 0.85 1.0]

// How different in depth two pixels may be before light stops spreading
// between them.
//
// Without this, a light source would bleed straight through a wall onto
// whatever is in front of it. Raise it if the color stops too abruptly at the
// edges of objects; lower it if a light source appears to shine through the
// wall it is behind.
#define LIGHT_BLEED_DEPTH 0.02 // [0.002 0.005 0.01 0.02 0.05 0.1]

// Taps per pixel. The taps are spread over the disk with a golden-angle spiral,
// which is the most even coverage a handful of taps can give - a regular
// pattern would show up as rings in the result. This is the pass's cost.
const int LIGHT_BLEED_TAPS = 16;

// The golden angle, in radians.
const float GOLDEN_ANGLE = 2.39996323;

/* DRAWBUFFERS:0 */

void main() {
	vec2 screenCoord = gl_FragCoord.xy * windowToScreen;

	vec3 scene = texture(colortex0, screenCoord).rgb;
	float centerDepth = texture(depthtex0, screenCoord).r;

	// The sky is not a surface, so nothing can spill onto it, and it is not a
	// light source either. Its depth is exactly 1.0, as no geometry was drawn.
	if (centerDepth >= 1.0) {
		gl_FragData[0] = vec4(scene, 1.0);
		return;
	}

	// Offsets are given in UV, but built from a radius in pixels, so the disk
	// stays circular whatever the aspect ratio is.
	float radius = LIGHT_BLEED_RADIUS * viewHeight / 1080.0;

	vec3 bleed = vec3(0.0);

	for (int i = 0; i < LIGHT_BLEED_TAPS; i++) {
		// Distance from the center, spread so that the taps cover the disk
		// evenly rather than crowding it.
		float t = (float(i) + 0.5) / float(LIGHT_BLEED_TAPS);
		float angle = float(i) * GOLDEN_ANGLE;

		vec2 offset = vec2(cos(angle), sin(angle))
			* sqrt(t) * radius * windowToScreen;
		vec2 tapCoord = screenCoord + offset;

		// Sampling past the edge of the screen would smear the edge pixels
		// inwards, as the buffers wrap their sampling.
		if (any(lessThan(tapCoord, vec2(0.0)))
			|| any(greaterThan(tapCoord, vec2(1.0)))) {
			continue;
		}

		vec3 tapMask = texture(colortex6, tapCoord).rgb;

		// Most taps have nothing glowing in them, and skipping them here is
		// what keeps the depth fetch below - which every tap would otherwise
		// pay for - off the overwhelming majority of pixels.
		if (dot(tapMask, tapMask) < 0.000001) {
			continue;
		}

		float tapDepth = texture(depthtex0, tapCoord).r;

		// Reject taps that are on a different surface, so that a light does not
		// bleed through a wall onto what stands in front of it.
		float depthWeight = 1.0 - smoothstep(
			LIGHT_BLEED_DEPTH,
			LIGHT_BLEED_DEPTH * 2.0,
			abs(tapDepth - centerDepth));

		if (depthWeight <= 0.0) {
			continue;
		}

		// Fade with distance from the center of the disk, quadratically so
		// that the edge of the spread is not a visible cut-off.
		float distanceFade = 1.0 - t;
		bleed += tapMask * (depthWeight * distanceFade * distanceFade);
	}

	// Divided by the tap count rather than by the accumulated weight: what
	// matters is how much of the area around this pixel is glowing, so a pixel
	// next to a large light source gets more light than one next to a small
	// one, instead of both saturating.
	bleed *= 1.0 / float(LIGHT_BLEED_TAPS);

	// Pull the surface's own color towards the color of the light around it.
	//
	// The tint is reduced to its hue and scaled to keep its brightness, so this
	// turns the color rather than darkening it - the wall lit by a soul lantern
	// goes from orange to a violet-blue rather than merely getting darker. How
	// much of it applies is set by how much light source is nearby, which is
	// what makes it fade out away from the source on its own.
	float nearby = dot(bleed, vec3(0.2126, 0.7152, 0.0722));

	if (nearby > 0.0001) {
		vec3 tint = bleed / max(max(bleed.r, bleed.g), bleed.b);
		float amount = LIGHT_TINT_STRENGTH * clamp(nearby * 3.0, 0.0, 1.0);

		scene *= mix(vec3(1.0), tint, amount);
	}

	scene += bleed * LIGHT_BLEED_STRENGTH;

	gl_FragData[0] = vec4(scene, 1.0);
}
