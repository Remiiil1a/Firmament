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

// https://github.com/dmnsgn/glsl-tone-map/blob/main/uchimura.glsl
// Tweaks are in the form of comments
// This is the old Uchimura / "GT" filmic tonemap.
//
// uchimura() below is the curve itself, blended from three pieces and weighted
// per channel by which piece the input falls in:
//
//  - the toe, T, from 0 to m;
//  - the linear section, L, from m to m + l0;
//  - the shoulder, S, which takes over above m + l0 and approaches P.
//
// The weights are mutually exclusive and add to one (w1 is written as 1 - w0 -
// w2), so exactly one piece is selected at a time and the whole thing is
// continuous. Note that w1 goes *negative* above m + l0 once L has crossed
// above 1.0 - that is what keeps the sum at one, and it is why L cannot simply
// be added unconditionally.
//
// The parameter names are the upstream ones and are not self-describing: l0
// below is the input width of the linear section (the l argument times the
// distance from the start of the linear section to P), not the linear section
// length, and the two L names below are the output values of the toe and the
// linear section at the join points.
//
// The file carries a URL, a note about tweaks, and the upstream MIT notice.
// Those are recorded as they were: the notice is Damien Seguin's, and the "old
// Uchimura" label is prose about which formulation this is, not something in
// the code.

// Copyright (C) 2019 Damien Seguin
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

// vec3 uchimura(vec3 x, float P, float a, float m, float l, float c, float b) {
vec3 uchimura(vec3 x, float P, float a, float m, float l, float c, float b) {
	// l0 has nothing to do with L0 two lines below it: GLSL is case sensitive,
	// and the two are different names. (They are the input width of the linear
	// section and the output value of the toe at m respectively, which is a
	// coincidence of naming rather than a collision.)
	float l0 = ((P - m) * l) / a;
	float L0 = m - m / a;
	float L1 = m + (1.0 - m) / a;
	float S0 = m + l0;
	float S1 = m + a * l0;
	float C2 = (a * P) / (P - S1);
	float CP = -C2 / P;

	// w0 is the toe's weight, w2 the shoulder's, and w1 whatever is left over
	// for the linear section. smoothstep takes w0 from 1 at x = 0 down to 0 at
	// x = m, and step switches w2 on at exactly m + l0, so the three weights are
	// 1 / 0 / 0 below m, 0 / 1 / 0 in the middle and 0 / 0 / 1 at and above
	// m + l0, and nowhere can two of them overlap.
	vec3 w0 = vec3(1.0 - smoothstep(0.0, m, x));
	vec3 w2 = vec3(step(m + l0, x));
	vec3 w1 = vec3(1.0 - w0 - w2);

	vec3 T = vec3(m * pow(x / m, vec3(c)) + b);
	vec3 S = vec3(P - (P - S1) * exp(CP * (x - S0)));
	vec3 L = vec3(m + a * (x - m));

	return T * w0 + L * w1 + S * w2;
}

// The same curve with this pack's own constants, and the only caller of
// uchimura() in this file - uchimura() is not referenced anywhere else in the
// pack. UchimuraTonemap itself is called from exactly two places: DisplayValue
// in composite4.fsh, whose argument is clamped to [0.0, 1.0e18] before this
// sees it, and postprocessing.fsh, which does not clamp and relies on colortex0
// being an unsigned format so that its texels cannot be negative. The curve
// needs a non-negative input: its toe is a pow().
//
// At these values the pieces simplify more than the general form suggests.
// With a = 1.0 two of the named constants collapse: L0 comes out at 0.0, so
// the linear section is just x, and S1 equals S0, so the shoulder's C2 reduces
// to P / (P - S1). The three pieces are therefore m * pow(x / m, c) + b below
// m = 0.22, the straight x through the middle, and
// P - (P - S1) * exp(CP * (x - S0)) above m + l0 = 0.61, with the weights
// picking between them. P is the value the shoulder converges to as x grows;
// the value written here is 1.0, and the result is clamped to 1.0 by the caller
// before it reaches the display.
//
// The two constants that differ from the upstream defaults are l (0.5 rather
// than 0.4) and c (1.0 rather than 1.33); the alternatives are kept as comments
// on the lines below, which is how this file records its tweaks.
vec3 UchimuraTonemap(vec3 x) {
	const float P = 1.0;	// max display brightness
	const float a = 1.0;	// contrast
	const float m = 0.22; // linear section start
	//const float l = 0.4;	// linear section length
	const float l = 0.5;	// linear section length
	//const float c = 1.33; // black
	const float c = 1.0; // black
	const float b = 0.0;	// pedestal

	return uchimura(x, P, a, m, l, c, b);
}
