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

// Modified 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

#if !defined (EXTERNALLY_DEFINED_UNIFORMS)
	uniform vec3 caveFogColor;
	uniform float eyeSkylight;
	uniform int isEyeInWaterFog;

	uniform vec3 underwaterFogColor;
	uniform float atmosphereFogCoefficient;
	uniform float blindness;
	uniform float borderFogDistance;

	// How much haze rain adds, from 0 up to the option's value at full rain -
	// uniform.float.rainFogAmount in shaders.properties, which builds it from the
	// mod's rainStrength and the pack's own rain option. It is computed there
	// rather than here because of where it has to work as much as what it is; the
	// reasoning is recorded in BATCH_LOG.md 171. It is listed in voxy.json as
	// well, because the Voxy patch compiles this file with
	// EXTERNALLY_DEFINED_UNIFORMS and declares the pack's custom uniforms itself
	// - see BATCH_LOG.md 178.
	uniform float rainFogAmount;
#endif

// Whether to enable fog that hides the render distance border.
#define BORDER_FOG
// The strength of fog at noon. 
#define ATMOSPHERE_FOG_STRENGTH_NOON 0.5 // [0.0 0.25 0.33 0.5 0.66 0.75 1.0]

vec4 FogV2(
	out float skyFogStrength,
	float fragDistance,
	float borderFragDistance,
	float skyLightStrength
) {
	float borderFog;

	#ifdef BORDER_FOG
		borderFog = smoothstep(
			borderFogDistance - 8,
			borderFogDistance,
			borderFragDistance);
	#else
		borderFog = 0.0;
	#endif

	float atmosphereFog = pow(fragDistance, 3.0) * atmosphereFogCoefficient;

	// Transition the fog color in caves.
	float caveFogTransition = smoothstep(
		0.0,
		0.25,
		max(skyLightStrength, eyeSkylight));
	skyFogStrength = caveFogTransition;
	vec3 fogColor = (1.0 - caveFogTransition) * caveFogColor;

	// Rain hazes the view out, and this is added here rather than multiplied into
	// the term above it.
	//
	// Multiplying that term was the first attempt and it did nothing visible at
	// any setting, not even at four times: the coefficient behind it is
	// normalised to the render distance, so at fifty blocks the whole term is a
	// small fraction of one. atmosphereFogCoefficient is
	// renderDistanceFogTweak * pow(0.60 / borderFogDistance, 3.0) *
	// mix(1.0, atmosphereFogStrengthNoon, noonFogProgress) * fogInCaveAdjustment
	// (shaders.properties), and the term is pow(fragDistance, 3.0) times that, so
	// at fifty blocks it is 125000 * pow(0.60 / D, 3.0) * S with D the border fog
	// distance in blocks and S the noon strength - about 0.0033 at D = 160 and
	// S = 0.5, but 0.015 at D = 96. It is not one number, and the figure the
	// argument was made with is the one at the render distance it was made at.
	// The cull just below this block then throws away most of what is left: it
	// zeroes the sum outright at or under 0.01 and only reaches full by 0.015. A
	// far-distance term scaled up is still a far-distance term.
	//
	// What rain does to a view is bend the distance out of sight, and the shape
	// of that is an optical depth growing with distance - exponential. Recorded:
	// this is said to be what Sundial's rain fog is, and why it shows in the
	// middle distance rather than only at the horizon; that is a comparison with
	// another pack and nothing here stands behind it. RAIN_FOG_DISTANCE is the
	// distance at which the haze is 1 - 1/e, about two thirds of the way to its
	// full strength.
	//
	// Gated by the cave transition, the smoothstepped skylight the pack's own
	// atmosphere coefficient is gated by as well - fogInCaveAdjustment in
	// shaders.properties, which is the smoothstep polynomial applied to a
	// clamped eyeSkylight and multiplies that coefficient: rain does not thicken
	// the air inside a cave, and someone under cover sees the sky darken without
	// the fog following it in.
	const float RAIN_FOG_DISTANCE = 96.0;

	atmosphereFog += (1.0 - exp(-fragDistance / RAIN_FOG_DISTANCE))
		* rainFogAmount * caveFogTransition;

	// The End is deliberately not given a fog colour of its own here.
	//
	// It has no sky light, so the transition above already treats the whole
	// dimension as a cave and picks the cave colour - which is only half the
	// story. The other half is that the pack switches atmospheric fog off
	// wherever the eye's sky light is low: fogInCaveAdjustment in
	// shaders.properties is a smoothstep of clamp(eyeSkylight / 0.25) and it
	// multiplies atmosphereFogCoefficient, so the atmosphere term is exactly zero
	// wherever the eye's sky light is zero, which in the End is everywhere. What
	// is left there is the thin border band at the render distance. So there was
	// no fog in the End for a colour to be applied to, and the option that used
	// to do it here could only be seen in that band, between two colours that are
	// both very nearly black.
	//
	// Recorded: batch 333 removed it. See BATCH_LOG.md 189.

	if (blindness > 0.0001) {
		// Blindness is essentially just a very strong fog.
		atmosphereFog = max(
			0.85, 
			1.0 - exp(-pow(fragDistance * blindness * 0.5, 2)));
		fogColor = vec3(0.0);
		skyFogStrength = 0.0;
	} else if (isEyeInWaterFog == 1) {
		// Underwater fog is much more dense than atmospheric fog.
		// This is relatively similar to exp2 fog from the OpenGL
		// fixed function pipeline.
		atmosphereFog = 1.0 - exp(-pow(fragDistance * 0.02, 2));
		fogColor = underwaterFogColor;
		skyFogStrength = 0.0;
	} else if (isEyeInWaterFog == 2) {
		// Lava fog, also uses exponential fog but with a very high minimum
		// fog intensity as you aren't really supposed to be able to see much
		// when in lava (though in survival mode you won't be in the lava for
		// long!)
		atmosphereFog = max(0.85, 1.0 - exp(-pow(fragDistance * 0.5, 2)));
		fogColor = vec3(1.0, 0.05, 0.0);
		skyFogStrength = 0.0;
	}

	float fogFactor = min(borderFog + atmosphereFog, 1.0);

	// ⚠️ There used to be a cull here that zeroed the fog outright below 0.01 and
	// only reached full by 0.015:
	//
	//     if (skyFogStrength > 0.0) {
	//         fogFactor *= smoothstep(0.01, 0.015, fogFactor);
	//     }
	//
	// It was written as an optimization for close terrain, and the guard was meant
	// to disable it for the three cases that are close fog (blindness, underwater
	// and lava all set skyFogStrength to 0.0 above). What it did not account for is
	// the shape of the haze in *light* rain: rainFogAmount is VOLUMETRIC_FOG_RAIN
	// STRENGTH times the square of rainStrength, so at a third of full rain the
	// whole rain term is under 0.01 out to about fifteen blocks and over it by
	// twenty - which is a ring of clear air around the player with the haze
	// switching on at the edge of it. Reported as a boundary close to the player in
	// rain, and removed in batch 462.
	//
	// What is left is the number itself, which fades in from zero: at the distances
	// where the cull used to bite, the fog factor is a hundredth or so, which is
	// invisible in a mix. Removing it costs nothing that can be seen and is one
	// smoothstep less per pixel.

	return vec4(fogColor, fogFactor);
}

// Kept around while we move over to FogV2
// TODO: Move everything to FogV2 and just have one Fog function
//
// Not dead yet: this is the wrapper FogV2 needs anyway, since FogV2 returns the
// fog colour and the fog factor separately and does not add the sky gradient
// in. Its callers are translucent.glsl, copy_and_fog.fsh and clouds.vsh; lit.fsh
// is the one that asks FogV2 directly.
vec4 Fog(
	vec3 skyGradient,
	float fragDistance,
	float borderFragDistance,
	float skyLightStrength
) {
	float skyFogStrength = 0.0;
	vec4 fogv2 = FogV2(
		skyFogStrength,
		fragDistance,
		borderFragDistance,
		skyLightStrength);
	fogv2.rgb += skyGradient * skyFogStrength;
	return vec4(fogv2.rgb * fogv2.a, 1.0 - fogv2.a);
}
