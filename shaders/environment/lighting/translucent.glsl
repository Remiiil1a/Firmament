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

// Water surface
#define BASIC 0
#define NOISE 1
// The water surface model. Each option has varying quality and performance.
#define WATER_SURFACE NOISE // [BASIC NOISE]
#if WATER_SURFACE == NOISE
	#include "/environment/water/surface_noise.glsl"
	#define WATER_PARALLAX
#else /* WATER_SURFACE == BASIC */
	#include "/environment/water/surface_basic.glsl"
	// TODO: Support water parallax on the basic water surface
#endif

#ifdef WATER_PARALLAX
	#include "/environment/water/parallax.glsl"

	// Distance in meters to apply parallax mapping to the water surface.
	#define WATER_PARALLAX_DISTANCE 48.0 // [8.0 16.0 24.0 32.0 48.0 64.0]
#endif

// Whether glass and stained glass reflect, the way water and ice already do.
//
// Glass reflects about 4% of the light that lands on it head on and nearly all
// of it at a glancing angle. That is what a window looks like: mostly you see
// through it, but from the side it turns into a mirror. Without this, glass is
// drawn with no specular response at all, so a pane is a hole in the world that
// happens to be tinted.
//
// The reflections come from the same code the water and ice reflections do, so
// they include the screen-space pass and therefore reflect the world rather than
// only the sky, and they fade out with the sky light like everything else here -
// glass deep indoors and underground stays unreflective.
//
// Water and ice are not affected by this: they always reflected, and their
// reflectance is decided below.
#define GLASS_REFLECTIONS
#ifdef GLASS_REFLECTIONS
	// Referenced with an #ifdef here so that Iris registers it as an option
	// rather than a plain define; the use is in lit.fsh.
#endif

// Screenspace terrain reflections
#include "/lib/raytrace.glsl"

// What glass reflects when the light lands on it head on.
//
// This is a property of the material rather than a value to taste: ordinary
// glass sits at about 4%, which is also the floor Steadfast puts under a
// dielectric's reflectance in the material decoding. It is a constant of its own
// rather than a reference to that floor because the two mean different things -
// one is what glass is, the other is what to assume when a resource pack says
// nothing.
const float GLASS_F0 = 0.04;

// Screenspace terrain refraction for water
#include "/environment/water/refraction.glsl"

#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
	// Integration between water absorption and refraction
	#include "/environment/water/absorption_refraction.glsl"

	// Sky light buffer for aiding refractive-based water absorption
	// TODO: This will prevent water absorption from working perfectly with
	//       Voxy. This is not an immediate issue at the moment since it is
	//       rarely visible, but it should be fixed...
	uniform sampler2D colortex5;

#endif

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	// Color buffer to trace SSR in
	uniform sampler2D colortex4;

	// We need to use the view matrix to convert between world-space and
	// view-space.
	//
	// Stands back if it has already been declared - the cloud layer's programs do
	// that, and a repeated uniform declaration is an error. See the note in
	// /environment/clouds/volumetric.glsl.
	#if !defined(GBUFFER_MODEL_VIEW_DECLARED)
		#define GBUFFER_MODEL_VIEW_DECLARED
		uniform mat4 gbufferModelView;
	#endif

	// Where the camera was when the colour buffer above was drawn, and the
	// matrices it was drawn with. The reflection below reads that buffer, so it
	// has to read it where the previous frame had the point the ray hit rather
	// than where this frame has it - see the comment in TranslucentLighting.
	//
	// A program that is handed its uniforms by something else is given no
	// previous frame at all (Voxy's terrain - see voxy.json), which is why all
	// three of these and the reprojection that uses them sit behind the same
	// test as the buffer itself.
	uniform vec3 previousCameraPosition;
	uniform mat4 gbufferPreviousModelView;
	uniform mat4 gbufferPreviousProjection;
#endif

#if !defined(DH_TERRAIN)
	// A fast and visually appealing approximation of refractions.
	#define SCREENSPACE_REFRACTION

	#if defined(SCREENSPACE_REFRACTION)
		#define WATER_REFRACTION_SAMPLE
	#endif
#endif

#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
	#define WATER_REFRACTION_SAMPLE
#endif

vec3 parallaxWaterNormal(
	vec3 incident,
	vec3 cameraRelativePos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	bool verticalNormal,
	vec3 worldNormal,
	// The frame the face has: tangent, bitangent, normal - see face.glsl.
	mat3 worldTBN
) {
	vec2 waterWorldPos = cameraRelativePos.xz + cameraPosition.xz;

	// Whether this face is standing up rather than lying flat - the side of a
	// waterfall, or the face of water flowing down a slope.
	bool sideways = abs(worldNormal.y) < 0.99;

	// If the normal vector is facing down instead of up, we need to flip the
	// results of our non-TBN calculations.
	float facing = worldNormal.y >= 0.0 ? 1.0 : -1.0;

	// Across a face that is not horizontal, x and z do not change: they are the
	// same for every fragment of it, and the wave field is a function of exactly
	// those two coordinates. It therefore comes out constant over the whole face
	// and the water reads as flat, whatever the surface style is set to. Folding
	// the height into the coordinate as well makes the same two-dimensional field
	// vary down the face, which is what gives falling water a surface.
	//
	// Sundial's water surface does the same thing for the same reason: its sample
	// coordinate is position.xz + vec2(position.y). Absolute height, not the
	// camera-relative one, so that the pattern does not slide when the camera
	// itself moves up or down.
	if (sideways) {
		waterWorldPos += vec2(cameraRelativePos.y + cameraPosition.y);
	}

	#if defined(WATER_PARALLAX) && !defined(DH_TERRAIN)
		// Parallax mapping stops at the edge of the vanilla render distance.
		//
		// Past that boundary the terrain belongs to another renderer, and its
		// water has no parallax of its own - so a surface that was still
		// displacing right up to the boundary would step visibly where the two
		// meet. `far` is exactly that boundary, and it is the same quantity the
		// screenspace shadows hand over at.
		//
		// The cost is that a short vanilla render distance also shortens the
		// parallax, since the parallax may then no longer reach past it.
		float parallaxDistance = float(WATER_PARALLAX_DISTANCE);

		#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
			// Not on the patch's path: far is a standard uniform, but that
			// program declares its own set and this is not in it.
			parallaxDistance = min(parallaxDistance, far);
		#endif

		// Fade out parallax mapping on faraway surfaces to avoid wasting
		// performance applying parallax mapping where the effect is not visible
		//
		// Also prevent parallax effects from taking place on sideways water,
		// because that does not really make sense with our 2D-only formulation
		// of water height.
		float parallaxStrength = clamp(
			(parallaxDistance - length(cameraRelativePos))
				/ (parallaxDistance * (1.5 - 1.0)),
			0.0,
			float(verticalNormal));

		if (parallaxStrength > 0.0001) {
			vec3 viewDirTangent = facing * incident.xzy;
			vec2 offsetPos = WaterSurfaceParallaxMapping(
				waterWorldPos,
				ddxWorldPos,
				ddyWorldPos,
				timeSeconds,
				viewDirTangent);
			waterWorldPos = mix(waterWorldPos, offsetPos, parallaxStrength);
		}
	#endif

	vec3 waterNormal = WaterNormal(
		waterWorldPos,
		ddxWorldPos,
		ddyWorldPos,
		timeSeconds);

	// A face that is not horizontal needs a frame of its own. WaterNormal returns
	// the normal in tangent space, where Z points out of the surface and X and Y
	// point along it - and for water lying flat on the ground those two happen to
	// be east and north, which is why the swizzle below is written the way it is.
	// On a vertical face they are instead up the face and across it. Without
	// them the waves are applied as if the surface were flat on the ground: the
	// normal comes out pointing at the sky, so the side of a waterfall is shaded
	// and reflects exactly as if it were the top of a lake.
	//
	// The frame used here is the one the geometry itself carries rather than one
	// rebuilt from the world's up axis. On a block face lined up with the world
	// the two are the same frame up to the sign of each axis, which is most of
	// what water is ever drawn on; anywhere else - a mod's slope, a face at an
	// angle - they do not agree, and what the difference looks like is which way
	// across the face the waves run and how the field is stretched over it.
	if (sideways) {
		return normalize(
			worldTBN[0] * waterNormal.x
				+ worldTBN[1] * waterNormal.y
				+ worldTBN[2] * waterNormal.z);
	}

	// Water lying flat on the ground, which is the common case: the face is
	// already known to point along the world's up axis apart from the sign, and
	// the field the waves come from was laid out over world x and z (see
	// waterWorldPos above), so the swizzle into world axes is exact here and
	// needs no frame at all.
	//
	// The same reasoning covers the view direction the parallax mapping is given
	// further up - it is written in the field's axes for the same reason, not
	// because the face frame is assumed to be the world's.
	return facing * waterNormal.xzy;
}

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	// These are the view-space vectors that represent a one-pixel offset along
	// the X and Y axis in screen-space, respectively.
	uniform vec3 viewOffsetPixelX;
	uniform vec3 viewOffsetPixelY;
#endif

// This function is a method of computing the partial derivative of the world
// space position with respect to the screen space position (screen space
// partial derivative) using triangle intersections and the finite-difference
// method, but without requiring the calculations of a neighboring fragment.
//
// This technique is strongly inspired by the following paper:
//
//   Christopher A. Burns and Warren A. Hunt, The Visibility Buffer:
//   A Cache-Friendly Approach to Deferred Shading, Journal of Computer Graphics
//   Techniques (JCGT), vol. 2, no. 2, 55-69, 2013
//   Available online http://jcgt.org/published/0002/02/04/
//
// However, this implementation is a simpler variant that excludes the logic
// required for vertex attribute interpolation and fetching vertex positions,
// in favor of constructing a "hypothetical triangle" for the purpose of the
// intersection test that simplifies the resulting derivative calculations.
void dWorldPosdxdy(
	// View position of the fragment
	vec3 viewPos,
	vec3 worldTangent,
	vec3 worldBinormal,
	// dFdx(worldPos), computed with the finite distance method
	out vec3 ddxWorldPos,
	// dFdy(worldPos), computed with the finite distance method
	out vec3 ddyWorldPos
) {
	// Form a triangle in view-space with edge lengths of 1 with a plane that is
	// parallel to and overlapping the triangle plane that this fragment came
	// from. This "hypothetical triangle" is just to make our calculations more
	// straightforward but does not change their results.
	vec3 edge1 = mat3(gbufferModelView) * worldTangent;
	vec3 edge2 = mat3(gbufferModelView) * worldBinormal;

	// This is the Möller–Trumbore intersection algorithm:
	// https://en.wikipedia.org/wiki/Möller–Trumbore_intersection_algorithm
	//
	// I am summarizing the relevant part of the paper here.
	//
	// Given a triangle with vertices v0, v1, v2, we can define the following:
	//
	// edge1 = v1 - v0
	// edge2 = v2 - v0
	//
	// Then, for a ray with origin O and direction D, the ray distance (t) and
	// barycentric coordinates u and v are given by the following system of
	// equations, with T defined as O - v0:
	//
	//                        [ t ]
	// [ -D, edge1, edge2 ] * [ u ] = T
	//                        [ v ]
	//
	// Per Cramer's Rule, the solution is given by:
	//
	// [ t ]             1              [ det( T, edge1, edge2) ]
	// [ u ] =  --------------------- * [ det(-D,     T, edge2) ]
	// [ v ]    det(-D, edge1, edge2)   [ det(-D, edge1,     T) ]
	//
	// We do not care about the value of t here, and can simplify to:
	//
	//                   1
	// [ u ] =  --------------------- * [ det(-D,     T, edge2) ]
	// [ v ]    det(-D, edge1, edge2)   [ det(-D, edge1,     T) ]
	//
	// We trace from an origin of (0, 0, 0), so the vector from viewPos to the
	// origin is just -viewPos. Because the negatives cancel out below, we can
	// just treat the vector from the center vertex (v0, viewPos) to the origin
	// as viewPos. Therefore, we can set T as viewPos.
	//
	// From linear algebra:
	// det(A, B, C)
	// = dot(cross(A, B), C)
	// = -dot(cross(A, C), B)
	// = -dot(cross(C, B), A)
	//
	// Expanding these determinants as cross products:
	//
	//                   1
	// [ u ] =  --------------------------- * [ dot(cross(D, edge2), viewPos) ]
	// [ v ]    dot(cross(D, edge2), edge1)   [ dot(cross(viewPos, edge1), D) ]
	//
	// To avoid repetition, we introduce two variables:
	//
	// q = cross(viewPos, edge1)
	// p = cross(D, edge2)
	vec3 q = cross(viewPos, edge1);

	// These directions set up the intersection calculation we are using to find
	// the screen-space partial derivatives. We trace towards the triangle in
	// the direction of the current fragment, but then add one pixel up and one
	// pixel to the side for each trace.
	vec3 incident = normalize(viewPos);
	vec3 offsetX = incident + viewOffsetPixelX;
	vec3 offsetY = incident + viewOffsetPixelY;

	// Intersection for the trace along the screen in the X direction, in
	// barycentric coordinates.
	vec3 pdx = cross(offsetX, edge2);
	float invdetdx = 1.0f / dot(pdx, edge1);
	float dudx = invdetdx * dot(pdx, viewPos);
	float dvdx = invdetdx * dot(offsetX, q);

	// Intersection for the trace along the screen in the Y direction, in
	// barycentric coordinates.
	vec3 pdy = cross(offsetY, edge2);
	float invdetdy = 1.0f / dot(pdy, edge1);
	float dudy = invdetdy * dot(pdy, viewPos);
	float dvdy = invdetdy * dot(offsetY, q);

	// Transform the screen-space derivative from barycentric coordinates back
	// to world-space. The first barycentric coordinate is the movement toward
	// the first vertex, and the second is the movement towards the second
	// vertex.
	ddxWorldPos = worldTangent * dudx + worldBinormal * dvdx;
	ddyWorldPos = worldTangent * dudy + worldBinormal * dvdy;
}

// How much of the water's reflection to keep.
//
// 1.0 is every bit of it, which is what the pack has always drawn and what this
// is a way out of. It is here because the reflection is the one part of the water
// that reads as a shader rather than as water: a lake in a forest shows you the
// forest twice, and a pack that gets the reflection slightly wrong makes still
// water look like a mirror laid on the ground. Turning it down keeps the water's
// own colour and its Fresnel edge, and takes away the picture in it.
//
// 0.0 is no reflection at all - water lit and fogged like any other surface.
//
// It reaches level-of-detail water as well as the water beside it. Both go through
// TranslucentLighting, which is where this is applied, so there is one place it
// could have been and one place it is - see the note at the application below.
//
// It does not go above one. A Fresnel term is a fraction of the incoming light and
// cannot exceed all of it, so a setting that asked for more would be answered with
// the same picture as 1.0 - a slider whose top half does nothing, which is worse
// than a shorter slider. See PBR_PORTING.md 148.
#define WATER_REFLECTION_STRENGTH 0.5 // [0.0 0.1 0.25 0.5 0.75 1.0]

vec4 TranslucentLighting(
	vec4 fragmentColor,
	vec3 worldNormal,
	// The frame the face has: tangent, bitangent, normal - see face.glsl. Only
	// the water surface below uses it, but it is passed to everything so that
	// the call has one shape.
	mat3 worldTBN,
	vec3 cameraRelativePos,
	vec3 viewPos,
	float reflectionStrength,
	float skyLight,
	uint materialID,
	// The material data of this fragment and the normal it perturbs the surface
	// with. Programs without material data pass PbrNone() and the face normal,
	// which leaves every branch below exactly as it was.
	PbrSurface pbr,
	vec3 materialNormal
) {
	bool verticalNormal = worldNormal.y > 0.9999;

	// Adjust output for the remultiplied alpha blending mode:
	// glBlendFunc(sfactor=GL_ONE, dfactor=GL_ONE_MINUS_SRC_ALPHA)
	// 
	// Used for added flexibility with reflection calculations instead of:
	// glBlendFunc(sfactor=GL_SRC_ALPHA, dfactor=GL_ONE_MINUS_SRC_ALPHA)
	float srcAlpha = 1.0 - fragmentColor.a;
	fragmentColor.rgb *= fragmentColor.a;
	vec3 normal = worldNormal;

	// We can get the view-space incident vector (needed for reflection and
	// refraction) from normalizing the view position as the incident vector
	// from our view is necessarily the direction of the fragment in view space!
	vec3 incident = normalize(cameraRelativePos);

	// The frame of this face, which the world-space derivatives below are taken
	// in.
	//
	// These two vectors have to be unit length, and orthogonal with each other
	// and with the normal, or the intersection the derivative code performs
	// stops describing the plane this fragment came from - and only a face's own
	// tangent and bitangent are that on every face. They used to be hardcoded to
	// the world's east and north, on the grounds that a water face pointing up
	// has those as its own axes; that is true of the water the pack used to
	// draw, and of nothing else, and every translucent comes through here.
	vec3 worldTangent  = worldTBN[0];
	vec3 worldBinormal = worldTBN[1];

	// Compute ddxWorldPos = dFdx(worldPos) and ddyWorldPos = dFdy(worldPos)
	// without actually requiring the screen-space partial derivative functions
	// dFdx or dFdy, which are not compatible with discarded fragments or any
	// other form of non-uniform control flow. This is primarily a limitation in
	// practice with Voxy.
	//
	// The two world-space vectors must be of length 1 to avoid needing to
	// divide later on within the function, and they must be orthogonal with
	// both each other and the normal vector for correct results, hence by
	// definition they must be the tangent and binormal vectors, but their
	// order does not matter.
	vec3 ddxWorldPos;
	vec3 ddyWorldPos;
	dWorldPosdxdy(
		// Inputs
		viewPos, worldTangent, worldBinormal,
		// Outputs
		ddxWorldPos, ddyWorldPos);

	#ifdef SCREENSPACE_REFRACTION
		if (materialID == WATER) {
			normal = parallaxWaterNormal(
				incident,
				cameraRelativePos,
				ddxWorldPos.xz,
				ddyWorldPos.xz,
				verticalNormal,
				worldNormal,
				worldTBN);
		}
	#endif

	if (reflectionStrength > 0.0001) {
		// For non-water, allow the fresnel to go to zero and use the face
		// normal instead of any normal-mapping.
		//
		// Water uses a different F0 (minimum fresnel) value as well as normal
		// mapping for moving waves.
		//
		// If we wanted to be physically-based, the F0 for water should be
		// around 0.02 per Shlick's approximation, but that makes it too
		// see-through.
		float F0 = materialID == WATER ? 0.1 : 0.0;

		// Glass does not need the resource pack to say anything: its reflectance
		// is a property of the material, and the Fresnel term below needs
		// something to start from or a pane would only ever reflect at a
		// glancing angle.
		if (materialID == GLASS || materialID == STAINED_GLASS) {
			F0 = GLASS_F0;
		}

		#ifdef PBR_SURFACE
			#ifdef PBR_TRANSLUCENT
				// Ice and glass are solid surfaces that happen to be drawn in
				// the translucent pass, so unlike water they have materials of
				// their own - and taking the reflectance and the normal from the
				// resource pack is what turns their reflections into reflections
				// of the material the pack authored.
				//
				// Water keeps the value above even here. See PBR_TRANSLUCENT in
				// pbr.glsl for why the two are not treated the same way.
				if (materialID != WATER) {
					// Glass is still floored at its own reflectance: a pack that
					// ships no specular map for a pane is not describing a
					// surface that reflects nothing, it is describing nothing at
					// all. Ice is left to the pack, since a pack's ice is often
					// closer to snow than to glass.
					F0 = max(
						dot(pbr.f0, PBR_LUMINANCE),
						materialID == ICE ? 0.0 : GLASS_F0);
					normal = materialNormal;
				}
			#endif
		#endif

		// If we didn't already calculate the water normal, calculate it now.
		#ifndef SCREENSPACE_REFRACTION
			if (materialID == WATER) {
				normal = parallaxWaterNormal(
					incident,
					cameraRelativePos,
					ddxWorldPos.xz,
					ddyWorldPos.xz,
					verticalNormal,
					worldNormal,
					worldTBN);
			}
		#endif

		// First, determine the reflected normal.
		//
		// While a bit atypical, we compute this reflection with world-space
		// vectors instead of view-space vectors. This leads to no visual
		// difference in most scenes, but when under the effects of nausea,
		// view space is warped and skewed, and these sorts of calculations
		// give wacky results, while doing them in world space leads to
		// correct reflection results.
		vec3 reflected = reflect(incident, normal);

		// TODO: This is a hack. Sometimes, we hit the "back" of a wave we
		// technically should not be able to see, and the reflected direction
		// goes underwater. Checking against the face normal detects this and we
		// fall back to using the face normal. This still is not correct, but is
		// better than the seriously ugly artifacts of when that happens.
		//
		// Not sure how to fix this best.
		if (dot(worldNormal, reflected) <= 0.0) {
			reflected = reflect(incident, worldNormal);
		}
		
		// Fresnel calculation. The actual fresnel value is modulated by the sky
		// reflection strength, which is affected by material properties and the
		// sky light strength and isn't just 1.0.
		//
		// The incident vector and normal vector are always 90 degrees or more
		// apart from each other - conceptually, the incident vector is always
		// sideways or downwards if the normal vector is upwards. This means the
		// dot product is always negative so adding it is really a subtraction.
		//
		// Otherwise, this follows the physically-based Shlick's approximation
		// for the fresnel factor:
		// https://en.wikipedia.org/wiki/Schlick's_approximation
		float fresnel = F0 + (1.0 - F0) * pow(1.0 + dot(incident, normal), 5.0);
		// The water's reflection strength is scaled by the option here, and by the
		// material and by nothing else: ice and glass come through the same code
		// and keep every bit of their reflection, because a window and a frozen
		// lake are read as surfaces rather than as water, and dimming them is not
		// what the option is for.
		//
		// This is the only line the option is applied on, which is what makes it
		// reach the level-of-detail water as well: Voxy's water and the water drawn
		// by the chunk renderer both arrive at this function, so neither of them
		// can be left out of it.
		fresnel *= reflectionStrength
			* (materialID == WATER ? WATER_REFLECTION_STRENGTH : 1.0);

		// Very basic reflections using the sky gradient. There is no need to
		// apply fog to the sky reflection, as we apply fog at the very end for
		// the overall fragment (reflection + refraction + its own color.)
		//
		// The stars come with the sky, in the reflection of every surface that
		// has one - water and glass alike. They are part of the sky rather than
		// a decoration on the water, and a reflected sky without them is a sky
		// that has been emptied of the one thing left in it at night.
		//
		// The sun and the moon below are the exception and are water only; the
		// note there says why.
		vec3 skyReflection = SkyDither(
			gl_FragCoord.xy,
			SkyColor(reflected) + SkyStars(reflected));

		#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
			// The sun and the moon are added on top, on water only. The sky model
			// is atmosphere only, so without them the water reflected the air
			// with nothing standing in it, and a clear night had no moonlight on
			// it at all - see environment/sky/bodies.glsl.
			//
			// Glass and ice are left with the sky reflection and their own
			// Fresnel term. A disc of sunlight on a window reads as a hole in it
			// rather than as a reflection, because a window is being seen
			// through as much as reflected in, and the disc does not dim with
			// the part that is being seen through.
			//
			// Both directions are turned into view space here, where the game
			// holds the sun for the sky it draws - see SkyBodies. The third
			// argument is the world-to-view rotation, so that the quad the body
			// is drawn in is built in the same space as the two directions.
			if (materialID == WATER) {
				skyReflection += SkyBodies(
					(gbufferModelView * vec4(reflected, 0.0)).xyz,
					normalize(sunPosition),
					mat3(gbufferModelView));
			}
		#else
			// The patch's own program. It has neither the view matrix the
			// geometry here was drawn with nor the game's own sun position, so
			// both directions are taken from the world ones instead.
			//
			// They are converted by the same code, so the two of them agree with
			// each other, and that is all the comparison needs to put a disc on
			// the water. What is given up is only the agreement with the sun the
			// game draws in the sky - and that is the far terrain's water, where
			// the sky above it is small in the view and the disc does not sit
			// next to the real sun on screen.
			if (materialID == WATER) {
				// No rotation wanted here: both directions are already in world
				// space, so the identity is what takes world to world.
				skyReflection += SkyBodies(reflected, worldSunVector, mat3(1.0));
			}
		#endif
		vec3 reflectedColor = skyReflection;

		// Allows water and ice to reflect the world in addition to the sky.
		#define SCREENSPACE_REFLECTIONS

		#ifdef SCREENSPACE_REFLECTIONS
			// Note: We don't have a separate terrain reflection strength. As it
			// turns it, in the same places that sky reflections look bad, the
			// limitations of SSR makes terrain reflections look bad too.
			// 
			// As a result, reflections are reserved for outdoors, not caves and
			// indoors.
			vec2 hitPos;
			vec3 hitViewPos;

			// Controls the base thickness and increase in thickness over
			// distance during raytracing, effectively the tolerance of
			// determinining whether we are going
			// to accept a hit or not.
			//
			// X: initial thickness in meters
			// Y: additional increase in meters per raytracing step not directly
			//    related to distance
			vec2 thicknessControl;

			// The mirror-like reflection of a solid surface - ice, glass, a
			// window pane - makes it harder to hide the stretching that the
			// thickness causes, so those use a low thickness. The wavy
			// reflection of water easily hides it, and a stretched reflection of
			// something still looks better than no reflection at all.
			thicknessControl = vec2(materialID == WATER ? 1.0 : 0.5, 1.0);
			
			vec3 reflectedView = mat3(gbufferModelView) * reflected;

			bool hit = Raytrace(
				opaqueDepth,
				projectionMatrix,
				inverseProjectionMatrix,
				viewPos,
				reflectedView,
				thicknessControl,
				hitPos,
				hitViewPos);

			#if defined(DISTANT_HORIZONS) && !defined(DH_TERRAIN)
				// Try again for a distant hit if we didn't get a nearby hit
				//
				// TODO: Only do this if the reason for the miss was a depth
				// buffer escape along the Z axis.
				if (!hit) {
					hit = Raytrace(
						opaqueDepthDistant,
						projectionMatrixDistant,
						inverseProjectionMatrixDistant, 
						viewPos,
						reflectedView,
						thicknessControl,
						hitPos,
						hitViewPos);
				}
			#endif

			if (hit) {
				vec2 hitPosAbs = abs(hitPos * 2.0 - 1.0);
				float hitPosMax = max(hitPosAbs.x, hitPosAbs.y);
				float visibility = min(1.0, (1.0 - hitPosMax) / 0.10);

				// When we are looking upwards and there is an upwards-facing
				// water face, the Z-component of the normal  in view-space is
				// positive, and when we are looking downwards, it is negative.
				//
				// Essentially, this means that we only fade out the reflections
				// at the edge when it is necessary, ie, we are looking downward
				// at the water instead of level or upwards.
				//
				// This transformation is just getting the Z component of
				// the normal in view space.
				float viewNormalZ = dot(gbufferModelView[2].xyz, worldNormal);
				visibility = mix(1.0, visibility, clamp(viewNormalZ, 0.0, 1.0));

				// What the ray hit, in the world axes of this frame, and where the
				// colour buffer it is read from has that point.
				//
				// colortex4 holds the frame before this one, drawn with the camera
				// where it was then. Reading it at this frame's screen position -
				// which is what the pack did until now - therefore reads the colour
				// of whatever stood a small distance away from the point that was
				// actually hit. Standing still, that distance is nothing; walking,
				// the view bobs back and forth several times a second, and the
				// reflection slides with it. That is why a glass pane or a calm
				// water surface shivers as the player walks, why it does it in time
				// with the step, and why flying - which has no bob - is free of it.
				//
				// The cure is the one every temporal effect uses: put the hit point
				// back where the previous frame had it. Its position in this frame
				// is exact (the ray is traced against this frame's depth buffer),
				// so moving it into the previous frame's screen is a matter of
				// taking the camera's own movement back out of it and projecting it
				// with the matrices that frame was drawn with.
				vec3 cameraRelativePosW;
				vec2 reflectionPos;

				#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
					// The hit's position in world axes, read out against the axes of
					// the matrix the geometry was drawn with, for the reason given in
					// program/world/lit.fsh: gbufferModelViewInverse is not quite the
					// inverse of that matrix while the view is bobbing.
					mat3 viewAxes = mat3(gbufferModelView);
					cameraRelativePosW = vec3(
						dot(hitViewPos, viewAxes * vec3(1.0, 0.0, 0.0)),
						dot(hitViewPos, viewAxes * vec3(0.0, 1.0, 0.0)),
						dot(hitViewPos, viewAxes * vec3(0.0, 0.0, 1.0)));

					// World position = camera position + that, so the position
					// relative to where the camera was a frame ago is this plus how
					// far the camera has moved since.
					vec3 previousRelativePos = cameraRelativePosW
						+ cameraPosition - previousCameraPosition;
					vec4 previousClipPos = gbufferPreviousProjection
						* (gbufferPreviousModelView * vec4(previousRelativePos, 1.0));
					vec2 previousPos = previousClipPos.xy
						/ previousClipPos.w * 0.5 + 0.5;

					// A point the previous frame did not have on screen has no
					// colour to offer, and its projection is not to be trusted
					// either: those pixels keep this frame's position, which is
					// wrong in the way above but not wrong in a new way. They are
					// mostly the ones at the edge of the screen, where the fade
					// below is taking the reflection out anyway.
					bool previousOnScreen = previousClipPos.w > 0.0
						&& previousPos.x > 0.0 && previousPos.x < 1.0
						&& previousPos.y > 0.0 && previousPos.y < 1.0;

					reflectionPos = previousOnScreen ? previousPos : hitPos;
				#else
					// A program with externally supplied uniforms has no previous
					// frame to read (see voxy.json), so it keeps reading this
					// frame's position and with it the wobble this fix removes.
					cameraRelativePosW = (gbufferModelViewInverse
						* vec4(hitViewPos, 1.0)).xyz;
					reflectionPos = hitPos;
				#endif

				// Water that stands up is rough, and a rough surface does not show
				// a mirror: it shows a wide, soft average of whatever it faces.
				// Both packs this one follows filter a water reflection by
				// roughness for exactly that reason - Mellow blurs the reflected
				// image by a radius that grows with the distance to whatever was
				// hit (blur_variable, global/water.glsl), and Sundial stores
				// water's smoothness in its gbuffer and filters the reflection
				// with it (Composite5.frag). This pack had one unfiltered fetch,
				// which is why the sides of flowing water read as a sharp picture
				// of something they are not facing.
				//
				// The radius is in pixels and grows with the distance to the hit,
				// because the same roughness covers more of the screen the further
				// away the thing being reflected is - the rule Mellow's blur uses.
				// Water lying flat keeps the single fetch: its reflection is the
				// one the pack is known for, and it is not this batch's business.
				vec3 terrainReflection;

				if (materialID == WATER && !verticalNormal) {
					// Pixel size, taken from a uniform the Voxy patch also gets
					// rather than from windowToScreen, which it does not.
					vec2 pixelSize = windowToNdc * 0.5;
					float blurRadius = clamp(0.06 * length(hitViewPos), 2.0, 24.0);

					// Two rings of four taps, at half and full radius: cheaper to
					// write than a disc and even enough that the ring itself does
					// not show in the result.
					vec3 blurred = vec3(0.0);
					for (int i = 0; i < 8; i++) {
						float angle = float(i) * 0.7853982;
						float ringScale = i < 4 ? 0.5 : 1.0;
						vec2 offset = vec2(cos(angle), sin(angle))
							* (blurRadius * ringScale);
						blurred += texture(
							colortex4,
							reflectionPos + offset * pixelSize).rgb;
					}

					terrainReflection = blurred * 0.125;
				} else {
					terrainReflection = texture(colortex4, reflectionPos).rgb;
				}

				float fragDistanceW = max(
					abs(cameraRelativePosW.y),
					length(cameraRelativePosW.xz)
				);

				// Note: Using sky light strength of here, not of where we are
				// reflecting - this could look odd with caves reflecting, but
				// I have not noticed any issue and loading the sky light
				// texture would not be free.
				vec4 fogForWater = Fog(
					skyReflection,
					fragDistanceW,
					fragDistanceW,
					skyLight);

				// We apply fog to the terrain reflection, but critically, the
				// fog we are applying is from the standpoint of the reflected
				// direction - that is, we are fading the terrain reflection
				// into its background, even if the water the reflection will be
				// applied to is in a different situation fog-wise.
				reflectedColor = mix(
					reflectedColor,
					terrainReflection * fogForWater.a + fogForWater.rgb,
					visibility);
			}
		#endif

		// Mix in the reflection color based on the fresnel factor, and reduce
		// the intensity of the background (destination) color accordingly.
		//
		// The short version is that we need to reduce the visibility of the
		// terrain behind the water even more when incorporating reflections.
		fragmentColor.rgb = mix(fragmentColor.rgb, reflectedColor, fresnel);
		srcAlpha *= 1.0 - fresnel;
	}

	#if defined(WATER_REFRACTION_SAMPLE)
		// Only water is refractive for now as with our refraction calculation,
		// a normal map is a requirement for refraction, as otherwise the face
		// normal and normalmap normal are the same and we have no variance to
		// refract with.
		//
		// This is actually pretty desirable underground as it makes water far
		// more noticeable than it otherwise would be.
		//
		// TODO: Permit sideways water to refract, or make it just opaque.
		//       Just do something.
		//
		// Water that stands up is taken here too. Its refraction direction comes
		// out as little more than the incident vector - the difference between
		// the wave normal and the face normal is what drives the offset, and on a
		// face that stands up they are nearly the same - so it warps the
		// background by a hair and, more to the point, it reaches the background
		// and the absorption below at all. Without this the sides of flowing
		// water had neither colour nor background: their own alpha is zero in
		// daylight, since it is the absorption that gives a water surface its
		// colour, so they came out as glass and were then thrown away by the
		// alpha test.
		if (materialID == WATER) {
			// Screen-space refraction implementation. We are working within the
			// following constraints:
			//
			// - Realistic refraction is relatively unintuitive: when you
			//   encounter it in real life, it is a "whoa, weird, neat"
			//   situation, but when it is in a renderer, it feels like a bug.
			//   It's also not gameplay-friendly: objects appear in
			//   substantially different locations than they actually are.
			//   That would make mining sand from above water for example an
			//   odd experience.
			//
			// - Even if we wanted realism, all we have is data on the screen. 
			//   Realistic refraction will hide things that are on screen, and
			//   show underwater objects not visible on screen. This will
			//   reveal obvious artifacts when we can't access this information.
			//
			// - Realistic refraction results in such extreme distortion that we
			//   need to actually raytrace through the scene, but the artifacts
			//   and cost of doing so are not acceptable in screen space.
			// 
			// These combined factors mean that actually simulating physically
			// based refraction is a NOT the goal. Instead, the effect we are
			// going for is warping the background based on how deep the water
			// is, such that a given fragment moves around fairly uniformly
			// around where it would otherwise be, rather than offsetting the
			// background significantly upwards/downwards from its actual
			// location.
			//
			// Instead, we use a non-physically-based refraction direction
			// calculation. We take the incident vector, and add the difference
			// between the normal-mapped normal and the face normal. Finally, we
			// normalize the result so that we can calculate offsets along a ray
			// with it.
			//
			// When we subtract the face normal from the wave normal, what we
			// actually get is a short vector that points slightly downwards but
			// otherwise in the direction of the wave.
			//
			// In practice, this approximates a side-to-side movement of the
			// refracted direction while broadly going in the same direction as
			// the original incident vector, which means that the incident
			// vector and refracted vector are close enough to make some
			// important approximations.
			vec3 refractedDir = normalize(incident + normal - worldNormal);
			float maxRefractDistance = 32.0;

			vec3 refractedDirView = mat3(gbufferModelView) * refractedDir;

			// TODO: Simplify this or perhaps make refraction not care about
			//       the depth buffer at all.
			vec3 refractedScreenPos = RefractTrace(
				opaqueDepth, projectionMatrix, inverseProjectionMatrix,
			 	viewPos, refractedDirView, maxRefractDistance
			);
			vec3 ndcPosRefracted = refractedScreenPos * 2.0 - 1.0;
			vec4 viewPosHRefracted =
				inverseProjectionMatrix * vec4(ndcPosRefracted, 1.0);
			vec3 viewPosRefracted =
				vec3(viewPosHRefracted.xyz / viewPosHRefracted.w);

			#if defined(DISTANT_HORIZONS) && !defined(DH_TERRAIN)
				if (refractedScreenPos.z == 1.0) {
					refractedScreenPos = RefractTrace(
						opaqueDepthDistant,
						projectionMatrixDistant,
						inverseProjectionMatrixDistant,
						viewPos,
						refractedDirView,
						maxRefractDistance
					);

					ndcPosRefracted = refractedScreenPos * 2.0 - 1.0;
					viewPosHRefracted = inverseProjectionMatrixDistant
						* vec4(ndcPosRefracted, 1.0);
					viewPosRefracted =
						vec3(viewPosHRefracted.xyz / viewPosHRefracted.w);
				}
			#endif

			vec3 dstColor = RefractionSafeSample(
				colortex4, 
				refractedScreenPos.xy
			).rgb;

			#if WATER_ABSORPTION_METHOD == REFRACTION_ASSISTED
				// The world-space upwards vector (0, 1, 0), transformed into
				// view space.
				//
				// Taking the dot product of the this vector and another view
				// space vector gives the Y-component of that vector in world
				// space, which is useful for measuring vertical distance and if
				// a vector is pointing up or down.
				//
				// This is just the simplified form of the standard matrix
				// multiplication for transforming from world space to view
				// space.
				//
				// TODO: This leads to inaccurate results during nausea
				vec3 upVector = gbufferModelView[1].xyz;

				// How deep this fragment sits in the water, which the absorption
				// below is measured in.
				float waterDepth;

				dstColor = RefractionBasedWaterAbsorption(
					refractedScreenPos, viewPosRefracted, upVector,
					viewPos, verticalNormal,
					dstColor, colortex5,
					skyLight,
					waterDepth
				);
			#endif

			// To apply the refraction, sample the background texture at the
			// refracted position. The sampled color becomes are new background,
			// and as a result, we replicate the blending equation with it as
			// the "destination color" in terms of OpenGL blending.
			//
			// Our blend equation is:
			//
			//   BlendResult = (SrcColor * 1) + (DstColor * SrcAlpha)
			//
			// In terms of our variable names, this is:
			//
			//   fragmentColor = (fragmentColor * 1) + (dstColor * srcAlpha)
			//
			// Which simpifies to the following:
			fragmentColor.rgb += srcAlpha * dstColor;

			// Finally, make the fragment opaque based on the above blending
			// equation.
			//
			// You might wonder - what is the point of forward-rendered
			// translucents if refraction means we have to turn off translucency
			// anyways? The answer is that we can still get benefits if
			// translucent objects are in front of refractive objects.
			//
			// In other words, you can see water through stained glass if
			// stained glass doesn't have refraction enabled.
			srcAlpha = 0.0;
		}
	#endif

	return vec4(fragmentColor.rgb, 1.0 - srcAlpha);
}
