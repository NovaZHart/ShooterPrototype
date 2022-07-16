#ifndef PLANET_HPP
#define PLANET_HPP

#include <vector>
#include <unordered_map>

#include "Vector3.hpp"
#include "Transform.hpp"
#include "String.hpp"
#include "NodePath.hpp"
#include "RID.hpp"
#include "Dictionary.hpp"

#include "CE/ObjectIdGenerator.hpp"
#include "CE/CelestialObject.hpp"

namespace godot {
  namespace CE {
    struct ShipGoalData;
    class Ship;
    
    class Planet: public CelestialObject {
      std::vector<ShipGoalData> goal_data;
    public:
      const object_id id;
      const Vector3 rotation, position;
      const Transform transform;
      const String name;
      const NodePath scene_tree_path;
      const RID rid;
      const real_t radius;
      const float population, industry;
      
      Planet(Dictionary dict,object_id id);
      ~Planet();
      Dictionary update_status() const;
      void update_goal_data(const Planet &other);
      void update_goal_data(const std::unordered_map<object_id,Ship> &ships);
      inline const std::vector<ShipGoalData> &get_goal_data() const { return goal_data; }

      inline Vector3 get_position() const {
        return position;
      }
      inline Vector3 get_rotation() const {
        return rotation;
      }

      void get_object_info(CelestialInfo &info) const override;
      object_id get_object_id() const override;
      real_t get_object_radius() const override;
      Vector3 get_object_xyz() const override;
      Vector2 get_object_xz() const override;
    };

    typedef std::unordered_map<object_id,Planet>::iterator planets_iter;
    typedef std::unordered_map<object_id,Planet>::const_iterator planets_const_iter;
  }
}

#endif
