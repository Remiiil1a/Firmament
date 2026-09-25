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

// Added 2026-09-22 by Remiiil1a for Firmament. See PBR_PORTING.md 128.

// Ambient occlusion.
//
// What this is for: Minecraft's own lighting is one number per block, so it has
// nothing to say about the inside of a corner - a wall is exactly as bright at
// its base as it is at its top, and two blocks meeting look like one surface
// folded rather than two surfaces touching. Light does not actually arrive that
// way, and the difference is most of what makes a scene look flat.
//
// This asks the depth buffer, per pixel, how much of the sky around this point
// is standing behind something else. It is a screen-space effect and inherits
// the usual limits of one: only what is on screen occludes, and thin geometry is
// missed.
//
// It runs in the deferred pass, which is the pass before composite1 resolves the
// frame over time. That placement is the point of it: the samples here are noisy
// and the dither that makes them noisy moves every frame, so the temporal filter
// downstream is what turns the noise into a smooth result. Applying this after
// the resolve instead would leave every bit of that noise in the picture - see
// PBR_PORTING.md 55.2, where the first attempt did exactly that and had the
// variance clamp pull the occlusion back out every frame.

// Whether to darken what the sky cannot reach.
//
// Off by default while it is new: it is the one effect here that changes the
// brightness of everything on screen, so it should be turned on deliberately and
// compared against having it off.
//
// The #ifdef is not decoration: Iris only treats a bare #define as a boolean
// option if the macro is referenced by an #ifdef or #ifndef somewhere.
//#define AMBIENT_OCCLUSION
#ifdef AMBIENT_OCCLUSION
	// How much of the occlusion to apply. 0 is off without the option being off,
	// which is what makes it possible to judge the effect against itself rather
	// than against a version of the pack that differs in other ways too.
	#define AO_STRENGTH 1.0 // [0.0 0.25 0.5 0.75 1.0]
	// Up to 1.0 and no further, and that cap is not a matter of taste. This value
	// multiplies the frame by mix(1.0, ao, AO_STRENGTH), so a strength above 1.0
	// turns a fully occluded pixel - where ao is 0 - into a negative one, and a
	// negative colour is drawn as black. It is the same hole the screen-space
	// shadows had, reached the same way and just as permanent, because this pass
	// writes the buffer the temporal history is built from. The list used to run
	// to 1.5. See PBR_PORTING.md 136.

	// How far a sample is allowed to be from the point it is testing, in blocks.
	//
	// This is the scale of the effect: about a block reaches the corner where two
	// walls meet and the gap under a fence, and stops well short of the shading
	// that the sun and the sky already do at larger scales. Raising it reaches
	// further and costs nothing extra - the count below is what sets the cost -
	// but it also spreads the same number of samples over a larger disk, so the
	// result comes out coarser as well as broader.
	#define AO_RADIUS 1.5 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0]

	// How many samples are taken per pixel.
	//
	// This is the pass's cost - one depth fetch each - and it is the dial for how
	// noisy the result is. The noise falls with the square root of it, so doubling
	// the count is worth about a third less noise for twice the work; the default
	// sits above the first version's twelve for that reason.
	#define AO_SAMPLES 24 // [4 8 12 16 24 32]

	// Show the occlusion and nothing else: black where the sky is fully blocked,
	// white where nothing is in the way.
	//
	// This exists because ambient occlusion is the one thing in this pack whose
	// failure mode is "it looks like nothing happened". An occlusion that is
	// measuring nothing, one that is measuring everything, and one that is simply
	// too weak all read as the same slightly flat picture - so there has to be a
	// way to see the measurement itself before its result. See the note on
	// AO_STRENGTH above for the other half of that.
	//#define AO_DEBUG
#endif

// The loop bound for the sample count, which is an option and so cannot be the
// bound itself. Kept outside the option's guard because the function below is
// inside it and the two are compiled together either way.
const int AO_SAMPLE_LIMIT = 32;

// How far along its own normal a sample is pushed before it is tested, in blocks.
//
// This is the one number that decides whether the result is a contact shadow or
// a grey wash, and it is worth being exact about why. A sample sitting exactly on
// the surface projects back onto the surface it came from, where the depth buffer
// holds the same depth - and a depth buffer's depth is quantised, so "the same"
// reads as "very slightly nearer" about half the time and the surface occludes
// itself everywhere. Lifting the sample off the surface by more than the
// quantisation is what stops that.
//
// Lifting it further than that does the opposite and is worse: a sample floating
// a fraction of a block off a flat floor finds no floor above it and no wall
// beside it, so every pixel loses a little light equally. That is the grey wash.
// The first version of this pack's ambient occlusion lifted by half the radius -
// 1.25 blocks - and that is exactly what it looked like.
//
// The bias in the test below is the same idea for the other side of the
// comparison; see Tolerance below for why it cannot be a constant.
const float AO_NORMAL_OFFSET = 0.05;

// How much coarser than the depth buffer the test is allowed to be, as a
// fraction of how far the point is from the eye.
//
// This is the part that the first attempt at this effect got wrong, and it is
// worth spelling out because a constant looks like it should work. The depth
// buffer's precision is not uniform: it is dense near the camera and coarse far
// from it, so a fixed bias of a few centimetres is generous at arm's length and
// far smaller than one unit of the buffer twenty blocks away. With a fixed bias
// every sample out there reads as occluded, every pixel darkens by the same
// amount, and the picture goes grey rather than gaining corners.
//
// It is also why the sky and the block light are not the things measured here:
// this compares two view-space positions and asks how far apart they are in
// blocks, which is a question the buffer can answer at any distance.
//
// The same window, at the same rate, is what lib/sss.glsl uses for the shadows
// the shadow map does not reach - and that one was measured from the driver's
// seat and works.
const float AO_DEPTH_RATE = 0.02;

// How thick a surface in front of a sample has to be to count as blocking it, in
// blocks, before the distance term above is added.
//
// Without an upper bound as well as a lower one, everything in front counts: a
// wall across the valley sits between a sample and the camera just as much as
// the wall beside it does, and the result is the same flat darkening by a
// different route. The bound is what says that an occluder is a surface *here*,
// which is what a corner is made of.
const float AO_THICKNESS = 1.5;

// The golden angle, in radians, and the number of turns in a circle.
//
// The samples are spread over their disk with a golden-angle spiral, which is
// the most even coverage a handful of them can give - the same shape the light
// bleed uses, and for the same reason: a regular pattern would show up as rings
// in the result.
const float AO_GOLDEN_ANGLE = 2.39996323;
const float AO_TAU = 6.28318531;

// The sky this fragment can see, as a factor: 1.0 where nothing stands in the
// way, and less the more of its surroundings are blocked.
//
// viewPos is this fragment's position in view space and viewNormal its normal,
// also in view space - which is the space the depth buffer's positions come back
// in, so that the two can be compared as distances in blocks.
//
// dither offsets the sample pattern per pixel and, through the noise that feeds
// it, per frame. It is passed in rather than computed here so that this file
// needs no uniforms of its own: every one it uses belongs to the program that
// includes it, which is also how lib/sss.glsl's ScreenSpaceShadow is written.
#ifdef AMBIENT_OCCLUSION
	float AmbientOcclusion(
		sampler2D depthTexture,
		mat4 projection,
		mat4 projectionInverse,
		vec3 viewPos,
		vec3 viewNormal,
		float dither
	) {
		vec3 normal = normalize(viewNormal);

		// Any pair of axes across the normal will do to place the samples in.
		vec3 tangent = abs(normal.z) < 0.9
			? normalize(cross(normal, vec3(0.0, 0.0, 1.0)))
			: normalize(cross(normal, vec3(1.0, 0.0, 0.0)));
		vec3 bitangent = cross(normal, tangent);

		float angle0 = dither * AO_TAU;
		float blocked = 0.0;
		float tested = 0.0;

		for (int i = 0; i < AO_SAMPLE_LIMIT; i++) {
			if (i >= AO_SAMPLES) {
				break;
			}

			// Distance from the centre, spread so that the samples cover the disk
			// evenly rather than crowding it, and an angle that walks around it by
			// the golden angle.
			float t = (float(i) + 0.5) / float(AO_SAMPLES);
			float angle = angle0 + float(i) * AO_GOLDEN_ANGLE;

			// The sample itself: on the disk across the surface, then lifted along
			// the normal. See AO_NORMAL_OFFSET for why the lift is small and why it
			// cannot be zero.
			vec3 samplePos = viewPos
				+ tangent * (cos(angle) * sqrt(t) * AO_RADIUS)
				+ bitangent * (sin(angle) * sqrt(t) * AO_RADIUS)
				+ normal * AO_NORMAL_OFFSET;

			// Where that sample lands on screen. A sample behind the camera has no
			// position to test, and one off the edge of the screen has no depth to
			// read - neither is an occluder, so neither is counted either way.
			vec4 sampleH = projection * vec4(samplePos, 1.0);
			if (sampleH.w <= 0.0) {
				continue;
			}

			vec2 sampleCoord = (sampleH.xy / sampleH.w) * 0.5 + 0.5;

			if (any(lessThan(sampleCoord, vec2(0.0)))
				|| any(greaterThan(sampleCoord, vec2(1.0)))) {
				continue;
			}

			float sceneDepth = texture(depthTexture, sampleCoord).r;

			// The sky is nothing to be blocked by, and a sample whose pixel shows
			// sky was never going to be blocked by it.
			if (sceneDepth >= 1.0) {
				tested += 1.0;
				continue;
			}

			// Where the surface at that screen position is, in the same space as
			// the sample - so that the two can be compared as a distance in blocks.
			vec2 ndcCoord = sampleCoord * 2.0 - 1.0;
			vec4 sceneH = projectionInverse
				* vec4(ndcCoord, sceneDepth * 2.0 - 1.0, 1.0);
			vec3 scenePos = sceneH.xyz / sceneH.w;

			// A sample whose scene position is not usable is counted as having
			// found nothing, and never as an occluder. Written as one bound rather
			// than as two tests because it has to catch three things at once: a
			// point that is absurdly far away, one that came out infinite, and one
			// that came out as a NaN - and a NaN fails every comparison, including
			// this one, which is what makes the negation the check.
			//
			// It matters here more than it looks. The occlusion is a factor
			// multiplied into the frame, and the pass after this one writes its
			// own result back for the next frame to read, so a factor that is not
			// a number does not fade - it spreads. See PBR_PORTING.md 130.
			if (!(dot(scenePos, scenePos) < 1.0e18)) {
				tested += 1.0;
				continue;
			}

			// View space looks down the negative Z axis, so a surface *nearer to
			// the camera* than the sample has the larger z. The sample is blocked
			// exactly when the surface is in front of it, so this is the scene's z
			// minus the sample's.
			float gap = scenePos.z - samplePos.z;

			// How far from the eye the sample is, which is what the depth buffer's
			// precision depends on. See AO_DEPTH_RATE.
			float fromEye = length(samplePos);
			float tolerance = max(0.05, fromEye * AO_DEPTH_RATE);
			float thickness = AO_THICKNESS + fromEye * AO_DEPTH_RATE;

			// How much this sample counts as an occluder: fully in the middle of the
			// band where the surface it found is plausibly the thing standing in the
			// way, and less towards either edge of that band. A hard yes or no per
			// sample is what quantises the result into visible steps, and dithering
			// only moves where those steps land.
			float softness = max(0.25, fromEye * AO_DEPTH_RATE);

			blocked += smoothstep(tolerance, tolerance + softness, gap)
				* (1.0 - smoothstep(thickness - softness, thickness, gap));

			// Counted whether or not this sample found anything. Dividing by the
			// number of samples *taken* instead would treat every sample that fell
			// off the screen or onto the sky as an unoccluded one, which dilutes the
			// result by however much of the disk happened to leave the frame - and
			// it dilutes it most where the frame is busiest.
			tested += 1.0;
		}

		if (tested <= 0.0) {
			return 1.0;
		}

		// Bounded, and checked for being a number before it is bounded: clamp()
		// of a NaN is not defined to return anything in particular, and this value
		// is multiplied into the frame and then fed back through the temporal
		// history. "Nothing is blocked" is the answer that cannot make the picture
		// worse, so that is what a value that is not a number becomes.
		float visibility = 1.0 - blocked / tested;

		if (isnan(visibility)) {
			return 1.0;
		}

		return clamp(visibility, 0.0, 1.0);
	}
#endif
