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

// Show the picture this pass was handed on the left of the screen, and the one it
// writes on the right - the same split the temporal resolve has, one pass earlier.
//
// It exists because the resolve's own split answered its question and moved the
// search along: the dark blot that grows over the terrain is present in the frame
// the resolve is handed, which means the geometry or this pass put it there and
// the resolve is only keeping it. Of those two this is the cheap one to rule out.
//
// Left half: colortex0 as the surface programs left it. Right half: what this pass
// writes, after the fog, the reflections and the water absorption.
//
// Which side the blot is on is the reading: the left means the geometry drew it,
// the right means this pass made it. See PBR_PORTING.md 135.
//#define DEFERRED_DEBUG

// We must make a copy of colortex0 for forward-rendered reflections and
// refraction, as we cannot sample a texture we are rendering into.
const int R11F_G11F_B10F = 0;
const int R8 = 0;

// We must write to colortex4, as per OptiFine/Iris specifications, that is the
// first colortex buffer number that gbuffers shaders can sample. colortex0-3
// are not bound in gbuffers shaders.
const int colortex4Format = R11F_G11F_B10F;

// Not cleared between frames, for the one reader that runs before this pass
// writes it: the hand's reflection, in lit.fsh, is taken from this buffer
// during the gbuffers stage - which is a frame earlier than everything else
// that reads it. What it finds there is the last finished frame, which is what
// Mellow Shader's reflection for a held item reads as well (see gaux1Clear in
// its global/configurations.glsl), and it is the only picture of the world that
// exists at that point in the frame.
//
// Everything that reads this buffer later in the frame is unaffected: the pass
// below writes all of it, every frame, so what they see is the current frame's
// copy whether or not the loader wiped it first.
const bool colortex4Clear = false;
const int colortex2Format = R8;
const int colortex5Format = R8;

// Water absorption configuration, has wide-reaching impacts across the
// codebase.
#include "/environment/water/absorption_settings.glsl"

// vec4 Fog(...)
#include "/environment/fog.glsl"

// vec3 SkyColor(vec3 ray, float dither)
#include "/environment/sky.glsl"

// The material model, for the Fresnel term and the option switches its
// environment reflection is built on. Nothing here is read from a resource pack:
// this pass has no material textures bound and no need for them.
#include "/environment/lighting/pbr.glsl"

// PbrReflectionDirection, PbrReflectionFresnel, PbrReflectionPossible
#include "/environment/lighting/reflections.glsl"

// The trace's step budget, which is an option rather than the water reflections'
// constant: this trace runs on every smooth pixel of the screen, and spending
// the same number of steps on all of them as on a surface of water is a
// different proposition. Has to be set before the include below, which only
// falls back to its own default if nobody has chosen one.
#define RAYMARCH_STEPS PBR_SSR_STEPS

// Raytrace(...), for the screen-space reflection
#include "/lib/raytrace.glsl"

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform vec2 windowToNdc;

// Where the camera is in the world. The cloud layer is a place rather than a
// direction - it sits at a height, and the camera has to be located against it -
// and this is the pass that draws it.
uniform vec3 cameraPosition;

// The direction of the light that casts shadows, straight from the shader mod
// and already in view space. A sky pixel has no surface program behind it to
// have read this, so it is read here, and the cloud layer turns it into world
// axes itself - for the reason given in /environment/clouds/volumetric.glsl.
uniform vec3 shadowLightPosition;

// BlockyClouds(...), the pack's own cloud layer. See that file for what it is,
// why it is drawn here rather than with the sky, and what it costs.
//
// Included here rather than with the includes above, because the layer reads the
// camera's position, the camera's matrix and the light direction, and those are
// declared in between: a shader has to see a uniform's declaration before the
// code that uses it, even when the two end up in the same file once the includes
// are done.
#include "/environment/clouds/volumetric.glsl"

uniform sampler2D colortex2;
uniform sampler2D colortex0;
uniform sampler2D depthtex1;

// The depth of the surface each pixel actually shows, which is depthtex1
// wherever nothing translucent is in front and the translucent's own depth
// where something is. The screen-space shadows below shadow the surface this
// names, while sampling their occluders from depthtex1 - so this is the one
// that has to be the surface, not the opaque pass.
uniform sampler2D depthtex0;

// How far the shadow map reaches: the point past which the screen-space shadows
// below take over. Derived in shaders.properties from the Shadow Distance
// setting, because this pass does not get that setting's own uniform - it reads
// as zero here.
uniform float sssShadowDistance;

// The far plane, in blocks - which is the vanilla render distance: Minecraft
// sets it from the View Distance setting.
//
// It is the other half of where the handover belongs. The shadow map can only
// contain terrain that was actually rendered into it, and that is the vanilla
// chunks the game loaded, so the map reaches
//
//     min(Shadow Distance, view distance in blocks)
//
// rather than the Shadow Distance setting on its own. With the setting at 160
// and the view distance at 8 chunks, the map ends at 128, and the terrain from
// 128 to 160 - LOD terrain, since that is past the vanilla render distance -
// would be left with neither the shadow map nor the screen-space shadows: a
// ring of ground in full sun with a hill standing between it and the sun.
//
// The pack already treats `far` as this edge: it is what the stipple in
// /program/world/lit.fsh fades distant terrain against, for the same reason.
uniform float far;

// ScreenSpaceShadow(...), for terrain the shadow map does not reach.
//
// Included here, below the uniforms it uses, for the same reason the cloud layer
// below is: a shader has to see a uniform's declaration before the code that
// uses it.
#include "/lib/sss.glsl"

// AmbientOcclusion(...), for the light the sky cannot reach, and SssScreenNoise,
// which is the dither it samples with. See the note in that file on why it
// belongs in this pass rather than after the temporal resolve.
#include "/environment/lighting/ssao.glsl"

// The previous frame, resolved. The screen-space reflection traces against the
// depth buffer below and reads the colour it finds here: this frame's own
// colortex0 is being written by this very pass, so it cannot be sampled at
// arbitrary points, and the deferred copy of it is not written yet either.
uniform sampler2D colortex3;

// The material the surface programs wrote: the normal to reflect around and the
// roughness in one, the reflectance in the other. See lit.fsh.
uniform sampler2D colortex7;
uniform sampler2D colortex8;

#ifdef DISTANT_HORIZONS
	uniform mat4 dhProjectionInverse;
	uniform sampler2D dhDepthTex0;
#endif

// The view-space position of the fragment at the given depth.
//
// Note: w must be 1.0 in these homogenous coordinates, as 1.0 means a point in
// space rather than a vector.
vec3 ViewPosFromDepth(mat4 inverseProjection, float depth) {
	vec3 ndcPos = vec3(gl_FragCoord.xy * windowToNdc, depth * 2.0) - 1.0;
	vec4 viewPosH = inverseProjection * vec4(ndcPos, 1.0);

	return viewPosH.xyz / viewPosH.w;
}

vec3 ApplyFog(
	mat4 inverseProjection,
	vec3 fragCoord,
	vec3 background,
	float skyLight
) {
	// Project back to view space from the fragment coordinates
	vec3 viewPos = ViewPosFromDepth(inverseProjection, fragCoord.z);

	// Into world axes through the matrix the geometry was drawn with, for the
	// reason given where the cloud layer's ray is turned the same way, below.
	mat3 viewRotation = mat3(gbufferModelView);
	vec3 cameraRelativePos = vec3(
		dot(viewPos, viewRotation * vec3(1.0, 0.0, 0.0)),
		dot(viewPos, viewRotation * vec3(0.0, 1.0, 0.0)),
		dot(viewPos, viewRotation * vec3(0.0, 0.0, 1.0)));

	vec3 worldSpaceVector = normalize(cameraRelativePos);
	vec3 sky = SkyDither(fragCoord.xy, SkyColor(worldSpaceVector));

	// Compute the fog against the sky background
	float fragDistance = max(
		abs(cameraRelativePos.y),
		length(cameraRelativePos.xz)
	);
	vec4 fog = Fog(sky, fragDistance, fragDistance, skyLight);

	return background * fog.a + fog.rgb;
}


void main() {
	// texelFetch & gl_FragCoord used like this are a perfect way to copy a
	// texture.
	//
	// ivec2 cast functionality per the GLSL specification:
	//
	// > When constructors are used to convert a floating-point type to an
	// > integer type, the fractional part of the floating-point value is
	// > dropped.
	//
	// gl_FragCoord per the GLSL reference:
	// https://registry.khronos.org/OpenGL-Refpages/gl4/html/gl_FragCoord.xhtml
	//
	// > By default, gl_FragCoord assumes a lower-left origin for window
	// > coordinates and assumes pixel centers are located at half-pixel
	// > centers. For example, the (0.5, 0.5) location is returned for the
	// > lower-left-most pixel in the window.
	vec3 background = texelFetch(colortex0, ivec2(gl_FragCoord), 0).rgb;

	#ifdef AMBIENT_OCCLUSION
		// Ambient occlusion, applied before the fog below so that the fog is not
		// darkened by the ground it happens to sit behind. See
		// environment/lighting/ssao.glsl for what it is and why it is here, in
		// the pass before composite1 resolves the frame over time - that resolve
		// is what turns these samples into a smooth result.
		//
		// depthtex1 rather than depthtex0, for the reason the reflection uses it
		// as well: the occlusion is asked about opaque geometry, and at a pixel
		// where water or glass is in front, depthtex0 holds that surface while
		// depthtex1 holds the block behind it - and the block behind it is not
		// what this pixel's brightness is about.
		float aoDepth = texelFetch(depthtex1, ivec2(gl_FragCoord), 0).r;
		float aoFrontDepth = texelFetch(depthtex0, ivec2(gl_FragCoord), 0).r;

		// Two things have to be true before this pixel can be shaded by it. There
		// has to be an opaque surface here at all, and it has to be the surface
		// this pixel shows rather than one behind something translucent.
		bool aoHasSurface = aoDepth < 1.0 && abs(aoDepth - aoFrontDepth) < 1.0e-6;

		// And there has to be a normal to place the samples around. Only the
		// surface programs write one: Voxy draws its own terrain and writes no
		// material buffer at all, so its pixels still hold whatever the last
		// surface program to reach them left behind - and occlusion measured
		// around that would be noise rather than shading. Skipping them says so
		// plainly: there is no ambient occlusion on Voxy's terrain yet. See
		// PBR_PORTING.md 128 for what giving it one would take.
		vec4 aoMaterial = texelFetch(colortex7, ivec2(gl_FragCoord), 0);
		bool aoHasNormal = dot(aoMaterial.xyz, aoMaterial.xyz) > 0.5;

		if (aoHasSurface && aoHasNormal) {
			float ao = AmbientOcclusion(
				depthtex1,
				gbufferProjection,
				gbufferProjectionInverse,
				ViewPosFromDepth(gbufferProjectionInverse, aoDepth),
				aoMaterial.xyz,
				// The dither of lib/sss.glsl, borrowed rather than written again:
				// it is a per-pixel pattern that also moves every frame, which is
				// what leaves the temporal filter something it can average away.
				// A pattern fixed to the pixel would be the same value in the
				// history as in the current frame, and averaging it with itself
				// keeps it in the picture forever.
				SssScreenNoise(gl_FragCoord.xy));

			// Checked at the point of use as well as inside: this factor is
			// multiplied into the frame, and the resolve that follows writes its
			// own result back for the next frame to read - so a factor that is not
			// a number does not fade, it spreads. See PBR_PORTING.md 130.
			//
			// One bound rather than a test for each, for the reason the same guard
			// inside ssao.glsl gives: a NaN fails every comparison, so "is it
			// outside the range I want" is true of it, and "is it inside" is not.
			if (!(ao >= 0.0 && ao <= 1.0)) {
				ao = 1.0;
			}

			#ifdef AO_DEBUG
				background = vec3(ao);
			#else
				// Bounded on both sides, for the reason the same line is capped in
				// the screen-space shadows above: a factor below zero is drawn as
				// black, and this pass writes the buffer the temporal history is
				// built from, so such a pixel would stay. The option's own list no
				// longer goes above 1.0, which is what makes this unreachable in
				// practice - and this is what makes it unreachable if the list
				// changes again. See PBR_PORTING.md 136.
				background *= clamp(mix(1.0, ao, AO_STRENGTH), 0.0, 1.0);
			#endif
		}
	#endif

	#ifdef SCREENSPACE_SHADOWS
		// Shadows for terrain past the shadow map's reach, cast by whatever the
		// depth buffer says is in the way. See lib/sss.glsl.
		//
		// It is faded in over the shadow distance rather than applied everywhere:
		// inside that distance the shadow map has already done this, more
		// accurately, and doing it twice would darken the same shadow twice.
		// The surface this pixel shows, taken from the depth buffer that has the
		// translucent pass in it rather than from the opaque one.
		//
		// The two are identical wherever nothing translucent is in front, which
		// is every pixel of land, so this changes nothing about how terrain is
		// shadowed. They differ wherever a water or ice surface is the thing
		// being looked at, and there the opaque depth is not this pixel's
		// surface at all - it is whatever stands behind the water. Shadowing
		// from that position meant a distant water surface was darkened by the
		// screen-space shadow of its own bottom, which only happens past the
		// shadow map's reach and so read as water on LOD terrain being darker
		// than the same water nearby.
		//
		// The marching below still reads depthtex1 for what is in the way: a
		// shadow on a water surface is cast by the opaque world, and the water
		// itself is not part of it.
		float sssDepth = texelFetch(depthtex0, ivec2(gl_FragCoord), 0).r;

		if (sssDepth < 1.0) {
			vec3 sssNdcPos = vec3(
				gl_FragCoord.xy * windowToNdc - 1.0, sssDepth * 2.0 - 1.0);
			vec4 sssViewH = gbufferProjectionInverse * vec4(sssNdcPos, 1.0);
			vec3 sssViewPos = sssViewH.xyz / sssViewH.w;
			float sssDistance = length(sssViewPos);

			// Where the shadow map stops and this takes over: the smaller of what
			// the map is set to reach and how far the terrain it could contain
			// actually goes. See the notes on the two uniforms above.
			//
			// The floor keeps the fade window from collapsing to nothing when
			// either of them is small - a window a few blocks wide would read as a
			// line rather than as a transition - and it also covers the shadow
			// distance reading as zero, which is what the post passes get for it.
			float sssReach = max(min(sssShadowDistance, far), 32.0);

			// Whether the surface this pixel is looking at is translucent - water,
			// ice, glass, and the water drawn on LOD terrain.
			//
			// The two depth buffers answer that between them: only one of them has
			// the translucent pass in it, so they differ exactly where something
			// translucent is in front. That is the whole of the test.
			//
			// Such a pixel is left out of the screen-space shadows. What is seen of
			// water is the sky and the world reflected in it plus the light that
			// came through it, and none of those is something a shadow should be
			// multiplying. It matters most at a distance, where a water surface is
			// seen at a grazing angle and the ray finds occluders far more often:
			// that is why water on LOD terrain came out darker than the same water
			// in the near world, and why this is where that difference is settled.
			float sssSurfaceDepth = texelFetch(depthtex0, ivec2(gl_FragCoord), 0).r;
			float sssOpaqueDepth = texelFetch(depthtex1, ivec2(gl_FragCoord), 0).r;
			bool sssTranslucent = sssSurfaceDepth + 1.0e-6 < sssOpaqueDepth;

			// Painted magenta wherever the test above says "translucent", so that
			// it can be checked against what is on screen - in both the near world
			// and on LOD terrain - rather than being trusted.
			//
			// Hung on the depth debug view rather than on DEBUG as a whole: DEBUG
			// is an enum whose name is defined whatever it is set to, so an
			// #ifdef on it is true in every mode and would paint over the image
			// permanently. See the values in lang/zh_CN.lang.
			//
			// The guard around the test is not decoration. DEBUG and DEBUG_DEPTH
			// are declared in postprocessing.fsh, which is a different program,
			// and an option is a macro - so this pass cannot see either of them,
			// and a test on two names the preprocessor has never heard of is a
			// test of 0 against 0. Written plainly, this painted every translucent
			// surface in the frame half magenta in every mode. Written with the
			// guard, the marking appears in the depth debug view and nowhere else,
			// which is what it was for.
			#if defined(DEBUG) && DEBUG == DEBUG_DEPTH
				if (sssTranslucent) {
					background = mix(background, vec3(1.0, 0.0, 1.0), 0.5);
				}
			#endif

			// Faded out while the light is low, and that is the whole of it.
			//
			// The light here is whichever of the sun and the moon is higher, so
			// its height is at its *smallest* at exactly the moment the two
			// change places: the sun has come down to meet the rising moon, they
			// are level, and from there they trade. Fading out below a threshold
			// on that height therefore covers the changeover without having to
			// know when it happens, or which of the two is which.
			//
			// It covers the other thing a low light is bad for at the same time:
			// a ray that runs almost parallel to the ground, where the samples
			// are furthest apart and the shadow comes out as stripes.
			//
			// The band is two degrees wide and sits on the horizon, so it runs from
			// 0 to 1 degree of the light's height - 0 to 0.01745 as a direction's
			// y, which is the sine of one degree. At or below the horizon the
			// effect is off entirely, above the band it is at full strength, and it
			// crosses over in between.
			//
			// The horizon, because that is where the two bodies meet: one is coming
			// up as the other goes down, so they are level at the crossing point.
			// One number, and one place.
			//
			// Measured in world axes rather than view ones: in view space the
			// light's height would change as the player looks up and down, which
			// has nothing to do with where the sun is. shadowLightPosition is a
			// view-space direction, and the transpose of the view matrix is its
			// inverse for a rotation.
			vec3 sssLightWorld = transpose(mat3(gbufferModelView))
				* normalize(shadowLightPosition);

			float sssSunFade = smoothstep(0.0, 0.01745, abs(sssLightWorld.y));

			float sssWeight = SSS_STRENGTH * sssSunFade * smoothstep(
				sssReach * 0.85, sssReach * 1.15, sssDistance);

			if (sssWeight > 0.0 && !sssTranslucent) {
				float lit = ScreenSpaceShadow(
					depthtex1,
					gbufferProjection,
					gbufferProjectionInverse,
					sssViewPos,
					// Whichever body is lighting the world, which is what this
					// whole effect has to follow to work at night as well as by
					// day. It reverses when the two change places, and the fade
					// below is what covers that moment.
					normalize(shadowLightPosition));

				// The weight is capped, and that cap is the difference between a
				// dark shadow and a black hole in the picture.
				//
				// ScreenSpaceShadow returns exactly zero for a ray that is more
				// than half blocked, which is the ordinary result out here rather
				// than a rare one - this effect only runs past the shadow map's
				// reach, on terrain several dozen blocks away. Without a cap the
				// whole colour of the pixel is multiplied by zero and drawn flat
				// black, with no texture and no noise left in it. See
				// PBR_PORTING.md 136.
				//
				// Capping the weight rather than the result leaves every pixel
				// that is not shadowed exactly as it was: mix(1.0, 1.0, anything)
				// is still 1.0.
				//
				// The cap was a fixed 0.9 and is now SSS_DARK_LIMIT, which
				// defaults lower, because 0.9 was not low enough for what it caps.
				// Note what this multiplies: not the sunlight, but the whole colour
				// of the pixel - the direct light, the sky light and the ambient
				// together, because the forward rendering has already added them
				// into one number by the time this pass runs. At a quarter of its
				// colour a dim surface is not in shadow, it is gone, and a region
				// of it was reported still to grow. The option's own note has the
				// rest; see PBR_PORTING.md 154.
				background *= mix(1.0, lit, min(sssWeight, SSS_DARK_LIMIT));
			}
		}
	#endif

	// colortex4 is a copy of the image for reflection and refraction, and does
	// not apply fog.
	//
	// The environment reflection is deliberately not part of it: this is the
	// buffer the water reflections read, and a surface reflecting a world that
	// already has reflections baked into it would be feeding itself.
	gl_FragData[0] = vec4(background, 1.0);

	float skylight = texelFetch(colortex2, ivec2(gl_FragCoord), 0).r;
	float depth = texelFetch(depthtex1, ivec2(gl_FragCoord), 0).r;

	vec3 scene = background;

	#if defined(VOLUMETRIC_CLOUDS) && defined(CLOUD_MARCH_AVAILABLE)
		// The cloud layer belongs to the sky and to nothing else, and a pixel the
		// depth buffer says has nothing in front of it is exactly a sky pixel.
		//
		// This is the only place it can be drawn: it needs a direction and a
		// camera position rather than a surface, and it needs the depth buffer to
		// be finished, so that it can both be occluded by the terrain and shadow
		// the terrain - the surface programs do the second half of that from
		// BlockyCloudTransmittance.
		bool skyPixel = depth >= 1.0;

		#ifdef DISTANT_HORIZONS
			// Distant terrain is drawn into this buffer but writes its depth to a
			// texture of its own, so the test above does not see it: without this
			// the layer would be drawn over terrain that is in front of it.
			float dhDepth = texelFetch(dhDepthTex0, ivec2(gl_FragCoord), 0).r;
			skyPixel = skyPixel && dhDepth >= 1.0;
		#endif

		// The ray, turned from view space into world axes the same way the
		// surface programs turn their positions: by dotting it against the
		// world's axes taken from the matrix the geometry was drawn with,
		// rather than through that matrix's inverse. The two agree except for
		// the inverse's own error while the view is bobbing, and that error is
		// enough to make a cloud layer visibly shift - subtly in the sky, and
		// plainly in the hard-edged shadow it casts on the ground.
		vec3 cloudViewRay = normalize(
			ViewPosFromDepth(gbufferProjectionInverse, 1.0));
		mat3 viewRotation = mat3(gbufferModelView);
		vec3 cloudRay = vec3(
			dot(cloudViewRay, viewRotation * vec3(1.0, 0.0, 0.0)),
			dot(cloudViewRay, viewRotation * vec3(0.0, 1.0, 0.0)),
			dot(cloudViewRay, viewRotation * vec3(0.0, 0.0, 1.0)));

		// Whether the layer is in front of whatever this pixel holds, which is
		// not the same question as whether this pixel is sky.
		//
		// Flown above the clouds, every pixel the layer covers has terrain behind
		// it and there is no sky left to draw the layer on, which is why the
		// clouds used to disappear up there. The layer is measured against the
		// scene instead: how far along this ray it sits, against how far away the
		// scene at this pixel is. Both directions are the same expression - a ray
		// going up and a ray going down reach the layer at a positive distance,
		// because the sign of the height difference and the sign of the ray's
		// vertical component are the same.
		bool cloudInFront = skyPixel;

		if (!cloudInFront && abs(cloudRay.y) > 1.0e-4) {
			float layerDistance =
				(CLOUD_LAYER_BOTTOM - cameraPosition.y) / cloudRay.y;
			float sceneDistance = length(
				ViewPosFromDepth(gbufferProjectionInverse, depth));

			cloudInFront = layerDistance > 0.0
				&& layerDistance < sceneDistance;
		}

		if (cloudInFront) {
			vec4 cloud = BlockyClouds(cloudRay, cameraPosition, shadowLightPosition);
			scene = mix(scene, cloud.rgb, cloud.a);
		}
	#endif

	#ifdef DEFERRED_DEBUG
		// Left half, what the surface programs left in colortex0; right half, what
		// this pass is about to write. One look says whether the dark blot that
		// grows over the terrain comes from the geometry or from here - see the
		// note on DEFERRED_DEBUG at the top of this file, and PBR_PORTING.md 135.
		//
		// windowToNdc rather than windowToScreen: this pass declares the first and
		// not the second, and a coordinate multiplied by it is 1.0 at the middle of
		// the screen rather than 0.5.
		scene = gl_FragCoord.x * windowToNdc.x < 1.0 ? background : scene;
	#endif

#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED || defined(VOXY)
	if (depth < 1.0) {
		vec3 viewPos = ViewPosFromDepth(gbufferProjectionInverse, depth);

		// The reflection goes on before the fog, so that a reflection far away
		// fades into the distance exactly as the surface it is on does.

		scene = ApplyFog(
			gbufferProjectionInverse,
			vec3(gl_FragCoord.xy, depth),
			scene,
			skylight
		);
	} else {
		#ifdef DISTANT_HORIZONS
			depth = texelFetch(dhDepthTex0, ivec2(gl_FragCoord), 0).r;
			if (depth < 1.0) {
				scene = ApplyFog(
					dhProjectionInverse,
					vec3(gl_FragCoord.xy, depth),
					scene,
					skylight
				);
			}
		#endif
	}

	// colortex0 from here on out will now be a complete image of the scene with
	// fog applied, so that translucents can blend fog.
	gl_FragData[1] = vec4(scene, 1.0);

	// colortex5 is an immutable copy of colortex2.
	// They both store skylight.
	gl_FragData[2] = vec4(vec3(skylight), 1.0);

	/* DRAWBUFFERS:405 */
#else
	// Water absorption is off, so nothing here applies fog and the scene has no
	// output of its own yet. It still has to be written, because the environment
	// reflection belongs to the scene rather than to the copy - and in this
	// configuration the reflection is the only reason this pass runs at all
	// unless something else asked for it.
	//
	// Note that the fog in this configuration was applied by the surface
	// programs themselves, which means the reflection added here is not fogged
	// with it. That is the price of adding it after the fact in this
	// configuration; the refraction-assisted one above gets it right.
	if (depth < 1.0) {
		vec3 viewPos = ViewPosFromDepth(gbufferProjectionInverse, depth);

	}

	gl_FragData[1] = vec4(scene, 1.0);

	/* DRAWBUFFERS:40 */
#endif
}