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
// These are the two discs, for the reflections to use. They are deliberately not
// drawn into the sky itself - what is up there is still the game's own sun and
// moon, and a second pair drawn by the pack would sit next to them.

#ifndef SKY_BODIES_GLSL_INCLUDED
#define SKY_BODIES_GLSL_INCLUDED

// Declared here, once, for sky.glsl's whole chain: this file and stars.glsl are
// both included from it and both read rainStrength, and sunPosition is read by
// the reflections through the function below.
uniform float rainStrength;
uniform vec3 sunPosition;

// Whether the reflections see the sun and the moon.
#define WATER_SKY_BODIES_ON 1
#define WATER_SKY_BODIES_OFF 0
#define WATER_SKY_BODIES WATER_SKY_BODIES_ON // [WATER_SKY_BODIES_OFF WATER_SKY_BODIES_ON]

// The cosine of a body's angular radius. The game draws the sun and the moon as
// quads sixty wide at a distance of a hundred, and the disc inside that texture
// is a little under two thirds of the quad across, which puts its edge at about
// ten degrees from the centre - a cosine of 0.985.
#define WATER_BODY_SIZE 0.995 // [0.9995 0.998 0.995 0.99 0.985 0.975 0.96]

// How bright a body is in a reflection. A reflection is not a surface being lit,
// so this is not the scene's exposure: it is the body's own light, and it is
// meant to be the brightest thing on the water.
#define WATER_BODY_BRIGHTNESS 4.0 // [1.0 2.0 4.0 8.0 16.0 32.0 64.0]

// What the moon is worth against the sun. It is the same sun's light, bounced
// off a rock, and the game draws it far dimmer up in the sky - so it is far
// dimmer here too, which is what keeps it a moon rather than a second sun.
#define MOON_TO_SUN 0.02

// The light the sun and the moon add in the given direction.
//
// Both directions are in view space, and they have to be. The game draws the sun
// and the moon into the sky from the position it holds for them, and that
// position is a view space one - so a disc placed from a world space direction
// is a disc that sits somewhere the real one is not, and the two drift apart as
// the camera's view bob changes. That mismatch is what a reflection of the sun
// swinging about the water as you walk is.
//
// The two fades below still read the world space direction, because how high a
// body is does not depend on which frame it is measured in, up to the bob, and
// they only drive a slow fade either side of the horizon.
vec3 SkyBodies(vec3 viewDir, vec3 sunViewDir) {
#if WATER_SKY_BODIES == WATER_SKY_BODIES_OFF
	return vec3(0.0);
#else
	// The two bodies are exactly opposite each other, so one dot product gives
	// both and the one below the horizon is simply never looked at.
	float muSun = dot(viewDir, sunViewDir);

	// A soft edge, not a hard one. At this angular size the disc is only a few
	// pixels across on screen, and a hard edge on something that small is a
	// stair-stepped blob rather than a sun.
	float sunDisc = smoothstep(WATER_BODY_SIZE, WATER_BODY_SIZE + 0.0015, muSun);
	float moonDisc = smoothstep(WATER_BODY_SIZE, WATER_BODY_SIZE + 0.0015, -muSun);

	// Each body fades as it sets and rises rather than switching at the horizon,
	// and rain covers both - the same rain that greys the sky and hides the
	// stars, so that the water and the sky above it agree about the weather.
	float sunUp = smoothstep(-0.12, 0.02, worldSunVector.y);
	float moonUp = smoothstep(-0.12, 0.02, -worldSunVector.y);
	float clear = 1.0 - rainStrength;

	vec3 sun = vec3(1.00, 0.94, 0.82) * (sunDisc * sunUp);
	vec3 moon = vec3(0.86, 0.91, 1.00) * (moonDisc * moonUp * MOON_TO_SUN);

	return (sun + moon) * (WATER_BODY_BRIGHTNESS * clear);
#endif
}

#endif // SKY_BODIES_GLSL_INCLUDED
