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

// Added 2026-09-22 by Remiiil1a for Firmament - SMAA's first pass: find the
// edges. See PBR_PORTING.md 140.

#version 150 compatibility

// SMAA's first stage: which pixels have an edge between them and their
// neighbours, written into colortex10 for the two passes after this one.
//
// Three passes rather than one, because the reference algorithm is three: this
// one marks the edges, composite5 looks along each edge for where it ends and
// reads the blend out of a table, and composite6 applies it. Splitting it that
// way is what makes it a morphological filter rather than a blur - the blend
// depends on the shape the edge makes, and the shape is not known until the whole
// edge has been walked.
//
// This is the pass where the difference between this pack and Mellow's shows.
// Mellow runs its SMAA on a picture that has already been tonemapped, in the
// values the display will show, which is what the algorithm's threshold is
// written for. This pack cannot: the tonemap is in final.fsh, which is the last
// program there is, and nothing can run after it - so a pass here is handed the
// linear HDR frame and has to reach the display's own values by itself.
//
// So every sample this pass compares is tonemapped and sRGB-encoded on the spot,
// exactly as final.fsh is about to do to it. The edge test then asks the question
// the algorithm intends - "do these two pixels look different to a person" - and
// the blending in composite6 is left in linear light, which is where a weighted
// average belongs. Mellow does the opposite for the second half: it blends in
// display space and converts the result back. Neither is wrong; this one avoids
// putting an 8-bit display-space value through a buffer.
//
// What this cannot see is anything final.fsh does after the tonemap's input is
// fixed: the godrays, the motion blur and the vignette are added there, and none
// of them is in colortex0 yet. All three are smooth gradients with no edges to
// find, so what they contribute to the test is nothing worth having.

// The frame as it was left by the pass before this one, in linear HDR light.
uniform sampler2D colortex0;

// The edge buffer this pass fills, as one byte per channel: two edges, and
// nothing else. Every pixel is written on every path through this pass - the
// early exit writes a zero - so it never needs clearing and holds nothing from
// one frame to the next.
const int RGBA8 = 0;
const int colortex10Format = RGBA8;

// The pack's tonemap and its own sRGB conversion, which are what turn the linear
// frame into the values the display is about to be given. Included here rather
// than only in final.fsh because this is the second place that needs them, and
// the whole point of the pass is that the two agree.
#include "/environment/tonemap_settings.glsl"
#include "/lib/tonemap_uncharted2.glsl"
#include "/lib/tonemap_uchimura.glsl"
#include "/lib/srgb.glsl"

// The SMAA options, and the view size this pass needs to keep its neighbour
// fetches inside the frame.
#include "/lib/smaa.glsl"

// colortex10, and it takes RENDERTARGETS where every other pass in this pack
// takes DRAWBUFFERS.
//
// DRAWBUFFERS is the older of the two directives and it cannot name a buffer
// above nine. It is read one character per buffer, so "DRAWBUFFERS:10" is the two
// buffers 1 and 0 rather than the one buffer ten, and what Iris then says is
// "Pass sizes must match for drawbuffers [1, 0] / Original width: 960 New width:
// 1920" - because colortex1 is the godrays at half resolution, so the pass was
// being asked to write two buffers of different sizes. There is no letter form
// and there never was; RENDERTARGETS is the directive that reaches all sixteen,
// and it takes a comma-separated list.
//
// The numbers in the list are the attachment indices the GLSL writes to, not the
// buffer names: with one entry, index 0 is colortex10, which is what smaaEdges
// below is. RENDERTARGETS is an Iris directive where DRAWBUFFERS is the one
// OptiFine has too, which costs this pack nothing - it is Iris-only already, for
// the Voxy support.
//
// composite5 does the same thing for colortex11. composite6 writes colortex0,
// which DRAWBUFFERS can name, so it keeps the older directive and matches the
// rest of the pack.
/* RENDERTARGETS: 10 */

layout(location = 0) out vec4 smaaEdges;

// What the display will show for this pixel, computed the way final.fsh computes
// it.
//
// The clamp is not decoration. LinearToSrgb is a pow(), and a pow() with a
// negative base is undefined in GLSL and comes out as a NaN on the drivers this
// pack has been tested on - which is the failure that made a black blot on
// reflective surfaces in PBR_PORTING.md 139. colortex0 is an unsigned format and
// cannot hold a negative number, so a negative cannot arrive here today; the clamp
// is what keeps that from being the only thing standing between this pass and a
// NaN, and it costs one instruction.
vec3 DisplayValue(vec3 linearColor) {
	vec3 light = clamp(linearColor, vec3(0.0), vec3(1.0e18));

	#if TONEMAP == TONEMAP_UNCHARTED2
		vec3 tonemapped = Uncharted2Tonemap(light);
	#else
		vec3 tonemapped = UchimuraTonemap(light);
	#endif

	return LinearToSrgb(clamp(tonemapped, vec3(0.0), vec3(1.0)));
}

// The display value of a pixel, with the fetch kept inside the frame.
//
// The reference implementation fetches out of bounds at the border and lets the
// driver answer with whatever it answers; some drivers return the edge texel and
// some return garbage, and garbage at the border is an edge, which is a ring of
// blend around the outermost pixels. Clamping is one line and removes the
// question.
vec3 DisplayAt(ivec2 pixel) {
	ivec2 limit = ivec2(viewWidth, viewHeight) - ivec2(1);
	return DisplayValue(texelFetch(colortex0, clamp(pixel, ivec2(0), limit), 0).rgb);
}

void main() {
	ivec2 pixel = ivec2(gl_FragCoord.xy);

	// The three pixels the edge test is defined on: this one, the one before it
	// on its row and the one before it in its column.
	vec3 center = DisplayAt(pixel);
	vec3 left = DisplayAt(pixel + ivec2(-1, 0));
	vec3 up = DisplayAt(pixel + ivec2(0, -1));

	vec2 difference = vec2(
		SmaaRedmean(center, left),
		SmaaRedmean(center, up));

	// The pattern of edges is stored as the pair of booleans the reference
	// algorithm stores: whether the edge crosses this pixel's left side, and
	// whether it crosses its top side.
	vec2 edges = step(SMAA_THRESHOLD, difference);

	// Most of the screen has no edge on it, and the reference implementation
	// stops here rather than fetching the four pixels below - which is the whole
	// of why this pass is cheap on a picture that is mostly flat.
	if (all(lessThan(edges, vec2(0.01)))) {
		smaaEdges = vec4(0.0);
		return;
	}

	// The edge is kept only if it is a local maximum of the difference among the
	// pixels around it, which is what stops a gradual gradient from being marked
	// as an edge from one end to the other. This is the reference
	// implementation's own test, and the four fetches it needs are why the early
	// exit above exists.
	vec3 right = DisplayAt(pixel + ivec2(1, 0));
	vec3 down = DisplayAt(pixel + ivec2(0, 1));
	vec3 left2 = DisplayAt(pixel + ivec2(-2, 0));
	vec3 up2 = DisplayAt(pixel + ivec2(0, -2));

	vec2 differenceForward = vec2(
		SmaaRedmean(center, right),
		SmaaRedmean(center, down));
	vec2 differenceBackward = vec2(
		SmaaRedmean(center, left2),
		SmaaRedmean(center, up2));

	vec2 largest = max(max(difference, differenceForward), differenceBackward);
	edges *= step(max(largest.x, largest.y), difference * 2.0);

	smaaEdges = vec4(edges, 0.0, 0.0);
}
