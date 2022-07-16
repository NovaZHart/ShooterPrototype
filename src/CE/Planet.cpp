#include "CE/Data.hpp"
#include "CE/Utils.hpp"
#include "CE/MultiMeshManager.hpp"

#include <cstdint>
#include <cmath>
#include <limits>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>

#include "CE/Planet.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

Planet::Planet(Dictionary dict,object_id id):
  CelestialObject(PLANET),
  goal_data(),
  id(id),
  rotation(get<Vector3>(dict,"rotation")),
  position(get<Vector3>(dict,"position")),
  transform(get<Transform>(dict,"transform")),
  name(get<String>(dict,"name")),
  scene_tree_path(get<NodePath>(dict,"scene_tree_path")),
  rid(get<RID>(dict,"rid")),
  radius(get<real_t>(dict,"radius")),
  population(get<real_t>(dict,"population")),
  industry(get<real_t>(dict,"industry"))
{
  if(scene_tree_path.is_empty())
    Godot::print_warning(name+": planet has no scene tree path",__FUNCTION__,__FILE__,__LINE__);
}

Planet::~Planet()
{}

void Planet::get_object_info(CelestialInfo &info) const {
  info = { id, position, radius };
}
object_id Planet::get_object_id() const {
  return id;
}
real_t Planet::get_object_radius() const {
  return radius;
}
Vector3 Planet::get_object_xyz() const {
  return get_position();
}
Vector2 Planet::get_object_xz() const {
  return get_xz();
}

Dictionary Planet::update_status() const {
  Dictionary s;
  // s["rotation"] = rotation;
  // s["position"] = position;
  // s["transform"] = transform;
  s["type"] = "planet";
  s["name"] = name;
  s["rid"] = rid;
  s["radius"] = radius;
  s["alive"] = true;
  return s;
}

void Planet::update_goal_data(const Planet &other) {
  FAST_PROFILING_FUNCTION;
  goal_data = other.goal_data;
  for(auto &goal_datum : goal_data)
    goal_datum.distsq = goal_datum.position.distance_squared_to(position);
  sort(goal_data.begin(),goal_data.end(),[] (const ShipGoalData &a,const ShipGoalData &b) {
      return a.distsq<b.distsq;
    });
}

void Planet::update_goal_data(const std::unordered_map<object_id,Ship> &ships) {
  FAST_PROFILING_FUNCTION;
  goal_data.reserve(ships.size());
  goal_data.clear();
  for(ships_const_iter p_ship=ships.begin();p_ship!=ships.end();p_ship++) {
    ShipGoalData d = {
      p_ship->second.threat,
      p_ship->second.position.distance_squared_to(position),
      p_ship->second.faction_mask,
      p_ship->second.position
    };
    goal_data.emplace_back(d);
  }
  sort(goal_data.begin(),goal_data.end(),[] (const ShipGoalData &a,const ShipGoalData &b) {
      return a.distsq<b.distsq;
    });
}
