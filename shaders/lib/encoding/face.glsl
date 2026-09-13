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

// Common encoding of per-face data that does not vary with each vertex.
//
// The following data is currently packed into a single 32-bit unsigned integer:
//
// * The face normal in world space
// * The material ID
//
// The face normal is first encoded with octahedral unit vector encoding, giving
// two values from 0 to 1, then these values are re-encoded as fixed-point
// integers and rounded accordingly. Note that with octahedral encoding, the
// 1.0 and 0.0 are NOT equivalent (the values do not wrap around), unlike angle
// measurements.
//
// The current encoding is: Octahedral X (9 bits), Octahedral Y (9 bits),
// and material ID (4 bits).
//
// This leaves 10 bits available for a diamond-encoded tangent vector and
// corresponding bitangent handedness bit, so we could store the material ID and
// data to reconstruct the TBN matrix in 32 bits. Neat!
//
// There is a fixed amount of buffer space available on graphics hardware for
// transferring data from the vertex shader to the fragment shader, and this is
// a common bottleneck in Minecraft, so packing this data into a single 32-bit
// value helps reduce this bottleneck.
//
// Reference for the octahedral unit vector encoding in use:
//
//  Quirin Meyer, Jochen Süßmuth, Gerd Sußner, Marc Stamminger, and Günther
//  Greiner. 2010. On floating-point normal vectors. In Proceedings of the 21st
//  Eurographics conference on Rendering (EGSR'10). Eurographics Association,
//  Goslar, DEU, 1405–1409. https://doi.org/10.1111/j.1467-8659.2010.01737.x
//
// PDF link: https://coburggraphicslab.github.io/files/Meyer10OFN.pdf

// With the diamond shape of the top and bottom projection of an octahedron, we
// can fill a square by folding one diamond outward into the 4 triangles on the
// edges of the other diamond within the square.
//
// Applying this function again reverses it. In other words, fold(fold(v)) = v.
vec2 fold(vec2 octahedral) {
	// With the diamond shape, we can fill a square by using the 4 triangles
	// on the edges of the diamond within the square.
	//
	// Our basic strategy is to take the absolute value of the coordinates to
	// get into the upper right quadrant, then mirror the point across the line
	// y = x (diagonal), then move back to the original square by restoring
	// the sign values.
	//
	// Excuse the stretching from the limitations of ASCII art:
	// 
	// |----/|\----|
	// |   / | \M  |
	// |  /  |  \ R|
	// | /   |  P\ |
	// |-----+-----|
	// | \   |   / |
	// |  \  |  /  |
	// |   \ | /   |
	// |----\|/----|
	//
	// Consider (0.5, 0.33) located at P. Subtracting from 1.0 would give
	// (0.5, 0.67) located at M. But, if we visually unwrap the octahedron,
	// we can easily see that we ended up on the wrong side of the octahedral
	// face. Instead, we need to end up at R, which swapping Y and X does.
	//
	// This gives us our wrapping algorithm:
	vec2 mirrored = 1.0 - abs(octahedral.yx);

	// Annoyingly, we cannot actually use the sign function here, as sign(0)
	// gives 0, when we actually need 1. But this is just a "compare" and a
	// "select" instruction in comparison to just extracting the sign bit.
	//
	// When we have zeroes, we aren't selecting a quadrant but rather are
	// just creating a singularity at the center. This needs to be -1 or 1.
	vec2 quadrant = vec2(
		octahedral.x >= 0.0 ? 1.0 : -1.0,
		octahedral.y >= 0.0 ? 1.0 : -1.0
	);

	return mirrored * quadrant;
}

// Given a normalized unit vector, returns the octahedral encoding of that
// vector with each component in the 0 to 1 range.
vec2 EncodeUnitVector(vec3 v) {
	// Project the vector on to an octahedron using the 1-norm. In this step,
	// we have projected the vector assuming that it is pointing upward, and it
	// occupies a diamond shape on a flat plane from [-1, -1] to [1, 1].
	vec2 octahedral = v.xy / dot(abs(v), vec3(1.0));

	// To store both the bottom and top diamonds of the octahedron, we can fold
	// the bottom octahedron outwards to fill in the gaps between the diamond
	// and the enclosing square.
	if (v.z < 0.0) {
		octahedral = fold(octahedral);
	}

	// Finally, scale to the 0 to 1 range.
	return octahedral * 0.5 + 0.5;
}

// Given the octahedral encoding of a unit vector with each component in the 0
// to 1 range, returns the normalized unit vector.
vec3 DecodeUnitVector(vec2 octahedral) {
	// Scale to the -1 to 1 range
	octahedral = octahedral * 2.0 - 1.0;

	// Reconstruct the Z value using the 1-norm. Conveniently, our fold function
	// gives the same Z value but negative if we are outside the inner diamond.
	float z = 1.0 - abs(octahedral.x) - abs(octahedral.y);

	// Applying the fold function again reverses it.
	if (z < 0.0) {
		octahedral = fold(octahedral);
	}

	// We now have a normal vector normalized at the 1-norm, and finally need to
	// normalize it with the 2-norm.
	return normalize(vec3(octahedral, z));
}

// Bits used for each of the two fixed-point encoded octahedral coordinates
const uint OCT_BITS = 9u;

uint EncodePerFace(vec3 worldNormal, uint materialID) {
	// Pack the floating point normal using fixed-point octahedral encoding
	vec2 worldNormalOct = EncodeUnitVector(worldNormal);
	uint octFixedX = uint(worldNormalOct.x * float((1u << OCT_BITS) - 1u));
	uint octFixedY = uint(worldNormalOct.y * float((1u << OCT_BITS) - 1u));
	uint normalBits = (octFixedX << (OCT_BITS + 4u)) | (octFixedY << 4u);

	// Truncate the material ID if needed
	uint materialBits = materialID & 0xFu;

	return normalBits | materialBits;
}

uint DecodePerFaceMaterialID(uint perFace) {
	return perFace & 0xFu;
}

vec3 DecodePerFaceWorldNormal(uint perFace) {
	uint octFixedX = ((1u << OCT_BITS) - 1u) & (perFace >> (4u + OCT_BITS));
	uint octFixedY = ((1u << OCT_BITS) - 1u) & (perFace >> 4u);

	return DecodeUnitVector(vec2(
		float(octFixedX) * (1.0 / float((1u << OCT_BITS) - 1u)),
		float(octFixedY) * (1.0 / float((1u << OCT_BITS) - 1u))
	));
}
