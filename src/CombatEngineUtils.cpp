#include "CombatEngineUtils.hpp"

#include <limits>
#include <cstdint>

using namespace godot;
using namespace godot::CE;
using namespace std;

// from https://burtleburtle.net/bob/hash/integer.html
uint32_t godot::CE::bob_full_avalanche(uint32_t a) {
    a = (a+0x7ed55d16) + (a<<12);
    a = (a^0xc761c23c) ^ (a>>19);
    a = (a+0x165667b1) + (a<<5);
    a = (a+0xd3a2646c) ^ (a<<9);
    a = (a+0xfd7046c5) + (a<<3);
    a = (a^0xb55a4f09) ^ (a>>16);
    return a;
}

godot::CE::select_mask::select_mask(int mask):
  mask(mask)
{}

godot::CE::select_nearest::select_nearest(const Vector3 &to):
  to(Vector3(to.x,0,to.z)),
  closest(numeric_limits<real_t>::infinity())
{}

