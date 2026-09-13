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

// Temporal anti-aliasing: the sub-pixel offset this frame is rendered with.
// Uniforms: frameCounter, viewWidth, viewHeight
#include "/lib/taa.glsl"

out float isstars;

void main() {
	gl_Position = ftransform();

	// Temporal anti-aliasing: shift this frame's sample position inside the
	// pixel. Scaling by w keeps the offset constant in pixels rather than in
	// world space.
	gl_Position.xy += TaaJitter() * gl_Position.w;

	// Star detection from https://github.com/shaderLABS/Base-120
	// File: /shaders/gbuffers_skybasic.vsh
	isstars = float(gl_Color.r == gl_Color.g
		&& gl_Color.g == gl_Color.b
		&& gl_Color.r > 0.0);
}
