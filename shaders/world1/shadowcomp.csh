#version 430
// The light volume's propagation step, for the end.
//
// This file exists because a worldN folder is a *complete* program set: Iris reads
// the end's programs out of world1/ and falls back to the root folder for none of
// them (Iris documentation, "worldN Legacy"). A pass that lives only at the root
// does not run in the end or the nether at all, and batch 696 shipped that mistake
// once - see BATCH_LOG.md 696/700.
//
// Same program as the root copy: the end's block light is glowstone, end rods and
// shulkers, and the field is only the hue of light the lightmap has already decided
// exists. The water simulation's two End copies next to this one are the opposite
// case - they differ from the root copies by a define, because the End's water is
// under a lighter pull.
#include "/program/light_volume/step.csh"
