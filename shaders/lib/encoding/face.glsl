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

// Modified 2026-09-19 by Remiiil1a for Firmament - v0.4 (edit of coderbot's Steadfast).

// Common encoding of per-face data that does not vary with each vertex.
//
// The following data is packed into a single 32-bit unsigned integer:
//
// * The face normal in world space
// * The tangent of the face, and which way its bitangent points, so that the
//   whole world space TBN matrix can be rebuilt in the fragment shader
// * The material ID
//
// The face normal is first encoded with octahedral unit vector encoding, giving
// two values from 0 to 1, then these values are re-encoded as fixed-point
// integers. That conversion truncates - the code casts to uint, it does not add
// a half step first - so both octahedral coordinates are floor(v * 511) / 511
// on the way back out, and each carries at most 9 bits. Note that with
// octahedral encoding, the 1.0 and 0.0 are NOT equivalent (the values do not
// wrap around), unlike angle measurements.
//
// The encoding, from the bottom of the word upwards, is: material ID (4 bits,
// bits 0-3), octahedral Y (9 bits, bits 4-12), octahedral X (9 bits, bits
// 13-21), a diamond-encoded tangent (9 bits, bits 22-30), and the handedness of
// the bitangent (1 bit, bit 31). That fills all 32 bits with nothing to spare.
//
// The shifts and masks below and in DecodePerFace* are this layout and nothing
// else: OCT_BITS and TANGENT_BITS are both 9, TANGENT_SHIFT is 4 + 9 + 9 = 22,
// and HANDEDNESS_SHIFT is that plus 9 = 31. The material ID is the low nibble,
// so it is the field the octahedral encoders' truncation cannot reach.
//
// The tangent is not encoded as a direction in three dimensions, which would
// not fit. It is meant to be orthogonal to the normal - the tangent that
// arrives as a vertex attribute is taken to be, and the fallback the vertex
// stage substitutes for geometry that carries none is built orthogonal to the
// same normal - so once the normal is known it lives in a plane, and two
// numbers are enough to place it in one. The basis vectors used for that plane,
// and the tangent itself, are all unit length, so those two numbers form a
// two-dimensional unit vector, which a single number can carry. See the diamond
// encoding below.
//
// The basis is the one OrthonormalBasisOf derives from the *decoded* normal, so
// the tangent this file rebuilds is orthogonal to the decoded normal by
// construction - it is only as orthogonal to the original normal as the 9-bit
// octahedral rounding allows (measured up to about 0.016 in vector distance
// over random unit normals at 9 bits). A tangent that was orthogonal before the
// round trip is carried back through the basis as though it still were.
//
// Recorded: upstream Steadfast writes this out and then leaves it behind a
// switch it has not turned on yet. This pack always stores the tangent - there
// is no option in this file that lets the tangent field go unused - because the
// water surface wants the frame the face actually has rather than an assumed
// one.
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

// The same as the vec2 decoder above, minus the final normalize. (Not the same
// as DecodeUnitVector directly above, which is the vec3 overload.)
//
// The encoder needs to know the sign of the Z component that the decoder will
// see, and only that sign - so it can skip both the square root of the
// normalization and everything downstream of it, provided it can ask for the
// unnormalized vector.
vec3 DecodeCodirectionalVector(vec2 octahedral) {
	// Scale to the -1 to 1 range
	octahedral = octahedral * 2.0 - 1.0;

	// Reconstruct the Z value using the 1-norm. Conveniently, our fold function
	// gives the same Z value but negative if we are outside the inner diamond.
	float z = 1.0 - abs(octahedral.x) - abs(octahedral.y);

	// Applying the fold function again reverses it.
	if (z < 0.0) {
		octahedral = fold(octahedral);
	}

	// Normalized at the 1-norm; the caller normalizes with the 2-norm if it
	// wants a unit vector.
	return vec3(octahedral, z);
}

// "Building an Orthonormal Basis, Revisited"
// https://jcgt.org/published/0006/01/01/
//
// Returns two unit vectors that, together with the given normal, form a basis.
// They are what the tangent is expressed in: it lies in the plane both of them
// cover, so two coefficients against them place it exactly.
//
// signZ must be 1.0 when normal.z is positive and -1.0 when it is negative.
// For a value very close to zero either may be chosen, but the encoder and the
// decoder must choose the same one - which is why the encoder below asks what
// the decoder would see (it decodes the quantized octahedral coordinates back
// to a Z value) instead of using the sign of the normal it was handed.
//
// Both callers normalise the normal they hand in, so sign + normal.z is in
// [1, 2] and the division cannot blow up - signZ is only ever +1 or -1 here,
// from the two ternaries below. Note what that means in an earlier sentence:
// the sign is a property of the normal argument, and the encoder passes the
// exact normal while deriving the sign from the truncated one, so the two bases
// differ by the quantization of the normal - about 0.016 at 9 bits. That does
// not matter for the tangent round trip, which is what the sign is there to
// agree on, and it is why the decoder is handed the decoded normal rather than
// decoding it again itself.
mat2x3 OrthonormalBasisOf(vec3 normal, float signZ) {
	float sign = signZ;
	float a = -1.0 / (sign + normal.z);
	float b = normal.x * normal.y * a;

	return mat2x3(
		vec3(1.0 + sign * normal.x * normal.x * a, sign * b, -sign * normal.x),
		vec3(b, sign + normal.y * normal.y * a, -normal.y)
	);
}

// We encode 2D unit vectors using "diamond encoding", the two-dimensional
// analogue of the octahedral encoding above:
//
// www.jeremyong.com/graphics/2023/01/09/tangent-spaces-and-diamond-encoding
//
// While we could use transcendental functions to store it as an angle, those
// functions are more costly than diamond encoding.
float EncodeUnitVector(vec2 v) {
	// Project to the unit diamond (1-norm)
	float x = v.x / (abs(v.x) + abs(v.y));

	// Contract the x coordinate by a factor of 4 to represent all 4 quadrants
	// in the unit range and remap. The angle below is the direction of v within
	// its plane, measured from the +x axis.
	//
	// * 0° to 90° are mapped between 0.0 and 0.25
	// * 90° to 180° are mapped between 0.25 and 0.5
	// * 180° to 270° are mapped between 0.5 and 0.75
	// * 270° to 360° (0°) are mapped between 0.75 and 1.0 (0.0)
	//
	// The mapping is continuous like an angle, which is what lets the fixed-point
	// conversion below wrap 1.0 around to 0.0 and pick up one extra step of
	// precision from doing it. The 512 steps of the 9-bit field then cover the
	// full turn, which is why 1.0 need not be representable: it is 0.0.
	float quarter = v.y >= 0.0 ? -0.25 : 0.25;

	// Written explicitly like a fused multiply-add
	return x * quarter + (0.5 - quarter);
}

// Given the diamond encoding of a unit vector with each component in the 0
// to 1 range, returns a vector codirectional to that unit vector.
//
// If you desire the same unit vector, use normalize() on the result.
vec2 DecodeCodirectionalVector(float diamond) {
	// To decode the above mapping, we have two cases.
	//
	// When diamond <= 0.5 (y >= 0):
	//
	// x = 4 * diamond - 1
	// y = 1 - |x|
	//
	// When diamond > 0.5 (y < 0):
	//
	// x = 3 - 4 * diamond
	// y = -(1 - |x|)
	//
	// The below is a branchless translation of this piecewise function.
	float sign = diamond >= 0.5 ? 1.0 : -1.0;
	float x = (-4.0 * sign) * diamond + (2.0 * sign + 1.0);

	// We now have a vector normalized at the 1-norm.
	// The caller calls normalize to normalize it with the 2-norm.
	return vec2(
		x,
		sign * (1.0 - abs(x))
	);
}

// Bits used for each of the two fixed-point encoded octahedral coordinates
const uint OCT_BITS = 9u;

// Bits used for the single diamond-encoded tangent
const uint TANGENT_BITS = 9u;

// Where the tangent sits: bits 22-30, above the 4 material bits and the two
// 9-bit octahedral coordinates.
const uint TANGENT_SHIFT = 4u + OCT_BITS + OCT_BITS;

// The handedness of the bitangent is the top bit (bit 31), so the tangent's
// field ends one bit below it.
const uint HANDEDNESS_SHIFT = TANGENT_SHIFT + TANGENT_BITS;

// The worldTangent must not be a zero vector: the first thing done with it is
// normalize, and normalizing a zero vector is undefined. It does not have to be
// unit length on the way in, because of that normalize - a vertex shader with
// geometry that carries no tangent at all - Minecraft's entity format, some
// mods - has to substitute a non-zero tangent of its own before calling this;
// see lit.vsh (its tangentAttribute is used raw when it is not near zero, and
// the first basis vector from OrthonormalBasisOf is used when it is).
uint EncodePerFace(
	vec3 worldNormal,
	vec3 worldTangent,
	bool handedness,
	uint materialID
) {
	// Pack the floating point normal using fixed-point octahedral encoding
	vec2 worldNormalOct = EncodeUnitVector(worldNormal);
	uint octFixedX = uint(worldNormalOct.x * float((1u << OCT_BITS) - 1u));
	uint octFixedY = uint(worldNormalOct.y * float((1u << OCT_BITS) - 1u));
	uint normalBits = (octFixedX << (OCT_BITS + 4u)) | (octFixedY << 4u);

	// Truncate the material ID if needed
	uint materialBits = materialID & 0xFu;

	// Encode the tangent. The bitangent is not stored: it can be rebuilt from
	// the normal, the tangent and the single handedness bit.
	uint handednessBits = uint(handedness) << HANDEDNESS_SHIFT;

	// To encode the tangent vector, we first identify two basis unit vectors
	// that form an orthogonal basis when combined with the normal vector.
	//
	// The function that derives the basis vectors relies on splitting the unit
	// sphere into two hemispheres, and it's important that we get the same
	// hemisphere decision on both the encode and decode path. Specifically, we
	// select a hemisphere based on the sign of the Z component of the normal.
	//
	// The octahedral coordinates are truncated to 9 bits first - this is not a
	// rounding, the cast to uint drops the fraction - so the normal the decoder
	// will see is not quite the one this function was handed. To predict what
	// hemisphere the decoder would select we therefore feed the *quantized*
	// coordinates back through the decode (the inverse of the fixed-point
	// conversion above, written out here rather than reusing the const) and take
	// the sign of the Z it returns. We can skip normalizing, and this lets the
	// optimizer remove the rest of the decode calls not needed to derive the Z
	// value.
	//
	// DecodePerFaceWorldTBN makes the same decision by testing the Z of the
	// normal it is handed, which is the normalized decode of these same 9-bit
	// coordinates - so the two agree. They cannot disagree even at Z = 0: a
	// checked sweep of all 512 * 512 9-bit coordinate pairs finds no pair whose
	// Z lands on zero (the closest magnitudes are 1/511 either side of it), so
	// the decoder's test always picks the same side the quantization implied.
	//
	// Without this roundtrip, the derived basis vectors during decoding would
	// be inconsistent with what this encoding function selected, and the
	// reconstructed tangent would come back rotated.
	float basisSign = DecodeCodirectionalVector(vec2(
		float(octFixedX) * (1.0 / float((1u << OCT_BITS) - 1u)),
		float(octFixedY) * (1.0 / float((1u << OCT_BITS) - 1u))
	)).z >= 0.0 ? 1.0 : -1.0;

	// The basis the tangent is measured against. It is built from the normal
	// argument - the exact one, not the decoded one - while the sign comes from
	// the decoded one; the tangent gets back the same coordinates on the decode
	// path, so the residual error is the octahedral truncation of the normal
	// and nothing to do with the hemisphere.
	mat2x3 basis = OrthonormalBasisOf(worldNormal, basisSign);

	// Since the tangent vector is meant to be orthogonal to the normal vector,
	// and these two basis vectors are both orthogonal to the normal argument,
	// they span the plane the tangent lies in. (The attribute is taken on trust;
	// a tangent that is not quite orthogonal is still carried through as though
	// it were, and what comes back is orthogonal to the decoded normal.)
	//
	// It follows that we can express the tangent vector as a linear combination
	// of the two basis vectors.
	vec2 plane = normalize(worldTangent) * basis;

	// Further, since the length of the basis vectors are both 1, and the length
	// of the tangent is normalized above to 1, the length of the 2D vector used
	// to express this linear combination is also 1 - up to the orthogonality
	// above. We can encode a 2D unit vector into a single value.
	float tangentEncoded = EncodeUnitVector(plane);

	// The encoded vector is continuous like an angle, so we can get a bit of
	// extra precision by wrapping 1.0 around to 0.0. This departs from the
	// octahedral encoding which is not continuous.
	uint tangentFixed = uint(tangentEncoded * float(1u << TANGENT_BITS));
	tangentFixed &= (1u << TANGENT_BITS) - 1u;
	uint tangentBits = tangentFixed << TANGENT_SHIFT;

	return normalBits | handednessBits | tangentBits | materialBits;
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

// Rebuilds the world space TBN matrix that EncodePerFace stored: the columns
// are the tangent, the bitangent and the face normal, in that order.
//
// The worldNormal is the one DecodePerFaceWorldNormal returned for this same
// perFace. It is passed in rather than decoded again because a fragment shader
// has already decoded it, and because the basis below has to be chosen with the
// normal the decoder sees - the truncated one - rather than the exact normal
// the vertex shader encoded. Asking the caller to single-source it is also what
// makes the two Z signs agree by construction rather than by two copies of the
// same arithmetic happening to stay in step.
mat3 DecodePerFaceWorldTBN(uint perFace, vec3 worldNormal) {
	const float fromTangentFixed = 1.0 / float(1u << TANGENT_BITS);

	// Determine the basis vectors the tangent was expressed with
	float basisSign = worldNormal.z >= 0.0 ? 1.0 : -1.0;
	mat2x3 basis = OrthonormalBasisOf(worldNormal, basisSign);

	// Unpack the diamond-encoded tangent from fixed point
	uint tangentFixed = (perFace >> TANGENT_SHIFT)
		& ((1u << TANGENT_BITS) - 1u);
	float tangentEncoded = float(tangentFixed) * fromTangentFixed;

	// Decode the tangent as a linear combination of the two basis vectors.
	vec2 plane = normalize(DecodeCodirectionalVector(tangentEncoded));
	vec3 worldTangent = basis * plane;

	// The bitangent is the tangent turned a quarter turn in the face's plane,
	// with the direction the vertex stage recorded.
	//
	// This is written as a cross product rather than as a rotation within the
	// basis, because it must agree with the convention the material decoding
	// uses for the tangents that arrive as vertex attributes (see
	// PbrAttributeFrame in pbr.glsl) - and a cross product cannot disagree with
	// it. The two differ only in the sign convention of the basis, which is not
	// something worth being clever about here.
	//
	// ⚠️ The operand order below is the one this pack has always used, and it is
	// the negation of the loader's: Iris documents the handedness as
	// "vec3 bitangent = cross(tangent, normal) * handedness", and
	// PbrAttributeFrame has since been corrected to that, so the material
	// frame's second axis is the texture's +v and this one's is -v. What that
	// costs is bounded by where this frame is read - dWorldPosdxdy below takes
	// the pair as an arbitrary orthonormal basis of the plane and reconstructs a
	// world-space derivative from it, which a negated edge cancels out of, and
	// the water reads worldTBN[1] only for a face that is not horizontal, the
	// flat case using the world swizzle in translucent.glsl instead, where the
	// note at that use already says the two frames agree only "up to the sign of
	// each axis".
	//
	// So the sign is left here rather than changed with the material frame's:
	// making them agree is a change to how sideways water looks, and it belongs
	// in a change of its own, made while looking at water.
	float handedness = (perFace >> HANDEDNESS_SHIFT) > 0u ? 1.0 : -1.0;
	vec3 worldBitangent = cross(worldNormal, worldTangent) * handedness;

	return mat3(worldTangent, worldBitangent, worldNormal);
}
