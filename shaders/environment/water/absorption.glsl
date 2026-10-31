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
// Two callers still hand over a normalised 0..1 depth - the underwater light in
// environment/lighting/diffuse.glsl and the water medium in
// program/post/volumetric_fog.fsh - and both were tuned against that scale,
// each reaching full attenuation about fifteen blocks down. One unit is
// therefore sixteen metres, which is also what makes the old and the new
// numbers agree exactly for TROPICAL: exp(-vec3(16, 3, 1) * depth) and
// exp(-vec3(1.0, 0.1875, 0.0625) * 16 * depth) are the same expression.
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

// The same thing for the two callers that still hand over a normalised depth.
//
// KEPT rather than converted on purpose: those two curves are the underwater
// light and the water medium, both tuned by eye in this form, and they are not
// what batch 671 set out to change. They do follow WATER_CHARACTER, through
// the shared coefficients - which is why choosing TROPICAL restores exactly
// what they did before.
vec3 WaterAbsorption(float depth) {
	return WaterAttenuation(depth * NORMALISED_DEPTH_METERS);
}
