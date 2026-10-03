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

// Added 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

// LabPBR material support.
//
// This decodes the normal (_n) and specular (_s) atlases that Iris / OptiFine
// build from a PBR resource pack, following the shaderLABS LabPBR 1.3 material
// standard:
//
//   https://shaderlabs.org/wiki/LabPBR_Material_Standard
//
// Channel layout, as defined by the standard:
//
//   _n.rgb - tangent-space normal, stored in the DirectX convention (X points
//            right, Y points *down* in the texture). Note that _n.b is NOT the
//            Z component: LabPBR stores material ambient occlusion there and
//            requires Z to be reconstructed from X and Y. That occlusion is
//            read when PBR_MATERIAL_AO is on (PbrDecode, into materialAO); with
//            that off, nothing in this file reads the blue channel except the
//            occlusion debug view, which samples it independently of the option
//            so that a pack can be judged before the option is turned on.
//   _n.a   - height, used for parallax occlusion mapping.
//
//   _s.r   - perceptual smoothness. roughness = (1.0 - smoothness)^2
//   _s.g   - F0 / metal ID, read as a byte by multiplying by 255 and split at
//            229.5 and 237.5 - half-way between the bytes that neighbour each
//            range, so that a filtered sample cannot land on a boundary.
//            Values are stored linearly as of 1.3 (older versions stored the
//            square root of F0 and would need squaring).
//              0-229   dielectric, F0 = the value itself (max ~0.898)
//              230-237 hardcoded metals, see PbrMetalF0
//              238-255 albedo-based metal, F0 = the albedo
//   _s.b   - subsurface scattering above 64.5/255, porosity below it. The
//            scattering is read when PBR_SUBSURFACE is on and is the channel
//            itself, so 65/255 arrives as 0.255 and 254/255 as 0.996; the
//            porosity is read when PBR_POROSITY_WETNESS is and is rescaled
//            out of the lower range, b * 255 / 64, so byte 64 is a porosity
//            of 1.0 and byte 32 is 0.5.
//   _s.a   - emission. 254 means "fully emissive", 255 means "does not emit".
//
// Every feature below has its own switch, so a player who does not want, say,
// the cost of parallax mapping can turn just that off.
//
// Cost note - all of this is per-pixel:
//
//   Always executed (when PBR_SURFACE is defined and the material is not
//   skipped): the tangent frame, the parallax ray march if that is enabled, the
//   normal decode, and the specular / emission decode.
//
//   Conditionally executed: the hardcoded metal lookup (only for materials with
//   G > 229.5/255), emission (only when the material actually emits), the
//   occlusion channel of the normal map (only when PBR_MATERIAL_AO is on), and
//   the specular lobe itself (skipped entirely when F0 is zero, which is what a
//   resource pack without specular maps produces).
//
//   Everything else here is either unconditional or gated on the material
//   actually carrying the channel it reads, so a resource pack without a given
//   map pays nothing for it.

// A note for anyone adding options here: a boolean option is only registered
// by Iris if the macro is referenced by an #ifdef or #ifndef somewhere in the
// pack. A toggle that is only ever tested with "#if defined(NAME)" is declared,
// works when edited by hand, and silently never appears in the settings menu.
// That is what the #ifdef blocks after the toggles below are for.
//
// Whether to read PBR material data at all. Turn this off to fall back to
// Steadfast's original rendering, which is useful when playing with a resource
// pack that has no normal / specular maps.
#define PBR_OFF 0
#define LAB_PBR 1
#define PBR_FORMAT LAB_PBR // [PBR_OFF LAB_PBR]

// Whether to build the material tangent frame from the tangent the geometry
// actually has, instead of rebuilding one out of screen-space derivatives.
//
// The derivative route has to reconstruct the surface position from the depth
// buffer before it can differentiate it, and the depth buffer quantizes: past a
// certain distance the step it takes between two neighbouring pixels is larger
// than the distance between those pixels across the surface. The frame that
// comes out of those derivatives stops describing the surface, and the normal
// map then bends the normal along axes that have nothing to do with the
// material - which reads as the normal map inverting at a fixed distance from
// the camera, and which no amount of mip clamping or parallax tuning can fix,
// because neither of those is what is wrong. The distance it starts at depends
// on the depth buffer's precision and on how obliquely the surface is seen, not
// on the resource pack.
//
// The vertex tangent has none of that to worry about: it comes from the quad
// itself, and perspective-correct interpolation of it is exact on a flat
// triangle.
//
// On by default, since it is a correctness fix rather than a look. Turning it
// off restores the derivative frame, which is worth doing only to compare the
// two on the same scene.
//
// This option is about the material frame only. The frame the water surface is
// drawn in comes from the same per-face encoding and is not affected by it: the
// water surface has no resource pack to fall back on, so it always uses the
// frame the face has, and the option would otherwise have to mean two things.
#define PBR_TANGENT_ATTRIBUTE
#ifdef PBR_TANGENT_ATTRIBUTE
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in lit.vsh and lit.fsh.
#endif

// Whether to perturb the surface normal with the normal map, which is what
// makes the surface detail react to the light direction.
#define PBR_NORMAL_MAP

// Whether to use the smoothness and F0 stored in the specular map, which is
// what gives materials their roughness-driven highlights.
#define PBR_SPECULAR

// How strong the specular reflection is. 1.0 is the physically correct value,
// but a correct dielectric only reflects about 4% of the light that hits it,
// and Steadfast tonemaps its highlights down on top of that, so a physically
// correct highlight is far less visible than most people expect from a
// "reflective" material. Raise this if materials still look flat.
#define PBR_SPECULAR_STRENGTH 2.0 // [1.0 1.25 1.5 2.0 2.5 3.0 4.0 6.0]

// How big the sun and the moon are, as far as the highlight they make on a
// surface is concerned.
//
// Both are treated as points, which is why a polished block shows a highlight
// the size of a single pixel instead of the disc a mirror really shows: the sun
// covers about half a degree of sky, and that angle is what should spread the
// highlight out. This widens the specular lobe by that angle, so a mirror shows
// a disc of the sun's true size and a rough surface - whose lobe is far wider
// already - is left as it was.
//
// 1.0 is the sun's real angular size and is what the option is for. 0.0 is the
// point light this used to be, for comparing the two; larger values exaggerate
// the disc for the look of it, like a photographer's starburst. The moon is
// close enough to the sun in size to share the setting.
//
// Only the highlight is affected. The sun and moon drawn in the sky are a disc
// of their own and do not change size with this.
#define PBR_LIGHT_SIZE 1.0 // [0.0 1.0 2.0 3.0 4.0 6.0 8.0]

// Whether to weight the diffuse light by the part of it that the surface did
// not reflect, which is what keeps diffuse and specular from adding up to more
// light than arrived.
//
// Fresnel is the term that decides the split: a surface reflects a fraction of
// the light that hits it and lets the rest through into the material, and that
// transmitted part is what the diffuse response is made of. Steadfast adds the
// two together without that split, which is why a shiny surface can be brighter
// than the light falling on it, and why a metal - which reflects most of the
// light and should have almost no diffuse response at all - still takes half a
// diffuse response and reads as shiny plastic rather than as metal.
//
// Off by default because it changes the brightness of everything with a
// specular map at once. Turning it on is worth pairing with a specular strength
// of 1.0 above: that is the value at which the budget is balanced, and 2.0 was
// only ever a way of fighting the tonemapper without it.
//
// Note that this makes bright metals (gold, silver, aluminium) noticeably
// darker in caves and at night, which is correct - a metal that is not reflecting
// anything and is not lit by anything is dark - but it is a large enough change
// in look to be worth trying rather than assuming.
//#define PBR_ENERGY_CONSERVATION
#ifdef PBR_ENERGY_CONSERVATION
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in diffuse.glsl.
#endif

// Whether materials that the resource pack gives no usable specular data for
// should fall back to a plain dielectric instead of being left with no surface
// response at all.
//
// This is what makes a resource pack that only ships normal maps, or that only
// ships specular maps for some of its blocks, still look like it has materials
// everywhere. Turn it off if you would rather see exactly what the resource
// pack authored, matte blocks included.
#define PBR_DEFAULT_MATERIAL

// The roughness used for those fallback materials. Lower is glossier.
#define PBR_DEFAULT_ROUGHNESS 0.5 // [0.1 0.15 0.2 0.3 0.4 0.5 0.65 0.8 1.0]

// F0 for the fallback materials, and the floor applied to dielectrics. 0.04 is
// the reflectance of ordinary glass and plastic, and is what a dielectric
// should be reflecting; a resource pack that leaves the green channel at zero
// is asking for a surface that reflects nothing, which no real material does.
const float PBR_DEFAULT_F0 = 0.04;

// Whether to look up the LabPBR hardcoded metal types (iron, gold, copper, and
// so on). With this off, those materials are shaded as albedo-based metals
// instead, which is a much closer approximation than treating a metal as a
// dielectric.
#define PBR_METALS

// Whether to add the emission stored in the alpha channel of the specular map.
#define PBR_EMISSION

// Whether the emission in a specular map is used on any block, or only on the
// blocks the game's own lighting already treats as light sources.
//
// On by default, and this is the LabPBR rule: the alpha channel is the resource
// pack saying "this part of my texture emits", and it is how a pack makes an ore
// vein, a rune or a lamp's glass glow. An ore is not a light source in the game,
// so a rule that asked for one would mean the channel could never do the thing it
// exists for. See PBR_PORTING.md 164.
//
// Off is the older behaviour, kept as the escape hatch rather than as a default:
// a pack, or a texture a mod generated, that paints emission where it did not
// mean to - or that leaves the channel at its maximum by accident - would have
// every such sprite light up. Turn this off if something glows that should not,
// and the emission is then only added where the game's own lighting already
// calls the block a light source.
#define PBR_EMISSION_ANY_BLOCK

// How bright that emission is.
//
// LabPBR stores emission as a fraction of the surface color, and on its own
// that is rarely bright enough to read as something lit from within - the
// tonemapper compresses it straight back down. Raise this to make emissive
// materials actually glow.
#define PBR_EMISSION_STRENGTH 4.0 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0]

// Whether blocks that emit light should glow with their own color.
//
// This is what makes glowstone, sea lanterns, lava, torches, and the like look
// like they are lit from within rather than merely brightly lit, and unlike the
// emission above it needs nothing from the resource pack.
//
// Iris and OptiFine mark a face that can emit light by making the block light
// coordinate of its lightmap negative, which is the only signal available for
// this. Note that this lights up the block itself, not its surroundings: the
// light it casts on neighbouring blocks is already part of the block lighting.
#define BLOCK_EMISSION
#ifdef BLOCK_EMISSION
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in lit.fsh.
#endif

// How bright block self-emission is. Values above 1.0 push the surface into
// overbright territory, which is what a light source should look like.
#define BLOCK_EMISSION_STRENGTH 1.5 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0]

// How far the normal map is allowed to bend the surface normal. Raise this if
// the surface detail is there but too subtle to notice, or lower it if the
// lighting looks noisy.
#define PBR_NORMAL_STRENGTH 1.0 // [0.5 0.75 1.0 1.25 1.5 2.0]

// The deepest mip level the material maps are sampled at.
//
// The space between sprites in the material atlases is empty, and an empty
// texel is black. Black is not a neutral value for a normal map: it decodes to
// a tangent-space direction of (-1, -1) with no Z at all, which is a strong
// fixed tilt rather than a flat normal. As distance grows, the mip level the
// maps are sampled at grows with it, and once those texels reach past the
// sprite the sample picks up that black - which is what makes a surface's
// normal map appear to invert beyond a particular distance.
//
// A higher-resolution resource pack reaches that mip sooner, so the artifact
// moves closer as the pack gets sharper. That is the signature to check for.
//
// 0 keeps every sample in the sharpest level, which makes the contamination
// impossible. Raise it only if you would rather have the mip filtering back.
#define PBR_MATERIAL_MAX_LOD 0 // [0 1 2 3]

// The mip level at which the normal map has faded out to a flat surface. The
// fade starts at 40% of this value and completes here.
//
// Keeping the samples in the sharpest mip means they can no longer be blurred
// out by distance, so they would alias instead. Fading the perturbation to flat
// over this range is the equivalent of that missing blur, and it is what stops
// distant surfaces from shimmering.
//
// The level this is measured against is the true one for the fragment's
// distance, not the level actually sampled, so it fades in the same place no
// matter what PBR_MATERIAL_MAX_LOD is set to. The Material detail limit debug
// view shows the same number, scaled by a fixed eighth - level 8 is white and
// everything past it saturates - which is how to place this exactly: pick the
// level at which the surface stops looking like it has any detail left.
#define PBR_NORMAL_FADE_LOD 2.0 // [1.0 1.5 2.0 2.5 3.0 4.0 6.0]

// Whether what the material maps and the base texture are sampled at is moved
// along the direction the fragment is seen from, by the height the resource pack
// stores in the alpha channel of its normal map.
//
// A block face is a flat surface with a picture of a shape on it, and everything
// this file reads - the normal, the roughness, the reflectance, the emission,
// the colour - is read at the fragment's own coordinate. The height channel is
// the part of a material that says the shape is not flat: LabPBR stores, per
// texel, how far the surface really sits below the face, with 1.0 meaning "not
// at all". This option is what makes that claim visible. The coordinate is moved
// to where the eye's ray meets the shape, so the near wall of a groove hides the
// part of it behind, a mortar line shows its own side, and the other channels are
// read from the texel the eye is actually looking at rather than from the one the
// face is drawn at.
//
// Off by default, and it is the one material option that costs real time rather
// than a fetch here and there: the march below is a loop of texture reads per
// fragment of every block in the world, and its length is a setting of its own.
// It is also the one that needs something from the resource pack that the rest of
// this file can do without - a pack that ships no height channel has nothing to
// displace, and turning this on for one of those pays the march to draw exactly
// the picture it drew without it. The height debug view is the way to see whether
// a pack has one.
//
// The height is not the displacement. A texel at 1.0 sits at the face and does
// not move; a texel at 0.0 sits a full PBR_PARALLAX_DEPTH below it. Nothing can
// rise above the face, so what this draws is grooves, seams and mortar lines
// rather than stones standing proud of a wall.
//#define PBR_PARALLAX
#ifdef PBR_PARALLAX
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in lit.fsh, where the
	// displaced coordinate replaces the fragment's own.
#endif

// How many steps the march takes across the height field, before the crossing it
// finds is refined.
//
// This is the coarse half of the cost and the first half of the quality: each
// step reads one height and compares it against the ray, and the first step that
// lands below the surface ends the march. A larger number therefore finds a
// shallow groove that a smaller one walks straight past - which reads as a groove
// that is there from one side and gone from another - and it costs one texture
// read per step for every covered fragment of the world.
//
// Thirty-two is the default because it is where the refinement below has enough to
// work with on the resource packs this was set up against, and because it is also
// the width of the surface's staircase. The crossing can only be found between two
// samples, so the displaced surface is a set of steps one spacing apart - and at a
// grazing angle a spacing is several texels of the sprite, spread across several
// pixels of the screen, which is what "plates stacked up the surface" is. Two things
// answer that and this is the budget both draw on: the march starts from a per-pixel
// offset within its first sample so that the staircase is noise rather than bands
// (see PbrParallaxDither), and its samples are crowded towards the shallow end of the
// depth, where a height map's crossings actually are (see PbrParallaxMapping). So
// raising this raises the resolution of the staircase itself, and halving it is the
// quickest way to feel what that resolution costs: at 4 the deepest parts of a height
// map disappear, and the displacement starts to look as though it switches on and off
// as the camera turns.
//
// Note what the top of the range costs. This is the one multiplier on the whole
// feature: the step count times one height read - four, if Smooth parallax is on -
// per covered fragment, and the self-shadow march takes half of this again on top.
// 128 steps is there for a machine that can afford it and for the look of the thing,
// not because 128 is a reasonable default.
#define PBR_PARALLAX_STEPS 32 // [4 8 12 16 24 32 48 64 96 128]

// How many times the crossing found above is halved again, by a binary search
// between the last step that was still above the surface and the first that was
// below it.
//
// The march stops at the first sample past the crossing, so what it finds is within
// one step of the answer - and the march also *starts* somewhere inside its first
// step, per pixel, so that the error of the coarse half is different for every pixel
// instead of the same across a band of them. This is the option that removes that
// error: each halving of the bracket takes it down by a factor of two for one more
// texture read, which makes this the cheapest quality in the file. Eight of them
// leave an eighth of a step, and nothing about a height field shows at that size.
//
// Which is why it can look as though it does nothing: at the bottom of its range
// what is left is the noise the march's start put there, and at the top it is gone;
// the step count above is the other half, and it is the one that decides whether
// there are grooves to refine at all.
//
// The march also crowds its samples towards the shallow end of the depth, which is
// where a height map's crossings are (see PbrParallaxMapping), so what is left for
// this to clean up is the last of the staircase and the deep end of the range.
#define PBR_PARALLAX_REFINE 8 // [2 4 6 8 12 16 24 32]

// Whether the height the march reads is interpolated between the texels of the
// height map, or taken from the texel the coordinate lands in.
//
// On is the smoother of the two: the height between two texels is a ramp, so the
// surface the ray meets has no edge at a texel boundary, and the displaced
// coordinate moves continuously as the camera does. It is also a claim the data
// does not make - the pack stores one height per texel - and the ramp is visible
// as a ridge along the border of a groove whose two sides store very different
// heights.
//
// ⚠️ The interpolation is this file's own - four texel fetches and three mixes per
// step - and it has to be, because the atlas it reads is not filtered. The loader
// builds the material maps with nearest-neighbour sampling, so that a sprite can
// never blend into the sprite beside it, which means a texture() or textureGrad()
// call against them returns the single texel the coordinate lands in however it is
// written. This option asking the sampler to interpolate, which is what it did
// first, therefore changed nothing at all: the two halves of it were the same
// picture. It costs four reads per step instead of one, which is worth knowing
// before turning it on for a weak GPU.
//
// Off reads the texel itself, which is the height map as the pack authored it:
// each texel is a flat plate at its own height, the surface is a staircase by
// construction, and the displaced coordinate steps from one plate to the next as
// the camera moves. That is not a defect - it is what a 16 pixel height map of a
// lumpy surface is - but it is where the sparkle along the edges of a deep groove
// comes from, and it is the setting to compare against when a displacement looks
// suspiciously smooth.
//
// Off by default, for two reasons and one of them is the cost: this is the one
// option that multiplies the whole feature, four height reads per step where the
// other half of it needs one, on every covered fragment of the world and on both
// marches when the self-shadow is on. The other is that the plates are what the
// pack actually authored, and at the step counts this ships with the staircase is
// no longer the widest thing in the picture. Turn it on when a groove's edge
// sparkles and the terraces are what you notice: it trades the reads for the ramp.
//#define PBR_PARALLAX_SMOOTH
#ifdef PBR_PARALLAX_SMOOTH
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in PbrParallaxHeight.
#endif

// How far the height field reaches below the face, as a fraction of the sprite
// the height map belongs to, at a texel whose height is 0.
//
// This is the one number that has to be guessed. A height map says how the shape
// varies but never how tall it is, and the block it was authored for is the only
// thing that could say - so what is left is a setting, and the two ends of it are
// a mortar line and a carving. The fraction is of the sprite, which on a full block
// face is the face itself: a twentieth of a sprite is about a twentieth of a block,
// which is the depth of a seam, and 1.0 - the top of the list - is a groove a whole
// block deep, whose sides are longer than the surface they are cut into. Everything
// past about a third reads as a hole rather than as a carving. It is turned into the
// coordinate's own units by the size the sprite has in the atlas - see the
// conversion in PbrParallaxMapping, which is where a fraction of an atlas was read
// as a fraction of a sprite for one batch and the surface came out deformed.
//
// LabPBR does give one number for it: the standard says a height of 0 is a depth
// of 25% of the texture, which makes 0.25 - in the list below - the scale the
// format itself asks for. The default is a little shallower than that, and it is
// a depth at 1.0 rather than an average: a resource pack that uses only the top
// tenth of the range, which many do, displaces a tenth of what this says.
//
// Raise it and the shape deepens until the surface reads as carved stone; raise
// it past the point where the sides of a groove are longer than the surface and
// the wall starts to look like a sheet of paper with holes in it, which is the
// parallax artefact proper. Lower it and the displacement fades back into
// something a normal map could have said more cheaply.
#define PBR_PARALLAX_DEPTH 0.2 // [0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5 0.65 0.8 1.0]

// The ceiling on how deep a displacement is ever allowed to be, as a fraction of
// the sprite. It works with PBR_PARALLAX_DEPTH and not instead of it: the depth
// above says how deep the pack's shape is, this says the most the picture should
// ever lean, and the march works in whichever of the two is lower.
//
// At the defaults the depth is the lower one, so this does nothing until the depth
// is raised past it - set PBR_PARALLAX_DEPTH to 1.0 and this to 0.1 to see what it
// does. The top of its list is past a whole block, which is deeper than anything a
// height map should be read as; it is there so that the ceiling is never the thing
// that stops a pack from being read the way it was authored.
//
// It is a bound on the *depth*, and that is the point of it: what it must not be is
// a bound on how far the ray travels, which is the same thing as a bound on the
// angle it meets the surface at, and a ray at a shallower angle than the view is a
// ray through a shallower field. Written that way - which it was - the relief went
// visibly flat the more nearly parallel to the surface the view got. See the note
// where the displacement is built in PbrParallaxMapping.
#define PBR_PARALLAX_MAX_OFFSET 0.5 // [0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5 0.6 0.8 1.0 1.2]

// The distance in blocks out to which the displacement is applied, fading out
// over the last half of it.
//
// Past a certain distance a pixel covers more than one texel of the height map,
// and what the displacement computes stops meaning anything: the height one texel
// has is not visible from where the camera is, and the coordinate the march finds
// differs from the fragment's own by less than the texel the filter was going to
// mix in anyway. What is left is the cost - a loop of texture reads per fragment
// over most of the screen - and the noise of a coordinate that wanders inside a
// texel.
//
// Sixteen blocks is the default because that is where the effect stops being
// visible on a 16 pixel resource pack at a normal field of view. Raise it for a
// high resolution pack, whose texels stay resolvable much further out; lower it
// to 8 to see how much of the frame's cost the march was. It is a distance in the
// pack's own sky light and shadow units, which is to say metres.
#define PBR_PARALLAX_DISTANCE 16.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0 96.0 128.0]

// Whether the height field shadows itself: a texel that stands above the ones
// behind it, seen from the sun, darkens them.
//
// The displacement above is a change of shape, and a shape that is lit from one
// side and not the other needs to cast its own shadow or it reads as painted on.
// A mortar line displaced by the option above is a step in a wall, and the sun
// meets the step from the side it is on: the texels beyond it are in its shadow
// and should be darker for it. This is a second march, from the displaced point
// towards the light rather than from the eye, and it is the only thing in the
// pack that darkens the direct light for a reason the shadow map cannot see -
// the shadow map knows about blocks, and this is a shape inside one.
//
// On by default, because what it draws is the part of the displacement that no
// other channel can say: a groove's own side, going from lit at its lip to dark at
// its floor, in the one direction the pack's painted shading is usually wrong
// about. It costs half of what the displacement costs again, at half the step
// count, on the fragments the displacement covers - so the way out of it, if the
// frame rate matters more than the shape, is this switch rather than a lower step
// count: turning it off leaves the displacement exactly as it was.
#define PBR_PARALLAX_SHADOW
#ifdef PBR_PARALLAX_SHADOW
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in PbrParallaxShadow.
#endif

// How much of the direct light the height field is allowed to take away.
//
// A self-shadow here is a soft thing and this is its depth. 1.0 is a texel
// standing in the way of the sun for as much of the light as the geometry allows;
// lower values keep some of the light, which reads as a shallower carving and is
// the setting to reach for if the grooves look painted in rather than cut in.
// Below about a quarter the shadow is doing more to hide the displacement than to
// explain it.
//
// Has no effect while PBR_PARALLAX_SHADOW is off.
#define PBR_PARALLAX_SHADOW_STRENGTH 0.85 // [0.25 0.5 0.65 0.75 0.85 1.0]

// Whether to scale the indirect light that reaches a fragment by the ambient
// occlusion the resource pack baked into the blue channel of the normal map.
//
// That channel is the third of the three things LabPBR stores in a normal map -
// X and Y are the normal, alpha is the height, and blue is occlusion - and it is
// baked from the block's own geometry: the inside of a brick, the corner of a
// plank, the gaps between leaves. None of that is present in the lighting
// Steadfast computes on its own, because Minecraft's per-vertex ambient occlusion
// only knows about block corners and the shadow map only knows about the sun.
//
// This is off by default, as it is the one PBR feature that changes how bright
// familiar blocks are: a pack that bakes strong occlusion makes the world read
// darker than Steadfast's original rendering, and whether that looks like the
// depth it is meant to be or like a bug depends entirely on the pack. Use the
// occlusion view under PBR_DEBUG to see what a pack actually authored before
// deciding.
//
// Only indirect light is occluded. Sunlight is left to the shadow map and to the
// parallax height field, both of which know where the light comes from, so a
// sunlit surface is never darkened twice.
//#define PBR_MATERIAL_AO
#ifdef PBR_MATERIAL_AO
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in diffuse.glsl.
#endif

// How much of that occlusion is applied. 1.0 uses the channel exactly as the
// resource pack authored it; lower it if the pack overdoes the effect.
// Has no effect while PBR_MATERIAL_AO is off.
#define PBR_MATERIAL_AO_STRENGTH 1.0 // [0.25 0.5 0.75 1.0]

// Whether to add the light that scatters through a thin surface, using the
// amount stored in the blue channel of the specular map.
//
// LabPBR splits that channel at 64.5/255: below it the value is porosity, above
// it the material lets light through. Leaves, grass, paper, and similar thin
// materials are what use the upper range, where the stored value is the
// scattering amount itself - 65/255 arrives as 0.255, 254/255 as 0.996 - and
// what the effect adds is the glow of a backlit leaf: the light comes through
// the surface instead of bouncing off it. In PbrSubsurfaceScatter that same
// number drives both the brightness and the width of the glow - the light is
// weighted by exp(-(1 - sss) * PBR_SSS_EDGE_FALLOFF * |NdotL|) - so the glow is
// brightest where the surface is edge-on to the sun and narrows as the stored
// value rises. See the note on the phase term there for what picks the
// direction the glow is strongest in.
//
// Steadfast already has a cruder version of this for foliage, chosen by block ID
// (see SUBSURFACE_SCATTERING, LEAVES and GROUND_FOLIAGE in materialIDs.glsl,
// and the NdotL remapping in DirectLighting). This option is what makes the
// effect follow the texture instead, so that a pack can mark one leaf or one
// plant as thin, and it is what adds the directional glow on top of the
// existing all-round brightening.
//
// A material with nothing stored in that channel scatters nothing, so a pack
// that does not support this renders exactly as it did before.
//#define PBR_SUBSURFACE
#ifdef PBR_SUBSURFACE
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in diffuse.glsl.
#endif

// How much of that scattered light is added.
//
// 0.7 is the value this effect was tuned at in the pack it was modelled on.
// Raise it for a stronger glow through leaves, lower it if foliage looks like it
// is lit from the inside rather than from the sun.
#define PBR_SSS_STRENGTH 0.7 // [0.0 0.25 0.5 0.7 1.0 1.5 2.0]

// Whether a surface that the resource pack marked as porous gets darker while
// it is wet, which is what makes brick, dirt, wood and the like look soaked
// after rain instead of merely shiny.
//
// LabPBR stores porosity in the lower half of the specular map's blue channel
// (0 to 64 out of 255, where 0 is not porous at all and 64 is fully porous). A
// porous surface is one whose light response comes from scattering inside the
// material rather than off its surface, and water filling those pores takes that
// scattering away - so the surface darkens, and what is left is the wet sheen.
//
// The darkening is scaled by the sky light, which is what keeps it outdoors: a
// torch-lit cellar does not dry out differently from a torch-lit cellar that
// happens to be under a storm. This is the pack's own convention and matches
// what Steadfast already does with rain elsewhere.
//
// On by default. It shows itself in rain, and only on the materials a pack
// marked as porous, so turning it off only matters for a pack that overdoes it.
#define PBR_POROSITY_WETNESS
#ifdef PBR_POROSITY_WETNESS
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in diffuse.glsl.
#endif

// How much darker a fully porous surface gets when it is fully wet and fully
// exposed to the sky. This is the value the effect was tuned at in the pack it
// was modelled on.
const float PBR_WETNESS_DARKENING = 0.66;

// Whether ice and other translucent solids take their surface response from the
// material maps, instead of from the assumption that they reflect nothing.
//
// Ice is drawn by the translucent pass, so it never reached the material model
// in this file: TranslucentLighting starts every material at a reflectance of
// 0.0, gives water 0.1 and gives glass its own GLASS_F0 floor (translucent.glsl),
// which leaves ice with no specular response at all beyond the grazing Fresnel
// that every surface has. With this on, ice reads its
// reflectance and its normal from the resource pack like any other block, and
// the reflections it already had become the reflections of the material the
// pack authored.
//
// Water is deliberately left out of this. Steadfast's water is an animated
// surface whose normal comes from its own wave model, and the 0.1 it uses is a
// documented compromise; a pack's water material describes a thinner and much
// smoother surface than the one being drawn, so mixing the two does not produce
// the water the pack intended either.
//
// On by default. Turn it off to see an icy biome the way the resource pack left
// it.
#define PBR_TRANSLUCENT
#ifdef PBR_TRANSLUCENT
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in lit.fsh and
	// translucent.glsl.
#endif

// Whether the environment a material reflects gets a direction and a roughness,
// instead of being a flat wash of the ambient light.
//
// PbrAmbientSpecular below is a stand-in for image-based lighting that is cheap
// enough to run everywhere, and it is honest about being one: it reflects the
// light around the fragment equally in every direction, so a surface reflects
// exactly the same thing whichever way it faces, and roughness only scales how
// much of it there is. Turning this on asks the sky model for the colour along
// the reflected ray instead, which is what makes a polished surface outdoors
// look like something reflecting a sky rather than like something lit by it.
//
// By itself this reflects the sky and not the world: the reflection is looked up
// in the sky model along the reflected ray, so a metal outdoors picks up the sky
// and anything indoors or underground picks up nothing but its own ambient
// light. PBR_SSR below is what adds the world.
//
// It is applied in a composite pass rather than where the surface is drawn -
// composite3, which includes environment_reflection.glsl, and which the rest of
// the pack calls the deferred pass - because that is the first point at which the
// depth buffer describes a finished frame - see the note on PBR_SSR. The material
// it needs (normal, roughness, reflectance) is written into two buffers by the
// programs that draw surfaces, and read back there.
//
// Noticeably more expensive than the term it replaces: one sky model evaluation
// per covered pixel. Off by default for that reason. PBR_REFLECTIONS_STRENGTH is
// the control for how visible it is, and this pack ships with it turned down.
//#define PBR_REFLECTIONS
#ifdef PBR_REFLECTIONS
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in copy_and_fog.fsh.
#endif

// How strong that reflection is. 1.0 is the value it was tuned at.
#define PBR_REFLECTIONS_STRENGTH 0.25 // [0.25 0.5 0.75 1.0 1.5 2.0]

// The same, for a metal.
//
// A metal gets its own because the strength above is not describing metals at
// all. It is there to hold back a wash of environment that used to land on every
// surface in the scene, and a metal is the case where the reflection is the
// material rather than a sheen over it - a held-back metal does not read as a
// restrained one, it reads as a dull one. The reference packs give metals no
// such factor, so 1.0 is the value that matches them.
//
// Turn it down if metals come out too bright in a scene, which is a judgement
// about the scene rather than about the physics.
#define PBR_METAL_REFLECTION_STRENGTH 1.0 // [0.25 0.5 0.75 1.0 1.5 2.0]

// How far a rough surface bends the reflected ray towards its own normal, as a
// fraction of the roughness range.
//
// This defaults to 0.0, which is to say it does nothing, and it should stay
// there. What it does at 1.0 is distort the reflection: a surface of roughness
// 0.2 has its reflected ray pulled a fifth of the way towards the normal - the
// mix factor is roughness * this option, in PbrReflectionDirection - and the
// reflection of anything in front of it arrives shifted and misshapen even
// though the thing reflected was in plain sight.
//
// It was written to stand in for roughness, on the reasoning that a rough
// surface reflects an average of the sky over it and looking straight up is
// that average. The problem is that it is not what roughness does. A GGX lobe
// is centred on the mirror direction and spread around it; bending the centre
// moves the reflection, which no amount of roughness does. The blur is what
// spreads it, and the blur is separate - see PBR_REFLECTION_BLUR.
//
// With the normal map off, a block face is flat and its reflection should be a
// plain mirror. Any remaining distortion is this, which is how it was found.
//
// Raise it and the distortion comes back; there is no reason to.
#define PBR_REFLECTIONS_ROUGHNESS 0.0 // [0.0 0.5 0.75 1.0]

// Whether a reflection may include the world and not only the sky, by tracing
// the reflected ray through the depth buffer.
//
// This is possible here only because Steadfast applies its reflections in the
// deferred pass, after the opaque scene has been drawn and the depth buffer is
// complete. An opaque surface could not trace against the frame it is being
// drawn in, since that frame is still being filled; tracing the previous frame
// instead costs one frame of lag, so whatever has just come into view is not in
// the reflection yet. That is the same compromise the water reflections make,
// and the reason the sea looks right most of the time and briefly wrong when
// you spin around.
//
// A trace can only find what is on screen, so a ray that leaves the view or
// lands on nothing falls back to the sky, which is what the reflection would
// have been without this.
//
// The trace is by a wide margin the most expensive thing in the pack: it runs on
// every smooth pixel, at PBR_SSR_STEPS steps each, whether or not it finds
// anything. It ships on, with PBR_REFLECTION_SMOOTHNESS_MIN keeping most of a
// world out of it; turn that limit down first, and this option off second.
#define PBR_SSR
#ifdef PBR_SSR
	// The test below is what makes Iris
	// register this as a boolean option. The actual use is in copy_and_fog.fsh.
#endif

// The most the reflection may be spread out, in pixels.
//
// A rough surface does not reflect what a mirror reflects: a whole cone of
// directions arrives at the same pixel, and one sharp sample of that cone shows
// the mirror image the surface should not have. Spreading the sample over the
// cone is what makes a brushed or frosted metal read as brushed or frosted
// rather than as a mirror with its colours dimmed, and at 0.0 the reflection is
// as sharp as it is with no material data at all.
//
// The radius depends on roughness and not on distance, which is worth knowing
// before wondering why a distant reflection is not blurrier: a cone of a given
// angle covers about the same number of pixels whatever it lands on, because the
// screen-space size of the cone grows exactly as fast as the thing it spreads
// over shrinks.
//
// Only surfaces the reflection gate lets through pay for this, which is a small
// part of any scene - see PbrReflectionSmoothness. Each of those pays eight
// samples instead of one.
#define PBR_REFLECTION_BLUR 64.0 // [0.0 16.0 32.0 48.0 64.0 96.0]

// How many steps the reflection trace may take.
//
// Only the material reflections use this; the water reflections keep their own
// budget - the fixed 24 in lib/raytrace.glsl, which is not an option - because
// spending this many steps on the water and on every smooth pixel of the screen
// are two very different propositions. More steps find more
// hits and refine the ones they find better, and the cost is paid whether or not
// anything is found at all.
#define PBR_SSR_STEPS 24 // [8 12 16 24 32]

// How much sky a surface has to see before it reflects any of it.
//
// This is what keeps sky reflections out of caves and interiors. Minecraft's sky
// light spreads sideways under an overhang and passes straight through glass, so
// a fragment can be lit as if it were outdoors while nothing of the sky is
// actually visible from it - which is what a polished block on the floor of a
// shallow cave reflecting a noon sky looks like. Requiring nearly full sky
// light, and fading in over the tenth below that value rather than switching on
// at a threshold, is what stops that. The fade is PbrSkyExposure in
// reflections.glsl, and its width is fixed at a tenth whatever this is set to,
// so lowering the option moves the whole ramp down with it.
//
// Note the one case this cannot fix: a surface lit through a glass window has a
// sky light of 15, exactly like one standing in the open, and no lighting
// information available here can tell the two apart. Lower this if you would
// rather have reflections indoors and put up with them in caves.
#define PBR_REFLECTION_SKY_MIN 0.9 // [0.0 0.5 0.75 0.85 0.9 0.95 1.0]

// How smooth a surface has to be before it reflects the sky at all.
//
// The reflectance on its own is not a gate: it falls off as a surface gets
// rougher but it never reaches zero, and the ground is always seen at a glancing
// angle, where the Fresnel term rises towards 1.0 whatever the surface is. The
// two together are what put a wash of sky colour over stone and dirt, and what
// made a whole landscape look faintly frosted rather than dull. A surface as
// rough as a stone has no business reflecting the sky, and nothing short of a
// threshold that reaches zero says so.
//
// The curve is Sundial's, from the "diffuse weight" it gives a solid surface in
// its Composite0, which is where the numbers come from. PbrReflectionSmoothness
// turns this pack's roughness back into a smoothness first - 1 - sqrt(roughness),
// the inverse of the decode in PbrDecode - and returns the square root of how far
// past the threshold that smoothness is. At the default 0.5 the threshold is a
// smoothness of 0.5, so anything rougher than about 0.25 in this pack's roughness
// reflects nothing whatever. A metal's threshold is half of that - a smoothness
// of 0.25, a roughness of about 0.56 - which is what keeps a brushed metal
// reflecting at all.
//
// Raise it to restrict reflections to shinier blocks and lower it to let them
// onto duller ones; 0.0 disables the gate and leaves the old fall-off alone.
#define PBR_REFLECTION_SMOOTHNESS_MIN 0.5 // [0.0 0.25 0.5 0.6 0.7 0.8 0.9]



// Replaces the shaded image with a visualisation of the material data, which is
// the quickest way to find out whether a resource pack actually provides what
// an effect needs. Height draws the raw alpha of the normal map, so a pack with
// no height channel for a block reads as one flat value there. LabPBR stores 1.0
// for "not displaced" and an absent channel holds 0 everywhere, and both of those
// read as flat - so a pack without height data is not broken here, there is
// simply nothing for a displacement to use.
#define PBR_DEBUG_NONE 0
#define PBR_DEBUG_HEIGHT 1
#define PBR_DEBUG_SMOOTHNESS 2
#define PBR_DEBUG_F0 3
#define PBR_DEBUG_NORMAL 4
#define PBR_DEBUG_MIP 5
#define PBR_DEBUG_TANGENT_NORMAL 6
#define PBR_DEBUG_MATERIAL_AO 7
#define PBR_DEBUG_SUBSURFACE 8
#define PBR_DEBUG_EMISSION 9

// The environment reflection by itself, with the rest of the picture taken away.
//
// It exists because the reflection is the one thing in this pack that cannot be
// judged by looking at the finished image. Everything else can: a normal map
// that is wrong looks wrong, a shadow that is wrong looks wrong. A reflection
// that is being blurred wrongly and a reflection that is being traced wrongly
// both come out looking like a strange reflection, and there is no way to tell
// which from the picture - which is how seven attempts at its blur were made
// without once establishing whether the blur was running at all.
//
// Unlike the others this one is not read by the surface programs: it replaces
// the finished frame in composite3, which is the pass that applies the
// reflection - see environment_reflection.glsl. Turning it on leaves the sky and the terrain as the reflection
// alone, so what is shown is exactly what the reflection contributed, at four
// times its strength so that a faint one can be seen.
#define PBR_DEBUG_REFLECTION 11
#define PBR_DEBUG PBR_DEBUG_NONE // [PBR_DEBUG_NONE PBR_DEBUG_HEIGHT PBR_DEBUG_SMOOTHNESS PBR_DEBUG_F0 PBR_DEBUG_NORMAL PBR_DEBUG_MIP PBR_DEBUG_TANGENT_NORMAL PBR_DEBUG_MATERIAL_AO PBR_DEBUG_SUBSURFACE PBR_DEBUG_EMISSION PBR_DEBUG_REFLECTION]

// How much of its diffuse response a metal loses, over both the direct light
// and the indirect light around it.
//
// A metal has no diffuse response at all: light either reflects off it or it is
// absorbed, and everything that gives a metal its appearance is in the
// reflection. A surface that keeps some of its diffuse and gains a reflection on
// top does not look like a restrained metal - it looks like a metal with
// something smeared over it, because that is exactly what such a surface is: a
// bright, coloured, blurred film sitting on a body that is still scattering
// light the way a plastic would.
//
// This used to default to half, on the grounds that the pack had no environment
// reflection and a fully metallic surface would be left with its highlight alone
// and read as a black hole in a cave. The pack has had that reflection for a
// while now, and a metal in a lit cave picks up the block light around it
// through PbrAmbientSpecular, so the reason for stopping half-way is gone and
// the halfway value is what the smearing looked like.
//
// 0.0 = metals keep all of their diffuse response (shiny plastic look)
// 1.0 = metals lose their diffuse response entirely (physically correct)
#define PBR_METAL_DIFFUSE 1.0 // [0.0 0.25 0.5 0.75 1.0]

// The main switch. It is defined for the block atlas programs (see PBR_ATLAS in
// the gbuffers wrappers), whose coordinates index into the block atlas grid, and
// for the ones that opt in through PBR_MATERIALS_ANY_TEXTURE - a program whose
// own texture already is the material's texture, so the coordinate indexes it
// directly without needing to know anything about an atlas. The player, its
// armour and whatever it holds are drawn by such a program, and this is how
// Mellow and Sundial give them materials too. See
// gbuffers_entities_translucent.fsh for why that program takes this route
// rather than PBR_ATLAS.
//
// gbuffers_entities is the one program that takes PBR_ATLAS without a block
// atlas under it, and it does so as an experiment on whether the loaders bind
// the _n and _s a resource pack ships beside an entity's own texture; the note
// there says how to tell whether it works. Note that this also puts it on
// lit.vsh's mc_midTexCoord path, which that same note says entities do not have.
//
// Distant Horizons and Voxy terrain deliberately do not opt in through either
// route: what they sample is not the texture their coordinate belongs to. Held
// items do not take the PBR_MATERIALS_ANY_TEXTURE route either - they come in
// through PBR_ATLAS in gbuffers_hand.fsh, under PBR_HAND_ITEMS.
//
// When neither is defined, every declaration below is removed by the
// preprocessor and no PBR data is read or paid for.
#if (defined(PBR_ATLAS) || defined(PBR_MATERIALS_ANY_TEXTURE)) && PBR_FORMAT != PBR_OFF
	#define PBR_SURFACE


#endif

// The decoded material properties of a fragment.
struct PbrSurface {
	// Perceptual roughness, where 0.0 is a mirror and 1.0 is fully diffuse.
	float roughness;
	// Reflectance at normal incidence.
	vec3 f0;
	// 1.0 for hardcoded and albedo-based metals, 0.0 for dielectrics.
	float metalness;
	// Which metal, as the byte the specular map's green channel carried: 230-237
	// for the hardcoded ones, 238 for the albedo-based ones, and 0 for a
	// dielectric. metalness above says whether there is a metal here; this says
	// which one, which is what PbrMetalF82 needs for the colour it reflects at a
	// grazing angle. It is carried rather than recomputed because the byte it
	// came from is gone by the time the reflection is applied: the deferred pass
	// (composite3) has only the two material buffers this file's callers write -
	// a normal and a roughness in one, a reflectance in the other - and the
	// byte's only place left is the alpha of the reflectance, written as
	// metalID / 255 at the bottom of lit.fsh and read back in
	// environment_reflection.glsl.
	float metalID;
	// Emission strength, 0.0 when the material does not emit.
	float emission;
	// 1.0 when f0 has to be taken from the surface albedo rather than from the
	// specular map, which is how LabPBR stores albedo-based metals.
	// PbrResolveAlbedo() folds this in once the surface color is known.
	float albedoMetal;
	// How much of the direct light reaches this fragment through the height
	// field, where 1.0 means nothing is in the way. Only the direct light is
	// affected: the height field does not occlude the sky.
	float selfShadow;
	// The ambient occlusion baked into the material's normal map, where 1.0
	// means the texel is open to the sky and 0.0 means it sits in a crevice.
	// Only indirect light is scaled by it, and only while PBR_MATERIAL_AO is
	// on; see PbrMaterialOcclusion. Surfaces with no material data carry 1.0,
	// which is the neutral value.
	float materialAO;
	// How much of the light that reaches this surface scatters through it
	// instead of reflecting off it, where 0.0 means none of it does. Read from
	// the upper range of the specular map's blue channel, and only used while
	// PBR_SUBSURFACE is on. A surface with no material data carries 0.0, which
	// is what keeps the scattered light out of every other material.
	float sss;
	// How porous this material is, from 0.0 (not porous) to 1.0 (fully porous),
	// normalised from the lower half of the same channel as sss above. Only used
	// while PBR_POROSITY_WETNESS is on, and 0.0 for a surface with no material
	// data.
	float porosity;
};

// The neutral material: fully rough, no specular reflection, no emission,
// nothing in the way of the light, and no occlusion. This is what lighting
// paths without PBR data use, and it reproduces Steadfast's original
// appearance exactly.
PbrSurface PbrNone() {
	return PbrSurface(1.0, vec3(0.0), 0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0);
}

// The factor that the indirect lighting is scaled by for this fragment.
//
// This is a function rather than a plain field of PbrSurface so that the
// strength control and the "this surface has no material data" case live in one
// place. PbrNone() carries an occlusion of 1.0, which makes the whole thing the
// identity, so every lighting path that is not a block atlas surface keeps the
// original rendering untouched. With PBR_MATERIAL_AO off, the compiler removes
// the multiplication entirely.
//
// Declared outside the PBR_SURFACE guard below on purpose: the struct and this
// helper have to exist for every program, if only so that the non-PBR callers
// can pass PbrNone() through them.
float PbrMaterialOcclusion(PbrSurface pbr) {
	#ifdef PBR_MATERIAL_AO
		return mix(1.0, pbr.materialAO, PBR_MATERIAL_AO_STRENGTH);
	#else
		return 1.0;
	#endif
}

// Whether a sample from the specular atlas carries no material data at all.
//
// Where a sprite has no specular map - which is the normal state of affairs for
// anything a resource pack does not cover, modded foliage and grass included -
// the atlas holds whatever it was built with, and both colours it can be are
// meaningless as materials:
//
//   - Black means no reflectance, no scattering and no porosity.
//   - White means total reflectance on every channel at once, which is a
//     material that reflects everything, scatters everything and is porous
//     everywhere - not something a pack authors.
//
// The alpha is meaningless too, whichever end of the range the atlas left it at.
// Emission happens to survive that on its own: a missing sprite reads as
// transparent black, and LabPBR defines an alpha of zero as "emits nothing".
// The porosity and the scattering do not - they read the blue channel - so
// telling an empty atlas region apart from a real material is what the two
// rejected colours above are for. Rejecting both with any alpha, rather than
// only the opaque pair, is what keeps a block the pack never covered from
// scattering all of the light or darkening as though it were porous everywhere.
//
// The price is that a material which really is fully emissive and has exactly
// zero reflectance, zero scattering and zero porosity is read as having no data
// instead, and the same for a material that is exactly white on all three. Both
// are indistinguishable from an empty atlas region, so a pack that authors them
// has to move one of those three channels off the extreme.
bool PbrMissingSpecular(vec4 specularSample) {
	vec3 rgb = specularSample.rgb;

	float maxChannel = max(max(rgb.r, rgb.g), rgb.b);
	float minChannel = min(min(rgb.r, rgb.g), rgb.b);

	// Black, with any alpha: nothing recorded on any channel.
	if (maxChannel < 1.0e-3) {
		return true;
	}

	// White, with any alpha: every channel at its maximum at once.
	if (minChannel > 0.999) {
		return true;
	}

	return false;
}

// Deliberately not named PI, as the sky and water code both declare local
// constants with that name.
const float PBR_PI = 3.14159265359;

// The weights used wherever a reflectance has to be reduced from a colour to a
// single number. Rec. 709, matching what the rest of the pack uses for luma.
const vec3 PBR_LUMINANCE = vec3(0.2126, 0.7152, 0.0722);

// Schlick's approximation of the Fresnel term: reflectance rises towards 1.0 at
// grazing angles.
//
// Declared out here rather than next to the BRDF below, which is where it
// belongs thematically, because a pass with no block atlas has no PBR_SURFACE
// and the guard below would remove it - and composite3 includes this file
// without ever drawing a block. ⚠️ Nothing outside this file calls it as things
// stand: reflections.glsl carries its own PbrReflectionFresnel, and that is what
// the environment reflection actually evaluates. What keeps this out here is
// that everything it depends on is a constant, so the guard costs nothing to
// cross.
vec3 F_Schlick(vec3 f0, float u) {
	float f = 1.0 - u;
	float f2 = f * f;
	float f5 = f2 * f2 * f;
	return f0 + (vec3(1.0) - f0) * f5;
}

#ifdef PBR_SURFACE

// Declared as plain, top-level uniforms on purpose. Iris and OptiFine detect
// that a shader pack wants PBR material data by scanning its source for these
// two declarations, and only then build and bind the normal and specular
// atlases.
uniform sampler2D normals;
uniform sampler2D specular;

#ifdef PBR_POROSITY_WETNESS
	// The wetness of the terrain, where 0.0 is dry and 1.0 is soaked.
	//
	// Iris and OptiFine both track this from the weather and provide it without
	// anything being declared in the pack's properties, so this is only a
	// declaration and not a request. Declared inside the feature's own guard so
	// that it is not paid for in programs that never compile the code below.
	//
	// The cloud layer wants the same value - it uses it for how thick the clouds
	// are - so the macro tells it that this has already been declared.
	#define WETNESS_DECLARED
	uniform float wetness;
#endif

// The screen-space derivatives that the material decoding needs.
//
// These have to be taken once, before any discard and outside non-uniform
// control flow, because dFdx and dFdy are undefined after either; lit.fsh takes
// them at the top of its PBR block for that reason. Nothing below samples with
// an implicit level of detail - every fetch in this file is textureGrad or
// texelFetch - so one set of gradients serves the whole file, and passing them
// around is what lets the parallax march sample with an explicit level of
// detail from inside its loop.
struct PbrGradients {
	// The texture coordinate and the position are in different spaces and the
	// pair is kept apart for that reason: the coordinate derivatives are in the
	// atlas space that texCoord itself is in (lit.fsh passes the matrixed
	// `texcoord`), and the position derivatives are of the camera-relative world
	// position lit.fsh reconstructs from the depth buffer, so they are a world
	// direction per pixel and not a texture quantity.
	vec2 ddxTexCoord;
	vec2 ddyTexCoord;
	vec3 ddxPosition;
	vec3 ddyPosition;
	// The mip level the material maps would be sampled at. Recorded here because
	// it cannot be recovered from the gradients once they have been scaled, and
	// the normal map's fade is driven by it.
	float lod;
};

// The mip level a texture with these gradients is sampled at.
//
// The atlas size comes from the sampler itself, so this makes no assumption
// about the resource pack. Note that the level depends on the texture's size as
// well as on distance, which is why anything that goes wrong at a particular
// mip level moves closer as the resource pack gets sharper.
float PbrMaterialLOD(PbrGradients gradients) {
	vec2 atlasSize = vec2(textureSize(normals, 0));
	vec2 ddx = gradients.ddxTexCoord * atlasSize;
	vec2 ddy = gradients.ddyTexCoord * atlasSize;

	return log2(max(max(length(ddx), length(ddy)), 1.0e-8));
}

// Scales the gradients so that no sample lands deeper than PBR_MATERIAL_MAX_LOD.
//
// This deliberately depends on nothing but the option: an earlier version of
// this used the sprite's bounds to allow deeper mips in the middle of a sprite,
// but fell back to doing nothing when those bounds were not usable, and a fix
// that can silently do nothing is worse than no fix at all.
//
// The position gradients are left alone - they are the true derivatives of the
// surface, and the tangent frame needs them unmodified.
PbrGradients PbrMaterialGradients(PbrGradients gradients) {
	float scale = exp2(
		min(gradients.lod, PBR_MATERIAL_MAX_LOD) - gradients.lod);

	return PbrGradients(
		gradients.ddxTexCoord * scale,
		gradients.ddyTexCoord * scale,
		gradients.ddxPosition,
		gradients.ddyPosition,
		gradients.lod);
}

// Takes the one set of screen-space derivatives the fragment stage is allowed to
// have, for a texture coordinate in the atlas space texCoord is in and for a
// position in camera-relative world space, and records the mip level those
// derivatives call for. Both are the caller's to supply: lit.fsh passes the
// matrixed `texcoord` and the camera-relative position it rebuilt from the depth
// buffer. See PbrGradients for what the two pairs mean.
PbrGradients PbrSampleGradients(vec2 texCoord, vec3 position) {
	PbrGradients gradients = PbrGradients(
		dFdx(texCoord),
		dFdy(texCoord),
		dFdx(position),
		dFdy(position),
		0.0);

	gradients.lod = PbrMaterialLOD(gradients);

	return gradients;
}

// The metal ID the albedo-based metals carry, since they have no byte of their
// own to carry - LabPBR gives 238-255 all the same meaning.
//
// 238 rather than 255 so that it sits just past the hardcoded table, which is
// the range it belongs to, and is a constant rather than a #define because it is
// not a setting: nothing about it is worth offering to a user.
const float PBR_METAL_ALBEDO = 238.0;

// F0 values for the LabPBR hardcoded metals, looked up by the byte value stored
// in the green channel of the specular map.
//
// It is reached only for a byte in 230-237, which is what lets it be an unrolled
// chain of equality tests: the dielectric case is separated out by the two
// comparisons in PbrDecode and never calls this, so the chain is paid for only
// by the materials that use the feature.
vec3 PbrMetalF0(int metalID) {
	if (metalID == 230) return vec3(0.78, 0.77, 0.74); // Iron
	if (metalID == 231) return vec3(1.00, 0.90, 0.61); // Gold
	if (metalID == 232) return vec3(1.00, 0.98, 1.00); // Aluminum
	if (metalID == 233) return vec3(0.77, 0.80, 0.79); // Chrome

	if (metalID == 234) return vec3(1.00, 0.89, 0.73); // Copper
	if (metalID == 235) return vec3(0.79, 0.87, 0.85); // Lead
	if (metalID == 236) return vec3(0.92, 0.90, 0.83); // Platinum
	if (metalID == 237) return vec3(1.00, 1.00, 0.91); // Silver

	return vec3(0.0);
}

// Builds a tangent frame around the surface normal from the screen-space
// derivatives of the world position and the texture coordinate. This is the
// technique from Christian Schüler's "Normal Mapping Without Precomputed
// Tangents".
//
// This is the fallback frame, and there are two ways to arrive at it: it is what
// PbrAttributeFrame calls when the geometry's own tangent is degenerate -
// Minecraft's entity format has none, and some mods leave the attribute at zero
// - and it is what lit.fsh builds directly when PBR_TANGENT_ATTRIBUTE is off.
// PbrAttributeFrame is preferred wherever the geometry has a tangent, because
// this one depends on differentiating a position that lit.fsh had to reconstruct
// from the depth buffer first, and the depth buffer's precision runs out at a
// distance.
//
// Note that it derives the frame from the UV mapping, which is also why it stays
// correct for modded models that Steadfast knows nothing about - a modded model
// that supplies no tangent still gets a usable frame this way.
//
// The frame is also what the parallax mapping uses to turn a view ray into a
// displacement along the texture coordinates, so it is built whenever either
// feature needs it. When neither does, the compiler discards the whole thing.
mat3 PbrCotangentFrame(vec3 worldNormal, PbrGradients gradients) {
	vec3 dp1 = gradients.ddxPosition;
	vec3 dp2 = gradients.ddyPosition;
	vec2 duv1 = gradients.ddxTexCoord;
	vec2 duv2 = gradients.ddyTexCoord;

	// Project the position derivatives onto the plane of the surface and pair
	// them with the texture coordinate derivatives. The results are
	// perpendicular to the normal by construction, so this replaces the
	// Gram-Schmidt orthogonalization that a precomputed tangent would need.
	vec3 dp2perp = cross(dp2, worldNormal);
	vec3 dp1perp = cross(worldNormal, dp1);

	vec3 tangent = dp2perp * duv1.x + dp1perp * duv2.x;
	vec3 bitangent = dp2perp * duv1.y + dp1perp * duv2.y;

	// Normalize both vectors with a single reciprocal square root.
	float maxLength = max(dot(tangent, tangent), dot(bitangent, bitangent));

	if (maxLength < 1.0e-12) {
		// Degenerate UV mapping (a zero-area triangle, or a fragment where the
		// derivative was lost). Fall back to an arbitrary but consistent frame
		// so that we never produce NaNs.
		vec3 helper = abs(worldNormal.y) < 0.99
			? vec3(0.0, 1.0, 0.0)
			: vec3(1.0, 0.0, 0.0);

		tangent = normalize(cross(helper, worldNormal));
		return mat3(tangent, cross(worldNormal, tangent), worldNormal);
	}

	float invLength = inversesqrt(maxLength);
	return mat3(tangent * invLength, bitangent * invLength, worldNormal);
}

#ifdef PBR_TANGENT_ATTRIBUTE
	// The same frame, built from the tangent the geometry itself carries.
	//
	// worldTangent is that tangent in world space, with the handedness in w, and
	// it is degenerate for geometry that has no tangent at all - Minecraft's
	// entity format does not carry one, and some mods leave it at zero. That
	// case falls back to the derivative frame above rather than producing a
	// frame full of NaNs, so that a mob or a modded model still gets the
	// material response it can get.
	//
	// The handedness exists because a tangent alone does not say which way the
	// bitangent points; it is what the loader stores in w for exactly this
	// purpose.
	//
	// The bitangent is cross(tangent, worldNormal) * worldTangent.w, which is
	// the convention Iris documents for at_tangent - its own example is written
	// out as
	//
	//   float handedness = clamp(at_tangent.w * inf, -1.0, 1.0);
	//   vec3 bitangent = cross(tangent, normal) * handedness;
	//
	// and the two operands of a cross product cannot be swapped without
	// negating the result. For Minecraft's texture convention the result is the
	// direction the texture's V axis increases in, which is the axis the normal
	// map's green channel describes, and PbrTangentNormalXY does land the green
	// channel on it with no sign of its own.
	//
	// ⚠️ The operands used to be the other way round here, so every frame this
	// pack built had its second axis pointing at -v rather than +v. One axis
	// mirrored and nothing else is what was reported from the game: a ridge with
	// the sun to its south-east cast its shadow to the south-west rather than to
	// the north-west, and the displaced coordinate moved the wrong way across
	// the texture in the same axis, which reads as the surface being flat rather
	// than as a displacement. The derivative frame above has its second axis at
	// +v by construction, so the two frames agreeing is the check that says this
	// line is right: before it, they were negatives of each other in that axis,
	// which is what the note on PbrTangentNormalXY recorded as the open question
	// batch 392 was testing.
	mat3 PbrAttributeFrame(
		vec3 worldNormal,
		vec4 worldTangent,
		PbrGradients gradients
	) {
		vec3 tangent = worldTangent.xyz;

		if (dot(tangent, tangent) < 1.0e-8) {
			return PbrCotangentFrame(worldNormal, gradients);
		}

		tangent = normalize(tangent);

		vec3 bitangent = cross(tangent, worldNormal) * worldTangent.w;

		return mat3(tangent, bitangent, worldNormal);
	}
#endif

// The tangent-space XY of the normal map at this coordinate, decoded to the
// -1 to 1 range.
//
// LabPBR normals use the DirectX convention, where green points down in the
// texture - which is exactly the direction that the texture coordinate's V axis
// increases in Minecraft, so the green channel is meant to map straight onto the
// bitangent with no flip. The code here does no flip of its own: .xy is decoded
// and handed to the frame as (x, y), so green is the frame's second axis and
// nothing else.
//
// That the frame's second axis really is the atlas's +v was the open question
// batch 392 was testing, and PbrAttributeFrame is where the answer is: the
// operand order of its cross product had that axis pointing the other way, so
// everything read through here - the normal map, and the parallax march, which
// takes the same frame - was mirrored in one axis until it was corrected.
vec2 PbrTangentNormalXY(vec2 texCoord, PbrGradients gradients) {
	vec2 encoded = textureGrad(
		normals,
		texCoord,
		gradients.ddxTexCoord,
		gradients.ddyTexCoord).xy;

	return encoded * 2.0 - 1.0;
}

// Perturbs the interpolated face normal using the normal map.
vec3 PbrNormal(mat3 frame, vec2 texCoord, PbrGradients gradients) {
	#ifndef PBR_NORMAL_MAP
		return frame[2];
	#else
		vec2 tangentNormalXY = PbrTangentNormalXY(texCoord, gradients);

		// Past a certain distance the normal map is finer than a pixel, so the
		// perturbation it describes cannot be resolved and sampling it only
		// produces shimmer. Fade it out to the flat surface normal instead,
		// which is what a correctly filtered normal map converges to anyway.
		//
		// The level this is keyed on is the true one rather than the level
		// actually sampled, so the fade still applies when PBR_MATERIAL_MAX_LOD
		// holds the sample at a sharp level.
		float detail = 1.0 - smoothstep(
			PBR_NORMAL_FADE_LOD * 0.4,
			PBR_NORMAL_FADE_LOD,
			gradients.lod);

		// Scaling the tangent plane components tips the normal further away
		// from the surface for the same texture, which is how the strength
		// control works. Z is reconstructed from the scaled components below,
		// so a normal that ends up longer than one is simply renormalized.
		tangentNormalXY *= PBR_NORMAL_STRENGTH * detail;

		// LabPBR leaves Z out of the texture and requires reconstructing it,
		// since the blue channel stores material ambient occlusion instead.
		// Clamping keeps the vector valid if a resource pack over-saturates the
		// XY channels.
		float tangentNormalZ = sqrt(max(
			0.0,
			1.0 - dot(tangentNormalXY, tangentNormalXY)));

		// A texel holding a flat normal - 128 in both of the XY channels - decodes
		// to (0, 0, 1) and reproduces the original face normal exactly. A pack
		// that ships no normal map at all leaves the atlas holding whatever the
		// loader puts there, and the blank it leaves is the black texel
		// PBR_MATERIAL_MAX_LOD describes, which decodes to (-1, -1) and is not
		// flat.
		return normalize(frame * vec3(tangentNormalXY, tangentNormalZ));
	#endif
}

#ifdef PBR_PARALLAX

// Whether the sprite bounds a program handed over describe a sprite at all.
//
// A half extent of zero is how a program says "this coordinate is not from the
// block atlas and there are no bounds to give" - see
// gbuffers_entities_translucent.fsh, which takes PBR_MATERIALS_ANY_TEXTURE rather
// than PBR_ATLAS and so declares no mc_midTexCoord to measure one from. Anything
// larger than half the atlas cannot be a sprite either.
//
// Both of those cases mean no parallax rather than unlimited parallax. What the
// march needs the sprite for is a scale: PBR_PARALLAX_DEPTH and
// PBR_PARALLAX_MAX_OFFSET are fractions of a sprite, and the coordinate they would
// move is in atlas units, so a program with no sprite has no way to turn one into
// the other and is given the coordinate it came in with. A program that wants
// parallax has to hand over bounds it can stand behind.
bool PbrSpriteBoundsUsable(vec4 spriteBounds) {
	return spriteBounds.z > 1.0e-4 && spriteBounds.w > 1.0e-4
		&& spriteBounds.z <= 0.5 && spriteBounds.w <= 0.5;
}

// The coordinate a sample is taken at, held inside the sprite it belongs to.
//
// This is the whole reason the sprite bounds are carried as far as here. The
// material maps and the base texture are atlases, and the space beside a sprite
// is either another block's sprite or - in the material atlases - the black the
// atlas is built with, which decodes to a strong fixed tilt and to no emission,
// no scattering and no porosity at all. A sample that walks off its sprite
// therefore reads a material belonging to a block that is not there, which shows
// up as a band of the neighbouring block along the edge of a face.
//
// What this does about that is *wrap*, rather than shorten the displacement or
// box the coordinate into the sprite's rectangle. The three are not equivalent,
// and the difference is depth that holds together against depth that does not:
//
//   * Wrapping keeps the whole displacement. Every texel of a face displaces by
//     what the height field says it should, wherever on the face it sits.
//   * It is also what the pattern itself does. Minecraft's block textures tile
//     with themselves across block boundaries - the mortar at the left edge of a
//     stone brick sprite is the mortar at the right edge of the copy beside it -
//     so a ray that runs past the edge of the sprite is looking at the same
//     pattern one tile over, and wrapping is that tile exactly.
//   * Shortening the displacement instead was measured to flatten the relief it
//     is most needed on. On a 16 pixel stone brick sprite at a forty-five degree
//     view, every one of the 42 texels on the sprite's border that carries height
//     had its displacement cut to nothing, and the cut tapered back to full only
//     four texels in. The relief of a tiled block is the seam at its border, so
//     that is that seam drawn with depth in the middle of a face and flat at its
//     edge, which reads as the surface deforming rather than as shape.
//
// The wrap takes the sprite's whole rectangle as its period, so a coordinate that
// is already inside the sprite comes back exactly where it was - which is what
// makes this invisible everywhere except past the edge. The half texel at each
// edge is then clamped rather than wrapped, because a filtered sample reaches half
// a texel to either side of its coordinate and that half texel must stay inside the
// sprite; the clamp can only ever move a sample by less than a texel, at the very
// border, which is why it costs nothing visible.
vec2 PbrParallaxWrap(vec2 texCoord, vec4 spriteBounds) {
	if (!PbrSpriteBoundsUsable(spriteBounds)) {
		return texCoord;
	}

	vec2 atlasSize = vec2(textureSize(normals, 0));
	vec2 minCoord = spriteBounds.xy - spriteBounds.zw;
	vec2 size = 2.0 * spriteBounds.zw;
	vec2 inset = min(0.5 / atlasSize, spriteBounds.zw * 0.25);

	// fract is x - floor(x), so this wraps in both directions.
	vec2 wrapped = minCoord + fract((texCoord - minCoord) / size) * size;

	return clamp(wrapped, minCoord + inset, minCoord + size - inset);
}

// The height the material stores for a coordinate: the alpha channel of the
// normal map, where LabPBR writes 1.0 for a texel that is not displaced and 0.0
// for one that sits the full PBR_PARALLAX_DEPTH below the face.
//
// The coordinate is wrapped into its sprite first, so the march below walks the
// pattern as it tiles rather than the atlas, and nothing read here can leave the
// sprite the fragment belongs to. PbrParallaxWrap is where that is argued.
//
// The two halves of PBR_PARALLAX_SMOOTH differ here and nowhere else. Both read
// the height with texelFetch, at level 0, and neither lets the sampler filter
// anything - because it does not. The loader builds the material maps as a
// nearest-neighbour atlas, so that one sprite can never blend into the sprite
// beside it, and a texture() or textureGrad() call against it therefore returns
// the single texel the coordinate lands in however it is written. The interpolation
// that this option is named for is between those texels, so it has to be this
// shader's own: four fetches and three mixes, which is what the reference packs do
// as well. With it off, the one texel the coordinate lands in is the height map as
// the pack authored it, one flat plate per texel and a staircase across the face.
float PbrParallaxHeight(vec2 texCoord, vec4 spriteBounds) {
	vec2 sampleCoord = PbrParallaxWrap(texCoord, spriteBounds);
	ivec2 atlasSize = textureSize(normals, 0);
	ivec2 texelMax = atlasSize - 1;

	#ifdef PBR_PARALLAX_SMOOTH
		// The texel centres are at half-integer coordinates, so this is the
		// position of the sample among them and the fraction across the cell it
		// landed in. texelFetch does not clamp, so the four taps are held to the
		// map; the wrap and the half texel it keeps from the sprite's edge have
		// already made that unnecessary, and this is what happens if they stop.
		vec2 texelPos = sampleCoord * vec2(atlasSize) - 0.5;
		vec2 texel00 = floor(texelPos);
		vec2 f = texelPos - texel00;

		float h00 = texelFetch(normals, clamp(ivec2(texel00), ivec2(0), texelMax), 0).a;
		float h10 = texelFetch(normals, clamp(
			ivec2(texel00 + vec2(1.0, 0.0)), ivec2(0), texelMax), 0).a;
		float h01 = texelFetch(normals, clamp(
			ivec2(texel00 + vec2(0.0, 1.0)), ivec2(0), texelMax), 0).a;
		float h11 = texelFetch(normals, clamp(
			ivec2(texel00 + vec2(1.0, 1.0)), ivec2(0), texelMax), 0).a;

		return mix(mix(h00, h10, f.x), mix(h01, h11, f.x), f.y);
	#else
		ivec2 texel = clamp(ivec2(sampleCoord * vec2(atlasSize)), ivec2(0), texelMax);

		return texelFetch(normals, texel, 0).a;
	#endif
}

// A number in [0, 1) that is the same for a pixel every frame and unrelated to the
// numbers its neighbours get, which is what the parallax marches start from.
//
// It is here because a fixed number of samples along a ray quantizes where the
// crossing can be found to those samples, and a quantized crossing is a staircase.
// Hashing the pixel into the start of the march moves that staircase per pixel, and
// a staircase that moves per pixel is noise: noise is what the refinement below can
// average away, and bands are what it cannot. See where it is used in
// PbrParallaxMapping for the whole of that argument.
//
// Deliberately a function of the pixel and not of the frame, so that a still scene
// is still: a dither that changed every frame would trade the bands for shimmer.
// It is the hash from Dave Hoskins' "Hash without Sine", with the constants he
// gives for it.
float PbrParallaxDither() {
	vec3 p3 = fract(vec3(gl_FragCoord.xy, gl_FragCoord.x) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);

	return fract((p3.x + p3.y) * p3.z);
}

#ifdef PBR_PARALLAX_SHADOW
// How much of the height field the light finds in its way, as a fraction of the
// height range: the width of the ramp between nothing in the way and all of it.
//
// A shaping constant rather than an option. 0.06 of a height field is about one
// texel of a sixteen texel sprite, which is as narrow as the ramp can be before
// every step in the field becomes an edge between lit and dark.
const float PBR_PARALLAX_SHADOW_SOFTNESS = 0.06;

// How much of the direct light reaches a displaced point through the height
// field, where 1.0 is nothing in the way.
//
// This is the second march, from the point the first one found towards the light
// rather than from the eye: the light's own ray, in the same frame the height
// field lives in, climbing towards the face. At every step the field's height
// there is compared against the height the ray has climbed to, and the largest
// amount by which the field stands over the ray is how much of the light it is
// standing in the way of.
//
// The largest, rather than the first, and soft rather than hard: the height field
// is a surface of steps, and a hard test makes every step either fully lit or
// fully dark, which reads as dirt in the grooves rather than as a shadow. Taking
// the deepest obstruction along the ray and turning it into an amount with a ramp
// is what gives a groove a side that goes from lit at its lip to dark at its
// floor.
//
// depth is the depth the first march found the surface at, and it is also the
// whole of the room the light's ray has to work with: climbing that far puts it
// back at the face. depthScale is the depth the field's full range stands for, the
// same number PbrParallaxMapping worked in.
float PbrParallaxShadow(
	vec2 texCoord,
	float depth,
	float depthScale,
	vec4 spriteBounds,
	mat3 frame,
	vec3 lightDirection
) {
	// The light, in the frame the height field lives in.
	vec3 tangentLight = vec3(
		dot(lightDirection, frame[0]),
		dot(lightDirection, frame[1]),
		dot(lightDirection, frame[2]));

	// A light at or below the face is not lighting this surface at all - the
	// diffuse term is already zero for it - and a point that the first march left
	// at the face itself has no field to climb out of.
	if (tangentLight.z <= 1.0e-4 || depth <= 1.0e-6) {
		return 1.0;
	}

	// How far across the surface the light's ray travels per unit of height it
	// climbs, which is the same slope the view ray was built from and for the same
	// reason: a fraction of the sprite first, then the sprite's own size, exactly as
	// PbrParallaxMapping does it. It is not capped, and that is deliberate: a cap
	// here would be a cap on the angle, and capping the angle of a ray is the same
	// thing as making the field under it shallower.
	//
	// It is not held inside the sprite here either: every read below goes through
	// PbrParallaxHeight, which wraps, so a step that runs past the edge of the
	// sprite reads the same pattern one tile over rather than the block next door.
	vec2 lightSlope = tangentLight.xy / tangentLight.z * depthScale;
	lightSlope *= 2.0 * spriteBounds.zw;

	// Half the parallax march's budget, because this one is looking for the shape
	// of an obstruction rather than for a crossing: it is read at every step and
	// the answer is the largest of them, so a step missed here costs detail in a
	// shadow rather than a surface that moves as the camera turns. It starts from
	// the same per-pixel jitter the displacement march does, for the same reason:
	// a shadow whose edge is quantized to the steps is as banded as a surface is.
	float stepSize = depth / float(PBR_PARALLAX_STEPS / 2);
	float stepJitter = PbrParallaxDither() * stepSize;
	float penetration = 0.0;

	for (int i = 0; i < PBR_PARALLAX_STEPS / 2; i++) {
		float climb = stepJitter
			+ (depth - stepJitter) * (float(i + 1) / float(PBR_PARALLAX_STEPS / 2));

		// The ray's own height. It starts on the surface, which the first march
		// put at the field's height there, so climbing raises it by exactly as
		// much as it has climbed.
		float rayHeight = 1.0 - depth + climb;

		float fieldHeight = PbrParallaxHeight(
			texCoord + lightSlope * climb, spriteBounds);

		penetration = max(penetration, fieldHeight - rayHeight);
	}

	return 1.0 - smoothstep(
		0.0,
		PBR_PARALLAX_SHADOW_SOFTNESS,
		penetration) * PBR_PARALLAX_SHADOW_STRENGTH;
}
#endif /* PBR_PARALLAX_SHADOW */

// Where the eye's ray meets the height field buried in a face, and how much of
// the direct light the field lets through to that point.
//
// The coordinate returned is the one the material maps and the base texture are
// to be read at; selfShadow is the fraction of the direct light that reaches that
// point, where 1.0 is nothing in the way. See PBR_PARALLAX for what the whole
// thing is for and the options above for what each number does.
//
// The march is steep parallax, and it is steep rather than a single shifted
// sample because a single sample cannot describe a groove: it moves the whole
// face by its own height, and a groove's near wall ends up drawn where its far
// wall is. What is wanted is where the ray first goes below the field, which is
// the point at which the near wall starts hiding the far one. That is what the
// loop computes: it walks down the ray in equal steps of height, reads the field
// at each one, and stops at the first step that has gone under.
vec2 PbrParallaxMapping(
	vec2 texCoord,
	vec4 spriteBounds,
	mat3 frame,
	PbrGradients gradients,
	// The fragment's position relative to the camera. The eye sits at the origin
	// of that space, so the direction from the fragment towards the eye is this,
	// negated. lit.fsh works its own view direction out the same way, further
	// down, and the two have to agree.
	vec3 viewPosition,
	// The direction towards the sun or moon, in world space.
	vec3 lightDirection,
	out float selfShadow
) {
	selfShadow = 1.0;

	// A program with no usable sprite has no depth scale to apply: both options
	// below are fractions of the sprite, and the coordinate they would move is in
	// atlas units - so without the sprite there is no way to turn one into the
	// other, and the honest answer is to displace nothing. See
	// PbrSpriteBoundsUsable for which programs that is.
	if (!PbrSpriteBoundsUsable(spriteBounds)) {
		return texCoord;
	}

	// A texel at the reference height is the face itself, and the eye's ray meets
	// it there: there is nothing in front of it to hide it and nothing behind it
	// to be hidden, so the coordinate stays where it is. That is also most of the
	// world on most resource packs - a height map is flat wherever the pack had
	// nothing to say - and returning here is what keeps the whole march off those
	// texels rather than paying for it to arrive at the same answer.
	if (PbrParallaxHeight(texCoord, spriteBounds) >= 1.0 - 1.0e-4) {
		return texCoord;
	}

	vec3 viewDirection = normalize(-viewPosition);

	// The view ray in the frame the height field lives in, which is the surface's
	// own axes: the third one is the face normal, so a positive z here is "out of
	// the face, towards the eye".
	vec3 tangentView = vec3(
		dot(viewDirection, frame[0]),
		dot(viewDirection, frame[1]),
		dot(viewDirection, frame[2]));

	// A face seen exactly edge on has no height field to enter, and the division
	// below would be through zero. It is also the case where nothing of the face
	// is visible anyway, so there is nothing to lose by giving the displacement
	// up outright rather than clamping the ray to some very large slope.
	if (tangentView.z <= 1.0e-4) {
		return texCoord;
	}

	// The fade at the far end of PBR_PARALLAX_DISTANCE, which is where a pixel
	// covers more than a texel and the displacement can no longer describe
	// anything the filter was not going to mix in anyway.
	float distanceFade = 1.0 - smoothstep(
		PBR_PARALLAX_DISTANCE * 0.5,
		PBR_PARALLAX_DISTANCE,
		length(viewPosition));

	if (distanceFade <= 1.0e-4) {
		return texCoord;
	}

	// The depth the whole march works in: how far below the face a texel at height
	// 0 sits, as a fraction of the sprite. It is the depth option, but never more
	// than the offset option, which is the hard ceiling on how deep a displacement
	// is allowed to be - two controls rather than one because the first is the
	// shape the pack authored and the second is the most the picture should ever
	// lean. At the defaults the depth is the lower of the two, so the ceiling does
	// nothing until the depth is raised past it.
	float parallaxDepth = min(PBR_PARALLAX_DEPTH, PBR_PARALLAX_MAX_OFFSET);

	// The whole of the displacement, as a fraction of the sprite: the lateral part
	// of the view ray, stretched by how obliquely it meets the surface - a grazing
	// ray crosses much further than it descends - and scaled by how deep the field
	// is.
	//
	// The lateral movement is *against* the side the eye is on. The eye is to one
	// side of the point being drawn, and the deeper into the surface the ray gets,
	// the further across it travels away from the eye. Reading that sign the other
	// way round turns every groove inside out, which shows up as a surface lit
	// from the wrong side rather than as a displacement.
	//
	// ⚠️ And it is not capped. A cap on how far the ray travels is a cap on the
	// angle it meets the surface at, and a ray at a shallower angle than the view
	// is a ray through a shallower field: the relief under it comes out flatter by
	// the same factor. That is what a maximum offset written here used to do, and
	// what was reported from the game was exactly that - the parallax going
	// shallower the more nearly parallel to the surface the view got, because past
	// about sixty-eight degrees the requested travel passed the cap and the whole
	// surface was scaled down with it. The reference packs never cap it: they let
	// the ray be the ray and bound the work with the step count, the distance fade
	// and the screen.
	vec2 totalOffset = -tangentView.xy / tangentView.z * parallaxDepth;
	totalOffset *= distanceFade;

	if (length(totalOffset) <= 1.0e-6) {
		return texCoord;
	}

	// And now the units. Everything above is a fraction of the sprite, and
	// everything below is the coordinate's own space, so the last step is to scale
	// by the size the sprite has in that space.
	//
	// ⚠️ This multiply is not optional and it is not small: a 16 pixel sprite in
	// a 32 x 32 sprite atlas is a thirty-second of the atlas, so without it the
	// depth above would be read as a fraction of the *atlas* - six and a half
	// sprites deep at the default rather than a fifth of one. What that looked
	// like, reported from the game, was the surface deforming: the ray walked
	// across several blocks of the atlas, so a groove was drawn with the pattern
	// of whatever the atlas had six sprites away, wrapping as it went. The
	// reference packs in this workspace all do the same conversion, each in its
	// own way - Sundial multiplies by the quad's size in atlas units, Mellow by
	// its texel scale over the sprite's atlas scale.
	vec2 spriteSize = 2.0 * spriteBounds.zw;
	totalOffset *= spriteSize;

	// The march is a fixed number of samples along a ray, and a fixed number of
	// samples means the crossing it finds can only land between them: the surface it
	// draws is a staircase whose step is one step's worth of the ray. At a grazing
	// angle a step is several texels of the sprite, so the staircase is several texels
	// wide on screen and reads as plates stacked up the surface - which is what was
	// reported from the game. The refinement below narrows the step it lands within,
	// but it cannot remove the staircase; what removes it is starting the march
	// somewhere else in the first step, per pixel, so that the staircase's edge moves
	// per pixel and stops being an edge. The two together are the whole of the
	// quality, and the reference packs do exactly this - Mellow and Bliss by
	// offsetting where their march starts, Sundial by refining after its walk.
	//
	// Where the samples *go* is the other half of it, and it is the half that costs
	// nothing to get right. The samples cannot be spread evenly over the whole depth
	// and also be where the crossings are, because a height map's texels are mostly at
	// the reference height: a pack uses the top of its range for the seams it wants
	// displaced and leaves the rest at 1.0, which is why this function can return
	// early at all. On a 16 pixel stone brick sprite, for instance, the texels that
	// carry any height at all sit between 0.89 and 1.0, so every crossing it can have
	// is within the top tenth of the depth - and an even march spends most of its
	// budget below that, on depths nothing is ever found at. Squaring the fraction
	// crowds the samples towards the shallow end: at a fifth of the depth an even
	// march of thirty-two has six samples and this one has fourteen, for the same
	// thirty-two reads. The deep end is left sparse, and the refinement below is what
	// covers it - a resource pack that uses its whole height range still gets its deep
	// grooves, they are just bracketed more coarsely before the refinement.
	//
	// The jitter is applied to the *index* rather than to the depth, so that it is one
	// sample's spacing wherever it lands: a thirty-second of the depth near the top of
	// an even march, and a small fraction of that where the crossings actually are in
	// this one. That is the same dither as before, doing less damage for the same
	// benefit.
	float dither = PbrParallaxDither();

	// The bracket the crossing is in: the last sample that was still above the field,
	// and the first that was below it. The far end starts at the full depth, which is
	// always below the field - a height cannot be negative, so 1 - h cannot exceed 1 -
	// and that is what guarantees a bracket however the field behaves.
	vec2 aboveCoord = texCoord;
	float aboveDepth = 0.0;
	vec2 belowCoord = texCoord + totalOffset;
	float belowDepth = 1.0;

	for (int i = 0; i < PBR_PARALLAX_STEPS; i++) {
		float fraction = (float(i) + dither) / float(PBR_PARALLAX_STEPS);
		float sampleDepth = fraction * fraction;
		vec2 sampleCoord = texCoord + totalOffset * sampleDepth;

		if (sampleDepth >= 1.0 - PbrParallaxHeight(sampleCoord, spriteBounds)) {
			belowCoord = sampleCoord;
			belowDepth = sampleDepth;
			break;
		}

		aboveCoord = sampleCoord;
		aboveDepth = sampleDepth;
	}

	vec2 previousCoord = aboveCoord;
	float previousDepth = aboveDepth;
	vec2 coord = belowCoord;
	float depth = belowDepth;

	// The loop above stops at the first sample past the crossing rather than at the
	// crossing, so what it found is within one sample spacing of the answer - and a
	// spacing is a thirty-second of the whole displacement at the default, at the very
	// most, and rather less than that where a crossing is likely to be. Left there,
	// the displaced surface is a staircase with steps that wide; the dither above
	// turns that staircase into noise rather than into bands, and this turns the noise
	// back into a surface. It is a binary search between the last sample above the
	// surface and the first one below it, and each halving of that bracket is one
	// sample's worth less error: this is the option that decides how clean the
	// displaced surface is, and the reason it can look like it does nothing at the
	// bottom of its range is that the staircase was the other option's problem.
	for (int i = 0; i < PBR_PARALLAX_REFINE; i++) {
		vec2 midCoord = (previousCoord + coord) * 0.5;
		float midDepth = (previousDepth + depth) * 0.5;

		if (midDepth >= 1.0 - PbrParallaxHeight(midCoord, spriteBounds)) {
			coord = midCoord;
			depth = midDepth;
		} else {
			previousCoord = midCoord;
			previousDepth = midDepth;
		}
	}

	#ifdef PBR_PARALLAX_SHADOW
		// The self-shadow is the displacement's own shading, so it fades out with
		// it: a surface whose shape has been flattened back to the face has
		// nothing left to cast anything. It starts from the wrapped coordinate,
		// which is the point the material was read at.
		selfShadow = mix(
			1.0,
			PbrParallaxShadow(
				PbrParallaxWrap(coord, spriteBounds),
				depth,
				parallaxDepth,
				spriteBounds,
				frame,
				lightDirection),
			distanceFade);
	#endif

	// Wrapped, because this is the coordinate every map below is read at and the
	// sprite is the only place its material lives. Wrapping is what lets the whole
	// displacement through: a seam at the edge of a sprite is read one tile over
	// rather than drawn flat. See PbrParallaxWrap.
	return PbrParallaxWrap(coord, spriteBounds);
}

#endif /* PBR_PARALLAX */

// Decodes the material properties of a fragment from the specular map.
//
// The albedo is deliberately not an input: albedo-based metals use the surface
// color as their reflectance, and this has to be called before the surface
// color is known (see the ordering note in lit.fsh). PbrResolveAlbedo()
// finishes that case off later.
PbrSurface PbrDecode(vec2 texCoord, PbrGradients gradients) {
	PbrSurface pbr = PbrNone();

	#if defined(PBR_SPECULAR) || defined(PBR_EMISSION) || defined(PBR_SUBSURFACE)
		vec4 specularSample = textureGrad(
			specular,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord);
	#endif

	#ifdef PBR_SPECULAR
		// A resource pack that ships no specular map for a sprite leaves the
		// atlas either black or white there, depending on how the atlas is
		// built. Neither is usable: black decodes to "no reflectance and fully
		// rough" and white to "perfect mirror", and the first of those is what
		// makes a block look like it has no surface response at all.
		//
		// Note what the test deliberately ignores: the alpha. Black is rejected
		// with any alpha, which is what keeps a transparent black region out, and
		// the price is that a material which really is emissive over a black rgb
		// is rejected along with it - see the price paragraph on
		// PbrMissingSpecular.
		#ifdef PBR_DEFAULT_MATERIAL
			bool missingSpecular = PbrMissingSpecular(specularSample);
		#else
			bool missingSpecular = false;
		#endif

		if (missingSpecular) {
			pbr.roughness = PBR_DEFAULT_ROUGHNESS;
			pbr.f0 = vec3(PBR_DEFAULT_F0);
		} else {
			// Smoothness is stored perceptually, so square it to get a
			// roughness that behaves linearly in the shading math.
			pbr.roughness = pow(1.0 - specularSample.r, 2.0);

			// Rescale the green channel back to the byte value that the artist
			// stored. Texture filtering can leave the sampled value between two
			// bytes, so the boundaries are placed half-way between neighboring
			// IDs, as LabPBR specifies.
			float green255 = specularSample.g * 255.0;

			bool hardcodedMetal = false;
			#ifdef PBR_METALS
				hardcodedMetal = green255 >= 229.5 && green255 < 237.5;
			#endif

			if (green255 < 229.5) {
				// Dielectric. F0 is stored linearly as of LabPBR 1.3, where the
				// dielectric range tops out at 229/255 (~0.898) - which is high
				// enough for gemstones, so it is deliberately not clamped lower.
				//
				#ifdef PBR_DEFAULT_MATERIAL
					// Floored: a resource pack that leaves the green channel
					// near zero is not describing a real material, as no
					// dielectric reflects nothing, and the result would be a
					// surface with no reflection at all - roughness comes from
					// the red channel and is not what this floor touches.
					pbr.f0 = vec3(max(specularSample.g, PBR_DEFAULT_F0));
				#else
					pbr.f0 = vec3(specularSample.g);
				#endif
			} else if (hardcodedMetal) {
				// Hardcoded metal, looked up from the table.
				pbr.f0 = PbrMetalF0(int(green255 + 0.5));
				pbr.metalness = 1.0;
				pbr.metalID = float(int(green255 + 0.5));
			} else {
				// Albedo-based metal. f0 is filled in from the surface color by
				// PbrResolveAlbedo(). This is also where hardcoded metals land
				// when the metal lookup is turned off, which approximates them
				// far better than treating them as dielectrics would - and it is
				// why they are given the albedo metal's ID rather than their own:
				// the table that ID would index is the one that is turned off.
				pbr.metalness = 1.0;
				pbr.albedoMetal = 1.0;
				pbr.metalID = PBR_METAL_ALBEDO;
			}
		}
	#endif

	#ifdef PBR_EMISSION
		// LabPBR stores emission as alpha directly: 0 is 0% and 254 is 100%.
		// 255 is not "more than 100%", it is the no-data value - an RGB image
		// with no alpha channel at all loads as 255 everywhere, so a pack that
		// never touched the channel has to read as "does not emit" rather than
		// as a lamp. That is the whole reason the useful range stops one short
		// of the top, and it is why this is a multiply and not a subtraction.
		// See PBR_PORTING.md 165.
		//
		// The albedo supplies the color; this only supplies the amount.
		//
		// Still behind PbrMissingSpecular: a sprite with no specular map reads
		// as transparent black, and while its alpha of zero already decodes to
		// no emission, the same guard is what keeps the porosity and the
		// scattering off data that is not there (see the block below).
		if (!PbrMissingSpecular(specularSample)) {
			pbr.emission = specularSample.a * step(specularSample.a, 0.999);
		}
	#endif

	#if defined(PBR_SUBSURFACE) || defined(PBR_POROSITY_WETNESS)
		// LabPBR packs two things into one channel and splits them at 64 out of
		// 255: below that the value is porosity, above it the surface lets that
		// much of the light through. The boundary is placed half-way between the
		// two ranges so that texture filtering between neighbouring texels
		// cannot land on it.
		//
		// The two are scaled differently on the way out. The scattering is the
		// channel as it stands, so byte 65 arrives as 0.255 and byte 254 as
		// 0.996; the porosity is normalised out of the lower range by
		// b * 255 / 64, so byte 64 - the top of that range - is 1.0.
		//
		// Both readings are skipped for a sprite the resource pack gives no
		// specular map, since the atlas value there is an artefact rather than a
		// material - taking it at face value would make every such block scatter
		// all of the light or darken as if it were porous everywhere. See
		// PbrMissingSpecular.
		if (!PbrMissingSpecular(specularSample)) {
			#ifdef PBR_SUBSURFACE
				pbr.sss = specularSample.b * 255.0 > 64.5 ? specularSample.b : 0.0;
			#endif

			#ifdef PBR_POROSITY_WETNESS
				pbr.porosity = specularSample.b * 255.0 > 64.5
					? 0.0
					: specularSample.b * 255.0 / 64.0;
			#endif
		}
	#endif

	#ifdef PBR_MATERIAL_AO
		// The normal map is sampled here not for the normal - PbrNormal takes
		// care of that - but for the occlusion LabPBR stores in its blue
		// channel. The arguments are identical to the ones PbrNormal uses (same
		// sampler, same coordinate, same gradients), so the two fetches are
		// expected to be merged into one; if materials visibly cost more with
		// PBR_MATERIAL_AO on, that merge is the first thing to check.
		pbr.materialAO = textureGrad(
			normals,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).b;
	#endif

	return pbr;
}

// Applies the albedo-based metal case, which can only be resolved once the
// surface color has been computed. This is a single mix, so it is affordable to
// call unconditionally.
PbrSurface PbrResolveAlbedo(PbrSurface pbr, vec3 albedo) {
	pbr.f0 = mix(pbr.f0, albedo, pbr.albedoMetal);
	return pbr;
}

#ifdef PBR_SUBSURFACE
	// How strongly a thin material scatters the light that enters it forwards,
	// for the Henyey-Greenstein phase function below. 0.6 is the value the
	// effect was tuned at in the pack it was modelled on, and it concentrates
	// the glow around the direction of the sun rather than spreading it evenly.
	const float PBR_SSS_PHASE_G = 0.6;

	// How quickly the glow falls off as the surface turns away from the light.
	// Higher values keep it closer to the silhouette of the leaf.
	const float PBR_SSS_EDGE_FALLOFF = 5.0;

	// The floor under the phase term, so that a thin surface still scatters
	// something when the sun is not directly behind it. Without it, a leaf lit
	// from the side would show no scattering at all, since the phase function
	// above is very nearly zero once the light is more than a few degrees off
	// the direction towards the viewer.
	const float PBR_SSS_ISOTROPIC_PHASE = 0.1;

	// The Henyey-Greenstein phase function, which describes what fraction of the
	// light that scatters inside a material comes out in a given direction.
	//
	// cosTheta is the cosine of the angle between the light's direction of travel
	// and the direction towards the viewer, so 1.0 is light that carries straight
	// on towards the camera - the sun behind a leaf, seen through it - and -1.0
	// is light that has to turn all the way around to be seen. g is how strongly
	// the material scatters forwards, where 0.0 spreads the light evenly in every
	// direction and values approaching 1.0 send nearly all of it straight on.
	float PbrPhaseHG(float cosTheta, float g) {
		float g2 = g * g;
		float denominator = 1.0 + g2 - 2.0 * g * cosTheta;

		return (1.0 - g2)
			/ (4.0 * PBR_PI * denominator * sqrt(max(denominator, 1.0e-4)));
	}

	// The light that reaches the viewer through the surface rather than off it.
	//
	// Three things decide how much of it there is, and the first is what keeps
	// the effect from touching anything that is not thin:
	//
	//   - The amount the resource pack stored, which is zero for every material
	//     that does not scatter.
	//   - How edge-on the surface is to the light. A leaf facing the sun is lit
	//     like any other surface and shows no glow; the glow belongs to the
	//     leaves seen edge-on and to the rim of the canopy.
	//   - How closely the viewer, the light and the surface line up, which is the
	//     phase term below.
	//     ⚠️ What is handed to it is dot(viewDirection, lightDirection), and
	//     lightDirection points *towards* the light - PbrSpecular uses it as
	//     NdotL, and shaders.properties builds it from lightVector - so this is
	//     the cosine between "towards the camera" and "towards the sun". That is
	//     the negative of the argument a forward-scattering phase function wants,
	//     which is the cosine between the light's direction of travel and the
	//     direction towards the viewer; with g = 0.6 the term is therefore
	//     largest when the camera and the sun are on the same side, rather than
	//     when the light has come through the surface towards the eye. The 0.1
	//     floor below is what keeps the backlit case from going dark outright.
	//     Reported rather than changed: if the glow reads as front-lit instead of
	//     as coming through the leaf, this sign is why.
	//
	// visibility is the shadow map result for this fragment, passed in so that
	// the glow cannot pass through a wall the direct light itself is blocked by.
	float PbrSubsurfaceScatter(
		PbrSurface pbr,
		vec3 worldNormal,
		vec3 lightDirection,
		vec3 viewDirection,
		float visibility
	) {
		// The scattered light is a fraction of the light that arrives, so where
		// none arrives there is nothing to scatter. This also skips the phase
		// function for every material that does not scatter in the first place.
		if (pbr.sss <= 0.0 || visibility <= 0.0) {
			return 0.0;
		}

		float NdotL = dot(worldNormal, lightDirection);

		// A material that scatters more also keeps the glow over a wider range
		// of angles, so the same value drives both how bright the glow is and
		// how quickly it fades away from the silhouette.
		//
		// ⚠️ The argument is dot(viewDirection, lightDirection), with
		// lightDirection pointing towards the light - see the third item of the
		// list above for what that does to the sign. PbrPhaseHG's own convention
		// is stated on the function, and the function is the standard one.
		float phase = max(
			PBR_SSS_ISOTROPIC_PHASE,
			PbrPhaseHG(dot(viewDirection, lightDirection), PBR_SSS_PHASE_G));

		return PBR_SSS_STRENGTH * pbr.sss * visibility * phase
			* exp(-(1.0 - pbr.sss) * PBR_SSS_EDGE_FALLOFF * abs(NdotL));
	}
#endif /* PBR_SUBSURFACE */

// A visualisation of the material data behind the PBR settings.
//
// This is the quickest way to tell whether a resource pack actually provides
// what an effect needs. Height draws the raw alpha of the normal map, so a block
// the pack gave no height channel reads as one flat value there - flat black,
// not flat grey, since black is what an empty atlas region holds - and LabPBR
// stores 1.0 for "not displaced", so both read as flat and there is nothing to
// displace. The effect is not broken, there is simply nothing to displace.
vec3 PbrDebugColor(
	mat3 frame,
	vec2 texCoord,
	PbrSurface pbr,
	PbrGradients gradients,
	// Whether the world's own lighting treats this face as a light source. Only
	// the calling shader can work that out, from the lightmap, and only the
	// emission view below reads it.
	float lightSourceSignal
) {
	#if PBR_DEBUG == PBR_DEBUG_HEIGHT
		return vec3(textureGrad(
			normals,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).a);
	#elif PBR_DEBUG == PBR_DEBUG_SMOOTHNESS
		return vec3(1.0 - pbr.roughness);
	#elif PBR_DEBUG == PBR_DEBUG_F0
		return pbr.f0;
	#elif PBR_DEBUG == PBR_DEBUG_NORMAL
		return PbrNormal(frame, texCoord, gradients) * 0.5 + 0.5;
	#elif PBR_DEBUG == PBR_DEBUG_MIP
		// The mip level the fragment's distance calls for - not the level actually
		// sampled, which PBR_MATERIAL_MAX_LOD holds at 0 by default - as a
		// greyscale ramp from level 0 (black) to a fixed level 8 (white). Blockier
		// bands are expected - the level steps once per doubling of distance.
		//
		// This is what decides where the normal map fades out.
		return vec3(clamp(gradients.lod / 8.0, 0.0, 1.0));
	#elif PBR_DEBUG == PBR_DEBUG_TANGENT_NORMAL
		// The normal map exactly as authored, decoded but before the surface's
		// tangent frame is applied - so it shows the texture's own content and
		// nothing this shader does to it. A flat normal reads as the light blue
		// of a straight-up vector.
		//
		// A tangent-space view is the way to tell a bad sample apart from a bad
		// frame: if the colour stays correct with distance but the shading does
		// not, the sample is fine and the frame is at fault. Anything with both
		// colour channels at zero is a texel that decodes to (-1, -1) rather than
		// to the flat (0, 0) - the black texel of an empty atlas region - and its
		// blue reads 0.5 because Z is reconstructed as zero, so it comes out a
		// dark blue rather than black.
		vec2 tangentXY = PbrTangentNormalXY(texCoord, gradients);
		float tangentZ = sqrt(max(0.0, 1.0 - dot(tangentXY, tangentXY)));

		return vec3(tangentXY, tangentZ) * 0.5 + 0.5;
	#elif PBR_DEBUG == PBR_DEBUG_MATERIAL_AO
		// The occlusion channel of the normal map exactly as the resource pack
		// authored it, and sampled independently of PBR_MATERIAL_AO so that it
		// can be inspected with the feature switched off - which is the state
		// the decision to switch it on has to be made in.
		//
		// Flat white means the pack ships no occlusion data for this block and
		// PBR_MATERIAL_AO has nothing to apply. Anything darker, especially
		// shading inside a sprite away from its edges, is the occlusion itself.
		return vec3(textureGrad(
			normals,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).b);
	#elif PBR_DEBUG == PBR_DEBUG_SUBSURFACE
		// The blue channel of the specular map, which is where both of the
		// things LabPBR packs into it live: values up to 64 out of 255 are
		// porosity, anything above that is how much the material scatters. Both
		// therefore appear in this one picture - a scattering surface reads as a
		// mid to bright colour, a porous one as a dark colour, and one that is
		// neither as black. The channel is shown raw rather than decoded: a fully
		// porous texel (byte 64) is a quarter-bright grey and not white, and a
		// fully scattering one (byte 254) is 0.996.
		//
		// Sampled independently of PBR_SUBSURFACE, so that a pack can be checked
		// before the option is switched on.
		return vec3(textureGrad(
			specular,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).b);
	#elif PBR_DEBUG == PBR_DEBUG_EMISSION
		// Red: the emission the material is putting on this fragment, after the
		// decoding has decided whether its data is usable at all. Green: whether
		// the world's own lighting treats this face as a light source, which is
		// what the emission is weighed against.
		//
		// This is the view to open when a block glows that should not, and the
		// two channels answer it between them:
		//
		//   - Red bright means the material's specular map is being read as
		//     emissive, and the material data is what to look at next.
		//   - Green bright means the lightmap is calling this face a light
		//     source, which is the block self-emission rather than the material.
		//   - Both black means neither is putting light here, and a glow that is
		//     still visible comes from somewhere else again - the light bleed
		//     spreading a nearby source's colour, or something outside the
		//     material model entirely.
		return vec3(pbr.emission, lightSourceSignal, 0.0);
	#else
		return vec3(0.0);
	#endif
}

#ifdef PBR_POROSITY_WETNESS
	// How much darker this fragment is because it is wet, as a fraction of its
	// light, from 0.0 for a dry or non-porous surface to PBR_WETNESS_DARKENING
	// (0.66) for one that is soaked through. The clamp above that is a formality:
	// even a fully porous, fully wet, fully sky-lit surface cannot reach it.
	//
	// Three things scale it, and each is a reason for a surface to be left
	// alone: how porous the material is (a mirror or a metal has no pores for
	// water to fill), how wet it currently is, and how much sky light reaches
	// it. That last one is what keeps a lit cellar the same in the rain as out
	// of it, and it matches how the rest of the pack treats weather.
	float PbrWetnessDarkening(PbrSurface pbr, float skyLight) {
		return clamp(
			pbr.porosity * wetness * PBR_WETNESS_DARKENING * skyLight,
			0.0,
			1.0);
	}
#endif

#ifdef PBR_SPECULAR
	// Half the angle the sun covers seen from the ground, in radians: its disc is
	// about 0.53 degrees across, so its radius is a little under a quarter of a
	// degree. This is the size a light that is not a point has in the lobe below,
	// scaled by PBR_LIGHT_SIZE.
	const float PBR_SUN_ANGULAR_RADIUS = 0.0046;

	// The GGX / Trowbridge-Reitz normal distribution function, which controls
	// the size and shape of the specular lobe.
	float D_GGX(float NdotH, float roughness) {
		float a = roughness * roughness;
		float a2 = a * a;
		float d = NdotH * NdotH * (a2 - 1.0) + 1.0;
		return a2 / (PBR_PI * d * d);
	}

	// Smith's visibility function with the height-correlated form of the
	// geometric term, divided by the 4 * NdotL * NdotV denominator of the
	// microfacet BRDF. The division is kept inside so that the caller can
	// multiply the pieces together directly.
	float V_SmithGGXCorrelated(float NdotL, float NdotV, float roughness) {
		float a2 = roughness * roughness * roughness * roughness;
		float lambdaV = NdotL * sqrt((-NdotV * a2 + NdotV) * NdotV + a2);
		float lambdaL = NdotV * sqrt((-NdotL * a2 + NdotL) * NdotL + a2);
		return 0.5 / max(lambdaV + lambdaL, 1.0e-6);
	}

	// Schlick's approximation of the Fresnel term lives above, outside the
	// PBR_SURFACE guard, where a pass with no block atlas can reach it - see the
	// note there; nothing outside this file calls it at present.

	#ifdef PBR_ENERGY_CONSERVATION
		// The fraction of the light arriving at this angle that goes into the
		// surface rather than bouncing off it, which is what the diffuse term
		// has to be weighted by.
		//
		// This is the same Fresnel term the specular lobe below uses, read the
		// other way round: what is not reflected is transmitted, and the
		// transmitted light is what lights the material from the inside.
		//
		// Reflectance is a colour and a diffuse weight has to be a single
		// number, so it is reduced to its luminance. For a dielectric that
		// hardly matters, since the reflectance is within a few percent of
		// neutral; for a metal it produces exactly the behaviour that makes
		// metals look like metals, because a bright metal then has almost no
		// diffuse response left.
		float PbrDiffuseWeight(vec3 f0, float cosTheta) {
			vec3 fresnel = F_Schlick(f0, cosTheta);
			return 1.0 - dot(fresnel, PBR_LUMINANCE);
		}

		// The same weight for the light that arrives from the environment rather
		// than from the sun. The angle that decides the split there is the one
		// between the surface and the viewer, since that is the direction the
		// light has to leave in to be seen.
		float PbrAmbientDiffuseWeight(
			PbrSurface pbr,
			vec3 worldNormal,
			vec3 viewDirection
		) {
			float NdotV = max(dot(worldNormal, viewDirection), 1.0e-4);

			return PbrDiffuseWeight(pbr.f0, NdotV);
		}

		// The weight for the direct light, evaluated at the half angle so that
		// it uses the same reflectance the specular lobe below reflects with.
		float PbrDirectDiffuseWeight(
			PbrSurface pbr,
			vec3 lightDirection,
			vec3 viewDirection
		) {
			vec3 H = normalize(viewDirection + lightDirection);

			return PbrDiffuseWeight(pbr.f0, max(dot(viewDirection, H), 0.0));
		}
	#endif /* PBR_ENERGY_CONSERVATION */

	// Direct specular reflection for the sun / moon.
	//
	// The light term is passed in pre-multiplied by the shadow map result and
	// the pack's existing sky light falloff, so that the highlight is occluded
	// in exactly the same way as the diffuse lighting, and so that we never
	// sample the shadow map twice.
	vec3 PbrSpecular(
		PbrSurface pbr,
		vec3 worldNormal,
		vec3 lightDirection,
		vec3 viewDirection,
		float lightTerm
	) {
		// A material with no reflectance at all cannot have a highlight. This
		// is the common case for resource packs without specular maps, and
		// skipping it also avoids the metal lookup above from having to be any
		// more careful.
		if (dot(pbr.f0, pbr.f0) < 1.0e-8 || lightTerm <= 0.0) {
			return vec3(0.0);
		}

		vec3 H = normalize(viewDirection + lightDirection);

		float NdotL = max(dot(worldNormal, lightDirection), 0.0);
		float NdotV = max(dot(worldNormal, viewDirection), 1.0e-4);
		float NdotH = max(dot(worldNormal, H), 0.0);
		float VdotH = max(dot(viewDirection, H), 0.0);

		// The light is behind this surface, so there is nothing to reflect.
		if (NdotL <= 0.0) {
			return vec3(0.0);
		}

		// A perfectly smooth surface collapses the specular lobe into a single
		// point and divides by zero while doing so, so keep a floor under the
		// roughness. At this value the highlight is still sharp enough to read
		// as a mirror on a polished block.
		float roughness = max(pbr.roughness, 2.0e-3);

		// The light is not a point, and this is where that shows: the sun's own
		// angular size widens the lobe, which is what turns the highlight on a
		// polished block from a single bright pixel into the disc the sun really
		// is.
		//
		// The angle is added to alpha itself and not to the roughness, because
		// alpha is the number the lobe's width is measured in: a distribution of
		// width alpha spreads the reflected light over about that angle. D_GGX
		// squares whatever it is handed - a = roughness * roughness - so what is
		// passed in below is the square root of alpha.
		//
		// Adding the angle to the roughness instead is the mistake this file made
		// first: alpha is the square of that, so the sun's own 0.0046 would arrive
		// in alpha as its square, about 2.1e-5, on a surface whose alpha is 2.5e-3
		// at roughness 0.05 - under a hundredth of the lobe it was meant to widen,
		// which is exactly how it looked.
		//
		// With PBR_LIGHT_SIZE at 0.0 this is exactly the point light it used to
		// be, which is the setting to compare against.
		float alpha = roughness * roughness
			+ PBR_SUN_ANGULAR_RADIUS * PBR_LIGHT_SIZE;

		// A distribution is only meaningful up to a width of about a radian, so an
		// exaggerated light size is capped there rather than being left to describe
		// a lobe wider than the maths can.
		float lobe = min(sqrt(alpha), 1.0);

		float D = D_GGX(NdotH, lobe);
		float visibility = V_SmithGGXCorrelated(NdotL, NdotV, lobe);
		vec3 fresnel = F_Schlick(pbr.f0, VdotH);

		return PBR_SPECULAR_STRENGTH * D * visibility * fresnel * lightTerm;
	}

	// A crude stand-in for image-based lighting.
	//
	// The highlight above only exists where a light source is, and Steadfast
	// only has one: the sun or moon. Without the term below, a material would
	// therefore only ever look reflective when it happens to be in direct
	// sunlight - never in a cave, never indoors, never at night, never on a
	// side face, and never from the block light of a torch right next to it.
	// That is what makes a shader look like it has materials on some blocks and
	// not on others.
	//
	// Treating the ambient and block light around the fragment as a uniform
	// environment is not physically correct - a real reflection would be
	// blurred by roughness rather than faded by it, and would have a direction
	// to it - but it is cheap, it responds to the material and to the light
	// around it, and it is what makes every surface read as a material.
	//
	// PBR_REFLECTIONS is what supplies the direction and the roughness described
	// above, by reflecting the sky along the reflected ray (PbrReflectionDirection
	// in reflections.glsl, evaluated by EnvironmentReflection in
	// environment_reflection.glsl). With it on, this term keeps only what the sky cannot
	// do - the light indoors and underground, which has no direction to
	// reflect.
	vec3 PbrAmbientSpecular(
		PbrSurface pbr,
		vec3 worldNormal,
		vec3 viewDirection,
		// The ambient and block light reaching this fragment, standing in for
		// the environment that it reflects.
		vec3 indirectLighting,
		// How much sky reaches this fragment; only read when PBR_REFLECTIONS is
		// on, where it decides how much of this term the directional reflection
		// in reflections.glsl has taken over.
		float skyLight
	) {
		float NdotV = max(dot(worldNormal, viewDirection), 1.0e-4);
		vec3 fresnel = F_Schlick(pbr.f0, NdotV);

		// A rough surface scatters the environment too broadly to show a
		// coherent reflection.
		float smoothness = 1.0 - pbr.roughness;

		#ifdef PBR_REFLECTIONS
			// PbrReflectionDirection reflects the sky with a direction and a
			// roughness, which is exactly what this term was standing in for. Wherever that
			// one is doing the job - a surface smooth enough to show a coherent
			// reflection, with a sky in front of it - this one steps back, so
			// that the same environment is not counted twice.
			//
			// The step-back is weighted by the same roughness that fades the sky
			// term, so a rough surface keeps this term in full rather than
			// losing its only environment response to a reflection it can barely
			// show. Underground and indoors the sky light is zero, so this is
			// untouched either way - which is what keeps a material reading as a
			// material in a cave.
			smoothness *= 1.0 - skyLight * (1.0 - pbr.roughness);
		#endif

		return PBR_SPECULAR_STRENGTH * smoothness * fresnel * indirectLighting;
	}
#endif /* PBR_SPECULAR */

#endif /* PBR_SURFACE */



