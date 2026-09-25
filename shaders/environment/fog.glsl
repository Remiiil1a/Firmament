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

	// How much haze rain adds, from 0 up to the option's value at full rain.
	// Built in shaders.properties from the mod's rainStrength, which is a quantity
	// that file can read and the shading stages cannot be sure of - see
	// PBR_PORTING.md 171. It is listed in voxy.json as well, because the Voxy
	// patch compiles this file with EXTERNALLY_DEFINED_UNIFORMS and declares the
	// pack's custom uniforms itself - see PBR_PORTING.md 178.
	uniform float rainFogAmount;
#endif

// The End's haze color. Uniforms: dimension, biome_category
#include "/environment/lighting/end_lighting.glsl"

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
	// normalised to the render distance - pow(0.60 / borderFogDistance, 3.0) in
	// shaders.properties - so at fifty blocks the whole term is around 0.003, and
	// the cull just below this block throws away anything under 0.015 outright. A
	// far-distance term scaled up is still a far-distance term.
	//
	// What rain does to a view is bend the distance out of sight, and the shape
	// of that is an optical depth growing with distance - exponential, which is
	// what Sundial's rain fog is and why it shows in the middle distance rather
	// than only at the horizon. RAIN_FOG_DISTANCE is the distance at which the
	// haze is about two thirds of the way to its full strength.
	//
	// Gated by the cave transition, the smoothstepped skylight the pack's own
	// atmosphere coefficient is gated by as well: rain does not thicken the air
	// inside a cave, and someone under cover sees the sky darken without the fog
	// following it in.
	const float RAIN_FOG_DISTANCE = 96.0;

	atmosphereFog += (1.0 - exp(-fragDistance / RAIN_FOG_DISTANCE))
		* rainFogAmount * caveFogTransition;

	// The End has no sky light either, so the line above treats the whole
	// dimension as a cave and fogs it with the cave's color. Its sky is open
	// space, though, so its haze is the color of that space instead - which is
	// what lets its islands fade into the sky rather than into a grey wall.
	//
	// Applied before the branches below, so that being underwater or blind in
	// the End still overrides it.
	if (EndDimension()) {
		fogColor = mix(fogColor, END_FOG_COLOR, END_FOG);
	}

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

	if (skyFogStrength > 0.0) {
		// Zero out low-strength fog to enable an optimization on most close
		// terrain. This does not work with very closer fog so this is a hack to
		// disable it (such as when underwater).
		fogFactor *= smoothstep(0.01, 0.015, fogFactor);
	}

	return vec4(fogColor, fogFactor);
}

// Kept around while we move over to FogV2
// TODO: Move everything to FogV2 and just have one Fog function
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
