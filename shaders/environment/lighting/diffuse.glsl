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

// Modified 2026-09-13 by Remiiil1a for Firmament - v0.1 (edit of coderbot's Steadfast).

// This is a high-performance lighting model that delivers pleasing visuals
// while requiring only shadow mapping. By carefully tweaking ambient lighting,
// a look similar to indirect lighting can be achieved without the associated
// complexity and performance cost.
//
// Recorded: "high-performance" and the cost comparison are the upstream pack's
// own claim about this model, carried over with it. Nothing in this file
// measures either.

// LabPBR material decoding and the metallic BRDF.
// Uniforms: normals, specular (only when PBR_SURFACE is defined)
#include "/environment/lighting/pbr.glsl"

// The End's own light, which is what stops that dimension from being lit by
// nothing but the ambient floor. Uniforms: dimension, biome_category
#include "/environment/lighting/end_lighting.glsl"

// Whether to use the new direct lighting model with atmospheric scattering.
#define MINISHITA_LIGHTING
#ifdef MINISHITA_LIGHTING
	// Actual effect is in shaders.properties
#endif

#define STEADFAST BY_CODERBOT // Authorship attribution. [BY_CODERBOT]

// Authorship attribution for this edit. Nothing in the shader reads these - the
// lang files carry the strings, and the settings screen both titles itself with
// the FIRMAMENT token and lists all three as credits. See NOTICE.md.
//
// The name carried by FIRMAMENT has to end with "(edit of coderbot's Steadfast)"
// - that parenthesis is required by Steadfast's additional terms (GPLv3 7c/7e),
// so do not shorten it away.
#define FIRMAMENT BY_REMIIIL1A // Authorship attribution. [BY_REMIIIL1A]

// The other shaders this one references or quotes code from - one credit each,
// rather than one credit per feature, and rather than one entry with all of
// them in it. They are listed on a Special thanks page of their own under
// "Credits & licence"; see NOTICE.md for the licence terms that go with them.
//
// Steadfast itself has its own entry above rather than one here, because
// Steadfast's additional terms require their notice to appear on its own,
// before any download link.
#define THANKS_MELLOW BY_THECMK // Authorship attribution. [BY_THECMK]
#define THANKS_SUNDIAL BY_GEFORCELEGEND // Authorship attribution. [BY_GEFORCELEGEND]

// Bliss is an edit of Chocapic13's shaders, so its entry names the base as well
// as the edit - crediting the edit alone would leave the author of the base
// unnamed, and the base is where its licence comes from. See NOTICE.md.
#define THANKS_BLISS BY_X0NK // Authorship attribution. [BY_X0NK]

// Eclipse, whose water interaction the simulation in environment/water is ported
// from: credited for the code and for the idea, and the README says so as well.
// The waves a player leaves behind in this pack are Eclipse's arrangement of the
// wave equation, ported through porting_kit/ and adapted to how this pack shades
// water. Its licence is its own - see NOTICE.md.
#define THANKS_ECLIPSE BY_MERLIN1809 // Authorship attribution. [BY_MERLIN1809]

#define FANTASY 0
#define SEMI_NATURAL 1
#define RETRO 2

// The style of direct and ambient sky lighting to use during the day.
#define DAY_SKY_LIGHTING SEMI_NATURAL // [FANTASY SEMI_NATURAL RETRO]

// The style of direct and ambient sky lighting to use at night.
#define NIGHT_SKY_LIGHTING SEMI_NATURAL // [FANTASY SEMI_NATURAL RETRO]

// Whether real-time shadows using shadow mapping are enabled for entities.
#define REAL_TIME_ENTITY_SHADOWS
#ifdef REAL_TIME_ENTITY_SHADOWS
	// Actual effect is in shaders.properties
#endif

// Whether real-time shadows using shadow mapping are enabled for block entities
// (chests, beds, etc).
//
// Declared in /environment/materialIDs.glsl since batch 719, not here: the program
// that reads it now is the shadow program, which includes that file and not this
// one, and a second declaration of one option is one option that can be answered
// two ways. The note there is the one that explains what it also decides - whether
// the coloured light fill can see the only two block entity light sources whose
// colour this pack can name.

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform vec3 minAmbient;
	uniform vec3 skyAmbient;
	uniform float blocklightSuppression;
	uniform float nightVision;

	// The lightmap, which is where the color of block light comes from. See
	// BlockLightTint below.
	uniform sampler2D lightmap;
	#define BLOCKLIGHT_HAS_LIGHTMAP
#endif

// The same lightmap, for the programs whose uniforms come from elsewhere - which
// is Voxy's terrain, and only Voxy's terrain.
//
// No declaration here, and that is the whole subtlety: an entry in the samplers
// map of voxy.json is not this pack asking for a sampler, it is Voxy being told
// to declare one and bind a texture to it. Voxy therefore emits the declaration
// itself into every program that reads that file, and a second one written here
// would be the same declaration twice in one program - which does not compile.
// What this file contributes is only the knowledge that the sampler is there to
// be sampled.
//
// This is the same arrangement the pack's rainStrength uniform has with the same
// file, and it is what the source checker's rules about the Voxy chain exist to
// catch. They caught this one; see BATCH_LOG.md 147.
//
// What it is for: without it, level-of-detail terrain is the one place in the
// world that cannot see the lightmap, so it is the one place whose block light has
// no color to take - and taking the color from the lightmap everywhere else is
// what left the far half white while the near half stayed warm. Lighting that
// changes color at the edge of the render distance is worse than lighting that is
// wrong everywhere, because the edge moves.
#if defined(EXTERNALLY_DEFINED_UNIFORMS) && defined(VOXY_LIGHTMAP)
	#define BLOCKLIGHT_HAS_LIGHTMAP
#endif

// How bright block light is at full block light level.
//
// This number is the pack's own rather than something read from the lightmap:
// the lightmap supplies the color, but the brightnesses it carries have its own
// falloff baked into them, and this model replaces that with its own falloff
// and this.
//
// BATCH 748 RAISED IT FROM 4.0 TO 5.0, AND THE REASON IS THE CURVE ABOVE.
// This option is defined as "how bright block light is at FULL light level", so
// it has to be re-anchored whenever the curve changes, or the change leaks into
// the bright end where nothing was wrong. The old pair was pow(x,4) at 4.0,
// which gives 3.03 for a surface beside a torch (level 0.933); the new curve at
// 5.0 gives 2.75, which is 0.91 of that - inside the 10% the batch was asked to
// hold. The exact match would be 5.52, and the slider offers 5.0 and 6.0 either
// side of it; 5.0 was chosen because it errs dimmer, and the bright end is not
// the end that was wrong.
//
// What the change does, level by level, at 5.0:
//
//     level 0.05   0.0000 -> 0.0032   128x brighter   deep shadow
//     level 0.10   0.0004 -> 0.0132    33x brighter   shadow
//     level 0.20   0.0064 -> 0.0557   8.7x brighter   shadow edge
//     level 0.40   0.1024 -> 0.2540   2.5x brighter   dim
//     level 0.70   0.9604 -> 1.0228   1.06x           lit
//     level 0.933  3.0310 -> 2.7466   0.91x           beside a torch
//     level 1.00   4.0000 -> 5.0000   1.25x           full light
//
// So the dark end is lifted by one to two orders of magnitude and the lit end is
// within 10%, which is the whole intent: the shadows were too black, and the
// bright end was fine.
#define BLOCKLIGHT_STRENGTH 5.0 // [1.0 2.0 3.0 4.0 5.0 6.0 8.0]

// The color temperature of block light, in kelvin.
//
// The color of block light comes from the lightmap, because the lightmap is how
// a resource pack says what color its lights are - see BlockLightTint below. This
// is for the case where a resource pack says nothing, or says something that does
// not suit the world being built, and what is wanted is to move the whole of it
// warm or cool without editing the pack. It reaches the level-of-detail terrain
// too, and there by the same route as everything else: lit_voxy.fsh asks Voxy for
// the lightmap and defines VOXY_LIGHTMAP, so that terrain samples it as well. The
// fallback branch in BlockLightTint, which has no lightmap and takes a colour of
// the pack's own, is what used to serve the far half; it is now reached by
// nothing in the pack, and it applies this option too in case that changes.
//
// The scale is the one a photographer uses. A candle and a torch are around
// 1800 to 2500 K and read as deep orange; an incandescent bulb is 2700 K, which
// is the warm white most people mean by "warm"; 4000 K is neutral; daylight is
// 5500 to 6500 K; an overcast sky is 7000 and up and reads blue. So lowering this
// makes block light more yellow, and raising it makes it whiter and then blue.
//
// 6500 is the middle of the scale rather than the middle of the numbers, and it is
// the default because it is exactly no change: the tint below is computed as a
// ratio against this value, so at 6500 it is one and the pack draws what it drew
// before this option existed. Every other setting moves away from that.
//
// A hundred kelvin per step, because that is the finest step anybody can see on a
// light color and anything finer would be a list of numbers no one could read.
#define BLOCKLIGHT_TEMPERATURE 2700 // [1000 1100 1200 1300 1400 1500 1600 1700 1800 1900 2000 2100 2200 2300 2400 2500 2600 2700 2800 2900 3000 3100 3200 3300 3400 3500 3600 3700 3800 3900 4000 4100 4200 4300 4400 4500 4600 4700 4800 4900 5000 5100 5200 5300 5400 5500 5600 5700 5800 5900 6000 6100 6200 6300 6400 6500 6600 6700 6800 6900 7000 7100 7200 7300 7400 7500 7600 7700 7800 7900 8000 8100 8200 8300 8400 8500 8600 8700 8800 8900 9000 9100 9200 9300 9400 9500 9600 9700 9800 9900 10000]

// What the option above is a ratio against, which is the value that leaves the
// light alone.
#define BLOCKLIGHT_TEMPERATURE_NEUTRAL 6500.0

// The color a black body at this temperature glows, from Tanner Helland's
// approximation of the Planckian locus - the same curve the kelvin scale on a
// camera or a light bulb is drawn from.
//
// Every pow() below has a guarded base, and the guards are the lesson from
// BATCH_LOG.md 139 rather than something this curve can reach. Worth being
// exact about, because it reads the other way round: the resolved temperature is
// clamped to 1000 K and up and then scaled by 0.01, so t is never below 10, and
// the branch that tests t - 60 is only taken when t is above 66. Every max()
// below is therefore inert on the path that evaluates it - t - 60 is at least 6
// there, t is at least 10, and the log of t - 10 is only reached between 19 and
// 66. They are kept because a curve like this is the kind of thing that gets
// edited, and a negative base to a fractional power is undefined in GLSL and
// comes out as a NaN on the drivers this pack has been tested on.
//
// The branches meet closely but not exactly: red is 255 below t = 66 and 259.7
// just above it, and the clamp to 0 to 1 on the way out is what makes that
// invisible. Green steps from 255.6 to 251.7 across the same point, which is
// inside the range and does show as a slight crease.
vec3 BlockLightTemperatureRgb(float kelvin) {
	float t = clamp(kelvin, 1000.0, 40000.0) * 0.01;

	float red = t <= 66.0
		? 255.0
		: 329.698727446 * pow(max(t - 60.0, 1.0), -0.1332047592);

	float green = t <= 66.0
		? 99.4708025861 * log(max(t, 1.0)) - 161.1195681661
		: 288.1221695283 * pow(max(t - 60.0, 1.0), -0.0755148492);

	float blue;
	if (t >= 66.0) {
		blue = 255.0;
	} else if (t <= 19.0) {
		blue = 0.0;
	} else {
		blue = 138.5177312231 * log(max(t - 10.0, 1.0)) - 305.0447927307;
	}

	return clamp(vec3(red, green, blue) / 255.0, vec3(0.0), vec3(1.0));
}

// The factor to multiply block light's color by.
//
// Two normalizations, and both of them are the difference between this being a
// color control and being a second brightness control:
//
// - Against the neutral temperature, so that the default setting is exactly one
// and the option does nothing until it is moved. Without this every setting
// would also brighten or darken the world by whatever the curve happens to do
// at that temperature.
// - Against its own brightness afterwards, so that the factor changes the hue
// and not the luminance. A warm tint that also took a third of the light away
// would read as "warmer and darker", and the two are separate controls here:
// BLOCKLIGHT_STRENGTH above is the brightness one.
//
// Both arguments are compile-time constants, so a driver folds this to two
// constants; the two calls are kept as calls rather than written out because the
// curve is the thing being documented.
vec3 BlockLightTemperatureTint() {
	vec3 tint = BlockLightTemperatureRgb(float(BLOCKLIGHT_TEMPERATURE))
		/ BlockLightTemperatureRgb(BLOCKLIGHT_TEMPERATURE_NEUTRAL);

	float luma = dot(tint, vec3(0.2126, 0.7152, 0.0722));

	return tint / max(luma, 1.0e-4);
}

// The color of block light, taken from the lightmap.
//
// This used to be a color of the pack's own - a warm orange - which is a
// reasonable average of every light in the game and wrong for every one of them
// individually, and it is not the pack's to choose in the first place: the
// lightmap is a texture, and recoloring it is how a resource pack says what
// color its lights are. Sampling it here means block light is whatever the
// lightmap says it is, which is both more correct and something a resource pack
// can change without touching this pack at all.
//
// Sampled at zero sky light so that this is the block light's color with no
// contribution from the sky, and reduced to its hue, because the brightness of
// block light is built from the falloff in BlockLighting and
// BLOCKLIGHT_STRENGTH rather than from the lightmap's own.
//
// BLOCKLIGHT_TEMPERATURE then moves that hue along with everything else - see the
// note on the option, and the note on the far half of the world in the branch
// below.
vec3 BlockLightTint(vec2 lightMapCoord) {
	#if defined(BLOCKLIGHT_HAS_LIGHTMAP)
		vec3 tint = texture(lightmap, vec2(lightMapCoord.x, 1.0 / 32.0)).rgb;

		// A lightmap that cannot be read comes back black, which would put every
		// light in the world out. Neutral is the safe answer.
		if (dot(tint, tint) < 0.0001) {
			return vec3(1.0);
		}

		// Only the hue: scaled so that its brightest channel is one, and then
		// moved to the temperature the option asks for.
		return tint / max(max(tint.r, tint.g), tint.b)
			* BlockLightTemperatureTint();
	#else
		// Reached only by a program that reads its uniforms from elsewhere and was
		// not given the lightmap - which is no program at all now that Voxy's
		// terrain asks for it, and is kept because a path that cannot be taken is
		// cheaper to keep than to rediscover. What it used to be is in
		// BATCH_LOG.md 146: the fallback was a warm orange of the pack's own,
		// written here to undo a regression where this returned white, and 147
		// replaced it with the lightmap itself for the programs that can have one.
		//
		// The temperature option is applied here too, so that a program which ends
		// up on this path still moves with everything else.
		return vec3(1.0, 0.52, 0.20) * BlockLightTemperatureTint();
	#endif
}

// The flood fill, which is where block light's colour comes from when the option
// above is on.
//
// The first condition is COLORED_LIGHTS, because the option is the whole
// of whether this pack has a colour of its own for block light to have: with it
// off the module has to be absent from the translation unit, or the compiled
// program would carry three sampler uniforms it has no use for and would no
// longer be the program that was compiled before the flood fill existed.
//
// The second condition is the Voxy build. The flood fill needs samplers of the
// pack's own, and a program whose uniforms are supplied from outside the pack
// cannot have them - Voxy compiles its own terrain shader and binds exactly what
// voxy.json names, so a sampler declared here would be unbound and read zero for
// the whole frame (see the note at the top of lit_voxy.fsh).
// BLOCK_LIGHT_FLOOD_FILL is the one name both this include and BlockLightColorAt
// test, so the two cannot disagree about whether the module is present.
//
// It sits here because BlockLightTint has just been defined, which is the
// function the module's own fallback is built on, and because the only caller -
// BlockLightColorAt, further down - has to see the module before it can call it.
//
// Uniforms: the two propagation fields (light_volume_a_sampler and
// light_volume_b_sampler), and frameCounter, which the module declares itself.
//
// LIGHT_VOLUME_CONSUMER is defined here and nowhere else: the module compiles
// its sampling half only for a translation unit that asks for it, because the
// writer and the compute pass include the same file for its constants and must
// not see functions that read cameraPosition and frameCounter. See the note at
// that half in light_volume.glsl.
#if defined(COLORED_LIGHTS) && !defined(EXTERNALLY_DEFINED_UNIFORMS)
	#define BLOCK_LIGHT_FLOOD_FILL
	#define LIGHT_VOLUME_CONSUMER
	#include "/environment/lighting/light_volume.glsl"
#endif

float AmbientStrength(float worldDirY) {
	// Mimic vanilla directional lighting by varying the strength of ambient
	// lighting based on whether the face is facing upwards, downwards, or
	// sideways.
	return (0.67 + worldDirY * 0.33);
}

vec3 AmbientSkyLighting(float skyLightStrength, float ambientStrength) {
	// x^3 falloff to have a more even transition
	float skyLight = pow(skyLightStrength, 3);

	// Whether sky light intensity should be directly based on the face
	// direction.
	#define DIRECTIONAL_SKYLIGHT_SHADING

	// A flat floor under the ambient light, in linear light units.
	//
	// Everything above scales with sky light, which is what makes unlit places
	// - the inside of a cave, the Nether, and the End, which has no sky light at
	// all - sit at a brightness close to black. This adds a constant instead of
	// scaling with the sky, so raising it lifts those places to something
	// readable without flattening the falloff around a torch or washing the color
	// out of a surface.
	//
	// What it does scale with depends on the branch this is compiled in: under
	// DIRECTIONAL_SKYLIGHT_SHADING, which is the one the #define above selects,
	// the constant sits inside the multiplication by ambientStrength and so
	// varies with the face direction along with everything else. In the other
	// branch it is added after that multiplication and is genuinely flat.
	//
	// It is deliberately not affected by sky light: the point is that this light
	// is there when nothing else is.
	//
	// The range goes well above the default because of how little a small
	// number does here. The tonemapper is not close to the identity in this range:
	// for a white surface under TONEMAP_UNCHARTED2, what is written here reaches
	// the screen at a fraction of its own size - 0.05 arrives as about 0.038, 0.1
	// as 0.074, 0.6 as 0.35 in linear light - and then the sRGB encode at the end
	// of postprocessing lifts it again. A cave floor at 0.05 is a very dark grey;
	// making one properly readable takes several times that.
	//
	// The default is 0.02 and not 0.1 (batch 602, the author's setting adopted as
	// the shipped one), which is BELOW the range's own first step above zero and had
	// to be added to the list to be selectable at all. It is a floor for places with
	// no light rather than a brightness in its own right: at the tonemapper's
	// compression, 0.02 arrives as roughly 0.016 in linear light, which is enough to
	// keep an unlit cave from being pure black without reading as a glow. The note
	// above still describes what the higher values do.
	#define MIN_AMBIENT_BRIGHTNESS 0.02 // [0.0 0.01 0.02 0.03 0.05 0.1 0.2 0.35 0.6]

	// Fade sky ambient lighting away as sky light fades away, as that helps us
	// rather convincingly approximate indirect lighting. But, have a "minimum"
	// ambient color so that caves are not completely black.
	#ifdef DIRECTIONAL_SKYLIGHT_SHADING
		return ambientStrength * (minAmbient
			+ vec3(MIN_AMBIENT_BRIGHTNESS)
			+ skyLight * skyAmbient);
	#else
		return ambientStrength * minAmbient
			+ vec3(MIN_AMBIENT_BRIGHTNESS)
			+ skyLight * skyAmbient;
	#endif
}

// Desaturate terrain that receives moonlight without being lit by block light.
#define NIGHT_DESATURATION_EFFECT 
#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	#ifdef NIGHT_DESATURATION_EFFECT
		uniform float desaturationIntensity;
	#else
		const float desaturationIntensity = 0.0;
	#endif
#endif

// Whether blocks in your hand should dynamically cast light on surroundings.
#if !defined(NO_HELD_BLOCK_LIGHTING)
	#define HELD_BLOCK_LIGHTING 
#endif

#ifdef HELD_BLOCK_LIGHTING
	#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
		uniform float heldLightBaseStrength;
		uniform float heldLightSuppression;
	#endif
#else
	const float heldLightBaseStrength = 0.0;
	const float heldLightSuppression = 0.0;
#endif

float HeldLightStrength(vec3 cameraRelativePos) {
	// This is an attempt to model held light strength off of the same scale as
	// Minecraft block lights use.
	//
	// Previously, this used the inverse-square law, but this led to held light
	// having an impact very far away from the player, which felt implausible.
	//
	// What the falloff is measured from is the fragment's own camera-relative
	// position, so the light is implicitly centred on the camera. To centre it
	// somewhere else, subtract the wanted position from cameraRelativePos before
	// the length below.
	float fragDistance = length(cameraRelativePos);
	return clamp(heldLightBaseStrength - fragDistance / 15.0, 0.0, 1.0);
}

// Desaturate terrain that receives moonlight without being lit by block light.
float NightDesaturation(float skyLight, float blockLight) {
	#ifndef NIGHT_DESATURATION_EFFECT
		return 0.0;
	#endif

	// Nighttime desaturation is applied to surfaces that are exposed to the sky
	// but not subject to block light.
	return desaturationIntensity * skyLight * (1.0 - blockLight);
}

#ifdef NIGHT_DESATURATION_EFFECT
	#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
		uniform vec3 desaturationColor;
	#endif

	vec3 Desaturate(vec3 color, float desaturation) {
		// Rec601 luma from https://en.wikipedia.org/wiki/Luma_(video)
		// TODO: Use luminance, luma is for sRGB only.
		float luma = dot(color, vec3(0.299, 0.587, 0.114));

		// Fade the pre-lighting color to the desaturation color
		return mix(color, luma * desaturationColor, desaturation);
	}
#endif

// The colour of block light at a fragment, and the light level the fill carries
// there.
//
// This is where the pack's two answers meet. BlockLightTint is the colour the
// lightmap says block light is; the flood fill is the colour the light actually
// arrives in and how far it reaches. The fill is asked first, and it returns the
// fallback itself wherever it has nothing to say - outside its grid, before the
// propagation has run a frame, where the field is too weak to be a colour - so
// what comes back is always a colour at the fallback's own brightness.
//
// BATCH 739 CHANGED WHAT THE SECOND OUTPUT IS. Until this batch the fill decided
// hue and the lightmap decided brightness: the out parameter was a strength in
// [0, 1] that scaled a lightmap-derived envelope, and the field's own magnitude
// was a distance weight that was thrown away. That is why the effect read as a
// tint rather than as light. Now the fill carries a light level - the number of
// blocks of reach - and the caller adds it to the lightmap's own level. A surface
// the lightmap calls dark but a torch reaches is lit by that torch, which is what
// Eclipse does and what the author asked for.
//
// Wherever the include above is not taken - COLORED_LIGHTS off, or the Voxy
// build, whose samplers are not the pack's - this compiles to one call that
// returns exactly what BlockLighting multiplied before, and reports a level of
// zero, which is the property the option is required to have.
vec3 BlockLightColorAt(
	// Where this fragment sits in the lightmap, which is where its fallback
	// colour comes from.
	vec2 lightMapCoord,
	// Where the fragment is relative to the camera, in world axes, and which way
	// its surface faces. The fill is a grid of voxels around the player, so it is
	// sampled by position, and the normal picks the empty voxel on this side of
	// the surface - see LIGHT_VOLUME_NORMAL_OFFSET in the module.
	//
	// This is the VERTEX stage's position, not the one this stage rebuilds: the
	// rebuild carries the view bobbing's translation and the field is anchored to
	// world blocks, so sampling it there makes the light pulse as the player
	// walks. See SurfaceFragment.fieldWorldPos.
	//
	// The normal here is the GEOMETRIC one, not the normal-mapped one: which
	// neighbouring voxel is air is a property of the block's geometry, not of the
	// shading detail painted on its surface. See the note on
	// SurfaceFragment.geometricNormal.
	vec3 fieldWorldPos,
	vec3 geometricNormal,
	// The fractional part of the camera's position, which is where the fixed grid
	// is snapped: the module takes it as an argument because the writer includes
	// the same file and declares cameraPosition of its own.
	vec3 subBlockOffset,
	// The game's own block light level here, which is the floor the fill's level
	// is added to.
	float blockLight,
	// The light level the fill carries here, in blocks of reach. Zero wherever the
	// fill has nothing to say.
	out float fillLevel,
	// How much of this fragment's block light the field owns, in [0, 1]. One well
	// inside the grid, zero outside it. BATCH 746: the caller REPLACES the
	// lightmap's level with the field's by this weight rather than adding them.
	out float fieldWeight
) {
	vec3 fallback = BlockLightTint(lightMapCoord);

	#ifdef BLOCK_LIGHT_FLOOD_FILL
		vec3 colored = LightVolumeBlockLight(
			fallback,
			fieldWorldPos,
			geometricNormal,
			subBlockOffset,
			blockLight,
			fillLevel,
			fieldWeight);
		return colored;
	#else
		fillLevel = 0.0;
		fieldWeight = 0.0;
		return fallback;
	#endif
}

// The curve that turns a light level into brightness.
//
// BATCH 748 REPLACED pow(level, 4.0) WITH THIS, AND THE AUTHOR IS THE REASON.
// His correction to the previous batch's framing was that the corner problem is
// not "replace vs fall back" at all - it is that our shadowed areas are simply
// too dark and the transition is not as natural as Eclipse's. That is a curve
// problem, and the fourth power was the curve.
//
// WHY THE FOURTH POWER WAS WRONG, IN TWO NUMBERS. At level 0.10 it returns
// 0.0001 where Eclipse's returns 0.0026 - 26 times darker - and at level 0.05 it
// is 103 times darker. That is the "black too hard". And its SLOPE at zero is
// zero: it lies flat and then explodes, so a one-voxel ramp in the level becomes
// a step in brightness. A curve that is flat then steep IS a hard edge, whatever
// the sampling does - which is why batch 747 could not find the corner by moving
// the normal offset, and why the offset turned out to be innocent.
//
// WHERE THE SHAPE COMES FROM. Eclipse's lib/diffuse_lighting.glsl:113-120:
//
//     float lightmapBrightspot = min(max(lightmap-0.7,0.0)*3.3333,1.0);
//     lightmapBrightspot *= lightmapBrightspot*lightmapBrightspot;
//     float lightmapLight = 1.0-sqrt(1.0-lightmap);
//     lightmapLight *= lightmapLight;
//     float lightmapCurve = mix(lightmapLight, 2.5, lightmapBrightspot);
//
// `lightmapLight` is the half taken here: (1 - sqrt(1 - x))^2. It rises
// immediately from zero, which is the natural transition, and it returns exactly
// 1.0 at full light.
//
// ⚠️ THE BRIGHTSPOT TERM IS DELIBERATELY NOT TAKEN, AND THIS IS THE ONE PLACE
// THIS PACK CANNOT FOLLOW ECLIPSE. That term lifts the curve to 2.5 at full
// light. Our function does not return the curve directly - it returns
//
//     envelope = min(1.0, blockLightIntensity + heldLightIntensity)
//
// so anything above 1.0 is clamped before BLOCKLIGHT_STRENGTH multiplies it.
// Eclipse's curve passes 1.0 at level 0.89, so dropped in verbatim everything
// from 0.89 to 1.0 would render IDENTICALLY: a surface beside a torch and one a
// block away would stop being distinguishable. That is a worse defect than the
// one being fixed, and it does not show up in a table that only compares the
// curves - only in the clamped output. The probe measures both.
//
// What the brightspot term does in Eclipse - make a surface right next to a
// source read as bright - is already what BLOCKLIGHT_STRENGTH does here, and
// doing it twice is what the clamp would turn into a flat top.
float BlockLightCurve(float level) {
	// Clamped because the field's level can exceed the game's ceiling near a
	// strong source, and a negative base under the sqrt would be NaN.
	level = clamp(level, 0.0, 1.0);

	float curve = 1.0 - sqrt(1.0 - level);
	return curve * curve;
}

vec3 BlockLighting(
	// Where this fragment sits in the lightmap, which is where the color of its
	// block light comes from.
	vec2 lightMapCoord,
	// Where this fragment is relative to the camera, and which way it faces,
	// which is what the flood fill is sampled by. See BlockLightColorAt.
	//
	// The position is the VERTEX stage's, for the reason given there: the field
	// is anchored to world blocks and the fragment-stage rebuild carries the view
	// bobbing's translation.
	//
	// The normal is the GEOMETRIC one, for the reason given there.
	vec3 fieldWorldPos,
	vec3 geometricNormal,
	float skyLight,
	float blockLight,
	float heldLight
) {
	// The brightness envelope, and what batch 739 changed about it.
	//
	// Until this batch the envelope was the whole of block light's brightness: the
	// game's own block light level, raised to the fourth power, times
	// BLOCKLIGHT_STRENGTH, and the flood fill only chose the colour that went
	// through it. That is why the fill read as a tint - a torch's colour could
	// reach a wall but could not make it brighter than the lightmap said.
	//
	// Now the fill carries a light level of its own, and the two are added before
	// the envelope is applied. The addition is what keeps the effect safe in both
	// directions: where the fill has nothing to say its level is zero and this is
	// exactly the multiplication it was, and where it does have something to say
	// the surface is lit by the light that actually reaches it. The lightmap's own
	// level is still the floor, so a surface the game says is lit never goes dark
	// because the fill could not see its source - which is the failure mode a
	// replacement rather than an addition would have.
	//
	// The two are clamped to the game's own maximum before the power, because the
	// sum can exceed it: a level-14 torch that the lightmap also calls 14 would
	// otherwise be raised to the fourth power at 28 and blow out. Fifteen is the
	// game's own ceiling and the one the fill's encoding is scaled to.
	float fillLevel;
	float fieldWeight;
	vec3 blockLightColor = BlockLightColorAt(
			lightMapCoord,
			fieldWorldPos,
			geometricNormal,
			// The grid's sub-block offset, which the consumer passes in because
			// the module cannot read cameraPosition itself - see the note there.
			fract(cameraPosition),
			blockLight,
			fillLevel,
			fieldWeight);

	// THE TWO TERMS ARE IN DIFFERENT UNITS, AND BATCH 740 IS THE FIX FOR IT.
	//
	// blockLight is the lightmap's own reading, normalised to 0..1: it arrives from
	// LightMapToLight (lib/encoding/lightmap.glsl), which returns the light level
	// over fifteen - level 15 is exactly 1.0 and level 0 is the floor. fillLevel is
	// a light level in blocks, 0..15, because that is what the fill's alpha channel
	// encodes and what LightVolumeBlockLight reports.
	//
	// Batch 739 added the two without converting, then divided the sum by fifteen.
	// That divided the lightmap's term by fifteen twice: a level-15 block arrived as
	// 1.0, became 1.0 / 15.0 = 0.0667, and the fourth power below turned it into
	// 2e-5 - effectively zero. The visible consequence was that the lightmap stopped
	// lighting anything and the voxel field became the only light in the frame,
	// which is why the fill read as a hard-edged bright map over everything, why
	// emitters barely glowed once the coloured lights were off, and why block
	// corners had dark seams where the field is empty and nothing could compensate.
	//
	// Scaling the lightmap term up to blocks first is the whole of the fix. This is
	// the same class of error as LESSONS 109: one quantity, two units.
	// BATCH 746: INSIDE THE GRID THE FIELD REPLACES THE LIGHTMAP, IT DOES NOT ADD
	// TO IT. This is reports C and D, which are one root cause.
	//
	// Until this batch this was
	//
	//     float combinedLight = min(blockLight * 15.0 + fillLevel, 15.0) / 15.0;
	//
	// which ADDS the game's own block light level to the field's. Two things
	// follow, and the author reported both:
	//
	//  * where the field has nothing to say, the sum is the lightmap's own level,
	//    so a surface inside the grid that no coloured light reaches is lit by the
	//    ordinary block light colour - "a different light colour showing through"
	//    (report C). It should be dark, because inside the grid the field is the
	//    whole answer.
	//  * where the field does have something to say, the surface gets the field's
	//    level AND the lightmap's, so coloured light inside the grid is brighter
	//    than ordinary light outside it (report D).
	//
	// Eclipse replaces: lib/diffuse_lighting.glsl:137 is
	//
	//     blockLight = mix(blockLight, lpvSample.rgb + lightColor * 2.5 * ..., voxelRangeFalloff);
	//
	// and inside the volume voxelRangeFalloff is 1, so its blockLight IS the
	// field's value. Outside it the lightmap is used. That is the shape here, with
	// fieldWeight - the edge fade - as the blend factor.
	//
	// WHY THE BLEND IS ON THE LEVEL AND NOT ON THE COLOUR. The two quantities are
	// both "how much block light is here", in the same unit: the field's level is a
	// number of blocks of reach, and blockLight * 15.0 is the game's own level in
	// the same unit. So they can be mixed directly, and the result is a level the
	// fourth power below turns into brightness. Mixing the colours instead would
	// leave the brightness wrong on both sides of the boundary.
	//
	// The clamp to 15 is kept: the field's level can exceed the game's ceiling near
	// a strong source, and the envelope is scaled to fifteen.
	float lightmapLevel = blockLight * 15.0;
	float combinedLevel = mix(lightmapLevel, fillLevel, fieldWeight);
	float combinedLight = min(combinedLevel, 15.0) / 15.0;

	float blockLightIntensity = BlockLightCurve(combinedLight);
	float heldLightIntensity = BlockLightCurve(heldLight);

	// Apply block light suppression (see details in shaders.properties).
	//
	// sqrt(skyLight) makes the suppression affect most areas impacted
	// by skylight.
	blockLightIntensity *= 1.0 - sqrt(skyLight) * blocklightSuppression;

	// For held light, we also suppress it if the player is standing in sky
	// light, so that suppressed light held by the player doesn't still get
	// cast into a cave or dark area nearby.
	float heldLightSkyLight = sqrt(max(skyLight, heldLightSuppression));
	heldLightIntensity *= 1.0 - heldLightSkyLight * blocklightSuppression;

	// BATCH 745: THE TWO TERMS NO LONGER SHARE ONE COLOUR.
	//
	// Until this batch this was
	//
	//     return blockLightColor
	//         * (BLOCKLIGHT_STRENGTH * min(1.0, blockLightIntensity + heldLightIntensity));
	//
	// which multiplies BOTH intensities by blockLightColor - the colour the flood
	// fill put at this fragment. The held light therefore took on whatever colour
	// the field happened to carry there, and where the field is empty it took the
	// fallback tint. A player holding a torch in a room lit by a soul lantern got
	// cyan light from his own torch; standing in a dark corner he got the pack's
	// warm default. Neither is the light the item gives off.
	//
	// The two are separate lights and they now have separate colours:
	//
	//   * block light keeps the field's colour, which is the whole point of the
	//     flood fill - it is the colour that actually arrives at this surface;
	//   * held light gets the pack's own block light colour, taken from the
	//     lightmap at full block light rather than at this fragment's own level.
	//     That is the game's answer to "what colour is block light", moved by
	//     BLOCKLIGHT_TEMPERATURE like everything else, and it is independent of
	//     both the field and this fragment's position - which is what a light
	//     carried by the player should be.
	//
	// WHY NOT THE HELD ITEM'S OWN COLOUR. The loader gives this shader a light
	// LEVEL (heldBlockLightValue, see shaders.properties) and nothing else - not
	// the item, not its texture. There is no colour to look up, so the honest
	// choice is the pack's own block light colour rather than a guess at what the
	// player is holding. A torch, a lantern and a glowstone all read as warm block
	// light, which is what they are.
	//
	// The clamp is kept, and it is now component-wise on the sum rather than on the
	// scalar before the multiply. The old form could not exceed one because the
	// colour was factored out; with two colours the sum has to be bounded after
	// they are applied, or a bright field plus a held torch would blow out.
	vec3 heldLightColor = BlockLightTint(vec2(1.0, 0.0));

	// The two intensities share one brightness envelope and are mixed by weight,
	// which is the same shape the fill uses to blend two colours meeting head-on
	// (see the level-weighted average in program/light_volume/step.csh). The
	// envelope is still the SUM, so the property the old comment was protecting -
	// no seam where the two lights intersect - is kept.
	//
	// With no held light this reduces exactly to the old expression:
	// heldLightIntensity is zero, so the weight is zero, the colour is
	// blockLightColor and the envelope is min(1.0, blockLightIntensity). That
	// identity is the reason for this shape rather than for two separate terms
	// added together: the overwhelming majority of fragments have no held light,
	// and they must come out of this function bit for bit as they did before.
	float lightSum = blockLightIntensity + heldLightIntensity;
	float envelope = min(1.0, lightSum);

	vec3 lightColor = lightSum > 1.0e-6
		? (blockLightColor * blockLightIntensity
			+ heldLightColor * heldLightIntensity) / lightSum
		: blockLightColor;

	return lightColor * (BLOCKLIGHT_STRENGTH * envelope);
}

// Tilt the path of the sun sideways. This is a standard shader effect that
// makes shadows look much better.
//
// Both declarations below were exposed to the menu in batch 669, following
// upstream Steadfast 0.9.0, which collects settings like these into its own
// pipeline file. The value is written as -40.0 rather than -40.0f so the
// loader can read a default out of the value list.
const float	sunPathRotation	= -40.0; // [-45.0 -40.0 -35.0 -30.0 -25.0 -20.0 -15.0 -10.0 -5.0 0.0 5.0 10.0 15.0 20.0 25.0 30.0 35.0 40.0 45.0]

// How much of the ambient occlusion the game bakes into block lighting is
// allowed to reach the shader. 1.0 is vanilla. Declaring it is what makes
// the value settable at all: with no declaration the loader uses 1.0 and
// the menu has nothing to show.
const float ambientOcclusionLevel = 1.0; // [0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0]

#if !defined(EXTERNALLY_DEFINED_UNIFORMS)
	uniform vec3 directLightSurface;
	uniform vec3 worldLightVector;
#endif

// The water's absorption of the light reaching a surface is NOT applied here any
// more, and that is batch 711.
//
// Until then this file carried ApplyWaterAbsorption: it took a water depth, turned
// it into a tint with WaterAbsorption, multiplied the surface's ambient and direct
// light by it, and swapped the sun's colour for the underwater one as it went.
// All of that was upstream Steadfast's design, and it ran in two places at once -
// here, per lit fragment, and once to the whole frame in copy_and_fog.fsh - while
// the depth it wanted was read out of the fragment's own sky light. A world
// surface's sky light is a real reading of how much water is above it; a model's is
// the light the game gives that model and carries no sky component under the
// surface at all, so the hand, an entity and the player's own model in third person
// were read as sixteen metres down and multiplied into the colour of the water
// behind them - the author's "see-through" (LESSONS 68, 87).
//
// The fix is not another reading of the same quantity. The pack already has the
// correct implementation of this physics and it is now the only one: the water
// medium in program/post/volumetric_fog.fsh attenuates per step of the view ray
// (WaterAbsorption(stepLength/16)), and composite1 applies that transmittance to
// everything drawn by then - models included - in every tier where the fog runs.
// See the note at the top of /environment/water/absorption.glsl.

struct SurfaceFragment {
	// The fragment's position relative to the camera, in world axes.
	//
	// This used to sit inside the REAL_TIME_SHADOWS block below, because the only
	// thing in this struct that read it was the shadow map. The flood fill reads
	// it too, and the flood fill has nothing to do with shadows, so the field is
	// unconditional now - the same field with a wider guard rather than a second
	// copy of it. See BlockLightColorAt.
	vec3 cameraRelativePos;
	// The same fragment's position, but taken from the VERTEX stage instead of
	// rebuilt here, and this is the one the coloured light field is sampled by.
	//
	// The two are the same value whenever the view is not bobbing, and they
	// differ by about a tenth of a block when it is. cameraRelativePos above is
	// rebuilt from gl_FragCoord as transpose(mat3(gbufferModelView)) * viewPos,
	// and with View Bobbing on that matrix is affine - vanilla's bobView opens
	// with a translate() - so the 3x3 transpose cannot undo the translation and
	// the rebuild carries a residual that contains no position at all: a
	// constant per-frame offset whose direction turns with the camera's heading.
	// The field is a voxel grid anchored to world blocks, so that offset changes
	// the level read at a fixed world position, by an amount set by the local
	// slope of the staircase - nothing at a ring centre, tens of percent on a
	// ring boundary. That is the author's pulsing rings.
	//
	// This one comes from lit.vsh as the full 4x4 inverse applied to the
	// position the geometry was drawn at, which is exact. It is the same value
	// the portal effect samples, and the reason the portal has never been
	// affected by the bob.
	//
	// cameraRelativePos is deliberately NOT replaced by this. It has more than
	// twenty readers - the shadow map, the held light, the portals, the
	// reflections - and none of them is wrong; only the field moves.
	vec3 fieldWorldPos;
	#if defined(REAL_TIME_SHADOWS)
		// The projected shadow map position to sample from.
		//
		// X and Y are coordinates in the shadow map texture, and Z is the
		// depth value to compare the sampled shadow depth against to
		// determine to what extent the fragment is or is not in shadow.
		vec3 shadowPos;
	#endif
	// The linear RGB color of the surface at this position, including all AO
	// and tinting.
	vec3 surfaceColor;
	// The predefined material ID of this fragment.
	uint materialID;
	// The normal vector of the surface where this fragment is, in world-space.
	vec3 worldNormal;
	// The same surface's geometric normal: the face the block actually has,
	// before any normal map is applied to it.
	//
	// The coloured light field is sampled along this one rather than along
	// worldNormal above, and the reason is what the field is. It is a voxel grid
	// aligned to blocks, and the offset along the normal exists to move the
	// sample off the surface and into the empty voxel on the visible side. Which
	// voxel next to a block is empty is a property of the block's geometry, not
	// of the shading detail painted on its surface: a normal map describes how
	// light bounces off a surface, and says nothing about which neighbouring
	// voxel is air. Offsetting along the mapped normal also imports that map's
	// view-dependent level-of-detail fade into a quantity that has no business
	// being view-dependent - see LIGHT_VOLUME_NORMAL_OFFSET in
	// /environment/lighting/light_volume.glsl.
	//
	// It is a second field rather than a replacement for worldNormal because the
	// two are read by different things: the shading terms want the mapped normal,
	// and only the field wants this one.
	vec3 geometricNormal;
	// This fragment's coordinate in the lightmap, which is where the color of
	// block light is read from. Not folded into the block light strength below
	// because the color has to be looked up, not computed.
	vec2 lightMapCoord;
	// The sky light strength, where 1 is light level 15 and 0 is no light.
	float skyLight;
	// The block light strength, where 1 is light level 15 and 0 is no light.
	float blockLight;
	// The held light strength, where 1 is light level 15 and 0 is no light.
	float heldLight;
};

float DirectLighting(
	SurfaceFragment fragment,
	bool subsurfaceScatter,
	PbrSurface pbr,
	vec3 viewDirection,
	// The specular reflection of this light, in linear RGB. Left at zero for
	// every material that does not reflect anything.
	out vec3 specular,
	// How much of the direct light survives the shadow sources, where 1.0 is
	// fully lit. Read by the subsurface scattering term in
	// PbrSubsurfaceScatter, which is a fraction of the light that arrives.
	out float shadowVisibility,
	// The colour the direct light arrives in, white unless stained glass stood in
	// its way. Written by ShadowMapping on every path through it.
	out vec3 shadowTint
) {
	// Note: these are set before any of the early outs below, so that callers
	// never read an undefined value.
	specular = vec3(0.0);
	shadowVisibility = 0.0;
	shadowTint = vec3(1.0);

	// Derive the direct lighting contribution (directLightStrength), which for
	// most surfaces is Lambertian:
	//
	// - Only faces directly facing the light source receive the full intensity
	// - Faces gradually darken as the angle between them and the light
	// approaches 90 degrees
	// - Faces that are facing away from the light receive none of the light
	float directLightStrength = dot(fragment.worldNormal, worldLightVector);

	// Foliage and glass diverge from the pure Lambertian lighting model to
	// account for their subsurface scattering, which lets sunlight partially
	// pass through the foliage surface.
	if (subsurfaceScatter) {
		// The direct light strength is overridden in the shadow-mapping code to
		// 0.7071 (~= cos(pi/4)) within the shadow map for materials with
		// subsurface scattering.
		//
		// Outside of the shadow map, that would be too bright, so we darken
		// based on direction like so:
		if (fragment.materialID == LEAVES) {
			directLightStrength = directLightStrength * 0.50 + 0.50;
		} else {
			directLightStrength = directLightStrength * 0.35 + 0.65;
		}
	} else if (fragment.materialID == GLASS) {
		// Because glass is transparent / translucent and does not cast shadows,
		// directional shading looks implausible on it, hence we use a different
		// shading model.
		directLightStrength = fragment.worldNormal.y * 0.2071 + 0.5;
	} else {
		#ifndef DIRECTIONAL_SKYLIGHT_SHADING
			// Stylized lighting model:
			//
			// - Faces facing the light source in nearly any way receive the
			// full light intensity
			// - Faces that approach 90 degrees or more away from the light
			// rapidly fade to dark
			// - Faces that are facing away from the light receive no light
			directLightStrength = smoothstep(-0.05, 0.05, directLightStrength);
		#else
			directLightStrength = max(directLightStrength, 0.0);
		#endif

		// Only sample the shadow map if this face can receive shadows. Glass
		// and materials with subsurface scattering can always receive shadows.
		if (directLightStrength < 0.0001) {
			return 0.0;
		}
	}

	// Fade away direct lighting based on the sky lighting.
	//
	// Otherwise, the intensity of direct sunlight would otherwise be the same
	// as on land even for deep underwater terrain!
	//
	// In addition, as ambient light brightness decreases as the sky light
	// strength decreases, this is necessary even if we are not underwater, as
	// otherwise darker ambient environments look really odd when the direct
	// light is bright but the ambient light is dark.
	//
	// However, we allow a very very small direct light lower bound to allow for
	// some shadows deep underwater / etc.
	//
	// TODO: This is also the only reason why there is any light in the End.
	directLightStrength *= max(fragment.skyLight, 0.125 / 16.0);

	// This static (lightmap) shadowing technique is a way of treating areas
	// with less than a full skylight level as being shaded. At a distance, it
	// is difficult to notice, and far more visually appealing than terrain
	// without any shadows. The technique and tuned fading factors are from:
	//
	// - Photon Shaders by SixthSurge:
	// https://github.com/sixthsurge/photon
	// 
	// File /shaders/include/lighting/shadows.glsl#L56-L59 as of commit
	// 26c2906ee02cc484359b835fba6993d443d45966
	float shadowSample = smoothstep(
		// Everything darker than this will be fully in shadow
		13.5 / 15.0,
		// Everything lighter than this will be fully lit
		14.5 / 15.0,
		fragment.skyLight);

	#ifdef REAL_TIME_SHADOWS
		directLightStrength = ShadowMapping(
			fragment.materialID,
			shadowSample,
			subsurfaceScatter,
			directLightStrength,
			fragment.shadowPos,
			fragment.cameraRelativePos,
			// Zero unless PBR_SUBSURFACE is on and this material's specular map
			// says it is thin, which is what confines the shadow softening to
			// the feature. See PbrDecode.
			pbr.sss,
			shadowVisibility,
			shadowTint);
	#else
		directLightStrength *= shadowSample;
		shadowVisibility = shadowSample;
		// No shadow map, so no buffer of colours that came through glass either -
		// see COLORED_SHADOWS in /environment/materialIDs.glsl.
		shadowTint = vec3(1.0);
	#endif

	#ifdef PBR_SURFACE
		// The height field can stand between this point and the light, which is
		// what gives the displaced surface visible sides. This is applied before
		// the specular below so that the highlight is occluded along with the
		// diffuse light. It never affects ambient light, which does not come
		// from one direction and so cannot be blocked by a bump.
		directLightStrength *= pbr.selfShadow;
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR)
		// Compute the specular reflection before the metalness reduction below,
		// as the highlight is not affected by how much diffuse response the
		// material keeps.
		//
		// We deliberately pass directLightStrength through as the light term
		// rather than recomputing N·L: it already carries both the shadow map
		// result and the pack's sky light falloff, so the highlight is occluded
		// exactly like the diffuse light is and the shadow map is never sampled
		// a second time.
		specular = PbrSpecular(
			pbr,
			fragment.worldNormal,
			worldLightVector,
			viewDirection,
			directLightStrength);

		#if defined(PBR_ENERGY_CONSERVATION)
			// What the surface did not reflect is what lights it from the
			// inside. Applied before the metal reduction below, which removes
			// the rest of the diffuse response a metal should not have.
			directLightStrength *= PbrDirectDiffuseWeight(
				pbr,
				worldLightVector,
				viewDirection);
		#endif

		// Metals have no diffuse response of their own. See PBR_METAL_DIFFUSE
		// for why this is only a partial reduction.
		directLightStrength *= 1.0 - PBR_METAL_DIFFUSE * pbr.metalness;
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_POROSITY_WETNESS)
		// Rain darkens a porous surface by filling the pores that its light
		// response comes from.
		//
		// Applied after the specular above for the same reason the metal
		// reduction just above is: a wet surface reflects more of its
		// surroundings, not less, so the highlight must not be dimmed along with
		// the diffuse light.
		directLightStrength *= 1.0 - PbrWetnessDarkening(pbr, fragment.skyLight);
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SUBSURFACE)
		// The light that goes through the surface instead of bouncing off it,
		// added to the direct light because it is a fraction of it.
		//
		// This is done after the specular above, so the highlight is built from
		// the light that reflects off the surface and is not lit by the light
		// that comes through it. It is also deliberately not routed through the
		// metal reduction just above, as a surface that scatters is thin and a
		// metal is not.
		directLightStrength += PbrSubsurfaceScatter(
			pbr,
			fragment.worldNormal,
			worldLightVector,
			viewDirection,
			shadowVisibility);
	#endif

	return directLightStrength;
}

// The shared implementation of the lighting model. Programs that have no PBR
// material data available pass PbrNone(), which makes the PBR branches below
// compile-time dead code - see the two wrappers underneath.
vec3 DiffuseLightingImpl(
	SurfaceFragment fragment,
	PbrSurface pbr,
	// The direction from this fragment towards the camera, in world space.
	vec3 viewDirection
) {
	// How much of the colour this returns is a mirror rather than light the
	// surface was given, in linear RGB. Two things make it up: the highlight of
	// the sun or moon, and the environment term further down.
	//
	// It is local now. Until batch 709 it was an out parameter, because the bloom
	// subtracted it back out of the frame; the author removed that, so the one
	// caller that wanted it out of here is gone and nothing else ever read it.
	// Set before any of the early outs below, so that it is defined on every path
	// - the same rule the two outputs of DirectLighting follow.
	vec3 specularColor = vec3(0.0);

	// Part of approximating subsurface scattering
	bool subsurfaceScatter = fragment.materialID == SUBSURFACE_SCATTERING
		|| fragment.materialID == GROUND_FOLIAGE
		|| fragment.materialID == LEAVES;

	// Strength of the ambient lighting contribution (sky & min ambient)
	float ambientStrength = AmbientStrength(
		subsurfaceScatter ? 0.7071 : fragment.worldNormal.y);

	vec3 lighting = AmbientSkyLighting(
		// When night vision is active, treat everything as fully lit by sky
		// light.
		max(fragment.skyLight, nightVision),
		ambientStrength);

	// The End's own light, which is zero in every other dimension. Its sky
	// gives no sky light at all, so everything above contributes almost nothing
	// there and its islands would otherwise be lit by the ambient floor alone -
	// which is what actually lights them, at a level the pack's own
	// MIN_AMBIENT_BRIGHTNESS sets. This is a brightening on top of that; see
	// the note in end_lighting.glsl.
	lighting += EndAmbientLighting(ambientStrength);

	// Compute the contribution to indirect lighting from block light without
	// immediately applying it. When water absorption is enabled, for gameplay
	// purposes we tweak the amount of water absorption applied to blocklight
	// based on depth to avoid ruining submerged bases.
	vec3 blocklightIndirect = BlockLighting(
		fragment.lightMapCoord,
		// The vertex stage's position, not fragment.cameraRelativePos: the field
		// is anchored to world blocks and the fragment-stage rebuild carries the
		// view bobbing's translation. See SurfaceFragment.fieldWorldPos.
		fragment.fieldWorldPos,
		// The geometric normal, not fragment.worldNormal: the field is a voxel
		// grid and the offset picks the empty voxel on this side of the surface,
		// which is a property of the block's geometry rather than of the shading
		// detail painted on it. See SurfaceFragment.geometricNormal.
		fragment.geometricNormal,
		fragment.skyLight,
		fragment.blockLight,
		fragment.heldLight
	);

	vec3 directLightColor = directLightSurface;

	// Block light goes in as it is. Upstream Steadfast held it back and added it by
	// hand here, interleaved with the water absorption of the surface's light, and
	// batch 711 removed all of that - the reason, and where the physics lives now,
	// is at the note where ApplyWaterAbsorption used to be, above SurfaceFragment.
	lighting += blocklightIndirect;

	#ifdef PBR_SURFACE
		// The occlusion the resource pack baked into the material, which only
		// says anything about light that arrives from no particular direction -
		// the sky's ambient light and the block light around the fragment.
		// Applying it here, before the environment reflection reads the same
		// value below, is what makes a crevice reflect less of the sky as well
		// as receive less of it.
		//
		// The direct sunlight added further down is deliberately left alone: a
		// baked occlusion map has no idea where the sun is, and the shadow map
		// and the parallax height field already darken what the light cannot
		// reach, so applying both would darken sunlit surfaces twice.
		//
		// Water absorption above has already run, so it scales the absorbed
		// result rather than being scaled by it - which is what it should be,
		// as the absorption describes how much light the water takes away, not
		// how much the material lets through.
		lighting *= PbrMaterialOcclusion(pbr);
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR)
		// Everything that is not direct lighting, which is what stands in for
		// the environment a surface reflects. Captured here because the direct
		// lighting is added to `lighting` below.
		vec3 indirectLighting = lighting;
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_POROSITY_WETNESS)
		// The same wet darkening as in DirectLighting, for everything that is
		// not direct light.
		//
		// Placed after the environment reflection has read the light above, for
		// the same reason it comes after the specular there: what is left of a
		// wet surface is a sheen, so the reflection is the one thing that should
		// not fade with it.
		lighting *= 1.0 - PbrWetnessDarkening(pbr, fragment.skyLight);
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR) && defined(PBR_ENERGY_CONSERVATION)
		// The same energy split as in DirectLighting, for everything that is not
		// direct light.
		//
		// Placed after the environment reflection above has read the light, so
		// that the environment is still reflected at full strength: it is the
		// diffuse response that has to give way for it, not the other way round.
		lighting *= PbrAmbientDiffuseWeight(pbr, fragment.worldNormal, viewDirection);
	#endif

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR)
		// A metal has no diffuse response at all, and this is the indirect half
		// of taking it away - the direct half is scaled in DirectLighting above,
		// for the same reason and by the same option.
		//
		// It has to be here rather than there because the two halves arrive by
		// different routes: the direct one is a single term, while this one is
		// the sky's ambient light, the block light around the fragment, the
		// ambient floor, the material's own occlusion and the dimension's
		// additions, already summed. Scaling the sum is the only place that
		// covers all of them.
		//
		// It is placed after indirectLighting was captured above and before the
		// ambient specular is added below, which is what keeps this from being
		// applied to the reflection: what a metal still has left is exactly that
		// reflection, and dimming it here would undo the same light twice.
		lighting *= 1.0 - PBR_METAL_DIFFUSE * pbr.metalness;
	#endif

	// The specular reflection of the direct lighting, which is zero for every
	// material that does not reflect anything.
	vec3 specular;

	// How much of the direct light survives the shadows. Only the subsurface
	// scattering term reads it, and it is written by DirectLighting on every
	// path through it.
	float shadowVisibility;

	// The colour the direct light arrives in, which is white until stained glass
	// colours it - see COLORED_SHADOWS in /environment/materialIDs.glsl. Written
	// by DirectLighting on every path through it as well.
	vec3 shadowTint = vec3(1.0);

	// Add in direct lighting, unless this program is one that can never receive
	// it. Three raise NEVER_RECEIVES_SHADOWS: the weather program, which is drawn
	// over the sky rather than in it; the Distant Horizons terrain and water
	// programs, which have no shadow map position; and every world program when
	// the shadow option is off, since lit.vsh raises it there when lit.fsh has
	// not defined REAL_TIME_SHADOWS. Without the term there is nothing to build a
	// highlight on either, which is what the #else branch says.
	#if !defined(NEVER_RECEIVES_SHADOWS)
		float directLightStrength = DirectLighting(
			fragment,
			subsurfaceScatter,
			pbr,
			viewDirection,
			specular,
			shadowVisibility,
			shadowTint);
	#else
		// Without shadow mapping there is no light visibility term to build a
		// highlight on top of, so PBR materials simply do not get one.
		specular = vec3(0.0);
		shadowVisibility = 1.0;
		float directLightStrength = 1.0;
	#endif

	// The tint belongs to the direct light and to nothing else: it is sunlight
	// that came through a window, where the ambient light around the fragment
	// did not. It is applied to the highlight along with the diffuse light,
	// because a highlight is the same light seen from a different angle.
	lighting += (vec3(directLightStrength) + specular) * directLightColor * shadowTint;

	// And the highlight is kept on its own as well as added to the lighting.
	//
	// Tinted by exactly what the line above tinted it with, so that this is the
	// same quantity the frame received: a highlight seen through stained glass
	// is removed in the colour it was added in, rather than in white.
	specularColor = specular * directLightColor * shadowTint;

	// The sun's own highlight, before the environment stand-in below is added to
	// the same variable. Only this one is taken back out of the albedo multiply
	// at the end - see the note there.
	vec3 directHighlight = specularColor;

	#if defined(PBR_SURFACE) && defined(PBR_SPECULAR)
		// Ice is left out while PBR_TRANSLUCENT is on: its reflections are drawn
		// by TranslucentLighting, which has both a direction and a screen-space
		// term, and adding this crude environment term on top of that would
		// count the same light twice. Note that ice reflects nothing underground
		// either way, since the other term fades out with the sky light.
		bool skipAmbientSpecular = false;
		#ifdef PBR_TRANSLUCENT
			skipAmbientSpecular = fragment.materialID == ICE;
		#endif

		if (!skipAmbientSpecular) {
			// The environment reflection, so that a material responds to the
			// light around it and not only to the sun and moon.
			//
			// Held in a variable of its own rather than added straight into the
			// lighting, because it belongs to the specular total below as well:
			// this is the second of the two terms that make it up.
			vec3 ambientSpecular = PbrAmbientSpecular(
				pbr,
				fragment.worldNormal,
				viewDirection,
				indirectLighting,
				fragment.skyLight);

			lighting += ambientSpecular;
			specularColor += ambientSpecular;
		}
	#endif

	vec3 surfaceColor = fragment.surfaceColor;

	#ifdef NIGHT_DESATURATION_EFFECT
		float desaturation = NightDesaturation(
			fragment.skyLight,
			max(fragment.blockLight, fragment.heldLight)
		);

		surfaceColor = Desaturate(surfaceColor, desaturation);
	#endif

	// The same multiplication by the surface colour that the return below does,
	// and after the night desaturation for the same reason the return is: what
	// is wanted is not something proportional to the highlight but the exact
	// part of the returned colour that the highlight contributed, so that
	// subtracting it leaves what the surface would have looked like without it.
	specularColor *= surfaceColor;

	// Emission is deliberately not added here: it is added by the caller, so
	// that everything that glows goes through one place. See lit.fsh.
	//
	// Only the SUN's highlight is taken back out of the albedo multiply, and
	// put back tinted the way the material itself tints it - white for a
	// dielectric, the surface colour for a metal. That is what Bliss does with
	// its metalAlbedoTint (lib/specular.glsl:370), and it is right for a
	// highlight: it is the light source seen in the surface, and a dielectric
	// does not colour the light it reflects.
	//
	// The environment stand-in is deliberately NOT treated that way. It
	// stands in for the light around the fragment rather than for a source, and
	// taking it out of the albedo multiply turns it into a white wash over every
	// dark material - which is what it did: at night and in the Nether, where
	// there is no sun to make a highlight and all that is left is that stand-in,
	// every surface went pale. It stays inside the multiply, as it always was.
	return surfaceColor * (lighting - directHighlight)
		+ directHighlight * mix(vec3(1.0), surfaceColor, pbr.metalness);
}

// Lighting for everything that has no PBR material data: entities, held items,
// Distant Horizons terrain, Voxy terrain, and every program at all when PBR is
// turned off.
vec3 DiffuseLighting(SurfaceFragment fragment) {
	// There is no material here, so nothing this call shades reflects anything
	// and the specular total inside the implementation can only come out zero.
	return DiffuseLightingImpl(fragment, PbrNone(), vec3(0.0));
}

#ifdef PBR_SURFACE
	vec3 DiffuseLighting(
		SurfaceFragment fragment,
		PbrSurface pbr,
		vec3 viewDirection
	) {
		return DiffuseLightingImpl(fragment, pbr, viewDirection);
	}
#endif
