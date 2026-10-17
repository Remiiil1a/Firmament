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

// The eye's position, which WaveFoliage below adds to a camera-relative position to
// get the world position the phases are taken from.
//
// ⚠️ Under a guard of its own (batch 587). lit.vsh used to declare it for the
// world's own reasons and the shadow pass now needs it as well, so the declaration
// lives here and both callers take it from here - one name, one place, and no
// program declaring it twice.
#if !defined(CAMERA_POSITION_DECLARED)
	#define CAMERA_POSITION_DECLARED
	uniform vec3 cameraPosition;
#endif

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

// Which blocks wave, and by how much. Moved here from lit.vsh in batch 587, because
// the shadow pass now needs it too and a second copy of this would be a second place
// for the two to drift apart - which is the defect being fixed, not a tidy-up.
//
// ⚠️ WHY THE SHADOW PASS NEEDS IT (batch 587). Until then the shadow map held the
// leaves AT REST while lit.vsh drew them MOVING, and lit.vsh built the lookup from
// the pre-wave position as well. So three things disagreed at once: the occluder in
// the map, the geometry on screen, and the coordinate the shadow was asked about. A
// leaf's own lit/shadowed pattern therefore slid across its surface by the whole
// displacement, every frame, at the wind's frequency - and a leaf is built of
// features one to six shadow texels across, so a slide of one or two texels moves
// the boundary across part of it every frame. That is the author's "crawling
// through leaves", and it is the only difference found in either pack that is
// leaf-specific AND per-frame by construction.
//
// ⚠️ Both callers must pass a position in the same space: camera-relative, which
// carries the same axes as the world because both view matrices are built from the
// player's yaw and pitch alone. The phases are taken from the position, so a caller
// that passed one relative to a different origin would drag the patches along with
// it - see the note on WindDisplacement above.
//
// ⚠️ A no-op on every material but leaves and the tops of ground foliage, so both
// callers can call it unconditionally and only the waving geometry pays.
void WaveFoliage(uint materialID, inout vec4 cameraRelativePos) {
	// at_midBlock.xyz is the offset from this vertex to the centre of its block in
	// 1/64 block units - not in blocks, and not the distance in blocks. The attribute
	// the loader supplies is a vec4 whose w is the block's own light level (Iris 1.7
	// and later); the declarations take only the xyz, so that component is not
	// readable here and nothing here wants it. Read these numbers as 1/64-block
	// offsets and the test below is "is this vertex at the top of its block's
	// column".
	//
	// So if these are the top vertices, then the offset to the center will be
	// negative as the center is below these vertices.
	bool topOfFoliage = at_midBlock.y < 0.0;
	bool wavingGroundFoliage = materialID == GROUND_FOLIAGE;
	bool wavingLeaves = materialID == LEAVES;

	if (wavingLeaves || (wavingGroundFoliage && topOfFoliage)) {
		vec3 worldPos = cameraRelativePos.xyz + cameraPosition;
		vec3 displacement = WindDisplacement(worldPos);
		// Ground foliage keeps its feet in the ground: only the top vertices move,
		// and only sideways.
		displacement.y = wavingGroundFoliage ? 0.0 : displacement.y;
		cameraRelativePos.xyz += displacement;
	}
}
