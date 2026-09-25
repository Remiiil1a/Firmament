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

// Added 2026-09-25 by Remiiil1a for Firmament - bloom's first pass: keep the
// part of the frame that blooms and drop it to half resolution.
// See PBR_PORTING.md 166.

#version 150 compatibility

// The threshold is applied here, before the picture is reduced, and that order
// is the opposite of what it looks like it should be. Testing after the blur
// would be cheaper - there would be a quarter of the pixels to test - and it is
// also wrong. A blur mixes a bright pixel with its neighbours, so a threshold
// that ran afterwards would be deciding on the mixed value: a small bright
// thing would fall below the threshold precisely because its light had been
// spread out, and the smaller and brighter the thing is, the less it would
// bloom. The glow would come from broad dim surfaces instead of from the
// torches and the lava it exists for.
//
// The reduction is a four-tap tent rather than the single bilinear fetch that
// halving a picture normally uses. Both average a 2x2 block - the bilinear
// filter does that on its own when the sample lands between four texels, which
// is where the position below puts it - but the tent reaches one texel further
// out in each direction, and that extra width is what keeps small bright things
// from flickering as they drift across the half-resolution grid.

uniform sampler2D colortex0;

// The specular highlight each pixel was given, as the surface programs left it
// in colortex15, so that it can be taken back out before the threshold is
// applied. See BLOOM_EXCLUDE_SPECULAR in lib/bloom.glsl for why a highlight is
// not something the glow should be built from in the first place.
uniform sampler2D colortex15;

// Both bloom levels are held in a floating-point format with an alpha channel,
// which is what lets a value above white survive in them. In an eight-bit
// buffer the bright pass would be pointless: the threshold only ever keeps
// values above 1.0, and that is exactly what an eight-bit buffer cannot store.
const int RGBA16F = 0;
const int colortex12Format = RGBA16F;

#include "/lib/bloom.glsl"

// colortex12 takes RENDERTARGETS rather than DRAWBUFFERS for the reason spelled
// out at length in composite4.fsh: DRAWBUFFERS cannot name a buffer above nine,
// and this is where its declaration lives because this is the first pass that
// writes it. composite8 declares colortex13 and composite9 declares colortex14
// in the same way.
/* RENDERTARGETS: 12 */

layout(location = 0) out vec4 bloomTight;

uniform float viewWidth;
uniform float viewHeight;

// The frame at one corner of the tent, less whatever of it was a highlight.
//
// The subtraction is done per tap rather than once at the centre because a
// highlight can be a single pixel wide: averaged over the whole tent, the
// smallest and brightest ones - which are exactly the ones that look worst when
// they bloom - would leave a ring of glow around themselves rather than
// disappearing with them.
//
// Clamped at zero so that a tap the highlight more than accounts for adds none
// of the glow rather than a negative amount of it. A negative would eat into a
// neighbour's glow in the average below, which is a worse failure than the one
// it would be fixing: dark holes in the glow instead of glow where there should
// be none.
vec3 BloomSource(vec2 screenCoord) {
	vec3 color = textureLod(colortex0, screenCoord, 0.0).rgb;

	#ifdef BLOOM_EXCLUDE_SPECULAR
		color = max(color - textureLod(colortex15, screenCoord, 0.0).rgb, vec3(0.0));
	#endif

	return color;
}

void main() {
	vec2 halfRes = vec2(viewWidth, viewHeight) * 0.5;

	// Where this fragment is, read as a position in the full-resolution frame.
	// It lands exactly between four of that frame's texels, which is what makes
	// each fetch below average a 2x2 block without any help.
	vec2 screenCoord = gl_FragCoord.xy / halfRes;
	vec2 reach = vec2(0.5) / halfRes;

	vec3 color = BloomSource(clamp(screenCoord + vec2(-reach.x, -reach.y), vec2(0.0), vec2(1.0)));
	color += BloomSource(clamp(screenCoord + vec2(reach.x, -reach.y), vec2(0.0), vec2(1.0)));
	color += BloomSource(clamp(screenCoord + vec2(-reach.x, reach.y), vec2(0.0), vec2(1.0)));
	color += BloomSource(clamp(screenCoord + vec2(reach.x, reach.y), vec2(0.0), vec2(1.0)));
	color *= 0.25;

	bloomTight = vec4(color * BloomContribution(color, BLOOM_THRESHOLD), 1.0);
}
