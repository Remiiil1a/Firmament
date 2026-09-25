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

// Added 2026-09-25 by Remiiil1a for Firmament - bloom's second pass: reduce the
// bright parts again, to a quarter of the screen.
// See PBR_PORTING.md 166.

#version 150 compatibility

// The wide half of the bloom, built by reducing what composite7 kept rather
// than by blurring it very widely at half resolution. Reducing is not only
// cheaper - each texel here stands for sixteen of the original frame's, so the
// blur that follows travels four times as far across the picture for the same
// tap count - it is also smoother, since every step of the way has averaged
// real neighbours rather than reaching past them.
//
// There is no threshold here. It has already been applied, and applying it
// twice would not be the same threshold: the values arriving here have been
// averaged, so a second test at the same number would reject a dim halo that
// the first one deliberately kept.

uniform sampler2D colortex12;

// Declared here rather than in composite10, which is the other pass that writes
// colortex13: the format belongs to the buffer, not to the pass, and declaring
// it twice invites the two declarations to drift apart.
const int RGBA16F = 0;
const int colortex13Format = RGBA16F;

#include "/lib/bloom.glsl"

/* RENDERTARGETS: 13 */

layout(location = 0) out vec4 bloomWide;

uniform float viewWidth;
uniform float viewHeight;

void main() {
	vec2 quarterRes = vec2(viewWidth, viewHeight) * 0.25;

	// The same trick as composite7's, one level down: this position lands
	// between four of colortex12's texels, so each fetch averages a 2x2 block of
	// that buffer, which is a 4x4 block of the frame.
	vec2 screenCoord = gl_FragCoord.xy / quarterRes;
	vec2 reach = vec2(0.5) / quarterRes;

	vec3 color = textureLod(colortex12, clamp(screenCoord + vec2(-reach.x, -reach.y), vec2(0.0), vec2(1.0)), 0.0).rgb;
	color += textureLod(colortex12, clamp(screenCoord + vec2(reach.x, -reach.y), vec2(0.0), vec2(1.0)), 0.0).rgb;
	color += textureLod(colortex12, clamp(screenCoord + vec2(-reach.x, reach.y), vec2(0.0), vec2(1.0)), 0.0).rgb;
	color += textureLod(colortex12, clamp(screenCoord + vec2(reach.x, reach.y), vec2(0.0), vec2(1.0)), 0.0).rgb;
	color *= 0.25;

	bloomWide = vec4(color, 1.0);
}
