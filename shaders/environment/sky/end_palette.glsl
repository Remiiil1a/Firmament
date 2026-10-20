// Firmament: the End's palette, in one place.
//
// Copyright (C) 2026 Remiiil1a. Part of Firmament, an edit of coderbot's
// Steadfast; see NOTICE.md for the licence this is distributed under.
//
// Added 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's
// Steadfast).

// The colour of the End's body, and of the air the End's light is scattered by.
//
// ⚠️ This exists as a file of its own because two things need it and they are in
// two different programs: the body, in the sky pass, which includes
// environment/sky/end.glsl, and the medium the light shafts are drawn in, in the
// volumetric fog pass, which includes environment/effects/volumetric_fog.glsl.
//
// The user's requirement for the second of those was that the End's volumetric
// fog "stay consistent with the body's colour", and this is how that is
// guaranteed rather than hoped for: two copies of a colour are two colours the
// moment one of them is edited, and the copy in the other program is the one
// nobody would think to look at. See BATCH_LOG.md 197.

#ifndef END_PALETTE_GLSL_INCLUDED
#define END_PALETTE_GLSL_INCLUDED

// The body's colour, from a warm white at 0.0 to the End's own violet at 1.0.
//
// ⚠️ Both ends were made properly saturated in batch 338, and the shipped default
// was moved to the violet end of the range in v0.7 - it is 1.0 now. Before batch
// 338 the violet end was vec3(0.88, 0.82, 1.00) - so pale that mixing 35% of it
// into a warm white gave vec3(0.958, 0.892, 0.870), which is a slightly warm
// white and not violet at all: the option could not reach the colour it was named
// after, and no setting of it could have. See CHANGELOG.md for v0.7, where the
// whole set of retuned defaults is listed.
//
// ⚠️ Declared here rather than in end.glsl as of batch 340, so that the
// volumetric fog pass - which does not include end.glsl and has no reason to -
// can read the same option and the same two colours.
#define END_GIANT_TINT 1.0 // [0.0 0.25 0.5 0.65 0.75 1.0]

// The two ends of that range.
const vec3 END_GIANT_WARM = vec3(1.00, 0.93, 0.80);
const vec3 END_GIANT_VIOLET = vec3(0.62, 0.42, 1.00);

// The colour at the chosen tint: the body's own colour, and what the End's air
// is tinted with where the volumetric fog is drawn there.
//
// ⚠️ The End's ambient light in /environment/lighting/end_lighting.glsl is a
// violet too, retuned in the same batch 338, but it is not this colour. That one
// is `vec3(0.78, 0.48, 1.34)` - a light colour, scaled so that its luminance
// matches the near-neutral colour it replaced, so that fixing the hue did not
// also make the dimension darker. Read the two as the same violet family and
// the same intent, not as one value: they differ in hue as well as in scale
// (this end of the range is 0.62 : 0.42 : 1.00), and end_lighting.glsl explains
// its own compensation in full.
vec3 EndPaletteColor() {
	return mix(END_GIANT_WARM, END_GIANT_VIOLET, END_GIANT_TINT);
}


// ---------------------------------------------------------------------------
// The star field, moved here from end.glsl in batch 612.
//
// The palette lives here because two programs need it; the stars live here for
// the same reason. end.glsl is a sky program and cannot be included by one that
// is not - it reads uniforms only a sky pass declares - so the portal effect in
// program/world/lit.fsh includes this file instead and calls the same
// EndStarfield, which is what keeps its stars on END_STAR_TINT.
// ---------------------------------------------------------------------------
// How crowded the starfield is. The star threshold is 0.04 * this, so the count
// is directly proportional to it and 0.0 leaves an empty sky. The steps below
// are not a constant ratio: each one raises the count by between about 1.3x and
// 2x, so this is a fine control rather than a sequence of doublings.
#define END_STAR_DENSITY 2.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]

// How bright the stars are. Apart from the body below, they are the only thing
// in the End brighter than the surface of a lit block, so raising this makes
// the sky dominate more.
#define END_STAR_BRIGHTNESS 3.0 // [0.0 0.5 0.75 1.0 1.5 2.0 3.0]

// How large a single star is drawn, as a multiple of its natural size. Added in
// batch 333 at the user's request.
//
// The starfield is a grid laid over the sky with one star to a cell, and each
// star is a disc drawn inside its own cell - see EndStarfield below. This
// scales that disc's radius, so it changes how big the stars look without
// changing how many there are. END_STAR_DENSITY above is the one that decides
// how many cells hold a star at all.
//
// ⚠️ This note used to describe a ceiling: the field only ever looks at the one
// cell the view direction falls into, so a disc that reached past a cell wall
// came out with a straight edge sliced off it, and the steps stopped short of
// that. Batch 339 removed the cause instead of ducking it - the star is now
// placed inset from the walls by its own radius, which costs nothing and makes
// the ceiling go away. See the inset in EndStarfield and BATCH_LOG.md 196.
#define END_STAR_SIZE 2.0 // [0.5 0.75 1.0 1.25 1.5 2.0 2.5]

// How far the field is moved towards violet.
//
// Added in batch 339 at the user's request. 0.0 leaves the field exactly as it
// was - a range from hot blue through to cool orange - and 1.0 is a violet
// field. In between, both ends of the range move together rather than the
// colours being replaced by one, so the field keeps its variety at every
// setting instead of flattening into a single colour as it turns.
//
// ⚠️ The shipped default is 1.0 as of v0.7 - the fully violet end - because the
// release's defaults are the user's own settings. See CHANGELOG.md under v0.7.
//
// ⚠️ This is the End's field only. The Overworld's stars are a different
// implementation - environment/sky/stars.glsl - and are not affected by it.
#define END_STAR_TINT 1.0 // [0.0 0.25 0.5 0.75 1.0]

// A hash on a cell of the star grid. Standard integer-free hash, chosen for
// being short and for not producing visible structure when fed cell corners.
float EndSkyHash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

vec3 EndSkyHash3(vec3 p) {
	return vec3(
		EndSkyHash(p),
		EndSkyHash(p + 19.19),
		EndSkyHash(p + 43.71));
}

// The stars.
//
// They are placed one to a cell of a grid laid over the sky, at a random
// position inside an inset of that cell - see the note in the function for why
// the inset is there - and only some of the cells hold one at all. A grid
// is used rather than anything cleverer because it needs no state and no
// texture: the whole starfield is a hash of which cell the view direction
// happens to be in.
vec3 EndStarfield(vec3 worldDir) {
	// Cells across the sky. This sets the grid's pitch, so it decides how many
	// stars fit across the sky and, with it, the scale the size option below is
	// measured against - a star cannot be larger than the cell it sits in. Use
	// END_STAR_SIZE to change how large a star looks; this one changes how many
	// there are room for.
	const float CELLS = 60.0;

	vec3 scaled = worldDir * CELLS;
	vec3 cell = floor(scaled);
	vec3 local = fract(scaled);

	// Whether this cell holds a star, and if so, where in the cell it sits.
	float roll = EndSkyHash(cell + 31.7);

	if (roll > 0.04 * END_STAR_DENSITY) {
		return vec3(0.0);
	}

	// Bright stars are also slightly larger. Varying both together is what
	// makes a starfield read as having depth instead of looking like noise.
	float magnitude = 0.35 + 0.65 * EndSkyHash(cell + 11.3);

	// Scaled by END_STAR_SIZE; see the note on that option.
	float radius = (0.06 + 0.05 * magnitude) * END_STAR_SIZE;

	// ⚠️ The star is placed inset from its cell's walls by its own radius, and
	// that inset is the whole reason the star is not cut in half.
	//
	// This field only ever evaluates the one cell the view direction falls into.
	// There is no loop over the neighbours, which is what keeps it to a handful
	// of hashes per sky fragment instead of the twenty-seven the Overworld's
	// field costs. The price of that is that a star whose disc reaches past a
	// wall is only drawn as far as the wall: the rest of it lies in a
	// neighbouring cell, which is evaluated as a different star or as none at
	// all, and the star comes out with a straight edge sliced off it.
	//
	// And a star could sit anywhere in its cell, so roughly half of them had at
	// least one edge sliced off, because a ball of radius r centred uniformly in
	// a unit cube stays inside it only (1 - 2r)^3 of the time, which at r = 0.1
	// is about a half. It was easy to miss on its own and impossible to miss
	// once the lens magnified the field, which is how the user found it.
	//
	// Insetting fixes it for nothing at all: a disc of radius r placed at least
	// r from every wall cannot reach one. The margin is the largest radius any
	// star can have, which is the one with magnitude 1.0, so the inequality
	// holds for every star and not just the average one. See BATCH_LOG.md 196.
	//
	// ⚠️ The clamp is what keeps the inequality true if the size option is ever
	// pushed past 0.46 / 0.11, which is 4.18: past that the margin stops growing
	// (it is pinned at 0.46) while the largest radius keeps growing with the
	// option, and the slicing would come back. The steps offered stop at 2.5,
	// well short of it.
	float margin = min(0.11 * END_STAR_SIZE, 0.46);
	vec3 starPos = margin + EndSkyHash3(cell) * (1.0 - 2.0 * margin);

	float distance = length(local - starPos);

	float star = 1.0 - smoothstep(0.0, radius, distance);
	star *= star;

	// Stars are not all white: the range runs from hot blue to cool orange, and
	// END_STAR_TINT moves both ends of it towards violet together, so that the
	// field keeps its variety however far it has been turned.
	vec3 cool = mix(vec3(0.72, 0.82, 1.0), vec3(0.55, 0.42, 1.15),
		END_STAR_TINT);
	vec3 warm = mix(vec3(1.0, 0.86, 0.72), vec3(0.85, 0.58, 1.10),
		END_STAR_TINT);
	vec3 tint = mix(cool, warm, EndSkyHash(cell + 5.1));

	// 1.6 puts the brightest stars above white, which is what makes them read
	// as points of light rather than as white dots. The color it puts above
	// white is the blue channel (1.15, 1.10 or 1.0 depending on the tint), which
	// is the "hot" end of the range; the red channel sits at 1.0 or just under.
	return tint * (star * magnitude * 1.6 * END_STAR_BRIGHTNESS);
}

// The nebula band's two colours. A nebula in one colour reads as a stain rather
// than as a cloud, and this pair is the one the End's own palette suggests: its
// violet, with a cold cyan to give the band somewhere to go.
const vec3 END_GIANT_NEBULA_VIOLET = vec3(0.34, 0.22, 0.62);
const vec3 END_GIANT_NEBULA_TEAL = vec3(0.10, 0.42, 0.48);

#endif // END_PALETTE_GLSL_INCLUDED
