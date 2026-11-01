#version 430
// The light volume's propagation step, for the nether.
//
// This file exists only because of how Iris picks programs per dimension: a worldN
// folder is a *complete* set, not a set of overrides - Iris reads the programs for
// the nether out of world-1/ and falls back to the root folder for none of them
// (Iris documentation, "worldN Legacy"; BATCH_LOG.md 351 reached the same reading).
// A pass that lives only at the root therefore does not run in the nether or the
// end at all, whatever shaders.properties says about it, and this batch learned
// that the hard way: without this copy nothing in the nether writes the field every
// terrain program in it samples - so the samples are whatever the image holds, and
// the shading side has no ready flag of its own to tell it so.
//
// So there is one copy per dimension set, and all three are the same program: the
// fill has nothing dimension-specific to say - lava and soul fire colour the nether
// the way a torch colours the overworld, and the field is only the hue of light the
// lightmap has already decided exists. The copies are kept as separate files rather
// than shared because that is the only arrangement Iris loads.
#include "/program/light_volume/step.csh"
