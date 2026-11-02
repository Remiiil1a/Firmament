#version 430
// The light volume's propagation step, for the nether.
//
// This file exists because a worldN folder is a *complete* program set: Iris reads
// the nether's programs out of world-1/ and falls back to the root folder for none
// of them (Iris documentation, "worldN Legacy"). A pass that lives only at the root
// does not run in the nether or the end at all, and batch 696 shipped that mistake
// once - see world1/prepare3.csh's history in BATCH_LOG.md 696/700.
//
// Same program as the root copy: the fill has nothing dimension-specific to say -
// lava and soul fire colour the nether the way a torch colours the overworld.
#include "/program/light_volume/step.csh"
