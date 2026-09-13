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

// Quick approximation for water absorption based on a linear 
// depth value from 0.0 to 1.0 (1.0 = deepest, 0.0 = no water)
vec3 WaterAbsorption(float depth) {
	// Tweaking these factors allows you to change the "character" of
	// the water pretty heavily. It would be pretty cool to bake this
	// into the vertex color and make it biome dependent, but vertex
	// attributes do not grow on trees...
	#define COLD -vec3(16, 5, 1)
	#define BALANCED -vec3(16, 3, 1)
	#define TROPICAL -vec3(32, 2, 0.5)
	// Perceptual appearance of water. 
	#define WATER_CHARACTER BALANCED // [COLD BALANCED TROPICAL]
	// Additional brightness reduction of underwater...
	// 1.0 = no reduction, 0.0 = full reduction.
	#define DARK_UNDERWATER 1.0 // [0.33 0.5 0.66 0.75 0.8 1.0]

	return exp(depth * WATER_CHARACTER) * (depth > 0.0 ? DARK_UNDERWATER : 1.0);
}
