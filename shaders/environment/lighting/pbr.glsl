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
//            read when PBR_MATERIAL_AO is on; with it off, only .xy is used
//            and the blue channel is never read at all.
//   _n.a   - height, used for parallax occlusion mapping.
//
//   _s.r   - perceptual smoothness. roughness = (1.0 - smoothness)^2
//   _s.g   - F0 / metal ID. Values are stored linearly as of 1.3 (older
//            versions stored the square root of F0 and would need squaring).
//              0-229   dielectric, F0 = the value itself (max ~0.898)
//              230-237 hardcoded metals, see PbrMetalF0
//              238-255 albedo-based metal, F0 = the albedo
//   _s.b   - subsurface scattering above 64.5/255, porosity below it. The
//            scattering is read when PBR_SUBSURFACE is on, the porosity when
//            PBR_POROSITY_WETNESS is.
//   _s.a   - emission. 255 means "does not emit", 0 means "fully emissive".
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
//   The parallax ray march is the only part with a variable cost, and it is
//   bounded by PBR_PARALLAX_STEPS texture samples. A resource pack whose height
//   channel is flat costs a single sample and produces no displacement, since
//   LabPBR stores 1.0 for "not displaced".

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
#define PBR_TANGENT_ATTRIBUTE
#ifdef PBR_TANGENT_ATTRIBUTE
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
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
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
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

// How bright that emission is.
//
// LabPBR stores emission as a fraction of the surface color, and on its own
// that is rarely bright enough to read as something lit from within - the
// tonemapper compresses it straight back down. Raise this to make emissive
// materials actually glow.
#define PBR_EMISSION_STRENGTH 1.5 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0]

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
	// See the note on PBR_PARALLAX_SHADOW: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in lit.fsh.
#endif

// How bright block self-emission is. Values above 1.0 push the surface into
// overbright territory, which is what a light source should look like.
#define BLOCK_EMISSION_STRENGTH 1.5 // [0.5 0.75 1.0 1.5 2.0 3.0 4.0 6.0]

// Whether to displace the material and base textures with the height stored in
// the alpha channel of the normal map.
//
// This is parallax occlusion mapping: the surface is traced against its own
// height field along the view ray. It is the most expensive part of this file,
// and the only one that changes where textures are sampled rather than just how
// they are lit.
//#define PBR_PARALLAX

// How many layers the parallax ray march takes. Each layer is one texture
// sample, and more layers track the height field more closely at grazing
// angles. 32 is enough for the effect to be essentially exact; 4 is enough to
// see that something is there.
//
// Note: these are written as #define rather than const, which is the form the
// rest of this pack uses for tunable values (see WATER_PARALLAX_DISTANCE).
#define PBR_PARALLAX_STEPS 16 // [4 8 12 16 24 32]

// How deep the height field is, in blocks, at its deepest point (height 0).
// LabPBR asks resource packs to stay within a quarter of a block, so values
// much above 0.25 are likely to look wrong on most packs. A resource pack with
// a flat height channel is unaffected by this setting.
#define PBR_PARALLAX_DEPTH 0.2 // [0.05 0.1 0.15 0.2 0.25 0.3 0.4 0.5]

// How many binary search steps refine the ray march.
//
// The layer march can only ever land on a layer boundary, and a resource pack's
// height channel usually covers only a fraction of its range, so very few
// layers actually fall inside the real height variation. Without refinement the
// texture then visibly snaps between a handful of positions - it stacks up in
// steps rather than following the surface.
//
// Each step is one more texture sample. Setting this to 0 disables refinement
// and gets the stepping back.
#define PBR_PARALLAX_REFINE 4 // [0 2 4 6]

// How far a sample is allowed to be displaced, in blocks.
//
// Grazing angles divide the displacement by the view direction's slope, which
// would otherwise drag samples clean across into the neighbouring sprites of
// the block atlas - the material data read there belongs to a different block,
// which shows up as a visible boundary partway across the ground. This caps the
// displacement at well under one block, which is also all the geometry has to
// give.
#define PBR_PARALLAX_MAX_OFFSET 0.25 // [0.1 0.15 0.2 0.25 0.3 0.35 0.4 0.5 0.6]

// Distance in meters at which parallax mapping fades out. Past a certain
// distance a single screen pixel covers more than the whole height range, so
// the ray march only produces shimmer at full cost. This mirrors the water
// parallax settings.
#define PBR_PARALLAX_DISTANCE 16.0 // [8.0 12.0 16.0 24.0 32.0 48.0 64.0 96.0 128.0]

// Whether the height field should also shadow itself.
//
// Parallax mapping on its own only slides the texture around; the raised parts
// of the height field do not darken the crevices behind them, so the surface
// ends up looking like a flat picture pasted onto the block rather than like
// something with depth. Shadowing the height field against the light is what
// makes the sides of the bumps read as sides.
#define PBR_PARALLAX_SHADOW
#ifdef PBR_PARALLAX_SHADOW
	// The #ifdef is not decoration. Iris only treats a bare #define as a
	// boolean option if the macro is referenced by an #ifdef or #ifndef
	// somewhere, so without this the option would be declared but never appear
	// in the settings menu. (This is why every toggle elsewhere in this pack is
	// followed by an #ifdef block.) The actual use is in lit.fsh.
#endif

// How dark those height field shadows get. 1.0 is a fully occluded crevice.
#define PBR_PARALLAX_SHADOW_STRENGTH 0.85 // [0.25 0.5 0.65 0.75 0.85 1.0]

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
// view shows the same number, which is how to place this exactly: pick the
// level at which the surface stops looking like it has any detail left.
#define PBR_NORMAL_FADE_LOD 2.0 // [1.0 1.5 2.0 2.5 3.0 4.0 6.0]

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
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
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
// materials are what use the upper range, and what the effect adds is the glow
// of a backlit leaf - the light comes through the surface instead of bouncing
// off it, so the brightest side is the one facing away from the sun.
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
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
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
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
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
// in this file: TranslucentLighting gives water a reflectance of 0.1 and gives
// everything else 0.0, which leaves ice with no specular response at all beyond
// the grazing Fresnel that every surface has. With this on, ice reads its
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
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
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
// It is applied in the deferred pass rather than where the surface is drawn,
// because that is the first point at which the depth buffer describes a finished
// frame - see the note on PBR_SSR. The material it needs (normal, roughness,
// reflectance) is written into two buffers by the programs that draw surfaces,
// and read back there.
//
// Noticeably more expensive than the term it replaces: one sky model evaluation
// per covered pixel. PBR_REFLECTIONS_STRENGTH is the control for how visible it
// is, and this pack ships with it turned down.
#define PBR_REFLECTIONS
#ifdef PBR_REFLECTIONS
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in copy_and_fog.fsh.
#endif

// How strong that reflection is. 1.0 is the value it was tuned at.
#define PBR_REFLECTIONS_STRENGTH 0.25 // [0.25 0.5 0.75 1.0 1.5 2.0]

// How far a rough surface bends the reflected ray towards its own normal, as a
// fraction of the roughness range.
//
// At 1.0 a fully rough surface looks straight up, which is the average of the
// sky over it. At 0.0 roughness would not affect the direction at all, and a
// rough surface would show the same mirror image a polished one does.
#define PBR_REFLECTIONS_ROUGHNESS 1.0 // [0.0 0.5 0.75 1.0]

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
// anything. It ships on, with PBR_SSR_ROUGHNESS keeping most of a world out of
// it; turn that limit down first, and this option off second.
#define PBR_SSR
#ifdef PBR_SSR
	// See the note on PBR_PARALLAX_SHADOW above: the #ifdef is what makes Iris
	// register this as a boolean option. The actual use is in copy_and_fog.fsh.
#endif

// How rough a surface may be and still have the world traced into its
// reflection.
//
// Above this the reflection is the sky term alone. A rough surface scatters the
// reflected ray over too wide a range of directions for one sharp sample to
// stand in for, so tracing it would show a mirror image of the world that the
// surface should not have - and the trace costs the same whether it finds
// anything or not, which makes this the single largest saving available in a
// scene that is mostly made of rough things.
//
// Raise it to reflect the world in rougher surfaces at a higher cost and with
// reflections that are sharper than they should be; to blur them properly
// instead, the trace would have to sample several points around the hit.
#define PBR_SSR_ROUGHNESS 0.2 // [0.1 0.2 0.35 0.5 0.7 1.0]

// How many steps the reflection trace may take.
//
// Only the material reflections use this; the water reflections keep their own
// budget, because spending this many steps on the water and on every smooth
// pixel of the screen are two very different propositions. More steps find more
// hits and refine the ones they find better, and the cost is paid whether or not
// anything is found at all.
#define PBR_SSR_STEPS 12 // [8 12 16 24 32]

// How much sky a surface has to see before it reflects any of it.
//
// This is what keeps sky reflections out of caves and interiors. Minecraft's sky
// light spreads sideways under an overhang and passes straight through glass, so
// a fragment can be lit as if it were outdoors while nothing of the sky is
// actually visible from it - which is what a polished block on the floor of a
// shallow cave reflecting a noon sky looks like. Requiring nearly full sky
// light, and fading in over the last tenth of the range rather than switching on
// at a threshold, is what stops that.
//
// Note the one case this cannot fix: a surface lit through a glass window has a
// sky light of 15, exactly like one standing in the open, and no lighting
// information available here can tell the two apart. Lower this if you would
// rather have reflections indoors and put up with them in caves.
#define PBR_REFLECTION_SKY_MIN 0.9 // [0.0 0.5 0.75 0.85 0.9 0.95 1.0]



// Replaces the shaded image with a visualisation of the material data, which is
// the quickest way to find out whether a resource pack actually provides what
// an effect needs. If Height shows a flat grey for the block you are looking
// at, that pack has no height channel there and no amount of parallax tweaking
// will produce any displacement.
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
#define PBR_DEBUG PBR_DEBUG_NONE // [PBR_DEBUG_NONE PBR_DEBUG_HEIGHT PBR_DEBUG_SMOOTHNESS PBR_DEBUG_F0 PBR_DEBUG_NORMAL PBR_DEBUG_MIP PBR_DEBUG_TANGENT_NORMAL PBR_DEBUG_MATERIAL_AO PBR_DEBUG_SUBSURFACE PBR_DEBUG_EMISSION]

// How much of its diffuse response a metal loses. Physically, metals have no
// diffuse component at all, but Steadfast has no image-based lighting or
// screen-space reflections for opaque terrain, so a fully metallic surface
// would be lit by its specular highlight alone and read as a black hole in
// caves. Keeping half of the diffuse response keeps metals recognizable
// without ruining dark scenes.
//
// 0.0 = metals keep all of their diffuse response (shiny plastic look)
// 1.0 = metals lose their diffuse response entirely (physically correct)
#define PBR_METAL_DIFFUSE 0.5 // [0.0 0.25 0.5 0.75 1.0]

// The main switch. Defined only for the block atlas programs (see PBR_ATLAS in
// the gbuffers wrappers), as the PBR atlases only cover the block atlas - the
// texture coordinates of entities, held items, and Distant Horizons terrain do
// not index into it. When this is not defined, every declaration below is
// removed by the preprocessor and no PBR data is read or paid for.
#if defined(PBR_ATLAS) && PBR_FORMAT != PBR_OFF
	#define PBR_SURFACE

	// Height field shadowing reuses the parallax height sampling, so it needs
	// both switches. Nested rather than combined with defined() so that both
	// macros are referenced with a real #ifdef, which is what registers them as
	// options in the first place.
	#ifdef PBR_PARALLAX
		#ifdef PBR_PARALLAX_SHADOW
			#define PBR_PARALLAX_SHADOWING
		#endif
	#endif

	// Iris reports the PBR format that the resource pack declares in its
	// texture.properties. It cannot be declared from the shader side, so this
	// is purely informational - if the pack says nothing, we still sample and
	// rely on the neutral defaults below.
	#if defined(MC_TEXTURE_FORMAT_LAB_PBR_1_3) || defined(MC_TEXTURE_FORMAT_LAB_PBR)
		#define LABPBR_1_3
	#endif
#endif

// The decoded material properties of a fragment.
struct PbrSurface {
	// Perceptual roughness, where 0.0 is a mirror and 1.0 is fully diffuse.
	float roughness;
	// Reflectance at normal incidence.
	vec3 f0;
	// 1.0 for hardcoded and albedo-based metals, 0.0 for dielectrics.
	float metalness;
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
	return PbrSurface(1.0, vec3(0.0), 0.0, 0.0, 0.0, 1.0, 1.0, 0.0, 0.0);
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
// The alpha is meaningless too, whichever end of the range the atlas left it at,
// and this is the part that matters for emission: LabPBR stores emission as the
// *inverse* of alpha, so a zero there reads as "fully emissive" and a whole
// block's worth of missing data turns into a lamp. That is what shows up as a
// glow over modded leaves and grass, and it is why both colours are rejected
// with any alpha rather than only the opaque pair.
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
// belongs thematically, because the environment reflection is applied in the
// deferred pass - a program that has no block atlas and therefore no
// PBR_SURFACE - and needs this. Everything it depends on is a constant.
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
// These have to be taken once, unconditionally, at the top of main(): dFdx and
// dFdy have undefined results after a discard or in non-uniform control flow,
// and a texture sample that relies on implicit derivatives (which is to say,
// any sample outside the parallax ray march) has the same restriction. Passing
// them around also lets the parallax march sample with an explicit level of
// detail from inside its loop.
struct PbrGradients {
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

// F0 values for the LabPBR hardcoded metals, looked up by the byte value stored
// in the green channel of the specular map.
//
// This is a branch, and the two comparisons in the fallback path are the cost
// of a material not using the feature, which is why the common dielectric case
// never reaches this function at all.
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
// This is the fallback frame, used for geometry that carries no tangent of its
// own - Minecraft's entity format has none, and some mods leave the attribute at
// zero. Everywhere else PbrAttributeFrame below is preferred, because this one
// depends on differentiating a position that had to be reconstructed from the
// depth buffer first, and the depth buffer's precision runs out at a distance.
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
	// purpose. For Minecraft's texture convention the result is the direction
	// the texture's V axis increases in, which is the axis the normal map's
	// green channel describes, so the green channel lands on it without a flip.
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

		vec3 bitangent = cross(worldNormal, tangent) * worldTangent.w;

		return mat3(tangent, bitangent, worldNormal);
	}
#endif

#ifdef PBR_PARALLAX
	// Samples the height channel of the normal map. The atlas is sampled with
	// explicit gradients because this is called from inside the ray march, where
	// implicit derivatives are not available.
	float PbrHeight(vec2 texCoord, PbrGradients gradients) {
		return textureGrad(
			normals,
			texCoord,
			gradients.ddxTexCoord,
			gradients.ddyTexCoord).a;
	}

	// How far the height field is displaced, and how far the effect reaches.
	// Shared by the view ray march and the height field shadowing so that the
	// two cannot drift apart.
	float PbrParallaxStrength(vec3 cameraRelativePos) {
		return clamp(
			(PBR_PARALLAX_DISTANCE - length(cameraRelativePos))
				/ (PBR_PARALLAX_DISTANCE * 0.25),
			0.0,
			1.0);
	}

	// Inverts the texture coordinate Jacobian to get the world-space direction
	// and size of one unit of texture coordinate along each axis.
	//
	// This is what makes a displacement a distance in blocks rather than a
	// fraction of the texture: a sprite occupies only a small part of the block
	// atlas, so a displacement expressed directly in texture coordinates would
	// depend on the atlas resolution and on how large the sprite happens to be.
	//
	// Returns false when the mapping is degenerate (a zero-area triangle, or a
	// fragment where the derivative was lost).
	bool PbrTexCoordAxes(
		PbrGradients gradients,
		out vec3 dPdu,
		out vec3 dPdv
	) {
		float determinant = gradients.ddxTexCoord.x * gradients.ddyTexCoord.y
			- gradients.ddxTexCoord.y * gradients.ddyTexCoord.x;

		if (abs(determinant) < 1.0e-12) {
			dPdu = vec3(0.0);
			dPdv = vec3(0.0);
			return false;
		}

		dPdu = (gradients.ddyTexCoord.y * gradients.ddxPosition
			- gradients.ddxTexCoord.y * gradients.ddyPosition) / determinant;

		dPdv = (gradients.ddxTexCoord.x * gradients.ddyPosition
			- gradients.ddyTexCoord.x * gradients.ddxPosition) / determinant;

		return true;
	}

	// Projects a displacement in world space onto the texture coordinate axes.
	//
	// Projecting rather than dividing by a length keeps the direction correct
	// for mirrored or skewed UV mappings, where dividing would flip it.
	vec2 PbrWorldOffsetToTexCoord(vec3 worldOffset, vec3 dPdu, vec3 dPdv) {
		return vec2(
			dot(worldOffset, dPdu) / dot(dPdu, dPdu),
			dot(worldOffset, dPdv) / dot(dPdv, dPdv));
	}

	// Clamps a displacement so that it cannot leave the sprite the fragment
	// started in.
	//
	// This is the difference between parallax mapping and a visible boundary at
	// a fixed distance from the player. The offset is a distance in blocks and a
	// block face is one sprite, so once it grows to a decent fraction of a block
	// the sample crosses the edge of that sprite and lands in whatever is beside
	// it in the atlas - the neighbouring block's texture, or the empty margin
	// between sprites.
	//
	// Material data read from a neighbouring block is merely wrong. Data read
	// from an empty margin is worse: a black texel decodes to a tangent-space
	// direction of (-1, -1) with no Z at all, ie, a strong fixed tilt rather
	// than a flat normal, and the surface looks like its normal map has
	// inverted. Since the offset grows with how shallow the view angle is, and
	// on flat ground the view angle maps to distance, that shows up as a line
	// across the ground at whatever distance the offset first gets that large.
	//
	// spriteBounds is xy: the centre of the sprite, zw: half of its size, both
	// in the same texture coordinate space as texCoord. Geometry that provides
	// nothing usable is left to the global displacement limit alone.
	vec2 PbrClampToSprite(vec2 offset, vec2 texCoord, vec4 spriteBounds) {
		vec2 halfSize = spriteBounds.zw;

		if (any(lessThanEqual(halfSize, vec2(0.0)))
			|| any(greaterThan(halfSize, vec2(0.5)))) {
			return offset;
		}

		// How far this fragment can move before it leaves the sprite, with a
		// margin left over for texture filtering at the edge.
		vec2 room = max(halfSize - abs(texCoord - spriteBounds.xy), vec2(0.0))
			* 0.9;

		return clamp(offset, -room, room);
	}
#endif

// Returns the texture coordinate to sample the material from, displaced by the
// height field along the view ray.
//
// This is parallax occlusion mapping: rather than displacing geometry (which we
// cannot do, as the depth buffer has already been written by the time this
// runs), it walks along the view ray in layers and finds where the ray passes
// below the surface. The result is that deep parts of the texture appear to sit
// further back than shallow ones.
//
// Without this, a height field can only be faked by shifting the whole surface
// uniformly, which does not produce occlusion between the near and far parts of
// the surface and therefore does not read as depth at all.
vec2 PbrParallaxUV(
	mat3 frame,
	vec3 cameraRelativePos,
	vec2 texCoord,
	PbrGradients gradients,
	// xy: the centre of this face's sprite, zw: half of its size.
	vec4 spriteBounds
) {
	#ifndef PBR_PARALLAX
		return texCoord;
	#else
		// The view direction, expressed in the tangent space of this fragment.
		vec3 viewDirection = normalize(-cameraRelativePos);
		vec3 viewTangent = vec3(
			dot(viewDirection, frame[0]),
			dot(viewDirection, frame[1]),
			dot(viewDirection, frame[2]));

		// The surface is being viewed edge-on or from behind, so there is no
		// sensible ray to trace through the height field.
		if (viewTangent.z < 1.0e-3) {
			return texCoord;
		}

		// The displacement grows without bound as the view direction approaches
		// the plane of the surface, which at the very least would drag samples
		// across the neighbouring sprites of the atlas. Clamp how shallow the
		// trace is allowed to get, ie, how far a point at full depth can be
		// dragged sideways.
		float depthRate = max(viewTangent.z, 0.25);

		// Fade the effect out with distance rather than spending up to
		// PBR_PARALLAX_STEPS samples per pixel on shimmer.
		float strength = PbrParallaxStrength(cameraRelativePos);

		if (strength <= 0.0) {
			return texCoord;
		}

		vec3 dPdu;
		vec3 dPdv;

		if (!PbrTexCoordAxes(gradients, dPdu, dPdv)) {
			return texCoord;
		}

		// The displacement, in world space, of a point that sits
		// PBR_PARALLAX_DEPTH blocks below the reference surface, seen along the
		// view ray.
		//
		// A point that is further away from the eye than the surface appears to
		// be is the one that gets sampled: looking down at a recessed point, the
		// ray from the eye reaches it further along the surface, away from the
		// eye. Since viewTangent points *towards* the eye, the negation below is
		// what turns "towards the eye" into "away from the eye", which is the
		// direction the ray march then travels in.
		vec3 worldOffset = -strength * PBR_PARALLAX_DEPTH
			* (viewTangent.x * frame[0] + viewTangent.y * frame[1])
			/ depthRate;

		// Shallow view angles divide by a small slope, which on its own would
		// drag the sample far enough to leave the sprite it belongs to. The
		// material data read from a neighbouring sprite describes a different
		// block, and the boundary where that starts happening is visible as a
		// line across the ground at a fixed distance from the player.
		float offsetLength = length(worldOffset);

		if (offsetLength > PBR_PARALLAX_MAX_OFFSET) {
			worldOffset *= PBR_PARALLAX_MAX_OFFSET / offsetLength;
		}

		vec2 fullOffset = PbrWorldOffsetToTexCoord(worldOffset, dPdu, dPdv);

		// Never sample outside the sprite this fragment belongs to.
		fullOffset = PbrClampToSprite(fullOffset, texCoord, spriteBounds);

		// Walk along the ray in layers until it passes below the surface it is
		// tracing. Each layer moves the sample further from the eye and deeper
		// into the height field, which is why the offset is added.
		//
		// LabPBR stores 1.0 for "not displaced", so it is the *depth* of the
		// surface (1 - height) that the ray is compared against. That also means
		// a resource pack without height data costs exactly one sample here and
		// produces no displacement, so this degrades gracefully.
		float layerStep = 1.0 / float(PBR_PARALLAX_STEPS);
		vec2 stepOffset = fullOffset * layerStep;

		vec2 currentTexCoord = texCoord;
		float currentLayer = 0.0;
		float currentDepth = 1.0 - PbrHeight(currentTexCoord, gradients);

		vec2 previousTexCoord = currentTexCoord;
		float previousLayer = 0.0;

		for (int i = 0; i < PBR_PARALLAX_STEPS; i++) {
			if (currentLayer >= currentDepth) {
				break;
			}

			previousTexCoord = currentTexCoord;
			previousLayer = currentLayer;

			currentTexCoord += stepOffset;
			currentLayer += layerStep;
			currentDepth = 1.0 - PbrHeight(currentTexCoord, gradients);
		}

		// How far above or below the surface the ray is at each of the two
		// layers that bracket the intersection.
		//
		// `beforeDepth` is measured rather than assumed to be positive: if the
		// march simply ran out of layers, there is no crossing to refine and the
		// last sample is the best answer available.
		float afterDepth = currentDepth - currentLayer;
		float beforeDepth =
			(1.0 - PbrHeight(previousTexCoord, gradients)) - previousLayer;

		if (afterDepth > 0.0 || beforeDepth <= 0.0) {
			return currentTexCoord;
		}

		#if PBR_PARALLAX_REFINE > 0
			// Find the crossing point properly, by bisecting the interval
			// between the two layers that bracket it.
			//
			// This matters more than it sounds like it should. The march places
			// a fixed number of layers across the entire height range, but a
			// resource pack's height channel usually covers only a fraction of
			// that range, so only one or two layers tend to fall inside the
			// actual variation. Interpolating between two such distant layers is
			// not enough to hide them, and the texture snaps between a handful
			// of positions, which reads as the surface being built out of
			// stacked layers rather than following a continuous slope.
			vec2 lowTexCoord = previousTexCoord;
			vec2 highTexCoord = currentTexCoord;
			float lowLayer = previousLayer;
			float highLayer = currentLayer;

			for (int i = 0; i < PBR_PARALLAX_REFINE; i++) {
				vec2 midTexCoord = 0.5 * (lowTexCoord + highTexCoord);
				float midLayer = 0.5 * (lowLayer + highLayer);

				if ((1.0 - PbrHeight(midTexCoord, gradients)) > midLayer) {
					// The ray is still above the surface here, so the crossing
					// is further along the ray.
					lowTexCoord = midTexCoord;
					lowLayer = midLayer;
				} else {
					highTexCoord = midTexCoord;
					highLayer = midLayer;
				}
			}

			return 0.5 * (lowTexCoord + highTexCoord);
		#else
			// Without refinement, at least interpolate between the two layers.
			float weight = clamp(
				afterDepth / max(afterDepth - beforeDepth, 1.0e-4),
				0.0,
				1.0);

			return mix(currentTexCoord, previousTexCoord, weight);
		#endif
	#endif
}

#ifdef PBR_PARALLAX_SHADOWING
	// How much of the sunlight reaches this point through the height field.
	//
	// This is what makes the height field read as depth rather than as a
	// picture sliding around on the block. Parallax mapping on its own only
	// moves the texture; nothing about it says that the side of a bump should
	// be darker than the surrounding flat ground, so the eye reads the result
	// as a flat layer that happens to move. Marching the height field against
	// the light and darkening whatever is behind a bump is what turns that into
	// something with visible sides.
	//
	// Note that this can only ever darken. The shape of the block is still a
	// cube: nothing here can make the height field stick out past the block's
	// own edges, because the fragment shader has no way to move geometry.
	float PbrParallaxShadow(
		// The displaced texture coordinate, ie, the point being shaded.
		vec2 texCoord,
		mat3 frame,
		vec3 lightDirection,
		vec3 cameraRelativePos,
		PbrGradients gradients,
		// xy: the centre of this face's sprite, zw: half of its size.
		vec4 spriteBounds
	) {
		float surfaceHeight = PbrHeight(texCoord, gradients);

		// A point sitting at the reference height cannot be shadowed by the
		// height field, because nothing in it is tall enough to rise above the
		// ray that leaves this point towards the light. This is what makes a
		// resource pack with a flat height channel cost a single sample, as the
		// ray march below is skipped entirely.
		if (surfaceHeight >= 1.0 - 1.0e-4) {
			return 1.0;
		}

		// The light direction, expressed in the tangent space of this fragment.
		vec3 lightTangent = vec3(
			dot(lightDirection, frame[0]),
			dot(lightDirection, frame[1]),
			dot(lightDirection, frame[2]));

		// The light is at or below the horizon of this surface, so the surface
		// is unlit anyway and there is nothing to shadow.
		if (lightTangent.z <= 1.0e-3) {
			return 1.0;
		}

		float depthRate = max(lightTangent.z, 0.25);

		vec3 dPdu;
		vec3 dPdv;

		if (!PbrTexCoordAxes(gradients, dPdu, dPdv)) {
			return 1.0;
		}

		// The ray towards the light rises by one layer of height per step, so
		// the horizontal distance it covers per step is one layer of height
		// measured along the light's direction. Note that there is no negation
		// here: this ray travels towards the light, unlike the view ray above,
		// which travels away from the eye and into the surface.
		vec3 worldOffset = PBR_PARALLAX_DEPTH
			* (lightTangent.x * frame[0] + lightTangent.y * frame[1])
			/ depthRate;

		float offsetLength = length(worldOffset);

		if (offsetLength > PBR_PARALLAX_MAX_OFFSET) {
			worldOffset *= PBR_PARALLAX_MAX_OFFSET / offsetLength;
		}

		vec2 fullOffset = PbrWorldOffsetToTexCoord(worldOffset, dPdu, dPdv);

		// The shadow ray has to respect the sprite bounds too: it samples the
		// height channel just as the view ray samples the normals.
		fullOffset = PbrClampToSprite(fullOffset, texCoord, spriteBounds);

		vec2 stepOffset = fullOffset / float(PBR_PARALLAX_STEPS);

		// The height range that this ray actually travels through. A resource
		// pack's height channel normally covers only a fraction of its range, so
		// measuring the occlusion against the full range would leave subtle
		// height maps casting no shadow at all - which is exactly what happened
		// before this was measured locally.
		float farHeight = PbrHeight(texCoord + fullOffset, gradients);
		float variation = max(surfaceHeight, farHeight)
			- min(surfaceHeight, farHeight);
		float variationScale = 1.0 / max(variation, 0.05);

		float layerStep = 1.0 / float(PBR_PARALLAX_STEPS);
		float rayHeight = surfaceHeight;
		vec2 currentTexCoord = texCoord;

		// How far the ray ends up buried underneath the height field is what
		// decides how much light gets through. Counting the blocked layers
		// instead would dilute the result across the whole march: a crevice is
		// open along most of the ray and only blocked close in.
		float deepest = 0.0;

		for (int i = 0; i < PBR_PARALLAX_STEPS; i++) {
			currentTexCoord += stepOffset;
			rayHeight += layerStep;

			deepest = max(
				deepest,
				PbrHeight(currentTexCoord, gradients) - rayHeight);
		}

		float occlusion = clamp(deepest * variationScale, 0.0, 1.0);
		float shadow = 1.0 - occlusion * PBR_PARALLAX_SHADOW_STRENGTH;

		// Fade the shadowing out with distance along with the rest of the
		// parallax effect.
		return mix(1.0, shadow, PbrParallaxStrength(cameraRelativePos));
	}
#endif

// The tangent-space XY of the normal map at this coordinate, decoded to the
// -1 to 1 range.
//
// LabPBR normals use the DirectX convention, where green points down in the
// texture - which is exactly the direction that the texture coordinate's V axis
// increases in Minecraft, so the green channel maps straight onto the bitangent
// with no flip.
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

		// A resource pack without normal maps yields a flat normal here, which
		// decodes to (0, 0, 1) and reproduces the original face normal exactly.
		return normalize(frame * vec3(tangentNormalXY, tangentNormalZ));
	#endif
}

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
		// Note the assumption that a missing sprite is opaque; a transparent
		// black would be indistinguishable from a fully emissive material.
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
					// perfectly smooth surface with no reflection at all.
					pbr.f0 = vec3(max(specularSample.g, PBR_DEFAULT_F0));
				#else
					pbr.f0 = vec3(specularSample.g);
				#endif
			} else if (hardcodedMetal) {
				// Hardcoded metal, looked up from the table.
				pbr.f0 = PbrMetalF0(int(green255 + 0.5));
				pbr.metalness = 1.0;
			} else {
				// Albedo-based metal. f0 is filled in from the surface color by
				// PbrResolveAlbedo(). This is also where hardcoded metals land
				// when the metal lookup is turned off, which approximates them
				// far better than treating them as dielectrics would.
				pbr.metalness = 1.0;
				pbr.albedoMetal = 1.0;
			}
		}
	#endif

	#ifdef PBR_EMISSION
		// 255 means "does not emit", 0 means "fully emissive". Resource packs
		// without specular maps sample as 1.0 here, which correctly yields no
		// emission at all.
		//
		// Only where the atlas holds a material, though: a sprite with no
		// specular map reads as transparent black, whose alpha of zero would
		// otherwise be read as "fully emissive" and make every such block glow.
		// See PbrMissingSpecular.
		if (!PbrMissingSpecular(specularSample)) {
			pbr.emission = max(1.0 - specularSample.a, 0.0);
		}
	#endif

	#if defined(PBR_SUBSURFACE) || defined(PBR_POROSITY_WETNESS)
		// LabPBR packs two things into one channel and splits them at 64 out of
		// 255: below that the value is porosity, above it the surface lets that
		// much of the light through. The boundary is placed half-way between the
		// two ranges so that texture filtering between neighbouring texels
		// cannot land on it.
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
	//   - How closely the viewer is looking along the light, which is what makes
	//     the glow appear when the sun is behind the leaves.
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
// what an effect needs. If Height comes out flat grey for the block being
// looked at, that pack has no height channel there, and no amount of parallax
// tuning will produce displacement - the effect is not broken, there is simply
// nothing to displace.
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
		// The mip level this fragment's material samples land on, as a greyscale
		// ramp from level 0 (black) to level 8 (white). Blockier bands are
		// expected - the level steps once per doubling of distance.
		//
		// This is the level the distance calls for, before PBR_MATERIAL_MAX_LOD
		// clamps it, which is what decides where the normal map fades out.
		return vec3(clamp(gradients.lod / 8.0, 0.0, 1.0));
	#elif PBR_DEBUG == PBR_DEBUG_TANGENT_NORMAL
		// The normal map exactly as authored, decoded but before the surface's
		// tangent frame is applied - so it shows the texture's own content and
		// nothing this shader does to it. A flat normal reads as the light blue
		// of a straight-up vector.
		//
		// A tangent-space view is the way to tell a bad sample apart from a bad
		// frame: if the colour stays correct with distance but the shading does
		// not, the sample is fine and the frame is at fault. Anything that comes
		// out black is a texel outside the sprite, which decodes to a (-1, -1)
		// direction rather than a flat one.
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
		// neither as black.
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
	// light, from 0.0 for a dry or non-porous surface to 1.0 for one that is
	// soaked through.
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
	// PBR_SURFACE guard, because the deferred pass needs it too.

	#ifdef PBR_ENERGY_CONSERVATION
		// The fraction of the light arriving at this angle that goes into the
		// surface rather than bouncing off it, which is what the diffuse term
		// has to be weighted by.
		//
		// This is the same Fresnel term the specular lobe above uses, read the
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
		// it uses the same reflectance the specular lobe above reflects with.
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
		// takes its square root, so the square root is what is passed in.
		//
		// Adding the angle to the roughness instead is the mistake this file made
		// first: alpha is the square of that, so half a degree would arrive as four
		// millionths of a radian - a change far too small to see on any surface,
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
	// above, by reflecting the sky along the reflected ray (see
	// reflections.glsl). With it on, this term keeps only what the sky cannot
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
			// PbrReflection reflects the sky with a direction and a roughness,
			// which is exactly what this term was standing in for. Wherever that
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
