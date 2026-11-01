#version 430
#define WATER_SIM_END_DIMENSION
// The water interaction simulation's first sub-step, for the End.
//
// It is the same program as the root one, with one define in front of it: the End has
// no weather and no tide, and the water there is under a lighter pull, so the step it
// runs is slower and calmer than the overworld's. The define is also what lets the
// End's copy be switched off on its own - see WATER_SIM_END in
// environment/water/water_interaction.glsl.
//
// It lives under world1/ so that only the End picks it up. Iris looks a program up in
// the current dimension's folder first, so the overworld and the nether keep running
// the root copies and never see this one.
#include "/program/water_interaction/step_a.csh"
