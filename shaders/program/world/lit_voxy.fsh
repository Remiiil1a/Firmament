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

// With Voxy, we can assume that textureGather is available, as the shader we
// are patched into requires GLSL version 460 (OpenGL 4.6), but textureGather is
// core (not an extension) in OpenGL 4.0. This is nice, because we otherwise
// can't actually explicitly enable an extension in Voxy because it requires
// an #extension directive in the middle of the shader.
#define MC_GL_ARB_texture_gather

// Voxy hands this program only the uniforms that voxy.json lists in its
// "uniforms" array, and it hands over every one of them by name - so a uniform
// this file's includes declare but that the array does not name is not an error.
// It is declared, it compiles, and it reads zero for the whole frame.
//
// That is worth knowing before adding anything to the chain below: a missing
// name looks exactly like a feature that does not work, and only on Voxy's
// terrain. rainStrength was missing that way, which left the sun, the moon and
// the stars in the water's reflection at full strength through a thunderstorm -
// while the same water drawn by the game itself faded them out correctly, since
// an ordinary program is given every uniform it declares.
//
// So: when this chain starts reading a new uniform, add it to that array in the
// same change. See PBR_PORTING.md 124.
#define EXTERNALLY_DEFINED_UNIFORMS
#define NO_HELD_BLOCK_LIGHTING

// The lightmap, which this program gets through voxy.json rather than from the
// uniforms this pack declares for itself - see the note where the lightmap is
// declared in environment/lighting/diffuse.glsl, and "lightmap" in the samplers
// map of voxy.json. It is what lets level-of-detail terrain be lit in the same
// color as the blocks beside it, which is the whole of why it is asked for.
#define VOXY_LIGHTMAP

// Water absorption configuration, has wide-reaching impacts across the codebase
// Uniforms: none
#include "/environment/water/absorption_settings.glsl"

// Water absorption, if being done with the refraction-assisted method.
// Uniforms: none
#include "/environment/water/absorption.glsl"

// Whether to freeze animations (useful for testing).
//#define FREEZE_ANIMATION_TIMER
#ifdef FREEZE_ANIMATION_TIMER
	float timeSeconds = 500.0;
#else
	float timeSeconds = frameTimeCounter;
#endif

#include "/environment/materialIDs.glsl"

#include "/environment/lighting/diffuse.glsl"

layout(location = 0) out vec4 out0;
layout(location = 1) out float out1;

#if defined(TRANSLUCENT)
	#define opaqueDepth vxDepthTexOpaque
	#define projectionMatrix vxProj
	#define inverseProjectionMatrix vxProjInv

	// Sky reflection
	#include "/environment/fog.glsl"
	#include "/environment/sky.glsl"

	// The TBN reconstruction below is the same one the per-face encoding
	// decodes from, so that a water face drawn here and the same face drawn by
	// the terrain programs get the same frame.
	#include "/lib/encoding/face.glsl"

	#include "/environment/lighting/translucent.glsl"
#elif defined(FANCY_TRANSLUCENTS)
	layout(location = 2) out vec4 out2;
#endif

// sRGB to Linear RGB
// Uniforms: none
#include "/lib/srgb.glsl"

#include "/lib/encoding/lightmap.glsl"

void voxy_emitFragment(VoxyFragmentParameters parameters) {
	vec3 worldNormal = (float(int(parameters.face) & 1) * 2.0 - 1.0) * vec3(
		uint((parameters.face >> 1) == 2),
		uint((parameters.face >> 1) == 0),
		uint((parameters.face >> 1) == 1)
	);

	vec4 surfaceColor =
		SrgbToLinear(parameters.sampledColour * parameters.tinting);
	uint materialID = DecodeMaterialID(parameters.customId);

	// Geometry selectors are not applicable on Voxy terrain right now, as the
	// only selector is for diagonal geometry, which is not possible in Voxy.
	if (materialID > 0xFu) {
		materialID = 0u;
	}

	float skyLight = LightMapToLight(parameters.lightMap.y);

	vec4 fragmentColor = vec4(DiffuseLighting(SurfaceFragment(
		// The linear RGB color of the surface at this position, including all
		// AO and tinting.
		surfaceColor.rgb,
		// The predefined material ID of this fragment.
		materialID,
		// The normal vector of the surface where this fragment is, in
		// world-space.
		worldNormal,
		// Where this fragment sits in the lightmap, which is where the color of
		// its block light comes from.
		parameters.lightMap,
		// The sky light strength, where 1 is light level 15 and 0 is no light.
		skyLight,
		// The block light strength, where 1 is light level 15 and 0 is no
		// light.
		LightMapToLight(parameters.lightMap.x),
		// The held light strength, where 1 is light level 15 and 0 is no light.
		0.0
	)), surfaceColor.a);


	#if defined(TRANSLUCENT)
		vec3 ndcPos = gl_FragCoord.xyz * vec3(windowToNdc, 2.0) - 1.0;
		vec4 viewPosH = inverseProjectionMatrix * vec4(ndcPos, 1.0);
		vec3 viewPos = viewPosH.xyz / viewPosH.w;
		vec3 cameraRelativePos =
			(gbufferModelViewInverse * vec4(viewPos, 1.0)).xyz;

		if (materialID == WATER) {
			fragmentColor = vec4(0.0);
		}

		float reflectionStrength = materialID == WATER ? 1.0 : 0.0;

		// Voxy's vertices are not put through this pack's vertex shaders, so
		// there is no per-face encoding to read a frame out of. The faces it
		// does emit are all lined up with the world's axes, so a frame derived
		// from the face normal is as good as the geometry's own would be - and
		// it is derived the same way the vertex stage falls back for geometry
		// that carries no tangent (see lit.vsh), which keeps the two paths
		// agreeing on the same face.
		mat2x3 voxyBasis = OrthonormalBasisOf(
			worldNormal, worldNormal.z >= 0.0 ? 1.0 : -1.0);
		mat3 voxyTBN = mat3(voxyBasis[0], voxyBasis[1], worldNormal);

		// Voxy terrain has no material data of its own, so it passes the neutral
		// material and the face normal, which leaves water and ice here exactly
		// as they were.
		fragmentColor = TranslucentLighting(
			fragmentColor,
			worldNormal,
			voxyTBN,
			cameraRelativePos,
			viewPos,
			reflectionStrength,
			skyLight,
			materialID,
			PbrNone(),
			worldNormal
		);
	#endif

	out0 = fragmentColor;
	out1 = skyLight;

	#if defined(FANCY_TRANSLUCENTS) && !defined(TRANSLUCENT)
		out2 = fragmentColor;
	#endif
}