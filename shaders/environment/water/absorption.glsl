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

// The attenuation coefficients are in reciprocal metres: the factor for a path
// through water is exp(coefficients * metres), which is Beer's law. Batch 671
// moved them out of the function below and into these units, which is what
// lets the surface path measure the distance the light actually travelled
// instead of a normalised depth (upstream Steadfast 0.9.0 did the same).
//
// CLEAR is the measured set: Pope & Fry 1997, at 680/550/440 nm, converted
// from 1/cm to 1/m - which is why its numbers sit two orders from the others.
//
// BALANCED is a stylised set with 0.10/m of scattering folded into it. That
// scattering deliberately does not follow the water's own scattering settings:
// turning the scattering up should not also change the water's colour.
//
// TROPICAL is where the old default lands once it is converted. The old
// BALANCED was -vec3(16, 3, 1) per unit of normalised depth, and one unit is
// sixteen metres (see NORMALISED_DEPTH_METERS), so it is -vec3(1.0, 0.1875,
// 0.0625) per metre. Choosing it reproduces the water this pack had before
// batch 671, for the two normalised callers as well.
//
// COLD is kept in the list so that a saved configuration naming it still
// works. It is the old -vec3(16, 5, 1), converted the same way.
#define CLEAR -vec3(0.465, 0.0565, 0.00635)
#define BALANCED -vec3(0.35, 0.18, 0.10)
#define TROPICAL -vec3(1.0, 0.1875, 0.0625)
#define COLD -vec3(1.0, 0.3125, 0.0625)

// A water colour of one's own (batch 716), in the form upstream Steadfast 0.9.0 uses
// in its own absorption settings: each channel is a coefficient between 0 and 1 times
// a magnitude, and the minus that makes the set negative is applied once, below.
//
// The magnitude exists because the coefficients span the range from a puddle to the
// open sea - CLEAR's blue is 0.00635/m, TROPICAL's red is 1.0/m - and one slider
// cannot be useful across that. The three channels get one each, because blue has to
// be able to sit two orders below red (see CLEAR).
//
// The defaults are BALANCED exactly - 0.35, 0.18, 0.10 at magnitude 1.0 - so that
// selecting CUSTOM changes nothing until one of the six is moved, and so that this
// preset cannot become a second, silently different "balanced" water.
#define CUSTOM_WATER_ABSORPTION_R 0.35 // [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.60 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.70 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.80 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.90 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.00]
#define CUSTOM_WATER_ABSORPTION_G 0.18 // [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.60 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.70 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.80 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.90 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.00]
#define CUSTOM_WATER_ABSORPTION_B 0.10 // [0.00 0.01 0.02 0.03 0.04 0.05 0.06 0.07 0.08 0.09 0.10 0.11 0.12 0.13 0.14 0.15 0.16 0.17 0.18 0.19 0.20 0.21 0.22 0.23 0.24 0.25 0.26 0.27 0.28 0.29 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40 0.41 0.42 0.43 0.44 0.45 0.46 0.47 0.48 0.49 0.50 0.51 0.52 0.53 0.54 0.55 0.56 0.57 0.58 0.59 0.60 0.61 0.62 0.63 0.64 0.65 0.66 0.67 0.68 0.69 0.70 0.71 0.72 0.73 0.74 0.75 0.76 0.77 0.78 0.79 0.80 0.81 0.82 0.83 0.84 0.85 0.86 0.87 0.88 0.89 0.90 0.91 0.92 0.93 0.94 0.95 0.96 0.97 0.98 0.99 1.00]
#define CUSTOM_WATER_ABSORPTION_R_MAGNITUDE 1.0 // [0.0001 0.001 0.01 0.1 1.0 10.0 100.0 1000.0]
#define CUSTOM_WATER_ABSORPTION_G_MAGNITUDE 1.0 // [0.0001 0.001 0.01 0.1 1.0 10.0 100.0 1000.0]
#define CUSTOM_WATER_ABSORPTION_B_MAGNITUDE 1.0 // [0.0001 0.001 0.01 0.1 1.0 10.0 100.0 1000.0]

#define CUSTOM -vec3(CUSTOM_WATER_ABSORPTION_R * CUSTOM_WATER_ABSORPTION_R_MAGNITUDE, CUSTOM_WATER_ABSORPTION_G * CUSTOM_WATER_ABSORPTION_G_MAGNITUDE, CUSTOM_WATER_ABSORPTION_B * CUSTOM_WATER_ABSORPTION_B_MAGNITUDE)

// Perceptual appearance of water.
// CUSTOM is the sixth value and not a fourth preset: it is the six options above.
// It is listed last so that a saved configuration naming one of the four presets
// keeps the meaning it had.
#define WATER_CHARACTER BALANCED // [CLEAR BALANCED TROPICAL COLD CUSTOM]

#define WATER_ATTENUATION_COEFFICIENTS WATER_CHARACTER

// What a normalised depth of 1.0 is worth in metres.
//
// One caller still hands over a normalised 0..1 depth - the water medium in
// program/post/volumetric_fog.fsh - and it was tuned against that scale, reaching
// full attenuation about fifteen blocks down. One unit is therefore sixteen
// metres, which is also what makes the old and the new numbers agree exactly for
// TROPICAL: exp(-vec3(16, 3, 1) * depth) and exp(-vec3(1.0, 0.1875, 0.0625) * 16 *
// depth) are the same expression.
//
// It had a second caller until batch 711: environment/lighting/diffuse.glsl, which
// multiplied each lit fragment's own light by this, and program/post/copy_and_fog.fsh,
// which multiplied the whole frame. Both are gone - see the note at the bottom of
// this file.
#define NORMALISED_DEPTH_METERS 16.0

// Additional brightness reduction of underwater...
// 1.0 = no reduction, 0.0 = full reduction.
// This is a plain scale factor on the exponential, reached only when there is
// water in the path at all, so at the surface it does nothing.
#define DARK_UNDERWATER 1.0 // [0.33 0.5 0.66 0.75 0.8 1.0]

// Beer's law over a path length in metres.
vec3 WaterAttenuation(float meters) {
	return exp(meters * WATER_ATTENUATION_COEFFICIENTS)
		* (meters > 0.0 ? DARK_UNDERWATER : 1.0);
}

// The same thing for the one caller that still hands over a normalised depth.
//
// KEPT rather than converted on purpose: that curve is the water medium, tuned by
// eye in this form, and it is not what batch 671 set out to change. It does follow
// WATER_CHARACTER, through the shared coefficients - which is why choosing TROPICAL
// restores exactly what it did before.
vec3 WaterAbsorption(float depth) {
	return WaterAttenuation(depth * NORMALISED_DEPTH_METERS);
}

// WHERE WATER ABSORPTION IS APPLIED, and why there is only one place (batch 711).
//
// Upstream Steadfast applied it twice over: once inside each lit fragment's shading
// (environment/lighting/diffuse.glsl, from the fragment's own sky light) and once to
// the whole frame in program/post/copy_and_fog.fsh. Both wanted a water depth, and
// both took it from the fragment's sky light - which is a real reading only where
// the fragment is world geometry. An entity or the hand writes the light the game
// gives that model, which under the surface has no sky component at all, so those
// fragments were read as sixteen metres down and multiplied into the colour of the
// water behind them. That is the "see-through" the author reported at b677 and that
// b678, b679 and b681 each tried to repair in one of the two copies.
//
// Batch 711 deleted both instead of repairing a third. What is left is the water
// medium in program/post/volumetric_fog.fsh: it attenuates per step of the view ray
// (WaterAbsorption(stepLength / 16)), composite1 multiplies that transmittance into
// the finished frame, and it is applied to everything drawn by then - models
// included - with no light map anywhere in the path. Its cost is the tier that runs
// without the volumetric fog: there nothing absorbs water, and the water's own colour
// in that case comes from the fog colour and WATER_CHARACTER, which is the trade this
// batch took rather than a second copy of the same physics.

