// Firmament: the star field.
//
// Copyright (C) 2026 Remiiil1a. Part of Firmament, an edit of coderbot's
// Steadfast; see NOTICE.md for the licence this is distributed under.

// The pack used to leave the vanilla star quads to the game and fill whatever
// it recognized as one with pure white. That recognition was a flat-colour
// test, the game's own sky quad fails it only by luck, and in rain it stopped
// failing it - which is what turned the whole sky white. See
// program/world/sky.fsh for that story.
//
// With the white gone there was nothing left drawing stars, so this draws them
// instead. A texture would have to be shipped and bound for that, and the sky
// already has a direction to work from, so the field is generated: a grid of
// cells is laid over the view direction, most cells are empty, and every cell
// that is not holds one point with its own position, brightness and colour.
//
// This costs 27 cell hashes per sky fragment. The empty cells - the large
// majority - cost one hash and nothing else, which is why the density can stay
// this low without the loop being the expensive part.

#ifndef SKY_STARS_GLSL_INCLUDED
#define SKY_STARS_GLSL_INCLUDED

// rainStrength and worldSunVector both arrive from environment/sky.glsl, which
// is included ahead of this file: this reads the two of them and declares
// neither, so that a program which includes the sky can only ever end up with
// one declaration of each.

// Draw stars at all. Named values rather than 0 and 1, so that the menu shows
// it as the switch every other toggle in the pack is, rather than as a number.
#define STARS_ON 1
#define STARS_OFF 0
#define STARS STARS_ON // [STARS_OFF STARS_ON]

// The peak brightness of a single star, before the tonemapper. This is the one
// knob that decides whether the field reads as a sky or as a light show.
#define STAR_BRIGHTNESS 5.0 // [0.5 1.0 1.5 2.0 3.0 5.0 8.0]

// Cells across the sky sphere. More cells means more stars and smaller ones.
#define STAR_CELLS 48.0 // [16.0 24.0 32.0 48.0 64.0 96.0]

// The fraction of cells that hold a star.
#define STAR_DENSITY 0.08 // [0.01 0.02 0.03 0.05 0.08 0.12]

// A star's radius, in cells. At the default of 48 cells this is under a fifth
// of a degree - a couple of pixels on a 1080p screen - which is what a star
// should be. Past that it stops reading as a point.
#define STAR_RADIUS 0.15 // [0.05 0.1 0.15 0.25 0.35 0.45]

// Three values in [0, 1) from one cell coordinate. The same construction the
// rest of the pack uses for its screen-space noise, so there is only one kind
// of hash to reason about.
vec3 StarHash(vec3 cell) {
	return fract(sin(vec3(
		dot(cell, vec3(127.1, 311.7, 74.7)),
		dot(cell, vec3(269.5, 183.3, 246.1)),
		dot(cell, vec3(113.5, 271.9, 124.6)))) * 43758.5453);
}

// The light the star field adds in the given direction.
//
// Takes a unit world direction, the same one SkyColor() is given, so that the
// stars and the sky agree about where the sky is.
vec3 SkyStars(vec3 worldDir) {
#if STARS == STARS_OFF
	return vec3(0.0);
#else
	// Stars belong to the night. They fade in with the sun rather than
	// switching on at it, they fade out with the last of the daylight, and rain
	// covers them the same way it greys the sky.
	float night = smoothstep(0.0, -0.12, worldSunVector.y);
	night *= 1.0 - rainStrength;
	// And nothing below the horizon: that part of the sky quad is the plane the
	// game draws under the world, not sky.
	night *= smoothstep(-0.02, 0.08, worldDir.y);

	if (night <= 0.0) {
		return vec3(0.0);
	}

	vec3 p = worldDir * STAR_CELLS;
	vec3 cell = floor(p);
	vec3 f = fract(p);

	vec3 total = vec3(0.0);

	// A star may sit anywhere in its cell and its radius reaches past the cell
	// wall, so the neighbours have to be visited as well as the cell the
	// fragment is in.
	for (int x = -1; x <= 1; x++) {
		for (int y = -1; y <= 1; y++) {
			for (int z = -1; z <= 1; z++) {
				vec3 offset = vec3(float(x), float(y), float(z));
				vec3 c = cell + offset;

				// Whether this cell holds a star at all. This is what makes the
				// loop cheap: the other 95% of the sky stops here.
				vec3 h = StarHash(c);
				if (h.x >= STAR_DENSITY) {
					continue;
				}

				// Where in the cell, measured from this fragment's cell so that
				// the neighbours can be compared against f directly.
				vec3 centre = offset + StarHash(c + 31.7);

				float d = length(f - centre);
				if (d >= STAR_RADIUS) {
					continue;
				}

				// Brightness: a uniform value cubed, so that most of the field
				// is faint and a few stars carry it.
				float magnitude = h.y * h.y * h.y;

				// Warm through to cool, so that the field is not one colour.
				vec3 tint = mix(
					vec3(1.0, 0.84, 0.68),
					vec3(0.76, 0.85, 1.0),
					h.z);

				// A tight core: the falloff is squared twice, which keeps the
				// bright part of the star down around a tenth of its radius and
				// leaves the rest as a faint halo. Squared only once - the
				// obvious way to write this - the whole disc stays bright and
				// the field reads as a haze of soft blobs rather than as stars.
				float core = 1.0 - d / STAR_RADIUS;
				core *= core;
				total += tint * (magnitude * core * core);
			}
		}
	}

	return total * (night * STAR_BRIGHTNESS);
#endif
}

#endif // SKY_STARS_GLSL_INCLUDED
