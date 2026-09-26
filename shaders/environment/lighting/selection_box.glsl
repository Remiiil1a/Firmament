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

// Added 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's
// Steadfast).

// The block selection outline, and what it is allowed to look like.
//
// Included by gbuffers_basic.fsh alone - that is the program the game hands
// lines and boxes to - and by nothing else. It defines the options there and
// the colour helper the world shader calls; the drawing itself is in
// program/world/lit.fsh, where fragmentColor is finally written.
//
// ⚠️ "The block selection outline" is really "every line the game draws",
// because there is only one program for all of them: the outline, the entity
// hitboxes that F3+B shows, the bounding boxes of a structure block, and
// anything else handed to a line render type. The pack cannot tell them apart -
// they arrive at the same program with the same material - so every one of these
// options applies to all of them. Worth knowing before wondering why a hitbox
// changed colour.

// Which look the outline gets.
//
// VANILLA leaves it to the pack's ordinary shading, which is what it was before
// this existed. NONE removes it. GLOW and RGB light it up; see below for what
// separates those two.
#define SELECTION_BOX_VANILLA 0
#define SELECTION_BOX_NONE 1
#define SELECTION_BOX_GLOW 2
#define SELECTION_BOX_RGB 3
#define SELECTION_BOX SELECTION_BOX_VANILLA // [SELECTION_BOX_VANILLA SELECTION_BOX_NONE SELECTION_BOX_GLOW SELECTION_BOX_RGB]

// What GLOW lights the outline with, one value per channel, 0 to 255.
//
// ⚠️ These are read as sRGB - the numbers a colour picker shows - and converted
// on the way in, so that 128 looks like a mid tone rather than like a fifth of
// full brightness. The pack works in linear light throughout and this is the one
// place a player types a colour, which is why the conversion lives here.
//
// ⚠️ They do nothing in the RGB mode, which chooses its own colours, and nothing
// in VANILLA or NONE. Changing them in those modes is not a bug.
//
// The lists run the whole way from 0 to 255 one step at a time, so that every
// value is reachable. A coarser list would be shorter and would also make the
// sliders useless for matching a colour to anything.
#define SELECTION_GLOW_R 255 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255]
#define SELECTION_GLOW_G 255 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255]
#define SELECTION_GLOW_B 255 // [0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45 46 47 48 49 50 51 52 53 54 55 56 57 58 59 60 61 62 63 64 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95 96 97 98 99 100 101 102 103 104 105 106 107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 123 124 125 126 127 128 129 130 131 132 133 134 135 136 137 138 139 140 141 142 143 144 145 146 147 148 149 150 151 152 153 154 155 156 157 158 159 160 161 162 163 164 165 166 167 168 169 170 171 172 173 174 175 176 177 178 179 180 181 182 183 184 185 186 187 188 189 190 191 192 193 194 195 196 197 198 199 200 201 202 203 204 205 206 207 208 209 210 211 212 213 214 215 216 217 218 219 220 221 222 223 224 225 226 227 228 229 230 231 232 233 234 235 236 237 238 239 240 241 242 243 244 245 246 247 248 249 250 251 252 253 254 255]

// How fast RGB mode walks through the colours.
//
// One full turn of the colour wheel takes about ten seconds at 1.0. Slower than
// that it stops reading as a glow and starts reading as a tint that is slightly
// wrong; faster it becomes a strobe.
#define SELECTION_RGB_SPEED 1.0 // [0.0 0.25 0.5 0.75 1.0 1.5 2.0 3.0]

// How much brighter than the scene the outline is written.
//
// ⚠️ This is the whole of what makes it glow, and it is worth being exact about
// why. The bloom pass reads colortex0 and takes everything above its threshold,
// which is zero by default - so anything written brighter than the scene comes
// back as a halo around itself. Writing the outline at its own colour would give
// a coloured line with nothing around it; writing it several times over gives
// the line and a halo of the same colour, which is what a glow is.
//
// ⚠️ The cost is that the line's own core clips towards white, because everything
// above one is white after the tonemap. The COLOUR survives in the halo, which
// is the larger part of what is being looked at - so a deep red reads as a white
// line inside a red glow rather than as a red line. That is how emission usually
// behaves and it was left that way deliberately; lowering this trades the halo
// for the line's own colour.
const float SELECTION_GLOW_STRENGTH = 5.0;

// The time uniform, which RGB mode cycles on.
//
// Declared behind a guard because more than one file in this pack asks for it
// and a repeated uniform declaration is an error: whichever of them is included
// first declares it and the rest are skipped. Programs whose uniforms come from
// elsewhere - Voxy's terrain - get it from there instead.
#if !defined(EXTERNALLY_DEFINED_UNIFORMS) && !defined(FRAME_TIME_COUNTER_DECLARED)
	#define FRAME_TIME_COUNTER_DECLARED
	uniform float frameTimeCounter;
#endif

// SrgbToLinear, for the three numbers above.
// ⚠️ Deliberately not included: see the note in SelectionBoxColor below.

// The colour the outline is drawn in, in linear light, already scaled by the
// strength - so the caller writes it and nothing else.
//
// ⚠️ The RGB mode's cycle is a hue rotation written out rather than an HSV
// conversion, because all it needs is the fully saturated rim of the colour
// wheel and that has a closed form: take the hue as a position round the circle,
// read three offset triangles of it, and the result is the colour. It costs no
// branches and has no singularities at the ends, which a hue-to-RGB written the
// other way does.
//
// ⚠️ The three values of the GLOW mode are converted from sRGB by hand rather
// than through lib/srgb.glsl - not for its sake, but because that file has no
// include guard of its own and this program already includes it somewhere else.
// Including it a second time is a redeclaration and does not compile, which
// _check_shader_sources.ps1 says out loud: "srgb.glsl is in this program 2 times,
// and does not guard itself". SRGB_GAMMA is 2.2, so this is the same curve.
vec3 SelectionBoxColor() {
	#if SELECTION_BOX == SELECTION_BOX_RGB
		float hue = fract(frameTimeCounter * SELECTION_RGB_SPEED * 0.1);

		return clamp(
			abs(mod(hue * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
			0.0, 1.0) * SELECTION_GLOW_STRENGTH;
	#else
		return pow(vec3(
			SELECTION_GLOW_R, SELECTION_GLOW_G, SELECTION_GLOW_B) / 255.0,
			vec3(2.2)) * SELECTION_GLOW_STRENGTH;
	#endif
}

// Writing that colour out.
//
// ⚠️ The macro exists only when there is something to write, and that is what
// makes the guard in the world shader work: it tests defined(SELECTION_BOX_OVERRIDE),
// so the block is compiled in this program and dropped in the other fourteen,
// and the name in the guard is the name in the block.
//
// ⚠️ Which matters for more than tidiness. The pack's own source check reads the
// text without evaluating #if, and it recognises a use under a guard only when
// the guard names the symbol being used - so a call to SelectionBoxColor sitting
// in the world shader under a guard on DRAWING_LINES reads to it as a call in
// fifteen programs that have never heard of the name, and it says so fifteen
// times. Keeping the call in this macro body, and the guard on this macro's own
// name, is what keeps the check quiet and honest at the same time.
#if SELECTION_BOX == SELECTION_BOX_GLOW || SELECTION_BOX == SELECTION_BOX_RGB
	#define SELECTION_BOX_OVERRIDE fragmentColor = vec4(SelectionBoxColor(), 1.0);
#endif

