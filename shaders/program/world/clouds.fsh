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

// sRGB to Linear RGB
#include "/lib/srgb.glsl"

// The interpolated vertex color directly from the vertex buffer.
in vec4 tinting;

// The program's own texture sampler, the one Iris binds for every program.
//
// At this point in the file it is the cloud texture and not a material: this
// program is gbuffers_clouds, which samples the cloud layer's own texture.
//
// See /lib/valueNoise.glsl for the same sampler used as a noise texture, which
// is the other thing the pack binds it to.
uniform sampler2D gtexture;

// The interpolated texture coordinate directly from the vertex buffer.
in vec2 texcoord;

in vec4 fog;

// Declared by the pack for the programs that take light from the world; it is
// not read anywhere in the body below, so at this point in the file it has no
// meaning to state. Left in place rather than given a meaning it has not got.
// Declared by the pack for the programs that take light from the world; it is
// not read anywhere in the body below, so at this point in the file it has no
// meaning to state. Left in place rather than given a meaning it has not got.
in vec3 indirect;

uniform vec3 cloudColor;

// Alpha test threshold - any pixels with an alpha less than this will be
// discarded.
//
// An Iris uniform whose value differs per program - 0.1 for terrain cutout, 0
// for solid - so it exists only where the pack declares it. Here it is the
// cloud texture's own cutout.
uniform float alphaTestRef;

void main() {
	vec4 surfaceColor = tinting * texture(gtexture, texcoord);

	// Run the alpha test here, before the sRGB conversion below, so that a
	// discarded fragment never reaches that work.
	//
	// What it provably skips is the SrgbToLinear() on the next lines. The
	// texture fetch above it has already happened, and a fragment that is
	// discarded writes nothing - GLSL guarantees it - so what is saved is
	// arithmetic, not the sample.
	//
	// This used to claim a boost from skipping "shading" and from memory
	// bandwidth and TMU load. Recorded: those were expectations, not
	// measurements, and none of them can be re-derived from this file. The
	// discards are still the right order - they are free either way - but read
	// the paragraph above as what the code shows.
	if (surfaceColor.a < alphaTestRef) { 
		discard;
		return;
	}

	// Apply sRGB to linear conversion
	//
	// We do this after multiplying texture color with vertex color
	// and after including entity color (if applicable) as to mimic
	// Minecraft, as it does the same multiplications (incorrectly)
	// in sRGB color space.
	surfaceColor.rgb = SrgbToLinear(surfaceColor.rgb);

	// Multiply in cloud color / fog and write out to the primary color
	// buffer.
	//
	// fog.a is the Fog() return's transmittance - what is left of the surface
	// after the fog - and fog.rgb its colour already multiplied by the fog
	// factor, so this is a premultiplied blend of one surface with no
	// background behind it. See environment/fog.glsl for the return.
	//
	// fog.a is the Fog() return's transmittance - what is left of the surface
	// after the fog - and fog.rgb its colour already multiplied by the fog
	// factor, so this is a premultiplied blend of one surface with no
	// background behind it. See environment/fog.glsl for the return.
/* DRAWBUFFERS:0 */
	gl_FragData[0] = vec4(surfaceColor.rgb * cloudColor * fog.a + fog.rgb, 0.2);
}
