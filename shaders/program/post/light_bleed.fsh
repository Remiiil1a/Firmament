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

// The frame as the deferred pass copied it, which is what the second source
// below is read from.
//
// A different buffer from colortex0 rather than the near neighbours of that
// one, and that is not a preference: this pass writes colortex0, and a pass
// that reads the pixels around the one it is writing is reading values it may
// itself have already overwritten this frame. composite6 gets away with doing
// that because the two pixels SMAA blends with are on the row or column the
// edge runs along and have not been reached yet; a gather in every direction
// has no such order to rely on, and what it would produce is a smear in the
// direction the rasteriser happens to run.
//
// Reading this one instead is safe and costs nothing: colortex4 is written by
// the deferred pass, which runs before every composite, so what is here is this
// frame's picture. It is also the same format as colortex0 - R11F_G11F_B10F,
// unsigned and with no exponent of its own - so it cannot hold a NaN, an
// infinity or a negative, and this gather needs no guard for one. If the
// deferred pass is skipped for a frame, this holds the previous frame's copy,
// which for a blur this wide is a frame-old version of the same picture.
uniform sampler2D colortex4;

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

// Whether the light that bounces off one surface onto another is drawn.
//
// The source above is the light a source gives off. This is the other half of
// what a room does with light, and the half Minecraft has nothing to say about:
// a sunlit red wall puts red onto the white wall beside it, a torch-lit floor
// lights the underside of the table above it, and the reason a corner is not
// simply "the sum of the lights pointing at it" is that every surface is also a
// source. Minecraft's own light is a flood fill - it has no notion of a surface
// giving light back - so without this the only light a surface can receive is
// light that came from a block marked as a lamp.
//
// The gather is the same disk as above, over the frame itself instead of over
// the lamp mask, and weighted by how bright each tap already is: what is bright
// is what is giving light back, and what is in shadow is not. The subtraction
// of a floor underneath that is what keeps ordinary ambient from being taken
// for a source - without it every surface in the scene bounces, and what that
// amounts to is a general brightening rather than anything that looks like
// light arriving from somewhere.
//
// It is an approximation and it behaves like one: it is a blur of what is
// already on screen, so it redistributes light rather than creating it, and it
// cannot reach a surface that is in shadow down a corridor. What it is for is
// the local case - the two surfaces that meet at a corner each giving the other
// their colour.
//
// Off costs nothing: the sampling it needs is compiled out with it, not merely
// branched around.
//
// Off by default, and that is a correction rather than a preference. b311
// shipped this on and the verdict from testing it was that the effect is not
// visible, which is the right verdict: the half that was cut for cost is the
// half that would have made it read as light - a surface's own orientation
// deciding how much of what surrounds it arrives - and without that this is a
// wide blur of the frame, close enough to the color bleed above it that turning
// it on changes very little. Worth turning on to look at; not worth paying for
// by default until the directional half exists. See PBR_PORTING.md 168.5 and
// 169.
//
// The #ifdef below, and not #if defined, is what makes this a switch at all.
// Iris only treats a bare #define as a boolean option when something has
// referenced it with #ifdef or #ifndef - see the note at the top of
// lib/sss.glsl. Written the other way the option does not appear in the menu at
// all, while the code behind it still compiles and runs.
//#define INDIRECT_BOUNCE

// How much of the bounced light is added.
//
// It is added rather than mixed in, like the light above it, and unlike that
// one it is taken from light that is already in the picture - so this is the
// one option here that can make the frame brighter than it was. If the result
// looks washed out rather than lit, lower this before lowering anything else.
#define INDIRECT_BOUNCE_STRENGTH 0.4 // [0.0 0.1 0.2 0.3 0.4 0.5 0.75 1.0 1.5]

// How bright a surface has to be before it counts as giving light back.
//
// A fraction of white: the ambient light every surface receives is already in
// the frame, and if all of it counted as a source then every surface would
// bounce and the effect would be a haze rather than a direction. Raising this
// narrows the effect to what is genuinely bright - sunlight, lava, a lit lamp -
// and lowering it brings ordinary surfaces in.
#define INDIRECT_BOUNCE_FLOOR 0.35 // [0.0 0.1 0.2 0.35 0.5 0.75 1.0]

// Taps per pixel. The taps are spread over the disk with a golden-angle spiral,
// which is the most even coverage a handful of taps can give - a regular
// pattern would show up as rings in the result. This is the pass's cost.
const int LIGHT_BLEED_TAPS = 16;

// The golden angle, in radians.
const float GOLDEN_ANGLE = 2.39996323;

// How much of a tap's own color counts as light it is giving back: the part of
// it brighter than the floor, as a fraction of the whole.
//
// A fraction rather than the amount above the floor, for the reason the bloom's
// threshold is built the same way: what is wanted is the colour of the light
// leaving that surface, and scaling a colour by a ratio keeps it the right
// colour whatever its brightness is. Keeping the difference instead would leave
// every result as much darker than its own surface as the floor is bright, for
// no reason a viewer could name.
float IndirectBounceWeight(vec3 color) {
	float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));

	return max(brightness - INDIRECT_BOUNCE_FLOOR, 0.0) / max(brightness, 1.0e-4);
}

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

	#ifdef INDIRECT_BOUNCE
		// The second source: what the surfaces around this pixel are giving
		// back, gathered over the same disk.
		vec3 bounce = vec3(0.0);
	#endif

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
		bool tapGlows = dot(tapMask, tapMask) >= 0.000001;

		#ifdef INDIRECT_BOUNCE
			// Every tap is a possible source of bounced light, whether or not
			// there is a lamp in it, so the frame is read before the mask is
			// asked about. That is what this option costs, and it is also why
			// the loop is shaped the way it is: the early out below has to stay
			// exactly where it was for the case where the option is off.
			vec3 tapSurface = texture(colortex4, tapCoord).rgb;
		#else
			// Most taps have nothing glowing in them, and skipping them here is
			// what keeps the depth fetch below - which every tap would
			// otherwise pay for - off the overwhelming majority of pixels.
			if (!tapGlows) {
				continue;
			}

			vec3 tapSurface = vec3(0.0);
		#endif

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
		float tapWeight = depthWeight * distanceFade * distanceFade;

		if (tapGlows) {
			bleed += tapMask * tapWeight;
		}

		#ifdef INDIRECT_BOUNCE
			bounce += tapSurface * (IndirectBounceWeight(tapSurface) * tapWeight);
		#endif
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

	#ifdef INDIRECT_BOUNCE
		// Divided by the tap count for the same reason the bleed is: what
		// matters is how much of the area around this pixel is glowing, so a
		// pixel beside a large bright surface receives more than one beside a
		// small one rather than both saturating. See the note on the division
		// above.
		bounce *= 1.0 / float(LIGHT_BLEED_TAPS);

		scene += bounce * INDIRECT_BOUNCE_STRENGTH;
	#endif

	gl_FragData[0] = vec4(scene, 1.0);
}
