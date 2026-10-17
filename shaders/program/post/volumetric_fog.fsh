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
// renders into this buffer - and it is asked and not sampled at the top of
// main() for exactly that reason. The buffer IS sampled further down, by the
// temporal denoise, and that is legal for a different reason: Iris gives each
// colortex two sides and has a composite pass read one while writing the other,
// which is what makes the history read at the bottom of main() a read of the
// previous frame rather than a read of this one. See the note there, and
// BATCH_LOG.md b569 for the documentation that was checked.
uniform sampler2D colortex1;

// Where a world point was on the previous frame's screen, for the temporal
// denoise at the bottom of main().
//
// ⚠️ The four uniforms are declared here rather than in /lib/reproject.glsl,
// which declares none of its own on purpose: a second declaration of one uniform
// in one program does not compile, and that file is included by a vsh and by
// three programs that each declare their own set.
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;
uniform vec3 previousCameraPosition;

// The dither that breaks up the banding between steps. The same 8 by 8 pattern
// the screen-space shafts used, and the same one the sky's dithering uses.
#include "/lib/bayer8.glsl"

// The medium's options and its density. Declares isEyeInWaterFog itself, which
// is the pack's own alias for the mod's underwater flag - see the note there.
#include "/environment/effects/volumetric_fog.glsl"

// distort(), which the shadow map has to be read through - see the note where it
// is used. The same include lit.vsh and shadowmap.glsl take.
#include "/lib/distort.glsl"

// ReprojectWorldPosition(), the pack's one copy of "where was this point on the
// screen a frame ago" - the same function the temporal resolve, the reflection's
// history and the motion blur all take their movement from. The temporal denoise
// below is its fourth caller, which is the point of it being a file: a second
// copy of a reprojection is a second place to fix the next time one is found
// wrong. See the note on it in /lib/reproject.glsl.
//
// ⚠️ Included here, after the uniforms above, and not at the top of the file:
// that file declares no uniforms of its own and needs four in hand before it can
// be expanded - gbufferPreviousProjection, gbufferPreviousModelView,
// previousCameraPosition and viewWidth/viewHeight, the last two of which are
// declared above as well.
#include "/lib/reproject.glsl"

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
// effect either. The pack already keeps four other buffers in this format
// (colortex7, 9, 12, 13), so it is the familiar one here.
// ⚠️ It is a half float, so it is signed and tops out at 65504: the scattered
// light is nowhere near that, and the quantity in the fourth channel is a
// fraction between zero and one by construction - but see the note in
// lib/bloom.glsl about what a distance stored in a half float did once.
const int RGBA16F = 0;
const int colortex1Format = RGBA16F;

// And it keeps its contents between frames, which is what makes the temporal
// denoise at the bottom of main() possible at all: the denoise reads the
// previous frame's result back out of this very buffer as its history, and a
// buffer cleared every frame would have nothing in it to read.
//
// ⚠️ This line is the whole effect, and deleting it kills the denoise silently -
// the buffer goes back to being cleared to vec4(1.0) every frame, every frame is
// then averaged against that instead of against the fog, and a still frame looks
// plausible while the accumulation converges on "no fog at all". The copy in
// shaders.properties does NOT do the same job: Iris reads this directive out of
// the GLSL sources (its documentation puts it in "any GLSL shader file", and
// Bliss ships all sixteen in one included file) and its shaders.properties
// parser has no case for it. The properties line is there so that the flag is
// visible beside the size.buffer line it belongs to, and for no other reason.
const bool colortex1Clear = false;

// colortex1 can be named by DRAWBUFFERS, which reaches as far as nine - so this
// pass keeps the older directive and matches the rest of the pack, unlike the
// SMAA and bloom passes which have to reach past it.
/* DRAWBUFFERS:1 */

layout(location = 0) out vec4 fogScatter;

// The temporal denoise.
//
// The march takes ONE ray through each texel of this buffer, with its steps
// offset by a dither that changes every frame, so a single frame of it is a
// single sample of a noisy estimator: what the eye is given is the step
// boundaries and the patch noise of the medium, and nothing in this pass can
// average them away because there is nothing else to average them with. This
// stage is that average. It reads the previous frame's result back through the
// camera's own reprojection, keeps it if it looks like a plausible value for
// this texel, and mixes the two - which is the "denoise" half of what
// Bliss Shader's VLTemporalFiltering() does for its own volumetrics
// (shaders/dimensions/composite3.fsh, and see BATCH_LOG.md b569 for the
// line-by-line comparison of what was taken from it and what was not).
//
// It is a SEPARATE stage rather than more steps in the march, because the two
// buy the same thing at very different prices: the march's cost is the shadow
// fetch per step - the single most expensive instruction in this pack - while
// this stage's is ONE fetch of a quarter-resolution buffer plus the one depth
// read the march had already made, on a target a sixteenth of the frame's size.
//
// ⚠️ One fetch, and not the nine this started with. The first version bounded
// the history by the mean and the deviation of the texel's 3x3 neighbourhood,
// and that could not work for a reason worth keeping in front of a reader: every
// read of this buffer inside this pass returns the PREVIOUS frame's accumulated
// value (see the note on colortex1 below), so a neighbourhood of it measures an
// already-averaged signal, its spread is far below the per-frame noise, and the
// bound it makes contains the very ghost it was meant to reject. Nine fetches to
// reject nothing. What replaced it costs no fetches at all: the history against
// the frame being drawn, which is a measurement the one-pass shape can actually
// make. See the note on FOG_DENOISE_CHANGE_TOLERANCE.
//
// ⚠️ The options are in /environment/effects/volumetric_fog.glsl with the rest
// of the medium's, NOT here: the menu registers an option by finding its
// `#define` in the sources, and where that define lives is where a reader looks
// for what the option does. What is here is only what the option switches on,
// plus the one tuning constant below.

// The variance clamp this stage was designed around, kept as a note rather than
// as a constant.
//
// The plan was Salvi's variance clipping - the same bound the temporal resolve
// uses in composite1.fsh, the history held inside the current texel's
// neighbourhood mean plus or minus a multiple of its standard deviation. It is
// the right bound for a resolve because a resolve HAS the current frame's
// neighbourhood: composite1 reads colortex0, which this frame's geometry has
// just written.
//
// ⚠️ This pass does not have it, and that is the whole story of this stage's
// first attempt. The only buffer it can read is the one it is writing, and a
// composite pass reads the side of a colortex that holds the PREVIOUS frame (see
// the note on colortex1 below). So a 3x3 of it is a 3x3 of already-averaged
// values: its spread is that of the accumulated signal rather than of the
// per-frame noise, the band built from it is narrow AND contains the ghost it is
// supposed to exclude, and the clamp cannot reject anything. It measured nine
// fetches per texel and did nothing with them.
//
// What replaced it is on the other side of the same problem: instead of bounding
// the history by data that is not the current frame, compare the history against
// the current frame directly. That is VOLUMETRIC_FOG_DENOISE_TOLERANCE below,
// and it is a measurement one pass CAN make.

// How far a history's brightness may be from this frame's before the history
// starts to be distrusted, as a fraction of the brighter of the two.
//
// ⚠️ 1.0 - so the falloff only begins when the two differ by the whole of the
// brighter one, which is a doubling or a halving. That is a scene change: a door
// opening on a lit room, the water closing over the eye, a portal. Everything
// below it is the marching noise and must be averaged, not distrusted.
//
// ⚠️ This started at 0.25, and the user's report is what found it: "the denoise
// on and off look about the same". They were right, and the arithmetic says why.
// `raw` is one sample of the estimator while `history` is an average of ten, so
// the difference between them is dominated by raw's own per-frame error - at the
// relative noise a 24-step march reaches over a thin medium, a quarter threshold
// fires on about a THIRD of all texels every frame (see the model in BATCH_LOG.md
// b569). A hard test cannot sit above that noise and below a real change at the
// same time; this one no longer has to, because it scales the weight instead of
// throwing the history away.
const float VOLUMETRIC_FOG_DENOISE_TOLERANCE = 1.0;


// How far along the ray the temporal denoise's anchor sits, in blocks.
//
// ⚠️ A distance with NO DEPTH IN IT, and that is the whole point. At a silhouette
// the depth the march stopped at flips between the thing in front and the thing
// behind - a point-sampled depth does, which is what fixed the mosaic - so
// anything built from that depth flips with it, and an anchor that flips hands the
// reprojection a different world point every other frame. That is the drag the
// author reported after batch 573. A point at a fixed distance along the ray has
// no depth in it and nothing to flip.
//
// ⚠️ A median filter over the neighbouring depths was tried first and abandoned
// on measurement, not on taste: at a silhouette a neighbourhood is about half near
// samples and half far ones, so the middle of nine sits exactly on the boundary
// between the two groups and moving ONE sample across it moves the answer the
// whole way from one surface to the other. filter_choice.py shows the true median
// of nine swinging the full 30 blocks; every order statistic does. Only a mean is
// stable, and a mean is what caused the mosaic - it returns a distance no surface
// has.
//
// ⚠️ The cost of anchoring on the ray instead of the surface: a texel whose fog
// belongs to a wall right in front of it is reprojected as though it belonged to a
// point further along the same ray. That is a small error - and it is the SAME
// error every frame, which is the difference between a history that can be
// averaged and one that cannot.
//
// ⚠️ Not a knob, and not in the menu: it wants to be a typical distance into the
// medium, the same for every texel and every frame. A quantity that varies per
// texel is a quantity that can vary per frame, which is the failure being fixed.
const float FOG_DENOISE_ANCHOR_DISTANCE = 64.0;

// How strongly the medium scatters light forwards, as the Henyey-Greenstein
// anisotropy parameter.
//
// ⚠️ 0.4, and the number was CHOSEN BY MEASUREMENT rather than by reaching for a
// realistic one. The physical range is 0 (scatters equally in every direction) to 1
// (scatters only forwards); real mist is high on it, and 0.75 is a defensible value
// for it - but a phase function is normalised so that its average over all
// directions is one, which means a TIGHTER lobe is paid for by a DIMMER sky
// everywhere else (phase_check.py, integrating over the sphere):
//
//     g      looking at the sun     sun at 90 deg     back to the sun
//     0.40          x 3.9              x 0.67            x 0.31
//     0.50          x 6.0              x 0.54            x 0.22
//     0.75          x28.0              x 0.22            x 0.08
//
// At 0.75 the fog would be twenty-eight times brighter into the sun and less than a
// quarter as bright across the rest of the frame - which is what real mist does, and
// is why a photograph into the sun has no detail in it. It is also unusable as a
// default for a game: every fog brightness in the pack would have had to be retuned
// around the one direction the player is not usually looking. At 0.4 the shafts
// gain a factor of about four towards the sun and the rest of the frame moves by
// less than half either way.
//
// ⚠️ 3.9 at the sun is also the number the audit read out of Bliss Shader's own
// curve (fogPhase at full forward, times the 5.0 its caller applies), so this is
// the same visible strength as the reference rather than merely a safe one.
//
// ⚠️ Not a knob in the menu, deliberately, even though it is the one number here
// that a player might want to move. It is a property of the medium, like the
// density profile's shape; the dial for how bright the shafts are is
// GODRAYS_STRENGTH, and a second dial for how they respond to direction would be
// two ways to change the same picture.
const float FOG_PHASE_G = 0.4;

// And how strongly it scatters backwards, for the smaller second lobe.
//
// ⚠️ -0.2, which is a back-peaked lobe rather than a forward one - the sign of the
// parameter is what turns it round, and that is why it needs a constant of its own
// rather than reusing the one above. Small, because mist really is brighter looking
// INTO the light; its only job is to stop the medium being darkest exactly opposite
// the sun, which reads as the fog switching itself off behind the player.
const float FOG_PHASE_G_BACK = -0.2;

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
	// count below and smooths what the dither leaves behind.
	//
	// ⚠️ "and this pack has no temporal filter to do it" stood at the end of that
	// sentence until batch 569, which is the batch that gave this pass one. The
	// quarter is still worth having on its own - it is what pays for 24 steps -
	// but it is no longer the only thing standing between the dither and the eye.
	vec2 screenCoord = gl_FragCoord.xy / vec2(textureSize(colortex1, 0));

	// ⚠️ The depth is POINT-SAMPLED at one full-resolution pixel, and that is the
	// fix for the "blurry mosaic at the edges" the author reported (batch 573).
	// What stood here was `texture(depthtex0, screenCoord)`, and a texture() is a
	// BILINEAR read: at a quarter-resolution grid it averages the depth of the
	// four full-resolution pixels around this texel's centre. Away from an edge
	// those four are the same surface and the average is that surface's depth;
	// AT an edge they are not - two of them belong to the thing in front and two
	// to the thing behind - and the average is a distance that belongs to
	// neither. The march then stops there, so its far end and the surface it is
	// shaded against slide between the two real distances as the camera moves,
	// in whole fog texels. That is a mosaic on the fog buffer's own four-pixel
	// grid, and no filter downstream can remove it: the value was already wrong
	// when it was written.
	//
	// Bliss does not have this. Its march takes the depth with texelFetch at the
	// low-resolution pixel's own index (composite3.fsh's bilateralUpsample reads
	// depth with texelFetch), so its marched distance is one real surface's and
	// never a blend of two.
	//
	// ⚠️ The pixel is the one the fog texel's centre lands on, which is exactly
	// the pixel the reader reconstructs for this same texel and compares its
	// depth against - see fullTexel in /program/post/postprocessing.fsh. The two
	// have to be the same pixel or the depth the fog was built from and the depth
	// it is compared against are two different measurements of one texel.
	//
	// ⚠️ Clamped, because texelFetch outside a texture is undefined rather than
	// clamped, and a frame whose width is not a multiple of four can put this one
	// pixel past the end.
	ivec2 fullSize = ivec2(viewWidth, viewHeight);
	ivec2 depthPixel = clamp(ivec2(screenCoord * vec2(fullSize)),
		ivec2(0), fullSize - 1);

	float depth = texelFetch(depthtex0, depthPixel, 0).r;

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

	// HOW THE MEDIUM SCATTERS, BY THE ANGLE BETWEEN THE RAY AND THE SUN (batch 582).
	//
	// ⚠️ Until this existed the fog's brightness did not depend on WHERE THE CAMERA
	// WAS LOOKING AT ALL: one colour, times a shadow test, and the shafts were
	// exactly as bright viewed from the sun's side as from the far side. That is not
	// what air does, and it is the difference an audit found between this fog and
	// Bliss's - its `sunPhase` runs to about 2.5 at the sun and its `phaseRayleigh`
	// varies by a factor of nearly two across the sky, so its medium reads as a
	// volume the light is travelling through rather than as a glow laid on the
	// screen.
	//
	// ⚠️ Henyey-Greenstein rather than Bliss's own curve, and the reason is that
	// Bliss's is two exponentials of a power tuned to its own light levels - a shape
	// ported without its numbers is a shape with nothing behind it, which is the
	// mistake this whole line of work has already made three times. HG is the
	// standard single-lobe phase function, it is one line, and its parameter means
	// something physical:
	//
	//     g = 0.4    forward-peaked, which is what makes looking towards the sun
	//                through mist flare and looking away from it not
	//
	// ⚠️ Normalised so that the AVERAGE OVER ALL DIRECTIONS IS ONE, which is what
	// makes it a redistribution of the light rather than a source of more of it.
	// Integrating HG over the sphere gives `1 - g^2` of the isotropic case, so the
	// division by `1 - g^2` puts the mean back to one: the fog is not made brighter
	// on average by this line, only brighter towards the sun and dimmer away from it.
	// Without it the peak at the sun would multiply the medium in addition to
	// peaking, and every fog setting in the pack would have had to be retuned to
	// compensate.
	float cosSun = dot(rayDirection, worldSunVector);

	float hgForward = (1.0 - FOG_PHASE_G * FOG_PHASE_G)
		/ pow(1.0 + FOG_PHASE_G * FOG_PHASE_G
			- 2.0 * FOG_PHASE_G * cosSun, 1.5);

	// ⚠️ A little of the light comes back towards the eye from the other side, and
	// without it the medium is darkest exactly opposite the sun - which reads as the
	// fog being switched off behind the player rather than as air. Bliss has the same
	// second lobe (`backScatterPhase`, an HG at -SdotV). 0.06 is small, and it is
	// deliberately smaller than the forward lobe rather than symmetric: mist really
	// is brighter looking into the light, which is the whole reason sunbeams are
	// visible from the sun's side and not from behind.
	float hgBack = (1.0 - FOG_PHASE_G_BACK * FOG_PHASE_G_BACK)
		/ pow(1.0 + FOG_PHASE_G_BACK * FOG_PHASE_G_BACK
			+ 2.0 * FOG_PHASE_G_BACK * cosSun, 1.5);

	float sunPhase = mix(hgForward, hgBack, 0.06);

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
				// costs one smoothstep and four mixes and no fetch and no step.
				//
				// ⚠️ coreness is 0 at the thin edge of a column and 1 from
				// NETHER_PLUME_CORE_DENSITY upwards, and that constant is the half
				// density the arithmetic in the options calls a column's core: the
				// field's own mean plume is 0.353 and a typical surviving pillar is
				// 0.51, so a typical pillar's middle comes out at one and everything
				// thinner than 0.5 lands somewhere on the ramp between.
				//
				// ⚠️ The four mixes are written around the constants the pass already
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
				// The whole of what this step sends towards the eye, in the order
				// the integral is written in - see the notes above the two lines
				// this replaces.
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
		// ⚠️ This test CANNOT FIRE, and saying so is the fix (batch 580). The
		// comment here used to claim it skips the shadow fetch for every step above
		// the layer and keeps a high camera as cheap as a low one. It does not:
		// VolumetricFogDensity returns `exp(-max(y - base, 0) / height)` times the
		// noise and the option dials, and an exp() is never zero - it is small, not
		// absent - so the branch has never been taken and the saving it promises has
		// never been banked. An audit found it by asking what the function actually
		// returns rather than what the comment said.
		//
		// ⚠️ It is left in place, unreachable, rather than replaced with a threshold:
		// a threshold would change the fog, since the medium above the layer is thin
		// but not empty and the whole point of an exponential layer is that it has no
		// edge. Making the saving real would mean deciding how thin is nothing, and
		// that is a decision about how the fog looks rather than about how it costs.
		// What is fixed is the claim, not the branch.
		float density = VolumetricFogDensity(cameraPosition + samplePos);

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
			// ⚠️ FILTERED OVER THE STEP'S OWN FOOTPRINT, and that is the fix for
			// the flicker through leaves (batch 584).
			//
			// ⚠️ The single fetch that used to stand here is a POINT SAMPLE of a
			// high-frequency function. The shaft through a canopy is not a smooth
			// field - it is a hard pattern of lit gaps and dark leaves, and a gap a
			// block or two across subtends less than one shadow texel from far
			// enough away. Point-sampling that at 48 places along a ray, where each
			// sample's position moves with the camera, is textbook aliasing: the
			// sample lands in a gap or on a leaf, and which one changes as the player
			// walks, so the ray's answer swings the full way between lit and dark from
			// one frame to the next.
			//
			// ⚠️ The resolution is what makes it visible, and the author reported
			// exactly that: bad at a quarter of the frame, absent at full resolution.
			// This pass marches ONE ray per fog texel, so at a quarter of the frame
			// one ray stands for sixteen pixels and its single shadow answer is asked
			// to represent all sixteen - but the leaf pattern varies across those
			// sixteen at a scale the one ray cannot see, so the texel flickers as a
			// unit. At full resolution each pixel has its own ray, the pattern is
			// resolved across pixels rather than aliased into one, and any flicker
			// left is sub-pixel and the frame's own temporal resolve handles it.
			//
			// ⚠️ Why the temporal denoise could not save it, which is worth knowing
			// before trusting a filter to: the denoise drops the history in proportion
			// to how much the colour DISAGREES, and a swing between fully lit and
			// fully shadowed is not noise to it - it looks exactly like the fog
			// genuinely changing, which is the case the history is supposed to be
			// dropped for. Filtering is the only answer; averaging cannot fix a signal
			// that is wrong in the same way every frame it is wrong.
			//
			// ⚠️ The width is the STEP'S FOOTPRINT and not a fixed softness, because
			// that is the quantity the aliasing is against. A step of the march covers
			// a volume, not a point - that is what stepping through a medium means -
			// and its cross-section is (stepLength / distance) radians across. Asking
			// the map for the average over that cross-section is therefore not a
			// blur laid over the answer; it IS the answer the sample was always meant
			// to stand for, and the unfiltered version was the approximation.
			//
			// ⚠️ And that is also why this does NOT change the full-resolution path,
			// which the author could see was already right: the footprint is a
			// property of the march, and the march is identical at both resolutions.
			// The filter widens for the quarter-resolution case because it makes the
			// same request of the map; it does not widen because the buffer got
			// smaller. Nothing here reads the buffer size or the option, so the
			// resolution bug cannot come back through this door.
			//
			// ⚠️ The width is the loop's own `stepLength`, declared above with the
			// two ends of the step rather than recomputed here: one name for one
			// quantity, and the two ends are what the sample's position was made
			// from as well.

			// ⚠️ HALF the step, because `spread` here is a RADIUS and the four taps
			// below are placed AT it: they sit on the corners of a square twice this
			// wide, so a radius of half the step makes the kernel span one whole step.
			// Asking for `stepLength` instead would filter a volume twice the size of
			// the one the sample stands for, which softens the canopy's own light
			// beyond what is being asked about.
			//
			// ⚠️ The distance is `samplePos`'s own length and not a fresh one: that
			// vector is this step's centre in camera-relative space, and it is made
			// from the same `start` and `end` the step's length is, so the two
			// quantities in the ratio describe the same volume. Taking the distance
			// from anywhere else - the fragment's own depth, say - would measure the
			// footprint of a different step.
			//
			// ⚠️ Why there is a division at all, given that a shadow map for a
			// directional light is ORTHOGRAPHIC and a length in blocks is therefore a
			// constant number of map texels wherever it is: because the map is
			// DISTORTED, and the distortion divides the map's coordinates by
			// `length(pos.xy) + factor` (see /lib/distort.glsl). That gathers the map
			// towards the player, which is a perspective-like compression of the map's
			// own coordinates, so the width this filter has to ask for in those
			// coordinates is the world-space width divided by the distance it is being
			// gathered from.
			//
			// ⚠️ `shadowProjection[0][0]` is the map's own blocks-to-clip scale, which
			// for an orthographic projection is 1 over the half-width of the box the
			// map covers - 1/128 here, the shadow distance the pack ships.
			//
			// ⚠️ The ceiling: a ray that grazes along the layer has a long step and a
			// short distance to it, and without a bound the four taps would walk the
			// whole map and read the shadow of somewhere else entirely. 0.02 of the
			// map is about five blocks at these settings, which is already wider than
			// any gap this is for.
			float spread = min(stepLength * 0.5 / max(length(samplePos), 1.0)
				* shadowProjection[0][0], 0.02);

			// ⚠️ AN IRREGULAR KERNEL ROTATED PER FOG TEXEL AND PER FRAME, which is the
			// second half of this fix (batch 585). Four taps on the corners of a square
			// are a REGULAR pattern, and a regular pattern sampled against a regular
			// texel grid produces a regular artefact: on a shadow edge, where the
			// filter has a gradient to work on, it shows as a texture that crawls
			// rather than as softness. The same four taps in the same orientation every
			// frame also leave the eye something to follow as the camera moves - which
			// is the author's report, and it was reported as crawling rather than as a
			// hard or a soft edge.
			//
			// ⚠️ The kernel is the same 16-point list the world's shadow filter uses.
			// See /environment/lighting/shadowmap.glsl, which is where it is written
			// down and where its provenance and its measured properties are. It is
			// repeated here rather than reached by an include because that file
			// declares `shadowtex1` and `shadowDistance` for the world's own purposes
			// and this pass declares both itself - two declarations in one program do
			// not compile.
			//
			// ⚠️ The rotation is hashed from the fog TEXEL's own position and not from
			// gl_FragCoord, because this pass runs at a quarter of the frame: hashing
			// the full-resolution coordinate would give the sixteen pixels inside one
			// fog texel sixteen different rotations, and every one of those pixels then
			// reads a fog value built from a DIFFERENT set of shadow samples. That is
			// noise across the texel instead of an average inside it, and the upscale
			// would have to smooth away something that was never meant to be there.
			// One rotation per fog texel keeps each texel's answer coherent.
			//
			// ⚠️ `frameCounter` is stirred in with an irrational step so consecutive
			// frames take angles as far apart as possible. A slow sequence of angles
			// would read as the same crawl at a different speed, which is worse than
			// not changing it at all.
			vec2 fogPixel = floor(screenCoord * vec2(textureSize(colortex1, 0)));

			float pcfAngle = fract(sin(dot(fogPixel, vec2(12.9898, 78.233))) * 43758.5453
				+ float(frameCounter) * 0.6180339887) * 6.28318530718;

			float pcfCos = cos(pcfAngle);
			float pcfSin = sin(pcfAngle);

			float shadowAverage = 0.0;

			for (int i = 0; i < 16; i++) {
				// The kernel's own RMS radius is 0.783, so dividing by it keeps the
				// filter as wide as `spread` says - see the note on the world's copy
				// of this kernel in shadowmap.glsl, where the number is worked out.
				vec2 pcfOffset = pcfDisk[i];
				vec2 pcfRotated = vec2(
					pcfOffset.x * pcfCos - pcfOffset.y * pcfSin,
					pcfOffset.x * pcfSin + pcfOffset.y * pcfCos) * (spread / 0.783);

				// texture() on a shadow sampler compares the third component against
				// what the map holds there and returns the result, with the hardware
				// doing the filtering.
				shadowAverage += texture(shadowtex1,
					vec3(shadowPos.xy + pcfRotated, shadowPos.z));
			}

			shadowAverage /= 16.0;

			sunVisibility = mix(
				1.0,
				shadowAverage,
				withinShadowMap);
		}

		// The light this step of the medium sends towards the eye: what the
		// medium is lit by, how much of it the sun reaches, and how much medium
		// there is. There is no transmittance term in the loop because this pass
		// adds light rather than replacing any - see the note at the top.
		//
		// ⚠️ TWO TERMS because a volume of air has two sources of light, and until
		// batch 580 there was only the first (batch 580; the audit that found it is
		// the one that read both implementations side by side). With only the sun
		// term a step in shadow contributed EXACTLY zero - `sunVisibility` is the
		// whole of the light - so the fog was not dimmed where the sun was blocked,
		// it was deleted, and the shape of the hole was the shadow map's silhouette.
		// Air takes light from the whole sky, so what a shadow does is change the
		// colour the medium scatters and barely change how much of it there is.
		//
		// ⚠️ The ambient term is NOT weighted by `sunVisibility`, and that is the
		// entire point: what blocks the sun does not block the sky. Bliss makes the
		// same split - `LightColor*shadows*... + AmbientColor*...`, its
		// lib/overworld_fog.glsl:338 - and it is the same arrangement the pack's own
		// clouds already use, where `cloudLightAmbient` and `cloudLightDirect` are
		// separate uniforms.
		//
		// ⚠️ 0.5 on the ambient, and it is the one number here rather than a
		// derivation: a medium lit from a hemisphere receives about half of what the
		// same medium lit by a disc of the same radiance would, and the pack's sky
		// ambient is already the average over the sky. Too high and the fog stops
		// responding to the sun at all, which is the old artifact with the sign
		// reversed; too low and the shadow outline comes back.
		// ⚠️ The phase applies to the SUN term and NOT to the ambient one, and that
		// split is the whole reason the phase is worth having (batch 582). An
		// ambient term is light that arrived at the medium from every direction
		// before it was scattered towards the eye, so it has no angle to the sun to
		// depend on - weighting it by `sunPhase` would make the sky's own light
		// directional, which is the one thing it is not. Bliss separates them the
		// same way: its `shadows*sunPhase` multiplies the light term and its
		// `AmbientColor` is added outside the angle entirely.
		vec3 stepLight = fogAmbientColor * 0.5
			+ mediumColor * (sunVisibility * sunPhase);

		scatter += stepLight * (density * stepLength);

	}

	vec4 raw = vec4(scatter, absorbance);

	// TEMPORAL DENOISE BEGIN

	// What the march made, before the denoise touches it. Kept apart rather than
	// denoised in place so that the one path that cannot have a history is one
	// assignment rather than three, and so that a debug view of the noisy buffer
	// is a view of what the march actually produced.
	vec4 resolved = raw;

	#ifdef VOLUMETRIC_FOG_DENOISE
		// ⚠️ There is no history in the first frames of a buffer's life, and the
		// test is on the frame rather than on the buffer's contents because a
		// buffer that has never been written holds whatever the driver left in
		// it: this one is not cleared - see colortex1Clear in /composite.fsh,
		// without which there is nothing to accumulate onto - so its first
		// contents are undefined and may well be plausible-looking values. Three
		// frames is enough for the flip to have put a written frame on both sides,
		// which is the condition that makes the read below a read of the frame
		// before this one.
		if (frameCounter >= 3) {
			// Where this texel was on the previous frame's screen.
			//
			// ⚠️ `rayDirection` is ALREADY A WORLD DIRECTION, and that is the one
			// thing this block has to get right: it was taken through
			// `mat3(gbufferModelViewInverse)` near the top of main() - see the note
			// there - and it was never brought back. So neither branch below may
			// put it through that matrix a second time. Doing so rotates it by the
			// camera's own rotation twice, and the point that comes out is not this
			// ray: at a yaw of ninety degrees it lands ninety degrees away, the
			// reprojection reads a texel with nothing to do with this one, and the
			// noise the stage removes comes and goes as the player turns - a defect
			// no still frame can show.
			//
			// ⚠️ The point that is reprojected is a choice, and it is the whole
			// difference between a denoise that follows the world and one that
			// slides across it. A ray through a pixel covers everything from the eye
			// to wherever it stops, and the history has to be looked up at ONE
			// point; which point is right depends on what stopped the ray:
			//
			//   * it stopped on something solid - a hill, a wall, the ground - and
			//     the fog on screen is what is in front of THAT SURFACE. The point
			//     is the surface, at the distance the march stopped at, so the fog
			//     and the history are anchored to the same place in the world and
			//     both walk with the camera;
			//   * it stopped at the far end of the medium, over a sky pixel - there
			//     is no surface, and the fog on screen is the whole column. What
			//     anchors it is the DIRECTION, and nothing about where the camera
			//     is or has walked: the point is one block along the direction from
			//     the PREVIOUS eye, which cancels the walk out of the difference
			//     the reprojection takes. Using the current eye there instead would
			//     carry the whole frame's movement into the history and slide the
			//     fog sideways across a sky that is not moving.
			//
			// ⚠️ The split is on the surface being at the far plane, which is the
			// same test composite1.fsh makes to mean "nothing was drawn here" and
			// the same depthtex0 the march read - not on surfaceDistance reaching
			// VOLUMETRIC_FOG_DISTANCE, which is where the MARCH stops and not where
			// the surface is. The two are different questions: a hill two hundred
			// blocks away caps the march at 96 and is still a surface the fog
			// belongs to.
			//
			// ⚠️ The held item is not reprojected like the world, for the reason
			// composite1.fsh gives in full: it is attached to the camera, so it
			// stays put relative to the eye while the world slides past, and
			// reprojecting it with the camera's translation makes it drag its own
			// history along with the walking. Cancelling the translation the same
			// way - by adding back the difference - leaves the reprojection
			// rotation-only. The threshold is the game's own non-linear depth, so
			// it is Mellow Shader's empirical number, which is where the resolve
			// took it from; the fog over a held item is a small part of the frame
			// and getting the branch slightly wrong costs a small error in it.
			const float FOG_DENOISE_HAND_DEPTH = 0.56;

			// Whether the camera moved at all since the previous frame.
			//
			// ⚠️ This is not an optimisation and it is the fix for the defect that
			// made this whole stage a no-op in its first shipped build (b569, and
			// the user's report is what found it: "the denoise on and off look about
			// the same"). When the camera has not moved, the reprojection is an
			// identity and there is nothing to compute - but computing it anyway
			// costs accuracy, not just time: the point is rebuilt from the depth
			// buffer, the depth buffer is written by geometry drawn with the TAA's
			// sub-pixel jitter, and the projection inverse is the un-jittered one, so
			// the reprojected coordinate comes back a fraction of a pixel off. That
			// fraction is enough to give `velocity` a non-zero value, which lowers
			// the history weight - and, far worse, it is different for every texel
			// and every frame, so the weight itself becomes a per-frame noise field.
			// A stage whose blend factor flickers is a stage that does not average.
			//
			// ⚠️ With the camera still there is nothing to reproject and the history
			// is simply this texel: the buffer holds the previous frame at the same
			// index, so the read needs no coordinate at all. That is the case a
			// player is in whenever they stop to look at the fog, which is when the
			// marching noise and its flicker are visible in the first place.
			bool cameraStill = all(equal(cameraPosition, previousCameraPosition));

			vec4 history = raw;

			// ⚠️ Whether the reprojection found anything, kept outside the branch
			// that computes it: the debug view at the end of this stage needs it, and
			// a diagnostic that reads a variable its own branch declared would not
			// compile. The camera-still path has no reprojection to have failed, so
			// it starts true.
			bool historyFromScreen = true;

			// ⚠️ And the same for the coordinate itself, and this one is a compile
			// error rather than a convention: the velocity below is worked out from
			// it and sits OUTSIDE this branch, so a `Reprojection` declared inside
			// would not be in scope where it is read. That is exactly what the first
			// build of this batch did, and the driver said so - "undefined variable
			// reprojection" at the velocity. The still path leaves it at zero, which
			// is what the velocity wants there anyway: with no reprojection there is
			// no movement to measure, and the branch that reads it knows that.
			vec2 reprojectedCoord = screenCoord;

			if (cameraStill) {
				history = texelFetch(colortex1, ivec2(gl_FragCoord.xy), 0);
			} else {
			// ⚠️ The anchor is placed on the RAY and not on the surface, and that
			// is the fix for the drag reported after batch 573. It took two
			// attempts; the first is worth keeping because the arithmetic killed
			// it.
			//
			// What was wrong: the anchor was the surface point, rebuilt from the
			// depth the march stopped at. That depth is point-sampled - which is
			// what fixed the mosaic, see where it is read - and a point-sampled
			// depth FLIPS at a silhouette, between the thing in front and the thing
			// behind. So the anchor jumped between two world points 30 blocks apart
			// every time the view turned a little, the history was read from the
			// wrong place on those frames, and the fog dragged.
			//
			// ⚠️ THE FIRST ATTEMPT WAS A MEDIAN FILTER over the 3x3 of depths, and
			// it does not work - not because it was written badly, but because the
			// geometry forbids it. At a silhouette the neighbourhood is roughly
			// half near samples and half far ones, so the middle of nine sits
			// exactly on the boundary between the two groups, and moving ONE
			// sample across that boundary moves the answer the whole way from one
			// surface to the other. Measured on synthetic neighbourhoods
			// (filter_choice.py): the true median of nine swings by the full 30
			// blocks, and so does any other order statistic. Only a mean is stable,
			// and a mean is precisely what caused the mosaic - it returns a
			// distance that no surface has.
			//
			// ⚠️ So the stable quantity is not a filtered depth; it is the
			// DIRECTION, which has no discontinuity anywhere. A point at a fixed
			// distance along the ray:
			//
			//   * reprojects correctly under rotation, because the ray rotates with
			//     the camera exactly as the world does;
			//   * reprojects correctly under translation, because the point is
			//     placed in the world, so the camera moving moves the point against
			//     it exactly as it moves terrain;
			//   * has NO dependence on any depth, so there is nothing in it to flip.
			//
			// ⚠️ What it gives up is anchoring at the surface, which is what a
			// reprojection prefers when it can be had: a texel whose fog belongs to
			// a wall right in front of it is now reprojected as though it belonged
			// to a point further along the same ray. What that costs is a small
			// reprojection error where the surface is much nearer than the anchor -
			// and what it buys is that the error is the SAME every frame instead of
			// alternating between two surfaces, which is the difference between a
			// history that can be averaged and one that cannot.
			//
			// ⚠️ The sky and the surface now take the same branch, which is the
			// other half of the simplification: there is no longer a test on the
			// depth here at all, so there is nothing for a flipping depth to
			// disturb. The held item keeps its branch, because it is the one case
			// where the answer is genuinely different - it is attached to the
			// camera and does not move like the world.
			vec3 anchorWorldPos = cameraPosition + rayDirection * FOG_DENOISE_ANCHOR_DISTANCE;

			if (depth <= FOG_DENOISE_HAND_DEPTH) {
				anchorWorldPos += previousCameraPosition - cameraPosition;
			}

			Reprojection reprojection =
				ReprojectWorldPosition(anchorWorldPos, screenCoord);

			// A pixel that was off the screen or behind the camera last frame
			// has no history at all.
			//
			// ⚠️ The fetch is behind the test rather than left to a clamped
			// coordinate. A clamp would make the read legal, but what it would
			// read is the fog at the edge of the screen - a texel with nothing to
			// do with this one - and the clamp would also put a NaN coordinate
			// into a fetch whose result would then have to be discarded anyway.
			historyFromScreen = !reprojection.offScreen
				&& !reprojection.behindCamera;

			reprojectedCoord = reprojection.previousCoord;

			if (historyFromScreen) {
				history = texture(colortex1, reprojection.previousCoord);
			}
		}

			// A history that is not a number, or is infinite, is replaced rather
			// than left to the mix below: a buffer that cannot hold a NaN turns one
			// into an ordinary zero, and a zero that reaches the history is a hole
			// in the fog rather than a dark fog. One bound asks the whole question,
			// and a NaN fails every comparison - which is why the negation is the
			// check.
			if (!(dot(history, history) < 1.0e18)) {
				history = raw;
			}

			// How far this texel moved since the previous frame, in pixels of the
			// FRAME.
			//
			// ⚠️ The frame's pixels and not this buffer's, which is the one thing
			// about this number that was got wrong here first. The weight below is
			// the temporal resolve's, and the resolve's velocity is measured on the
			// frame's grid (composite1.fsh); measuring this one on the fog's grid
			// makes a texel of motion mean a quarter of a pixel, so a slow pan that
			// moves the picture one pixel a frame scores a stillness of 0.94 and
			// keeps almost the whole history - which is exactly the movement the
			// weight exists to react to. A pixel is a pixel: the same number the
			// resolve uses, so the same number means the same thing in both.
			//
			// ⚠️ Zero when the camera is still, and it is zero because the history
			// is this texel - there is no reprojected coordinate to measure against,
			// which is the whole point of the branch above. Not a shortcut: the
			// measured coordinate at a standstill is a fraction of a pixel off (see
			// the note on cameraStill), and that fraction would come out here as a
			// per-frame noise field on the blend factor itself.
			vec2 velocity = cameraStill
				? vec2(0.0)
				: (screenCoord - reprojectedCoord) * vec2(viewWidth, viewHeight);

			// How much of the history this texel keeps.
			//
			// The shape is the temporal resolve's, in composite1.fsh: the option
			// is the weight for a texel that did not move, and exp(-|v|^2) takes it
			// towards seven tenths of itself as the texel starts to move. That is
			// what makes a long history usable at all - a long history is the only
			// thing that can average a per-frame sample out, and it is also what
			// smears anything that moves, so the two are split by motion.
			//
			// ⚠️ A whole pixel of motion already scores 0.37, so the floor is what
			// most of a moving frame actually gets. It is 0.7 of the option rather
			// than zero because zero would throw the history away outright on every
			// frame the camera moves at all, which is every frame a player is
			// walking - and the noise this exists to remove does not stop when they
			// do.
			float stillness = exp(-dot(velocity, velocity));
			float historyWeight = VOLUMETRIC_FOG_DENOISE_STRENGTH
				* mix(0.7, 1.0, stillness);

			// How much of the history this texel keeps, given how far the history
			// is from what is being drawn now.
			//
			// ⚠️ This scales the weight, and it does NOT throw the history away.
			// Its first version rejected outright - `historyWeight = 0.0` whenever
			// the two agreed to less than a quarter - and that is what made the
			// whole stage a no-op in the build the user first saw:
			//
			//   `mix(raw, raw, w)` is `raw`.
			//
			// The arithmetic behind that is worth keeping, because the mistake is
			// easy to make again. `raw` is ONE sample of the estimator and
			// `history` is an average of about ten, so the difference between them
			// is dominated by raw's own per-frame error - its deviation is the
			// marching noise itself, not a fraction of it. At a relative noise of
			// 0.3, which a 24-step march over a mostly-empty medium reaches easily
			// (BATCH_LOG.md b569 measures this), a quarter threshold fired on about
			// **35% of all texels every frame**; at 0.5 it fired on 57%. A hard test
			// cannot sit above that noise and below a real scene change at the same
			// time, so it is the wrong instrument - it either discards the history
			// or it does nothing.
			//
			// What replaces it is the same measurement used as a weight, which has
			// no cliff in it:
			//
			//   * a texel where nothing changed keeps the full weight, and the
			//     history averages the dither away - which is the entire purpose;
			//   * a texel where the fog really has changed keeps almost none of it,
			//     and starts again from this frame;
			//   * and a texel where the history is merely noisy is pulled *towards*
			//     the current frame rather than being discarded, which is the case
			//     the old test could not express at all.
			//
			// ⚠️ The relative form is kept for the reason it was introduced: the
			// scattered light's scale is set by the exposure in shaders.properties
			// and by the time of day, so an absolute difference would be a different
			// test at noon and at dusk. What the reference is matters, though, and
			// it is the LARGER of the two rather than the raw frame: on the raw
			// frame alone, a texel whose history is correctly bright and whose raw
			// sample happens to be dark - which is exactly what the marching noise
			// produces - would read as a large change and be rejected, which is the
			// same defect in a smaller costume.
			//
			// ⚠️ It cannot fire on noise, and that is arithmetic rather than hope:
			// the ratio is a difference over the larger of two positive numbers, so
			// it is bounded by one; and below the scale floor the difference is
			// tested against the floor rather than against nothing, which is what
			// stops two black pixels on a dark night from reading as a change.
			float rawLuma = dot(raw.rgb, vec3(0.2126, 0.7152, 0.0722));
			float historyLuma = dot(history.rgb, vec3(0.2126, 0.7152, 0.0722));

			// Floored, so that the ratio cannot be against zero.
			float lumaScale = max(max(rawLuma, historyLuma), 1.0e-4);

			float disagreement = clamp(
				abs(historyLuma - rawLuma) / lumaScale
					/ VOLUMETRIC_FOG_DENOISE_TOLERANCE,
				0.0, 1.0);

			// ⚠️ The floor on the falloff, and it is what makes a real change
			// recover. At 0.0 the history would keep nothing and a texel whose fog
			// had genuinely gone - a door closed over a lit room - would snap to the
			// current frame, which is the cliff this whole change is undoing; at
			// 0.25 a texel that disagrees completely still keeps a quarter of each
			// frame, so a ghost is down to a sixteenth in three frames and gone in
			// about five, while a texel that agrees keeps the full average.
			historyWeight *= mix(0.25, 1.0, 1.0 - disagreement);

			// The weight is checked before it is used, and it is the last place in
			// this pass where a value that is not a number can still get in:
			// previousCoord came out of a clip-space division by its own w, and
			// mix(raw, raw, NaN) is a NaN. Zero rather than anything else, because
			// zero takes this texel from the current frame, which is the one answer
			// that cannot be wrong about a frame already known to be finite.
			if (!(historyWeight >= 0.0 && historyWeight <= 1.0)) {
				historyWeight = 0.0;
			}

			resolved = mix(raw, history, historyWeight);

			// A transmittance outside nothing and everything is not a transmittance.
			// The mix cannot produce one - both of its arms are in range - but the
			// value goes into a buffer the next frame reads back as its history, and
			// the picture multiplies the scene by it, so it is clamped where it is
			// made. ⚠️ It also cannot drift: a value that came back out of range
			// would be mixed in again every frame, so this is what keeps a
			// transmittance a transmittance for as long as the buffer lives.
			//
			// ⚠️ Inside the #ifdef, with the stage it belongs to. Outside it, this
			// line would run on the path where the option is off as well - which is
			// a no-op for the march's own output, whose fourth channel is 1.0 or a
			// product of exp()s, but it is a no-op this batch should not be adding
			// to a path it claims not to touch. See the note on the guard below for
			// the one line that has to stay outside.
			resolved.a = clamp(resolved.a, 0.0, 1.0);

			#ifdef VOLUMETRIC_FOG_DENOISE_DEBUG
				// What the stage actually did with this texel, in colour.
				//
				// ⚠️ This exists because the first shipped version of the stage
				// (b569) was a no-op and NOTHING on this machine could see that: the
				// user's report - "the denoise on and off look about the same" - was
				// the only evidence, and it arrived after the build was delivered. A
				// filter whose whole job is to change what a moving picture looks
				// like cannot be checked by reading its source; it has to be looked
				// at. This is what to look at.
				//
				// The four colours are the four states the stage can be in, and they
				// are the whole diagnosis:
				//
				//   * GREY  - `frameCounter < 3`: the buffer has no written history
				//             yet, so nothing is being averaged. Should only ever be
				//             seen for the first frames after a load or a resize.
				//   * BLACK - the camera is still and the history IS this texel:
				//             the ideal case, and the one a player is in whenever
				//             they stop to look at the fog. **A frame that is not
				//             black here while the player stands still is a bug in
				//             the reprojection, not in the averaging.**
				//   * GREEN - the camera is moving and the reprojection found a
				//             texel on screen, so the history was read. Brightness
				//             is how much of it was kept after the disagreement
				//             falloff: a texel with no history use left is red.
				//   * RED   - the reprojection went off screen or behind the camera,
				//             so there is no history at all. Saturated red over the
				//             whole frame is the signature of a reprojection that is
				//             wrong, which is what the double rotation of b569 looked
				//             like.
				if (frameCounter < 3) {
					resolved.rgb = vec3(0.5);
				} else if (cameraStill) {
					resolved.rgb = vec3(0.0);
				} else if (historyFromScreen) {
					resolved.rgb = vec3(0.0, historyWeight, 0.0);
				} else {
					resolved.rgb = vec3(1.0, 0.0, 0.0);
				}

				resolved.a = 1.0;
			#endif
		}
	#endif

	// Whatever this buffer holds, nothing that is not a number leaves the pass
	// that fills it - the guard postprocessing.fsh's own UpsampleVolumetrics ends
	// with, for the same reason. One bound asks the whole question, and the
	// fallback is no fog rather than a black speck: no scattered light and full
	// transmittance, which is the state the march above starts from.
	//
	// ⚠️ This one is deliberately OUTSIDE the #ifdef, and it is the only line
	// after the march that is. Both paths end here - the march's own output feeds
	// it when the option is off - so putting it inside would leave the off path
	// unguarded, and putting it inside would also make it dead code on the path
	// it is most likely to be needed on. It does not change any value the march
	// can produce: the buffer is RGBA16F, whose largest finite value is 65504, so
	// dot(x,x) tops out near 1.3e10 against a bound of 1e18.
	//
	// ⚠️ It follows the clamp rather than preceding it, because `clamp(NaN, 0.0,
	// 1.0)` is a NaN - on the denoised path the two are one guard split in two,
	// not two guards.
	if (!(dot(resolved, resolved) < 1.0e18)) {
		resolved = vec4(0.0, 0.0, 0.0, 1.0);
	}

	fogScatter = resolved;
}
