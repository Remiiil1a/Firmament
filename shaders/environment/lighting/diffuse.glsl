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

// How bright block light is at full block light level.
//
// This number is the pack's own rather than something read from the lightmap:
// the lightmap supplies the color, but the brightnesses it carries have its own
// falloff baked into them, and this model replaces that with its own falloff
// and this.
#define BLOCKLIGHT_STRENGTH 4.0 // [1.0 2.0 3.0 4.0 5.0 6.0 8.0]

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
vec3 BlockLightTint(vec2 lightMapCoord) {
	#if defined(BLOCKLIGHT_HAS_LIGHTMAP)
		vec3 tint = texture(lightmap, vec2(lightMapCoord.x, 1.0 / 32.0)).rgb;

		// A lightmap that cannot be read comes back black, which would put every
		// light in the world out. Neutral is the safe answer.
		if (dot(tint, tint) < 0.0001) {
			return vec3(1.0);
		}

		// Only the hue: scaled so that its brightest channel is one.
		return tint / max(max(tint.r, tint.g), tint.b);
	#else
		// A program whose uniforms come from elsewhere does not get the
		// lightmap. That is Voxy's terrain, which keeps a neutral color.
		return vec3(1.0);
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
	#define MIN_AMBIENT_BRIGHTNESS 0.2 // [0.0 0.01 0.03 0.05 0.1 0.2 0.35 0.6]

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
	out float shadowVisibility
) {
	// Note: these are set before any of the early outs below, so that callers
	// never read an undefined value.
	specular = vec3(0.0);
	shadowVisibility = 0.0;

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
			shadowVisibility);
	#else
		directLightStrength *= shadowSample;
		shadowVisibility = shadowSample;
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
	vec3 viewDirection
) {
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
	// there and its islands would otherwise be lit by the ambient floor alone.
	lighting += EndAmbientLighting(ambientStrength, fragment.worldNormal);

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

	// The specular reflection of the direct lighting, which is zero for every
	// material that does not reflect anything.
	vec3 specular;

	// How much of the direct light survives the shadows. Only the subsurface
	// scattering term reads it, and it is written by DirectLighting on every
	// path through it.
	float shadowVisibility;

	// If the direct light strength is nonzero, add in direct lighting
	// based on sampling the shadow map.
	#if !defined(NEVER_RECEIVES_SHADOWS)
		float directLightStrength = DirectLighting(
			fragment,
			subsurfaceScatter,
			pbr,
			viewDirection,
			specular,
			shadowVisibility);
	#else
		// Without shadow mapping there is no light visibility term to build a
		// highlight on top of, so PBR materials simply do not get one.
		specular = vec3(0.0);
		shadowVisibility = 1.0;
		float directLightStrength = 1.0;
	#endif

	lighting += (vec3(directLightStrength) + specular) * directLightColor;

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
			lighting += PbrAmbientSpecular(
				pbr,
				fragment.worldNormal,
				viewDirection,
				indirectLighting,
				fragment.skyLight);
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

	// Emission is deliberately not added here: it is added by the caller, so
	// that everything that glows goes through one place. See lit.fsh.
	return surfaceColor * lighting;
}

// Lighting for everything that has no PBR material data: entities, held items,
// Distant Horizons terrain, Voxy terrain, and every program at all when PBR is
// turned off.
vec3 DiffuseLighting(SurfaceFragment fragment) {
	return DiffuseLightingImpl(fragment, PbrNone(), vec3(0.0));
}

#ifdef PBR_SURFACE
	vec3 DiffuseLighting(
		SurfaceFragment fragment,
		PbrSurface pbr,
		vec3 viewDirection
	) {
		return DiffuseLightingImpl(fragment, pbr, viewDirection);
	}
#endif
