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
// PBR_PORTING.md 169 for why.

// One ray per half-resolution pixel, from the eye to whatever the depth buffer
// shows, accumulating the light the medium scatters towards the eye on the way.
//
// It writes the scattered light and nothing else - not the fading of what is
// behind it. The pack's own fog already owns that, per fragment, in the surface
// programs; doing it here as well would count it twice, and doing it here
// instead would mean moving a term that four other things read. See the same
// note in the settings file.
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
// shadowDistance" on the driver. PBR_PORTING.md 171 records it.

uniform float viewWidth;
uniform float viewHeight;

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
// PBR_PORTING.md 176 records it.
uniform vec3 underwaterFogColor;

// Three channels and no alpha: the scattered light is a colour, and the fading
// it is not doing does not need a fourth channel to carry.
const int R11F_G11F_B10F = 0;
const int colortex1Format = R11F_G11F_B10F;

// colortex1 can be named by DRAWBUFFERS, which reaches as far as nine - so this
// pass keeps the older directive and matches the rest of the pack, unlike the
// SMAA and bloom passes which have to reach past it.
/* DRAWBUFFERS:1 */

layout(location = 0) out vec3 fogScatter;

void main() {
	// Where this fragment is on the screen. viewWidth is the size of the frame
	// and not of this target, so the target's own scale has to be written in
	// here by hand; getting it wrong offsets the whole effect by part of a
	// screen.
	//
	// A quarter of the frame rather than a half. The result is a wide smooth
	// glow with no edges of its own, which is the case upscaling handles best -
	// and the four times smaller target both pays for the higher step count
	// below and smooths what the dither leaves behind, which matters here
	// because this pack has no temporal filter left to do it.
	#ifdef VOLUMETRIC_FOG_FULL_RES
		vec2 screenCoord = gl_FragCoord.xy / vec2(viewWidth, viewHeight);
	#else
		vec2 screenCoord = gl_FragCoord.xy / (vec2(viewWidth, viewHeight) * 0.25);
	#endif

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
	vec3 mediumColor = isEyeInWaterFog == 1 ? underwaterFogColor : fogSunColor;

	// The cloud transmittance that used to be worked out here was taken back out
	// in b318: read once per pixel, at one point along the ray, it made the
	// shafts wander and flicker as the clouds drifted, and what it bought was not
	// worth that. See PBR_PORTING.md 175. The clouds still shade the terrain
	// exactly as they did - this was only ever the fog's own copy of it.

	vec3 scatter = vec3(0.0);

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

	fogScatter = scatter;
}
