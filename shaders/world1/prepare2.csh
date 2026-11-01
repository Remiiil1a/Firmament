#version 430
#define WATER_SIM_END_DIMENSION
// The water interaction simulation's second sub-step, for the End.
//
// It is the same program as the root one, with one define in front of it: the End has
// no weather and no tide, and the water there is under a lighter pull, so the step it
// runs is slower and calmer than the overworld's. The define is also what lets the
// End's copy be switched off on its own - see WATER_SIM_END in
// environment/water/water_interaction.glsl.
//
// It lives under world1/ because a worldN folder is a *complete* program set: the
// End reads its programs out of this folder and gets nothing from the root one (Iris
// documentation, "worldN Legacy"). So this is not an override of the root copy, it is
// the only copy the End has - and the consequence nobody had written down is that the
// nether, which has no prepare2.csh of its own, runs no water simulation at all. That
// costs nothing today because there is no water in the nether; see BATCH_LOG.md 696,
// where the same rule caught the light volume's propagation pass.
#include "/program/water_interaction/step_b.csh"
