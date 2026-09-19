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

// We must make a copy of colortex0 for forward-rendered reflections and
// refraction, as we cannot sample a texture we are rendering into.
const int R11F_G11F_B10F = 0;
const int R8 = 0;

// We must write to colortex4, as per OptiFine/Iris specifications, that is the
// first colortex buffer number that gbuffers shaders can sample. colortex0-3
// are not bound in gbuffers shaders.
const int colortex4Format = R11F_G11F_B10F;
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

// The environment this fragment reflects, in linear RGB.
//
// Zero wherever there is nothing to reflect anything - see
// PbrReflectionPossible - which is most of the screen: only surfaces with a
// reflectance and a roughness to speak of, under an open sky, are covered.
//
// This is the only place the environment reflection exists. It used to be added
// where each surface was drawn, which meant the reflection could not include the
// world: a surface is drawn while the frame it belongs to is still being filled,
// so the depth buffer it would have to trace against is not finished. Here, one
// pass later, it is.
vec3 EnvironmentReflection(
	vec3 viewPos,
	float skyLight
) {
	#if defined(PBR_REFLECTIONS) || defined(PBR_SSR)
		// Read the material the surface programs left for this pixel. Both
		// fetches are of this same pixel, which is why they can be exact.
		vec4 material = texelFetch(colortex7, ivec2(gl_FragCoord), 0);
		vec3 worldNormal = material.xyz;
		float roughness = material.w;
		vec3 f0 = texelFetch(colortex8, ivec2(gl_FragCoord), 0).rgb;

		if (!PbrReflectionPossible(worldNormal, roughness, f0)) {
			return vec3(0.0);
		}

		// The camera sits at the origin of view space, so the view direction is
		// simply the direction back towards the origin.
		//
		// Taken from the view-space position, which is exact, rather than from the
		// camera-relative one, which is that same position built through the
		// inverse of the camera's matrix: that inverse carries a small error while
		// the view is bobbing, and a mirror turns a small error in the view
		// direction into a reflection that shivers as you walk. See the note in
		// /environment/clouds/volumetric.glsl.
		//
		// The reflection itself is worked out in the world, beside the surface
		// normal, so the direction is turned back into world axes by dotting it
		// against them - the transpose of the matrix the geometry was drawn with,
		// which for a rotation is that matrix's inverse.
		mat3 view = mat3(gbufferModelView);
		vec3 viewDirection = normalize(vec3(
			dot(-viewPos, view * vec3(1.0, 0.0, 0.0)),
			dot(-viewPos, view * vec3(0.0, 1.0, 0.0)),
			dot(-viewPos, view * vec3(0.0, 0.0, 1.0))));
		float NdotV = max(dot(worldNormal, viewDirection), 1.0e-4);

		vec3 worldReflected = PbrReflectionDirection(
			worldNormal,
			viewDirection,
			roughness);

		// The sky, which is what an environment reflection is made of on its own,
		// and which is also where a trace that finds nothing ends up.
		//
		// Faded out by how much of the sky this fragment can actually see, so
		// that a cave floor or an interior does not reflect a sky that is not
		// visible from it.
		vec3 environment = SkyDither(
			gl_FragCoord.xy,
			SkyColor(worldReflected)) * PbrSkyExposure(skyLight);

		#if defined(PBR_SSR)
			// Only the smooth surfaces are traced. See PBR_SSR_ROUGHNESS: a rough
			// surface would be shown a mirror image it should not have, and since
			// the trace costs the same whether or not it finds anything, skipping
			// the rough ones is most of the cost of it in a scene that is mostly
			// made of rough things.
			if (roughness < PBR_SSR_ROUGHNESS) {
				vec2 hitPos;
				vec3 hitViewPos;

				// Tracing the reflected ray through the depth buffer finds
				// whatever is on screen along it. The thickness control is the
				// tolerance for accepting a hit: a surface as smooth as this one
				// shows every artefact of a stretched reflection, so it is kept
				// tight.
				if (Raytrace(
					depthtex1,
					gbufferProjection,
					gbufferProjectionInverse,
					viewPos,
					mat3(gbufferModelView) * worldReflected,
					vec2(0.5, 1.0),
					hitPos,
					hitViewPos
				)) {
					// What the ray found, which is the previous frame: the frame
					// this one is being drawn from is complete in depth but not in
					// colour at this point in the pipeline.
					vec3 hitColor = texture(colortex3, hitPos).rgb;

					// Fade the result out near the edge of the screen, where the
					// ray is about to leave the buffer and there is nothing more
					// to find. Without this the reflection would stop at a hard
					// line.
					vec2 hitPosAbs = abs(hitPos * 2.0 - 1.0);
					float edgeFade = min(
						1.0,
						(1.0 - max(hitPosAbs.x, hitPosAbs.y)) / 0.10);

					environment = mix(environment, hitColor, edgeFade);
				}
			}
		#endif

		return PBR_REFLECTIONS_STRENGTH
			* PbrReflectionFresnel(f0, NdotV, roughness)
			* environment;
	#else
		return vec3(0.0);
	#endif
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
			#if DEBUG == DEBUG_DEPTH
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

				background *= mix(1.0, lit, sssWeight);
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

#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED || defined(VOXY)
	if (depth < 1.0) {
		vec3 viewPos = ViewPosFromDepth(gbufferProjectionInverse, depth);

		// The reflection goes on before the fog, so that a reflection far away
		// fades into the distance exactly as the surface it is on does.
		scene += EnvironmentReflection(viewPos, skylight);

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

		scene += EnvironmentReflection(viewPos, skylight);
	}

	gl_FragData[1] = vec4(scene, 1.0);

	/* DRAWBUFFERS:40 */
#endif
}
