#ifndef INSTANCEEFFECT_HPP
#define INSTANCEEFFECT_HPP

#include "CE/ObjectIdGenerator.hpp"

namespace godot {
  namespace CE {

    // Visual effect with full mesh instance data.
    struct InstanceEffect {
      const object_id mesh_id;
      Transform transform;
      Color color_data, instance_data;
      Vector2 half_size;
    };
  }
}
#endif
