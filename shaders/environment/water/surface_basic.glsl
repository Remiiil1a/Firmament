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

// There's a lot going on in this small function. By being clever, we can
// compress the calculation of the gradient (partial derivative with respect to
// X and partial derivative with respect to Y) of a given 4-wave stack in a given
// direction to: a dot, fma, cos, dot, and a final multiply, which on most GPUs
// should be a bunch of fma instructions plus a cos.
//
// === Why this is valid ===
//
// Given a wave function - four harmonics, not three, with the cosine weights
// 1, 1/2, 1/4, 1/8 that the vec4 of coefficients below makes explicit:
//
// W(x, y, dirX, dirY, time) =        sin(       x*dirX + y*dirY  + time)
//                           +  0.5 * sin(2.0 * (x*dirX + y*dirY) + time)
//                           + 0.25 * sin(4.0 * (x*dirX + y*dirY) + time)
//                           + 0.125* sin(8.0 * (x*dirX + y*dirY) + time)
//
// The derivative with respect to X would be:
//
// dW/dx = dirX * 1.0  * cos(       x*dirX + y*dirY  + time)
//       + dirX * 0.5  * cos(2.0 * (x*dirX + y*dirY) + time)
//       + dirX * 0.25 * cos(4.0 * (x*dirX + y*dirY) + time)
//       + dirX * 0.125* cos(8.0 * (x*dirX + y*dirY) + time)
//
// We can peel out the x*dirX + y*dirY as the variable angle, leaving:
//
// dW/dx = dirX * 1.0  * cos(1.0 * angle + time)
//       + dirX * 0.5  * cos(2.0 * angle + time)
//       + dirX * 0.25 * cos(4.0 * angle + time)
//       + dirX * 0.125* cos(8.0 * angle + time)
//
// At this point the symmetry is starting to be obvious. We can write this
// as:
//
// dWdXeach = vec4(
//   dirX * 1.0  * cos(1.0 * angle + time),
//   dirX * 0.5  * cos(2.0 * angle + time),
//   dirX * 0.25 * cos(4.0 * angle + time),
//   dirX * 0.125* cos(8.0 * angle + time)
// )
//
// dW/dx = dWdXeach.x + dWdXeach.y + dWdXeach.z + dWdXeach.w
//
// Which is equivalent to:
//
// dWdXeach = vec4(
//   1.0  * cos(1.0 * angle + time),
//   0.5  * cos(2.0 * angle + time),
//   0.25 * cos(4.0 * angle + time),
//   0.125* cos(8.0 * angle + time)
// )
//
// dW/dx = dirX * dWdXeach.x + dirX * dWdXeach.y
//       + dirX * dWdXeach.z + dirX * dWdXeach.w
//
// By definition, this is equivalent to:
//
// dWdXeach = vec4(1.0, 0.5, 0.25, 0.125)
//          * cos(vec4(1.0, 2.0, 4.0, 8.0) * vec4(angle) + vec4(time))
// dW/dx = dirX * (dWdXeach.x + dWdXeach.y + dWdXeach.z + dWdXeach.w)
//
// which is what the function computes: the `cos` on the right of the dot is
// the `vec4(1.0, 0.5, 0.25, 0.125) * cos(...)` term, and the dot against a
// vec4(1.0) sums it - i.e. a `vec4` reduce, spelled as a dot because GLSL has
// no horizontal-sum builtin.
//
// Finally, we can note that the only function between dW/dx and dW/dy
// is multiplying by dirX or dirY, so we can share the common operations
// and only multiply in the direction at the end for a further win.
vec2 gradWaterWave(vec2 worldPos, vec2 dir, float time) {
	float angle = dot(worldPos, dir);
	float dWdA = dot(
		cos(vec4(angle) * vec4(0.5, 1.0, 2.0, 4.0) + vec4(time)),
		vec4(1.0)
	);

	return vec2(dWdA) * dir;
}

// This function uses a short sequence of pure ALU operations to generate some
// fairly nice-looking waves very efficiently.
//
// Inputs: world position on the water plane, in meters, plus the world-space
// screen derivatives of that position, which this function accepts and then
// does not use, and time in seconds.
//
// The caller passes `cameraRelativePos.xz + cameraPosition.xz`, which is the
// world X/Z, and for a face that is standing up it also folds world Y in - see
// parallaxWaterNormal in translucent.glsl. So "horizontal world position" is
// only true of water lying flat on the ground: the X and Z of a vertical face
// are constant for the whole face and it is the Y contribution that makes the
// waves vary down it.
//
// Output: normal vector in tangent space (X/Y = in-plane, Z = up out of the
// plane). Z is the constant 1.0 before the normalize, so the returned vector is
// never more than 45 degrees away from straight out of the face - this is a
// perturbed normal, not the result of a height field with real depth.
vec3 WaterNormal(
	vec2 worldPos,
	vec2 ddxWorldPos,
	vec2 ddyWorldPos,
	float time
) {
	// Deform the wavefront using a sine wave as in real life, water does not
	// simply advance forward and straight diagonal wavefronts are entirely
	// unconvincing.
	//
	// This is a deformation of the sample position, not of the result, and it
	// is applied once here so that all four wave quartets below share it. It is
	// the only place `worldPos` is modified, and the gradient that comes out is
	// therefore the gradient of the deformed field, which is what we want to
	// shade - but note that it also means the amplitudes (0.008 etc. below) are
	// the amplitudes of the *undeformed* wave, since no compensating factor for
	// the 0.125 domain warp is applied.
	worldPos += 0.125 * (sin(time * 2.0 + worldPos.yx * vec2(2.0, 1.0)));

	// The phase varies over time to move the waves, and we also add in
	// fixed offsets to keep the waves out-of-phase of each other. The constants
	// are arbitrary and were chosen by eye, not measured; what matters is only
	// that the four differ. Time is scaled by 4.0 here, so the waveform is
	// advanced four times faster than the `time * 2.0` of the domain warp
	// above.
	vec4 phase = vec4(time * 4.0) + vec4(1.3657, 1.1345, 1.2290, 3.0297);

	// Since the derivative of two functions summed together is the sum of the
	// respective derivatives, we can calculate the gradients of each individual
	// directional wave quartet separately and just add them all together.
	//
	// Four quartets, each with a different direction and one of the four
	// phases. Note the two amplitudes: 0.008 and 0.004, and that the pairs
	// alternate rather than descending.
	vec2 gradient;
	gradient  = 0.008 * gradWaterWave(worldPos, vec2(1.0, 1.0),  phase.x);
	gradient += 0.004 * gradWaterWave(worldPos, vec2(1.0, 0.66), phase.y);
	gradient += 0.008 * gradWaterWave(worldPos, vec2(0.5, 0.75), phase.z);
	gradient += 0.004 * gradWaterWave(worldPos, vec2(1.0, 0.33), phase.w);

	// Note that we are in tangent space, so in terms of directions, Z is the
	// direction going up out of the face, and the X/Y are side-to-side within
	// the face.
	return normalize(vec3(gradient, 1.0));
}
