// Firmament: the sun and the moon, as lights in the sky.
//
// Copyright (C) 2026 Remiiil1a. Part of Firmament, an edit of coderbot's
// Steadfast; see NOTICE.md for the licence this is distributed under.

// The generated sky - SkyColor() - is atmosphere only. It has no disc of either
// body in it, because in the sky above the discs are sprites the game draws, and
// they reach the screen through the program that draws textured things in the
// sky rather than through this.
//
// That is fine for the sky itself. It is not fine for a reflection of the sky,
// which is asked for through SkyColor() alone: water reflecting the sky was
// reflecting the air and nothing standing in it, so there was no sun on the
// water and no path of moonlight across it, however clear the night.
//
// So the two bodies are added here, and they are the game's own images of them:
// sun.png and the eight moon phases, copied into this pack's img folder and
// bound with customTexture in shaders.properties. See the note on the two
// samplers below for why they had to be copied rather than read from the game.
//
// They are deliberately not drawn into the sky itself - what is up there is
// still the game's own sun and moon, drawn by the game's own program, and a
// second pair drawn by the pack would sit next to them.

#ifndef SKY_BODIES_GLSL_INCLUDED
#define SKY_BODIES_GLSL_INCLUDED

// Declared here, once, for sky.glsl's whole chain: this file and stars.glsl are
// both included from it and both read rainStrength, and sunPosition is read by
// the reflections through the function below.
//
// Behind the guard because the Voxy patch declares all of these for us - see the
// note in program/world/lit_voxy.fsh. Its own declarations come from the
// "uniforms" and "samplers" arrays in voxy.json, and a name those arrays carry
// must not be declared again here, or the patch fails to compile with a
// redeclaration and Voxy falls back to drawing its terrain with no shader at
// all.
//
// sunPosition stays listed for the guard's sake rather than for the patch: the
// patch's branch of the reflection deliberately uses worldSunVector instead, so
// it never reads this one - but the declaration is a pair with rainStrength's,
// and this file is the only place either is declared.
#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform float rainStrength;
	uniform vec3 sunPosition;

	// Which of the moon's eight phases it is showing, which the game takes from
	// the day count: see the function below.
	uniform int worldDay;

	uniform sampler2D sunTex;
	uniform sampler2D moonPhasesTex;
#endif

// Whether the reflections see the sun and the moon.
#define WATER_SKY_BODIES_ON 1
#define WATER_SKY_BODIES_OFF 0
#define WATER_SKY_BODIES WATER_SKY_BODIES_ON // [WATER_SKY_BODIES_OFF WATER_SKY_BODIES_ON]

// The cosine of the half-angle the game draws a body's quad at.
//
// The game draws the sun and the moon as quads sixty wide at a distance of a
// hundred, which puts the edge of one at atan(30/100) from its centre: sixteen
// and a half degrees, a cosine of 0.96.
//
// The two images cover that whole quad, and the body inside them covers a little
// over a quarter of it - 64 of the 1024 pixels of sun.png are lit, so the sun
// the sky shows is about nine degrees wide. Setting this to the quad's edge is
// therefore what makes the sun in the water the same size as the sun in the sky.
//
// This is the coarse control. The two below it trim each body on their own, and
// whether the quad really is sixty at a hundred is not something this pack can
// check, so the last of it is settled by eye.
//
// This used to be 0.995, the edge of a disc drawn by this file with a wide glow
// painted around it, because there was no image to sample. Both of those are
// gone with the reason for them; PBR_PORTING.md 179 and 180 have the history.
#define WATER_BODY_SIZE 0.96 // [0.9995 0.998 0.995 0.99 0.985 0.975 0.96 0.94 0.92 0.90 0.85 0.80]

// How much larger or smaller than the sky's own quad each body is drawn in the
// water, one control each.
//
// Separate because the two are not the same picture up there: the sun nearly
// fills its own square, and the moon is a disc painted inside one, so the two do
// not need the same factor to come out the same size on the water - and the
// values below, which were arrived at by eye against the sky, differ by about a
// third.
//
// The steps are half a percent, which is what a size has to be matched to, and
// the range is wide enough to hold both of the tuned values with room either
// side of them.
#define WATER_SUN_SIZE 1.075 // [0.700 0.705 0.710 0.715 0.720 0.725 0.730 0.735 0.740 0.745 0.750 0.755 0.760 0.765 0.770 0.775 0.780 0.785 0.790 0.795 0.800 0.805 0.810 0.815 0.820 0.825 0.830 0.835 0.840 0.845 0.850 0.855 0.860 0.865 0.870 0.875 0.880 0.885 0.890 0.895 0.900 0.905 0.910 0.915 0.920 0.925 0.930 0.935 0.940 0.945 0.950 0.955 0.960 0.965 0.970 0.975 0.980 0.985 0.990 0.995 1.000 1.005 1.010 1.015 1.020 1.025 1.030 1.035 1.040 1.045 1.050 1.055 1.060 1.065 1.070 1.075 1.080 1.085 1.090 1.095 1.100 1.105 1.110 1.115 1.120 1.125 1.130 1.135 1.140 1.145 1.150 1.155 1.160 1.165 1.170 1.175 1.180 1.185 1.190 1.195 1.200]
#define WATER_MOON_SIZE 0.740 // [0.700 0.705 0.710 0.715 0.720 0.725 0.730 0.735 0.740 0.745 0.750 0.755 0.760 0.765 0.770 0.775 0.780 0.785 0.790 0.795 0.800 0.805 0.810 0.815 0.820 0.825 0.830 0.835 0.840 0.845 0.850 0.855 0.860 0.865 0.870 0.875 0.880 0.885 0.890 0.895 0.900 0.905 0.910 0.915 0.920 0.925 0.930 0.935 0.940 0.945 0.950 0.955 0.960 0.965 0.970 0.975 0.980 0.985 0.990 0.995 1.000 1.005 1.010 1.015 1.020 1.025 1.030 1.035 1.040 1.045 1.050 1.055 1.060 1.065 1.070 1.075 1.080 1.085 1.090 1.095 1.100 1.105 1.110 1.115 1.120 1.125 1.130 1.135 1.140 1.145 1.150 1.155 1.160 1.165 1.170 1.175 1.180 1.185 1.190 1.195 1.200]

// How far the axis the two bodies turn about is tilted, in degrees, away from
// straight up and towards the north.
//
// The two do not turn about the world's up, and they do not turn about the
// horizon either: they rise in the east and set in the west, so the axis is
// somewhere in the north-south and up plane, and which way it leans is what puts
// their arc through the southern sky and what makes the sun's square appear
// tilted as it climbs.
//
// The value is the one that came out of matching the sky by eye, after the
// spurious flip described in SkyBodyAxes was taken out, and it lands on the same
// number the pack's own constant implies: everywhere this pack asks how high the
// sun is it normalises worldSunVector.y by 0.75 rather than 1.0, with a comment
// reading "worldSunVector.y never actually gets to 1.0", and a sun that tops out
// at 0.75 has its orbit acos(0.75) = 48.4 degrees off the vertical.
//
// The option names a direction rather than an axis of rotation, and that only
// matters past a right angle: a direction and its opposite name the same line
// but give opposite pictures, so 131.6 and -48.4 are the same orbit as each
// other and the mirror image of this one. 48.4 is the one that puts the arc
// through the southern sky.
#define WATER_BODY_TILT 48.4 // [-180 -175 -170 -165 -160 -155 -150 -145 -140 -135 -130 -125 -120 -115 -110 -105 -100 -95 -90 -85 -80 -75 -70 -65 -60 -55 -50 -45 -40 -35 -30 -25 -20 -15 -10 -5 0 5 10 15 20 25 30 35 40 45 48.4 50 55 60 65 70 75 80 85 90 95 100 105 110 115 120 125 130 131.6 135 140 145 150 155 160 165 170 175 180]

// How bright a body is in a reflection. A reflection is not a surface being lit,
// so this is not the scene's exposure: it is the body's own light, and it is
// meant to be the brightest thing on the water.
#define WATER_BODY_BRIGHTNESS 32.0 // [1.0 2.0 4.0 8.0 16.0 32.0 64.0]

// What the moon is worth against the sun. It is the same sun's light, bounced
// off a rock, and the game draws it far dimmer up in the sky - so it is far
// dimmer here too, which is what keeps it a moon rather than a second sun.
#define MOON_TO_SUN 0.02

// The two axes one body's quad is drawn in, in whichever space the directions
// handed to SkyBodies are in.
//
// Both axes are perpendicular to the body's own direction, and they are
// perpendicular to each other. That is not a detail: the quad is a picture on a
// plane, and the only way to read a picture off a plane without distorting it is
// to measure along two perpendicular axes that lie in it. An earlier version of
// this mirrored one of the two as a direction in space, which took it out of the
// plane, and the result was not a rotated sun but a stretched one - a
// parallelogram, because the two measuring directions no longer met at a right
// angle.
//
// Nothing else happens here, and in particular the picture is not turned over.
// That is worth writing down because turning it over is the obvious thing to do
// and it is wrong. A reflection is not a picture of the sky with a flip applied
// to it; it is the sky read along a mirrored direction, and the mirroring is
// already complete in that direction - a direction shows a body the same way
// round whichever pixel it was reached from. Applying a flip as well flips it
// twice, and the water then shows the moon upside down against the sky, which is
// what was reported and what no amount of turning the axis could repair, because
// the axis and the flip are different axes.
void SkyBodyAxes(vec3 bodyDir, vec3 skyUp, vec3 celestialAxis, out vec3 right, out vec3 up) {
	// The axis the bodies turn about, taken perpendicular to the body. It
	// already is, for any sky where they rise in the east: that is what makes
	// the arc an arc. The subtraction is here for the dimension that has no such
	// sky, where it costs one instruction and saves a NaN.
	vec3 axis = celestialAxis;
	if (abs(dot(axis, bodyDir)) > 0.999) {
		axis = skyUp;
	}

	right = normalize(axis - bodyDir * dot(axis, bodyDir));
	up = cross(right, bodyDir);
}

// Where along that quad a direction looks, in the quad's own coordinates: the
// centre of the texture is the origin and its edge is one, so a component
// outside -1..1 means the direction misses the quad altogether.
//
// The division is by the cosine of the angle off the body's centre as well as by
// the half-size, because the quad is a flat thing at a distance and not a patch
// of a sphere: the game projects onto the plane, so the offset across it grows
// with the tangent of the angle, not with its sine.
vec2 SkyBodyQuad(vec3 viewDir, vec3 bodyDir, vec3 right, vec3 up, float halfSize) {
	float mu = dot(viewDir, bodyDir);
	vec3 rel = viewDir - bodyDir * mu;

	return vec2(dot(rel, right), dot(rel, up)) / (max(mu, 1.0e-4) * halfSize);
}

// The light the sun and the moon add in the given direction.
//
// viewDir and bodyDir are in view space in the normal program, and both in world
// space in the Voxy patch's - see the call site. worldToSpace is the rotation
// that takes a world direction into that same space, so that the two spaces stay
// one decision made in one place rather than two that have to agree.
//
// Why view space in the normal program: the game draws the sun and the moon into
// the sky from the position it holds for them, and that position is a view space
// one - so a body placed from a world space direction is a body that sits
// somewhere the real one is not, and the two drift apart as the camera's view bob
// changes. That mismatch is what a reflection of the sun swinging about the water
// as you walk is.
//
// The two fades below still read the world space direction, because how high a
// body is does not depend on which frame it is measured in, up to the bob, and
// they only drive a slow fade either side of the horizon.
vec3 SkyBodies(vec3 viewDir, vec3 bodyDir, mat3 worldToSpace) {
#if WATER_SKY_BODIES == WATER_SKY_BODIES_OFF
	return vec3(0.0);
#else
	// The two bodies are exactly opposite each other, so one dot product gives
	// both and the one below the horizon is simply never looked at.
	float muSun = dot(viewDir, bodyDir);

	vec3 skyUp = worldToSpace * vec3(0.0, 1.0, 0.0);

	// North, which in this game's coordinates is minus Z - Z is south. Getting
	// that sign the other way round leans the axis the wrong way, which is a
	// quarter of a turn of the reflected body, so it is worth naming rather than
	// writing.
	vec3 skyNorth = worldToSpace * vec3(0.0, 0.0, -1.0);

	// The axis the bodies turn about: up, leaned towards the north by the option
	// and normalised back to a direction.
	//
	// The cast is not decoration. radians() has no integer overload, and an
	// option whose value is written as a whole number arrives as an int - at
	// which point the call is ambiguous between the float, mediump and lowp
	// overloads and nothing compiles at all.
	float tilt = radians(float(WATER_BODY_TILT));
	vec3 celestialAxis = normalize(skyUp * cos(tilt) + skyNorth * sin(tilt));

	// The half-angle of the quad, as a tangent, from the cosine the option
	// holds: the side of a right triangle whose hypotenuse is one.
	float halfSize = sqrt(max(0.0, 1.0 - WATER_BODY_SIZE * WATER_BODY_SIZE));

	// The frames the two quads are drawn in.
	//
	// These must not be called sunUp and moonUp: those are the two floats the
	// horizon fades at the end of this function are held in, and GLSL has no
	// inner scope to hide one in. Naming them so is a redeclaration, and the
	// compiler says "declaration conflicts with previous declaration" twelve
	// lines later rather than at either of them.
	vec3 sunAxisRight, sunAxisUp;
	vec3 moonAxisRight, moonAxisUp;
	SkyBodyAxes(bodyDir, skyUp, celestialAxis, sunAxisRight, sunAxisUp);
	SkyBodyAxes(-bodyDir, skyUp, celestialAxis, moonAxisRight, moonAxisUp);

	// In front of the camera, or nothing at all.
	//
	// The two bodies are exactly opposite each other, so a direction that points
	// at one of them has a negative dot product with the other. The quad of the
	// one behind is behind the camera as well, and the offset across it is
	// measured from a point on the far side of the camera, where it collapses
	// towards nothing - which the test further down reads as the *centre* of
	// that quad. That is how the sun comes to be drawn inside the moon when the
	// moon is rising and the sun is setting: the two are opposite, the direction
	// being looked at is the anti-solar one, and the sun's offset there is zero.
	float sunFront = float(muSun > 0.0);
	float moonFront = float(-muSun > 0.0);

	vec2 quadSun = SkyBodyQuad(viewDir, bodyDir, sunAxisRight, sunAxisUp, halfSize * WATER_SUN_SIZE);
	vec2 quadMoon = SkyBodyQuad(viewDir, -bodyDir, moonAxisRight, moonAxisUp, halfSize * WATER_MOON_SIZE);

	// A direction that misses the quad contributes nothing. The images are
	// black everywhere the body is not - every one of them is opaque, edge to
	// edge, and the shape of the body is painted in rather than cut out - so
	// they are added the way the game adds them to the sky, and what falls
	// outside the quad reads as the black edge rather than as a coloured
	// rectangle. That is why this masks the sample and does not test first.
	float sunOn = sunFront * float(all(lessThan(abs(quadSun), vec2(1.0))));
	float moonOn = moonFront * float(all(lessThan(abs(quadMoon), vec2(1.0))));

	// Mip level zero, explicitly. The images are mostly black with a small body
	// in the middle, so any averaging of one is an average of that body spread
	// over the whole quad, and the quad is more than three times the width of
	// the body: the result is a faint rectangle the shape of the quad with a
	// small bright spot at its centre, which is a thing that was seen on the
	// water. The .mcmeta files beside the images ask for no mipmaps as well, and
	// this does not depend on whether they are honoured.
	vec3 sunColor = textureLod(sunTex, quadSun * 0.5 + 0.5, 0.0).rgb * sunOn;

	// The moon's phase, the same way the game takes it: the day count modulo
	// eight, counting from a full moon on day zero.
	int moonPhase = worldDay % 8;

	// The eight phases are one image laid out in a row, because this version of
	// the game keeps them as eight separate files rather than as one sheet.
	vec2 moonPixel = vec2(
		(float(moonPhase) + quadMoon.x * 0.5 + 0.5) / 8.0,
		quadMoon.y * 0.5 + 0.5);

	vec3 moonColor = textureLod(moonPhasesTex, moonPixel, 0.0).rgb * moonOn * MOON_TO_SUN;

	// Each body fades as it sets and rises rather than switching at the horizon,
	// and rain covers both - the same rain that greys the sky and hides the
	// stars, so that the water and the sky above it agree about the weather.
	float sunUp = smoothstep(-0.12, 0.02, worldSunVector.y);
	float moonUp = smoothstep(-0.12, 0.02, -worldSunVector.y);
	float clear = 1.0 - rainStrength;

	return (sunColor * sunUp + moonColor * moonUp) * (WATER_BODY_BRIGHTNESS * clear);
#endif
}

#endif // SKY_BODIES_GLSL_INCLUDED
