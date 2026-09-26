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
	// This needs to be at the top of the preprocessed shader
	#extension GL_ARB_texture_gather : require
#endif

// The light source mask this program writes for the light bleed pass - see
// DRAWBUFFERS at the bottom of this file, and /program/post/light_bleed.fsh for
// what reads it.
//
// The format name on the right is not a name the shader mod provides to GLSL.
// It is read out of the declaration as text and then replaced, but the line is
// also an ordinary GLSL declaration, so the name has to exist as a constant for
// the shader to compile at all - hence the line above it. Every place in this
// pack that names a format does this; leaving the constant out fails with
// "'R11F_G11F_B10F' : undefined variable" from the driver.
const int R11F_G11F_B10F = 0;
const int colortex6Format = R11F_G11F_B10F;

// Where the specular highlight is recorded, so that the bloom can leave it out.
//
// The same format as colortex0, deliberately: this value is subtracted from
// that buffer, and in one format the two agree digit for digit, so a pixel
// whose whole colour is its highlight comes out at exactly zero rather than at
// whatever a change of format rounded off. It is also an unsigned format with
// no exponent of its own, and that is what rules out a value arriving at the
// bloom's blur as a NaN, an infinity or a negative - a blur is the worst place
// for one of those to appear, because it spreads it over the whole screen
// instead of leaving it where it was. See lib/bloom.glsl.
const int colortex15Format = R11F_G11F_B10F;

// The material the environment reflection is computed from, read back by the
// deferred pass. See the material outputs at the bottom of this file.
//
// RGBA16F for the normal, because a reflection is only as accurate as the
// direction it is sampled in and half floats are the cheapest thing that keeps
// that direction smooth. RGBA8 for the reflectance, which is a colour that
// hardly varies across a surface and does not need more.
const int RGBA16F = 0;
const int RGBA8 = 0;
const int colortex7Format = RGBA16F;
const int colortex8Format = RGBA8;

// Water absorption configuration, has wide-reaching impacts across the codebase
// Uniforms: none
#include "/environment/water/absorption_settings.glsl"

// Water absorption, if being done with the refraction-assisted method.
// Uniforms: none
#include "/environment/water/absorption.glsl"

// The vanilla render distance, in blocks: where the terrain the game's own
// renderer draws ends and another renderer's - Distant Horizons, Voxy - begins.
//
// Declared up here, ahead of the includes, for the same reason the matrix below
// is: the water parallax fade is limited by it, and that is pulled in further
// down. It used to sit with the stipple that reads it, near the bottom of the
// file, which put the parallax code above its own declaration.
uniform float far;

// Used to covert viewPos to worldPos.
uniform vec3 cameraPosition;

// The forward half of the camera's matrix pair - world to view - which is the
// one the geometry here was drawn with.
//
// Declared up here, ahead of the includes, because the cloud layer needs it and
// that is pulled in further down; a shader has to see a declaration before the
// code that uses it. The macro tells other files that want the same uniform -
// /environment/lighting/translucent.glsl - that it has already been declared,
// because a repeated declaration is an error.
#define GBUFFER_MODEL_VIEW_DECLARED
uniform mat4 gbufferModelView;

// Water waves and caustics scrolling.
//
// Declared behind a guard because more than one file in a program wants this
// and a repeated uniform declaration is an error. See the note in
// /environment/sky/end.glsl.
#if !defined(EXTERNALLY_DEFINED_UNIFORMS) && !defined(FRAME_TIME_COUNTER_DECLARED)
	#define FRAME_TIME_COUNTER_DECLARED
	uniform float frameTimeCounter;
#endif

// Whether to freeze animations (useful for testing).
//#define FREEZE_ANIMATION_TIMER
#ifdef FREEZE_ANIMATION_TIMER
	float timeSeconds = 500.0;
#else
	float timeSeconds = frameTimeCounter;
#endif

#include "/environment/materialIDs.glsl"

// The color of each light source's light. Uniforms: none.
#include "/environment/lighting/light_colors.glsl"

#if !defined(NEVER_REALTIME_SHADOWS) && !defined(NEVER_RECEIVES_SHADOWS)
	#define REAL_TIME_SHADOWS // Enables real-time shadows using shadow mapping.
#endif

#if defined(REAL_TIME_SHADOWS)
	#include "/environment/lighting/shadowmap.glsl"
	in vec3 shadowPos;
#endif

#include "/environment/lighting/diffuse.glsl"

#if defined(AFTER_DEFERRED)
	#define APPLY_FOG
#endif

#if WATER_ABSORPTION_METHOD != REFRACTION_ASSISTED && !defined(VOXY)
	#define APPLY_FOG
#endif

#if defined(TRANSLUCENT) || defined(APPLY_FOG)
	#include "/environment/fog.glsl"

	// Sky reflection
	#include "/environment/sky.glsl"
#endif

#if defined(TRANSLUCENT) || defined(EXPLICIT_OPAQUE_DEPTH_TEST)
	// Used for SSR tracing and for depth-testing on DH translucents
	uniform sampler2D depthtex1;
#endif

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;

// Distant Horizons terrain is rendered with a different projection matrix, and
// we must be aware of it in our transformations.
#ifdef DH_TERRAIN
	uniform mat4 dhProjection;
	uniform mat4 dhProjectionInverse;
	uniform sampler2D dhDepthTex1;

	// Workaround for an apparent Iris bug:
	//
	// gl_ProjectionMatrixInverse is well-defined with Distant Horizons, but
	// dhProjectionInverse (what you are supposed to use) is not correct.
	#define inverseProjectionMatrix gl_ProjectionMatrixInverse
	#define projectionMatrix gl_ProjectionMatrix
	#define opaqueDepth dhDepthTex1
#else
	// Workaround continues:
	//
	// Naturally, since things couldn't be that simple, 
	// gl_ProjectionMatrixInverse seems to have garbage outside of Distant
	// Horizons passes, but gbufferProjectionInverse is identical.
	#define inverseProjectionMatrix gbufferProjectionInverse
	#define projectionMatrix gbufferProjection
	#define opaqueDepth depthtex1

	#ifdef DISTANT_HORIZONS
		uniform mat4 dhProjection;
		uniform mat4 dhProjectionInverse;
		uniform sampler2D dhDepthTex1;

		// TODO: It seems like this is still not correct and leads to
		//       discontinuities in things like fog between nearby water
		//       reflecting distant terrain and distant terrain reflecting
		//       distant terrain, unfortunately I am not sure how to work around
		//       this.
		#define inverseProjectionMatrixDistant dhProjectionInverse
		#define projectionMatrixDistant dhProjection
		#define opaqueDepthDistant dhDepthTex1
	#endif
#endif

uniform vec2 windowToNdc;

// Note: using #if defined instead of #ifdef to prevent this from being picked
// up as a shader configuration option.
#if defined(TRANSLUCENT)
	#include "/environment/lighting/translucent.glsl"
#endif

// The environment reflections for materials, which need the sky model above and
// bring it in themselves if this program did not already ask for it. Only
// compiled when one of the two options is on, since it is one sky evaluation
// per pixel.
//
// Both options rather than the sky one alone: the file's own guard is the same
// pair, and the hand's reflection below is a traced one - it needs these
// whether or not the sky half of the world's reflection is switched on.
#if defined(PBR_REFLECTIONS) || defined(PBR_SSR)
	#include "/environment/lighting/reflections.glsl"
#endif

// How much of the diffuse response a metal keeps on a held item, from none of
// it to all of it - the number, and why it exists, are where it is used, at the
// end of the material block in main().
//
// Declared here rather than in gbuffers_hand.fsh, which is where a constant
// about the hand belongs, because this file is included by every world program:
// a name the hand's program defines alone would be missing from the expansion
// of all the others, and which of them compile the line that uses it is then a
// question about the preprocessor rather than about the hand. Whoever uses it
// declares it, which is the same rule the includes in this file follow.
#if defined(PBR_HAND_ITEMS)
	#define PBR_HAND_METAL_DIFFUSE 0.5
#endif

// The two buffers a held item's reflection is traced against.
//
// depthtex2 is the depth buffer the hand is not in. depthtex1 - the one the
// world's own reflections march - holds the item itself at the item's own
// pixels, so a ray leaving the item meets the item first and paints it with
// whatever is behind it; that was measured twice on this pack, and it is why a
// held item was left out of the reflection altogether. Mellow Shader, which
// does reflect held items, solves the same problem by hand: its ray gives up
// when the depth under it is nearer than 0.56, and the same number appears in
// its SSAO pass with the comment "Skip hand". Sundial documents depthtex2 in
// its own option list as the depth without the hand, which is the same rule
// kept by the loader instead of by the shader.
//
// colortex4 is the world's colour with no reflections in it, which is what the
// world's reflections sample - except that at this point in the frame the pass
// that writes it has not run yet, so what is there is the last finished frame.
// That is the same one-frame-old picture Mellow's reflection reads (gaux1,
// with gaux1Clear set so that it survives), and it is the only one there is:
// the item is drawn while the frame it belongs to is still being filled.
#if defined(PBR_HAND_ITEMS) && defined(PBR_SSR)
	uniform sampler2D depthtex2;
	uniform sampler2D colortex4;

	// The one test a hit has to pass that the trace does not make itself: it
	// has to be beyond the item. See where it is used, at the end of the
	// material block in main().
	//
	// A reflected ray only ever travels away from the surface it left, so a
	// genuine hit is always further from the eye than the fragment that cast
	// it, and anything nearer is the item meeting itself. That test is exact
	// and needs no threshold - which is what the first version of this got
	// wrong. It refused every hit closer than a block instead, and a block is
	// most of what a held item reflects when the player is anywhere near
	// anything: mining, standing against a wall, looking down. The result was a
	// reflection that covered part of the item and not the rest, with the
	// boundary moving as the player walked.

	// The trace's step budget, which is the option the world's screen-space
	// reflections use, and for the same reason: this is one trace per pixel of
	// the item rather than one per pixel of the screen.
	#define RAYMARCH_STEPS PBR_SSR_STEPS

	// Raytrace(...), for the trace itself. Nothing else in this file includes
	// it: the deferred pass and composite1 are different programs.
	#include "/lib/raytrace.glsl"

#endif

#ifdef DISTANT_HORIZONS
	// Needed for stippling between vanilla and distant terrain during the
	// transition between the two near the edge of vanilla render distance.
	#include "/lib/bayer8.glsl"
#endif

// sRGB to Linear RGB
// Uniforms: none
#include "/lib/srgb.glsl"

#if !defined(COLORWHEEL)
	// The interpolated vertex color directly from the vertex buffer.
	in vec4 tinting;

	// The lightmap texture coordinates, ranging from 0.03125 to 0.96875.
	// The x / "s" component is the block light, and the y / "t" component is
	// the sky light. The block light will be negative when this face can be
	// emissive.
	in vec2 lightMap;

	// Must match the guard in lit.vsh, or one stage would have a varying the
	// other does not. The entity programs get here through
	// PBR_MATERIALS_ANY_TEXTURE rather than PBR_ATLAS.
	#if defined(PBR_ATLAS) || defined(PBR_MATERIALS_ANY_TEXTURE)
		// xy: the centre of this face's sprite in the block atlas, zw: half of
		// its size, except that an axis whose extent is nil takes the other
		// axis's half instead (see the assignment in lit.vsh). Parallax mapping
		// works in the box these describe, and a sample that would leave that box
		// has the offset faded by the room the fragment has left and is held at the
		// box's edge behind that, rather than being wrapped round to the far side of
		// the sprite; see PbrFadeOffsetToSprite and PbrClampToSprite, and
		// PbrSpriteLocal for the box itself. A zero half-size, which is what a
		// non-atlas surface carries, is what PbrSpriteUsable reads as "no box here",
		// and both of the marches then leave the surface undisplaced.
		in vec4 spriteBounds;

		// The tangent this geometry actually carries, from lit.vsh, with the
		// handedness in w. Zero for geometry that has none, which
		// PbrAttributeFrame detects and falls back on.
		in vec4 pbrTangent;
	#endif

	// Note: using #if defined instead of #ifdef to prevent this from being
	// picked up as a shader configuration option.
	#if defined(MIX_ENTITY_COLOR)
		// This is an overlay color used when rendering entities in some cases.
		// It has two functions:
		// 
		// 1. Implement the about-to-explode flash on creepers and primed TnT
		//    (white direction of overlay texture)
		// 2. Implement the red hurt flash on damaged entities
		//    (red direction of overlay texture)
		// 
		// However, that is abstracted away from us. All we have to care about
		// is that we have an RGB color, and an interpolation factor from 0.0 to
		// 1.0 (0.0 = no overlay visible, 1.0 = only overlay visible).
		// 
		// File reference on how this relates to the Minecraft concept in Iris:
		// 
		// https://github.com/IrisShaders/Iris
		// Commit: f0f6a27453d44a18e1c655880dca0baf2de03c9a
		// /src/main/java/net/coderbot/iris/pipeline/transform/transformer
		// /AttributeTransformer.java#L139-L229
		uniform vec4 entityColor;
	#endif
#endif

// Note: using #if defined instead of #ifdef to prevent this from being picked
// up as a shader configuration option.
#if !defined(NO_GTEXTURE)
	// The base material (block/entity/etc) texture
	uniform sampler2D gtexture;

	// The interpolated texture coordinate directly from the vertex buffer.
	in vec2 texcoord;
#endif

#if defined(WEATHER)
	// Rain and snow particles.
	//
	// Declared behind this guard rather than in a shared file, for the reason
	// WAVING_FOLIAGE is declared beside its own: only this program draws
	// weather, so only this program should carry the options, and nothing that
	// Distant Horizons patches has to know about them.
	//
	// AMOUNT tiles the rain texture across each quad, which packs more drops
	// into the same column of rain; SIZE then keeps only the middle of each
	// drop, which makes the drops thinner. SIZE is scaled by AMOUNT where it is
	// used, so the drops stay the same thickness on screen as AMOUNT changes
	// and the two controls stay independent of each other. Snow is drawn by
	// this program too, so both act on snow as well, and 1.0 is the untouched
	// vanilla particle for either one. SATURATION is the colour of the particle
	// itself: 1.0 leaves the texture's own pale blue-grey alone, 0.0 takes the
	// colour out of it, and above 1.0 pushes what colour there is.
	#define RAIN_DROP_AMOUNT 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0 2.5 3.0 4.0 6.0 8.0]
	#define RAIN_DROP_SIZE 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]
	#define RAIN_COLOR_SATURATION 1.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 4.0]

	// See the matching outputs in /program/world/lit.vsh.
	in vec2 weatherSpriteCoord;
	in vec2 weatherSpriteScale;
#endif

#define STANDARD 1
#define NONE 2
#define VERTEX_COLOR 3
#define WORLD_POSITION 4
#define WORLD_NORMAL 5
#define SURFACE_COLORS STANDARD // [STANDARD NONE VERTEX_COLOR WORLD_POSITION WORLD_NORMAL]

// Alpha test threshold - any pixels with an alpha less than this will be
// discarded.
#if !defined(ALPHA_TEST_CUTOFF)
	uniform float alphaTestRef;
#else
	#define alphaTestRef ALPHA_TEST_CUTOFF
#endif

#include "/lib/encoding/lightmap.glsl"

// Per-face data encoded by EncodePerFace (/lib/encoding/face.glsl)
#include "/lib/encoding/face.glsl"
flat in uint perFace;

void main() {
	// End debug: paint everything this program draws in a flat color, so that an
	// effect whose program is not known can be traced to the program that draws
	// it by looking at what color it turns. See END_DEBUG in
	// /environment/dimension.glsl.
	#if defined(END_DEBUG) && defined(END_DEBUG_TINT)
		if (EndDimension()) {
			gl_FragData[0] = vec4(END_DEBUG_TINT, 1.0);
			return;
		}
	#endif

	// The selection outline, removed outright when the option says so.
	//
	// ⚠️ discard rather than writing something invisible, because the point of
	// NONE is that the box is not there - and discarding also skips the depth
	// write, so nothing of the outline is left behind for anything downstream to
	// find. It is here, at the top, so that a fragment which is not going to be
	// drawn does not pay for the rest of the shader either.
	//
	// ⚠️ After the debug block above rather than before it: that block is how a
	// program is identified, and an option that could hide the evidence would
	// make identifying one harder.
	#if defined(DRAWING_LINES) && SELECTION_BOX == SELECTION_BOX_NONE
		discard;
	#endif

	#if defined(SUPPRESS_END_FLASH)
		#if !defined(MC_VERSION) || MC_VERSION >= 12109
			// The End's light flash (Minecraft 1.21.9) is drawn as a quad in the
			// sky with no texture that the mod knows to bind, so it samples the
			// block atlas and shows up as a patch of a random block's texture.
			// There is nothing to be done with it from here, so it is dropped.
			//
			// Unconditional as of batch 333: this used to sit behind an option,
			// HIDE_END_FLASH, and the user reported that toggling it changed
			// nothing. That is because the flash is overwritten by the End's sky
			// anyway - see the note in /environment/dimension.glsl.
			//
			// Only what is far away is dropped, because the programs that draw
			// it also draw things worth keeping near the player. Past ten blocks
			// or so, gl_FragCoord.z is within a hundredth of the far plane, which
			// is what that test is: the sky it is drawn in is a hundred blocks
			// out, and nothing worth keeping is.
			if (EndDimension() && gl_FragCoord.z > 0.99) {
				discard;
			}
		#endif
	#endif

	// Transform back from window coordinates to view-space position and world
	// space positions (camera-relative and absolute).
	//
	// It is cheaper to do this transform back from the fragment coordinates in
	// the fragment shader rather than passing these positions as varyings from
	// the vertex shader, as the cost of buffering and interpolating is more
	// expensive than the following matrix math.
	vec3 ndcPos = gl_FragCoord.xyz * vec3(windowToNdc, 2.0) - 1.0;
	vec4 viewPosH = inverseProjectionMatrix * vec4(ndcPos, 1.0);
	vec3 viewPos = viewPosH.xyz / viewPosH.w;
	// The fragment's position relative to the camera, in world axes.
	//
	// Read out of the view-space position against the world's axes taken from
	// gbufferModelView, rather than by putting the view position through
	// gbufferModelViewInverse.
	//
	// The two should be the same rotation of each other, and the second is what
	// the pack has always done, but they are not quite the same while the view is
	// bobbing: that inverse is not quite the inverse of the matrix the vertices
	// went through, and the small error it carries is what made the reflections
	// shiver as the player walked - the screen-space reflection stopped doing it
	// once its direction came from the view position instead (see the note in
	// /program/post/copy_and_fog.fsh). Dotting the view position against the
	// world's axes is the transpose of that matrix, which for a rotation is its
	// inverse, and it cannot disagree with the geometry by construction.
	mat3 viewRotation = mat3(gbufferModelView);
	vec3 cameraRelativePos = vec3(
		dot(viewPos, viewRotation * vec3(1.0, 0.0, 0.0)),
		dot(viewPos, viewRotation * vec3(0.0, 1.0, 0.0)),
		dot(viewPos, viewRotation * vec3(0.0, 0.0, 1.0)));

	uint materialID = DecodePerFaceMaterialID(perFace);
	vec3 worldNormal = DecodePerFaceWorldNormal(perFace);

	// Whether the world's own lighting treats this face as a light source.
	//
	// Iris and OptiFine mark a face that can emit light by making the block
	// light coordinate of its lightmap negative, which is the signal that does
	// not depend on the resource pack at all. The second test is a fallback for
	// shader mod versions that do not provide that marker: a face sitting at the
	// maximum block light level is a light source itself rather than merely
	// something lit by one. Only the brightest level is taken, so that the
	// blocks around a torch do not glow along with it.
	//
	// Worked out here, above the alpha test, rather than down where it is used:
	// the material debug view needs it too, and hoisting it out keeps this one
	// expression in one place. Left at zero for the Colorwheel programs, which
	// do their own material shading and have no lightmap of their own to read.
	float emissive = 0.0;

	#if !defined(COLORWHEEL)
		emissive = lightMap.x < 0.0
			? 1.0
			: smoothstep(14.5 / 15.0, 1.0, LightMapToLight(lightMap.x));
	#endif

	// The material the environment reflection will be computed from, written out
	// at the bottom of this file for the deferred pass to read back.
	//
	// The neutral values - an up normal, fully rough, no reflectance - are what
	// that pass reads as "there is nothing here to reflect anything", so a
	// program with no material data at all writes those rather than skipping the
	// write. The buffers are cleared every frame, so anything that draws no
	// material and writes none either reads back the same way.
	vec3 reflectionNormal = vec3(0.0, 1.0, 0.0);
	float reflectionRoughness = 1.0;
	vec3 reflectionF0 = vec3(0.0);

	// Which metal this is, or 0 for anything that is not one. Carried alongside
	// the reflectance because the deferred pass needs it to know which metals
	// reflect which colour at a grazing angle, and because a metal is also
	// allowed to reflect at a roughness where everything else is not. See
	// PbrMetalF82 and PbrReflectionSmoothness.
	float reflectionMetalID = 0.0;

	#ifdef PBR_SURFACE
		// Sample the derivatives that the material decoding needs up here,
		// before the discards below.
		//
		// dFdx and dFdy have undefined results once a fragment has been
		// discarded or after non-uniform control flow, and a texture sample with
		// an implicit level of detail has the same restriction. The alpha test
		// further down throws away a large number of fragments (think of a
		// player shoving their camera into a block of leaves), so this ordering
		// is not optional.
		//
		// The alpha test also means the landscape below is not one of our
		// choice: the parallax ray march would much rather sample before it has
		// to worry about any of this.
		// The gradients, with their mip level clamped by PBR_MATERIAL_MAX_LOD.
		// See PbrMaterialGradients - without that clamp a distant surface's
		// normal map picks up the empty space beside its sprite and appears to
		// invert.
		PbrGradients pbrGradients = PbrMaterialGradients(
			PbrSampleGradients(texcoord, cameraRelativePos));
		#ifdef PBR_TANGENT_ATTRIBUTE
			// The geometry's own tangent, which is what the frame should have
			// been built from all along: see PBR_TANGENT_ATTRIBUTE.
			mat3 pbrFrame = PbrAttributeFrame(worldNormal, pbrTangent, pbrGradients);
		#else
			mat3 pbrFrame = PbrCotangentFrame(worldNormal, pbrGradients);
		#endif

		PbrSurface pbr = PbrNone();
		vec3 pbrNormal = worldNormal;
		vec2 pbrTexCoord = texcoord;

		// How far the parallax ray was displaced, in texture coordinates. Only
		// PBR_DEBUG_PARALLAX reads it; see the note on that option.
		float pbrParallaxOffset = 0.0;

		// Water has its own reflection model in TranslucentLighting, which
		// relies on the unperturbed face normal to decide whether a face can
		// reflect at all. Leave it to that rather than fighting over the same
		// highlight.
		//
		// Ice is different: it is a solid surface drawn by the translucent pass
		// rather than a body of liquid, and TranslucentLighting gives it no
		// reflectance of its own. Decoding it here is what gives it one, so it
		// is included whenever PBR_TRANSLUCENT is on; see the option there.
		bool pbrMaterial = materialID != WATER;

		#if !defined(PBR_TRANSLUCENT)
			pbrMaterial = pbrMaterial && materialID != ICE;
		#endif

		#if defined(PBR_HAND_ITEMS) && !defined(PBR_HAND_ITEM_MATERIALS)
			// A held item is not a block, and the material maps are generated for
			// the block atlas: its coordinates would land on another sprite's
			// material and turn the item into a mirror of whatever is behind it.
			// Only geometry the world gave a material to - which is to say a block,
			// as mc_Entity reports it - is read from that atlas.
			//
			// A held block answers to a material ID and an item does not, so that
			// is the test. See the option in gbuffers_hand.fsh for the whole of it.
			pbrMaterial = pbrMaterial && materialID != GENERIC;
		#endif

		// This branch is safe even though it contains texture samples because
		// every one of them uses explicit gradients (see PbrGradients) - only
		// the derivatives above had to be taken unconditionally.
		if (pbrMaterial) {
			pbrTexCoord = PbrParallaxUV(
				pbrFrame,
				cameraRelativePos,
				texcoord,
				pbrGradients,
				spriteBounds,
				pbrParallaxOffset);

			pbr = PbrDecode(pbrTexCoord, pbrGradients);
			pbrNormal = PbrNormal(pbrFrame, pbrTexCoord, pbrGradients);

			#ifdef PBR_PARALLAX_SHADOWING
				// How much of the sunlight survives the height field, which is
				// what stops the displaced surface from looking like a flat
				// layer that merely slides around.
				pbr.selfShadow = PbrParallaxShadow(
					pbrTexCoord,
					pbrFrame,
					worldLightVector,
					cameraRelativePos,
					pbrGradients,
					spriteBounds);
			#endif
		}

	#endif

	#if !defined(NO_GTEXTURE)
		// The coordinate used to sample the base material texture.
		//
		// Parallax mapping shifts it along with the material maps, so that the
		// albedo lines up with the displaced surface rather than staying flat.
		// Shifting only the normals would make the two disagree, which reads as
		// the lighting sliding across the texture rather than the surface
		// having depth.
		vec2 surfaceTexCoord = texcoord;

		#ifdef PBR_SURFACE
			surfaceTexCoord = pbrTexCoord;
		#endif

		#if defined(WEATHER)
			// Rain and snow particles, tiled RAIN_DROP_AMOUNT times across
			// each quad.
			//
			// The tiling has to be done on the sprite's own coordinate, not on
			// surfaceTexCoord: they differ by the texture matrix, and folding
			// an atlas coordinate leaves the sprite entirely. Subtracting the
			// untransformed coordinate and adding the tiled one back, scaled
			// into atlas space, is the same fold carried out in the space the
			// sprite actually lives in. At the default of 1.0 the two folds
			// agree and this is the identity.
			vec2 weatherRainCoord = vec2(
				fract(weatherSpriteCoord.x * RAIN_DROP_AMOUNT),
				weatherSpriteCoord.y);

			surfaceTexCoord = texcoord + (weatherRainCoord - weatherSpriteCoord) * weatherSpriteScale;
		#endif
	#endif

	// Distant Horizons translucent terrain needs a manual depth test against
	// the non distant depth buffer.
	//
	// It is rendered after all opaque objects but before translucent normal
	// terrain, but uses the depth buffer for distant terrain.
	#if defined(EXPLICIT_OPAQUE_DEPTH_TEST)
		float opaqueDepth = texelFetch(depthtex1, ivec2(gl_FragCoord), 0).r;

		if (opaqueDepth != 1.0) {
			// Project back to view space from the fragment coordinates
			vec3 ndcPosOpaque = vec3(ndcPos.xy, opaqueDepth * 2.0 - 1.0);
			vec4 ndcPosHOpaque = vec4(ndcPosOpaque, 1.0);
			vec4 viewPosOpaque = gbufferProjectionInverse * ndcPosHOpaque;

			if (viewPosOpaque.z / viewPosOpaque.w > viewPos.z) {
				discard;
				return;
			}
		}
	#endif

	vec4 surfaceColor;

	#if defined(COLORWHEEL)
		vec4 entityColor;
		vec2 lightMap;
		float ignoredAo;

		vec4 sampledColor = texture(gtexture, surfaceTexCoord);

		#if SURFACE_COLORS == VERTEX_COLOR
			sampledColor.rgb = vec3(1.0);
		#endif

		clrwl_computeFragment(
			// Input: the result obtained from sampling gtexture.
			sampledColor,
			// Output: the result of sampledColor times the tinting (vertex 
			// color), with ambient occlusion applied.
			surfaceColor,
			// Output: the final lightmap value, with values ranging from
			// 0.03125 to 0.96875.
			lightMap,
			// Output: the ambient occlusion value, not needed in our case.
			ignoredAo,
			// Output: equivalent to entityColor.
			entityColor);
	#else
		surfaceColor = tinting;
	#endif

	float skyLight = LightMapToLight(lightMap.y);

	#if defined(TRANSLUCENT)
		// The strenght of sky reflections (separate from terrain reflections)
		// 0.0 to 1.0, this is modulated into the fresnel value.
		// 
		// Only ice and water can reflect the sky / terrain currently.
		//
		// We only enable sky & terrain reflections on faces pointing upwards.
		// This is due to a few factors:
		//
		// - The player view angle is generally horizontal. As a result, when
		//   looking at upwards-facing water surfaces, generally there are
		//   plenty of things in the background to reflct, so upwards-facing
		//   faces look good as a baseline.
		//
		// - When looking at the sides of faces, the screenspace reflections
		//   cannot often actually trace to what the block is reflecting, due to
		//   either there being things in the way or the object-to-be-reflected
		//   simply not being on screen.
		//
		// - Flowing water sides should be rough anyways and should not have
		//   glassy, specular reflections. We do not support rough reflections,
		//   so even if we permitted reflections on the sides of water, it looks
		//   bad.
		//
		// - Reflecting underwater terrain while underwater is OK, but is
		//   not really impactful and not particularly worth our time, so we can
		//   skip it.
		//
		// Water that is not lying flat - the side of a waterfall, or water
		// running down a slope - used to be demoted to a generic material here,
		// which left it with nothing but the vanilla water texture: every branch
		// downstream asks for water by material, so the surface style, the water
		// colour and the reflections were all skipped. The demotion was there
		// because the wave normal on those faces used to come out pointing at the
		// sky - see parallaxWaterNormal - so everything built on it was wrong.
		// They have a normal of their own now, so the faces are left as water.

		// Fade out reflections to zero as the skylight goes away, needed to
		// avoid water being reflective underground which looks bad.
		bool reflective = materialID == WATER || materialID == ICE;

		#ifdef GLASS_REFLECTIONS
			// Glass and stained glass reflect with the same code, which is what
			// gives a window a mirror side when seen at an angle - and, because
			// that code includes the screen-space pass, what lets it reflect the
			// world rather than only the sky. See GLASS_REFLECTIONS in
			// translucent.glsl for what that costs.
			reflective = reflective
				|| materialID == GLASS
				|| materialID == STAINED_GLASS;
		#endif

		float reflectionStrength = reflective ? skyLight : 0.0;
	#endif

	// No need for this with Colorwheel as it handles this in its material
	// shader.
	#if !defined(NO_GTEXTURE) && !defined(COLORWHEEL)
		#if defined(TRANSLUCENT)
			if (materialID == WATER) {
				// This alpha value is tuned for clear water but you can
				// increase it for dirtier/murkier water (it might be better to
				// adjust the water absorption though.)
				//
				// Note: When underground, don't tint the water with the sky
				// color.
				
				// Whether to enable a different style water.
				//#define VANILLA_ISH_WATER 
				#ifndef VANILLA_ISH_WATER
					// TODO: Use dedicated water color uniform?
					surfaceColor.rgb = mix(
						surfaceColor.rgb,
						skyAmbient,
						reflectionStrength);
					surfaceColor.a = 0.25 * (1.0 - reflectionStrength);

					// The alpha test further down throws away anything with an
					// alpha below 1/10000, and at full sky light this expression
					// lands on exactly zero - so the brightest water, which is the
					// water most worth drawing, was the water that disappeared.
					// Everything the surface actually shows is added afterwards by
					// TranslucentLighting; this is only a floor to keep the
					// fragment alive long enough to get there.
					surfaceColor.a = max(surfaceColor.a, 1.0 / 1024.0);
				#else
					surfaceColor *= texture(gtexture, surfaceTexCoord);

					// We blend in HDR, meaning that there can be a large
					// difference in brightness between the water surface
					// and the background.
					//
					// To maintain a similar level of perceptual opacity,
					// we need to scale the alpha value accordingly.
					surfaceColor.a *= 0.25;
				#endif
			} else {
		#endif
				// The base texture is sampled at the displaced coordinate so
				// that the albedo lines up with the surface the height field
				// describes rather than staying flat.
				//
				// What the displaced coordinate is not allowed to do is decide
				// the alpha test below. The height field is a 2D claim about a
				// 3D surface, and a ray that walks off a groove can land on a
				// texel the fragment's own surface does not have at all: the
				// transparent pixels a resource pack keeps inside a cutout
				// sprite, of which a door's window is one. The alpha read there
				// is zero, the alpha test throws the fragment away, and both
				// symptoms land in the same band - a point of fine grain per
				// pixel, because where the ray lands moves with the view, and
				// sky through the middle of a solid surface. That band is
				// exactly the texels whose own height sits below the reference
				// height, which is the seams, the frame edges and the border of
				// the window, and it is also the only place the march runs at
				// all: a texel at the reference height returns before the march
				// starts, which is why the flat parts of the same surface stay
				// clean.
				//
				// So a sample that would fail the test is retaken at the
				// coordinate the fragment arrived with. A fragment is inside
				// opaque material by construction - it is drawn from that texel
				// - so it stays opaque, and what it gives up is the
				// displacement it could not have shown anyway, there being no
				// material at the point the ray chose. The cost is one fetch,
				// and only for the fragments that would otherwise be discarded:
				// a surface with no transparent texel in it never enters the
				// branch.
				//
				// Sundial and Mellow both sample the albedo at the displaced
				// coordinate and both alpha test what they get - which is where
				// this march came from, and where this guard does not - so this
				// is a departure from the reference rather than a port of it.
				//
				// Written against alphaTestRef rather than against zero on
				// purpose: in a program whose alpha test is off the reference is
				// zero, so the branch cannot be taken there, and nothing changes
				// for a surface that was never cut out. The parallax test is
				// here for the same reason - with the option off the displaced
				// coordinate is the fragment's own to begin with.
				vec4 baseTexture = texture(gtexture, surfaceTexCoord);

				#if defined(PBR_SURFACE) && defined(PBR_PARALLAX)
					if (baseTexture.a < alphaTestRef) {
						// Explicit gradients: this fetch is inside a branch, so
						// an implicit level of detail is not available to it.
						baseTexture = textureGrad(
							gtexture,
							texcoord,
							pbrGradients.ddxTexCoord,
							pbrGradients.ddyTexCoord);
					}
				#endif

				surfaceColor *= baseTexture;
		#if defined(TRANSLUCENT)
			}
		#endif
	#endif

	#if SURFACE_COLORS == NONE
		surfaceColor.rgb = vec3(1.0);
	#elif SURFACE_COLORS == VERTEX_COLOR && !defined(COLORWHEEL)
		surfaceColor.rgb = tinting.rgb;
	#elif SURFACE_COLORS == WORLD_POSITION
		// In this case, we only care about the offset of the camera position
		// relative to the block grid. Then, offsetting with the normal vector
		// gives us consistent results for the positions that exactly on the
		// grid.
		vec3 worldPosOffset = fract(cameraPosition) - 0.025 * worldNormal;
		surfaceColor.rgb = fract(cameraRelativePos + worldPosOffset);
	#elif SURFACE_COLORS == WORLD_NORMAL
		surfaceColor.rgb = 0.5 * worldNormal + 0.5;
	#endif

	// TODO: For now, we make all water fully reflective with Distant Horizons
	#if defined(NO_GTEXTURE) && defined(TRANSLUCENT) && defined(DH_TERRAIN)
		materialID = WATER;

		if (materialID == WATER) {
			surfaceColor = vec4(0.0);
			reflectionStrength = 1.0;
		}
	#else

	// Reduce alpha of weather (rain, snow) for better visibility
	//
	// Note: using #if defined instead of #ifdef to prevent this from being
	// picked up as a shader configuration option.
	#if defined(WEATHER)
		surfaceColor.a *= 0.5;

		// Rain drop width.
		//
		// The rain texture is a grid of drops with the gaps already painted in
		// as transparency, so the only way to thin a drop without new art is to
		// take another bite out of its alpha. The bite is a repeating band that
		// keeps the middle of every texel of the sprite, RAIN_DROP_SIZE wide as
		// a fraction of the drop - at 1.0 the band is the whole texel period and
		// nothing is removed.
		//
		// The band is measured in the tiled coordinate, so scaling it by
		// RAIN_DROP_AMOUNT is what keeps the drops the same thickness on screen
		// when the tiling above packs more of them into the same quad.
		#if !defined(NO_GTEXTURE)
			float weatherDropTexels = weatherSpriteScale.x * textureSize(gtexture, 0).x;

			float weatherDropMask = step(
				abs(fract(weatherDropTexels * weatherRainCoord.x) - 0.5),
				clamp(RAIN_DROP_AMOUNT * RAIN_DROP_SIZE, 0.0, 1.0) * 0.5);

			// A sprite of no width gives no texel period to measure the band in,
			// and the band then collapses to a constant that happens to sit on
			// the discard side for every value of the two options below 1.0 -
			// which is a whole world of rain disappearing at once because one
			// option moved, and that is exactly what was reported. When the
			// width of the sprite is unknown there is nothing to measure a drop
			// against, so nothing is taken away.
			surfaceColor.a *= weatherDropTexels > 0.5 ? weatherDropMask : 1.0;
		#endif

		// Rain colour saturation.
		//
		// The particle textures are a pale blue-grey, and against a dark scene
		// rain reads as a blue haze rather than as water. This mixes the colour
		// towards its own luminance to take that out, and away from it to push
		// what colour there is. The weights are Rec. 709's, the same grey the
		// rest of the pack measures against.
		//
		// It is applied to the sampled colour, which the surface tint has
		// already been folded into, so a coloured tint on the particle is
		// carried along with it rather than left behind.
		float weatherLuma = dot(surfaceColor.rgb, vec3(0.2126, 0.7152, 0.0722));
		surfaceColor.rgb = mix(vec3(weatherLuma), surfaceColor.rgb, RAIN_COLOR_SATURATION);
	#endif

	#endif
	
	#if defined(MIX_ENTITY_COLOR)
		// Apply hurt flash / tnt flash on entities.
		surfaceColor.rgb = mix(
			surfaceColor.rgb, entityColor.rgb, entityColor.a);
	#endif

	#if !defined(SKIP_ALPHA_TEST)
		// Run the alpha test immediately to avoid shading fragments
		// that would fail the alpha test.
		// 
		// There's no penalty to running it early as we have to run it
		// either way, but if it lets us skip a whole block of pixels
		// (think player shoving their camera into a block of leaves),
		// then maybe we will get a little boost!
		// 
		// Ideally, this helps us save on memory bandwidth when
		// and sampling the shadowmap as well as overall TMU load.
		//
		// Note: Even if you discard, you must also explicitly
		// return or else shader execution will continue with
		// some drivers (NVIDIA).
		//
		// - https://community.khronos.org/t/use-of-discard-and-return/68293/3
		// - https://community.khronos.org/t/probable-nvidia-glsl-compiler-bug/66129/2
		//
		// > An implementation might or might not continue executing the shader,
		// > but it is guaranteed that there is no effect on the framebuffer.
		//
		// The reason why is likely - "Non-uniform_flow_control":
		// https://wikis.khronos.org/opengl/Sampler_(GLSL)
		//
		// You cannot retrieve implicit derivatives (dFdx / etc) or sample with
		// mipmapping after this location if any of the materials you render are
		// subject to alpha testing.
		if (surfaceColor.a < alphaTestRef) { 
			discard;
			return;
		}
	#endif

	// Because of the significant difference in style between Distant Horizons
	// terrain and vanilla terrain, to avoid significant pop-in we need to fade
	// between the two.
	//
	// Distant Horizons has a feature called "overdraw", where it will draw
	// distant terrain even within the vanilla render distance, which gives us
	// the opportunity to fade between vanilla and distant terrain.
	//
	// However, one challenge is that we do not have the straightforward ability
	// to use translucency (alpha blending) to implement this fade. As a result,
	// we need to resort to alternatives, in this case, stippling.
	//
	// To remain seamless, this fade progresses in 5 stages as we get farther
	// from the camera:
	//
	// 1. Vanilla terrain only
	// 2. Fading in distant terrain
	// 3. Distant terrain and vanilla terrain both visible
	// 4. Fading out vanilla terrain
	// 5. Distant terrain only
	//
	// We cannot trivially fade in distant terrain at the same time as we fade
	// out vanilla terrain, as otherwise we would end up with holes where the
	// vanilla and distant terrain have different geometry.
	//
	// TODO: (3) does not work with non-fancy translucents, which get double
	// blended! It only works with opaques! This breaks Retro / vanilla water.
	//
	// TODO: These thresholds were iterated on before I discovered and fixed a
	//       bug causing a discontinuity in cameraRelativePos between DH and non
	//       DH terrain, so they should be redone.
	float fragDistance = length(cameraRelativePos);

	#if (!defined(AFTER_DEFERRED) || defined(FANCY_TRANSLUCENTS)) \
		&& defined(DISTANT_HORIZONS)
		float stipple = Bayer8(gl_FragCoord.xy);

		#if defined(DH_TERRAIN)
			if (smoothstep(far - 8, far - 6, fragDistance) <= stipple) {
				discard;
				return;
			}
		#elif defined(DISTANT_HORIZONS)
			if (1.0 - smoothstep(far - 2, far, fragDistance) <= stipple) {
				discard;
				return;
			}
		#endif
	#elif defined(DH_TERRAIN)
		surfaceColor.a *= smoothstep(far - 5, far - 3, fragDistance);
	#elif defined(DISTANT_HORIZONS)
		surfaceColor.a *= 1.0 - smoothstep(far - 2, far, fragDistance);
	#endif

	vec4 fragmentColor = vec4(vec3(0.0), surfaceColor.a);

	// How much of that colour is a mirror rather than light the surface was
	// given. Filled in by DiffuseLighting below, which is the only code that
	// knows: the same sun that lights a surface also leaves a highlight on it,
	// and it is the second of those two that a bloom should not be counting,
	// because a highlight is a picture of a light rather than a light.
	//
	// Left at zero on every path that never calls it - water and glass take
	// their reflection from TranslucentLighting instead - so the bloom simply
	// does not take that out. See BLOOM_EXCLUDE_SPECULAR in lib/bloom.glsl.
	vec3 specularInFrame = vec3(0.0);

	// Apply sRGB to linear conversion
	//
	// We do this after multiplying texture color with vertex color
	// and after including entity color (if applicable) as to mimic
	// Minecraft, as it does the same multiplications (incorrectly)
	// in sRGB color space.
	surfaceColor.rgb = SrgbToLinear(surfaceColor.rgb);

	// The color of the light this block gives off, if it is a light source, for
	// the bleed pass to spread onto the surfaces around it. Left black for
	// everything that is not a light source, which is what the pass reads as
	// "nothing glows here".
	vec3 emitterColor = vec3(0.0);

	// Skip all these lighting calculations if we are going to throw away the
	// result anyhow.
	#if defined(SKIP_ALPHA_TEST)
		if (fragmentColor.a > 0.01) {
	#endif
		#ifdef PBR_SURFACE
			// This is the first point at which the surface color is final, so
			// it is where albedo-based metals pick up their reflectance.
			pbr = PbrResolveAlbedo(pbr, surfaceColor.rgb);

			// How much of the diffuse response a metal keeps on a held item,
			// from none of it to all of it.
			//
			// A metal in the world reflects what is around it and has almost no
			// diffuse response of its own, and that trade is what makes it read
			// as metal - see PBR_METAL_DIFFUSE, which is where the response is
			// taken away. A held item cannot make the other half of that trade,
			// because it is not in the world the reflection is built from. Both
			// halves of that reflection were measured to leave a held item
			// looking like a window onto whatever is behind it, and refusing
			// both is what the neutral material below does; see §21 of
			// PBR_PORTING.md for the test that settled it.
			//
			// So an item made of metal has to keep some of what a metal in the
			// world gives up, or it has nothing left to show. With the
			// reflection refused and the diffuse response removed, a metal held
			// item is black whatever the light around it is doing - which is
			// what a held gold block was doing before this number existed.
			//
			// Half of it is a guess, and one to adjust by eye: the constant is
			// declared at the top of this file.
			//
			// The metalness is kept as well as scaled, so that the reflection
			// below is weighted by the material the resource pack authored
			// rather than by the adjusted one - the two would otherwise dim each
			// other by the same amount, and a metal item would be left dimmer
			// than either on its own.
			#if defined(PBR_HAND_ITEMS)
				float handMetalness = pbr.metalness;
				pbr.metalness *= 1.0 - PBR_HAND_METAL_DIFFUSE;
			#endif

			// Hand the material on to the environment reflection, which the
			// deferred pass applies. Set after the albedo is resolved so that a
			// metal reflects with the colour it actually has.
			reflectionNormal = pbrNormal;
			reflectionRoughness = pbr.roughness;
			reflectionF0 = pbr.f0;
			reflectionMetalID = pbr.metalID;

			// Surfaces drawn by the translucent pass have their own reflection
			// path in TranslucentLighting, which reflects the world as well as
			// the sky. Leaving them with no material here is what keeps the same
			// environment from being reflected twice, from two different places.
			#if defined(TRANSLUCENT)
				reflectionRoughness = 1.0;
				reflectionF0 = vec3(0.0);
				reflectionMetalID = 0.0;
			#endif

			// Everything drawn after the deferred pass is left out for a
			// sharper version of the same reason, and this is the rule the
			// three programs above already follow - water, Distant Horizons
			// water and Colorwheel's translucents all define AFTER_DEFERRED and
			// all write a neutral material here. The translucent entities were
			// the one that did not, and they are where the third-person player
			// is drawn: a player is a translucent entity, so the player, its
			// armour and whatever it holds arrive here rather than at
			// gbuffers_entities the way a mob does.
			//
			// What goes wrong without it is not a wrong reflection but a
			// reflection of nothing: colortex4 - the picture of the world the
			// reflections are sampled from - is copied by the deferred pass, and
			// the deferred pass is over by the time any of this geometry is
			// drawn. So the surface is in the depth buffer the ray marches and
			// not in the colour buffer it samples: the ray meets the surface
			// itself, and takes the colour of whatever is standing behind it.
			// A held item in third person showing the scene through itself is
			// exactly that, and it is what a held item and a held block differ
			// by - a block goes to gbuffers_entities and is drawn before the
			// copy is taken.
			//
			// There is nothing to give them instead. The trace would need a
			// depth buffer with the entities left out and a colour buffer with
			// them left in, and neither exists - the hand's reflection has the
			// first of those in depthtex2 and no need of the second, which is
			// why it could be done there and cannot be done here.
			#if defined(AFTER_DEFERRED)
				reflectionRoughness = 1.0;
				reflectionF0 = vec3(0.0);
				reflectionMetalID = 0.0;
			#endif

			// The hand is left out of the environment reflection for a reason of its
			// own: it is not part of the world that reflection is built from.
			//
			// The hand is a quad hanging in front of the camera, a foot from the eye,
			// with nothing behind it that the reflection pass can see. Both halves of
			// that pass therefore produce something that is not a reflection:
			//
			//   - The traced ray marches the world's depth buffer, which at these
			//     pixels holds the hand itself and at the pixels around them holds
			//     the world. It finds the world standing behind the item and paints
			//     that onto the item.
			//   - The sky reflection needs no depth at all. The item faces the
			//     camera, so its mirror direction points back past the eye, and the
			//     sky that lands on it is the sky behind the player.
			//
			// Either one leaves a held item showing the scene through itself - which
			// is what a material on a held item looked like it was doing - and turning
			// both off is the only configuration that reads correctly, so both are
			// off here.
			//
			// Nothing else is given up: the material still has its normal, its
			// roughness, its ambient response and the highlight the sun puts on it.
			// What is dropped is the part of the environment a fragment that sits
			// outside the world cannot reflect.
			#if defined(PBR_HAND_ITEMS)
				reflectionRoughness = 1.0;
				reflectionF0 = vec3(0.0);
				reflectionMetalID = 0.0;
			#endif
		#endif

		SurfaceFragment surface = SurfaceFragment(
			#if defined(REAL_TIME_SHADOWS)
				cameraRelativePos,
				// The projected shadowmap position to sample from.
				shadowPos,
			#endif
			// The linear RGB color of the surface at this position, including
			// all AO and tinting.
			surfaceColor.rgb,
			// The predefined material ID of this fragment.
			materialID,
			// The normal vector of the surface where this fragment is, in
			// world-space.
			#ifdef PBR_SURFACE
				// The normal-mapped normal, so that ambient lighting, direct
				// lighting and the subsurface scattering decision all agree
				// with the surface detail that is actually visible.
				pbrNormal,
			#else
				worldNormal,
			#endif
			// Where this fragment sits in the lightmap, which is where the
			// color of its block light comes from.
			lightMap,
			// The sky light strength, where 1 is light level 15 and 0 is no
			// light.
			skyLight,
			// The block light strength, where 1 is light level 15 and 0 is no
			// light.
			LightMapToLight(lightMap.x),
			// The held light strength, where 1 is light level 15 and 0 is no
			// light.
			HeldLightStrength(cameraRelativePos)
		);

		#ifdef PBR_SURFACE
			// The camera sits at the origin of camera-relative space, so the
			// view direction is simply the direction back towards the origin.
			vec3 viewDirection = normalize(-cameraRelativePos);

			fragmentColor.rgb = DiffuseLighting(surface, pbr, viewDirection, specularInFrame);

			// The reflection a held item is given, which is the one the world's
			// surfaces are given: the same direction, the same Fresnel, the same
			// smoothness gate, the same strength, and the same trace. See the
			// notes on the two buffers at the top of this file for what it is
			// traced against and why those and not the world's.
			//
			// It is applied here rather than in the deferred pass because the
			// deferred pass cannot tell the hand from the world - it must refuse
			// the hand - and because this is the one point in the frame at which
			// the item is known to be the item.
			//
			// What stood here two batches ago was a sky term with no trace
			// behind it, and it read as a wash of pale sky over the item: a
			// held item shows its faces to the camera, and a face turned towards
			// the eye reflects whatever is behind the player. The trace is what
			// answers that. The faces whose reflected ray leaves the item are
			// given the world; only the ones that genuinely point back past the
			// eye are left with the sky, which is what a mirror held up in front
			// of you would show as well.
			#if defined(PBR_HAND_ITEMS) && defined(PBR_SSR)
				// The camera sits at the origin of view space, so the item's
				// view position is its camera-relative position turned out of
				// the world's axes - the transpose of the matrix the geometry
				// was drawn with, which for a rotation is its inverse.
				mat3 handView = mat3(gbufferModelView);
				vec3 handViewPos = handView * cameraRelativePos;

				// The reflected direction, in view space - the space the depth
				// buffer the ray is marched through is in. The normal and the
				// view direction are both world-space, so what comes back is
				// turned out of the world's axes by the same matrix as the
				// position above.
				vec3 handViewReflected = handView * PbrReflectionDirection(
					pbrNormal,
					viewDirection,
					pbr.roughness);

				float handNdotV = max(dot(pbrNormal, viewDirection), 1.0e-4);

				vec3 handWeight = mix(
					PBR_REFLECTIONS_STRENGTH,
					PBR_METAL_REFLECTION_STRENGTH,
					clamp(handMetalness, 0.0, 1.0))
					* PbrReflectionFresnel(
						pbr.f0,
						PbrMetalF82(pbr.metalID),
						handNdotV,
						pbr.roughness)
					* PbrReflectionSmoothness(pbr.roughness, handMetalness);

				// What the item reflects: the world, and nothing where the ray
				// found none of it.
				//
				// There is no sky here, and that is deliberate rather than
				// unfinished. The world's reflection falls back to the sky
				// model, and a held item was given the same fallback first - but
				// the sky a face turned towards the camera reflects is the sky
				// behind the player, and over an item that is a wash of pale
				// blue rather than a reflection: on a gold apple it reads as the
				// item going white. It was the whole of what a held item showed
				// before the trace existed, which is why the trace was worth
				// asking for; with the trace there, the fallback is in the way
				// of it.
				//
				// So a pixel whose ray found nothing keeps what it already has -
				// its own diffuse response, and the ambient specular the surface
				// programs apply to every material - and only a pixel the ray
				// reached is given anything on top.
				vec3 handEnvironment = vec3(0.0);

				vec2 handHitPos;
				vec3 handHitViewPos;

				if (Raytrace(
					depthtex2,
					gbufferProjection,
					gbufferProjectionInverse,
					handViewPos,
					handViewReflected,
					vec2(0.5, 1.0),
					handHitPos,
					handHitViewPos
				) && length(handHitViewPos) > length(handViewPos)) {
					// Faded out near the edge of the screen, where the ray is
					// about to leave the buffer and there is nothing left to
					// find. The world's reflection does the same, for the same
					// reason, and with the same width.
					vec2 handHitAbs = abs(handHitPos * 2.0 - 1.0);
					float handHitFade = min(
						1.0,
						(1.0 - max(handHitAbs.x, handHitAbs.y)) / 0.10);

					handEnvironment =
						texture(colortex4, handHitPos).rgb * handHitFade;
				}

				fragmentColor.rgb += handWeight * handEnvironment;
			#endif
		#else
			fragmentColor.rgb = DiffuseLighting(surface);
		#endif

		// Emission, from both of the sources that can provide it.
		//
		// This is added on top of the lighting rather than being part of it: a
		// glowing block looks the same in a cave as it does in direct sunlight.
		// Adding it here rather than at the very end of the shader means that
		// fog, water absorption, and the reflections applied to translucent
		// surfaces all still apply to it, so a glowing block in the distance
		// fades into the fog rather than shining through it.
		#if !defined(COLORWHEEL)
			// Block self-emission, from the light source signal worked out above.
			//
			// Which block this is decides what color its light is, where the
			// block is one we know: a soul lantern burns blue and a torch does
			// not, even though both light their own faces the same way.
			//
			// This is also what the bleed pass spreads onto the surfaces around
			// each source, so it is computed even with self-emission turned off -
			// the two effects are separate, and the mask is only a comparison and
			// a lookup.
			vec3 emissiveColor = LightSourceSurfaceColor(
				materialID,
				surfaceColor.rgb);

			// Only the color of the source matters to the bleed; how bright the
			// bleed ends up is a control of its own, in the pass that applies it.
			emitterColor = emissiveColor * clamp(
				emissive * BLOCK_EMISSION_STRENGTH, 0.0, 1.0);

			#ifdef BLOCK_EMISSION
				fragmentColor.rgb += BLOCK_EMISSION_STRENGTH
					* emissive * emissiveColor;
			#endif
		#endif

		#ifdef PBR_SURFACE
			#ifdef PBR_EMISSION
				// Emission authored by the resource pack, which LabPBR stores in
				// the alpha channel of the specular map.
				//
				// It is weighted by two things, and both of them exist to keep
				// missing or meaningless data from turning a block into a lamp.
				//
				// The first is the same signal the block self-emission above is
				// built on - whether the game's own lighting treats this block as a
				// light source - and it is only applied when
				// PBR_EMISSION_ANY_BLOCK is off. On, which is the default, the
				// alpha channel decides on any block at all, because that is what
				// the channel is for: an ore is not a light source in the game, and
				// a pack that paints a glowing vein into one is asking for exactly
				// this. See the option in pbr.glsl for what turning it off protects
				// against.
				//
				// The second is how much of the pixel the fragment covers, which
				// is LabPBR's rule for cut-out materials: a pack that leaves the
				// gaps in a leaf, or the space around a tuft of grass, at alpha
				// zero is describing holes rather than asking for them to emit.
				float pbrEmission = pbr.emission;

				#ifndef PBR_EMISSION_ANY_BLOCK
					pbrEmission *= emissive;
				#endif

				fragmentColor.rgb += PBR_EMISSION_STRENGTH
					* pbrEmission * surfaceColor.rgb * fragmentColor.a;
			#endif
		#endif
	#if defined(SKIP_ALPHA_TEST)
		}
	#endif

	#if defined(TRANSLUCENT)
		// Programs with no material data pass PbrNone() and the face normal, so
		// that TranslucentLighting has one shape to compile in every case.
		PbrSurface translucentPbr = PbrNone();
		vec3 translucentNormal = worldNormal;

		#if defined(PBR_SURFACE)
			translucentPbr = pbr;
			translucentNormal = pbrNormal;
		#endif

		// The frame this face has, which a water surface is expressed in.
		//
		// Water needs the real thing rather than an assumed one: its waves are
		// a field that lives in the plane of the face, so the frame decides
		// which way they run across it, and on a face that is not lined up with
		// the world's axes an assumed frame lays them out wrong. The per-face
		// encoding is the only place a frame the geometry actually has can come
		// from - see /lib/encoding/face.glsl.
		//
		// Ice and glass never build a surface of their own - they reflect the
		// material the resource pack authored, against the face normal - so for
		// them this is only kept because the call has one shape.
		mat3 translucentTBN = DecodePerFaceWorldTBN(perFace, worldNormal);

		fragmentColor = TranslucentLighting(
			fragmentColor,
			worldNormal,
			translucentTBN,
			cameraRelativePos,
			viewPos,
			reflectionStrength,
			skyLight,
			materialID,
			translucentPbr,
			translucentNormal
		);
	#endif

	#if defined(APPLY_FOG)
		// Determining the fragment distance for fog
		float fogDistance = max(
			abs(cameraRelativePos.y),
			length(cameraRelativePos.xz));

		// FogV2 does not immediately require the sky color, which enables an
		// optimization where we skip the atmospheric fog (requiring the sky
		// color) at low fog strengths.
		float skyFogStrength;
		vec4 fog = FogV2(skyFogStrength, fogDistance, fogDistance, skyLight);

		fragmentColor.rgb = mix(fragmentColor.rgb, fog.rgb, fog.a);

		// And the highlight recorded for the bloom fades by the same amount.
		// The mix above is linear, so the part of the frame the highlight
		// contributes is exactly this much of what was recorded; leaving it
		// unfaded would have the bloom subtract more highlight than the frame
		// still holds wherever the fog is thick, and what that looks like is
		// patches of missing glow in the distance rather than fog.
		specularInFrame *= 1.0 - fog.a;

		// FogV2 instead just tells us the amount of sky color to add in to the
		// final fogged fragment color, so we can skip computing the sky color
		// when we do not need to add in any of the sky color.
		//
		// This can actually be quite impactful with the new Minishita sky model
		// and when looking at a lot of water, since we have to compute the sky
		// color twice (once for reflection, once for fog) otherwise and this
		// is basically as if the sky color calculation was twice as fast.
		skyFogStrength *= fog.a;

		if (skyFogStrength > 0.0) {
			vec3 sky = SkyDither(
				gl_FragCoord.xy, 
				SkyColor(normalize(cameraRelativePos)));
			fragmentColor.rgb += sky * skyFogStrength;
		} else {
			// Tints terrain receiving lit.fsh fog that did not require the sky
			// color
			// #define DEBUG_FOG_OPTIMIZATION
			#ifdef DEBUG_FOG_OPTIMIZATION
				fragmentColor.rb = vec2(0.0);
			#endif
		}

		// We also fade away the background (effectively, because we need to
		// blend it with the fog, too) based on the same factor used to fade
		// away the fragment color.
		fragmentColor.a = mix(fragmentColor.a, 1.0, fog.a);
	#endif

	#if defined(PBR_SURFACE) && PBR_DEBUG != PBR_DEBUG_NONE
		// The material debug view replaces the shaded image entirely, so that it
		// shows the data the resource pack provides rather than something the
		// lighting has already been applied to. The light source mask goes with
		// it, so that the bleed pass does not tint the debug view.
		//
		// Worked out here rather than where the material was decoded, because
		// the emission view also needs the light source signal, and that is only
		// known once the lightmap has been read.
		vec3 pbrDebugColor = PbrDebugColor(
			pbrFrame,
			pbrTexCoord,
			pbr,
			pbrGradients,
			emissive);

		#if PBR_DEBUG == PBR_DEBUG_PARALLAX && defined(PBR_PARALLAX)
			// A diagnostic rather than a material view; see the option. It draws
			// the three quantities that decide whether a surface gets parallax at
			// all, so that a face where the effect is missing can be told apart
			// from one where it is merely subtle:
			//
			//   red   - the offset the ray starts with (before the march);
			//   green - the displacement the march returned;
			//   blue  - the distance fade, which is how much of the effect this
			//           fragment is allowed in the first place.
			//
			// Both distances are shown as a fraction of the sprite the fragment
			// belongs to, not in raw texture coordinates, so that the reading means
			// the same thing whatever resolution the pack's atlas has. A fixed
			// scale cannot do that: the same displacement is a large number of
			// texture coordinate units in a 256-wide atlas and a tiny one in a
			// 4096-wide atlas, which on a big atlas leaves both channels so dim
			// that the view looks like it is not reporting anything at all.
			//
			// The caps hold the offset to half a sprite, so half a sprite is a full
			// red. The square root stretches the low end: a tenth of a sprite is a
			// third of the channel rather than a tenth of it, which is what makes a
			// small offset readable next to a large one.
			vec2 parallaxDisplacement = abs(pbrTexCoord - texcoord);
			float parallaxScale = 256.0;

			#ifdef PBR_ATLAS
				if (all(greaterThan(spriteBounds.zw, vec2(0.0)))) {
					parallaxScale =
						1.0 / max(spriteBounds.zw.x, spriteBounds.zw.y);
				}
			#endif

			float parallaxOffsetDebug = sqrt(clamp(
				pbrParallaxOffset * parallaxScale, 0.0, 1.0));
			float parallaxResultDebug = sqrt(clamp(
				max(parallaxDisplacement.x, parallaxDisplacement.y)
					* parallaxScale,
				0.0,
				1.0));
			float parallaxReachDebug = clamp(
				PbrParallaxStrength(cameraRelativePos), 0.0, 1.0);

			pbrDebugColor = vec3(
				parallaxOffsetDebug,
				parallaxResultDebug,
				parallaxReachDebug);
		#elif PBR_DEBUG == PBR_DEBUG_PARALLAX
			// Parallax mapping is off, so there is nothing to measure and all
			// three channels of the diagnostic would read zero. A solid magenta
			// says that instead of saying "no displacement", which is the
			// difference between a setting that was never turned on and a
			// surface that genuinely gets none.
			pbrDebugColor = vec3(1.0, 0.0, 1.0);
		#endif

		fragmentColor = vec4(pbrDebugColor, 1.0);
		emitterColor = vec3(0.0);
	#endif

	// The buffers this program writes: the shaded color, the sky light the
	// deferred pass reads for refraction and reflections, and the light source
	// mask the bleed pass spreads.
	//
	// The light source mask has to be recorded here rather than recovered from
	// the finished image later: block light in this pack is bright, so a wall
	// lit by a torch is brighter than the torch itself, and no threshold on
	// brightness can tell a light source from the light it casts.
	//
	// Note that this is one fixed list rather than a different list per
	// configuration, as it used to be. Programs that have no use for the sky
	// light - the translucent ones, which run after the only pass that reads it
	// - write it regardless, which costs nothing that anything can observe.
	// Keeping the list the same for every program means the attachments can
	// never disagree with the writes, which is the failure a conditional list
	// risks and which would be very hard to see: the writes would land in
	// whichever buffers the directive happened to name.
	// The selection outline's own colour, when it has one.
	//
	// ⚠️ Overridden here, immediately before the writes, rather than returned
	// early somewhere above - and the reason is the fixed list of attachments
	// this file keeps. A fragment that returned after writing gl_FragData[0]
	// alone would leave the other five buffers holding whatever was in them from
	// the last thing drawn at that pixel: stale skylight, stale reflection
	// material, a stale specular highlight for the bloom to subtract. Letting the
	// shader run to the end and changing only the colour is what keeps every
	// write paired with a value.
	//
	// ⚠️ And the colour is written several times over its own brightness, which
	// is what the bloom turns into the glow - see SELECTION_GLOW_STRENGTH where
	// it is defined, including what it costs.
	// ⚠️ The guard is on the macro's own name, and the macro is defined by the
	// selection box options only when there is something to write - so this block
	// is compiled in the one program that draws lines and dropped in the other
	// fourteen. See where it is defined for why the guard is written this way
	// rather than as a test on that program's flag.
	#if defined(SELECTION_BOX_OVERRIDE)
		SELECTION_BOX_OVERRIDE
	#endif

	gl_FragData[0] = fragmentColor;
	gl_FragData[1] = vec4(skyLight);
	gl_FragData[2] = vec4(emitterColor, 1.0);

	// The material the deferred pass reflects the environment with: the normal
	// to reflect around, how rough the surface is, and its reflectance. Written
	// for every surface program, with the neutral values from the top of main()
	// wherever there is no material to speak of.
	//
	// These two buffers are paid for whether or not the reflection options are
	// on, which is the price of the fixed list below and cheaper in the end than
	// a list that changes with the options - see the note above.
	gl_FragData[3] = vec4(reflectionNormal, reflectionRoughness);

	// The metal ID rides in the alpha channel of the reflectance, which was
	// written as a hard zero before there was anything to put there. The byte it
	// is divided by is the byte it came from, so the eight-bit buffer carries it
	// without loss - see PbrMetalF82 for what reads it back.
	gl_FragData[4] = vec4(reflectionF0, reflectionMetalID / 255.0);

	// The specular highlight, for the bloom to take back out. Written by every
	// program that comes through here and zero wherever there was no highlight,
	// so that the bloom is never reading a stale highlight under a surface that
	// has stopped reflecting.
	//
	// Paid for whether or not the bloom option that reads it is on. That is the
	// same bargain the two buffers above are on, and for the same reason: the
	// list at the bottom of this file is fixed, so that the attachments can
	// never disagree with the writes. See the note there.
	gl_FragData[5] = vec4(specularInFrame, 1.0);

	/* RENDERTARGETS: 0,2,6,7,8,15 */
}
