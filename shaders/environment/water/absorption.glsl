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

// Perceptual appearance of water.
#define WATER_CHARACTER BALANCED // [CLEAR BALANCED TROPICAL COLD]

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

