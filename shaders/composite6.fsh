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

// Added 2026-09-22 by Remiiil1a for Firmament - SMAA's third pass: blend across
// the edges. See PBR_PORTING.md 140.

#version 150 compatibility

// SMAA's last stage: take the weights composite5 worked out and use them to
// average each edge pixel with the two pixels across its edge.
//
// The blend happens in the linear HDR frame and not in the tonemapped one, which
// is the one deliberate difference from the reference implementation - it works on
// display values throughout, and here the display values exist only inside
// composite4's edge test. A weighted average of light is what the operation means,
// so linear is where it belongs; the pixel is tonemapped once, by final.fsh, on
// its way out, exactly as it was before this feature existed.
//
// The picture is read and written in place. That is what every implementation of
// this stage does in a shader mod, and it is only safe because the two pixels it
// reads are the ones either side of this pixel on the row or column the edge runs
// along: at the moment this pixel is written, the pass has not reached them.
// Nothing outside the blend is allowed to read colortex0 after this.

// The frame, in and out.
uniform sampler2D colortex0;

// What composite5 worked out: how much of the pixel on each side of this one to
// mix in, as left, up, right, down.
uniform sampler2D colortex11;

// The edges composite4 found. Only the SMAA_DEBUG view below reads it, and it is
// read here rather than in composite5 because a view has to be drawn by the pass
// that puts something on the screen - see the note on SMAA_DEBUG in lib/smaa.glsl.
uniform sampler2D colortex10;

uniform float viewWidth;
uniform float viewHeight;

/* DRAWBUFFERS:0 */

layout(location = 0) out vec4 finalColor;

void main() {
	ivec2 pixel = ivec2(gl_FragCoord.xy);
	ivec2 limit = ivec2(viewWidth, viewHeight) - ivec2(1);
	vec2 screenCoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	vec2 pixelSize = vec2(1.0) / vec2(viewWidth, viewHeight);

	// The weight of the pixel on each of the four sides, and the weight of the
	// one an edge to the right or below would be told to use. A weight is written
	// against the pixel the edge belongs to and is read from the pixel the blend
	// would take from, which is why the right and bottom reads are offset.
	float left = texelFetch(colortex11, pixel, 0).b;
	float up = texelFetch(colortex11, pixel, 0).r;
	float right = texelFetch(colortex11, clamp(pixel + ivec2(1, 0), ivec2(0), limit), 0).a;
	float down = texelFetch(colortex11, clamp(pixel + ivec2(0, 1), ivec2(0), limit), 0).g;

	float total = left + up + right + down;

	#ifdef SMAA_DEBUG
		// Whether SMAA is running, and where it stops if it is not: red is an edge
		// composite4 found, green is a weight composite5 answered with. Yellow
		// lines mean both ran; red on its own means the lookup images are not
		// reaching composite5; the ordinary picture means this pass did not run at
		// all. See lib/smaa.glsl for the whole reading.
		vec2 edgesHere = texelFetch(colortex10, pixel, 0).rg;

		finalColor = vec4(
			clamp(max(edgesHere.x, edgesHere.y), 0.0, 1.0),
			clamp(total, 0.0, 1.0),
			0.0,
			1.0);
		return;
	#endif

	// No weight on any side means no edge reaches this pixel, which is most of
	// the screen: the picture is copied and nothing else happens.
	if (total > 0.01) {
		// An edge is either roughly horizontal or roughly vertical, and the
		// weights decide which by which pair is the stronger. The blend then
		// takes the two pixels across the edge, in proportion to their weights.
		bool horizontal = max(left, right) > max(down, up);
		vec4 offsets = horizontal
			? vec4(-left, 0.0, right, 0.0)
			: vec4(0.0, -up, 0.0, down);
		vec2 blend = horizontal ? vec2(left, right) : vec2(up, down);
		blend /= dot(blend, vec2(1.0));

		vec3 blended = textureLod(
			colortex0,
			screenCoord + offsets.xy * pixelSize,
			0.0).rgb * blend.x;
		blended += textureLod(
			colortex0,
			screenCoord + offsets.zw * pixelSize,
			0.0).rgb * blend.y;

		finalColor = vec4(blended, 1.0);
		return;
	}

	finalColor = vec4(textureLod(colortex0, screenCoord, 0.0).rgb, 1.0);
}
