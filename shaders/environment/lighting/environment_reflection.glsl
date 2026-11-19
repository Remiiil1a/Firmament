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
// It samples colortex4: the deferred pass's copy of this frame, written by
// /program/post/copy_and_fog.fsh. That is a raw single frame rather than a
// resolved one.
//
// BATCH 758 PUT THE REFLECTION AFTER THE TEMPORAL RESOLVE, AND THE HISTORY OF THE
// OTHER ARRANGEMENT IS WORTH KEEPING BECAUSE IT EXPLAINS THE TRAILING.
//
// Batch 664 moved the reflection ahead of the resolve, on the argument that a
// reflection added after it is a fresh noisy sample every frame with nothing
// downstream to average it. That argument was right about the noise and wrong
// about the price: a reflection inside the history lives as long as the history,
// which is about 1/(1-0.85) = 6.7 frames at the default TAA_STRENGTH, and it
// trails. Batch 674 then widened the neighbourhood clamp so the reflection would
// not be cut back out, which lengthened the trail to the full weight. The author
// reports the result as trailing and lagging water reflections.
//
// Neither reference pack does it that way. Sundial composites its reflection in
// Composite0 through Composite3 and resolves in Composite7 and Composite9; Bliss
// composites in composite1.fsh and resolves in composite5.fsh. In both, the
// reflection is an input to the resolve rather than part of its history.
//
// So the reflection is applied after the resolve now, and the noise the move was
// avoiding is answered where it comes from instead: `traceDither` below is a
// spatial dither, so a single frame is already smooth and nothing needs to average
// it across frames.
//
// Sampling colortex4 rather than colortex3 is still what makes the trace legal.
// composite1 writes colortex3, and a buffer a pass writes is not one it may trace
// over: the read side is the previous frame's resolved image, reflection and all,
// so a trace over it would sample a picture that already contains a reflection -
// the feedback loop whose symptom was a black blot that grew (BATCH_LOG.md 210).
// colortex4 carries no reflection, and it is this frame's world, which is also
// the frame the reflection is being added to.
//
// The uniforms are declared here rather than in the pass, because the pass
// includes this file. colortex3 is declared here too although this file no
// longer samples it: the pass that includes it does - that buffer is its
// anti-aliasing history, written with colortex3Clear=false, see the note in
// shaders.properties and lib/taa.glsl - and a uniform may only be declared once
// per program.

uniform sampler2D colortex3;
uniform sampler2D colortex4;
uniform sampler2D colortex7;
uniform sampler2D colortex8;
uniform sampler2D depthtex1;

// How far a reflection has to travel before the LOD ramp is complete, in blocks.
//
// BATCH 760. This is the one number that is NOT Bliss's, and the reason is worth
// stating because the obvious translation is wrong.
//
// Bliss's `reflectionLength` is not a distance. It is the fraction of the ray to
// the screen edge that the march consumed (`reflectionLength += 1.0 / quality`,
// lib/specular.glsl:169, where `stepv = direction * mult / quality` and `mult` is
// the ray's length to the edge, :128-130). So Bliss's ramp is over SCREEN SPAN,
// and its `min(max(reflectionLength - 0.1, 0.0)/0.9, 1.0)` (:212) means "the
// first tenth of the ray is perfectly sharp, the ramp covers the rest".
//
// ⚠️ BATCH 763: THE TRANSLATION BELOW WAS THE REASON NOTHING WAS VISIBLE, AND IT
// TOOK THREE BATCHES TO FIND BECAUSE IT LOOKS SO REASONABLE.
//
// 760 read "the first tenth of the ray" as "the first tenth of 64 blocks", which
// is 6.4 blocks, and made everything inside that perfectly sharp. But a metal
// reflects the wall and the floor a few blocks away - that is what a metal block
// in a build actually shows - so the reflections the author was looking at were
// ALL inside the dead zone, where the distance term is exactly 0.0 and the LOD is
// exactly 0.0 whatever the roughness does. 761 then pushed the roughness term from
// 5.14 to 6.00, which is 1.17x of zero.
//
// The scale is now 16 blocks and the sharp fraction is a length rather than a
// proportion, so that "near" means near in blocks and not in some fraction of a
// number that was itself a guess. 16 is where a reflection has crossed enough of
// the screen for the cone to span several texels at a typical field of view.
#define PBR_SSR_BLUR_DISTANCE 16.0

// How far from the fragment a reflection stays perfectly sharp, in blocks.
//
// BATCH 763: THIS IS A LENGTH NOW, NOT A FRACTION. As a fraction of
// PBR_SSR_BLUR_DISTANCE it was 6.4 blocks, which is most of what a metal reflects.
// Half a block is the distance at which a reflection is still the surface's own
// immediate surroundings - the thing the author's tap-based attempts kept eating -
// and past it the ramp starts immediately.
#define PBR_SSR_BLUR_SHARP_DISTANCE 0.5

// The narrowest cone the sky half of the reflection is averaged over, in pixels.
//
// BATCH 763. The cone is the roughness in radians, which is right for a dielectric
// and far too narrow for a polished metal: iron_block's roughness is 0.0167 rad,
// about 13 pixels at a 70 degree field of view, and a metal block reflects mostly
// sky - so those 13 pixels were the whole of its blur. See the note at the cone.
//
// 24 pixels is roughly the width of a block face at arm's length, which is the
// scale a metal block's reflection is read at. It is a starting value for the
// author to tune, and it is in pixels rather than radians so that it does not
// change with the field of view.
#define PBR_SSR_BLUR_MIN_CONE_PIXELS 24.0

// The highest mip level the reflection may be sampled at.
//
// Bliss uses 6.0 (lib/specular.glsl:213). A level is a halving of resolution, so
// 6 is a 64x64 box - far wider than any cone a surface's roughness opens, and it
// is the cap rather than the working range: the roughness term saturates well
// before it, and the distance term is what reaches it.
//
// It is a #define and not an option because the two terms that build the LOD are
// Bliss's and were tuned against its picture; exposing the cap would invite
// tuning a number that is not the one that needs tuning.
#define PBR_SSR_BLUR_MAX_LOD 6.0

// The depth of the surface each pixel shows with the translucents in it, and
// the one with neither the translucents nor the hand.
//
// Batch 663 reads the pair at the far end of the trace: the hand and the held
// item are in depthtex1 - which is what the march walks through - but not in
// depthtex2, so a hit that lands where the first is nearer has found the
// viewmodel rather than a place in the world.
//
// depthtex2 is declared here because this is where it is read. depthtex0 is not:
// the pass that includes this file (composite1) reads it in its fog upscale,
// which sits above this include in its source, so THAT pass declares it and this
// file uses that declaration - a uniform may only be declared once per program,
// and a shader has to see one before the code that uses it.
uniform sampler2D depthtex2;

uniform mat4 gbufferProjection;
uniform mat4 gbufferModelView;

uniform vec2 windowToNdc;

// Removed in batch 622: PBR_EDGE_SKY_MARGIN, PBR_MIN_REFLECTION_DISTANCE and
// ViewDistanceFromDepth. Both constants guarded a refusal that turned out to be
// aimed at the wrong cause - see the two removal notes in the body.

// The environment this fragment reflects, in linear RGB.
//
// Zero wherever there is nothing to reflect anything - see
// PbrReflectionPossible - which is most of the screen: only surfaces with a
// reflectance and a roughness to speak of, under an open sky, are covered.
//
// This is the only place the environment reflection exists. It used to be added
// where each surface was drawn, which meant the reflection could not include the
// world: a surface is drawn while the frame it belongs to is still being filled,
// so the depth buffer it would have to trace against is not finished. Here, in
// the composite stage, it is.
// seenThrough: whether this pixel is being looked at through something
// translucent - water, ice, glass. The caller answers it because it is a
// question about the two depth buffers, and only the caller has both; see
// the note on it below for what it is for.
// reflectionWeightOut: how much of the environment this pixel ends up taking, as
// a colour. The caller uses it to take that fraction *out* of the picture
// under PBR_ENERGY_CONSERVATION, so that the reflection replaces the light it
// stands for instead of being added on top of it. See the note on it where it
// is filled in.
// reflectionHitOut: whether the trace found the world at all. Written on every
// path through this function, because two readers depend on it: the body's own
// presence test below (batch 725 - a hit is a real sample however dark, and the
// weight may not be built from the sample's brightness) and the reflection debug
// view, which paints the pixels that fell back to the sky: that is how a
// boundary in the reflection is told apart from a boundary in the material
// without guessing, which took several rounds to learn.
// reflectionHitDistanceOut: how far from the fragment the hit was, in blocks, and
// zero where there was no hit. Used by the same debug view to mark the hits
// that are near enough to be this block's own geometry.
vec3 EnvironmentReflection(
	vec3 viewPos,
	float skyLight,
	bool seenThrough,
	out vec3 reflectionWeightOut,
	out bool reflectionHitOut,
	out float reflectionHitDistanceOut
) {
	#if defined(PBR_SSR)
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
			reflectionWeightOut = vec3(0.0);

			reflectionHitOut = false;
			reflectionHitDistanceOut = 0.0;
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
			reflectionWeightOut = vec3(0.0);

			reflectionHitOut = false;
			reflectionHitDistanceOut = 0.0;
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
			reflectionWeightOut = vec3(0.0);

			reflectionHitOut = false;
			reflectionHitDistanceOut = 0.0;
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

		vec3 worldReflected =
			PbrReflectionDirection(worldNormal, viewDirection);

		// How wide the cone of directions this surface reflects over is, and how
		// many pixels that comes to on screen.
		//
		// The angle is the roughness itself, in radians. It is not the alpha
		// PbrSpecular builds its highlight from: that is the roughness squared
		// (see PbrSpecular in pbr.glsl), so the blur opens with the roughness
		// while the highlight opens with its square. Both widen as the surface
		// gets rougher, which is the point - a rough surface should not keep a
		// mirror-sharp highlight beside a wide reflection - but they are not the
		// same number, which is why the angle is written out here rather than
		// read back from there.
		//
		// This used to be a radius in pixels proportional to roughness, which is
		// the same idea with the two conversions left out, and it came to about
		// a thirtieth of the right answer on a brushed metal: roughness in this
		// pack is (1 - smoothness)^2, so a surface whose authors were describing
		// a brushed finish arrives at 0.16, and 0.16 radians is not 0.16 pixels.
		//
		// The pixel scale is the one that turns an angle at the centre of the
		// screen into pixels: half the screen height, divided by the tangent of
		// half the field of view, which is what the projection's second row
		// carries - gbufferProjection[1][1] is 1 / tan(fovY / 2). windowToNdc is
		// two divided by the viewport size, so half the height is its reciprocal.
		//
		// BATCH 763: THE CONE HAS A FLOOR NOW, AND THAT IS WHAT MAKES A POLISHED
		// METAL'S SKY REFLECTION SOFT.
		//
		// The angle is the roughness, which is right for a dielectric - a stone
		// floor arrives at 0.44 rad and its sky reflection is properly wide. A
		// polished metal does not: iron_block's specular map is smoothness 222/255,
		// so its roughness is (1 - 0.871)^2 = 0.0167 rad, which is 13 pixels at a
		// 70 degree field of view. That is a mirror, and it is what the author was
		// looking at: a metal block reflects the sky, the trace finds nothing above
		// it, and the only blur it ever got was those 13 pixels.
		//
		// The floor is not a fudge to make metals look soft. It is the observation
		// that a reflection is never sharper than the buffer it is read from, and
		// the buffer is one sample per pixel: a cone narrower than a pixel is a
		// cone that cannot be resolved, so widening it to a pixel costs nothing and
		// is the honest answer. PBR_SSR_BLUR_MIN_CONE_PIXELS is that pixel, and it
		// is in pixels rather than radians so that it means the same thing at every
		// field of view.
		float coneAngle = clamp(roughness, 0.0, 1.0);
		float pixelsPerRadian = gbufferProjection[1][1]
			/ max(windowToNdc.y, 1.0e-6);
		coneAngle = max(coneAngle, PBR_SSR_BLUR_MIN_CONE_PIXELS / pixelsPerRadian);
		float blurPixels = coneAngle * pixelsPerRadian;

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
		//
		// The quantity that answers that is the sky light level, and it answers
		// it in the Overworld: a cave has none, an open field has all of it.
		//
		// It does not answer it in the End, and that is batch 726. The End has
		// no sky light level at all - it is lit by its own ambient, see
		// EndAmbientLighting in end_lighting.glsl, and the pack says the same
		// thing about the fog in environment/fog.glsl - so skyLight is zero
		// everywhere there and this factor was zero everywhere too. The End's
		// sky is not an atmosphere: it is a star field and a nebula, and it is
		// there in every direction whatever the light level says. Multiplying it
		// away left a polished block in the End reflecting nothing but its own
		// colour, which is the same "the reflection is not there" the author
		// reported after batch 725.
		//
		// EndSkyDimension() is the pack's own answer to "is the sky this
		// dimension's own", and it is the same predicate SkyColor above used to
		// choose the sky in the first place - so the gate and the sky agree by
		// construction, including the END_SKY option that can force the End's
		// sky on in every dimension. It is false in the Overworld and in the
		// Nether, which is what keeps the cave and interior protection exactly
		// as it was; the Nether is deliberately left alone, because this pack
		// has no Nether sky of its own for a reflection to show.
		bool skyIsAlwaysThere = EndSkyDimension();

		vec3 environment = SkyDither(
			gl_FragCoord.xy,
			skyReflection) * (skyIsAlwaysThere ? 1.0 : PbrSkyExposure(skyLight));

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

				// Written before the trace rather than by the branch that finds
				// something, and that is not tidiness: an out parameter is
				// undefined until it is written, and the miss path returns without
				// writing it. The guard further down reads this flag, so a value
				// that only one branch produced would be a flag from a branch that
				// did not run - the same class of mistake the guard itself had.
				reflectionHitOut = false;
				reflectionHitDistanceOut = 0.0;

				// The trace itself is ScreenSpaceRaytrace, in lib/raytrace.glsl,
				// and the note at its head is where the reason it is not the
				// world-space Raytrace lives. In one line: what has to be found
				// here is a block four metres away, and a ladder that doubles
				// puts its second sample at six and its third at fourteen.
				//
				// windowToNdc is handed over because the trace needs to know
				// where one pixel ends and the next begins: the fragment's own
				// surface is in the depth buffer too, and a sample that has not
				// left the pixel the ray started from is still standing on it.
				// Where in the first cell of the ladder this pixel starts, and it has
				// to move from frame to frame as well as from pixel to pixel.
				//
				// BATCH 766: THE FRAME TERM IS BACK, AND BATCH 758 WAS WRONG TO REMOVE
				// IT. 758 removed it on the argument that the reflection is applied
				// after the temporal resolve, so nothing averages a per-frame dither
				// and a moving one would simply be noise. The premise was false:
				// composite1.fsh:1537 writes `max(resolved, ...)` to the history, and
				// `resolved` carries the reflection - so the reflection IS in the
				// history, and has been all along. What 758 actually did was leave the
				// reflection in the history while making the dither identical every
				// frame, so the history had a noise it could not average. That is the
				// author's report: the SSR reflection shows clear noise.
				//
				// The frame term walks by the golden ratio, so the sequence does not
				// repeat on a short cycle and the history averages the lattice away
				// instead of reinforcing it. That is what it is for, and it only works
				// because the reflection is in the history - which it is.
				float traceDither = fract(
					Bayer8(gl_FragCoord.xy) * 1.32
					+ float(frameCounter) * 0.618034);

				// BATCH 764: THE RAY DIRECTION IS JITTERED OVER THE CONE, WHICH IS
				// WHAT MAKES THE REFLECTION SPREAD RATHER THAN MERELY BLUR.
				//
				// The author's report, after 763 finally made the blur visible: the
				// texture in the reflection is soft now, but the SHAPE of the block
				// is still pinned where it was, where Bliss's reflection looks
				// smeared out. That is exactly right, and it is a difference in what
				// is being blurred.
				//
				// 763 blurred the COLOUR the ray came back with. A mip level is a
				// wider average of the picture, so the picture's detail softens while
				// its outline stays where the single ray put it - and one ray has one
				// outline.
				//
				// Bliss blurs the DIRECTION instead (lib/specular.glsl:355-362):
				//
				//     vec3 samplePoints = SampleVNDFGGX(viewDir, roughness, noise.xy);
				//     vec3 reflectedVector_L = basis * reflect(-normalize(viewDir), samplePoints);
				//
				// and that jittered vector is what its march walks along (:411). So
				// every pixel's ray leaves at a slightly different angle, lands on a
				// slightly different place, and the reflection's outline is spread
				// over the cone - which is what "smeared out" looks like, and what a
				// rough surface actually does: it reflects a range of directions, not
				// one direction with a soft colour.
				//
				// The two uniform numbers are the spatial dither this pass already
				// computes, so the cost is zero and the reflection stays correlated
				// with the highlight rather than reading as noise on top of it.
				//
				// ⚠️ The cone is the roughness in radians - the same angle the sky
				// half is averaged over - so both halves of the reflection now agree
				// about width. A mirror (roughness 0) draws a zero-width cone and
				// keeps its exact direction, which is why a mirror still reads as a
				// mirror.
				vec3 rayDirection = PbrReflectionDirectionJittered(
					worldNormal,
					viewDirection,
					roughness,
					vec2(traceDither, fract(traceDither * 7.0 + 0.37)));

				if (ScreenSpaceRaytrace(
					depthtex1,
					gbufferProjection,
					gbufferProjectionInverse,
					viewPos,
					mat3(gbufferModelView) * rayDirection,
					windowToNdc,
					traceDither,
					hitPos,
					hitViewPos
				)) {
					reflectionHitOut = true;
					reflectionHitDistanceOut = length(hitViewPos - viewPos);

					// Removed in batch 622: this refused every hit closer than
					// half a block, on the theory that the bright line along block
					// edges was the trace sampling a groove wall or a bevel lip. It
					// was not that - it was a mapped normal turned past the eye,
					// fixed in PbrVisibleNormal - and the refusal cost the
					// reflection at the angles where it matters most: on a surface
					// seen almost edge-on the ray runs nearly parallel to it, so its
					// first honest hit is routinely within half a block, and the band
					// of floor near the horizon lost the sky it should have shown.
					//
					// The distance is still reported, because the debug view marks
					// near hits with it.
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
					// What the ray found, in the deferred pass's copy of THIS
					// frame.
					//
					// colortex4 and not colortex3, and that is not a detail: the
					// pass that calls this one (composite1) writes colortex3, so
					// what a read there returns is the previous frame's resolved
					// image - reflection included - and a trace that samples a
					// picture containing itself feeds on itself. colortex4 is
					// copy_and_fog.fsh's copy of the world as this frame left it,
					// which is also the frame this reflection is added to.
					//
					// BATCH 760: THE TRACED HALF IS BLURRED BY LOD, WHICH IS BLISS'S
					// ARRANGEMENT.
					//
					// Batches 631 and 660-668 tried to blur this with taps - an
					// eight-tap ring, then a 32/56-pixel Vogel disk - and the author
					// rejected both ("滤波看起来很奇怪、还把高光一起过滤了"). The
					// reason a tap filter failed is worth stating, because it is why
					// this is a different mechanism rather than a better-tuned one: a
					// tap filter averages a FIXED number of samples over a FIXED
					// radius, so it either blurs too little at high roughness or
					// costs a fortune at low roughness, and it always costs the same
					// whatever the surface is.
					//
					// Bliss does not take taps. It samples a higher MIP LEVEL
					// (lib/specular.glsl:211-213):
					//
					//     float LOD = mix(0.0, 6.0*(1.0-exp(-15.0*sqrt(roughness))),
					//                     1.0-pow(1.0-reflectionLength,5.0));
					//     reflection.rgb = texture2DLod(colortex5, previousPosition.xy, LOD).rgb;
					//
					// The mip chain is a prefiltered pyramid, so the cost is one
					// sample at any radius, and the radius is chosen per pixel by two
					// things that both matter:
					//
					//   * roughness - a rough surface sees a wide cone, so it wants a
					//     wide average. The `1 - exp(-15*sqrt(roughness))` term is
					//     steep near zero and saturates, which is the shape a
					//     microfacet distribution has.
					//   * reflectionLength - a reflection that travelled far has
					//     covered more screen, so the same cone spans more texels.
					//     The `1 - (1-x)^5` term is Bliss's, and it keeps a near
					//     reflection sharp however rough the surface is.
					//
					// The mip chain exists because copy_and_fog.fsh sets
					// colortex4MipmapEnabled, and Iris builds it after every composite
					// pass that reads the buffer - so by the time this pass samples it,
					// it is this frame's copy. See the note there.
					//
					// WHAT IS NOT TAKEN FROM BLISS: its `reflectionLength` is the
					// fraction of the ray to the screen edge that the march consumed,
					// not a distance (see the note on PBR_SSR_BLUR_DISTANCE). This
					// pack's trace reports blocks, so the same statement - "the first
					// stretch of the way is perfectly sharp, the ramp covers the rest"
					// - is written with two lengths instead of one number.
					float reflectionLength = clamp(
						(reflectionHitDistanceOut - PBR_SSR_BLUR_SHARP_DISTANCE)
							/ max(PBR_SSR_BLUR_DISTANCE
								- PBR_SSR_BLUR_SHARP_DISTANCE, 1.0e-4),
						0.0, 1.0);

					// BATCH 763: THE ROUGHNESS IS USED AS IT ARRIVES, AND BATCH 761'S
					// TRANSFORM WAS A SECOND DECODE.
					//
					// 761 added `roughness = 1.0 - roughness; roughness *= roughness;`
					// here, copying Bliss's lib/specular.glsl:338-339. That was wrong,
					// and the reason is that this pack had already done it: the
					// material decode is `pbr.roughness = pow(1.0 - specularSample.r,
					// 2.0)` (environment/lighting/pbr.glsl:1974), which is the same
					// (1 - smoothness)^2 Bliss applies at its line 338. So 761 decoded
					// a value that was already decoded - iron went from 0.0167 to
					// 0.9668 - and pushed the LOD term from 5.14 to 6.00, which is the
					// wrong direction for a surface that should be blurred.
					//
					// The value that arrives here is already the linear roughness the
					// formula wants. See the note on PBR_SSR_BLUR_DISTANCE for the
					// other half of why nothing was visible.
					float reflectionLod = mix(
						0.0,
						PBR_SSR_BLUR_MAX_LOD
							* (1.0 - exp(-15.0 * sqrt(roughness))),
						1.0 - pow(1.0 - reflectionLength, 5.0));

					vec3 hitColor = textureLod(colortex4, hitPos, reflectionLod).rgb;

					// Fade the result out near the edge of the screen, where the
					// ray is about to leave the buffer and there is nothing more
					// to find. Without this the reflection would stop at a hard
					// line.
					vec2 hitPosAbs = abs(hitPos * 2.0 - 1.0);
					float edgeFade = min(
						1.0,
						(1.0 - max(hitPosAbs.x, hitPosAbs.y)) / 0.10);

					// Batch 663: the hand and the held item are not part of the
					// world, so they are not part of what the world reflects.
					//
					// They are drawn in front of the camera at their own depth,
					// which means the march - walking depthtex1 - can land on
					// them like any other geometry, and what it then samples out
					// of the previous frame is the player's own arm where a
					// floor or a wall should be. The two depth buffers separate
					// the case exactly: depthtex0 has the hand in it, depthtex2
					// does not, so the hand is where the first is the nearer.
					// A hit there is treated as a miss, which is the same answer
					// the surface would have given before the trace ran: the sky.
					//
					// The texel is clamped because a hit two thousandths of a
					// pixel outside the buffer is not a place, and a fetch there
					// has no defined result.
					ivec2 hitTexel = clamp(
						ivec2(hitPos * 2.0 / windowToNdc),
						ivec2(0),
						ivec2(textureSize(depthtex0, 0)) - 1);
					float handFade = texelFetch(depthtex0, hitTexel, 0).r
						< texelFetch(depthtex2, hitTexel, 0).r
						? 0.0
						: 1.0;

					environment = mix(environment, hitColor, edgeFade * handFade);
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

		// Nothing to reflect is not the same as reflecting black.
		//
		// The weight below is what the caller takes OUT of the picture when it
		// replaces instead of adding, so it may only be as large as what the
		// reflection actually brings back. Indoors, underground and wherever the
		// sky is out of sight, the environment here is nothing at all - and a
		// weight of nearly one against an environment of zero is a surface
		// multiplied towards black and given nothing in its place. That is what
		// happened to metals: their Fresnel is high at every angle, so they lost
		// most of their own light to a reflection that had no light in it.
		// (Batch 621 section 20, which is where the floor comes from.)
		//
		// The floor is a luminance of a fiftieth, which is the point where a
		// reflection stops being able to stand in for a surface's own colour.
		//
		// Batch 725: it is a test of PRESENCE, and only the miss case needs it.
		// The trace already answers whether anything was sampled at all, and a
		// hit is a sample of the world however dark it is - the reflection of a
		// black block is black. Growing the floor out of the sampled colour
		// instead made the weight smaller exactly where the hit was darker, so a
		// hit below the floor kept the reflective surface's own colour instead of
		// replacing it: on a pale polished block the darkest content came out the
		// brightest, with the shape and the hue intact and at every viewing
		// angle. `_team_bfog/reflection_value_chain_725.py` sweeps the chain:
		// d(out)/d(hit luminance) was negative, down to -20.8 at a hit luminance
		// of 0.01, and is +0.73 everywhere once the flag below is used.
		//
		// The miss case keeps the floor exactly as it was: there the environment
		// really is the sky term, and "no sky in sight" is the case it was
		// written for.
		//
		// Batch 726: a dimension whose sky is not an atmosphere is the second
		// case where the floor is the wrong question. The End's sky is a star
		// field with a floor of about 0.0035, which is below this floor by
		// construction - so even with the exposure gate above opened, the floor
		// would scale the weight down to a fortieth and the reflection would
		// still be missing. Where the sky is always there, it is there however
		// dark it is, and the same predicate that opened the exposure gate
		// answers it.
		float environmentLuminance = dot(
			environment,
			vec3(0.2126, 0.7152, 0.0722));
		float environmentPresent = (reflectionHitOut || skyIsAlwaysThere)
			? 1.0
			: smoothstep(0.0, 0.02, environmentLuminance);

		// How much of the environment this surface takes, as a colour, before the
		// environment itself is multiplied in.
		//
		// Reported separately as well as used below, because the caller needs it:
		// with PBR_ENERGY_CONSERVATION on, the reflection REPLACES that fraction
		// of the picture instead of being added to it, which is the difference
		// between a metal and a metal with a white film over it. Bliss composites
		// the same way - mix(DarkenedDiffuseLighting, reflection, F0) - and it is
		// why its metals stay the colour of their metal.
		// The clamp is applied once and the clamped value is what is returned, and
		// that is not tidiness - it is the difference between a metal and a blown-out
		// white mirror (batch 626).
		//
		// With PBR_SPECULAR_STRENGTH at 2.0 a metal's weight is routinely above one:
		// iron's reflectance is 0.78, so 2.0 * 0.78 is 1.56. The composite below
		// subtracts `weight` from the picture and adds the reflection back in its
		// place, so an unclamped weight subtracts one at most - the clamp on the
		// weight the caller reads - and adds one and a half. The surface then reflects
		// half again more than the light that reached it, its own colour is replaced by
		// more than all of it, and what is left on screen is a pale wash where the
		// metal's reflectance should have been visible. It went unnoticed until the
		// strength was raised from 1.0, which is the only value at which every weight
		// was already below one.
		//
		// A surface cannot reflect more than all of the environment it stands in, which
		// is what the clamp says; the strength then only decides how quickly a surface
		// gets there, not how far past it goes.
		vec3 weight = strength
			* PbrReflectionFresnel(f0, PbrMetalF82(metalID), NdotV, roughness)
			* reflectionWeight
			* environmentPresent;
		reflectionWeightOut = clamp(weight, vec3(0.0), vec3(1.0));

		return reflectionWeightOut * environment;
	#else
		// Nothing here reflects anything, so nothing may be taken out of the
		// picture in its name either.
		reflectionWeightOut = vec3(0.0);

		reflectionHitOut = false;
		reflectionHitDistanceOut = 0.0;
		return vec3(0.0);
	#endif
}
