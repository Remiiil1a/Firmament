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

// Decode a lightmap texel coordinate to a scaled 0 to 1 light value / strength.
//
// At this point in the file the input is a texture coordinate in the lightmap
// texture, and its convention is texel centres rather than 0 to 1: the sixteen
// light levels 0 to 15 sit at (i + 0.5) / 16, so the range it can actually carry
// is 0.03125 (level 0) to 0.96875 (level 15), a span of 15/16.
//
// Subtracting 0.5 / 16 moves each input down by half a texel, and the
// 16.0 / 15.0 then stretches the levels' span of 15/16 out to 1.0. The result is
// the light level over 15, evenly spaced by 1/15: level 0 comes out at 0.0,
// level 1 at 1/15, and level 15 at exactly 1.0.
//
// The result is clamped to the unit range. For a level in range the clamp is
// mostly belt and braces: 0.03125 is exactly representable and 0.5 / 16.0 is
// exactly that, so level 0 lands exactly on the 0.000000001 floor and level 15
// is exactly 1.0 before the clamp is reached. What the clamp does bite on is a
// coordinate below the level-0 texel centre, which would otherwise come out
// negative and go to the floor anyway.
float LightMapToLight(float lightMap) {
	// As this is a texture coordinate, we need to subtract half of a texel
	// so that it starts from 0.0 instead of the middle of a texel. Otherwise
	// everything will be tinted with the color of blocklight.
	//
	// Recorded: the floor is 0.000000001 rather than 0.0 because of an "odd bug"
	// that was being hit when this returned 0.0. What that bug was is not
	// recorded here and there is no line in this file that shows it; note only
	// that the floor is what every out-of-range and level-0 input lands on, so
	// this function never returns 0.0 and lightmap-zero never reaches the
	// caller's own division or smoothstep unguarded.
	return clamp((lightMap - (0.5 / 16.0)) * (16.0 / 15.0), 0.000000001, 1.0);
}
