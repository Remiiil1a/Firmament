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

// Whether to use a more saturated tonemapping option, from the original
// Uncharted 2 Tonemapping presentation by John Hable.
//
// This is an option rather than a private constant: shaders.properties puts it
// on screen.EFFECTS_COLOR_SETTINGS and its EDIT_DEFAULT profile turns it off with
// "!SATURATED_TONEMAP", lang/en_us.lang gives it a name and a description, and
// the #ifdef below is what selects between the two parameter sets. The #define
// immediately below is commented out, so the default state of this file is the
// else branch; turning the option on makes Iris define the name for the build,
// which is what makes the #ifdef true.
//#define SATURATED_TONEMAP

// Uncharted 2 Tonemap from https://64.github.io/tonemapping/#uncharted-2
vec3 Uncharted2TonemapPartial(vec3 x) {
	#ifdef SATURATED_TONEMAP
		// These are the tonemapping parameters from John Hable's original
		// presentation at GDC:
		//
		// https://www.gdcvault.com/play/1012351/Uncharted-2-HDR
		//
		// Recorded as the reason this branch exists, and not as something the
		// code here shows: the comparison below was made between the two curves
		// at the time, and the claim is that these original parameters give an
		// even steeper start and an even shallower end - in other words, more
		// overall brightness, saturation, and contrast. What the code does show
		// is only which numbers differ: against the blog set below, A is higher
		// (0.22 against 0.15), B is lower (0.30 against 0.50) and E is lower
		// (0.01 against 0.02). C, D and F are identical in both sets.
		//
		// Comparison (green is blog parameters, red is GDC parameters):
		//
		// https://www.desmos.com/calculator/fxjrgjiepm
		const float A = 0.22;
		const float B = 0.30;
		const float C = 0.10;
		const float D = 0.20;
		const float E = 0.01;
		const float F = 0.30;
	#else
		// These are the tonemapping parameters from John Hable's blog post:
		// http://filmicworlds.com/blog/filmic-tonemapping-operators/
		const float A = 0.15;
		const float B = 0.50;
		const float C = 0.10;
		const float D = 0.20;
		const float E = 0.02;
		const float F = 0.30;
	#endif

	return ((x*(A*x+C*B)+D*E)/(x*(A*x+B)+D*F))-E/F;
}

// The same curve with a white point, in the form Uncharted 2 used it.
//
// exposure_bias is a fixed 2.0, so every input is doubled before the curve.
// white_scale is the reciprocal of the curve's own value at W = 11.2 - that is,
// at 11.2 after the bias, which is a scene value of 5.6 - and dividing by it is
// what puts that point at exactly 1.0. Everything the curve reaches after that
// is above 1.0, so the operator is not a clamp: with the blog parameters the
// scene values 8, 11.2 and 20 come out at about 1.07, 1.13 and 1.19, and the
// caller's own clamp is what brings them back. Uncharted2TonemapPartial is
// called twice for exactly this reason - the curve is not normalised on its own.
//
// The two constants are unverifiable from the code: nothing here says why 2.0 or
// 11.2, and both come from the operator as published. Recorded as they stand.
vec3 Uncharted2Tonemap(vec3 v) {
	float exposure_bias = 2.0;
	vec3 curr = Uncharted2TonemapPartial(v * exposure_bias);

	vec3 W = vec3(11.2);
	vec3 white_scale = vec3(1.0) / Uncharted2TonemapPartial(W);
	return curr * white_scale;
}
