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

// Added 2026-09-25 by Remiiil1a for Firmament - screen-space bloom.
// See PBR_PORTING.md 166.

// Bloom: the glow that spills out of anything brighter than the screen can
// show.
//
// A lens does this, and so does an eye. Light bright enough to saturate a pixel
// does not stop at the edge of the thing giving it off - it scatters inside the
// glass and lands on the pixels around it, which is why a torch seen at night
// has a halo rather than a hard outline. This is the screen-space imitation of
// that: take the parts of the frame that are brighter than white, blur them, and
// add the result back.
//
// It is built from colortex0 and added in final.fsh, before the tonemap, and
// both halves of that matter:
//
//   * The input is the linear HDR frame, not the tonemapped one. "Brighter than
//     white" only means anything before the curve: after the tonemap has run,
//     everything above white has already been squashed flat and there is nothing
//     left to find. It also means the blur averages light, which is what a
//     weighted average of pixels is.
//
//   * The result is added to the light rather than mixed into the finished
//     value, so a bright pixel spills onto its neighbours without those
//     neighbours losing their own color.
//
// What it deliberately does not do:
//
//   * The godrays, the motion blur and the vignette are all added in final.fsh,
//     after the bloom buffer has been built, so none of them feeds back into the
//     glow: a shaft of light crossing the screen does not brighten what it
//     crosses.
//   * Nothing is carried across frames. Each frame's bloom is built from that
//     frame alone, so it cannot smear or accumulate.
//
// Cost: four passes at half and quarter resolution, plus two fetches in
// final.fsh. Each buffer is smaller than the frame by the square of its scale,
// so the whole chain is roughly two full-resolution passes' worth of texture
// bandwidth. Turning BLOOM off skips all four passes as well as the two
// fetches.

// Whether to draw the bloom at all.
//
// The four passes that build it are skipped whole when this is off - see
// program.composite7 through program.composite10 in shaders.properties - and
// final.fsh then adds nothing.
#define BLOOM

// How much of the blurred light is added back.
//
// This is the option that decides whether the effect reads as "the bright
// things have a glow around them" or as "someone smeared vaseline on the lens".
// It scales the sum of both bloom levels, so it is the only strength control
// there is.
#define BLOOM_STRENGTH 0.35 // [0.0 0.05 0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5 0.6 0.75 1.0 1.5 2.0]

// How bright a pixel has to be before any of it blooms.
//
// The frame is in linear light with 1.0 at white, so a pixel below 1.0 is
// simply not bright enough to have spilled anywhere. Lowering this starts
// pulling ordinary lit surfaces into the glow, which thickens the effect but
// washes the contrast out; raising it picks out only the genuinely overexposed
// things - the sun, lava, a torch flame.
//
// The fade is a soft knee rather than a hard cut. A hard cut puts a visible
// edge on every bright surface: pixels just above the threshold bloom and their
// neighbours just below do not, and what that looks like is a second copy of
// the object's outline offset by the blur radius.
#define BLOOM_THRESHOLD 0.0 // [0.0 0.25 0.5 0.75 1.0 1.25 1.5 2.0 3.0 5.0]

// Whether the specular highlight on a surface is left out of the glow.
//
// On by default, and this is what keeps the effect believable rather than
// merely strong: a highlight is a picture of a light and not a light. The sun
// that makes it is somewhere else entirely, and its reflection on a polished
// floor does not light the room. Bloom it anyway and a shiny surface ends up
// looking like a lamp of its own, which is what a highlight glowing in the
// first place looks like.
//
// The cost is one more buffer for the terrain shaders to write - see
// colortex15 in /program/world/lit.fsh - and one more fetch per tap in the
// pass that keeps the bright parts. Turning this off skips those fetches and
// nothing else: the buffer is written either way, for the reason the note on
// the buffer gives.
//
// What it does not cover: water, ice and glass take their reflection from
// TranslucentLighting rather than from the surface lighting, so a highlight on
// those still blooms. That is a deliberate stopping point rather than an
// oversight - it is the sun glinting off water, which is the one specular
// highlight a camera really does bloom.
#define BLOOM_EXCLUDE_SPECULAR

// How far the glow spreads, as a multiple of the blur's own width.
//
// That width is about thirteen pixels at 1080p before this is applied. Raising
// this widens the halo and costs nothing extra: the tap count, not the radius,
// is what the passes pay for.
#define BLOOM_RADIUS 1.0 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0]

// The weights the two levels are mixed with before being added to the frame.
//
// Two levels rather than one, because a single blur cannot be both tight and
// wide: a narrow one leaves the glow glued to the object, and a wide one loses
// the bright core and turns the screen into a haze. The half-resolution level
// supplies the tight part, and the quarter-resolution one, which is blurred
// twice, supplies the spread.
//
// These are constants rather than options on purpose. The ratio between them is
// what makes the result read as a halo rather than a smear, and it is not
// something a player has any way to judge from inside the game - whereas the
// total, which BLOOM_STRENGTH sets, is immediately visible.
const float BLOOM_TIGHT_WEIGHT = 0.35;
const float BLOOM_WIDE_WEIGHT = 0.65;

// How much of a pixel blooms: 0 for "not at all", 1 for "all of it".
//
// The knee is half the threshold, so the fade starts that far below it and
// reaches full contribution at the threshold itself. Both branches of the max
// are needed - the first is the soft part of the ramp, the second takes over
// once the pixel is bright enough for the fade to have finished.
float BloomContribution(vec3 color, float threshold) {
	// The strongest channel rather than the weighted average the rest of the
	// pack uses to judge brightness. The question here is not "how much light
	// does this pixel carry" but "is the display about to fail to show it", and
	// a display fails one channel at a time: soul fire is nearly pure blue, and
	// its luminance is a fourteenth of its blue channel, so judging it by
	// luminance would leave one of the few saturated lights in the game with no
	// halo at all while a white cloud of the same brightness got one.
	float brightness = max(max(color.r, color.g), color.b);

	// A threshold of zero would otherwise divide by zero below. It is a legal
	// setting - it means "bloom everything" - so the floor has to be here
	// rather than in the option's list.
	float knee = max(threshold * 0.5, 1.0e-5);

	float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
	soft = soft * soft / (4.0 * knee);

	return max(soft, brightness - threshold) / max(brightness, 1.0e-5);
}

// A separable nine-tap Gaussian, taken five times.
//
// The four outer taps of a nine-tap kernel are paired up and each pair is read
// with one fetch halfway between its two texels, which is what the bilinear
// filter gives away for free - so this costs five fetches and a couple of
// multiplies instead of nine fetches. The weights are the ones that pairing
// produces and they sum to one.
//
// The samples are clamped into the frame rather than allowed to run off it: a
// buffer read outside its own range wraps, and what that would do here is drag
// the opposite edge's pixels into the glow along the border.
//
// There is no guard for a non-finite value in here, and that is not an
// oversight. The only thing this ever samples is colortex12 and colortex13,
// and the only thing that writes those is the pass that reads colortex0 - a
// buffer in R11F_G11F_B10F, which is an unsigned packed float with no exponent
// of its own and cannot hold a NaN, an infinity or a negative in the first
// place. A blur is the worst possible place for one of those to appear, since
// it would spread it over the whole screen rather than leaving it where it was,
// so it is worth knowing that the format is what rules it out.
vec3 BloomBlur(sampler2D source, vec2 screenCoord, vec2 direction, vec2 texelSize) {
	vec2 first = direction * texelSize * 1.3846153846;
	vec2 second = direction * texelSize * 3.2307692308;

	vec3 color = textureLod(source, screenCoord, 0.0).rgb * 0.2270270270;
	color += textureLod(source, clamp(screenCoord + first, vec2(0.0), vec2(1.0)), 0.0).rgb * 0.3162162162;
	color += textureLod(source, clamp(screenCoord - first, vec2(0.0), vec2(1.0)), 0.0).rgb * 0.3162162162;
	color += textureLod(source, clamp(screenCoord + second, vec2(0.0), vec2(1.0)), 0.0).rgb * 0.0702702703;
	color += textureLod(source, clamp(screenCoord - second, vec2(0.0), vec2(1.0)), 0.0).rgb * 0.0702702703;

	return color;
}
