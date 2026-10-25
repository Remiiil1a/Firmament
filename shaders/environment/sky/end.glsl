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
// What this draws instead is, in order of how far away it is:
//
// * a starfield hashed out of the view direction, with no texture and no
// state, which is what the empty sky needed and the Overworld model could
// not give it;
// * a nebula band, which is one noise fetch inside a band and nothing at all
// outside it;
// * the End's body, which is the pack's answer to "what is the dimension lit
// by", and which bends the two above as if it had gravity.
//
// Batch 338 removed the two older bodies - a single star and a black hole,
// chosen between by an END_BODY option - and the body is now always this one.
// See BATCH_LOG.md 194.
//
// The End has no sky light of its own, so its terrain is lit by the pack's
// direct light at the small fraction that dimension leaves it with, plus the
// ambient floor; see MIN_AMBIENT_BRIGHTNESS in
// /environment/lighting/diffuse.glsl, and END_AMBIENT in
// /environment/lighting/end_lighting.glsl for the dimension's own light.

// Which dimension this sky belongs to, and how that is decided.
// Uniforms: dimension, biome_category
#include "/environment/dimension.glsl"

// The End's palette: the body's colour, and the colour the End's volumetric fog
// is tinted with. Declared in its own file because the fog pass needs it too and
// does not include this one.
#include "/environment/sky/end_palette.glsl"

// The star field - its four options, the cell hashes and EndStarfield itself -
// lives in /environment/sky/end_palette.glsl as of batch 612.
//
// It moved for the same reason the palette did: a second program needs it and
// must not keep a copy. The portal effect (program/world/lit.fsh) is not a sky
// program and has none of the sky's uniforms, so it cannot include this file -
// but it can include the palette, and through it the very same stars. Two copies
// of a star field are two star fields the moment one of them is edited.

// The time uniform, which animates the sky.
//
// Declared behind a guard because more than one file in this pack asks for it
// and a repeated uniform declaration is an error: whichever of them is included
// first declares it and the rest are skipped. Programs whose uniforms come from
// elsewhere - Voxy's terrain - get it from there instead.
#if !defined(EXTERNALLY_DEFINED_UNIFORMS) && !defined(FRAME_TIME_COUNTER_DECLARED)
	#define FRAME_TIME_COUNTER_DECLARED
	uniform float frameTimeCounter;
#endif

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

// ---------------------------------------------------------------------------
// The End's body
// ---------------------------------------------------------------------------
//
// What sits at the point in the End's sky that the dimension is lit from, and
// bends the sky behind it.
//
// The End has no sky light, so the one thing lighting its islands is the pack's
// direct light, and in the End that light comes from a single direction (see
// the note on skyLight in /environment/lighting/diffuse.glsl). That is the one
// place in this sky where something belongs, so the body is drawn exactly where
// that light comes from - which is what keeps it agreeing with the light it
// casts.
//
// Whether that direction is genuinely fixed in the End is *believed, not
// verified*: worldSunVector is built from the mod's sunPosition, which advances
// with the world clock, so the body may well drift across the sky over a day.
// Nobody has watched a full day in the End. See BATCH_LOG.md 190.1.
//
// The body is built in several layers, and each has its own option so that the
// look can be worked on a layer at a time:
//
// the core         a small, very bright centre
// the halo         a wide, very faint glow around it
// the lens         the sky behind, bent, with an Einstein ring where the
// bending piles up
// the nebula band  what the lens has to bend
//
// Batch 334 added the first four as a star with a visible disc, batch 336
// replaced most of it with the lens and the band, and batch 338 removed the
// disc entirely at the user's request: the photosphere, the chromosphere and
// the surface detail are gone, so what is left is the small hot centre inside
// the ring. See BATCH_LOG.md 190, 192 and 194.

// Whether to draw the body and its lens at all.
//
// With it off the End is the plain turning sky - the starfield and the band,
// with nothing in front of them - which is a legitimate place to be rather than
// a broken state.
//
// The #define line below has to be here, on or off, and this is not
// decoration. Iris' manual is explicit about the two halves of a boolean
// option: it is *declared* by a #define line, and it is *recognised* by being
// checked at least once with #ifdef or #ifndef. Commenting the line out is what
// makes the default "off" - leaving the line out entirely makes no option at
// all, and the switch never appears in the menu.
//
// Batch 334 shipped exactly that mistake. It is the first thing
// _check_shader_sources.ps1 now checks for. See BATCH_LOG.md 191.
//
// To flip the default to "off", comment this one line out - and do not leave a
// second copy of it behind as a reminder, because the option has to be declared
// exactly once.
#define END_GIANT

// Overall size, as the angular radius of the body in radians. The real sun is
// 0.0046, so every step here is many times life size; the default is about
// fifteen degrees across.
//
// With no visible disc on the body any more, this is what scales everything
// else: the width of the core, the radius of the halo, and the Einstein radius
// that the ring sits at.
//
// Raising this raises the cost too: the rejection radius below is a multiple
// of it. See END_GIANT_REACH.
#define END_GIANT_SIZE 0.13 // [0.05 0.075 0.10 0.13 0.17 0.23]

// Everything the body emits, multiplied together at the end, so that this one
// knob scales the whole thing without disturbing the ratios between the layers.
#define END_GIANT_GLOW 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]

// The white-hot core, in linear light. It is deliberately far above white -
// this is the brightest thing in the dimension and the tonemapper needs
// something to compress - and deliberately *narrow*, because it is now the only
// part of the body that carries its own light. Batch 334's core was wide enough
// to blow out the whole disc and take its shading with it; see BATCH_LOG.md
// 192.
//
// The shipped default is 0.0 as of v0.7, which is the setting that turns this
// core off entirely: what is left is the Einstein ring and the glow, with the
// body's centre dark. That is a deliberate look rather than a broken default -
// it is what the user settled on, and it is the one setting here where a zero
// still leaves something to see. The retuned defaults are listed in
// CHANGELOG.md under v0.7.
#define END_GIANT_CORE 0.0 // [0.0 4.0 8.0 12.0 16.0 24.0 36.0]

// The wide halo around everything. Deliberately small: it should not be
// something you notice, it should be something you notice the absence of.
#define END_GIANT_HALO 0.10 // [0.0 0.03 0.06 0.10 0.16 0.25 0.4]

// The body's colour, from a warm white at 0.0 to the End's own violet at 1.0.
//
// Moved to environment/sky/end_palette.glsl in batch 340, because the End's
// volumetric fog has to agree with it and that is drawn in a different program.
// The option and the two ends of its range live there now, and there is one copy
// of each on purpose. See BATCH_LOG.md 197.

// Gravitational lensing: how hard the body bends the sky behind it.
//
// Added in batch 336 at the user's request, after
// https://github.com/rossning92/Blackhole, which he singled out for exactly
// this effect. That project integrates the bent ray over 300 steps per pixel -
// affordable for one black hole filling a demo window, not affordable here,
// where SkyColor() is asked for up to five times per reflective pixel. What is
// used instead is the closed form that stepping converges to in the weak field:
// the point-mass deflection alpha = theta_E^2 / theta, applied once as a
// rotation. About twenty ALU, no texture, no loop - and it produces the two
// things the eye actually reads as lensing, which are the sky dragged radially
// around the body and a bright ring where the mapping piles up.
//
// At 0.0 the sky is not bent and the option costs nothing.
#define END_GIANT_LENS 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0]

// The Einstein radius, as a multiple of the disc's radius: how far out the bent
// sky is dragged into a ring. This is the size of the effect rather than its
// strength.
#define END_GIANT_LENS_RING 2.2 // [1.2 1.6 2.0 2.2 2.8 3.6 4.5]

// How strong the nebula band across the End's sky is.
//
// This is not decoration. It is what makes the lensing visible at all. The
// sky this was first tried on was very nearly black with a few points in it,
// and bending a black sky with a few points in it gives back a black sky with a
// few moved points - the effect is spent and nothing is seen. The black hole
// demo that prompted all of this has a nebula skybox for exactly that reason,
// and the nebula wrapped into the ring is most of what is being looked at
// there. One noise fetch over the band, and nothing outside it.
#define END_GIANT_NEBULA 0.22 // [0.0 0.06 0.12 0.18 0.22 0.30 0.45]

// Whether the sky turns.
//
// Added in batch 337 at the user's request - "it would be even better if it
// could be made dynamic" - and made considerably faster and applied to the
// stars as well in batch 338, because the first version was too slow to see:
// the user's words were that even at the highest setting it was not obvious.
//
// One rotation, applied to the starfield and the nebula together, about the
// band's own axis. That axis is the useful one because the band does not move
// under it: only its contents stream along it. And because the ring is the sky
// behind the body, piled up, the ring's contents stream too - which is why the
// ring itself needs no animation of its own.
//
// The rotation is applied to the sky, not to the body: the body is radially
// symmetric and nothing would be visible if it turned.
//
// With this off, nothing anywhere carries a time term and the picture is
// exactly the still one.
//
// To flip the default to "off", comment this one line out, and do not leave a
// second copy of it behind.
#define END_GIANT_MOTION

// How fast the sky turns, as a multiplier.
//
// At 1.0 the whole sky comes round in about three minutes, which is a little
// under two degrees a second - visible as movement, and not a carousel. Batch
// 337 ran at a quarter of this and the user reported it as too weak even at its
// highest step, which is why both the rate and the top of the range moved.
//
// The shipped default is 0.25 as of v0.7 - the step that batch 337 was
// criticized for, now that the rate each step means has been raised. The retuned
// defaults are listed in CHANGELOG.md under v0.7.
#define END_GIANT_MOTION_SPEED 0.25 // [0.0 0.25 0.5 1.0 1.5 2.0 3.0 5.0]

// How far out anything is still drawn, in multiples of the disc's radius.
//
// This is also the rejection radius, so it is the cost of the whole feature:
// every pixel further out than this returns immediately without sampling
// anything.
//
// It has a hard upper bound that it and END_GIANT_SIZE must respect
// together. The tangent-plane coordinate the body is built on is the sine of
// the angle from the axis, and that starts shrinking again past 90 degrees; if
// SIZE times this ever reached a right angle the sky would be sampled a second
// time on the far side of the body. The largest pair offered (0.23 and 6.0)
// reaches 1.38 radians, inside 1.5708.
#define END_GIANT_REACH 6.0

// The band's axis, in world axes. Deliberately not the body's: a band running
// through the body would sit behind it and be hidden, and one at right angles
// would put the interesting sky where the body is not.
//
// It has to be a unit vector, and that is not cosmetic: the sky's drift is a
// Rodrigues rotation about this axis, and that formula is only a rotation when
// the axis is unit length. The value this started as was 0.99699 long, which is
// close enough to look right and wrong enough to shear the band as it turned.
const vec3 END_GIANT_NEBULA_AXIS = vec3(0.36108, 0.30090, 0.88265);

// The nebula band's two colours moved to /environment/sky/end_palette.glsl in
// batch 613, with the star field before them: the portal effect includes the
// palette unconditionally, and a colour that only exists when the sky happens to
// be compiled in is a colour that breaks the programs which do not include it.
// The whole sky turned by however far it has turned so far.
//
// Rodrigues' rotation about the band's axis. Applied to the starfield and to
// the nebula, which is the point: they are one sky, and turning them together
// is what stops the stars sliding across the clouds.
//
// Note that the direction the band's mask is taken from is unchanged by this -
// a rotation about the axis leaves dot(dir, axis) alone - so the band stays
// exactly where it is and only its contents move.
vec3 EndRotateSky(vec3 worldDir) {
	#ifdef END_GIANT_MOTION
		// About a full turn every three minutes at 1.0. The step is what the
		// user reaches for when the default is not enough; it goes to five.
		float angle = frameTimeCounter * END_GIANT_MOTION_SPEED * 0.035;
		float ca = cos(angle);
		float sa = sin(angle);

		return worldDir * ca
			+ cross(END_GIANT_NEBULA_AXIS, worldDir) * sa
			+ END_GIANT_NEBULA_AXIS
				* (dot(END_GIANT_NEBULA_AXIS, worldDir) * (1.0 - ca));
	#else
		return worldDir;
	#endif
}

// The nebula band across the End's sky.
//
// Its job is to be something for the lensing to wrap. One noise fetch, and only
// inside the band: the mask is evaluated first and the function returns before
// the fetch anywhere else.
//
// No time term of its own - the turning is EndRotateSky's, applied to the
// direction this is handed.
vec3 EndNebula(vec3 worldDir) {
	float latitude = dot(worldDir, END_GIANT_NEBULA_AXIS);
	float band = exp(-(latitude / 0.34) * (latitude / 0.34));

	if (band < 0.004) {
		return vec3(0.0);
	}

	// Two plane projections of the direction rather than an angle, because an
	// angle would put a seam where it wraps and this is a cloud, not a map.
	vec2 at = vec2(worldDir.x + worldDir.z * 0.6,
		worldDir.y * 0.8 + worldDir.z * 0.5);
	vec3 n = smoothNoise2Dx3(at * 3.2);

	// Three channels out of the one fetch: two to shape the cloud, one to
	// choose its colour.
	float cloud = smoothstep(0.34, 0.86, n.x * 0.7 + n.y * 0.3);
	vec3 color = mix(END_GIANT_NEBULA_VIOLET, END_GIANT_NEBULA_TEAL,
		smoothstep(0.30, 0.80, n.z));

	return color * (cloud * band * END_GIANT_NEBULA);
}

#ifdef END_GIANT
	// The body's two colours used to be declared here. They are in
	// environment/sky/end_palette.glsl as of batch 340, because the End's
	// volumetric fog has to agree with them and that is drawn in another
	// program entirely - one that has no reason to include this file. There is
	// one copy of each, deliberately; do not put them back.

	// Where the sky behind the body is really seen, once the body's gravity has
	// bent the light, and the two things that bending does to it.
	//
	// The lens equation for a point mass, read backwards. A source at true
	// angle beta appears at angle theta, with theta = beta + theta_E^2 / beta;
	// so the sky that appears at theta is the sky that is really at
	// beta = theta - theta_E^2 / theta.
	// Sampling the background at beta instead of theta is the whole of the
	// effect. It is one rotation, and it needs no stepping at all - which is
	// what makes it affordable in a pass that is asked for the sky up to five
	// times per pixel. See END_GIANT_LENS for what this stands in for.
	//
	// magnification is theta / beta, the tangential stretch. It is what turns a
	// displaced starfield into arcs, and it is why the sky piles up into a ring:
	// beta reaches zero at theta = theta_E and the ratio diverges there.
	//
	// ringGlow is that same divergence made finite, so that it can be drawn.
	vec3 EndLensBackground(vec3 worldDir, vec3 axis,
		out float magnification, out float ringGlow) {

		float theta = EndBodyAngle(worldDir, axis);
		float einstein = END_GIANT_SIZE * END_GIANT_LENS_RING * END_GIANT_LENS;

		magnification = 1.0;
		ringGlow = 0.0;

		if (einstein < 1.0e-5) {
			return worldDir;
		}

		// Clamped at theta itself so that beta cannot cross the axis. Beyond
		// that the light has been round the far side and comes back as a second
		// image, which one rotation cannot produce, and letting it through
		// would sample the sky from behind the player.
		float alpha = min(einstein * einstein / max(theta, 1.0e-4), theta);

		// The stretch, capped because it is unbounded exactly where the ring is.
		float beta = max(theta - alpha, 1.0e-5);
		magnification = clamp(theta / beta, 1.0, 6.0);

		// The ring itself, as a peak at the Einstein radius rather than as the
		// diverging ratio above: a Lorentzian has a height that can be chosen,
		// and the ratio does not. Written as a square rather than as pow(x, 2.0)
		// because the base is negative on the inside of the ring and pow with a
		// negative base is undefined - which is what BATCH_LOG.md 139 was.
		float ringOffset = (theta - einstein) / max(END_GIANT_SIZE * 0.07, 1.0e-4);
		ringGlow = 1.0 / (1.0 + ringOffset * ringOffset);

		vec3 outward = worldDir - axis * dot(worldDir, axis);
		float outwardLength = length(outward);
		if (outwardLength < 1.0e-5) {
			// Straight down the axis. There is no outward direction to bend
			// towards, and the sky there is the ring's own image.
			return worldDir;
		}
		outward /= outwardLength;

		// Rotated *towards* the axis, because a lens pushes the apparent
		// position of a source away from itself: the sky seen at theta is the
		// sky that is really closer in.
		return normalize(worldDir * cos(alpha) - outward * sin(alpha));
	}

	// The End's body, as seen from the given direction, in linear RGB.
	//
	// ringGlow comes from EndLensBackground, because the ring is the lens's own
	// light rather than the body's.
	//
	// Batch 338 removed the photosphere, the chromosphere and the surface
	// detail. What is left is the core, the ring and the halo - a small hot
	// centre inside a bright ring, which is the object the lens belongs to
	// rather than a star with a visible disc.
	vec3 EndGiantBody(vec3 worldDir, vec3 axis, float ringGlow) {
		float angle = EndBodyAngle(worldDir, axis);
		float across = angle / END_GIANT_SIZE;

		// The body's colour, from the one place it is defined - the same
		// function the volumetric fog pass tints the End's air with.
		vec3 tint = EndPaletteColor();

		vec3 light = vec3(0.0);

		// The Einstein ring first, and before the rejection test below: it sits
		// several disc radii out, and it is the one part of this that is meant
		// to be seen even when the core and the halo are both turned down.
		light += mix(tint, END_GIANT_VIOLET, 0.4)
			* (ringGlow * 0.55 * END_GIANT_LENS);

		if (across <= END_GIANT_REACH) {
			// Distance beyond the disc's edge, in the same units.
			float reach = max(across - 1.0, 0.0);

			// The core: narrow on purpose, and now the only part of the body
			// that carries its own light.
			float core = exp(-(across / 0.16) * (across / 0.16));
			vec3 coreColor = mix(vec3(1.0), END_GIANT_VIOLET,
				END_GIANT_TINT * 0.5);
			light += coreColor * (core * END_GIANT_CORE);

			// The wide halo. A very broad, very faint falloff whose whole job
			// is to make the sky around the body slightly less black.
			float halo = exp(-reach / 2.5);

			// Everything outside the disc is multiplied by this, and it is
			// not decoration: the rejection test above is a hard cutoff, and a
			// smooth glow that is still bright when it gets there draws a
			// visible circle around the body.
			float edge = 1.0 - smoothstep(END_GIANT_REACH * 0.5,
				END_GIANT_REACH, across);

			light += tint * (halo * END_GIANT_HALO * edge);
		}

		return light * END_GIANT_GLOW;
	}
#endif /* END_GIANT */

// The color of the End's sky in the given direction, in linear RGB, with the axis the
// giant is placed at handed in.
//
// The axis is the one quantity here that cannot be built from a direction: it comes from
// the mod's sunPosition, and turning that into a world direction exactly takes the full
// 4x4 inverse with w = 1 (see BATCH_LOG.md b502 and b504). The programs that draw the sky
// have the uniforms for that and this file does not, so it arrives as a parameter.
vec3 EndSkyColorWithAxis(vec3 worldDir, vec3 giantAxis) {
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

	#ifdef END_GIANT
		// Everything behind the body is sampled where the body's gravity has
		// put it rather than where it looks like it is, and it is brighter for
		// having been stretched getting there. This is the whole of the
		// lensing: one rotation, no stepping, and it costs nothing but ALU -
		// the starfield and the nebula were being sampled anyway, and this only
		// changes the direction they are sampled in.
		float lensMagnification = 1.0;
		float lensRing = 0.0;
		vec3 backgroundDir = EndLensBackground(dir, giantAxis,
			lensMagnification, lensRing);

		// Turned after the bend, because the turning belongs to the sky and the
		// bend belongs to the body: what the ray arrives from is the bent
		// direction, and the sky it arrives from is that direction turned.
		vec3 lensedSkyDir = EndRotateSky(backgroundDir);

		sky += EndStarfield(lensedSkyDir) * lensMagnification;
		sky += EndNebula(lensedSkyDir) * lensMagnification;
		sky += EndGiantBody(dir, giantAxis, lensRing);
	#else
		// No body: the plain sky, still turning.
		vec3 skyDir = EndRotateSky(dir);

		sky += EndStarfield(skyDir);
		sky += EndNebula(skyDir);
	#endif

	return sky;
}

// The same, with the axis taken from the pack's own worldSunVector. That form is correct
// to within the residual b504 took out of the sky - the translation column the mod's
// w = 1 sunPosition carries, left behind divided by 100 - so this is what a caller that
// does not have the uniforms for the exact form gets, and what the sky was drawn with
// before b504.
vec3 EndSkyColor(vec3 worldDir) {
	return EndSkyColorWithAxis(worldDir, normalize(worldSunVector));
}
