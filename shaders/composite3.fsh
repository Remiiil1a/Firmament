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

// Added 2026-09-22 by Remiiil1a for Firmament - the environment reflection, in a
// pass of its own, and resolved over time. See PBR_PORTING.md 121 and 123.

#version 150 compatibility

// The environment reflection of every material surface on screen.
//
// It is here, rather than in composite1, because of what it has to read.
//
// A reflection is a lookup into the world that is already drawn, and the world
// that is already drawn and put together over the last few frames is colortex3,
// which composite1 writes. A pass cannot read what it is writing, so the
// reflection cannot live in that pass: it can only read what composite1 leaves
// behind unused, and what it leaves is colortex4 - the frame as it was drawn,
// before the temporal resolve averaged the jitter of the last few frames out of
// it.
//
// That is one of the two reasons a reflection moved at all. The other is this
// pass's own history, below: the reflection is computed from the depth buffer
// and the material buffer, and the gbuffer pass draws both with a sub-pixel
// offset that changes every frame. A ray leaving a surface therefore sets out
// from a slightly different point every frame and lands on a slightly different
// place, and because the reflection is added after the temporal resolve, nothing
// downstream averages that out. What it looks like is a reflection that crawls.
// Enough frames a second and the eye does the averaging itself; at sixty it does
// not, which is how it was found.
//
// So this pass resolves its own output over time, in colortex9, the way
// composite1 resolves the picture. Both halves are needed: a stable picture to
// trace over, and a result that has stopped moving.

// The picture the reflection is added to, which is also the buffer this pass
// writes.
uniform sampler2D colortex0;

// The sky light at this pixel, written by the surface programs and not touched
// since. The reflection is faded out by it.
uniform sampler2D colortex2;

// The depth of the surface each pixel shows, translucents included. It is the
// one the reflection's "is this pixel seen through water" test needs.
uniform sampler2D depthtex0;

uniform mat4 gbufferProjectionInverse;

// The reflection this pass produced last frame, and the distance it was computed
// at, in the alpha channel. See the note on the history below.
//
// RGBA16F for the colour, which is the HDR reflection and not a display value,
// and whose alpha has room for the distance. Not cleared between frames, or
// there would be no history to accumulate onto.
const int RGBA16F = 0;
const int colortex9Format = RGBA16F;
const bool colortex9Clear = false;
uniform sampler2D colortex9;

// The scene's own temporal state, which the reflection rides on rather than
// duplicating: TAA to know whether there is a history at all, TAA_STRENGTH for
// how much of it to keep, and the view size for the pixel velocity that decides
// how much of it is safe to keep. See lib/taa.glsl.
#include "/lib/taa.glsl"

// Everything the reflection is built from: the pack's sky (SkyColor, SkyDither),
// the material model's option switches, the reflection helpers, the tracer, and
// the reflection itself.
//
// This is the same set composite1 includes to run the same reflection, and it
// has to be spelled out again rather than inherited: a program sees only what
// its own includes bring it, and a file that some other program includes is not
// included here. That is what the check script's third rule is for.
//
// The last include is where colortex3, depthtex1 and windowToNdc are declared,
// and it sits above every use of them below. Declaring any of the three here as
// well would be the same declaration twice in one program, which does not
// compile.
#include "/environment/sky.glsl"
#include "/environment/lighting/pbr.glsl"
#include "/environment/lighting/reflections.glsl"

// The trace's step budget, which is an option rather than the water reflections'
// constant. Has to be set before the include below, which only falls back to its
// own default if nobody has chosen one.
#define RAYMARCH_STEPS PBR_SSR_STEPS

#include "/lib/raytrace.glsl"
#include "/environment/lighting/environment_reflection.glsl"

// Where this surface point was on screen last frame, and the rest of what the
// reflection's history needs to be reprojected onto the current one. The scene's
// own resolve in composite1 does the same thing with the same matrices; the
// reflection repeats it because it is a different point in the frame, built from
// a different depth buffer.
uniform mat4 gbufferModelViewInverse;
uniform mat4 gbufferPreviousProjection;
uniform mat4 gbufferPreviousModelView;

uniform vec3 cameraPosition;
uniform vec3 previousCameraPosition;

uniform vec2 windowToScreen;

/* DRAWBUFFERS:09 */

void main() {
	ivec2 pixel = ivec2(gl_FragCoord.xy);
	vec2 screenCoord = gl_FragCoord.xy * windowToScreen;

	// The resolved image, which the reflection is added on top of. It arrives
	// fogged, as it left the deferred pass, and with no reflection in it.
	vec3 resolved = texelFetch(colortex0, pixel, 0).rgb;

	// What the next frame reads back as its history. Left at zero wherever there
	// is no reflection, so that a surface that starts reflecting does not inherit
	// the history of whatever was drawn there before it, and at a distance no
	// surface can have, so that the first frame of a reflection is never mistaken
	// for a continuation of one.
	vec3 reflectionResolved = vec3(0.0);
	// A distance no surface can have, so that the first frame of a reflection is
	// never mistaken for a continuation of one. It has to be a number the buffer
	// can hold: this is an RGBA16F target, whose largest finite value is 65504, so
	// the 1.0e9 this started as was stored as an infinity - which happened to
	// behave the same way and would have stopped doing so the moment anything
	// compared it.
	float reflectionDistanceStored = 1.0e4;

	#if defined(PBR_REFLECTIONS) || defined(PBR_SSR)
		// The view position is rebuilt here rather than passed in: this pass has
		// only the pixel it is writing, and every buffer it needs is read by
		// coordinate.
		//
		// depthtex1 rather than depthtex0: the tracer marches the opaque depth
		// buffer, so the ray has to start on the surface that buffer describes.
		// depthtex0 has the translucents in it, and at any pixel where a water or
		// glass surface is in front the two are different surfaces - so the ray
		// would set out from the glass and immediately meet the block behind it,
		// which is a reflection of the wrong thing from the wrong place.
		float reflectionDepth = texelFetch(depthtex1, pixel, 0).r;

		if (reflectionDepth < 1.0) {
			vec3 reflectionNdc = vec3(
				gl_FragCoord.xy * windowToNdc,
				reflectionDepth * 2.0) - 1.0;
			vec4 reflectionViewPosH =
				gbufferProjectionInverse * vec4(reflectionNdc, 1.0);
			vec3 reflectionViewPos =
				reflectionViewPosH.xyz / reflectionViewPosH.w;

			// Whether this pixel is being looked at through something
			// translucent, which the reflection declines to be computed for -
			// see the note on the parameter in environment_reflection.glsl.
			//
			// The two depth buffers answer it between them: only one of them has
			// the translucent pass in it, so the one with the translucents in it
			// being the nearer of the two means there is a water, ice or glass
			// surface in front of whatever is drawn at this pixel.
			bool seenThrough = texelFetch(depthtex0, pixel, 0).r
				< texelFetch(depthtex1, pixel, 0).r;

			vec3 environmentReflection = EnvironmentReflection(
				reflectionViewPos,
				texelFetch(colortex2, pixel, 0).r,
				seenThrough);

			// How far from the eye this reflection was worked out, which is what
			// the next frame compares its own distance against. A distance
			// rather than the depth buffer's own value, because that value is
			// squeezed into the last thousandth of its range for everything past
			// a few blocks, and a half float cannot tell two of those apart.
			float reflectionDistance = length(reflectionViewPos);

			#if TAA == TAA_ON
				// Where this surface point was on screen last frame.
				//
				// Only in the anti-aliasing mode: the reflection rides on the
				// scene's temporal state rather than duplicating it, and in
				// DENOISE there is no reprojected history to ride on - the scene
				// averages each pixel with itself, so there is no way to place the
				// reflection's own history and it is left with the current frame.
				// See TAA_DENOISE in lib/taa.glsl.
				// Rebuilt from the reflection's own view position rather than
				// reused from the scene's resolve: that one is the point this
				// pixel shows, and this is the point the ray starts from, which
				// is the same depth in the opaque buffer and not necessarily the
				// same place. Working in absolute terms so that this survives the
				// camera moving is the same trick composite1 uses.
				vec3 reflectionCameraRelativePos =
					(gbufferModelViewInverse * vec4(reflectionViewPos, 1.0)).xyz;
				vec3 reflectionWorldPos =
					reflectionCameraRelativePos + cameraPosition;

				vec4 previousReflectionClipPos = gbufferPreviousProjection
					* (gbufferPreviousModelView
						* vec4(reflectionWorldPos - previousCameraPosition, 1.0));
				vec2 previousReflectionCoord =
					(previousReflectionClipPos.xy / previousReflectionClipPos.w)
						* 0.5 + 0.5;

				// Both halves of what makes a sample untrustworthy, as in the
				// scene's resolve: the pixel was not on screen last frame, or the
				// surface under it is not the surface this reflection belongs to.
				//
				// The second test is what stops a reflection being dragged onto
				// whatever moves in front of it. A distance that has changed by
				// more than a hand's width, growing with distance the way the
				// depth buffer's precision does, is a different surface.
				//
				// The first test is written as "is it inside the frame", then
				// negated, rather than as "is it outside it", and that is not a
				// matter of taste: a comparison against a NaN is false, so a
				// coordinate divided by a w of zero is neither less than zero nor
				// greater than one and would pass an outside test. A history that
				// is not a number is permanent - the next frame reads this frame's
				// output back - so it grows instead of fading. See
				// PBR_PORTING.md 129.
				bool reflectionOffScreen =
					!(all(greaterThanEqual(previousReflectionCoord, vec2(0.0)))
						&& all(lessThanEqual(previousReflectionCoord, vec2(1.0))))
					|| previousReflectionClipPos.w <= 0.0;

				// Sampled only where there is a coordinate to sample with. A
				// texture() at a coordinate that is not a number has no defined
				// result, and one of the results a driver may give is an ordinary
				// colour from the edge of the texture - which would then look
				// exactly like a good history and pass every test below.
				vec4 reflectionHistory = reflectionOffScreen
					? vec4(0.0)
					: texture(colortex9, previousReflectionCoord);

				// And the history itself, whatever it was fetched with: one bound
				// asks about both infinities and about a NaN, because a NaN fails
				// every comparison. isinf() is not available in GLSL and isnan()
				// alone does not catch an infinity, which is how the first version
				// of this let a -Inf through: it is neither a NaN nor greater than
				// the bound it was compared against, and it is permanent once it
				// is in the buffer.
				//
				// The alpha is checked on its own because it carries the distance
				// rather than a colour, so it is not meaningful to ask about the
				// length of the whole vector.
				bool reflectionHistoryBad =
					!(dot(reflectionHistory.rgb, reflectionHistory.rgb) < 1.0e18)
					|| !(abs(reflectionHistory.a) < 1.0e18);

				float reflectionTolerance = 0.1 + 0.02 * reflectionDistance;
				bool reflectionDisoccluded = frameCounter < 2
					|| reflectionOffScreen
					|| reflectionHistoryBad
					|| abs(reflectionHistory.a - reflectionDistance) > reflectionTolerance;

				// How far this pixel moved since the previous frame, in pixels,
				// and how much of the history that leaves. The scene's resolve
				// splits its weight the same way and for the same reason: a long
				// history is what averages a per-frame sample out, and a long
				// history is also what smears anything that moves.
				vec2 reflectionVelocity = (screenCoord - previousReflectionCoord)
					* vec2(viewWidth, viewHeight);
				float reflectionStillness =
					exp(-dot(reflectionVelocity, reflectionVelocity));

				float reflectionHistoryWeight = reflectionDisoccluded
					? 0.0
					: TAA_STRENGTH * mix(0.7, 1.0, reflectionStillness);

				// The weight is computed from the coordinate, so a coordinate that
				// is not a number would make it one - and a NaN weight is not
				// caught by any test on the history.
				if (!(reflectionHistoryWeight >= 0.0 && reflectionHistoryWeight <= 1.0)) {
					reflectionHistoryWeight = 0.0;
				}

				environmentReflection = mix(
					environmentReflection,
					reflectionHistory.rgb,
					reflectionHistoryWeight);
			#endif

			// The reflection is checked here, before anything is done with it,
			// and not only at the bottom of this pass where the history is
			// checked.
			//
			// Those are two different values and only one of them reaches the
			// screen. The value added to the picture is this one; the value the
			// guard at the bottom of the pass cleans is the one written to
			// colortex9. A non-finite reflection therefore used to be scrubbed
			// out of the history - which is exactly why it never grew and never
			// spread, and so never looked like a buffer gone wrong - while the
			// pixel it belonged to was blacked out on screen, every frame, for
			// as long as the geometry kept producing one. That is what a black
			// blot on a reflective surface that comes and goes with the view
			// angle was. See PBR_PORTING.md 139 for where the NaN came from.
			//
			// Zero rather than something clever. A reflection that cannot be
			// trusted is not a reflection, and adding nothing is the only
			// replacement that cannot make the picture worse.
			if (!(dot(environmentReflection, environmentReflection) < 1.0e18)) {
				environmentReflection = vec3(0.0);
			}

			reflectionResolved = environmentReflection;
			reflectionDistanceStored = reflectionDistance;

			// The debug view, which is the reflection and nothing else: the whole
			// frame is replaced by it, at four times its strength so that the
			// faint reflection a well-behaved surface carries can be seen at all.
			//
			// It exists because the reflection is the one thing in this pack that
			// cannot be judged from the finished picture. A normal map that is
			// wrong looks wrong and a shadow that is wrong looks wrong, but a
			// reflection that is being blurred wrongly and one that is being
			// traced wrongly both come out as "a strange reflection", and no
			// amount of looking at the picture tells them apart. See
			// PBR_DEBUG_REFLECTION in pbr.glsl, and its entry in the lang files.
			#if PBR_DEBUG == PBR_DEBUG_REFLECTION
				resolved = environmentReflection * 4.0;
			#else
				resolved += environmentReflection;
			#endif
		}
	#endif

	// What is about to be written is read back next frame, so this is the last
	// place a value that is not a number can be stopped before it becomes
	// permanent. The reflection itself has been checked above, where it was
	// used; what is left for this one is the pair of things that are written
	// into the history and that nothing above has looked at together.
	//
	// The distance is checked on its own because it is not a colour and the
	// length of the vector says nothing about it: it is stored in the alpha
	// channel, and a distance that came out of the trace as an infinity would
	// otherwise pass straight through on the strength of a perfectly ordinary
	// reflection, be stored as an infinity in an RGBA16F buffer, and be
	// compared against every distance the next frame computes. The comparison
	// itself would then reject the history, which is the right outcome by
	// accident and not by decision.
	if (!(dot(reflectionResolved, reflectionResolved) < 1.0e18)
		|| !(abs(reflectionDistanceStored) < 1.0e18)) {
		reflectionResolved = vec3(0.0);
		reflectionDistanceStored = 1.0e4;
	}

	gl_FragData[0] = vec4(resolved, 1.0);

	// The history is written on every pixel, including the ones with no
	// reflection in them, so that a stale reflection cannot survive under
	// something that has stopped reflecting.
	gl_FragData[1] = vec4(reflectionResolved, reflectionDistanceStored);
}
