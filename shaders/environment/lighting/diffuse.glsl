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

// This is a high-performance lighting model that delivers pleasing visuals
// while requiring only shadow mapping. By carefully tweaking ambient lighting,
// a look similar to indirect lighting can be achieved without the associated
// complexity and performance cost.

// LabPBR material decoding and the metallic BRDF.
// Uniforms: normals, specular (only when PBR_SURFACE is defined)
#include "/environment/lighting/pbr.glsl"

// The End's own light, which is what stops that dimension from being lit by
// nothing but the ambient floor. Uniforms: dimension, biome_category
#include "/environment/lighting/end_lighting.glsl"

// Whether to use the new direct lighting model with atmospheric scattering.
#define MINISHITA_LIGHTING
#ifdef MINISHITA_LIGHTING
	// Actual effect is in shaders.properties
#endif

#define STEADFAST BY_CODERBOT // Authorship attribution. [BY_CODERBOT]

// Authorship attribution for this edit. Nothing in the shader reads these - the
// lang files carry the strings, and the settings screen both titles itself with
// the FIRMAMENT token and lists all three as credits. See NOTICE.md.
//
// The name carried by FIRMAMENT has to end with "(edit of coderbot's Steadfast)"
// - that parenthesis is required by Steadfast's additional terms (GPLv3 7c/7e),
// so do not shorten it away.
#define FIRMAMENT BY_REMIIIL1A // Authorship attribution. [BY_REMIIIL1A]

// The other shaders this one references or quotes code from - one credit each,
// rather than one credit per feature, and rather than one entry with all of
// them in it. They are listed on a Special thanks page of their own under
// "Credits & licence"; see NOTICE.md for the licence terms that go with them.
//
// Steadfast itself has its own entry above rather than one here, because
// Steadfast's additional terms require their notice to appear on its own,
// before any download link.
#define THANKS_MELLOW BY_THECMK // Authorship attribution. [BY_THECMK]
#define THANKS_SUNDIAL BY_GEFORCELEGEND // Authorship attribution. [BY_GEFORCELEGEND]

#define FANTASY 0
#define SEMI_NATURAL 1
#define RETRO 2

// The style of direct and ambient sky lighting to use during the day.
#define DAY_SKY_LIGHTING RETRO // [FANTASY SEMI_NATURAL RETRO]

// The style of direct and ambient sky lighting to use at night.
#define NIGHT_SKY_LIGHTING FANTASY // [FANTASY SEMI_NATURAL RETRO]

// Whether real-time shadows using shadow mapping are enabled for entities.
#define REAL_TIME_ENTITY_SHADOWS
#ifdef REAL_TIME_ENTITY_SHADOWS
	// Actual effect is in shaders.properties
#endif

// Whether real-time shadows using shadow mapping are enabled for block entities
// (chests, beds, etc).
// #define REAL_TIME_BLOCK_ENTITY_SHADOWS
#ifdef REAL_TIME_BLOCK_ENTITY_SHADOWS
	// Actual effect is in shaders.properties
#endif

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform vec3 minAmbient;
	uniform vec3 skyAmbient;
	uniform float blocklightSuppression;
	uniform float nightVision;

	// The lightmap, which is where the color of block light comes from. See
	// BlockLightTint below.
	uniform sampler2D lightmap;
	#define BLOCKLIGHT_HAS_LIGHTMAP
#endif

// The same lightmap, for the programs whose uniforms come from elsewhere - which
// is Voxy's terrain, and only Voxy's terrain.
//
// No declaration here, and that is the whole subtlety: an entry in the samplers
// map of voxy.json is not this pack asking for a sampler, it is Voxy being told
// to declare one and bind a texture to it. Voxy therefore emits the declaration
// itself into every program that reads that file, and a second one written here
// would be the same declaration twice in one program - which does not compile.
// What this file contributes is only the knowledge that the sampler is there to
// be sampled.
//
// This is the same arrangement the pack's rainStrength uniform has with the same
// file, and it is what the source checker's rules about the Voxy chain exist to
// catch. They caught this one; see PBR_PORTING.md 147.
//
// What it is for: without it, level-of-detail terrain is the one place in the
// world that cannot see the lightmap, so it is the one place whose block light has
// no color to take - and taking the color from the lightmap everywhere else is
// what left the far half white while the near half stayed warm. Lighting that
// changes color at the edge of the render distance is worse than lighting that is
// wrong everywhere, because the edge moves.
#if defined(EXTERNALLY_DEFINED_UNIFORMS) && defined(VOXY_LIGHTMAP)
	#define BLOCKLIGHT_HAS_LIGHTMAP
#endif

// How bright block light is at full block light level.
//
// This number is the pack's own rather than something read from the lightmap:
// the lightmap supplies the color, but the brightnesses it carries have its own
// falloff baked into them, and this model replaces that with its own falloff
// and this.
#define BLOCKLIGHT_STRENGTH 4.0 // [1.0 2.0 3.0 4.0 5.0 6.0 8.0]

// The color temperature of block light, in kelvin.
//
// The color of block light comes from the lightmap, because the lightmap is how
// a resource pack says what color its lights are - see BlockLightTint below. This
// is for the case where a resource pack says nothing, or says something that does
// not suit the world being built, and what is wanted is to move the whole of it
// warm or cool without editing the pack. It reaches the level-of-detail terrain
// as well, which has no lightmap and takes a color of the pack's own; see the
// note in BlockLightTint's far branch.
//
// The scale is the one a photographer uses. A candle and a torch are around
// 1800 to 2500 K and read as deep orange; an incandescent bulb is 2700 K, which
// is the warm white most people mean by "warm"; 4000 K is neutral; daylight is
// 5500 to 6500 K; an overcast sky is 7000 and up and reads blue. So lowering this
// makes block light more yellow, and raising it makes it whiter and then blue.
//
// 6500 is the middle of the scale rather than the middle of the numbers, and it is
// the default because it is exactly no change: the tint below is computed as a
// ratio against this value, so at 6500 it is one and the pack draws what it drew
// before this option existed. Every other setting moves away from that.
//
// A hundred kelvin per step, because that is the finest step anybody can see on a
// light color and anything finer would be a list of numbers no one could read.
#define BLOCKLIGHT_TEMPERATURE 6500 // [1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 2100 2200 2300 2400 2500 2600 2700 2800 2900 3000 3100 3200 3300 3400 3500 3600 3700 3800 3900 4000 4100 4200 4300 4400 4500 4600 4700 4800 4900 5000 5100 5200 5300 5400 5500 5600 5700 5800 5900 6000 6100 6200 6300 6400 6500 6600 6700 6800 6900 7000 7100 7200 7300 7400 7500 7600 7700 7800 7900 8000 8100 8200 8300 8400 8500 8600 8700 8800 8900 9000 9100 9200 9300 9400 9500 9600 9700 9800 9900 10000]

// What the option above is a ratio against, which is the value that leaves the
// light alone.
#define BLOCKLIGHT_TEMPERATURE_NEUTRAL 6500.0

// The color a black body at this temperature glows, from Tanner Helland's
// approximation of the Planckian locus - the same curve the kelvin scale on a
// camera or a light bulb is drawn from.
//
// Every pow() below has a guarded base, and that is the lesson from
// PBR_PORTING.md 139 rather than caution for its own sake: a pow() with a
// negative base is undefined in GLSL and comes out as a NaN on the drivers this
// pack has been tested on, and the two expressions here are of the form
// (t - 60) to a negative power, which is negative for every temperature below
// 6000 K - that is, most of the list above. The clamps are what make the two
// halves of each branch meet.
vec3 BlockLightTemperatureRgb(float kelvin) {
	float t = clamp(kelvin, 1000.0, 40000.0) * 0.01;

	float red = t <= 66.0
		? 255.0
		: 329.698727446 * pow(max(t - 60.0, 1.0), -0.1332047592);

	float green = t <= 66.0
		? 99.4708025861 * log(max(t, 1.0)) - 161.1195681661
		: 288.1221695283 * pow(max(t - 60.0, 1.0), -0.0755148492);

	float blue;
	if (t >= 66.0) {
		blue = 255.0;
	} else if (t <= 19.0) {
		blue = 0.0;
	} else {
		blue = 138.5177312231 * log(max(t - 10.0, 1.0)) - 305.0447927307;
	}

	return clamp(vec3(red, green, blue) / 255.0, vec3(0.0), vec3(1.0));
}

// The factor to multiply block light's color by.
//
// Two normalizations, and both of them are the difference between this being a
// color control and being a second brightness control:
//
//  - Against the neutral temperature, so that the default setting is exactly one
//    and the option does nothing until it is moved. Without this every setting
//    would also brighten or darken the world by whatever the curve happens to do
//    at that temperature.
//  - Against its own brightness afterwards, so that the factor changes the hue
//    and not the luminance. A warm tint that also took a third of the light away
//    would read as "warmer and darker", and the two are separate controls here:
//    BLOCKLIGHT_STRENGTH above is the brightness one.
//
// Both arguments are compile-time constants, so a driver folds this to two
// constants; the two calls are kept as calls rather than written out because the
// curve is the thing being documented.
vec3 BlockLightTemperatureTint() {
	vec3 tint = BlockLightTemperatureRgb(float(BLOCKLIGHT_TEMPERATURE))
		/ BlockLightTemperatureRgb(BLOCKLIGHT_TEMPERATURE_NEUTRAL);

	float luma = dot(tint, vec3(0.2126, 0.7152, 0.0722));

	return tint / max(luma, 1.0e-4);
}

// The color of block light, taken from the lightmap.
//
// This used to be a color of the pack's own - a warm orange - which is a
// reasonable average of every light in the game and wrong for every one of them
// individually, and it is not the pack's to choose in the first place: the
// lightmap is a texture, and recoloring it is how a resource pack says what
// color its lights are. Sampling it here means block light is whatever the
// lightmap says it is, which is both more correct and something a resource pack
// can change without touching this pack at all.
//
// Sampled at zero sky light so that this is the block light's color with no
// contribution from the sky, and reduced to its hue, because the brightness of
// block light is built from the falloff in BlockLighting and
// BLOCKLIGHT_STRENGTH rather than from the lightmap's own.
//
// BLOCKLIGHT_TEMPERATURE then moves that hue along with everything else - see the
// note on the option, and the note on the far half of the world in the branch
// below.
vec3 BlockLightTint(vec2 lightMapCoord) {
	#if defined(BLOCKLIGHT_HAS_LIGHTMAP)
		vec3 tint = texture(lightmap, vec2(lightMapCoord.x, 1.0 / 32.0)).rgb;

		// A lightmap that cannot be read comes back black, which would put every
		// light in the world out. Neutral is the safe answer.
		if (dot(tint, tint) < 0.0001) {
			return vec3(1.0);
		}

		// Only the hue: scaled so that its brightest channel is one, and then
		// moved to the temperature the option asks for.
		return tint / max(max(tint.r, tint.g), tint.b)
			* BlockLightTemperatureTint();
	#else
		// Reached only by a program that reads its uniforms from elsewhere and was
		// not given the lightmap - which is no program at all now that Voxy's
		// terrain asks for it, and is kept because a path that cannot be taken is
		// cheaper to keep than to rediscover. What it used to be is in
		// PBR_PORTING.md 146: the fallback was a warm orange of the pack's own,
		// written here to undo a regression where this returned white, and 147
		// replaced it with the lightmap itself for the programs that can have one.
		//
		// The temperature option is applied here too, so that a program which ends
		// up on this path still moves with everything else.
		return vec3(1.0, 0.52, 0.20) * BlockLightTemperatureTint();
	#endif
}

float AmbientStrength(float worldDirY) {
	// Mimic vanilla directional lighting by varying the strength of ambient
	// lighting based on whether the face is facing upwards, downwards, or
	// sideways.
	return (0.67 + worldDirY * 0.33);
}

vec3 AmbientSkyLighting(float skyLightStrength, float ambientStrength) {
	// x^3 falloff to have a more even transition
	float skyLight = pow(skyLightStrength, 3);

	// Whether sky light intensity should be directly based on the face
	// direction.
	#define DIRECTIONAL_SKYLIGHT_SHADING

	// A flat floor under the ambient light, in linear light units.
	//
	// Everything above scales with sky light, which is what makes unlit places
	// - the inside of a cave, the Nether, and the End, which has no sky light at
	// all - sit at a brightness close to black. This adds a constant instead of
	// scaling, so raising it lifts those places to something readable without
	// flattening the falloff around a torch or washing the color out of a
	// surface.
	//
	// It is deliberately not affected by sky light: the point is that this light
	// is there when nothing else is.
	//
	// The range goes well above the default because of how little a small
	// number does here: Steadfast's tonemapper is close to the identity below
	// 0.6 in linear light, so what is written here is roughly what reaches the
	// screen, multiplied by the surface's color. A cave floor at 0.05 is a very
	// dark grey; making one properly readable takes several times that.
	#define MIN_AMBIENT_BRIGHTNESS 0.1 // [0.0 0.01 0.03 0.05 0.1 0.2 0.35 0.6]

	// Fade sky ambient lighting away as sky light fades away, as that helps us
	// rather convincingly approximate indirect lighting. But, have a "minimum"
	// ambient color so that caves are not completely black.
	#ifdef DIRECTIONAL_SKYLIGHT_SHADING
		return ambientStrength * (minAmbient
			+ vec3(MIN_AMBIENT_BRIGHTNESS)
			+ skyLight * skyAmbient);
	#else
		return ambientStrength * minAmbient
			+ vec3(MIN_AMBIENT_BRIGHTNESS)
			+ skyLight * skyAmbient;
	#endif
}

// Desaturate terrain that receives moonlight without being lit by block light.
#define NIGHT_DESATURATION_EFFECT 
#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	#ifdef NIGHT_DESATURATION_EFFECT
		uniform float desaturationIntensity;
	#else
		const float desaturationIntensity = 0.0;
	#endif
#endif

// Whether blocks in your hand should dynamically cast light on surroundings.
#if !defined(NO_HELD_BLOCK_LIGHTING)
	#define HELD_BLOCK_LIGHTING 
#endif

#ifdef HELD_BLOCK_LIGHTING
	#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
		uniform float heldLightBaseStrength;
		uniform float heldLightSuppression;
	#endif
#else
	const float heldLightBaseStrength = 0.0;
	const float heldLightSuppression = 0.0;
#endif

float HeldLightStrength(vec3 cameraRelativePos) {
	// This is an attempt to model held light strength off of the same scale as
	// Minecraft block lights use.
	//
	// Previously, this used the inverse-square law, but this lead to held light
	// having an impact very far away from the player, which felt implausible.
	//
	// Implicitly, the light position is centered on the camera. This might not
	// be desired, so to adjust, simply subtract the light position from the
	// desired light position.
	float fragDistance = length(cameraRelativePos);
	return clamp(heldLightBaseStrength - fragDistance / 15.0, 0.0, 1.0);
}

// Desaturate terrain that receives moonlight without being lit by block light.
float NightDesaturation(float skyLight, float blockLight) {
	#ifndef NIGHT_DESATURATION_EFFECT
		return 0.0;
	#endif

	// Nighttime desaturation is applied to surfaces that are exposed to the sky
	// but not subject to block light.
	return desaturationIntensity * skyLight * (1.0 - blockLight);
}

#ifdef NIGHT_DESATURATION_EFFECT
	#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
		uniform vec3 desaturationColor;
	#endif

	vec3 Desaturate(vec3 color, float desaturation) {
		// Rec601 luma from https://en.wikipedia.org/wiki/Luma_(video)
		// TODO: Use luminance, luma is for sRGB only.
		float luma = dot(color, vec3(0.299, 0.587, 0.114));

		// Fade the pre-lighting color to the desaturation color
		return mix(color, luma * desaturationColor, desaturation);
	}
#endif

vec3 BlockLighting(
	// Where this fragment sits in the lightmap, which is where the color of its
	// block light comes from.
	vec2 lightMapCoord,
	float skyLight,
	float blockLight,
	float heldLight
) {
	// Give block lighting a strong but visually appealing falloff.
	float blockLightIntensity = pow(blockLight, 4.0);
	float heldLightIntensity = pow(heldLight, 4.0);

	// Apply block light suppression (see details in shaders.properties).
	//
	// sqrt(skyLight) makes the suppression affect most areas impacted
	// by skylight.
	blockLightIntensity *= 1.0 - sqrt(skyLight) * blocklightSuppression;

	// For held light, we also suppress it if the player is standing in sky
	// light, so that suppressed light held by the player doesn't still get
	// cast into a cave or dark area nearby.
	float heldLightSkyLight = sqrt(max(skyLight, heldLightSuppression));
	heldLightIntensity *= 1.0 - heldLightSkyLight * blocklightSuppression;

	// This method of combining held light and block light avoids weird lines
	// where the lights intersect.
	return BlockLightTint(lightMapCoord)
		* (BLOCKLIGHT_STRENGTH * min(1.0, blockLightIntensity + heldLightIntensity));
}

// Tilt the path of the sun sideways. This is a standard shader effect that
// makes shadows look much better.
const float	sunPathRotation	= -40.0f;

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
		uniform int isEyeInWater;
	#endif

	uniform vec3 directLightSurface;
	uniform vec3 directLightUnderwater;
	uniform vec3 worldLightVector;
#endif

void ApplyWaterAbsorption(
	// Water depth in meters
	float wdepth,
	out vec3 directLightColor,
	inout vec3 lighting,
	vec3 blocklightIndirect
) {
	// Determine the tint needed to simulate water absorption
	vec3 waterAbsorption = WaterAbsorption(wdepth);

	// Fade direct light color to its luminance to avoid odd colors
	// when orange sunrise light goes through water
	directLightColor = mix(directLightSurface, directLightUnderwater, wdepth);

	// Tint lighting (direct and ambient, but not block lighting) by the water
	// absorption
	directLightColor *= waterAbsorption;

	// Near the water surface, make water absorption apply to block light, but
	// do not apply it fully when deep underwater. This is so that lights in
	// underwater bases are not completely overwhelmed by the water absorption,
	// but also so that lights placed near the surface do not appear to pass
	// through the surface and ignore it completely.
	//
	// This is critical because in environments where the sky is not very
	// bright, for example, the semi-natural profile at night, we rely on the
	// water absorption to communicate that there is water. Without this, block
	// light completely breaks the illusion.
	//
	// Even though at maximum depth we still only allow 33% of the block light
	// to pass unaffected by water absorption, the original color of the block
	// light is visible just darker than usual, as at maximum depth water
	// absorption eliminates most light.
	float blocklightNotAbsorbed = 0.33 * wdepth;
	lighting += blocklightIndirect * (1.0 - blocklightNotAbsorbed);

	// Apply water absorption and then add in the block light not affected by
	// water absorption.
	lighting *= waterAbsorption;
	lighting += blocklightIndirect * blocklightNotAbsorbed;
}

struct SurfaceFragment {
	#if defined(REAL_TIME_SHADOWS)
		vec3 cameraRelativePos;
		// The projected shadow map position to sample from.
		//
		// X and Y are coordinates in the shadow map texture, and Z is the
		// depth value to compare the sampled shadow depth against to
		// determine to what extent the fragment is or is not in shadow.
		vec3 shadowPos;
	#endif
	// The linear RGB color of the surface at this position, including all AO
	// and tinting.
	vec3 surfaceColor;
	// The predefined material ID of this fragment.
	uint materialID;
	// The normal vector of the surface where this fragment is, in world-space.
	vec3 worldNormal;
	// This fragment's coordinate in the lightmap, which is where the color of
	// block light is read from. Not folded into the block light strength below
	// because the color has to be looked up, not computed.
	vec2 lightMapCoord;
	// The sky light strength, where 1 is light level 15 and 0 is no light.
	float skyLight;
	// The block light strength, where 1 is light level 15 and 0 is no light.
	float blockLight;
	// The held light strength, where 1 is light level 15 and 0 is no light.
	float heldLight;
};

float DirectLighting(
	SurfaceFragment fragment,
	bool subsurfaceScatter,
	PbrSurface pbr,
	vec3 viewDirection,
	// The specular reflection of this light, in linear RGB. Left at zero for
	// every material that does not reflect anything.
	out vec3 specular,
	// How much of the direct light survives the shadow sources, where 1.0 is
	// fully lit. Read by the subsurface scattering term in
	// PbrSubsurfaceScatter, which is a fraction of the light that arrives.
	out float shadowVisibility,
	// The colour the direct light arrives in, white unless stained glass stood in
	// its way. Written by ShadowMapping on every path through it.
	out vec3 shadowTint
) {
	// Note: these are set before any of the early outs below, so that callers
	// never read an undefined value.
	specular = vec3(0.0);
	shadowVisibility = 0.0;
	shadowTint = vec3(1.0);

	// Derive the direct lighting contribution (directLightStrength), which for
	// most surfaces is Lambertian:
	//
	// - Only faces directly facing the light source receive the full intensity
	// - Faces gradually darken as the angle between them and the light
	//   approaches 90 degrees
	// - Faces that are facing away from the light receive none of the light
	float directLightStrength = dot(fragment.worldNormal, worldLightVector);

	// Foliage and glass diverge from the pure Lambertian lighting model to
	// account for their subsurface scattering, which lets sunlight partially
	// pass through the foliage surface.
	if (subsurfaceScatter) {
		// The direct light strength is overridden in the shadow-mapping code to
		// 0.7071 (~= cos(pi/4)) within the shadow map for materials with
		// subsurface scattering.
		//
		// Outside of the shadow map, that would be too bright, so we darken
		// based on direction like so:
		if (fragment.materialID == LEAVES) {
			directLightStrength = directLightStrength * 0.50 + 0.50;
		} else {
			directLightStrength = directLightStrength * 0.35 + 0.65;
		}
	} else if (fragment.materialID == GLASS) {
		// Because glass is transparent / translucent and does not cast shadows,
		// directional shading looks implausible on it, hence we use a different
		// shading model.
		directLightStrength = fragment.worldNormal.y * 0.2071 + 0.5;
	} else {
		#ifndef DIRECTIONAL_SKYLIGHT_SHADING
			// Stylized lighting model:
			//
			// - Faces facing the light source in nearly any way receive the
			//   full light intensity
			// - Faces that approach 90 degrees or more away from the light
			//   rapidly fade to dark
			// - Faces that are facing away from the light receive no light
			directLightStrength = smoothstep(-0.05, 0.05, directLightStrength);
		#else
			directLightStrength = max(directLightStrength, 0.0);
		#endif

		// Only sample the shadow map if this face can receive shadows. Glass
		// and materials with subsurface scattering can always receive shadows.
		if (directLightStrength < 0.0001) {
			return 0.0;
		}
	}

	// Fade away direct lighting based on the sky lighting.
	//
	// Otherwise, the intensity of direct sunlight would otherwise be the same
	// as on land even for deep underwater terrain!
	//
	// In addition, as ambient light brightness decreases as the sky light
	// strength decreases, this is necessary even if we are not underwater, as
	// otherwise darker ambient environments look really odd when the direct
	// light is bright but the ambient light is dark.
	//
	// However, we allow a very very small direct light lower bound to allow for
	// some shadows deep underwater / etc.
	//
	// TODO: This is also the only reason why there is any light in the End.
	directLightStrength *= max(fragment.skyLight, 0.125 / 16.0);

	// This static (lightmap) shadowing technique is a way of treating areas
	// with less than a full skylight level as being shaded. At a distance, it
	// is difficult to notice, and far more visually appealing than terrain
	// without any shadows. The technique and tuned fading factors are from:
	//
	// - Photon Shaders by SixthSurge:
	//   https://github.com/sixthsurge/photon
	//   
	//   File /shaders/include/lighting/shadows.glsl#L56-L59 as of commit
	//   26c2906ee02cc484359b835fba6993d443d45966
	float shadowSample = smoothstep(
		// Everything darker than this will be fully in shadow
		13.5 / 15.0,
		// Everything lighter than this will be fully lit
		14.5 / 15.0,
		fragment.skyLight);

	#ifdef REAL_TIME_SHADOWS
		directLightStrength = ShadowMapping(
			fragment.materialID,
			shadowSample,
			subsurfaceScatter,
			directLightStrength,
			fragment.shadowPos,
			fragment.cameraRelativePos,
			// Zero unless PBR_SUBSURFACE is on and this material's specular map
			// says it is thin, which is what confines the shadow softening to
			// the feature. See PbrDecode.
			pbr.sss,
			shadowVisibility,
			shadowTint);
	#else
		directLightStrength *= shadowSample;
		shadowVisibility = shadowSample;
		// No shadow map, so no buffer of colours that came through glass either -
		// see COLORED_SHADOWS in /environment/materialIDs.glsl.
		shadowTint = vec3(1.0);
	#endif

	#ifdef PBR_SURFACE
		// The height field can stand between this point and the light, which is
		// what gives the displaced surface visible sides. This is applied before
		// the specular below so that the highlight is occluded along with the
		// diffuse light. It never affects ambient light, which does not come
		// from one direction and so cannot be blocked by a bump.
		directLightStrength *= pbr.selfShadow;
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR)
		// Compute the specular reflection before the metalness reduction below,
		// as the highlight is not affected by how much diffuse response the
		// material keeps.
		//
		// We deliberately pass directLightStrength through as the light term
		// rather than recomputing N·L: it already carries both the shadow map
		// result and the pack's sky light falloff, so the highlight is occluded
		// exactly like the diffuse light is and the shadow map is never sampled
		// a second time.
		specular = PbrSpecular(
			pbr,
			fragment.worldNormal,
			worldLightVector,
			viewDirection,
			directLightStrength);

		#if defined(PBR_ENERGY_CONSERVATION)
			// What the surface did not reflect is what lights it from the
			// inside. Applied before the metal reduction below, which removes
			// the rest of the diffuse response a metal should not have.
			directLightStrength *= PbrDirectDiffuseWeight(
				pbr,
				worldLightVector,
				viewDirection);
		#endif

		// Metals have no diffuse response of their own. See PBR_METAL_DIFFUSE
		// for why this is only a partial reduction.
		directLightStrength *= 1.0 - PBR_METAL_DIFFUSE * pbr.metalness;
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_POROSITY_WETNESS)
		// Rain darkens a porous surface by filling the pores that its light
		// response comes from.
		//
		// Applied after the specular above for the same reason the metal
		// reduction just above is: a wet surface reflects more of its
		// surroundings, not less, so the highlight must not be dimmed along with
		// the diffuse light.
		directLightStrength *= 1.0 - PbrWetnessDarkening(pbr, fragment.skyLight);
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SUBSURFACE)
		// The light that goes through the surface instead of bouncing off it,
		// added to the direct light because it is a fraction of it.
		//
		// This is done after the specular above, so the highlight is built from
		// the light that reflects off the surface and is not lit by the light
		// that comes through it. It is also deliberately not routed through the
		// metal reduction just above, as a surface that scatters is thin and a
		// metal is not.
		directLightStrength += PbrSubsurfaceScatter(
			pbr,
			fragment.worldNormal,
			worldLightVector,
			viewDirection,
			shadowVisibility);
	#endif

	return directLightStrength;
}

// The shared implementation of the lighting model. Programs that have no PBR
// material data available pass PbrNone(), which makes the PBR branches below
// compile-time dead code - see the two wrappers underneath.
vec3 DiffuseLightingImpl(
	SurfaceFragment fragment,
	PbrSurface pbr,
	// The direction from this fragment towards the camera, in world space.
	vec3 viewDirection,
	// How much of the colour this returns is a mirror rather than light the
	// surface was given, in linear RGB. Two things make it up: the highlight of
	// the sun or moon, and the environment term further down. Both are
	// reflections, and a reflection is a picture of a light rather than a light
	// - which is the whole reason the bloom leaves it out.
	//
	// Written on every path through this function. The callers that have no use
	// for it pass a variable nobody reads.
	out vec3 specularColor
) {
	// Set before any of the early outs below, so that no caller ever reads an
	// undefined value - the same rule the two outputs of DirectLighting follow.
	specularColor = vec3(0.0);

	// Part of approximating subsurface scattering
	bool subsurfaceScatter = fragment.materialID == SUBSURFACE_SCATTERING \
		|| fragment.materialID == GROUND_FOLIAGE \
		|| fragment.materialID == LEAVES;

	// Strength of the ambient lighting contribution (sky & min ambient)
	float ambientStrength = AmbientStrength(
		subsurfaceScatter ? 0.7071 : fragment.worldNormal.y);

	vec3 lighting = AmbientSkyLighting(
		// When night vision is active, treat everything as fully lit by sky
		// light.
		max(fragment.skyLight, nightVision),
		ambientStrength);

	// The End's own light, which is zero in every other dimension. Its sky
	// gives no sky light at all, so everything above contributes almost nothing
	// there and its islands would otherwise be lit by the ambient floor alone -
	// which is what actually lights them, at a level the pack's own
	// MIN_AMBIENT_BRIGHTNESS sets. This is a brightening on top of that; see
	// the note in end_lighting.glsl.
	lighting += EndAmbientLighting(ambientStrength);

	// Compute the contribution to indirect lighting from block light without
	// immediately applying it. When water absorption is enabled, for gameplay
	// purposes we tweak the amount of water absorption applied to blocklight
	// based on depth to avoid ruining submerged bases.
	vec3 blocklightIndirect = BlockLighting(
		fragment.lightMapCoord,
		fragment.skyLight,
		fragment.blockLight,
		fragment.heldLight
	);

	vec3 directLightColor = directLightSurface;

	#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
		// With refraction-assisted water absorption, we need an alternate way
		// to apply water absorption when the viewpoint is itself underwater, as
		// in this case, we can see the underwater terrain without it being
		// behind any refractive surface.
		// 
		// Minecraft helpfully puts water surfaces around glass and similar, so
		// underwater bases in glass domes for example will work fine when
		// applying water absorption just on refraction, but if the view is
		// actually within water, then we can utilize the skylight based water
		// depth to apply absorption.
		//
		// The only difficult part is the transition between above water and
		// underwater. This is because we can be in a state where the bottom of
		// the screen is underwater, even though the center of the screen is
		// above and can see above water. In this case, it is not trivial to
		// tell if any given piece of terrain should receive water absorption.
		//
		// We rectify this with a clever hack that aims to cover the bottom half
		// of the screen with water until the player's eyes are actually
		// underwater, which takes place near the end of the lit vertex shader.
		if (isEyeInWater == 1) {
			// TODO: Water depth calculation copied from
			// /environment/water/absorption_refraction.glsl
			// It should be in a common function
			float waterDepth = (-15.0 / 16.0) * fragment.skyLight + 1.0;

			ApplyWaterAbsorption(
				waterDepth,
				directLightColor,
				lighting,
				blocklightIndirect);
		} else {
			lighting += blocklightIndirect;
		}
	#else
		lighting += blocklightIndirect;
	#endif

	#ifdef PBR_SURFACE
		// The occlusion the resource pack baked into the material, which only
		// says anything about light that arrives from no particular direction -
		// the sky's ambient light and the block light around the fragment.
		// Applying it here, before the environment reflection reads the same
		// value below, is what makes a crevice reflect less of the sky as well
		// as receive less of it.
		//
		// The direct sunlight added further down is deliberately left alone: a
		// baked occlusion map has no idea where the sun is, and the shadow map
		// and the parallax height field already darken what the light cannot
		// reach, so applying both would darken sunlit surfaces twice.
		//
		// Water absorption above has already run, so it scales the absorbed
		// result rather than being scaled by it - which is what it should be,
		// as the absorption describes how much light the water takes away, not
		// how much the material lets through.
		lighting *= PbrMaterialOcclusion(pbr);
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR)
		// Everything that is not direct lighting, which is what stands in for
		// the environment a surface reflects. Captured here because the direct
		// lighting is added to `lighting` below.
		vec3 indirectLighting = lighting;
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_POROSITY_WETNESS)
		// The same wet darkening as in DirectLighting, for everything that is
		// not direct light.
		//
		// Placed after the environment reflection has read the light above, for
		// the same reason it comes after the specular there: what is left of a
		// wet surface is a sheen, so the reflection is the one thing that should
		// not fade with it.
		lighting *= 1.0 - PbrWetnessDarkening(pbr, fragment.skyLight);
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR) && defined(PBR_ENERGY_CONSERVATION)
		// The same energy split as in DirectLighting, for everything that is not
		// direct light.
		//
		// Placed after the environment reflection above has read the light, so
		// that the environment is still reflected at full strength: it is the
		// diffuse response that has to give way for it, not the other way round.
		lighting *= PbrAmbientDiffuseWeight(pbr, fragment.worldNormal, viewDirection);
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR)
		// A metal has no diffuse response at all, and this is the indirect half
		// of taking it away - the direct half is scaled in DirectLighting above,
		// for the same reason and by the same option.
		//
		// It has to be here rather than there because the two halves arrive by
		// different routes: the direct one is a single term, while this one is
		// the sky's ambient light, the block light around the fragment, the
		// ambient floor, the material's own occlusion and the dimension's
		// additions, already summed. Scaling the sum is the only place that
		// covers all of them.
		//
		// It is placed after indirectLighting was captured above and before the
		// ambient specular is added below, which is what keeps this from being
		// applied to the reflection: what a metal still has left is exactly that
		// reflection, and dimming it here would undo the same light twice.
		lighting *= 1.0 - PBR_METAL_DIFFUSE * pbr.metalness;
	#endif

	// The specular reflection of the direct lighting, which is zero for every
	// material that does not reflect anything.
	vec3 specular;

	// How much of the direct light survives the shadows. Only the subsurface
	// scattering term reads it, and it is written by DirectLighting on every
	// path through it.
	float shadowVisibility;

	// The colour the direct light arrives in, which is white until stained glass
	// colours it - see COLORED_SHADOWS in /environment/materialIDs.glsl. Written
	// by DirectLighting on every path through it as well.
	vec3 shadowTint = vec3(1.0);

	// If the direct light strength is nonzero, add in direct lighting
	// based on sampling the shadow map.
	#if !defined(NEVER_RECEIVES_SHADOWS)
		float directLightStrength = DirectLighting(
			fragment,
			subsurfaceScatter,
			pbr,
			viewDirection,
			specular,
			shadowVisibility,
			shadowTint);
	#else
		// Without shadow mapping there is no light visibility term to build a
		// highlight on top of, so PBR materials simply do not get one.
		specular = vec3(0.0);
		shadowVisibility = 1.0;
		float directLightStrength = 1.0;
	#endif

	// The tint belongs to the direct light and to nothing else: it is sunlight
	// that came through a window, where the ambient light around the fragment
	// did not. It is applied to the highlight along with the diffuse light,
	// because a highlight is the same light seen from a different angle.
	lighting += (vec3(directLightStrength) + specular) * directLightColor * shadowTint;

	// And the highlight is kept on its own as well as added to the lighting.
	//
	// Tinted by exactly what the line above tinted it with, so that this is the
	// same quantity the frame received: a highlight seen through stained glass
	// is removed in the colour it was added in, rather than in white.
	specularColor = specular * directLightColor * shadowTint;

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR)
		// Ice is left out while PBR_TRANSLUCENT is on: its reflections are drawn
		// by TranslucentLighting, which has both a direction and a screen-space
		// term, and adding this crude environment term on top of that would
		// count the same light twice. Note that ice reflects nothing underground
		// either way, since the other term fades out with the sky light.
		bool skipAmbientSpecular = false;
		#ifdef PBR_TRANSLUCENT
			skipAmbientSpecular = fragment.materialID == ICE;
		#endif

		if (!skipAmbientSpecular) {
			// The environment reflection, so that a material responds to the
			// light around it and not only to the sun and moon.
			//
			// Held in a variable of its own rather than added straight into the
			// lighting, because it belongs to the specular total below as well:
			// this is the second of the two terms that make it up.
			vec3 ambientSpecular = PbrAmbientSpecular(
				pbr,
				fragment.worldNormal,
				viewDirection,
				indirectLighting,
				fragment.skyLight);

			lighting += ambientSpecular;
			specularColor += ambientSpecular;
		}
	#endif

	vec3 surfaceColor = fragment.surfaceColor;

	#ifdef NIGHT_DESATURATION_EFFECT
		float desaturation = NightDesaturation(
			fragment.skyLight,
			max(fragment.blockLight, fragment.heldLight)
		);

		surfaceColor = Desaturate(surfaceColor, desaturation);
	#endif

	// The same multiplication by the surface colour that the return below does,
	// and after the night desaturation for the same reason the return is: what
	// is wanted is not something proportional to the highlight but the exact
	// part of the returned colour that the highlight contributed, so that
	// subtracting it leaves what the surface would have looked like without it.
	specularColor *= surfaceColor;

	// Emission is deliberately not added here: it is added by the caller, so
	// that everything that glows goes through one place. See lit.fsh.
	return surfaceColor * lighting;
}

// Lighting for everything that has no PBR material data: entities, held items,
// Distant Horizons terrain, Voxy terrain, and every program at all when PBR is
// turned off.
vec3 DiffuseLighting(SurfaceFragment fragment) {
	// There is no material here, so nothing this call shades reflects anything
	// and the specular total can only come out zero. The parameter exists so
	// that there is one implementation rather than two.
	vec3 specularColor;
	return DiffuseLightingImpl(fragment, PbrNone(), vec3(0.0), specularColor);
}

#ifdef PBR_SURFACE
	vec3 DiffuseLighting(
		SurfaceFragment fragment,
		PbrSurface pbr,
		vec3 viewDirection,
		out vec3 specularColor
	) {
		return DiffuseLightingImpl(fragment, pbr, viewDirection, specularColor);
	}
#endif
