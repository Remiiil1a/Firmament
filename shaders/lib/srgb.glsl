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

// Standard approximations for converting to and from sRGB.
//
// What the four functions below actually compute is a plain power curve with an
// exponent of 2.2, not the piecewise sRGB transfer function (which is linear
// near black and 2.4 above it). sRGB_GAMMA is 2.2 and that is the only thing
// they use, so the encode and decode are exact inverses of one another.
//
// The input is a value in 0 to 1, not a byte: SrgbToLinear(1.0) is 1.0 and
// SrgbToLinear(0.0) is 0.0. Nothing here clamps, and a negative input to pow()
// is undefined in GLSL, so a caller with a value that could be negative has to
// clamp it first - see the note in DisplayValue in composite4.fsh for what that
// cost before it was clamped.
//
// The vec4 overloads convert rgb and pass alpha through untouched, which is what
// lets them be used on a colour straight out of a texture fetch.
//
// See http://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
// for more information. We can do better but 2.2 is good enough.

const float SRGB_GAMMA = 2.2;

vec3 SrgbToLinear(vec3 srgb) {
	return pow(srgb, vec3(SRGB_GAMMA));
}

vec3 LinearToSrgb(vec3 linear) {
	return pow(linear, vec3(1.0 / SRGB_GAMMA));
}

vec4 SrgbToLinear(vec4 srgb) {
	return vec4(pow(srgb.rgb, vec3(SRGB_GAMMA)), srgb.a);
}

vec4 LinearToSrgb(vec4 linear) {
	return vec4(pow(linear.rgb, vec3(1.0 / SRGB_GAMMA)), linear.a);
}
