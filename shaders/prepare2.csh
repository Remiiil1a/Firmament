#version 430
// The water interaction simulation's second sub-step, entry point.
//
// It sits at the root, with every other program this pack draws with, and not in
// a dimension folder. The porting kit puts its copy in world0/ because Photon
// keeps its overworld programs there; this pack keeps all of its at the root and
// only overrides individual programs per dimension (see world-1/ and world1/), so
// the root is where Iris looks for a program that only exists once.
//
// That means the pass also runs in the nether and the end. It costs two small
// dispatches there and changes nothing: a wave only gets injected where the player
// is actually in water (WaterInteractionSourceActive in
// environment/water/water_interaction.glsl), so a world with no water stays calm,
// and the field the water programs read stays zero.
//
// #version 430 comes first because compute programs need it and the program this
// includes carries no version line of its own.
#include "/program/water_interaction/step_b.csh"
