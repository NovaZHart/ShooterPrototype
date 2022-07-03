#ifndef COMBATENGINETYPES_HPP
#define COMBATENGINETYPES_HPP

#include <unordered_map>
#include <cstdint>
#include <vector>
#include <algorithm>

#include "RID.hpp"
#include "Vector3.hpp"

#include "ObjectIdGenerator.hpp"

namespace godot {
  namespace CE {
    typedef int64_t ticks_t;
    typedef int faction_index_t;
    typedef uint64_t faction_mask_t;
  }
}

#endif
