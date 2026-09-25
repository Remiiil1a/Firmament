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

// Added 2026-09-22 by Remiiil1a for Firmament - SMAA's second pass: how much to
// blend where. See PBR_PORTING.md 140.

#version 150 compatibility

// SMAA's second stage: for every pixel that has an edge on it, how far along it
// the two ends are, and what the table says to do about it.
//
// The edges came from composite4 and the answer goes to composite6. This is the
// expensive pass - each edge pixel that is found walks along its own edge looking
// for the end of it - which is why the first pass threw away everything that is
// not an edge before this one got the chance to look at it.
//
// The edge buffer is read through a parameter rather than a name declared here,
// so that the two passes agree on it by argument. The two lookup tables are read
// from names declared in the library, because they are read here and nowhere
// else; shaders.properties is what puts the images in them.

// The edges composite4 found. Two channels, read-write: never written here.
uniform sampler2D colortex10;

// The blend weights this pass produces, read by composite6. Four channels - left,
// up, right, down, in that order. Written on every pixel, so like the edge buffer
// it carries nothing from one frame to the next; a pixel with no edge on it is
// written as no blend at all.
const int RGBA8 = 0;
const int colortex11Format = RGBA8;

#include "/lib/smaa.glsl"

// colortex11, through RENDERTARGETS for the reason composite4 gives: DRAWBUFFERS
// cannot name a buffer above nine, and there is no letter form to use instead.
/* RENDERTARGETS: 11 */

layout(location = 0) out vec4 smaaWeights;

void main() {
	ivec2 pixel = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	vec2 pixelSize = vec2(1.0) / vec2(viewWidth, viewHeight);

	vec2 center = texelFetch(colortex10, pixel, 0).rg;

	// Zero everywhere by default, and left that way for every pixel that has no
	// edge - which is what makes the third pass a straight copy of the picture
	// for the great majority of the screen.
	vec4 weights = vec4(0.0);

	// The eight positions the ends of the edge are looked for from, and the four
	// limits the search stops at. This is the reference implementation's own
	// geometry: the ends are looked for a quarter of a pixel out on each side, so
	// that the search starts on the side of the edge the pixel is on, and it is
	// not allowed to run further than SMAA_SEARCH_DISTANCE.
	vec4 offsetPos[3];
	offsetPos[0] = pixelSize.xyxy * vec4(-0.25, -0.125, 1.25, -0.125) + screenCoord.xyxy;
	offsetPos[1] = pixelSize.xyxy * vec4(-0.125, -0.25, -0.125, 1.25) + screenCoord.xyxy;
	offsetPos[2] = pixelSize.xxyy
		* (vec4(-1.0, 1.0, -1.0, 1.0) * float(SMAA_SEARCH_DISTANCE))
		+ vec4(offsetPos[0].xz, offsetPos[1].yw);

	// An edge crossing this pixel's top side: the two ends are to its left and
	// right, and the blend is horizontal.
	if (center.g > 0.0) {
		vec3 coords;
		vec2 distance;

		coords.x = SmaaSearchXLeft(colortex10, offsetPos[0].xy, offsetPos[2].x);
		coords.y = offsetPos[1].y;
		distance.x = coords.x;

		float leftEdge = texture(colortex10, coords.xy).r;

		coords.z = SmaaSearchXRight(colortex10, offsetPos[0].zw, offsetPos[2].y);
		distance.y = coords.z;

		// How far each end is from this pixel, in pixels, and then square-rooted
		// - the table is indexed by distance along the edge, which grows with the
		// square of the screen distance.
		distance = sqrt(abs(round(vec2(viewWidth) * distance - gl_FragCoord.xx)));

		float rightEdge = texture(colortex10, coords.zy + vec2(1.0, 0.0) * pixelSize).r;

		weights.rg = SmaaSampleArea(distance.x, distance.y, leftEdge, rightEdge);
	}

	// And an edge crossing its left side, which is the same thing turned a
	// quarter turn.
	if (center.r > 0.0) {
		vec3 coords;
		vec2 distance;

		coords.y = SmaaSearchYUp(colortex10, offsetPos[1].xy, offsetPos[2].z);
		coords.x = offsetPos[0].x;
		distance.x = coords.y;

		float topEdge = texture(colortex10, coords.xy).g;

		coords.z = SmaaSearchYDown(colortex10, offsetPos[1].zw, offsetPos[2].w);
		distance.y = coords.z;

		distance = sqrt(abs(round(vec2(viewHeight) * distance - gl_FragCoord.yy)));

		float bottomEdge = texture(colortex10, coords.xz + vec2(0.0, 1.0) * pixelSize).g;

		weights.ba = SmaaSampleArea(distance.x, distance.y, topEdge, bottomEdge);
	}

	smaaWeights = weights;
}
