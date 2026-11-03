#version 430
// Colored block light: the flood fill's propagation step, entry point.
//
// This is the overworld's copy. The nether and the end have their own, under
// world-1/ and world1/, and that is not a preference: a worldN folder is a
// *complete* program set, so Iris reads the nether's programs out of world-1/ and
// falls back to this folder for none of them (Iris documentation, "worldN Legacy";
// the same rule caught this pass in batch 696, which is why it has a copy per
// dimension set).
//
// WHY shadowcomp AND NOT prepare (batch 700). The pass reads the world image that
// the shadow program writes, and it has to read THIS frame's. Batch 696 put it in
// the prepare stage, on the strength of the documentation's wording; the author's
// screenshots in batch 699 settled what actually happens: the world image view
// showed the light sources and the terrain written into it, and the colour field
// view was pure black - the propagation was reading the world image before the
// shadow pass had filled it, every frame, for four batches. shadowcomp is the stage
// the loader runs directly after the shadow pass, and it is where Eclipse's LPV
// keeps the same step (its shadowcomp.csh), which is the reference this feature was
// built from.
//
// What it does is one step of the fill per frame: after the shadow pass that writes
// the world image it reads, and before the gbuffer programs that read the field it
// writes. What it costs, in every dimension equally, is one dispatch of
// LIGHT_VOLUME_SIZE cubed invocations per frame and a write of one volume into the
// current field, with the world image and six neighbours of every voxel read on top
// of that. Both follow COLORED_LIGHT_RANGE: 32,768 invocations and a quarter-megabyte
// write at 32, 2,097,152 invocations and a sixteen-megabyte write at 128. It is the
// same cost in an empty world as in a lit one: a voxel the fill has nothing to say
// about is stored as black, not skipped.
//
// #version 430 comes first because compute programs need it and the program this
// includes carries no version line of its own.
#include "/program/light_volume/step.csh"
