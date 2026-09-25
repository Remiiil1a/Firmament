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

// Added 2026-09-22 by Remiiil1a for Firmament - SMAA, as an alternative to the
// temporal anti-aliasing in lib/taa.glsl. See PBR_PORTING.md 140.
//
// SMAA is a morphological anti-aliasing: it finds the edges already in the
// finished image, works out what shape each one makes from a precomputed table
// of the sixteen ways a piece of an edge can look, and blends across the edge by
// the amount the table says. It has no history and no jitter, so it cannot smear
// anything and cannot accumulate anything - which is the whole of why it is here.
//
// The implementation is Mellow Shader's (Mellow_Shader_v3.4, global/post/smaa.glsl
// and program/composite9..11.fsh), which is itself the reference SMAA
// implementation of Jimenez et al, "SMAA: Enhanced Subpixel Morphological
// Antialiasing" (Eurographics 2012) - the search and area lookups below are the
// published algorithm and are kept as they are, including the exact addressing of
// the two lookup tables. What is Firmament's own is where the edge test gets its
// values from; see composite4.fsh.

// Whether to anti-alias the image morphologically.
//
// It is an alternative to the temporal anti-aliasing in lib/taa.glsl, not an
// addition to it. The two answer the same question in opposite ways: TAA renders
// each frame from a slightly different place and averages the frames, and SMAA
// leaves the frames alone and reshapes the edges in each one. Running both at
// once costs both their prices for one of their answers, and Mellow's own
// documentation says the same thing - "set temporal anti-aliasing to off or
// denoise only for best results".
//
// What SMAA does not do is denoise. It can only move an edge; it cannot average a
// per-frame sample out, so the dithered noise of the screen-space shadows, of the
// ambient occlusion and of the godrays is left exactly as it was drawn. With the
// temporal resolve off, that noise does not shimmer - the jitter is what made it
// move - but it is still a fixed dither rather than a smooth gradient. See the
// note on that in PBR_PORTING.md 140.
#define SMAA

// The #ifdef below is not decoration, and this is worth spelling out because the
// option it guards is invisible without it.
//
// Iris only treats a bare #define as a boolean option if the macro is referenced
// by an #ifdef or #ifndef somewhere in the pack's sources. Nothing in this feature
// branches on SMAA - the three passes are switched on and off from
// shaders.properties - so with no branch anywhere the macro is a plain
// preprocessor symbol, Iris does not offer it as a setting, and the option simply
// does not appear in the menu. What a user sees is two sliders for a feature with
// no switch to turn it on.
//
// The same rule and the same trick are in lib/sss.glsl, on SCREENSPACE_SHADOWS,
// where it is written down for the first time, and in
// environment/clouds/volumetric.glsl. The two options below live inside the branch
// because they only mean anything while SMAA is on, which is how
// environment/lighting/ssao.glsl holds the occlusion's own settings.
#ifdef SMAA

// How far apart two neighbouring pixels have to be before the edge between them
// is treated as one worth smoothing.
//
// Lower values find more edges, and find them in places where a texture's own
// detail is the only difference - which reads as the texture being blurred rather
// than as its edges being smoothed. Higher values miss real edges.
//
// This is measured in the space the display will show, not in the linear light
// this pack works in, and that is not a preference: a linear HDR value runs from
// zero to tens of thousands on this pack's buffers, so any fixed threshold is
// either below every difference in a bright region or above every difference in a
// dark one. See composite4.fsh for how the two are bridged.
#define SMAA_THRESHOLD 0.30 // [0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40]

// How far along an edge to look for the point where it ends.
//
// An edge that continues past this distance is treated as one that does not end
// near this pixel, so no blend is applied. Lower values are cheaper and leave
// long diagonal edges less smooth.
#define SMAA_SEARCH_DISTANCE 16 // [8 16 24 32 48 64]

// Show whether this feature is running, and where it stops if it is not.
//
// It exists because the switch above is not enough to answer the question it
// looks like it answers. Turning SMAA on and looking at the picture is a poor
// test: the edges it smooths are a few pixels wide, the temporal anti-aliasing in
// lib/taa.glsl smooths the same edges whenever it is on, and neither of those
// tells "SMAA is working" apart from "SMAA is off and TAA is doing all of it".
// What that leaves is a user who has turned the option on and cannot say whether
// anything happened.
//
// The view replaces the frame with two of the three stages' own buffers, in the
// red and green channels, so that what is on screen says which stage ran:
//
//   Red, from composite4: the edges it found. Red lines are the picture's edges
//   marked as edges, and red everywhere with no structure would be a threshold
//   so low that everything is an edge.
//
//   Green, from composite5: the blend weight the lookup table answered with.
//   Green only appears where red does, because a weight is only looked up at an
//   edge.
//
// The three readings, and they are unambiguous:
//
//   Yellow lines on black - both stages ran and the table answered. SMAA is on
//   and working, and everything above about its quality applies.
//
//   Red lines with no green - composite4 ran and composite5 did not, or the
//   lookup images in shaders.properties are not reaching the program. An unbound
//   image reads as zero and a weight of zero is no blend, which is the quiet
//   failure this arrangement was given on purpose; this view is what makes it
//   visible rather than invisible.
//
//   The ordinary picture - composite6 did not run at all, which means SMAA is
//   off. The view lives in that pass, so when the pass is skipped there is
//   nothing left to draw it with.
//
// It is under the development menu with the other views of this kind rather than
// on the anti-aliasing page: it is not a setting, and the pages that hold
// settings are for settings. See screen.DEBUG_VIEWS in shaders.properties.
//#define SMAA_DEBUG

#endif // SMAA

#if !defined(SMAA_DECLARATIONS)
#define SMAA_DECLARATIONS

	// The two lookup tables, which are images in the pack rather than anything
	// computed: /img/smaaArea.png holds, for each of the sixteen edge shapes and
	// each pair of distances to the ends of the edge, how much to blend and in
	// which direction; /img/smaaSearch.png holds how far past a run of pixels the
	// edge continues.
	//
	// They are bound to these names by shaders.properties, through the
	// customTexture directive - not through texture.<stage>.<name>, which names a
	// stage rather than a pass and silently ignores a name that is not one of its
	// seven. See the note there for what that cost. An image that is not bound
	// reads as zero, and an area value of zero is an edge with no blend - so a
	// binding that goes missing turns this feature off instead of corrupting the
	// picture. That is the failure this was given on purpose, and it is also why
	// the SMAA_DEBUG view below is worth having: it is the difference between that
	// failure and a working feature.
	//
	// Neither table is filtered the way a picture is, and both are filtered the way
	// the reference implementation expects: bilinear, clamped. It is not the
	// default - an image in a shader pack is nearest and wrapping unless it says
	// otherwise - and nearest is wrong here rather than merely less pretty. Both
	// lookups land between texels by design: the area lookup is indexed by how far
	// along the edge each end is, and the search lookup by how far the edge runs,
	// and both of those are continuous. Read with nearest, the distance is rounded
	// to the table's own resolution before it is ever used. The two .mcmeta files
	// beside the images are what say otherwise, and clamp is the other half of it:
	// a search that runs off the edge of the frame would otherwise wrap around and
	// read the opposite side of the table.
	uniform sampler2D smaaArea;
	uniform sampler2D smaaSearch;

	uniform float viewWidth;
	uniform float viewHeight;

#endif

// How different two pixels have to look to count as an edge.
//
// A plain Euclidean distance between two colours, weighted mostly by green
// because the eye is, and switched between two weightings by how red the midpoint
// is - which is the "redmean" approximation of how a person sees a colour
// difference, and is what the reference implementation uses.
float SmaaRedmean(vec3 a, vec3 b) {
	float r = step(0.5, mix(a.r, b.r, 0.5));
	vec3 d = a - b;

	return sqrt(dot(d * d, vec3(
		2.0 + r,
		4.0,
		3.0 - r
	)));
}

// How many pixels the edge continues past a sampled point, read out of the search
// table. The addressing is the reference implementation's and depends on the
// table's own size, which is 64 by 16.
float SmaaSearchLength(vec2 sample, float offset) {
	const vec2 SEARCH_TEX_SIZE = vec2(66.0, 33.0);

	vec2 scale = SEARCH_TEX_SIZE * vec2(0.5, -1.0) + vec2(-1.0, 1.0);
	vec2 bias = SEARCH_TEX_SIZE * vec2(offset, 1.0) + vec2(0.5, -0.5);

	scale /= vec2(64.0, 16.0);
	bias /= vec2(64.0, 16.0);

	return texture(smaaSearch, sample * scale + bias).r;
}

// Walk left along the edge until it stops, and return where that was.
//
// The edge buffer is passed in rather than read from a name declared here,
// because the pass that writes it is not the pass that reads it and the two do
// not have to agree on a name. See SmaaEdges in composite5.fsh.
float SmaaSearchXLeft(sampler2D edges, vec2 texcoord, float end) {
	vec2 e = vec2(0.0, 1.0);
	while (texcoord.x > end
		&& e.g > 0.8281 // Is there some edge not activated?
		&& e.r == 0.0) { // Or is there a crossing edge that breaks the line?
		e = texture(edges, texcoord).rg;
		texcoord -= vec2(2.0, 0.0) / vec2(viewWidth, viewHeight);
	}

	float offset = -(255.0 / 127.0) * SmaaSearchLength(e, 0.0) + 3.25;
	return texcoord.x + offset / viewWidth;
}

// The same, to the right.
float SmaaSearchXRight(sampler2D edges, vec2 texcoord, float end) {
	vec2 e = vec2(0.0, 1.0);
	while (texcoord.x < end
		&& e.g > 0.8281
		&& e.r == 0.0) {
		e = texture(edges, texcoord).rg;
		texcoord += vec2(2.0, 0.0) / vec2(viewWidth, viewHeight);
	}

	float offset = -(255.0 / 127.0) * SmaaSearchLength(e, 0.5) + 3.25;
	return texcoord.x - offset / viewWidth;
}

// And up, and down. Up is the negative direction, because the buffer's rows run
// downwards.
float SmaaSearchYUp(sampler2D edges, vec2 texcoord, float end) {
	vec2 e = vec2(1.0, 0.0);
	while (texcoord.y > end
		&& e.r > 0.8281
		&& e.g == 0.0) {
		e = texture(edges, texcoord).rg;
		texcoord -= vec2(0.0, 2.0) / vec2(viewWidth, viewHeight);
	}

	float offset = -(255.0 / 127.0) * SmaaSearchLength(e.gr, 0.0) + 3.25;
	return texcoord.y + offset / viewHeight;
}

float SmaaSearchYDown(sampler2D edges, vec2 texcoord, float end) {
	vec2 e = vec2(1.0, 0.0);
	while (texcoord.y < end
		&& e.r > 0.8281
		&& e.g == 0.0) {
		e = texture(edges, texcoord).rg;
		texcoord += vec2(0.0, 2.0) / vec2(viewWidth, viewHeight);
	}

	float offset = -(255.0 / 127.0) * SmaaSearchLength(e.gr, 0.5) + 3.25;
	return texcoord.y - offset / viewHeight;
}

// What the table says to do about an edge whose ends are d1 and d2 away, seen
// from the two sides e1 and e2. The table is 160 by 560 and this is its own
// addressing.
vec2 SmaaSampleArea(float d1, float d2, float e1, float e2) {
	vec2 coord = 16.0 * round(4.0 * vec2(e1, e2)) + vec2(d1, d2) + 0.5;
	return texture(smaaArea, coord / vec2(160.0, 560.0)).rg;
}
