// Steadfast is a fast and high-quality graphical overhaul for Minecraft (JE)
// Copyright (C) 2026 coderbot
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

// One definition per translation unit, however many files include this one: the
// underwater haze below is read by both the fog and the composite pass, which puts
// it in the include graph of both (batch 715).
#ifndef INCLUDE_ENVIRONMENT_WATER_ABSORPTION_SETTINGS
#define INCLUDE_ENVIRONMENT_WATER_ABSORPTION_SETTINGS

#define NO_ABSORPTION 0
#define REFRACTION_ASSISTED 1

// TODO: Remove this
#define WATER_ABSORPTION_METHOD REFRACTION_ASSISTED // [NO_ABSORPTION REFRACTION_ASSISTED]

// How thick the water's own haze is, per block.
//
// This is the pack's underwater haze, and it is one number for two consumers: the
// distance fog environment/fog.glsl puts on the surfaces under the water, and the
// frame-wide boundary fog in composite1.fsh that hides where the loaded world ends
// (batch 715). It is a constant rather than an option because a haze with two knobs
// is two hazes, and because the water's colour already has its own setting
// (WATER_CHARACTER, environment/water/absorption.glsl). Batch 716 removed the option
// that briefly stood here: this is the value it defaulted to, and upstream Steadfast
// 0.9.0 has no such switch in its water settings either.
//
// Before that it had been written into the fog's own water branch instead - 0.02,
// with no control at all, which is what the author's "the near field is far too blue
// and there is nothing to turn it down" was about. 0.012 is thinner than that number,
// because that is the direction the report was in.
const float UNDERWATER_HAZE_PER_METRE = 0.012;


#endif // INCLUDE_ENVIRONMENT_WATER_ABSORPTION_SETTINGS