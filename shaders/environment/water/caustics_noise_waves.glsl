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

// Convenience constant to express degree measurements, used in the wave
// definitions file.
#define Degrees radians(1.0)

const CausticNoiseWave CAUSTICS[6] = CausticNoiseWave[](
	CausticNoiseWave (
		// Tile Dimensions: 3.0 meters x 4.0 meters
		vec2(3.0, 4.0) * (3.0 / 2.0),
		// Shear Angle: 30° (Tilt by 60°)
		30.0 * Degrees,
		// Speed: 3.0 m/s
		3.0 * (2.0 / 3.0),
		// Heading: 243° (-X/-Z quadrant)
		//
		// This heading is the exact middle between the two large ripple waves,
		// such these 3 waves all move together and form the primary wave shape.
		180.0 * Degrees + 63.0 * Degrees,
		0.25,
		6.0
	),
	CausticNoiseWave (
		// Tile Dimensions: 6.0 meters x 8.0 meters
		//
		// Double the tile size of the previous wave as these are very
		// low frequency waves.
		vec2(6.0, 8.0) * (3.0 / 2.0),
		// Shear Angle: -30° (Tilt by -60°)
		//
		// Opposite direction of the shear for the previous wave.
		-30.0 * Degrees,
		// Speed: 12.0 m/s
		// 
		// This is fairly fast, but the waves are very low frequency so are 
		// fairly subtle. These waves break up and hide some of the tiling
		// patterns in the main crest wave that are otherwise very obvious.
		12.0 * (2.0 / 3.0),
		// Heading: 252° (-X/-Z quadrant)
		//
		// Same as the first ripple wave
		180.0 * Degrees + 72.0 * Degrees,
		0.15,
		6.0
	),
	CausticNoiseWave (
		// Tile Dimensions: 1.5 meters x 4 meters
		vec2(1.5, 2.0) * (3.0 / 2.0),
		// Shear Angle: 30° (Tilt by 60°)
		30.0 * Degrees,
		// Speed: 1.5 m/s
		1.5 * (2.0 / 3.0),
		// Heading: 252° (-X/-Z quadrant)
		180.0 * Degrees + 72.0 * Degrees,
		0.15,
		5.0
	),
	CausticNoiseWave (
		// Tile Dimensions: 1 meter x 1.5 meters
		vec2(1.0, 1.5) * (3.0 / 2.0),
		// Shear Angle: -36° (Tilt by -54°)
		-36.0 * Degrees,
		// Speed: 3 m/s
		3.0 * (2.0 / 3.0),
		// Heading: 234° (-X/-Z quadrant)
		180.0 * Degrees + 54.0 * Degrees,
		0.15,
		5.0
	),
	CausticNoiseWave (
		// Tile Dimensions: 30 cm x 40 cm
		vec2(0.30, 0.40) * (3.0 / 2.0),
		// Shear Angle: 45° (Tilt by 45°)
		45.0 * Degrees,
		// Speed: 1.5 m/s
		1.5 * (2.0 / 3.0),
		// Note: Overridden
		180.0 * Degrees + 63.0 * Degrees,
		0.15,
		1.25
	),
	CausticNoiseWave (
		// Tile Dimensions: 15 cm x 20 cm
		vec2(0.15, 0.20) * (3.0 / 2.0),
		// Shear Angle: -45° (Tilt by -45°)
		-45.0 * Degrees,
		// Speed: 0.5 m/s
		0.5 * (2.0 / 3.0),
		// Note: Overridden
		180.0 * Degrees + 54.0 * Degrees,
		0.15,
		1.25
	)
);
