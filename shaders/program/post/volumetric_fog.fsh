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

// Added 2026-09-25 by Remiiil1a for Firmament - the march through the medium.
// Replaces the screen-space shafts this pack used to draw; see
// /environment/effects/volumetric_fog.glsl for what that means and
// BATCH_LOG.md 169 for why.

// One ray per half-resolution pixel, from the eye to whatever the depth buffer
// shows, accumulating the light the medium scatters towards the eye on the way.
//
// It writes the scattered light and nothing else - not the fading of what is
// behind it. The pack's own fog already owns that, per fragment, in the surface
// programs; doing it here as well would count it twice, and doing it here
// instead would mean moving a term that four other things read. See the same
// note in the settings file.
//
// ⚠️ The one exception is the Nether's plumes, which do fade what is behind
// them. That fading travels in the fourth channel of this pass's own buffer,
// which is why the output below is a vec4 and no longer the bare colour it
// used to be. Every other path leaves the fourth channel at 1.0, so for them
// the pass is still the addition it has always been - see where absorbance is
// worked out in main().
//
// Half resolution, and the result is a wide smooth glow with no edges of its
// own, which is the case upscaling handles best: the sampling is bilinear and
// nothing in it needs a sharp boundary kept.
//
// Why this pass, and not the deferred one
// --------------------------------------
// It runs in the `composite` stage, which is the slot the screen-space shafts
// used to occupy - so the pass count and the buffer are the ones that were
// already being paid for, and nothing in the frame's ordering changes. It has
// to run after the deferred pass, which is where the world's picture and the
// depth buffer are both complete.

uniform sampler2D depthtex0;

// The shadow map, opaque casters only.
//
// shadowtex1 rather than shadowtex0 because the shafts should stop at what
// stops the sun itself: a pane of glass, or the surface of water, does not cast
// a shadow on the ground and should not cut a shaft in half either.
uniform sampler2DShadow shadowtex1;

uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform mat4 shadowModelView;
uniform mat4 shadowProjection;

// The colour of the light the medium is lit by, with the time-of-day exposure
// already folded in and the screen-space fades deliberately left out.
//
// That last part is the point of the whole change. The shafts this replaces had
// to fade themselves out as the sun left the view, because a blur towards a
// point off the screen is not a shaft; this one is lit by light that is in the
// volume whether or not its source is on screen, so fading with the sun's
// screen position would throw away the thing the volumetric version is for. The
// exposure is kept, because it is what keeps a noon sun from blowing the screen
// out, and it is built for this in shaders.properties - see fogSunColor.
uniform vec3 fogSunColor;

uniform vec3 cameraPosition;

// The frame's number, to stir the dither with. It is one of the mod's uniforms
// and the composite stage is given it - composite3.fsh reads it for its own
// history - so like cameraPosition this one is safe to use here.
uniform int frameCounter;

// The fade of the shadow test at the map's own border needs no uniform of its
// own - see where it is worked out. shadowDistance is deliberately not used
// here: it is one of the mod's uniforms, but not one the composite stage is
// given, and declaring it to use it fails to compile with "undefined variable
// shadowDistance" on the driver. BATCH_LOG.md 171 records it.

uniform float viewWidth;
uniform float viewHeight;

// ⚠️ colortex1, which is the buffer this pass WRITES - declared here only to ask
// its SIZE (batch 533), which is what the screen coordinate below is built from.
//
// It used to be built from viewWidth and the scale written in
// shaders.properties, and that is one fact written down in two places: the
// properties side turned the buffer into the frame's own size and this pass kept
// the quarter, so the fog landed shrunken into a corner of the screen. Asking
// the target removes the second copy, and the reader asks the same question of
// the same buffer before it decides how to read it - see
// /program/post/postprocessing.fsh - so no macro can leave the two apart.
//
// ⚠️ textureSize is a query and not a sample: it returns the texture's own
// dimensions and reads no texel, which is what makes it legal in the pass that
// renders into this buffer. Nothing else here samples it, and nothing should:
// reading a buffer while writing it is the undefined case this pack keeps its
// bloom buffers apart for.
uniform sampler2D colortex1;

// The dither that breaks up the banding between steps. The same 8 by 8 pattern
// the screen-space shafts used, and the same one the sky's dithering uses.
#include "/lib/bayer8.glsl"

// The medium's options and its density. Declares isEyeInWaterFog itself, which
// is the pack's own alias for the mod's underwater flag - see the note there.
#include "/environment/effects/volumetric_fog.glsl"

// distort(), which the shadow map has to be read through - see the note where it
// is used. The same include lit.vsh and shadowmap.glsl take.
#include "/lib/distort.glsl"

// The colour the pack fades what is under water towards, for the medium to take
// its own colour from down there. A custom uniform, so this stage has it.
//
// volumetricFogRainFactor and volumetricFogTimeFactor are deliberately NOT
// declared here. They belong to the medium's own file below, which is where the
// density that reads them lives, and an include expands into this same source:
// declaring one in both places is two declarations of one uniform, which the
// driver rejects with "declaration ... conflicts with previous declaration".
// BATCH_LOG.md 176 records it.
uniform vec3 underwaterFogColor;

// The scattered light in rgb, and in a the fraction of what is behind it that
// reaches the eye - 1.0 everywhere except the Nether, where the plumes fade.
//
// ⚠️ RGBA16F rather than the R11F_G11F_B10F this buffer used to be, and that is
// what makes the fourth channel exist at all: R11F_G11F_B10F is three
// components, so writing an alpha into it would have been silently dropped and
// the whole transmittance would have read back as 1.0 - no regression, but no
// effect either. The pack already keeps six other buffers in this format
// (colortex7, 9, 10, 11, 12, 13), so it is the familiar one here.
// ⚠️ It is a half float, so it is signed and tops out at 65504: the scattered
// light is nowhere near that, and the quantity in the fourth channel is a
// fraction between zero and one by construction - but see the note in
// lib/bloom.glsl about what a distance stored in a half float did once.
const int RGBA16F = 0;
const int colortex1Format = RGBA16F;

// colortex1 can be named by DRAWBUFFERS, which reaches as far as nine - so this
// pass keeps the older directive and matches the rest of the pack, unlike the
// SMAA and bloom passes which have to reach past it.
/* DRAWBUFFERS:1 */

layout(location = 0) out vec4 fogScatter;

void main() {
	// Where this fragment is on the screen. ⚠️ Asked of the target this pass is
	// rendering into, and not worked out from viewWidth and the scale in
	// shaders.properties: those are one fact written down twice, and the defect
	// batch 533 is named for is the two disagreeing - the properties side put
	// this buffer at the frame's own size and this pass kept the quarter, so the
	// fog landed shrunken into a corner of the screen. The reader asks the same
	// question of the same buffer before it reads it, so the two cannot be left
	// apart by a compile-time option whatever the loader does with the macro.
	//
	// ⚠️ textureSize reads no texel, which is what makes it legal here - see the
	// note on the declaration above.
	//
	// A quarter of the frame rather than a half by default. The result is a wide
	// smooth glow with no edges of its own, which is the case upscaling handles
	// best - and the four times smaller target both pays for the higher step
	// count below and smooths what the dither leaves behind, which matters here
	// because this pack has no temporal filter left to do it.
	vec2 screenCoord = gl_FragCoord.xy / vec2(textureSize(colortex1, 0));

	float depth = texture(depthtex0, screenCoord).r;

	// The ray, in camera-relative space, from the eye to the surface this pixel
	// shows - or to the far end of the medium, whichever comes first. Working
	// camera-relative rather than absolute because that is the space the shadow
	// matrices take, and it keeps the camera's own position out of a number that
	// is only ever used as a difference.
	vec4 viewPosH = gbufferProjectionInverse
		* (vec4(screenCoord * 2.0 - 1.0, depth * 2.0 - 1.0, 1.0));
	vec3 viewPos = viewPosH.xyz / viewPosH.w;

	// How far along the ray there is anything to light. The march does not use
	// this to place its steps - see below - only to know where to stop.
	float surfaceDistance = length(viewPos);
	vec3 rayDirection = normalize(
		(mat3(gbufferModelViewInverse) * viewPos));

	// The offset into the first step, so that neighbouring pixels do not all put
	// their boundaries in the same place. It is stirred by the frame counter as
	// well as by the pixel: a pattern fixed to the screen stays put while the
	// world slides underneath it, which reads as dirt on the lens rather than as
	// fog. Stirring makes it noise that changes every frame, and the
	// quarter-resolution target is what keeps that noise from being obvious.
	float dither = fract(Bayer8(gl_FragCoord.xy)
		+ float(frameCounter) * 0.6180339887);

	// What colour the medium scatters. Under water it is the water's own fog
	// colour rather than the sunlight, because the pack's underwater light has
	// been faded towards its own luma before it is handed out - so using it here
	// paints a white haze over a blue world, which is what it looked like.
	//
	// ⚠️ The End's tint is multiplied into the sunlight side of this and NOT
	// into the underwater side, and the ternary is what guarantees it rather
	// than a second test somewhere: a camera under water in the End takes the
	// left branch, which the tint is not on. The water column has an absorption
	// colour of its own and the pack already fades its light towards it, so
	// tinting the air inside the water as well would have the pack contradicting
	// its own underwater lighting. Added in batch 340; see BATCH_LOG.md 197.
	vec3 mediumColor = isEyeInWaterFog == 1
		? underwaterFogColor
		: fogSunColor * VolumetricFogTint();

	// The cloud transmittance that used to be worked out here was taken back out
	// in b318: read once per pixel, at one point along the ray, it made the
	// shafts wander and flicker as the clouds drifted, and what it bought was not
	// worth that. See BATCH_LOG.md 175. The clouds still shade the terrain
	// exactly as they did - this was only ever the fog's own copy of it.

	vec3 scatter = vec3(0.0);

	// What the medium lets through to the eye: one everywhere but the Nether,
	// where every step through a plume takes a bite out of it. ⚠️ It is left
	// exactly at one on every other path on purpose - what is behind the shafts
	// is already faded per fragment by the pack's own fog, and fading it a
	// second time here would count it twice. See the note at the top.
	float absorbance = 1.0;

	#ifdef NETHER_PLUMES
		// ⚠️ Asked once for the pixel rather than once per step. It is a uniform
		// comparison, so it costs nothing either way, but a branch inside the loop
		// whose answer cannot change within the pixel is the kind of thing a
		// compiler is not always free to lift out on its own.
		bool inNether = NetherDimension();
	#endif

	for (int i = 0; i < VOLUMETRIC_FOG_STEPS; i++) {
		// The steps are spread quadratically rather than evenly: two thirds of
		// them fall inside the first third of the ray. That is where the medium
		// is thickest and where the edges of the shafts are, while the far end is
		// a smooth wash that a long step covers without anything being lost. A
		// fixed step count spent evenly would put most of its samples where they
		// change nothing.
		float t0 = (float(i) + dither) / float(VOLUMETRIC_FOG_STEPS);
		float t1 = (float(i) + 1.0 + dither) / float(VOLUMETRIC_FOG_STEPS);

		// The steps sit at fixed distances along the ray, the same ones for
		// every pixel in the frame - as much for one showing a wall two blocks
		// away as for one showing the horizon. That is why this is
		// VOLUMETRIC_FOG_DISTANCE and not the distance to whatever this pixel
		// happens to show: a ladder packed into the surface distance rescales
		// itself whenever anything in the frame moves, so the places the medium
		// is sampled slide around under the world, and the fog shimmers as the
		// player walks. Fixed places cannot slide.
		float start = VOLUMETRIC_FOG_DISTANCE * t0 * t0;
		float end = VOLUMETRIC_FOG_DISTANCE * t1 * t1;
		float stepLength = end - start;

		// And where the surface is nearer than this step there is nothing left
		// to light, because the medium behind an opaque thing is not seen.
		// Stopping here keeps the saving the surface distance was there for,
		// without letting it move the ladder.
		if (start >= surfaceDistance) {
			break;
		}

		vec3 samplePos = rayDirection * ((start + end) * 0.5);

		#ifdef NETHER_PLUMES
			// The Nether's smoke, which is a different medium lit by a different
			// thing, so it takes the whole step rather than sharing any of it.
			//
			// ⚠️ No shadow map is read on this path, and that is not an
			// optimisation. There is no sun in the Nether to trace: the answer the
			// map holds is about a light that is not in this dimension, so asking
			// it would light the smoke with the Overworld's sun. The glow added
			// below is the medium's own.
			//
			// Because nothing below this runs, the whole rest of the loop - the
			// density, the shadow projection, the distortion, the border fade - is
			// skipped for the Nether as well, which is most of what a step costs.
			if (inNether) {
				// The bubble around the eye. samplePos is camera-relative, so its
				// length is the distance along the ray - this needs the camera's
				// own position for nothing.
				//
				// ⚠️ And this is the one suspect batch 527 left: it is not a fading
				// of something at the screen's edge, it multiplies the WHOLE plume
				// term - the emission along with the extinction - by the distance
				// out to NETHER_PLUME_CLEAR, so at the 24 that shipped, a player
				// standing on the lava sea had every column within 24 blocks scaled
				// down and the ones they were standing next to taken out entirely.
				// The report that opened batch 529 - one thin stripe against the
				// horizon - is that bubble seen from inside. The option's own note
				// has the numbers; the default is 8 now.
				float clearArea = clamp(
					length(samplePos) / NETHER_PLUME_CLEAR, 0.0, 1.0);

				vec3 worldPos = cameraPosition + samplePos;

				float plume = NetherPlumeDensity(worldPos, clearArea);

				// ⚠️ Inverted in batch 520. This used to be exp(-density), which is
				// brightest where the smoke is THINNEST and leaves a dense column with a
				// dark core - the shape the reference pack has, and the reason its plumes
				// read as outlined ropes. Here the core is the bright part and the edges
				// fall away, which is also what makes the churn legible: what rolls past is
				// a lit mass rather than a moving outline. The 0.25 keeps the brightest a
				// column can get at about what that curve gave it, so the change is about
				// where the light sits and not about how much of it there is.
				//
				// ⚠️ And batch 529 measured what "what that curve gave it" actually was,
				// which is where that batch's report came from. ⚠️ Its figures are that
				// batch's and are quoted here at ITS pair, optical 0.016 and density
				// 1.5: at a column's own half density of 0.5 the emission expression
				// below comes out at 0.0019 of a white frame per block of plume crossed,
				// and that batch put a quarter of it at the eye once the absorbance
				// weighting was on the glow - so its 0.6% for a 13-block crossing and
				// its 1.7% for a saturated core are light DELIVERED, not light emitted.
				// A column that is half a percent of the frame is a column nobody can
				// see, which is the near-black picture that opened that batch.
				//
				// ⚠️ That quarter was a round number for a weighting worth working out
				// rather than rounding: a sample's light arrives as the emission times
				// absorbance raised to NETHER_PLUME_SHADING + 1.0 - this option's
				// exponent and batch 524's own multiply, which is one more - and the
				// mean of that over a crossing of transmittance T is (1 - T^3)/(3 * -ln
				// T). At the pair batch 534 ships - optical 0.32, density 2.0,
				// extinction 0.03 - a half-density crossing has T = 45.8%, so 38.6% of
				// the light put into it arrives, which makes the same thirteen blocks
				// 65.7% of a white frame emitted and 25.4% of it delivered. Both of
				// those are the numbers this note is now built on, and every figure
				// below that is called ARRIVING is on that definition. The 0.25 is left
				// alone anyway: it is the null case for the sliders that were tuned
				// around it, and the gain belongs on NETHER_PLUME_OPTICAL, where it can
				// be seen and undone. See that option for the arithmetic on both sides
				// of it.
				//
				// ⚠️ Batch 528: and the glow is weighted by what is already between it
				// and the eye. Every term above is a function of the local density and of
				// nothing else, so on its own it cannot draw a form - a sample in the
				// middle of a column and a sample at its near face come out identical, and
				// what the eye is given is a soft blob with no edge to it, which is the
				// report that opened the batch. A medium is also not lit through itself:
				// what a sample sends towards the eye arrives through the smoke in front
				// of it, so it goes in weighted by that fraction raised to
				// NETHER_PLUME_SHADING. The near face of a column comes out bright and
				// the far face dark, and the column reads as a form against the lava
				// instead of as haze.
				//
				// ⚠️ This is an ADDITIONAL weighting and not the only one. The scatter
				// below is multiplied by the absorbance once more, in the front-to-back
				// order the integral is written in, and that multiply is batch 524's - so
				// the exponent the plume's light actually arrives with is
				// NETHER_PLUME_SHADING + 1.0, which is three at the shipped 2.0: a column
				// that has already taken half of what is behind it dims the glow behind
				// it to an eighth, where one absorbance would leave it at a half.
				//
				// ⚠️ absorbance is a product of exp()s over a march that never reaches
				// past VOLUMETRIC_FOG_DISTANCE, and its worst case over those 96 blocks -
				// a full-density column end to end, at the top of the extinction range -
				// is about 1e-20 rather than zero at the density batch 534 ships, so
				// pow() here is never handed the one input it has no value for. (The
				// 1e-15 this note carried until batch 534 is the same arithmetic at the
				// 1.5 the density shipped at from batch 520 to batch 528, and batch
				// 529's 3.0 puts it below 1e-30 - still a number in a 32-bit float,
				// whose smallest subnormal is about 1.4e-45.)
				//
				// ⚠️ The core-to-edge gradient (batch 534): the light a column sends
				// is not spread evenly across its width. The density above is the one
				// thing this pass holds that says how far into a column a sample sits -
				// the pillar field in NetherPlumeDensity is read in the horizontal
				// plane only, so it peaks at a column's core and falls to nothing in
				// the gaps between columns - and it is already in hand, so the shape
				// costs one smoothstep and three mixes and no fetch and no step.
				//
				// ⚠️ coreness is 0 at the thin edge of a column and 1 from
				// NETHER_PLUME_CORE_DENSITY upwards, and that constant is the half
				// density the arithmetic in the options calls a column's core: the
				// field's own mean plume is 0.353 and a typical surviving pillar is
				// 0.51, so a typical pillar's middle comes out at one and everything
				// thinner than 0.5 lands somewhere on the ramp between.
				//
				// ⚠️ The two mixes are written around the constants the pass already
				// had, so that NETHER_PLUME_CORE_GRADIENT at 0.0 gives back exactly
				// the colour and the weight the emission had before the option
				// existed - mix(x, y, 0.0) is x, to the bit - and that is the null
				// case this pack asks of every shaping option. The slider is a
				// compile-time constant, so at 0.0 the whole gradient folds away.
				//
				// ⚠️ The absorbance the march is holding is deliberately NOT part of
				// this. It is the other half of a column's shape and it already has an
				// option of its own - NETHER_PLUME_SHADING weights the glow by it,
				// which is what puts the light on a column's near face - and folding
				// it in here as well would darken the same side twice and make the
				// gradient depend on what stands in front of a column rather than on
				// where the sample sits inside it.
				float coreness = smoothstep(
					0.0, NETHER_PLUME_CORE_DENSITY, plume);

				vec3 plumeColor = mix(NETHER_PLUME_COLOR,
					mix(NETHER_PLUME_EDGE_COLOR, NETHER_PLUME_CORE_COLOR, coreness),
					NETHER_PLUME_CORE_GRADIENT);

				float plumeWeight = mix(1.0,
					mix(NETHER_PLUME_EDGE_GAIN, 1.0, coreness),
					NETHER_PLUME_CORE_GRADIENT);

				vec3 emission = plumeColor * plumeWeight
					* ((1.0 - exp(-NETHER_PLUME_ABSORPTION * plume)) * 0.25 * plume
						* NETHER_PLUME_OPTICAL * NETHER_PLUME_DENSITY)
					* pow(absorbance, NETHER_PLUME_SHADING);

				// The ceiling smoke goes in plainly instead. It has no inside and
				// outside to be brighter than - it is a flat layer under a roof.
				//
				// ⚠️ And it fades at half weight, by what the plumes have taken
				// rather than by a coefficient of its own: it is a sheet the ray
				// crosses briefly, not the column it spends its length in, so it
				// should not blot out as much. It adds no extinction of its own.
				emission += NETHER_CEILING_SMOKE_COLOR
					* (NetherCeilingSmokeDensity(worldPos)
						* NETHER_CEILING_SMOKE_OPTICAL)
					* (absorbance * 0.5 + 0.5);

				// And the third of the Nether's three: the thin haze that is
				// simply in the air rather than gathered into anything.
				//
				// ⚠️ Emission only. It adds nothing to absorbance, and that is
				// not an oversight: this haze is far too thin to take anything
				// out of what is behind it, and the reference pack says the same
				// of its own.
				//
				// ⚠️ Its colour is gl_Fog.color, the fixed-function built-in,
				// because the game fills that in per biome in the Nether - so the
				// crimson forest, the warped forest, the soul sand valley and the
				// basalt deltas each tint it themselves, and it costs no uniform
				// of this pack's. That is the whole reason it is read here.
				//
				// ⚠️ But this pack has never read gl_Fog anywhere before, and the
				// composite stage is not where that built-in is normally
				// populated: a black one would come out of the normalize below as
				// a flat grey haze, which is not what this dimension looks like.
				// So it is guarded, and below a small length the colour is
				// replaced by a plain constant instead.
				vec3 hazeColor = gl_Fog.color.rgb;

				if (length(hazeColor) < 1e-4) {
					hazeColor = vec3(0.35, 0.12, 0.10);
				}

				// The 0.25 scales the colour down: this is a tint over the air
				// rather than a light of its own.
				emission += normalize(hazeColor + 1e-6) * 0.25
					* (NetherHazeDensity(worldPos) * NETHER_HAZE_OPTICAL);

				// ⚠️ Where the order matters. What a step sends towards the eye
				// is what reaches it through everything the ray has already
				// crossed, so it goes in weighted by the absorbance the march is
				// holding as the step begins, and the extinction this step
				// charges is applied after it - front to back, which is the order
				// the single-scattering integral is written in. Until batch 524
				// every step went in at full weight, so the glow of the plumes
				// behind a near one reached the eye as though that plume were not
				// there, and the layer glowed through itself. The composite
				// cannot answer for that on its own: what it multiplies by this
				// pass's fourth channel is the frame BEHIND the medium, not the
				// medium's own light.
				scatter += emission * stepLength * absorbance;

				// The other half of what smoke does: it takes light out of what
				// is behind it as well as putting its own in. Charged per block
				// of plume the ray crosses, which is how a medium's optical
				// depth is charged.
				//
				// ⚠️ The density option is in here as well as in the emission, so
				// that turning the smoke up thickens it rather than only
				// brightening it.
				//
				// ⚠️ NETHER_PLUME_EXTINCTION is the number to tune. ⚠️ Every figure
				// in this note is at the pair batch 534 ships - density 2.0, extinction
				// 0.03 - and every one of them is a transmittance, which is the fraction
				// of what is behind the medium that reaches the eye. A sight line
				// through a column's core of about 0.5 keeps 30.1% of it over twenty
				// blocks and 5.0% over fifty; one through the field at its own mean
				// plume of 0.353 keeps 42.9% over the same twenty blocks and 1.71% over
				// the whole 96-block march, where the core keeps 0.31%. So the columns
				// silhouette against the lava without the layer becoming a black wall,
				// which is what this dial is for.
				//
				// ⚠️ What a transmittance does when the density or this is changed is
				// not proportional, and that is the trap: what doubles is the OPTICAL
				// DEPTH, which is the exponent, so doubling it squares the transmittance
				// and halving it takes the square root. Batch 534 lowered the density
				// from batch 529's 3.0 to 2.0 and this from 0.06 to 0.03, so the product
				// that scales every depth fell to a third of what it was: every figure
				// above is batch 529's own raised to the power one third - its core's
				// twenty blocks go from 2.7% to 30.1%, and its whole-march mean from
				// five parts in a million to 1.71%.
				//
				// ⚠️ The figures the earlier versions of this note carried are kept
				// here as the pairs that produced them, because each was true of one:
				// 17% and about 1% are batch 528's twenty- and fifty-block core rows at
				// density 1.5 with the extinction at 0.06; 41% and 10% are the same two
				// rows at 1.5 with 0.03, which is the pair before that batch and the
				// reason it raised this option, a column that leaves the background as
				// it was having no edge to read; 2.7%, 7.9% and five parts in a million
				// are batch 529's rows at density 3.0 with 0.06, the last of them being
				// the 96-block march at the field's own mean plume of 0.353; and the
				// 1.9% and 23% that stood here for that same march are batch 528's, the
				// first at the density the contrast raise had just produced and the
				// second at the mean plume of 0.168 it measured then. ⚠️ 54% and 1.3%
				// were not the pair any of those batches shipped: 54% is the twenty-block
				// row with the extinction still at 0.03 and 1.3% is the core's own
				// 96-block row at that same 0.03.
				//
				// The formula is untouched, and this is the dial if the Nether reads as
				// too closed in. Raise it for smoke you cannot see through, lower it for
				// smoke that only veils, and set it to 0.0 to take the fading out
				// altogether - which is a bottom the slider still has, although the
				// shipped 0.03 is now the second step on it rather than the step below
				// the top.
				absorbance *= exp(-plume * NETHER_PLUME_ABSORPTION
					* NETHER_PLUME_DENSITY * stepLength * NETHER_PLUME_EXTINCTION);

				continue;
			}
		#endif

		// The density is asked for a world position, not a camera-relative one:
		// the patches are fixed to the world, so that walking past them shows
		// them sliding by rather than standing still.
		float density = VolumetricFogDensity(cameraPosition + samplePos);

		// Most of the ray is usually outside the layer, and the density is zero
		// exactly rather than nearly there, so this skips the shadow fetch for
		// every step that is above the fog. It is the same early out the light
		// bleed uses for taps with no lamp in them, and it is what keeps the
		// cost of a high camera from being the cost of a low one.
		if (density <= 0.0) {
			continue;
		}

		// Whether the sun reaches this point of the medium, which is the whole
		// of what makes a shaft. The shadow map answers it directly and at the
		// same resolution the world's shadows are drawn at, so the shafts end
		// where the shadows do.
		//
		// The shadow map is drawn distorted, so it has to be read distorted.
		//
		// This is the whole of why the fog jumped as the player walked, and it
		// took a reader pointing at the shadow distortion to find it. shadow.vsh
		// pushes the map's clip position through distort() before drawing it,
		// and the surface programs push their sampling position through the same
		// function before reading it - see lit.vsh. Reading it undistorted lands
		// on a different place in the map than the one the answer was stored at,
		// and the error is largest exactly where it matters: the distortion
		// packs the map's texels towards the player, so without it one step of
		// the world moves the sample across several texels at once, and the
		// shadow the fog is standing in changes in jumps. That is the same thing
		// the distortion exists to stop the terrain's own shadows doing.
		//
		// The three steps are lit.vsh's, in its order: project to clip space,
		// distort there, and only then move into the map's 0 to 1 space. The
		// distortion works on -1 to 1 coordinates and halves z itself, so
		// applying the viewport transform first would scale the distortion by
		// two and put the depth in the wrong half of the buffer.
		vec3 shadowPos = (shadowProjection
			* (shadowModelView * vec4(samplePos, 1.0))).xyz;

		shadowPos = distort(shadowPos) * 0.5 + 0.5;

		// And the answer is faded out at the edge of the map rather than cut off
		// there, and it fades towards lit rather than towards shadowed.
		//
		// This is what the surface programs do, and here it is the difference
		// between fog that sits still and fog that jumps: the map covers a box
		// centred on the camera and travels with it, so calling everything
		// outside it shadowed lays a hard edge across the medium where the map
		// ends. Walking one block moves that edge one block, and the whole far
		// half of the fog changes brightness with it. Fading towards lit leaves
		// nothing to move, and being lit by the sun is also what is true out
		// there.
		//
		// The distance is measured to the map's own border, in the map's own
		// coordinates, rather than to the culling box the surface programs use -
		// that one is built from shadowDistance, and this stage is not given it.
		// It is the same border read the other way round, and it needs nothing
		// that is not already in hand: the map spans two shadow distances corner
		// to corner, so a fade of 0.026 of its width is about five blocks, which
		// is the width the surface programs fade over.
		vec2 borderDistance = min(shadowPos.xy, vec2(1.0) - shadowPos.xy);

		float withinShadowMap = smoothstep(
			0.0,
			0.026,
			min(borderDistance.x, borderDistance.y));

		float sunVisibility = 1.0;

		if (withinShadowMap > 0.0001) {
			// texture() on a shadow sampler compares the third component
			// against what the map holds there and returns the result, with the
			// hardware doing the filtering - so this is a soft edge for free,
			// and softer the further away the map's texels are.
			sunVisibility = mix(
				1.0,
				texture(shadowtex1, shadowPos),
				withinShadowMap);
		}

		// The light this step of the medium sends towards the eye: what the
		// medium is lit by, how much of it the sun reaches, and how much medium
		// there is. There is no transmittance term in the loop because this pass
		// adds light rather than replacing any - see the note at the top.
		scatter += mediumColor * (sunVisibility * density * stepLength);
	}

	fogScatter = vec4(scatter, absorbance);
}
