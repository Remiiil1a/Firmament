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

// Added 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

// The End's sky.
//
// Steadfast's atmosphere model is built for a world that has a sun and an
// atmosphere to scatter its light through. The End has neither: it is a void
// with a few islands in it, and it is lit by nothing at all. Running the
// Overworld model there produces an Overworld sky - a horizon, a day and night
// cycle, sunsets - on a dimension that has none of those things, and leaves the
// one thing the End should have, an open sky full of stars, missing.
//
// This replaces that sky with what the dimension actually looks like.
//
// The End has no sky light of its own, so its terrain is lit by the pack's
// direct light at the small fraction that dimension leaves it with, plus the
// ambient floor; see MIN_AMBIENT_BRIGHTNESS in
// /environment/lighting/diffuse.glsl if the islands are too dark.

// Which dimension this sky belongs to, and how that is decided.
// Uniforms: dimension, biome_category
#include "/environment/dimension.glsl"

// How crowded the starfield is. Each step doubles roughly how many stars are
// drawn, and 0.0 leaves an empty sky.
#define END_STAR_DENSITY 2.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]

// How bright the stars are. Apart from the body below, they are the only thing
// in the End brighter than the surface of a lit block, so raising this makes
// the sky dominate more.
#define END_STAR_BRIGHTNESS 3.0 // [0.0 0.5 0.75 1.0 1.5 2.0 3.0]

// What, if anything, sits at the point in the End's sky that the dimension is
// lit from.
//
// The End has no sky light, so the one thing lighting its islands is the pack's
// direct light, and in the End that light comes from a single fixed direction
// (see the note on skyLight in /environment/lighting/diffuse.glsl). It is
// therefore the one place in the sky where something belongs, and whichever of
// these is chosen is drawn exactly where that light comes from.
#define END_BODY_OFF 0
#define END_BODY_STAR 1
#define END_BODY_BLACK_HOLE 2
#define END_BODY END_BODY_STAR // [END_BODY_OFF END_BODY_STAR END_BODY_BLACK_HOLE]

// The time uniform, which animates the body above.
//
// Declared behind a guard because more than one file in this pack asks for it
// and a repeated uniform declaration is an error: whichever of them is included
// first declares it and the rest are skipped. Programs whose uniforms come from
// elsewhere - Voxy's terrain - get it from there instead.
#if !defined(EXTERNALLY_DEFINED_UNIFORMS) && !defined(FRAME_TIME_COUNTER_DECLARED)
	#define FRAME_TIME_COUNTER_DECLARED
	uniform float frameTimeCounter;
#endif

// Two vectors at right angles to the given axis, so that a direction can be
// turned into a coordinate on the sky around it.
//
// The reference vector is swapped when the axis is close to vertical, because a
// cross product with a parallel vector is zero - and this axis is the sun,
// which in the End sits close to straight up.
void EndBodyBasis(vec3 axis, out vec3 u, out vec3 v) {
	vec3 reference = abs(axis.y) > 0.99
		? vec3(1.0, 0.0, 0.0)
		: vec3(0.0, 1.0, 0.0);

	u = normalize(cross(reference, axis));
	v = cross(axis, u);
}

// The angle between a direction on the sky and the axis of a body, in radians.
//
// Both are assumed normalized, and the angle is taken as the arc tangent of the
// sine and cosine rather than as the arc cosine of the dot product. The two are
// the same number, but the arc cosine is flat at both ends: near the axis,
// where a body is, it takes a dot product that is a hair above one and returns
// an angle of zero, so a tiny error in the direction becomes a large error in
// the angle - and the angle is the only thing the size of the body is made of.
float EndBodyAngle(vec3 worldDir, vec3 axis) {
	return atan(length(cross(worldDir, axis)), dot(worldDir, axis));
}

#include "/lib/valueNoise.glsl"

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
// position inside that cell, and only some of the cells hold one at all. A grid
// is used rather than anything cleverer because it needs no state and no
// texture: the whole starfield is a hash of which cell the view direction
// happens to be in.
vec3 EndStarfield(vec3 worldDir) {
	// Cells across the sky. Larger means more, smaller stars: this is what sets
	// how large a single star ends up on screen.
	const float CELLS = 60.0;

	vec3 scaled = worldDir * CELLS;
	vec3 cell = floor(scaled);
	vec3 local = fract(scaled);

	// Whether this cell holds a star, and if so, where in the cell it sits.
	float roll = EndSkyHash(cell + 31.7);

	if (roll > 0.04 * END_STAR_DENSITY) {
		return vec3(0.0);
	}

	vec3 starPos = EndSkyHash3(cell);
	float distance = length(local - starPos);

	// Bright stars are also slightly larger. Varying both together is what
	// makes a starfield read as having depth instead of looking like noise.
	float magnitude = 0.35 + 0.65 * EndSkyHash(cell + 11.3);
	float radius = 0.06 + 0.05 * magnitude;

	float star = 1.0 - smoothstep(0.0, radius, distance);
	star *= star;

	// Stars are not all white: some are hot and blue, some cool and orange.
	vec3 tint = mix(
		vec3(0.72, 0.82, 1.0),
		vec3(1.0, 0.86, 0.72),
		EndSkyHash(cell + 5.1));

	// 1.6 puts the brightest stars above white, which is what makes them read
	// as points of light rather than as white dots.
	return tint * (star * magnitude * 1.6 * END_STAR_BRIGHTNESS);
}

#if END_BODY == END_BODY_STAR
	// The star the End is lit by.
	//
	// It is drawn as a disc with a boiling surface and a corona rather than as a
	// flat circle, because a flat circle reads as a hole punched in the sky. The
	// brightnesses are far above one on purpose: this is the brightest thing in
	// the dimension and everything else here is near black, so the pack's
	// tonemapper needs something to actually compress.
	vec3 EndSkyStar(vec3 worldDir, vec3 axis) {
		// Angular radius of the disc, in radians. A real star is a small
		// fraction of this - the sun as seen from Earth is 0.0045 - and at this
		// pack's field of view that would be under a pixel, so this is
		// deliberately many times too large.
		const float DISC = 0.050;

		// How far the faint outer corona reaches, how far the bright part of it
		// reaches, and how bright the two are together.
		const float CORONA = 0.45;
		const float INNER_GLOW = 0.10;
		const float CORONA_BRIGHTNESS = 0.30;

		float angle = EndBodyAngle(worldDir, axis);
		float across = angle / DISC;

		vec3 u, v;
		EndBodyBasis(axis, u, v);
		vec2 onFace = vec2(dot(worldDir, u), dot(worldDir, v));

		// The disc, with an edge that is softened across the corona rather than
		// stopping short of it.
		//
		// This is the whole of why there is no dark ring around the star. The
		// photosphere is brighter than the corona by a factor of ten, so if its
		// edge reaches zero before the corona has picked up, the gap between the
		// two is a band of nearly black sky between a bright disc and a dim
		// halo - which reads as a black outline. The two are added rather than
		// chosen between, and the edge is wide enough that they overlap.
		float disc = 1.0 - smoothstep(0.94, 1.10, across);

		// Two octaves of the pack's value noise drifting across the face at
		// different speeds, so the surface boils instead of sitting still.
		// Texture-sampled noise, so the octave costs one lookup.
		//
		// The scale is in noise cells, and the disc is only about a tenth of a
		// radian across, so this has to be large to get more than one cell of it
		// onto the face at all.
		//
		// Only computed on the disc, which is a small part of the sky: the rest
		// of it is asking for the corona, which does not need this.
		float boiling = 0.0;

		if (disc > 0.0) {
			vec2 surface = onFace * 90.0;
			boiling = smoothNoise2D(vec3(0.6, 0.3, 0.1),
				surface + vec2(frameTimeCounter * 0.05, 0.0));
			boiling += 0.5 * smoothNoise2D(vec3(0.5, 0.5, 0.0),
				surface * 2.3 - vec2(0.0, frameTimeCounter * 0.08));
			boiling /= 1.5;
		}

		// Limb darkening, in the Eddington form: the edge of a star is cooler
		// and dimmer than its middle because a line of sight there leaves at a
		// shallower angle and exits through cooler gas. 0.6 is about what the
		// sun does in visible light, and this is most of what makes the disc
		// read as a sphere rather than as a sticker.
		float mu = sqrt(max(0.0, 1.0 - min(across * across, 1.0)));
		float limb = 1.0 - 0.6 * (1.0 - mu);

		vec3 color = mix(vec3(1.0, 0.84, 0.58), vec3(1.0, 0.97, 0.93), mu);
		vec3 star = color * (disc * limb * (3.0 + 1.8 * boiling));

		// The corona: a bright part that meets the disc's edge and a faint part
		// that carries much further out. Faint streamers keep it from being a
		// perfect circle.
		float streamers = 0.70 + 0.30 * smoothNoise2D(vec3(1.0, 0.5, 0.0),
			onFace * 26.0 + vec2(frameTimeCounter * 0.02, 0.0));

		float reach = max(angle - DISC, 0.0);
		float corona = exp(-reach / CORONA) + 0.55 * exp(-reach / INNER_GLOW);

		return star + vec3(1.0, 0.76, 0.42)
			* (corona * CORONA_BRIGHTNESS * streamers);
	}
#endif /* END_BODY_STAR */

#if END_BODY == END_BODY_BLACK_HOLE
	// Angular radius of the shadow, and the inner and outer edges of the disc
	// around it, all in radians.
	#define END_BLACK_HOLE_SHADOW 0.032
	#define END_BLACK_HOLE_INNER 0.040
	#define END_BLACK_HOLE_OUTER 0.135

	// How flat the disc is seen, as a fraction of its width. At 1.0 it would be
	// seen face on, as a ring.
	#define END_BLACK_HOLE_TILT 0.30

	// Where the sky is bent around the hole.
	//
	// Light from directly behind it is pulled the furthest, which is what makes
	// the sky look like it is being poured around something rather than like
	// something has been pasted over it. The bend is capped because it grows
	// without limit as the axis is approached, and an unbounded remapping of the
	// view direction tears.
	vec3 EndBlackHoleLens(vec3 worldDir, vec3 axis) {
		vec3 outward = worldDir - axis * dot(worldDir, axis);
		float outwardLength = length(outward);

		if (outwardLength < 0.0001) {
			return worldDir;
		}

		float angle = EndBodyAngle(worldDir, axis);
		float bend = min(0.0016 / max(angle, 0.008), 0.06);

		return normalize(worldDir + (outward / outwardLength) * bend);
	}

	// How much of what is behind this direction the hole hides, from one at its
	// centre to zero past its edge.
	//
	// This is a plain circle rather than the squashed one the disc uses: what
	// casts the shadow is the hole itself, which is a sphere, and only the disc
	// around it is seen at an angle.
	float EndBlackHoleShadow(vec3 worldDir, vec3 axis) {
		float angle = EndBodyAngle(worldDir, axis);

		return 1.0 - smoothstep(END_BLACK_HOLE_SHADOW * 0.92,
			END_BLACK_HOLE_SHADOW, angle);
	}

	// The hole itself: a thin ring of light bent around its edge, and the disc
	// of matter falling into it. The shadow is applied by the caller, which is
	// where the sky it hides is.
	vec3 EndSkyBlackHole(vec3 worldDir, vec3 axis) {
		float angle = EndBodyAngle(worldDir, axis);

		vec3 u, v;
		EndBodyBasis(axis, u, v);
		vec2 onFace = vec2(dot(worldDir, u), dot(worldDir, v));

		// The disc is seen at an angle, so one axis of the tangent plane is
		// squashed. This is the whole of what makes it read as a flat disc
		// rather than as a ring.
		vec2 q = vec2(onFace.x, onFace.y / END_BLACK_HOLE_TILT);
		float radius = length(q);
		float azimuth = atan(q.y, q.x);

		// The disc turns at the speed an orbit does, angular speed falling as the
		// three-halves power of the distance, so the inner edge laps the outer
		// one and the pattern shears. That shear, rather than the noise itself,
		// is what makes the disc read as something turning.
		//
		// The number is what sets how fast that is, and the disc is small: the
		// inner edge comes round in about eight seconds and the outer one in
		// about a minute.
		const float SPIN = 0.006;

		float orbit = azimuth + frameTimeCounter
			* SPIN / pow(max(radius, 0.02), 1.5);

		vec2 diskUV = vec2(cos(orbit), sin(orbit)) * (radius * 90.0);
		float streaks = smoothNoise2D(vec3(1.0, 0.4, 0.0), diskUV);
		streaks += 0.5 * smoothNoise2D(vec3(0.4, 0.4, 0.2), diskUV * 2.7 + 0.31);
		streaks /= 1.5;

		// Nothing inside the inner edge: that is where the shadow is.
		float disk = smoothstep(END_BLACK_HOLE_INNER,
			END_BLACK_HOLE_INNER * 1.30, radius);
		disk *= 1.0 - smoothstep(END_BLACK_HOLE_OUTER * 0.45,
			END_BLACK_HOLE_OUTER, radius);

		// One side is coming towards the viewer and is beamed brighter, the
		// other is going away. Without this the disc is symmetric, which is the
		// one thing it should not be.
		float beaming = 0.30 + 1.30 * (0.5 + 0.5 * cos(azimuth));

		// Hotter and therefore bluer towards the middle, cooler and redder
		// further out.
		float innermost = 1.0 - smoothstep(END_BLACK_HOLE_INNER,
			END_BLACK_HOLE_OUTER * 0.55, radius);

		vec3 diskColor = mix(
			vec3(1.0, 0.62, 0.30),
			vec3(0.80, 0.88, 1.0),
			innermost);

		vec3 color = diskColor
			* (disk * beaming * (0.7 + 0.6 * streaks) * 2.2);

		// The photon ring: light that went around the hole one or more times
		// before escaping, which is what outlines the shadow.
		float ring = exp(-pow((angle - END_BLACK_HOLE_SHADOW * 1.05) / 0.0045,
			2.0));
		color += vec3(0.95, 0.80, 0.60) * (ring * 1.4);

		return color;
	}
#endif /* END_BODY_BLACK_HOLE */

// The color of the End's sky in the given direction, in linear RGB.
vec3 EndSkyColor(vec3 worldDir) {
	// The direction is normalized here rather than taken as given, because
	// every size the body below is drawn at is an angle measured from it.
	//
	// The sky's direction is built out of the camera's matrices, and a direction
	// that is not quite of unit length is not quite a direction: the dot product
	// with the axis comes out a fraction of a percent wrong, and near the axis -
	// which is where the body is - that is a fraction of a percent of the radius
	// of everything drawn there. That is invisible on a smooth sky gradient and
	// plainly visible as a disc pulsing in size, which is exactly what it does
	// while the view is bobbing, because that is when the camera's matrices
	// change a little every frame.
	vec3 dir = normalize(worldDir);

	// Not quite black. A perfectly black sky reads as a hole rather than as
	// distance, and the End's own sky has a faint violet cast to it.
	vec3 sky = vec3(0.0035, 0.0030, 0.0060);

	#if END_BODY == END_BODY_OFF
		sky += EndStarfield(dir);
	#else
		// Where the End is lit from, which in this dimension is a fixed
		// direction: the End has no day or night of its own, so the sun sits
		// where noon puts it and stays there, tilted by the pack's sun path
		// rotation. This is the same vector the dimension's direct light comes
		// from, which is what puts the body above the light it casts.
		//
		// Normalized for the same reason as the direction above.
		vec3 bodyAxis = normalize(worldSunVector);

		#if END_BODY == END_BODY_BLACK_HOLE
			// The sky is sampled through the bend the hole puts in it, so what
			// is behind the hole is seen around it rather than through it.
			sky += EndStarfield(EndBlackHoleLens(dir, bodyAxis));

			// And then the whole of it, the empty sky included, is hidden where
			// the hole is. Without this the bend would push stars out of the
			// shadow and there would be no shadow at all, only a ring of them.
			sky *= 1.0 - EndBlackHoleShadow(dir, bodyAxis);

			// The disc and the ring are in front of the hole rather than behind
			// it, so they are added after it has hidden everything else.
			sky += EndSkyBlackHole(dir, bodyAxis);
		#else
			sky += EndStarfield(dir);
			sky += EndSkyStar(dir, bodyAxis);
		#endif
	#endif

	return sky;
}
