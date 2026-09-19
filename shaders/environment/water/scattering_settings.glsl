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

// Added 2026-09-19 by Remiiil1a for Firmament - v0.4 (edit of coderbot's Steadfast).

// Light scattered back out of a body of water, which is the other half of what
// water does to light.
//
// Absorption alone - what this pack had until now - can only ever take colour
// away: light travels into the water, is attenuated by depth, and what comes
// back out is whatever survived. That produces the deep blue-green of water
// seen from above, but it cannot produce the glow a lit volume of water has,
// because it has nothing to add. Scattering is the part that comes back off
// the water's own particles instead of off the bottom, and it is what makes
// deep water bright rather than merely dark.
//
// It is added where the refracted background is read, so it lands on water seen
// through a surface - which is where a body of water is read as a body rather
// than as a sheet of glass.
//
// Zero by default, and that is deliberate: with both values at 0.0 the term
// this adds is exactly vec3(0.0), so a pack that has never raised them renders
// the water it always did. Turning it up is a change to the water's colour, so
// it is a choice rather than a default.

// How much of the effect to add. This is the depth-independent half of it: the
// rate below is this multiplied by the magnitude.
#define WATER_SCATTER 0.00 // [0.00 0.25 0.50 0.75 1.00]

// The same effect's scale, kept apart so that the slider above can stay in the
// range a person thinks in while the actual rate stays tunable.
#define WATER_SCATTER_MAGNITUDE 1.00 // [0.25 0.50 1.00 2.00 4.00]

// How fast the added light builds up with depth. The effect approaches its
// maximum as 1 - exp(-rate * depth), so a larger rate saturates nearer to the
// surface. Negative, as written, so that the exponential above decays.
#define WATER_SCATTER_BY_DEPTH (-WATER_SCATTER * WATER_SCATTER_MAGNITUDE)

// The colour the addition heads towards. These are weights rather than a colour
// in its own right: they are normalised below, so raising the luminance
// brightens the addition without shifting its hue.
#define WATER_SCATTER_COLOR_R 0.35
#define WATER_SCATTER_COLOR_G 0.75
#define WATER_SCATTER_COLOR_B 0.55

// How bright the addition is at full depth under a full sky. Zero leaves it
// switched off whatever the sliders above say.
#define WATER_SCATTER_LUMINANCE 0.50 // [0.00 0.25 0.50 1.00 2.00]

// The luminance of the weights, so that normalising by it leaves the colour
// where it was and only the brightness changed. Rec. 709 coefficients, the same
// ones the rest of the pack uses.
const float waterScatterColorLuminance = 0.2126 * WATER_SCATTER_COLOR_R
	+ 0.7152 * WATER_SCATTER_COLOR_G
	+ 0.0722 * WATER_SCATTER_COLOR_B;

const vec3 waterScattering = vec3(
	WATER_SCATTER_COLOR_R,
	WATER_SCATTER_COLOR_G,
	WATER_SCATTER_COLOR_B)
	* (WATER_SCATTER_LUMINANCE / waterScatterColorLuminance);
