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

// Modified 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

// Modified from /shaders/distort.glsl in
// https://github.com/shaderLABS/Shadow-Tutorial

// Distortion factor for the shadow map.
//
// In the code below it is added to the length of the position's xy, so it is a
// floor on the radius the shadow-space xy is divided by: at 0.20 a position
// inside 0.20 of the shadow map's centre is pushed outwards, which is what buys
// resolution near the player at the cost of it far away. Lower values mean
// higher quality near the player and lower quality far away.
//
// Note that a value of 0.00 is not "off" and nothing here is conditional on it:
// the division still happens, and with a factor of zero the radius of a position
// at the exact centre of the map is zero too. What decides whether the sampling
// position goes through this at all is where the call site sits - see
// ShadowMapPosition in lit.vsh and the same transform in shadow.vsh. The option
// is also the fixed part of the shadow bias; see its own description in
// lang/en_us.lang, which describes that side of it rather than this one.
#define SHADOW_DISTORT_FACTOR 0.20 // [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.60 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.70 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.80 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.90 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.00]

// Pushes a shadow-space position outwards from the centre of the map, so that
// the texels near the player cover less world. The same function is applied
// where the map is written (shadow.vsh) and where it is read (lit.vsh through
// ShadowMapPosition), which is what keeps the two samplings at the same place -
// changing it here changes both.
//
// At this point in the file pos is in the (-1, 1) cube of shadow clip space, and
// z is halved on the way out; the callers do the * 0.5 + 0.5 that follows.
vec3 distort(vec3 pos) {
	float factor = length(pos.xy) + SHADOW_DISTORT_FACTOR;
	return vec3(pos.xy / factor, pos.z * 0.5);
}
