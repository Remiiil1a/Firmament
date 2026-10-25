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

// Added 2026-09-16 by Remiiil1a for Firmament - v0.3 (edit of coderbot's Steadfast).

// Screen-space shadows.
//
// The shadow map only covers a fixed distance around the player, and terrain
// beyond it - Distant Horizons' level of detail terrain, Voxy's, and in general
// anything drawn past the shadow distance - gets light from the sun and casts
// none of its own. On a landscape with hills that is the most conspicuous thing
// about the distance: a valley sits in full sun no matter what stands between it
// and the sun.
//
// This walks a ray from the fragment towards the sun through the depth buffer
// instead. Whatever the buffer says is in the way, is in the way - and the depth
// buffer holds everything that writes depth, so terrain drawn by another mod
// casts shadows here just like the pack's own does.
//
// It is faded in over the shadow distance rather than applied everywhere, and
// what that means at this point in the file is the caller's blend and not this
// file's: inside that distance the shadow map is both more accurate and already
// paid for, so this contributes nothing there, and past the end of the fade
// window it is the only shadow the distance has. The two are both partly on
// across the window itself, which is what keeps the seam from showing. See the
// note at the call in program/post/copy_and_fog.fsh for how the window is built.

// Whether to cast shadows for terrain the shadow map does not reach.
//
// On by default: without it the distance is lit flat, which reads as a seam at
// the edge of the shadow distance.
//
// The #ifdef is not decoration: Iris only treats a bare #define as a boolean
// option if the macro is referenced by an #ifdef or #ifndef somewhere.
#define SCREENSPACE_SHADOWS
#ifdef SCREENSPACE_SHADOWS
	// How dark the shadows get, where 1.0 is as dark as the sun's own
	// contribution could be. It is applied to the whole colour rather than to
	// the sunlight alone, because by the time this pass runs the two are already
	// added together - so a value near 1.0 also takes some sky light with it.
	#define SSS_STRENGTH 0.5 // [0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.9 1.0]

	// The most this effect is allowed to darken a pixel by, as a fraction of its
	// own colour. 0.9 is the behaviour this had before the option existed, and it
	// is the default; lowering it keeps the distance shadows from ever getting
	// close to black.
	//
	// It exists because of what it multiplies. SSS_STRENGTH above already says
	// this is applied to the whole colour rather than to the sunlight alone - by
	// the time this pass runs, the direct light, the sky light, the ambient and
	// the reflection have all been added into one number, and there is no way to
	// take the sun back out of it. So the effect's strength and its risk are the
	// same dial: at full strength a fully occluded pixel keeps a quarter of its
	// colour, which on a dim surface is not a shadow but a hole. This separates
	// the two - how much of the effect to use, and how dark it may ever get.
	//
	// Batch 642 moved both defaults down - SSS_STRENGTH to 0.5 and this to
	// 0.55 - because the effect stopped averaging in batch 641 and started
	// deciding, and a decision reaches zero where an average never did. Until 641
	// this cap could not bind at all (the weight peaked below it), so the buffer
	// here is the first one written against a result that actually gets there:
	// the author's report was that the shadows had structure and were too dark.
	//
	// The earlier note about a black blot is kept in BATCH_LOG.md 155 rather than
	// here, because it no longer describes this option's default: turning the whole
	// effect off never stopped that blot, so the value was never the cause.
	//
	// The correct fix for the argument above is still to attenuate the sunlight
	// alone, which needs the surface programs to keep the direct and indirect parts
	// apart - the next step in this sequence. See BATCH_LOG.md 154.
	#define SSS_DARK_LIMIT 0.55 // [0.0 0.25 0.4 0.5 0.55 0.6 0.7 0.8 0.9]

	// How many steps the ray takes, spread evenly across the ray's length on
	// screen. More steps mean the samples sit closer together, which is what
	// keeps the shadow's edge from breaking up into the gaps between them.
	#define SSS_STEPS 32 // [8 12 16 24 32 48]

	// How high above the receiver the ray has to be able to climb, in blocks, and
	// the length that implies.
	//
	// This used to be the ray's length, and a fixed one. The two are different
	// questions. A ridge shadows a valley when the ray clears the ridge's height,
	// and how far away that is depends entirely on how high the sun is: at a high
	// sun the same height is reached in a fraction of the distance it takes at a
	// low one. A fixed length was therefore too long overhead and too short at the
	// angles that matter - the low ones, where the shadows are long and where a
	// fixed 48 blocks reached barely a dozen blocks of height (batch 645).
	#define SSS_LENGTH 24.0 // [8.0 16.0 24.0 32.0 48.0]

	// The cap on that division and the floor on the elevation it divides by. A sun
	// just above the horizon would otherwise ask for a ray hundreds of blocks long,
	// which is both wrong for a screen-space effect - the depth buffer holds a few
	// dozen blocks at most out here - and the most expensive case there is.
	const float SSS_MAX_LENGTH = 96.0;
	const float SSS_MIN_ELEVATION = 0.05;

	// How thick an occluder is allowed to be, as a fraction of how far along the
	// ray it was met.
	//
	// A ray that runs into a hill meets its surface almost exactly where it
	// reaches it. A ray that merely passes *in front of* something - an entity,
	// the held block, a tree nearer the camera than the terrain being shaded -
	// meets that thing hundreds of blocks short, and that is not an occluder.
	// The window below is what tells the two apart, and the distance it is
	// measured over is in blocks, in view space.
	//
	// The two constants below are not the window on their own: the test that
	// uses them combines them with a floor of 0.05 and with one step's worth of
	// depth, so the base thickness is `max(SSS_THICKNESS_BASE, stepInBlocks)`,
	// the rate term is `travelled * SSS_THICKNESS_RATE`, and a step's depth is
	// added separately. See the thickness assignment at the test.
	//
	// Sundial measures it in the depth buffer's own units instead, as a fraction
	// of the distance. That is not portable to this pack's depth buffer: those
	// units are not linear in distance, so out at the range this feature works
	// over the entire distant world sits in the last thousandth of the range and
	// a window expressed in them stops distinguishing anything from anything
	// else. Trying it caught nearly every sample and turned the whole distance
	// black, which is what this comment is here to stop anyone repeating.
	//
	// Batch 640 sharpened both of these, and the step count above, because the
	// report was that the shadows are blurry and the cause was arithmetic rather
	// than taste.
	//
	// The ray took 12 steps across 48 blocks - one sample every 4 blocks - so an
	// edge could only land on one of thirteen places along it and the result read
	// as a gradient. At 32 steps a sample falls every 1.5 blocks and the edge lands
	// where it belongs.
	//
	// The base thickness was 2 blocks. A tree's branch, a fence post, the lip of a
	// leaf canopy - anything thinner than two blocks - was too thin to count as an
	// occluder at all, and geometry that cannot occlude leaves a smooth wash where
	// its shadow should be. It is 0.75 now, with half the rate, which is what turns
	// those into shadows without turning everything into one.
	const float SSS_THICKNESS_BASE = 0.75;
	const float SSS_THICKNESS_RATE = 0.01;

	// What the blocked fraction of the ray is multiplied by before the shadow is
	// worked out - the dial for how dark a shadow gets.
	//
	// A ray that runs into a hillside is usually blocked over *part* of its
	// length rather than all of it: the far end of the ray passes over the hill
	// and comes out the other side, or the sample spacing steps past it. So the
	// fraction comes out well below one even for a shadow that should be solid,
	// and the shadow reads as faint. This is what to raise for that.
	//
	// It multiplies the *fraction*, never the per-sample count, so the result
	// still does not depend on the step count.
	#define SSS_GAIN 2.0 // [1.0 1.25 1.5 1.75 2.0 2.5 3.0 4.0]

	// SSS_GAIN, SSS_FULL_OCCLUSION and SSS_STEP_LIMIT described the old 
	// fractional logic, which is gone in batch 641. They are marked deprecated here 
	// rather than deleted in the same batch: SSS_GAIN is still listed in the menu and 
	// removing it means editing the profile, the slider list and both language files, 
	// which is a separate, safe change. Nothing reads them any more.

	// How much of the ray has to be blocked before the shadow is as dark as it
	// gets. The shadow is the *fraction* of the ray the depth buffer says is
	// blocked, so this is the whole of the tuning: a ray that runs into a hill is
	// blocked at nearly every sample and goes dark, and one that is blocked at a
	// few reads as light shading.
	//
	// It is deliberately a fraction rather than a running darkening applied per
	// occluded sample. Multiplying the light down once per hit made the result
	// depend on how many samples there were at all: raising the step count
	// darkened the image further even where nothing had changed, because whatever
	// the test wrongly counts as an occluder - and out at this range the depth
	// buffer is coarse enough that it will count some - gets more chances the
	// more samples are taken. That was measured from the driver's seat, by
	// lowering the step count until the darkening went away.
	const float SSS_FULL_OCCLUSION_DEPRECATED = 1.0;

	// The loop below needs a constant bound, so the option above selects how many
	// of a fixed set of iterations actually run.
	const int SSS_STEP_LIMIT_DEPRECATED = 32;
#endif

// The frame number, so that the dither below can move from frame to frame.
uniform int frameCounter;

// Cheap per-pixel value in 0..1, used to offset the first step of the ray so that
// neighbouring pixels do not march through the same sample positions.
//
// The offset also moves from one frame to the next, and that is the whole reason
// the temporal filter can do anything about this noise. A value that depended on
// the pixel alone is the *same* value in the history as it is in the current
// frame, so averaging the two averages the noise with itself and keeps it in
// full: it is a fixed pattern baked into the image, and no amount of history
// removes a pattern that never changes. Noise is only removable over time if it
// is different every frame, which is what the shift below makes it.
//
// Sundial does exactly this to the dither its own screen-space effects use
// (bayer64Temporal, in libs/Common.glsl): an ordered pattern shifted by an
// irrational fraction of its range per frame, so that a run of frames fills the
// range evenly instead of repeating. The constant here is the same golden-ratio
// step they approximate with sqrt(0.4), and the 64-frame wrap keeps the shifted
// value exactly representable in a float.
float SssScreenNoise(vec2 fragCoord) {
	float noise = fract(sin(dot(fragCoord, vec2(12.9898, 78.233))) * 43758.5453);
	float shift = float(frameCounter % 64) * 0.618034;
	return fract(noise + shift);
}

// The shadow at one fragment, as a fraction of the light that reaches it: 1.0
// where nothing is in the way, and darker the more of the ray the depth buffer
// says is blocked.
//
// viewPos is this fragment's position in view space and lightDirection points
// from it towards the sun, also in view space. No surface normal is needed: the
// ray only asks whether something stands between this point and the light.
#ifdef SCREENSPACE_SHADOWS
	float ScreenSpaceShadow(
		sampler2D depthTexture,
		mat4 projection,
		mat4 projectionInverse,
		vec3 viewPos,
		vec3 lightDirection
	) {
		// The ray is walked in *screen* space, and that is the whole reason it is
		// not walked in view space.
		//
		// Stepping a fixed distance in view space and projecting each step puts
		// the samples an uneven distance apart on the screen. A ray that runs
		// nearly parallel to the screen plane - which is exactly what a low sun
		// gives - covers many pixels per step, so the gaps between samples open
		// up, and what comes out is stripes that radiate from the sun rather than
		// a shadow. Stepping evenly between the projected ends of the ray keeps
		// the samples the same number of pixels apart at every sun angle. This is
		// how Sundial's screen-space shadows are built, and why they do not show
		// this.
		vec4 originClip = projection * vec4(viewPos, 1.0);

		if (originClip.w <= 0.0) {
			return 1.0;
		}

		vec2 originScreen = originClip.xy / originClip.w * 0.5 + 0.5;
		float originDepth = originClip.z / originClip.w * 0.5 + 0.5;

		// The far end of what the ray is allowed to reach, before projecting it.
		// Taken no further than the camera plane: a point at or behind that plane
		// has no screen position to aim at, and the ray is stopped where it
		// crosses instead.
		//
		// The length comes from the light's elevation, not from a constant: the ray
		// has to climb SSS_LENGTH blocks of terrain, and the distance that takes is
		// the height over the sine of the angle it climbs at. lightDirection is in
		// view space, so the world's up axis is the view matrix' transpose applied
		// to it - the same transpose the caller uses to answer the same question.
		vec3 lightWorld = transpose(mat3(gbufferModelView)) * lightDirection;
		float lightSine = max(abs(lightWorld.y), SSS_MIN_ELEVATION);
		float sssRayLength = clamp(SSS_LENGTH / lightSine, 8.0, SSS_MAX_LENGTH);

		vec3 farViewPos = viewPos + lightDirection * sssRayLength;
		vec4 farClip = projection * vec4(farViewPos, 1.0);

		if (farClip.w <= 1.0e-4) {
			float along = (originClip.w - 1.0e-4)
				/ max(originClip.w - farClip.w, 1.0e-6);

			farViewPos = mix(viewPos, farViewPos, clamp(along, 0.0, 1.0));
			farClip = projection * vec4(farViewPos, 1.0);
		}

		vec2 farScreen = farClip.xy / farClip.w * 0.5 + 0.5;
		float farDepth = farClip.z / farClip.w * 0.5 + 0.5;

		// Stop at the edge of the screen. Past it there is no depth to ask, and
		// the edge itself is not an occluder - treating it as one drew a shadow
		// down the sides of the screen.
		vec2 delta = farScreen - originScreen;
		float reach = 1.0;

		if (abs(delta.x) > 1.0e-6) {
			reach = min(reach, (delta.x > 0.0 ? 1.0 - originScreen.x : -originScreen.x)
				/ delta.x);
		}

		if (abs(delta.y) > 1.0e-6) {
			reach = min(reach, (delta.y > 0.0 ? 1.0 - originScreen.y : -originScreen.y)
				/ delta.y);
		}

		reach = clamp(reach, 0.0, 1.0);
		delta *= reach;

		// One step's worth of everything, so that the loop below is a single
		// multiply-add per sample.
		float screenLength = length(delta);
		vec2 stepDirection = screenLength > 1.0e-6 ? delta / screenLength : vec2(0.0);
		float stepInScreen = screenLength / float(SSS_STEPS);
		float stepInDepth = (farDepth - originDepth) * reach / float(SSS_STEPS);

		// How far one step of the march travels in blocks, which is the unit the
		// thickness window below is measured in.
		//
		// Every input is settled before this point: farViewPos at its own
		// assignment above, viewPos is read-only, reach was clamped a few lines
		// up, and SSS_STEPS is a compile-time count. So the whole expression is
		// the same number on every step of the loop, and it was written inside
		// the loop, which cost an sqrt and a division per sample to arrive at a
		// value it already had.
		float stepInBlocks = length(farViewPos - viewPos)
			* reach / float(SSS_STEPS);

		float dither = SssScreenNoise(gl_FragCoord.xy);

		// The bound is SSS_STEPS itself (batch 641). It used to be a separate
		// SSS_STEP_LIMIT of 24 while the result was divided by SSS_STEPS, so any setting
		// above 24 marched 24 steps and divided by more than it had walked - the mean
		// per sample fell as the count rose, which is one more reason raising the count
		// changed nothing.
		for (int i = 0; i < SSS_STEPS; i++) {

			// The first sample is offset a random fraction of a step per pixel,
			// so that neighbouring pixels do not step through the same sample
			// positions and the shadow boundary does not quantise into bands.
			//
			// It moves every frame as well - see SssScreenNoise - which is what
			// leaves the temporal filter in composite1 something to average: with
			// the dither standing still, the noise reached the history unchanged
			// and stayed in the image in full.
			float travel = float(i + 1) + dither;
			vec2 sampleCoord = originScreen + stepDirection * (stepInScreen * travel);
			float rayDepth = originDepth + stepInDepth * travel;

			if (any(lessThan(sampleCoord, vec2(0.0)))
				|| any(greaterThan(sampleCoord, vec2(1.0)))) {
				break;
			}

			// The sky is nothing to be blocked by.
			float sceneDepth = texture(depthTexture, sampleCoord).r;

			if (sceneDepth >= 1.0) {
				continue;
			}

			// Where the ray is at this sample, and where the surface at that same
			// screen position is, both in view space - so that the two can be
			// compared as a distance in blocks. The depth buffer's own units cannot
			// be used for this; see the note on SSS_THICKNESS_BASE.
			vec2 ndcCoord = sampleCoord * 2.0 - 1.0;
			vec4 rayH = projectionInverse
				* vec4(ndcCoord, rayDepth * 2.0 - 1.0, 1.0);
			vec4 sceneH = projectionInverse
				* vec4(ndcCoord, sceneDepth * 2.0 - 1.0, 1.0);
			vec3 rayPos = rayH.xyz / rayH.w;
			vec3 scenePos = sceneH.xyz / sceneH.w;

			// View space looks down the negative Z axis, so a positive gap is how
			// much nearer to the camera the surface at this sample is than the ray
			// is.
			//
			// The ray is blocked exactly when the surface is in front of it -
			// when the surface is the nearer of the two - so this has to be the
			// scene's z minus the ray's. Written the other way round it counted
			// the samples where the surface sat *behind* the ray as the occluded
			// ones, which is the opposite of what it means: for a day's worth of
			// tuning, everything that was blocked read as lit and everything with
			// nothing behind it read as shadowed - water flattening to a darker
			// shade at a distance among them.
			float gap = scenePos.z - rayPos.z;
			float travelled = length(rayPos - viewPos);

			// The occlusion only counts when what the ray found is *right there*,
			// within a thickness of it, and not merely closer to the camera: a hill
			// the ray runs into is a solid mass whose surface sits almost exactly
			// where the ray reaches it, while an entity, a held block or a tree
			// nearer the camera than the terrain being shaded sits hundreds of
			// blocks short and must not throw a shadow across the landscape.
			//
			// The lower bound is the depth buffer's precision, which is coarse this
			// far out, and so grows with how far the ray has travelled - without
			// it the surface shadows itself and the distance fills with noise.
			//
			// The window also has to cover at least one step's worth of depth, and
			// that is what the step below is for. Once the ray is *inside* a hill,
			// how far under that hill's surface it is grows with every step - so a
			// window narrower than a step stops counting after the first sample or
			// two and leaves the ray reporting itself almost unblocked even when
			// the whole of it is underground. Measured from the driver's seat: the
			// shadows came out faint enough to be invisible.
			// The rate term of the thickness window. It is one product of the
			// same two values wherever it appears - the tolerance below, the
			// window itself, and the softness at the end - so it is worked out
			// once here rather than three times. The 0.02 that used to be
			// written out at the softness is the same float as
			// SSS_THICKNESS_RATE, so naming the constant there changes nothing
			// but makes the sharing visible.
			float depthTolerance = travelled * SSS_THICKNESS_RATE;
			float tolerance = max(0.05, depthTolerance);
			float thickness = max(SSS_THICKNESS_BASE, stepInBlocks)
				+ stepInBlocks + depthTolerance;

			// How much this sample counts as an occluder: fully in the middle of
			// the band where the surface it found is plausibly the thing blocking
			// the light, and less towards either edge of that band.
			//
			// A hard yes or no per sample is what quantises a shadow into steps,
			// and no amount of dithering removes that - the dither only moves
			// where the steps land. Dividing the band into a hard core and a soft
			// edge is what the reference packs do, and it is also what lets the
			// same code work whether the band is wide or narrow.
			float softness = max(0.25, depthTolerance);
			float hit = smoothstep(tolerance, tolerance + softness, gap)
				* (1.0 - smoothstep(thickness - softness, thickness, gap));

			// One qualifying sample is a shadow, and the ray stops there - this is
			// the whole of the fix in batch 641.
			//
			// What stood here accumulated a soft band-pass weight over the ray and
			// divided by the step count, so the answer was "what fraction of the way to
			// the sun is blocked" instead of "is the sun blocked". A leaf, a tree and a
			// mountain all leave two or three samples inside a band that is two steps
			// deep by construction, which is seven to nine percent of the ray - so
			// everything cast the same faint grey tint and nothing had an edge. It also
			// made the result arithmetically insensitive to the step count, which is why
			// raising it from 12 to 32 changed nothing at all.
			//
			// Both packs this was compared against decide: Bliss sets its shadow to zero
			// on the first qualifying hit and stops, and Sundial multiplies by a clamp
			// that is exactly zero for a non-porous surface. A shadow is a yes or a no.
			//
			// The dither above is what keeps that from quantising into bands: neighbouring
			// pixels start their ray at different points along it, and composite1's
			// temporal resolve - which runs after this pass, at 0.85 - averages the
			// results. Hard edges, filtered over time, instead of a soft average.
			if (hit > 0.5) {
				return 0.0;
			}
		}

		return 1.0;
	}
#endif
