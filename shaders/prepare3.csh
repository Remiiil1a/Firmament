#version 430
// Colored block light: the flood fill's propagation step, entry point.
//
// This is the overworld's copy. The nether and the end have their own, under
// world-1/ and world1/, and that is not a preference: a worldN folder is a
// *complete* program set, so Iris reads the nether's programs out of world-1/ and
// falls back to this folder for none of them (Iris documentation, "worldN Legacy").
// A pass that existed only here would simply not run in those two dimensions, and
// what the batch that added this learned from getting that wrong is written out in
// world-1/prepare3.csh.
//
// What it does is one step of the fill per frame, in the prepare stage - after the
// shadow pass that writes the world image it reads, and before the gbuffer programs
// that read the field it writes.
//
// What it costs, in every dimension equally, is one dispatch of 64 cubed
// invocations per frame - 262144 threads, one per voxel - and a two-megabyte
// write into the current field, with the world image and six neighbours of every
// voxel read on top of that. It is the same cost in an empty world as in a lit
// one: a voxel the fill has nothing to say about is stored as black, not skipped.
//
// #version 430 comes first because compute programs need it and the program this
// includes carries no version line of its own.
#include "/program/light_volume/step.csh"
