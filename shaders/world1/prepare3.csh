#version 430
// The light volume's propagation step, for the end.
//
// This file exists only because of how Iris picks programs per dimension: a worldN
// folder is a *complete* set, not a set of overrides - Iris reads the programs for
// the end out of world1/ and falls back to the root folder for none of them (Iris
// documentation, "worldN Legacy"; BATCH_LOG.md 351 reached the same reading). A pass
// that lives only at the root therefore does not run in the end or the nether at
// all, whatever shaders.properties says about it, and this batch learned that the
// hard way: without this copy nothing in the end writes the field every terrain
// program in it samples - so the samples are whatever the image holds, and the
// shading side has no ready flag of its own to tell it so.
//
// So there is one copy per dimension set, and all three are the same program: the
// fill has nothing dimension-specific to say - the end's block light is glowstone,
// end rods and shulkers, and the field is only the hue of light the lightmap has
// already decided exists. The copies are kept as separate files rather than shared
// because that is the only arrangement Iris loads. The water simulation's two End
// copies next to this one are the opposite case: they differ from the root copies
// by a define, because the End's water is under a lighter pull.
#include "/program/light_volume/step.csh"
