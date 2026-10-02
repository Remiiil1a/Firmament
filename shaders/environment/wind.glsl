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

// Straightforward & fast but visually appealing displacement implementation.
// Utilizes custom uniforms defined in shaders.properties.
//
// worldPos is genuinely world space, not camera-relative: the one caller adds
// cameraPosition to its camera-relative position before calling this (lit.vsh,
// in WaveFoliage). That is load-bearing - the phases below are taken from the
// position, so a camera-relative argument would drag the patches along with the
// camera instead of leaving them fixed in the world.
uniform float windStrengthHalf;
uniform vec4 windTheta;

vec3 WindDisplacement(vec3 worldPos) {
	// Wind magnitude is given by a sine wave with a positional phase shift.
	// In other words, it cycles between 0 and twice windStrengthHalf - which is
	// what the name says, the uniform being half the peak - and varies with the
	// block position, but in a continuous manner such that wind appears to move
	// in patches.
	//
	// The phase it varies with is worldPos.y + worldPos.z, so it does not vary
	// with x at all: two blocks at the same height and the same z move together
	// however far apart they are along x.
	float magnitude = sin(windTheta.w + worldPos.y + worldPos.z)
		* windStrengthHalf + windStrengthHalf;

	// Wind direction is given by a sine wave for each axis. Similarly, we shift
	// the phase based on position. In the vertical direction (y), we halve the
	// phase shift, as wind is horizontal, and making columns of leaves appear
	// to move as a more continuous unit makes the wind more convincing.
	//
	// The phase is the same (worldPos.x + worldPos.z) for all three axes; the
	// vec2 below is (scale for x and z, scale for y), and it is read as
	// windPhaseShift.xyx.
	vec2 windPhaseShift = (worldPos.x + worldPos.z) * vec2(1.5, 0.75);

	// Finally, compute the displacement vector as magnitude times direction.
	// The direction is given by 3 sine waves with a position-dependent phase
	// shift.
	//
	// To similarly make wind appear horizontal, the vertical magnitude is
	// halved.
	vec3 direction = sin(windTheta.xyz + windPhaseShift.xyx);
	return vec3(magnitude, magnitude * 0.5, magnitude) * direction;
}
