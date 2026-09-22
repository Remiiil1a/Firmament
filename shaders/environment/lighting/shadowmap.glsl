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

#ifdef MC_GL_ARB_texture_gather
	// If textureGather is available, use that to fade away caustics, otherwise
	// we will fall back to texelFetch.
	#define CAUSTICS_FADE_METHOD_GATHER
#endif

// Just for shadow mapping constants
// Uniforms: none
#include "/lib/distort.glsl"

// Enable PCF (shadowHardwareFiltering) on both shadowmaps
const bool shadowHardwareFiltering0 = true;
const bool shadowHardwareFiltering1 = true;

// Whether to enable fancy translucent effects. When disabled, translucents are
// rendered with the same shading as solids.
#define FANCY_TRANSLUCENTS 
#ifdef FANCY_TRANSLUCENTS
	uniform sampler2DShadow shadowtex1;
	#define shadowSampler shadowtex1

	// Whether underwater terrain will have an antimated water caustics overlay.
	#define WATER_CAUSTICS
#else
	uniform sampler2DShadow shadowtex0;
	#define shadowSampler shadowtex0
#endif

#if defined(WATER_CAUSTICS)
	uniform sampler2D shadowcolor0;
	uniform float causticsFade;
	#define shadowWaterSampler shadowcolor0
#endif

#ifdef COLORED_SHADOWS
	// The colour of the light that has come through stained glass, written by the
	// shadow program at the same texel and the same depth as the shadow itself.
	//
	// A buffer of its own, so that nothing here has to know that the water heights
	// the caustics read live in shadowcolor0 and this does not. Read only where
	// the shadow map itself is read - see ShadowMapping - so that a fragment
	// outside the shadow distance never pays for the sample.
	//
	// See COLORED_SHADOWS in /environment/materialIDs.glsl for what is in it and
	// why a fragment that is not in the way is white.
	uniform sampler2D shadowcolor1;
#endif

// Higher shadow map resolutions give sharper shadows at the expense of
// perfomance.
const int shadowMapResolution = 2048; // [1024 1536 2048 3072 4096]

// Render distance of the shadow map, in blocks. No objects outside of this
// distance cast or receive real-time shadows.
const float shadowDistance = 128; // [32 48 64 80 96 112 128 144 160 192 256]
const float shadowDistanceRenderMul = 1.0;
const float entityShadowDistanceMul = 0.25;

// Samples the shadow map additional times to soften shadows.
#define SOFTER_SHADOWS
#ifdef SOFTER_SHADOWS
	float SampleShadows(vec3 shadowPos, float softnessScale) {
		// Controls softness and pixelation of shadows
		#define SHADOW_SOFTNESS 0.5 // [0.05 0.10 0.25 0.33 0.5 0.66]

		// Not const, unlike the softness above: the scale is a runtime value
		// that depends on the material being shaded.
		float spread = softnessScale * SHADOW_SOFTNESS / shadowMapResolution;

		// Make 4 taps on the shadowmap, where each tap is itself a hardware
		// accelerated 2x2 PCF tap, ending up with sampling up to 16 different
		// texels in the shadowmap. However, at low values of shadow softness,
		// the taps overlap.
		vec3 tap1 = vec3(shadowPos.xy + vec2(spread, spread), shadowPos.z);
		vec3 tap2 = vec3(shadowPos.xy + vec2(-spread, spread), shadowPos.z);
		vec3 tap3 = vec3(shadowPos.xy + vec2(spread, -spread), shadowPos.z);
		vec3 tap4 = vec3(shadowPos.xy + vec2(-spread, -spread), shadowPos.z);

		return 0.25 * texture(shadowSampler, tap1)
		     + 0.25 * texture(shadowSampler, tap2)
		     + 0.25 * texture(shadowSampler, tap3)
		     + 0.25 * texture(shadowSampler, tap4);
	}
#else
	// With the softening above switched off there is a single tap, and nothing
	// for the scale to widen - it is accepted and ignored so that callers do not
	// have to care which of the two sampling methods is in use.
	float SampleShadows(vec3 shadowPos, float softnessScale) {
		return texture(shadowSampler, shadowPos);
	}
#endif

#ifdef WATER_CAUSTICS
	#include "/environment/water/caustics_noise.glsl"

	// Distance in meters to apply parallax mapping to the water surface. 
	#define WATER_CAUSTICS_DISTANCE 48.0 // [8.0 16.0 24.0 32.0 48.0 64.0]
#endif

float SampleWaterCaustics(
	float shadowSample,
	float withinShadowMap,
	vec2 shadowPos,
	vec3 cameraRelativePos
) {
	// This method of water caustics depends on the shadow map for water depth
	// information, which is not available outside of the shadow map render
	// distance.
	//
	// In addition, rendering caustics far away from the player is still costly
	// and unnoticable after a certain distance, so it is a good optimization to
	// give them a render distance limit.
	float causticsStrength = causticsFade * withinShadowMap;
	causticsStrength *= 1.0 - smoothstep(
		WATER_CAUSTICS_DISTANCE,
		WATER_CAUSTICS_DISTANCE + 4.0,
		length(cameraRelativePos));

	if (causticsStrength < 0.0001) {
		return shadowSample;
	}

	#ifdef CAUSTICS_FADE_METHOD_GATHER
		// Water height values are discrete and not meant to be interpolated
		// linearly. This is normally not significant, however, if there is
		// something casting a shadow on the water at a given texel in the
		// shadow map, if we only fetched that texel we would be missing water
		// depth data since the water would not be drawn & write the water depth
		// value.
		//
		// Using textureGather allows us to access the height values of
		// neighboring texels, so we can use a gradual, almost un-noticeable
		// fade-out.
		vec4 encodedWaterHeights = textureGather(shadowWaterSampler, shadowPos);
		float encodedWaterHeight = min(
			min(encodedWaterHeights.x, encodedWaterHeights.y),
			min(encodedWaterHeights.z, encodedWaterHeights.w)
		);
	#else
		// If textureGather is not available, then just use nearest-neighbor
		// sampling, and a less ideal fade-out down below.
		ivec2 texel = ivec2(shadowMapResolution * shadowPos);
		float encodedWaterHeight = texelFetch(shadowWaterSampler, texel, 0).r;
	#endif

	// Decode the water height and calculate the distance between this fragment
	// and the water surface. Note that this will clamp out at +/- 1024 blocks
	// above or below the camera, but because we limit water caustics to much
	// more nearby than that, this is not an issue.
	//
	// See: shadow.fsh for the encoding. TODO: Make this a common function
	float waterYCameraRelative = (1.0 - 2.0 * encodedWaterHeight) * 1024.0;
	float causticsWaterDepth = waterYCameraRelative - cameraRelativePos.y;

	// Smoothly fade out caustics near the water surface (over 1/16th of a
	// block, aka 1 visible block pixel with default textures) to avoid a
	// visible, abrupt transition.
	causticsStrength *= smoothstep(0.0, 1.0 / 16.0, causticsWaterDepth);

	// Smoothly fade out caustics at the edges of shadows. This is necessary
	// because we lose water depth information in shadowed areas, so we need to
	// fade them away in areas where we still do have water depth information.
	causticsStrength *= smoothstep(
		#ifdef CAUSTICS_FADE_METHOD_GATHER
			// If we are using textureGather, we can still calculate the water
			// height even with just one of 4 texels not in shadow (25%), so we
			// can smoothly fade from 25% coverage to 75% coverage.
			0.25,
			0.75,
		#else
			// However, with texelFetch, we can only calculate the water height
			// when the immediate texel is not in shadow, even if its neighbors
			// are in shadow. While the true resulting range SHOULD be 0.75 to
			// 1.0, I brought the lower bound down a bit to make the transition
			// look less abrupt.
			0.675,
			1.0,
		#endif
		shadowSample
	);

	vec3 worldPos = cameraRelativePos + cameraPosition;
	float caustics = WaterCaustics(worldPos, timeSeconds);
	return shadowSample * max(0.0, 1.0 + causticsStrength * caustics);
}

float ShadowMapping(
	uint materialID,
	float shadowSample,
	bool subsurfaceScatter,
	float directLightStrength,
	vec3 shadowPos,
	vec3 cameraRelativePos,
	// How much this surface scatters light through itself, from 0.0 to 1.0.
	// Read from the material's specular map when PBR_SUBSURFACE is on, and 0.0
	// otherwise, which is what keeps the shadow softening below confined to the
	// feature.
	float sssAmount,
	// How much of the direct light survives every shadow source combined, where
	// 1.0 is fully lit. This is the product of the shadow map and the static
	// (light map) shadowing, and it is handed back separately from the direct
	// light strength because the subsurface scattering term needs to know
	// whether light arrives at this fragment, not how much of it there is.
	out float shadowVisibility,
	// The colour the direct light arrives in, which is white unless something
	// coloured stood in its way - see COLORED_SHADOWS in
	// /environment/materialIDs.glsl. Set on every path out of here, including
	// the early one below, so that callers never multiply by an undefined value.
	out vec3 shadowTint
) {
	// White is what "nothing is in the way" is, and it is the answer everywhere
	// except in the one branch further down. Set here rather than there so that
	// the early outs in between cannot leave it unset.
	shadowTint = vec3(1.0);

	// The culling enabled by shadowDistanceRenderMul takes the form of an
	// axis-aligned box centered on the camera. As a result, we evaluate the
	// distance of a fragment as the maximum along any axis to ensure we stay
	// within the bounding box.
	float boxDistance = max(abs(cameraRelativePos.x),
		max(abs(cameraRelativePos.y), abs(cameraRelativePos.z)));

	// Fade in static shadows first (5 - 10 blocks away from the bounds of the
	// shadow distance)...
	float staticShadowStrength = smoothstep(
		shadowDistance - 10.0,
		shadowDistance - 5.0,
		boxDistance);
	shadowSample = 1.0 - staticShadowStrength * (1.0 - shadowSample);

	// Then fade out real-time shadows once static shadows are fully faded in
	// (5 or fewer blocks from the bounds).
	float withinShadowMap = 1.0 - smoothstep(
		shadowDistance - 5.0,
		shadowDistance,
		boxDistance);

	// Only sample the shadow map if we are within the real-time shadowing
	// bounding box.
	if (withinShadowMap < 0.0001) {
		shadowVisibility = shadowSample;
		return directLightStrength * shadowSample;
	}

	// When applying real-time shadowing, if this surface has subsurface
	// scattering enabled, then modify the direct light strength accordingly.
	//
	// We do not use 1.0 here just because that is a bit too bright. This is as
	// if the foliage affected by SSS is facing just a little bit away from the
	// light at all times.
	//
	// More specifically, cos(pi/4) ~= 0.7071, ie, a 45 degree angle with the
	// light.
	if (subsurfaceScatter) {
		directLightStrength = mix(directLightStrength, 0.7071, withinShadowMap);
	}

	// How much wider the shadow filter is spread over this fragment.
	//
	// The shadow of a thin surface is not an edge cast onto a solid object: the
	// light that reaches the viewer through a leaf comes out of the leaf spread
	// over an area, so the leaf's own shadow has a soft rim rather than a hard
	// one. Widening the filter is what produces that rim.
	//
	// Either the block-based flag Steadfast already has or the amount the
	// resource pack stored can trigger this, whichever is larger, so a pack that
	// marks one plant as thin gets the wider shadow on that plant alone.
	//
	// Note the gate: with PBR_SUBSURFACE off this stays 1.0 for every material,
	// which leaves the shadows exactly as they were.
	float shadowSoftnessScale = 1.0;
	#if defined(PBR_SURFACE) && defined(PBR_SUBSURFACE)
		// How much wider the filter is spread for a fully scattering material.
		// The same four taps are used either way, so this costs no extra
		// samples - it only makes them cover more of the shadow map.
		#define PBR_SSS_SHADOW_SOFTNESS 5.0

		float scatter = max(subsurfaceScatter ? 1.0 : 0.0, sssAmount);
		shadowSoftnessScale = mix(1.0, PBR_SSS_SHADOW_SOFTNESS, scatter);
	#endif

	float shadowMapSample = mix(1.0, SampleShadows(shadowPos, shadowSoftnessScale), withinShadowMap);
	shadowSample = min(shadowSample, shadowMapSample);

	#ifdef WATER_CAUSTICS
		// Do not apply caustics to water itself.
		// Note: Caustics can be enabled even if FANCY_TRANSLUCENTS
		// is not, though that is an odd configuration to use.
		if (materialID != WATER) {
			shadowSample = SampleWaterCaustics(
				shadowSample,
				withinShadowMap,
				shadowPos.xy,
				cameraRelativePos);
		}
	#endif

	#ifdef COLORED_SHADOWS
		// Neither stained glass nor a nether portal occludes. Both are drawn in
		// the translucent stage, and the shadow map this samples - shadowtex1, the
		// one without translucents - leaves that stage out, so what either of them
		// leaves on the ground is not a hole in the light but a colour in it.
		//
		// Looked up at the same texel the shadow itself was sampled at, which is
		// the point: the shadow map records the nearest surface along the light
		// ray, and so does this buffer, so a fragment that finds a colour here is
		// one whose light really did come past whatever wrote it. The depth test is
		// what does the work; see the write in /program/shadow/shadow.fsh.
		//
		// Not applied to stained glass itself. A pane is thin, the light landing
		// on the face of one has not been through it yet, and the buffer at a
		// pane's own texel holds the pane's own colour - so tinting it would only
		// ever make a window darker than the light it passes, which is not the
		// effect anyone asked for.
		//
		// Faded out with the shadow map rather than cut off at its edge, so that
		// the tint hands over to the plain static-light shading at the shadow
		// distance instead of ending in a line across the ground.
		if (materialID != STAINED_GLASS) {
			// One texture fetch, on the same fragments that already pay for four
			// shadow taps and only where the shadow map reaches at all. The alpha
			// rides along with it: see the note on tintKind in
			// /program/shadow/shadow.fsh.
			vec4 tintSample = texture(shadowcolor1, shadowPos.xy);
			vec3 tint = tintSample.rgb;

			#if defined(COLORED_SHADOWS_PORTAL)
				// A portal needs an answer of its own, because in the world pass
				// there is nothing left to recognise it by. It is drawn in the
				// translucent pass and arrives here as GLASS - the material this
				// pack gives an unlisted translucent - so the only handle on the
				// portal's own faces is that they are a translucent surface at all,
				// and a portal would otherwise light its own faces with its own
				// glow, which would darken every green in them.
				//
				// So a colour that came from an emitter is faded out on translucent
				// surfaces, and the alpha is what says a colour came from an
				// emitter. Standing inside a portal is the same case seen from the
				// other side, and is answered by the same line.
				//
				// Stained glass is deliberately not treated this way - see the
				// branch above, and note that its colour is written with an alpha of
				// zero, so it passes through here untouched. A pane behind a window
				// really does receive the light that window coloured, and taking
				// that away would be a change to how glass is lit rather than a fix
				// to the portal.
				if (materialID == GLASS) {
					// Filtering across the rim of a portal blends the alpha the way
					// it blends the colour, so the fade there is smooth rather than
					// a choice between two kinds of source on either side of a texel.
					tint = mix(vec3(1.0), tint, 1.0 - tintSample.a);
				}
			#endif

			// White at the edge of the shadow map, the tint itself once inside it.
			shadowTint = mix(vec3(1.0), tint, withinShadowMap);
		}
	#endif

	// Reported after the caustics above, so that a fragment that water caustics
	// brighten is also seen as lit by whatever asks for the visibility.
	shadowVisibility = shadowSample;

	return directLightStrength * shadowSample;
}
