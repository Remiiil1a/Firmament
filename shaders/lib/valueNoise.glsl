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

// Include guard to permit every file that requires this function to include it,
// independent of other files.
#if !defined(VALUE_NOISE_INCLUDED)
#define VALUE_NOISE_INCLUDED

// Simple 2D value noise

// How big the noise texture is. The sampler itself is noisetex, supplied by the
// shader mod rather than shipped in this pack, so the size is stated here and
// everything else in this file and in valueNoiseDerivatives.glsl derives its
// texel arithmetic from these two constants - there is no image in the pack to
// cross-check the 64 against.
//
// Recorded as the reason for the size, and not something the code shows: 64x64
// is what is needed at most and 32x32 or 48x48 would probably do, and smaller is
// better because it helps the texture stay in cache.
const int noiseTextureResolution = 64;
const float noisePixel = 1.0 / noiseTextureResolution;

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform sampler2D noisetex;
#endif

// One texel of the noise texture, weighted by noiseChannel - which is not a
// channel selector but three weights, one per component of the fetched texel.
// Note that pos here is a raw texture coordinate, not the cell-space coordinate
// smoothNoise2Dx3 below takes; that function is the one that scales.
float noise(vec3 noiseChannel, in vec2 pos) {
	return dot(texture(noisetex, pos).xyz, noiseChannel);
}

// Helper function for the below smoothed noise function, this is taken from
// Perlin noise.
vec2 fade(vec2 t) {
	// 6t^5 - 15t^4 + 10t^3
	return t * t * t * (t * (t * 6 - 15) + 10);
}

// Very efficient value noise function taking full advantage of texture sampling
// hardware.
//
// Recorded as the reasoning behind the approach, and not as something this file
// can show: despite the memory bandwidth cost associated with texture sampling,
// the relatively small size of the texture we are sampling as well as the
// inherent nature of coherent noise (meaning that we usually are sampling
// similar broad areas of the texture) was taken to keep it in cache. And the
// bilinear filtering hardware in the GPU means that the normal process of
// sampling value noise - hashing the 4 cell corners and then interpolating
// between them - is entirely hardware-accelerated. Those two together were the
// argument that a texture-free version, even with a very fast hash function and
// optimized coordinate interpolation, ends up many more shader instructions and
// a fair bit slower; the measurement recorded at the time was 80 FPS to 90 FPS
// in a water-heavy scene. Neither the instruction count nor that FPS figure is
// verifiable from the code.
//
// Input: Coordinates scaled to the cell size - adding 1.0 to any coordinate
//        moves by the size of exactly 1 cell. The lower-left cell in the +X/+Y
//        quadrant covers the input coordinates (0.0, 0.0) to (1.0, 1.0).
//
// Output: 3 coherent noise values in the range [0.0, 1.0] - they are the three
//         components of the texel the bilinear filter produced, and that filter
//         cannot leave the range its inputs are in. Which component is which
//         noise field is a property of the texture, not of this code.
vec3 smoothNoise2Dx3(vec2 at) {
	// Determine the corner of the grid cell this coordinate lies in.
	vec2 corner = floor(at);

	// Per OpenGL reference pages, fract(x) is calculated by x - floor(x).
	// Since we have floor(x) anyways, we can skip the call to fract(x).
	vec2 offset = at - corner;

	// The critical component of value noise that makes it smooth (other than
	// the interpolation) is the smoothstep / fade function that we apply to the
	// cell-relative coordinates.
	//
	// In our case, as we will be computing the derivative of this noise
	// function, we MUST use fade() as it has a smooth derivative, whereas
	// smoothstep does not. If we used smoothstep, we would have
	// discontinuities.
	//
	// Note that the last operation in fade is a multiply. So this will compile
	// to a fused multiply-add.
	at = fade(offset) + corner;

	// Finally, we have our interpolation coordinates. However, we must change
	// coordinate systems into texel space before sampling. First, we must
	// obviously divide by the resolution of the value noise texture, as texture
	// coordinates are 0.0 to 1.0.
	//
	// However, less intuitively, we must also offset by half of a texel. Why?
	// Because in cell space, (0.5, 0.5) is the center of the lower-right cell.
	// However, in texture space (assuming a 64-pixel texture), (1/64, 1/64) is
	// the center of 4 texels (pixels) - in cell terms, the center of a cell,
	// and (0.5/64, 0.5/64) is actually dead-center on a single texel - in cell
	// terms, the lower-left corner of a cell.
	//
	// But, when we offset a cell coordinate we have scaled by 1/64 by half of a
	// texel, we then sync up these two spaces, such that a cell coordinate in
	// the center of a cell maps to a coordinate directly in the center of 4
	// texels, and such that a cell coordinate in the corner of a cell maps to a
	// coordinate in the dead center of a single texel.
	// 
	// We write out the coordinate system change like this to make it another
	// single-instruction fused multiply-add.
	at = at * (1.0 / noiseTextureResolution) + (0.5 / noiseTextureResolution);

	// Finally, sample the texture and choose our desired component.
	return texture(noisetex, at).xyz;
}

// Same as the function above, but only returns a single value noise result -
// the texel's x component, which the bilinear filter has already blended with
// the three texels around it, so this is still a coherent field and not a point
// sample of the texture.
float smoothNoise2D(vec2 at) {
	// TODO: This is the x component of an RGB/RGBA texel with the other
	// components thrown away, and the derivative variant below reads the same
	// component back with textureGather. A one-component texture would carry the
	// same field in a quarter of the memory, but nothing here can change which
	// texture the mod binds.
	return smoothNoise2Dx3(at).x;
}

// Same as the function above, but instead of returning the x component, it
// allows you to create your own noise channels dynamically - the noiseChannel
// parameter contains the weights of each noise channel, so this is the same dot
// product as noise() at the top of the file, applied to a filtered sample
// instead of a point sample.
float smoothNoise2D(vec3 noiseChannel, vec2 at) {
	return dot(smoothNoise2Dx3(at), noiseChannel);
}

#endif /* VALUE_NOISE_INCLUDED */
