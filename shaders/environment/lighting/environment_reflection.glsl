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

// The environment reflection of a PBR material, as applied by the pass that
// adds it to the picture.
//
// It lives here rather than in that pass because it is that pass's position in
// the frame that matters, and it has moved once already. It used to be applied
// by copy_and_fog, which is the pass that *writes* the buffer a reflection has
// to read - see the sampler below - and a pass cannot read what it is writing.
// It reads the temporal history instead in that position, and the history has
// the reflections of the frame before in it, which makes the reflection a loop
// rather than a lookup: stable while it is faint and sharp, divergent into
// black as soon as it is neither.
//
// composite1 runs one pass later, after the reflection copy is finished, which
// is what makes the read below legal rather than merely probable.
//
// The uniforms it needs are declared here rather than in either program,
// because both include this file in different positions and only the one that
// calls it needs them.

uniform sampler2D colortex4;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D depthtex1;

uniform mat4 gbufferProjection;
uniform mat4 gbufferModelView;

uniform vec2 windowToNdc;
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
// seenThrough: whether this pixel is being looked at through something
//   translucent - water, ice, glass. The caller answers it because it is a
//   question about the two depth buffers, and only the caller has both; see
//   the note on it below for what it is for.
vec3 EnvironmentReflection(
	vec3 viewPos,
	float skyLight,
	bool seenThrough
) {
	#if defined(PBR_REFLECTIONS) || defined(PBR_SSR)
		// A fragment that is being seen through something translucent is given
		// no reflection at all, and the reason for that is not about the
		// surface - it is about where the reflection would be put.
		//
		// Water is drawn after the pass that copies the world into colortex4,
		// and it refracts what is behind it, so the picture of a block under
		// the surface is not where the block is. The depth and the material of
		// that block still are: depthtex1 is the opaque depth, and the block is
		// the opaque surface at those pixels, so neither of them has ever heard
		// of the water. The reflection is therefore worked out for the block,
		// at the block's own pixels, sampled out of a buffer that holds the
		// block at the block's own position - and then added on top of a
		// picture in which the waves have moved the block somewhere else.
		//
		// The result is the same block twice: once distorted by the water, and
		// once sharp, unreflected and in the wrong place, because what the
		// reflection sampled was the pre-water picture of the block itself. It
		// reads exactly like a second copy of whatever is under the surface.
		//
		// The two depth buffers answer the question between them. Only one of
		// them has the translucent pass in it, so they differ at a pixel
		// exactly when something translucent is in front of what is drawn
		// there - which is exactly when this happens, and exactly when a
		// reflection drawn here would be drawn in the wrong place.
		if (seenThrough) {
			return vec3(0.0);
		}

		// Read the material the surface programs left for this pixel. Both
		// fetches are of this same pixel, which is why they can be exact.
		vec4 material = texelFetch(colortex7, ivec2(gl_FragCoord), 0);
		vec3 worldNormal = material.xyz;
		float roughness = material.w;

		vec4 reflectance = texelFetch(colortex8, ivec2(gl_FragCoord), 0);
		vec3 f0 = reflectance.rgb;

		// Which metal this is, or 0 for anything that is not one, and whether it
		// is one at all. The ID is carried as the byte the specular map held,
		// divided by 255 - see the write at the bottom of lit.fsh.
		//
		// Both are needed here and neither can be recovered from the reflectance:
		// the ID is what chooses the colour a metal reflects at a grazing angle,
		// and being a metal is what lets a much rougher surface reflect at all.
		float metalID = reflectance.a * 255.0;
		float metalness = step(0.5, metalID);

		if (!PbrReflectionPossible(worldNormal, roughness, f0)) {
			return vec3(0.0);
		}

		// How much of the environment this surface may reflect at all, worked
		// out here rather than at the end so that a surface that reflects
		// nothing pays for nothing. Most of the screen is rough enough that this
		// is zero, and the sky model and the trace are both expensive enough
		// that evaluating them to multiply the answer by zero is the largest
		// waste this pass had.
		float reflectionWeight = PbrReflectionSmoothness(roughness, metalness);

		if (reflectionWeight <= 1.0e-4) {
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

		// How wide the cone of directions this surface reflects over is, and how
		// many pixels that comes to on screen.
		//
		// The angle is the roughness itself, which is the alpha the highlight is
		// built from in PbrSpecular - so the blur and the highlight widen
		// together, instead of one of them being a number of its own. This used
		// to be a radius in pixels proportional to roughness, which is the same
		// idea with the two conversions left out, and it came to about a
		// thirtieth of the right answer on a brushed metal: roughness in this
		// pack is (1 - smoothness)^2, so a surface whose authors were describing
		// a brushed finish arrives at 0.16, and 0.16 radians is not 0.16 pixels.
		//
		// The pixel scale is the one that turns an angle at the centre of the
		// screen into pixels: half the screen height, divided by the tangent of
		// half the field of view, which is what the projection's second row
		// carries. windowToNdc is two divided by the viewport size, so half the
		// height is its reciprocal.
		float coneAngle = clamp(roughness, 0.0, 1.0);
		float pixelsPerRadian = gbufferProjection[1][1]
			/ max(windowToNdc.y, 1.0e-6);
		float blurPixels = min(coneAngle * pixelsPerRadian, PBR_REFLECTION_BLUR);

		// The sky, which is what an environment reflection is made of on its own,
		// and which is also where a trace that finds nothing ends up.
		//
		// It is averaged over the same cone the trace result is, and that is not
		// a detail: a rough surface outdoors mostly reflects sky, the trace
		// usually finds nothing above it, and a single sharp sample of the sky
		// gradient was the whole of what the surface showed. Whatever the blur
		// below did to the traced half, this half stayed a mirror.
		//
		// Four taps around the cone rather than a proper integral, because a sky
		// model evaluation is one of the more expensive things here and only
		// surfaces the reflection gate lets through run any of this. Below the
		// threshold the taps would land on top of each other and cost four
		// evaluations to say the same thing.
		vec3 skyReflection = SkyColor(worldReflected);

		if (blurPixels >= 0.75) {
			// Any vector that is not parallel to the reflected one will do to
			// build the frame the taps are placed in.
			vec3 coneAxis = abs(worldReflected.y) < 0.99
				? vec3(0.0, 1.0, 0.0)
				: vec3(1.0, 0.0, 0.0);
			vec3 coneTangent = normalize(cross(coneAxis, worldReflected));
			vec3 coneBitangent = cross(worldReflected, coneTangent);

			skyReflection = (
				skyReflection
				+ SkyColor(normalize(worldReflected + coneTangent * coneAngle))
				+ SkyColor(normalize(worldReflected - coneTangent * coneAngle))
				+ SkyColor(normalize(worldReflected + coneBitangent * coneAngle))
				+ SkyColor(normalize(worldReflected - coneBitangent * coneAngle))
			) * 0.2;
		}

		// Faded out by how much of the sky this fragment can actually see, so
		// that a cave floor or an interior does not reflect a sky that is not
		// visible from it.
		vec3 environment = SkyDither(
			gl_FragCoord.xy,
			skyReflection) * PbrSkyExposure(skyLight);

		#if defined(PBR_SSR)
			// Everything that got this far reflects something, so everything
			// that got this far is traced.
			//
			// This used to be gated on a roughness of its own, which the
			// reflection gate above now covers and covers better: for a
			// dielectric the two rules allow the same surfaces, and for a metal
			// the old limit cut off exactly the brushed metals the reflection
			// exists for. Those reflected the sky with no world in it, which is
			// the one thing a metal never does - and the reason a metal could
			// look reflective and still not look like a metal.
			{
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
					// Removed 2026-09-22: the test that stood beside the call
					// above, `length(hitViewPos) > length(viewPos)`. This is
					// why it went, what is drawn without it, and what to look
					// at if what it was written for ever comes back.
					//
					// It refused every hit that was not further from the
					// camera than the fragment that cast the ray. The
					// reasoning was that a ray only travels away from the
					// surface it left, so a hit nearer than the fragment must
					// be that surface meeting itself. The reasoning is sound
					// and the test was still wrong, because a hit is not a
					// point on the ray: it is the position the depth buffer
					// holds at the screen position the ray landed on. A ray
					// passing over anything nearer than the surface it left
					// therefore reports a hit nearer than the fragment, and
					// that is no self-hit at all.
					//
					// Every block edge is where that happens. On a surface
					// whose material carries a bevel in the outermost texels
					// of its sprite - a metal block in most resource packs -
					// the ray leaving those texels turns back into the surface
					// it left, and the hit it finds is nearer than the
					// fragment. The test threw that hit away, and a hit thrown
					// away is a fragment that falls back to the sky: a
					// one-pixel ring of sky around every edge of every such
					// block. It flickers, because the reflection is answered
					// afresh each frame and the gbuffer pass jitters its
					// sub-pixel position, so the foot of the ray lands
					// somewhere else on the bevel every one.
					//
					// A self-hit needs no test, because it is already
					// invisible: it samples the surface's own colour at the
					// surface's own pixels, and a floor that reflects itself is
					// a floor. That colour continuing is what the reflection
					// now shows at those pixels, instead of a ring of sky.
					//
					// The double image of a block seen through water, which
					// this test was written for, is refused earlier and more
					// exactly by the seenThrough gate at the top of this
					// function, which returns before the trace runs at all. If
					// that image is ever seen again, the gate is what to look
					// at - not a rule here, which could only bring the ring
					// back.
					//
					// What the ray found, which is the previous frame: the frame
					// this one is being drawn from is complete in depth but not in
					// colour at this point in the pipeline.
					//
					// Spread over the cone the surface's roughness opens, which
					// is the difference between a frosted metal and a mirror
					// with its colours turned down - see PBR_REFLECTION_BLUR. A
					// mirror takes one sample because one direction is all it
					// reflects, and a rough surface taking one sample is taking
					// one arbitrary direction out of many and calling it the
					// answer, which is what makes it look like noise rather than
					// like roughness.
					//
					// The taps are two rings of four, at half radius and full,
					// the same shape the water reflections blur theirs with: it
					// costs one sample per direction and is even enough that the
					// ring does not show in the result.
					vec3 hitColor;
					if (blurPixels < 0.75) {
						// Smooth enough that taps this close together would only
						// add cost and noise.
						hitColor = texture(colortex4, hitPos).rgb;
					} else {
						vec2 pixelSize = windowToNdc * 0.5;
						vec3 blurred = vec3(0.0);

						for (int i = 0; i < 8; i++) {
							float angle = float(i) * 0.7853982;
							float ringScale = i < 4 ? 0.5 : 1.0;
							vec2 offset = vec2(cos(angle), sin(angle))
								* (blurPixels * ringScale);

							blurred += texture(
								colortex4,
								hitPos + offset * pixelSize).rgb;
						}

						hitColor = blurred * 0.125;
					}

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

		// The smoothness gate is the one that decides whether this surface
		// reflects anything at all - see PbrReflectionSmoothness. It scales the
		// traced result as well as the sky, because both are answering the same
		// question: what does a surface this rough reflect? A rough surface
		// should be shown neither the sky nor a mirror image of the world.
		//
		// A metal is not held back by the global reflection strength. That
		// strength is there because a flat wash of environment over every
		// dielectric is what this looked like before it existed, and a metal is
		// the one case where the reflection is the material rather than a sheen
		// on top of it: Sundial gives it no such factor at all, and this dial is
		// how much of one to keep.
		float strength = mix(
			PBR_REFLECTIONS_STRENGTH,
			PBR_METAL_REFLECTION_STRENGTH,
			metalness);

		return strength
			* PbrReflectionFresnel(f0, PbrMetalF82(metalID), NdotV, roughness)
			* reflectionWeight
			* environment;
	#else
		return vec3(0.0);
	#endif
}
