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

#define REAL_TIME_SHADOWS // Whether real-time shadow mapping is enabled.
#ifndef REAL_TIME_SHADOWS
	#define NEVER_RECEIVES_SHADOWS
#endif

// Water clipping hack for refraction assisted water absorption
#if defined(ALLOW_CLIPPING_WATER_TO_COVER_SCREEN)
	// Water absorption configuration.
	#include "/environment/water/absorption_settings.glsl"

	#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
		// Used for the clipping hack at the bottom for refraction-assisted
		// water absorption.
		uniform int isEyeInWater;

		// Workaround for when the camera is intersecting water but can see some
		// underwater terrain without isEyeInWater reflecting this.
		#define CLIP_WATER_TO_COVER_SCREEN // Clipping hack to cover the screen.
	#endif
#endif

// Note: **the conditionals below** use #if defined instead of #ifdef on purpose:
// Iris recognises a boolean option only where it is checked with #ifdef or
// #ifndef, so a name that is only ever met through #if defined never becomes one
// and never reaches the settings screen. That is what is wanted for the
// *conditions* - they are the pack's own internal switches, not user choices.
//
// It does not apply to the #define on line 36: an option is *declared* by a
// #define line wherever that line is written, and CLIP_WATER_TO_COVER_SCREEN has
// one. What keeps it out of the menu is that no screen.* line names it, which is
// the only thing keeping it out.
#if defined(HAS_BLOCK_ATTRIBUTES)
	// Block identification
	in vec4 mc_Entity;
	in vec3 at_midBlock;
#endif

// The tangent this vertex's geometry actually has, with the handedness that
// fixes which way the bitangent points carried in w.
//
// It arrives in the same space as the normal, and is brought to world space the
// same way FetchWorldNormal brings that there, further down this file. The two
// attributes come from the same place, so whatever reasoning applies to one
// applies to the other.
//
// Minecraft's entity format carries no tangent at all, and some mods leave it
// at zero, so neither stage that uses this may assume it is there: the per-face
// encoding below replaces a degenerate tangent with one derived from the face,
// because the encoder normalizes what it is handed, and the material decoding
// falls back to a frame built from screen-space derivatives - see
// PbrAttributeFrame in pbr.glsl.
in vec4 at_tangent;

#ifdef PBR_ATLAS
	// Where this face's sprite sits in the block atlas, on the vertex buffer's
	// own side of the texture matrix: the middle of the sprite, in the same space
	// gl_MultiTexCoord0 arrives in.
	//
	// It is the middle of the *quad's* texture and not of the whole sprite - the
	// two are the same for the full-sprite quads a block model is made of, and
	// for a quad that covers part of its sprite, such as the side of a slab, this
	// is the middle of the part it covers. Either way the distance from it to any
	// corner of the quad is half of what the quad covers, which is what the
	// fragment stage wants: the displacement may move the coordinate anywhere the
	// quad is drawn, and no further.
	//
	// Iris and OptiFine supply this for every gbuffers vertex stage, and the pack
	// reads it under PBR_ATLAS - which is what marks a program whose coordinates
	// are meant to index an atlas. That is the block atlas for the block
	// programs, and gbuffers_entities, which takes the same route as an
	// experiment on whether the loaders build material maps beside an entity's
	// own texture. The entity program that takes PBR_MATERIALS_ANY_TEXTURE
	// instead has no atlas to sit in and writes a zero half extent below.
	in vec2 mc_midTexCoord;
#endif

// The varying below is needed by whatever program reads material maps, which is
// the block atlas programs and the entity programs that opted in through
// PBR_MATERIALS_ANY_TEXTURE.
#if defined(PBR_ATLAS) || defined(PBR_MATERIALS_ANY_TEXTURE)

	// The tangent on its way to the material decoding, in world space and with
	// the handedness in w.
	//
	// That frame is the one the material decoding prefers, because unlike one
	// rebuilt from screen-space derivatives it does not depend on how far away
	// the fragment is. The fragment stage still has to check for the degenerate
	// case, which is the only reason this is passed on rather than assumed.
	out vec4 pbrTangent;

	// The sprite this vertex's coordinate belongs to, in the atlas space texcoord
	// is in: the middle of the sprite in xy, and how far it reaches from that
	// middle in zw.
	//
	// This is what tells the parallax march which rectangle the coordinate it is
	// walking belongs to. Past the edge of a sprite the atlas holds a neighbouring
	// block's sprite, or the black the material atlases are built with, and a
	// sample taken there reads the material of a block that is not there - which
	// shows up as a band of the neighbouring block along the edge of every face.
	// The fragment stage wraps the coordinate back into this rectangle rather than
	// shortening the displacement to stay inside it, because the pattern a block
	// face is drawn with tiles with itself across block boundaries: see
	// PbrParallaxWrap.
	//
	// A program that has no such attribute to read writes a zero half extent
	// instead, which the fragment stage takes as "there are no bounds here" -
	// see PBR_MATERIALS_ANY_TEXTURE below.
	out vec4 pbrSpriteBounds;
#endif

#if !defined(COLORWHEEL)
	// The interpolated vertex color directly from the vertex buffer.
	out vec4 tinting;

	// The lightmap texture coordinates. The x / "s" component is the block
	// light and the y / "t" component is the sky light, as in vanilla.
	//
	// Their range is a texel-centre range and not 0 to 1: the light levels are
	// the sixteen texel centres of the lightmap texture, (i + 0.5) / 16, so the
	// low value is 0.03125 and the high one 0.96875. That is the convention
	// lib/encoding/lightmap.glsl inverts - it subtracts half a texel and
	// rescales by 16/15 to get 0 to 1 back - and it follows from that
	// function's arithmetic rather than from anything in this file.
	//
	// This is the value as it arrives; see the assignment in main for the
	// texture matrix that is applied to it on the way.
	out vec2 lightMap;
#endif

#if !defined(NO_GTEXTURE)
	// The interpolated texture coordinate, taken through the texture matrix.
	//
	// "Through the texture matrix" is the part that matters to a reader: this is
	// a place in the block atlas and not a place on the sprite, which is what
	// the assignment in main makes it, and it is what makes the two weather
	// varyings below necessary. The coordinate from the vertex buffer is not
	// carried on under this name anywhere.
	out vec2 texcoord;
#endif

#if defined(WEATHER)
	// Where the rain and snow sprites sit inside the block atlas.
	//
	// The coordinate the fragment shader receives has already been through the
	// texture matrix, so it names a place in the atlas rather than a place on
	// the sprite. Tiling that coordinate walks straight off the sprite and
	// samples whichever block happens to be the atlas neighbour of the rain,
	// so the two pieces needed to undo the trip - the sprite-local coordinate,
	// and how big the sprite is in atlas space - are measured here, where the
	// matrix is still in hand, and carried across for RAIN_DROP_AMOUNT to use.
	out vec2 weatherSpriteCoord;
	out vec2 weatherSpriteScale;
#endif

#if !defined(NEVER_RECEIVES_SHADOWS)
	// The projected shadowmap position to sample from.
	//
	// X and Y are coordinates in the shadowmap texture, and Z is the
	// depth value to compare the sampled shadow depth against to
	// determine to what extent the fragment is or is not in shadow.
	out vec3 shadowPos;

	// Shadow distortion
	#include "/lib/distort.glsl"

	uniform mat4 shadowProjection;
	uniform mat4 shadowModelView;
	uniform vec3 worldLightVector;
#endif

// Per-face data encoded by EncodePerFace (/lib/encoding/face.glsl)
#include "/lib/encoding/face.glsl"
#include "/environment/materialIDs.glsl"
flat out uint perFace;

// Temporal anti-aliasing: the sub-pixel offset this frame is rendered with.
// Uniforms: frameCounter, viewWidth, viewHeight, and taaJitter, which is not
// declared here - shaders.properties computes it and declares it as a custom
// uniform - but is what TaaJitter() returns.
#include "/lib/taa.glsl"

#if defined(HAS_WAVING_FOLIAGE)
	#define WAVING_FOLIAGE // Waving foliage (optional but basically free).

	uniform vec3 cameraPosition;

	// WindDisplacement
	#include "/environment/wind.glsl"

	void WaveFoliage(uint materialID, inout vec4 cameraRelativePos) {
		// at_midBlock.xyz is the offset from this vertex to the centre of its
		// block in 1/64 block units - not in blocks, and not the distance in
		// blocks. The attribute the loader supplies is a vec4 whose w is the
		// block's own light level (Iris 1.7 and later); the declaration above
		// takes only the xyz, so that component is not readable here and
		// nothing here wants it. Read these numbers as 1/64-block offsets and
		// the test below is "is this vertex at the top of its block's column".
		//
		// So if these are the top vertices, then the offset to the center
		// will be negative as the center is below these vertices.
		bool topOfFoliage = at_midBlock.y < 0.0;
		bool wavingGroundFoliage = materialID == GROUND_FOLIAGE;
		bool wavingLeaves = materialID == LEAVES;

		if (wavingLeaves || (wavingGroundFoliage && topOfFoliage)) {
			vec3 worldPos = cameraRelativePos.xyz + cameraPosition;
			vec3 displacement = WindDisplacement(worldPos);
			displacement.y = wavingGroundFoliage ? 0.0 : displacement.y;
			cameraRelativePos.xyz += displacement;
		}
	}
#endif

uint FetchMaterialID(vec3 worldNormal) {
	#if defined(HAS_BLOCK_ATTRIBUTES)
		uint materialID = DecodeMaterialID(mc_Entity.x);

		#if defined(TRANSLUCENT) || defined(TRANSLUCENT_LIGHTING)
			if (materialID == GENERIC) {
				// Use a slightly different lighting approximation for
				// translucents, as traditional directional lighting as
				// implemented below looks odd as our translucents don't cast
				// shadows and let a lot of light pass through.
				//
				// For now, use the same lighting as glass by treating all
				// unknown translucents as glass.
				//
				// "Translucents" here means what the #if above says: this
				// branch is compiled for TRANSLUCENT and TRANSLUCENT_LIGHTING,
				// and for a program that defines neither, GENERIC keeps its
				// own material ID.
				return GLASS;
			}

			if (materialID == NETHER_PORTAL) {
				// The nether portal has an ID of its own so that the shadow
				// program can recognise it and tint the light around it with the
				// colour of its glow - see NETHER_PORTAL in
				// /environment/materialIDs.glsl for the number and why it is
				// shaped the way it is.
				//
				// What it asks for here is the material it already had. A portal
				// is drawn in the translucent pass and, before it had an ID,
				// arrived here as GENERIC and was handed GLASS by the branch
				// above; this says the same thing outright instead of leaving it
				// to the low four bits of the portal's number working out to the
				// same 6. Nothing but the portal can carry that number - it is
				// the only block.properties entry that has ever used it - so no
				// other block can reach this line, and every other block leaves
				// this function through exactly the branches it always did.
				return GLASS;
			}
		#endif

		uint geometrySelector = materialID >> 4u;

		if (geometrySelector == GEOMETRY_HORIZONTAL_DIAGONAL_ONLY) {
			bool horizontal = abs(worldNormal.y) < 0.01;
			bool diag = abs(worldNormal.x) < 0.95 && abs(worldNormal.z) < 0.95;
			
			return horizontal && diag ? materialID & 0xFu : GENERIC;
		}

		return materialID;
	#elif defined(HAS_DH_MATERIAL_ID)
		if (dhMaterialId == DH_BLOCK_LEAVES) {
			return LEAVES;
		} else if (dhMaterialId == DH_BLOCK_WATER) {
			return WATER;
		} else {
			return GENERIC;
		}
	#else
		return GENERIC;
	#endif
}

uniform mat4 gbufferModelView;
uniform mat4 gbufferModelViewInverse;

vec3 FetchWorldNormal() {
	#if defined(NORMALS_ARE_IN_WORLD_SPACE)
		// If gl_Normal is already in world space, then skip two matrix-vector
		// multiplies that are otherwise completely unnecessary!
		return gl_Normal;
	#else
		// Otherwise, get the view-space normal and then convert to world-space
		// by multiplying with the inverse view matrix. What gl_NormalMatrix is
		// defined in is the loader's business, not something this file can
		// check; the reason this branch exists is that it is not world space,
		// and the `NORMALS_ARE_IN_WORLD_SPACE` branch above is how a program
		// says it is.
		//
		// We pass up on that optimization opportunity since entities are
		// generally not vertex shader bound and mods can do whatever they want,
		// we can really only make the assumption safely on terrain.
		//
		// Note that technically, the normal matrix SHOULD be:
		//
		// transpose(inverse(gbufferModelViewInverse))
		// = transpose(gbufferModelView)
		//
		// Otherwise, we apply the wrong transformation when the view matrix
		// is not just a rotation, translation, uniform scaling, or combination,
		// notably when under the nausea effect. **Recorded observation, not
		// something this pack can demonstrate**: it was found that the
		// "correct" matrix seemed to give the same result under nausea - which
		// would mean Iris or Minecraft do not handle this properly - and on that
		// basis the extra cost was not paid. The identity above is arithmetic
		// and holds; the observation about nausea is the part that would need
		// re-measuring before anyone relies on it.
		vec4 homogenousNormal = vec4(gl_NormalMatrix * gl_Normal, 0.0);
		return (gbufferModelViewInverse * homogenousNormal).xyz;
	#endif
}

#if !defined(NEVER_RECEIVES_SHADOWS)
	vec3 ShadowMapPosition(vec4 cameraRelativePos, vec3 worldNormal) {
		float NdotL = dot(worldNormal, worldLightVector);

		// Shadow bias method inspired by:
		//
		// - Complementary Reimagined by Emin:
		//   https://github.com/ComplementaryDevelopment/ComplementaryReimagined
		//   
		//   File /shaders/lib/lighting/mainLighting.glsl#L150-L154 as of commit
		//   b511bc03e3fd27023d8ea649e8621bb485518c43
		//
		// - Photon by SixthSurge:
		//   https://github.com/sixthsurge/photon
		//   
		//   File /shaders/include/light/distortion.glsl#L31-L47as of commit 
		//   e253cefc5ff1382f5758834a2d293749a814c724
		//
		// We do this a bit differently. I observed that varying the offset
		// along the normal vector is not only necessary, but rather directly
		// related to shadow distortion.

		// First, transform the position using the shadow matrices. We use the
		// same length calculation, but depart by keeping this variable term
		// separate. Multiplying it by 1.5 was a hack necessary to remove acne
		// on far-away mountain tops.
		vec4 shadowViewPosDistort = shadowModelView * cameraRelativePos;
		vec3 shadowPosDistort = (shadowProjection * shadowViewPosDistort).xyz;
		float distanceFactor = 1.5 * length(shadowPosDistort.xy);

		// However, for the fixed term, we decrease it for faces towards the
		// light to prevent artifacts at closer distances where shadows appear
		// out of sync on different sides of blocks.
		distanceFactor += SHADOW_DISTORT_FACTOR * (1.0 - max(NdotL, 0.0));

		// Finally, offset the shadow map sampling position along the surface
		// normal, accounting for distortion effects and the facing. This allows
		// us to have an adaptive shadow bias that gives us the best of both
		// worlds - no acne, but also no peter panning.
		vec4 shadowBias = vec4(worldNormal * distanceFactor, 0.0);

		// Project to NDC space
		vec4 shadowViewPos = shadowModelView * (cameraRelativePos + shadowBias);
		vec3 shadowPos = (shadowProjection * shadowViewPos).xyz;

		// Distort relative to the center of the shadow map
		shadowPos = distort(shadowPos);

		// Viewport transform: convert from (-1, 1) space to (0.0, 1.0) texture
		// space
		shadowPos = shadowPos * 0.5 + 0.5;

		// Very minor fixed depth bias because we have normal depth bias.
		shadowPos.z -= 0.00001;

		return shadowPos;
	}
#endif

void main() {
	vec4 viewPos = gl_ModelViewMatrix * gl_Vertex;

	// This is effectively as if we multiplied with the model matrix, because we
	// do not get the model matrix separate from the model view matrix.
	//
	// gbufferModelView is a misnomer, it is actually just the view matrix. Same
	// with gbufferModelViewInverse - it is the inverse view matrix.
	// 
	// So the inverse of the view matrix times the model view matrix is the
	// model matrix, which gives us camera-relative coordinates.
	vec4 cameraRelativePos = gbufferModelViewInverse * viewPos;

	// Colorwheel passes its own copies of these values and provides them for us
	// in the material shader we evaluate in the fragment shader, so there is no
	// need for us to pass our own copy in this case.
	#if !defined(COLORWHEEL)
		tinting = gl_Color;
		lightMap = (gl_TextureMatrix[1] * gl_MultiTexCoord1).xy;
	#endif

	#if !defined(NO_GTEXTURE)
		texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;

		#if defined(WEATHER)
			// The texture matrix is a scale and a translation, nothing more, so
			// two points recover it in full: the sprite's own origin, and its
			// far corner.
			weatherSpriteCoord = gl_MultiTexCoord0.xy;

			vec2 weatherAtlasOrigin = (gl_TextureMatrix[0] * vec4(0.0, 0.0, 0.0, 1.0)).xy;
			weatherSpriteScale = (gl_TextureMatrix[0] * vec4(1.0, 1.0, 0.0, 1.0)).xy - weatherAtlasOrigin;
		#endif
	#endif

	#if defined(PBR_ATLAS) || defined(PBR_MATERIALS_ANY_TEXTURE)

		// The geometry's tangent, brought into world space exactly the way
		// FetchWorldNormal brings the normal there - the two attributes arrive
		// in the same space, so whatever reasoning applies to one applies to the
		// other.
		//
		// The length is measured first rather than an offset being added before
		// normalizing, which is what this used to do: normalizing a zero vector
		// is undefined, so an offset kept that from happening - but it also
		// turned the zero into a perfectly good unit vector pointing one fixed
		// way, and the fragment stage's degenerate test, which is a length test,
		// then had nothing left to detect. A zero tangent is not a hypothetical
		// case: Minecraft's entity format has no tangent attribute at all, so
		// every entity arriving here carries one, and every one of them was
		// getting a frame built around that arbitrary direction.
		//
		// Passing the zero through instead costs nothing - a zero vector
		// transforms to a zero vector, whichever branch below runs - and leaves
		// the fragment stage free to fall back to the derivative frame, which is
		// the frame an entity should have.
		vec3 tangentDirection = vec3(0.0);
		float tangentLength = length(at_tangent.xyz);
		if (tangentLength > 1.0e-6) {
			tangentDirection = at_tangent.xyz / tangentLength;
		}

		#if defined(NORMALS_ARE_IN_WORLD_SPACE)
			vec3 worldTangent = tangentDirection;
		#else
			vec3 worldTangent = (gbufferModelViewInverse * vec4(
				gl_NormalMatrix * tangentDirection,
				0.0)).xyz;
		#endif

		pbrTangent = vec4(worldTangent, at_tangent.w);

		#ifdef PBR_ATLAS
			// Both points taken through the texture matrix, because the matrix is
			// what turns the vertex buffer's coordinates into the atlas
			// coordinates the fragment stage samples with - and because taking
			// the two through the same matrix is what makes their difference
			// meaningful whatever the matrix happens to be. gl_MultiTexCoord0 is
			// written out rather than read from texcoord so that a program with
			// NO_GTEXTURE, which has no texcoord, still has bounds.
			vec2 spriteCoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
			vec2 spriteMid = (gl_TextureMatrix[0] * vec4(mc_midTexCoord, 0.0, 1.0)).xy;

			// Every corner of a rectangular quad is the same distance from the
			// middle of it, so this is one value across the whole face and
			// interpolating it costs nothing but the two registers. The parallax
			// march reads it as the half extent of the sprite the coordinate
			// belongs to.
			pbrSpriteBounds = vec4(spriteMid, abs(spriteMid - spriteCoord));
		#else
			// This program reads material maps without a block atlas under them -
			// an entity's own texture is the material's texture - and has no mid
			// texture coordinate to measure a sprite from. A zero half extent is
			// how it says so; see PbrSpriteBoundsUsable, which is also where the
			// consequence is written down: the parallax depth is a fraction of a
			// sprite, so a program with no sprite gets no displacement.
			pbrSpriteBounds = vec4(0.0);
		#endif
	#endif

	vec3 worldNormal = FetchWorldNormal();
	uint materialID = FetchMaterialID(worldNormal);

	// Note: The vertex normal isn't actually guaranteed to be the same for all
	// vertices of a triangle, but this is the case in practice for almost all
	// mods and even Iris makes this assumption. The only case I know of that
	// breaks this assumption is PhysicsMod snow which has smooth normals.
	//
	// TODO: Allow some geometry to have smooth normals (like PhysicsMod snow),
	// I wonder if this could be done with manual interpolation in the fragment
	// shader / barycentrics instead of just giving up and passing in the full
	// normal or even TBN matrix through varyings.

	// The frame this face has, for the fragment stage to rebuild: its tangent,
	// the way its bitangent points, and its normal.
	//
	// The tangent is only meaningful against the normal of the face it lies in,
	// which is the face normal this is paired with - not the interpolated one a
	// smooth surface would have.
	//
	// Geometry that carries no tangent at all - Minecraft's entity format, some
	// mods - is given one derived from the face normal instead. It has to be
	// given something: EncodePerFace normalizes the tangent it is handed
	// (face.glsl, in the "express the tangent as a linear combination" step),
	// and normalizing a zero vector is undefined - so what this owes the
	// encoder is a tangent that is not zero, not one that is already unit
	// length. Any tangent in the face's plane is as good as any other for
	// geometry that did not author one, so the one both stages can arrive at on
	// their own is the one to use, which is what OrthonormalBasisOf returns.
	// Named apart from the worldTangent inside the PBR_ATLAS block above: that
	// block's own variable is in this same scope whenever the option is on, and
	// a second declaration of the same name would not compile.
	vec3 tangentAttribute = at_tangent.xyz;
	bool tangentHandedness = at_tangent.w > 0.0;
	vec3 faceTangent;

	if (dot(tangentAttribute, tangentAttribute) < 1.0e-8) {
		faceTangent = OrthonormalBasisOf(
			worldNormal,
			worldNormal.z >= 0.0 ? 1.0 : -1.0)[0];
	} else {
		#if defined(NORMALS_ARE_IN_WORLD_SPACE)
			faceTangent = tangentAttribute;
		#else
			faceTangent = (gbufferModelViewInverse
				* vec4(gl_NormalMatrix * tangentAttribute, 0.0)).xyz;
		#endif
	}

	perFace = EncodePerFace(
		worldNormal, faceTangent, tangentHandedness, materialID);

	#if !defined(NEVER_RECEIVES_SHADOWS)
		shadowPos = ShadowMapPosition(cameraRelativePos, worldNormal);
	#endif

	#ifdef WAVING_FOLIAGE
		WaveFoliage(materialID, cameraRelativePos);
		viewPos = gbufferModelView * cameraRelativePos;
	#endif

	#ifdef LOWER_DISTANT_WATER_HEIGHT
		if (materialID == WATER) {
			// By default, Distant Horizons renders water as a full block. This
			// leads to a more abrupt transition, so this is a hack to lower the
			// distant water faces to the same height as normal water faces.
			cameraRelativePos.y -= 2.0 / 16.0;
			viewPos = gbufferModelView * cameraRelativePos;
		}
	#endif

	// Transform to clip position.
	gl_Position = gl_ProjectionMatrix * viewPos;

	// Temporal anti-aliasing: shift this frame's sample position inside the
	// pixel. Scaling by w keeps the offset constant in pixels rather than in
	// world space.
	gl_Position.xy += TaaJitter() * gl_Position.w;

	#ifdef CLIP_WATER_TO_COVER_SCREEN
		// This is a fairly novel hack to overcome a minor, but extremely
		// noticeable limitation of our water absorption method.
		//
		//To reiterate, we rely on two methods of applying absorption:
		//
		// 1. When in water, we apply water absorption to everything.
		// 2. When not in water, we apply absorption to everything behind a
		//    refractive water surface.
		//
		// What happens when both are the case? That is, we are half-submerged,
		// with the upper half of the screen viewing above water, and the lower
		// half underwater?
		//
		// (1) will not apply any absorption because we are not actually fully
		//     underwater yet.
		// (2) will not apply absorption to the lower half, because that half of
		//     the screen is not behind a refractive water surface.
		//
		// This otherwise results in a quite visible flash of underwater terrain
		// brightly lit as if outside in broad daylight, before we actually
		// cross below the water surface and apply absorption. This problem
		// affects almost every shader pack, and even vanilla Minecraft. But, it
		// looks way more noticeable than vanilla due to how our lighting works.
		//
		// Try it yourself - run this command and see how nearly every shader
		// pack looks bugged:
		//
		// /tp @p ~ 61.26889 ~ 0 0
		//
		// The reason why this happens is that while we should be able to see a
		// water surface in front of us before we actually hit underwater, that
		// portion of the surface gets hidden by near-plane clipping (and other
		// things) - that is, the surface is behind the 0.05 meter near plane.
		// Unfortunately, while Iris or vanilla Minecraft could utilize depth
		// clamping or some other method to ensure that this does not happen, we
		// cannot really influence clipping from the shader side.
		//
		// Keyword "really" - we still can influence clipping! Essentially, if
		// we are NOT yet underwater, we can detect when this vertex is going to
		// be clipped by the near clipping plane based on the depth (z) of the
		// vertex. If it would be clipped (outside of -1 to 1 in NDC), then we
		// clamp the NDC z-coordinate to -1.0 by setting the clip-space
		// z-coordinate to -w.
		//
		// This gets us some of the way there, but then we have the jagged edges
		// of triangles on screen, as their neighbors were culled due to being
		// off-screen entirely. This gets us to the second part - we move the
		// Y coordinate to very far below the screen, effectively stretching the
		// triangle downwards. As a result, we basically stretch the would-be
		// clipped geometry to cover the whole bottom half of the screen.
		//
		// This does NOT work when the player is looking more than 45 degrees
		// downwards, as in that case the water faces are clipped off screen
		// entirely on the vertical axis. But this is better than nothing!
		// In my personal testing, this fix is good enough that the problem is
		// no longer noticeable, and we basically need to make zero sacrifices
		// in terms of performance (ie, reworking water to use a more expensive
		// and more robust method) or in terms of compatibility (ie, requiring a
		// very specific shader mod version). Sometimes, a well executed hack is
		// just good engineering, and this is one of those times!
		if (materialID == WATER
			// If we are not already in water...
			&& isEyeInWater == 0
			// If we would be clipped due to the depth being too close to the
			// camera...
			&& gl_Position.z < -gl_Position.w
			// But, we would NOT be clipped on the Y axis already in either
			// direction...
			&& abs(gl_Position.y) < abs(gl_Position.w)
			// And if the face is facing upwards...
			&& worldNormal.y > 0.9999
			// And, if flat, this face must also be high enough that it is not
			// just the flat center of flowing water as well.
			//
			// at_midBlock.xyz is the offset from the vertex to the centre of
			// its block in 1/64 block units. (The loader's attribute is a vec4
			// whose w is the block's light level; the declaration above takes
			// only the xyz, so that component is not readable here.) Because
			// the top face of still water is above the
			// center, this is negative as the center of the block is below.
			// So, this actually means: is this vertex more than 23/64th of a
			// block above its center?
			//
			// The numbers, in those units. Vanilla's still water has its top
			// face 2/16 of a block below the top of the block, which is 24/64
			// above the centre - so a threshold of 24/64 would be the exact
			// value. Flowing water whose centre is not raised sits at 20/64.
			// 23/64 is one unit under the exact value: enough room for the
			// side faces of still water to pass, and still above the 20/64 of
			// a flat flowing centre.
			&& at_midBlock.y < -23.0
		) {
			// Then use clipping to stretch this face downward across the
			// screen, vertically.
			gl_Position.yz = vec2(-1000.0, -gl_Position.w);
		}
	#endif
}

