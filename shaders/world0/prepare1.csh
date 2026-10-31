#version 430
// The water interaction simulation's first sub-step, entry point.
//
// It lives in world0/ and not in the root, and that is the whole of how it is
// limited to the overworld: Iris looks for a program in the current dimension's
// folder first, so the nether and the end never find these two and never run
// the simulation. There is no water to stir there in the nether's case, and the
// end's water is the pack's own; either way the field stays zero and the water
// programs leave the surface alone.
//
// #version 430 first: compute programs need it, and the program file that this
// includes carries no version line of its own.
#include "/program/water_interaction/step_a.csh"
