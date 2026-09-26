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
// nobody would think to look at. See PBR_PORTING.md 197.

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
// ⚠️ The End's ambient light in /environment/lighting/end_lighting.glsl is the
// same violet at a different scale - that one is a light colour, scaled so that
// its luminance matches the near-neutral colour it replaced, so that fixing the
// hue did not also make the dimension darker. Same hue, different scale, and
// deliberately so.
vec3 EndPaletteColor() {
	return mix(END_GIANT_WARM, END_GIANT_VIOLET, END_GIANT_TINT);
}

#endif // END_PALETTE_GLSL_INCLUDED
