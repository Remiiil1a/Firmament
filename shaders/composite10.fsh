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

// Added 2026-09-25 by Remiiil1a for Firmament - bloom's fourth pass: the
// vertical half of the blur, and the last pass that touches the buffer.
// See PBR_PORTING.md 166.

#version 150 compatibility

// The other half of composite9's blur, and the reason it reads colortex14 and
// writes colortex13: colortex13 is what composite9 read, and a pass cannot read
// and write one buffer at the same time. The two quarter-resolution buffers are
// therefore used in turn, one as the source and one as the destination, and
// this is the pass that leaves the finished wide level in colortex13, where
// final.fsh knows to look for it.
//
// This is the only pass in the pack that writes a buffer another pass had
// already read. That is safe because the reads are over: composite9 has
// finished with colortex13 by the time this one starts.

uniform sampler2D colortex14;

#include "/lib/bloom.glsl"

/* RENDERTARGETS: 13 */

layout(location = 0) out vec4 bloomBlurred;

uniform float viewWidth;
uniform float viewHeight;

void main() {
	vec2 quarterRes = vec2(viewWidth, viewHeight) * 0.25;
	vec2 screenCoord = gl_FragCoord.xy / quarterRes;
	vec2 texelSize = vec2(1.0) / quarterRes;

	bloomBlurred = vec4(
		BloomBlur(colortex14, screenCoord, vec2(0.0, BLOOM_RADIUS), texelSize),
		1.0);
}
