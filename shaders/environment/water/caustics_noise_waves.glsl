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

// Slightly tweaked version of surface_noise_waves
// TODO: Either decide to hard split this off, or deduplicate the constants
//
// Read the numbers below as `base * factor`, not as the values written in the
// comments: every tile size is `* (3.0 / 2.0)` and every speed is
// `* (2.0 / 3.0)`, so a comment reading "Tile Dimensions: 3.0 meters x 4.0
// meters" sits above an effective 4.5 x 6.0 meters, and "Speed: 3.0 m/s" above
// an effective 2.0 m/s. The commented figures are the surface_noise_waves
// values these were derived from, and they are still useful as the provenance
// of the base numbers, but they are not the sizes and speeds this file
// produces. The scaling makes the caustics pattern 1.5x the wave pattern in
// space and 2/3 its speed in time.

// Convenience constant to express degree measurements, used in the wave
// definitions file.
#define Degrees radians(1.0)

const CausticNoiseWave CAUSTICS[6] = CausticNoiseWave[](
	CausticNoiseWave (
		// Base tile dimensions: 3.0 meters x 4.0 meters
		// Effective, with the 3/2 factor below: 4.5 meters x 6.0 meters
		vec2(3.0, 4.0) * (3.0 / 2.0),
		// Shear Angle: 30° (Tilt by 60°)
		30.0 * Degrees,
		// Base speed: 3.0 m/s -> effective, with the 2/3 factor: 2.0 m/s
		3.0 * (2.0 / 3.0),
		// Heading: 243° (-X/-Z quadrant)
		//
		// This heading is the exact middle of the 234° and 252° headings used
		// by CAUSTICS[3] and CAUSTICS[2] below, such that those 3 waves all
		// move together and form the primary caustic shape.
		180.0 * Degrees + 63.0 * Degrees,
		0.25,
		6.0
	),
	CausticNoiseWave (
		// Base tile dimensions: 6.0 meters x 8.0 meters
		// Effective: 9.0 meters x 12.0 meters
		//
		// Double the tile size of the previous wave as these are very
		// low frequency waves.
		vec2(6.0, 8.0) * (3.0 / 2.0),
		// Shear Angle: -30° (Tilt by -60°)
		//
		// Opposite direction of the shear for the previous wave.
		-30.0 * Degrees,
		// Base speed: 12.0 m/s -> effective: 8.0 m/s
		//
		// This is fairly fast, but the waves are very low frequency so are
		// fairly subtle. These waves break up and hide some of the tiling
		// patterns in the main caustic wave that are otherwise very obvious.
		12.0 * (2.0 / 3.0),
		// Heading: 252° (-X/-Z quadrant)
		//
		// Same heading as CAUSTICS[2] below
		180.0 * Degrees + 72.0 * Degrees,
		0.15,
		6.0
	),
	CausticNoiseWave (
		// Base tile dimensions: 1.5 meters x 2.0 meters
		// Effective: 2.25 meters x 3.0 meters
		//
		// (Noise this small, exactly this pair of dimensions and the 180+72
		// heading, is what the comment above calls the first ripple wave; the
		// caustics list has no ripple waves, so read those names as provenance
		// from surface_noise_waves rather than as entries in this array.)
		vec2(1.5, 2.0) * (3.0 / 2.0),
		// Shear Angle: 30° (Tilt by 60°)
		30.0 * Degrees,
		// Base speed: 1.5 m/s -> effective: 1.0 m/s
		1.5 * (2.0 / 3.0),
		// Heading: 252° (-X/-Z quadrant)
		180.0 * Degrees + 72.0 * Degrees,
		0.15,
		5.0
	),
	CausticNoiseWave (
		// Base tile dimensions: 1.0 meter x 1.5 meters
		// Effective: 1.5 meters x 2.25 meters
		vec2(1.0, 1.5) * (3.0 / 2.0),
		// Shear Angle: -36° (Tilt by -54°)
		-36.0 * Degrees,
		// Base speed: 3 m/s -> effective: 2 m/s
		3.0 * (2.0 / 3.0),
		// Heading: 234° (-X/-Z quadrant)
		180.0 * Degrees + 54.0 * Degrees,
		0.15,
		5.0
	),
	CausticNoiseWave (
		// Base tile dimensions: 30 cm x 40 cm
		// Effective: 45 cm x 60 cm
		vec2(0.30, 0.40) * (3.0 / 2.0),
		// Shear Angle: 45° (Tilt by 45°)
		45.0 * Degrees,
		// Base speed: 1.5 m/s -> effective: 1.0 m/s
		1.5 * (2.0 / 3.0),
		// Heading: 243°
		//
		// Marked as overridden: this is not the heading the comparable entry in
		// surface_noise_waves uses, and nothing in this file computes it - the
		// literal below is the only source of it.
		180.0 * Degrees + 63.0 * Degrees,
		0.15,
		1.25
	),
	CausticNoiseWave (
		// Base tile dimensions: 15 cm x 20 cm
		// Effective: 22.5 cm x 30 cm
		vec2(0.15, 0.20) * (3.0 / 2.0),
		// Shear Angle: -45° (Tilt by -45°)
		-45.0 * Degrees,
		// Base speed: 0.5 m/s -> effective: 1/3 m/s
		0.5 * (2.0 / 3.0),
		// Heading: 234°
		//
		// Marked as overridden, same as the entry above.
		180.0 * Degrees + 54.0 * Degrees,
		0.15,
		1.25
	)
);
