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

out vec4 tinting;
out vec2 texcoord;

void main() {
	tinting = gl_Color;
	texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

	// Compressed version of the transforms from lit.vsh
	// We must use the EXACT same order of operations or else
	// we will get Z-fighting from floating-point imprecision.
	//
	// Always keep this in sync with the transformations in
	// that file!
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;
	gl_Position = gl_ProjectionMatrix * viewPos;

	// Temporal anti-aliasing: shift this frame's sample position inside the
	// pixel. Scaling by w keeps the offset constant in pixels rather than in
	// world space.
	gl_Position.xy += TaaJitter() * gl_Position.w;
}
