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
// absorption method below is read by the surface programs, the deferred pass and the
// composite pass, and the same #define twice is still a redefinition. (This file also
// held the underwater haze from batch 715 to batch 717; batch 718 moved that to the
// water's own coefficients, in environment/water/absorption.glsl.)
#ifndef INCLUDE_ENVIRONMENT_WATER_ABSORPTION_SETTINGS
#define INCLUDE_ENVIRONMENT_WATER_ABSORPTION_SETTINGS

#define NO_ABSORPTION 0
#define REFRACTION_ASSISTED 1

// TODO: Remove this
#define WATER_ABSORPTION_METHOD REFRACTION_ASSISTED // [NO_ABSORPTION REFRACTION_ASSISTED]

#endif // INCLUDE_ENVIRONMENT_WATER_ABSORPTION_SETTINGS