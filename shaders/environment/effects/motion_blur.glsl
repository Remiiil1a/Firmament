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

// Added 2026-09-14 by Remiiil1a for Firmament - v0.2 (edit of coderbot's Steadfast).

// Motion blur, driven by the camera travelling through the world between frames.
//
// How it works
// ------------
// Every pixel is a point in the world, and the world does not move between two
// frames - the camera does. A camera that has travelled by some distance sees
// that same point from somewhere else, which puts it somewhere else on the
// screen; the distance between the two positions is how far this pixel moved,
// and the blur is the image averaged along that segment.
//
// The point's position is recovered per pixel rather than once for the screen,
// so the movement is the pixel's own: walking makes the ground at your feet rush
// past and leaves the far horizon almost still, which is what a camera does and
// what one screen-wide offset cannot.
//
// Travel and turning, but not the bob
// -----------------------------------
// The camera's travel and its turning both move the picture and both are used.
// What is deliberately left out is the walk bob - the up-and-down and the roll
// of the view that comes with each step.
//
// The bob cannot simply be filtered out, because it *is* a rotation, and it is
// baked into the same matrix as the turning. What separates the two is size: at
// a walk the bob moves the picture one or two pixels a frame, while a turn worth
// blurring moves it dozens. So the turning is only added to the blur once it is
// moving more than a few pixels a frame, and a slow turn - a hand resting on the
// mouse - is not blurred. See the note on the dead zone below.
//
// What it does not do
// -------------------
// Only the camera is blurred. Steadfast has no motion vectors - a mob, a river,
// a falling block or a thrown item carries no record of where it was a frame ago
// - so those stay sharp and only what the camera did is smeared. That is also
// why the hand is left alone entirely: it is held in front of the camera, so on
// screen it is standing still while the camera walks past the rest of the world,
// and treating it like world geometry would smear it across the screen.
//
// Where it runs
// -------------
// In the final pass, on the scene colour as it is read and before the tonemap,
// so the blur happens in linear light where a bright pixel and a dark one mix
// the way they should. See /program/post/postprocessing.fsh.

#ifndef MOTION_BLUR_INCLUDED
#define MOTION_BLUR_INCLUDED

// Whether the image is blurred along the camera's movement.
//
// Off, because it is a taste rather than a correction: it makes fast movement
// read as fast, and it costs a little sharpness everywhere the camera is turning.
// The #ifdef is what makes Iris register this as a boolean option; the effect
// itself is applied by postprocessing.fsh.
//#define MOTION_BLUR
#ifdef MOTION_BLUR
#endif

// How far the blur reaches, as a multiple of the distance the pixel actually
// moved. 1.0 is the honest value; below that the blur is a hint of movement,
// above it the blur runs longer than the movement that caused it.
#define MOTION_BLUR_AMOUNT 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0 3.0 4.0]

// How many samples the blur takes along that movement, and so how smooth it is.
// Each one is a texture fetch on every pixel of the screen, which is what this
// feature costs: 2 is a visible double image, 8 is smooth in most scenes, and
// above that the difference is small.
#define MOTION_BLUR_SAMPLES 8 // [2 4 6 8 12 16 24 32]

// The lens: a bug this effect had, kept on purpose because it looks like
// something.
//
// The turning is measured by taking this pixel's direction, putting it through
// the view the previous frame was drawn with, and seeing where it lands. The
// direction has to be turned into world axes for that, and when it is not - when
// the view-space direction is handed to the previous view's matrix - the view's
// own rotation is applied twice. The result is a disc of wrong movement that
// turns with the camera at twice the angle the camera turns: looking north it
// sits exactly where you are looking and does nothing at all, and turning the
// view a quarter turn carries it half a turn round.
//
// It is off by default, because a movement blur that adds movement nobody made
// is a bug and not an effect. It is here because it was reported as a curiosity
// and asked for again; see PBR_PORTING.md §26.
//#define MOTION_BLUR_LENS
#ifdef MOTION_BLUR_LENS
#endif

#ifdef MOTION_BLUR

// The colour of the finished image, which the final pass has already been given
// by the passes before it. Declared behind a guard because the pass that
// includes this file declares the same texture for its own use, and a repeated
// uniform declaration is an error. See the note in /lib/taa.glsl.
#if !defined(SCENE_TEXTURE_DECLARED)
	#define SCENE_TEXTURE_DECLARED
	uniform sampler2D colortex0;
#endif

// The depth buffer, for the distance of this pixel from the eye - the hand test
// below is made of it, and nothing else here needs it.
uniform sampler2D depthtex0;

uniform mat4 gbufferProjection;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelView;

// The matrix the previous frame was drawn with, for the turning below. Only its
// rotation is used; see the note on the dead zone.
uniform mat4 gbufferPreviousModelView;

// Where the camera is and where it was, which is the movement of the travel half
// of this effect.
uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

// How close to the eye the blur gives up, in blocks, and where it is back to
// full strength. One frame of walking moves the camera a few centimetres, which
// at the distance a held item sits at would be most of the screen - so the
// near range is left sharp and the fade in between keeps that from becoming a
// visible line.
const float MOTION_BLUR_NEAR = 0.6;
const float MOTION_BLUR_FAR = 1.5;

// How much of the screen a turn has to move before it is blurred, in pixels per
// frame, and where it reaches full strength.
//
// The walk bob is a rotation of the view, and a small one: at a walk its own
// movement is one or two pixels a frame, while turning the head at any speed
// worth blurring moves the picture dozens. A dead zone in between keeps the bob
// out of the blur without needing to know anything about it - which matters,
// because the bob is baked into the same matrix as the turning and cannot be
// taken back out of it.
//
// The price is that a very slow, deliberate turn - slower than about a quarter
// of a pixel per frame at this resolution, which is a hand resting on the mouse
// more than a turn - is not blurred either.
const float MOTION_BLUR_TURN_MIN_PIXELS = 3.0;
const float MOTION_BLUR_TURN_MAX_PIXELS = 12.0;

// Where a world direction lands on the screen under the rotation of the previous
// frame and the projection of this one - or (-1, -1) if that view had the
// direction behind the eye, where there is no screen position to be had.
//
// A direction rather than a position on purpose: the screen position of a point
// depends on nothing but the direction from the eye to it, so a direction is
// enough for any distance, and a direction has no origin for the translation of
// the matrix to move - which is what keeps the bob's translation out of this.
vec2 TurnedScreenCoord(vec3 worldDir) {
	vec3 previousDirView = mat3(gbufferPreviousModelView) * worldDir;
	vec4 previousDirClip = gbufferProjection * vec4(previousDirView, 1.0);

	if (previousDirClip.w <= 0.0) {
		return vec2(-1.0);
	}

	return previousDirClip.xy / previousDirClip.w * 0.5 + 0.5;
}

// The finished colour of this pixel, blurred along the movement of the camera.
//
// `screenCoord` is where this pixel is on the screen, in 0.0 to 1.0, in the same
// space the scene texture is sampled in.
vec3 MotionBlur(vec2 screenCoord) {
	// This frame's fragment, in the view space of the frame it was drawn in.
	float depth = texture(depthtex0, screenCoord).r;

	vec3 ndcPos = vec3(screenCoord * 2.0 - 1.0, depth * 2.0 - 1.0);
	vec4 viewPosH = gbufferProjectionInverse * vec4(ndcPos, 1.0);
	vec3 viewPos = viewPosH.xyz / viewPosH.w;

	// How far the camera has travelled since the previous frame, in the axes of
	// the view. The matrix the geometry was drawn with turns world directions
	// into view ones, and this is a direction as far as it is concerned: only the
	// rotation of that matrix is used, so the bob - which is a rotation and a
	// small translation of the same matrix - is left out of the movement.
	vec3 travelView = mat3(gbufferModelView)
		* (cameraPosition - previousCameraPosition);

	// The same world point, seen from where the camera was a frame ago. The
	// camera moved forward, so relative to it the point stood further back.
	vec3 previousViewPos = viewPos - travelView;

	// Where that lands on the screen, under the same view and the same
	// projection: a frame in which the camera had moved and done nothing else.
	vec4 previousClipPos = gbufferProjection * vec4(previousViewPos, 1.0);

	// A point that the previous camera would have had behind it has no screen
	// position to be found at, and no movement worth drawing.
	if (previousClipPos.w <= 0.0) {
		return texture(colortex0, screenCoord).rgb;
	}

	// How far this pixel moved, and so the segment the blur is drawn along. A
	// pixel with nothing in front of it has no position of its own to move, and
	// comes out with almost no movement of its own: the sky is very far away, and
	// travelling does not change how a distant thing looks from here.
	vec2 previousScreenCoord = previousClipPos.xy / previousClipPos.w * 0.5 + 0.5;

	// Folded back onto the edge of the screen rather than dropped, so that the
	// few pixels at the edge blur by a little less instead of coming out as a
	// band of sharp pixels with a blurred one beside it.
	previousScreenCoord = clamp(previousScreenCoord, vec2(0.0), vec2(1.0));

	vec2 velocity = screenCoord - previousScreenCoord;

	// The turning of the camera, which is the other half of its movement: where
	// this pixel's direction was on the screen before the view turned.
	//
	// The direction has to be in world axes for that, and `viewPos` is not: the
	// vector from the eye to this pixel is expressed in the axes of the frame it
	// was drawn in. Reading it out against the columns of that matrix turns it
	// into world axes - the matrix's transpose, which for a rotation is its
	// inverse - and the previous frame's matrix then turns it back into the axes
	// the previous frame used, which is the whole comparison.
	//
	// Handing the view-space direction straight to the previous matrix instead
	// applies the view's own rotation a second time, which is what MOTION_BLUR_LENS
	// preserves on purpose. See the note on that option.
	vec3 viewDir = normalize(viewPos);
	mat3 viewAxes = mat3(gbufferModelView);
	vec3 worldDir = vec3(
		dot(viewDir, viewAxes * vec3(1.0, 0.0, 0.0)),
		dot(viewDir, viewAxes * vec3(0.0, 1.0, 0.0)),
		dot(viewDir, viewAxes * vec3(0.0, 0.0, 1.0)));

	#ifndef MOTION_BLUR_LENS
		vec2 turnedScreenCoord = TurnedScreenCoord(worldDir);
	#else
		// The view-space direction, which is the doubled rotation. Deliberate; see
		// the option.
		vec2 turnedScreenCoord = TurnedScreenCoord(viewDir);
	#endif

	// A direction the previous view had behind the eye has no screen position to
	// compare against, so nothing is added for it.
	if (all(greaterThan(turnedScreenCoord, vec2(-0.5)))
		&& all(lessThan(turnedScreenCoord, vec2(1.5)))) {
		vec2 turnVelocity = screenCoord - turnedScreenCoord;

		// How much of the screen that turn moved, in pixels: small movements are
		// the walk bob rather than the player turning, and are left out. See the
		// note on the dead zone above.
		float turnPixels = length(turnVelocity / windowToScreen);

		velocity += turnVelocity * smoothstep(
			MOTION_BLUR_TURN_MIN_PIXELS,
			MOTION_BLUR_TURN_MAX_PIXELS,
			turnPixels);
	}

	velocity *= MOTION_BLUR_AMOUNT;

	// Everything this close to the eye is held in front of the camera rather than
	// standing in the world, and does not move across the screen as the camera
	// does. See the note at the top of this file.
	velocity *= smoothstep(MOTION_BLUR_NEAR, MOTION_BLUR_FAR, length(viewPos));

	// The samples are spread evenly along the segment, centred on the pixel, so
	// that the blur is symmetric and the image does not shift along the movement.
	vec3 blurred = vec3(0.0);

	for (int i = 0; i < MOTION_BLUR_SAMPLES; i++) {
		float t = (float(i) + 0.5) / float(MOTION_BLUR_SAMPLES) - 0.5;
		vec2 sampleCoord = clamp(
			screenCoord + velocity * t,
			vec2(0.0),
			vec2(1.0));

		blurred += texture(colortex0, sampleCoord).rgb;
	}

	return blurred / float(MOTION_BLUR_SAMPLES);
}

#endif /* MOTION_BLUR */

#endif /* MOTION_BLUR_INCLUDED */
