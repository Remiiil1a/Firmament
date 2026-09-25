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

// Added 2026-09-25 by Remiiil1a for Firmament - bloom's third pass: the
// horizontal half of the blur. See PBR_PORTING.md 166.

#version 150 compatibility

// A Gaussian blur is separable - blurring along x and then along y gives the
// same result as one two-dimensional blur, for a fraction of the fetches - so
// the wide level is blurred by this pass and composite10, in that order, and
// neither of them is a blur on its own.
//
// Both halves are needed and the order does not matter. What does matter is
// that they run at all: one of them alone is a streak, not a glow.

uniform sampler2D colortex13;

const int RGBA16F = 0;
const int colortex14Format = RGBA16F;

#include "/lib/bloom.glsl"

/* RENDERTARGETS: 14 */

layout(location = 0) out vec4 bloomBlurred;

uniform float viewWidth;
uniform float viewHeight;

void main() {
	vec2 quarterRes = vec2(viewWidth, viewHeight) * 0.25;
	vec2 screenCoord = gl_FragCoord.xy / quarterRes;
	vec2 texelSize = vec2(1.0) / quarterRes;

	bloomBlurred = vec4(
		BloomBlur(colortex13, screenCoord, vec2(BLOOM_RADIUS, 0.0), texelSize),
		1.0);
}
