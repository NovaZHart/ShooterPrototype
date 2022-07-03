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

#include "CE/Faction.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

goal_action_t FactionGoal::action_enum_for_string(String string_goal) {
  if(string_goal=="raid")
    return goal_raid;
  else if(string_goal=="planet")
    return goal_planet;
  else if(string_goal=="arriving_merchant")
    return goal_avoid_and_land;
  else
    return goal_patrol;
}

object_id FactionGoal::id_for_rid(const RID &rid,const rid2id_t &rid2id) {
  rid2id_t::const_iterator rit = rid2id.find(rid.get_id());
  return rit==rid2id.end() ? -1 : rit->second;
}

FactionGoal::FactionGoal(Dictionary dict,const unordered_map<object_id,Planet> &planets,
                         const rid2id_t &rid2id):
  action(action_enum_for_string(get<String>(dict,"action"))),
  target_faction(get<faction_index_t>(dict,"target_faction")),
  target_rid(get<RID>(dict,"target_rid")),
  target_object_id(id_for_rid(target_rid,rid2id)),
  weight(get<float>(dict,"weight")),
  radius(get<float>(dict,"radius")),
  goal_success(0.0f),
  spawn_desire(0.0f),
  suggested_spawn_point(0.0f,0.0f,0.0f)
{
  if(target_object_id>=0) {
    planets_const_iter pit = planets.find(target_object_id);
    if(pit!=planets.end()) {
      suggested_spawn_point = pit->second.position;
      suggested_spawn_path = pit->second.scene_tree_path;
    }
  }
}

FactionGoal::~FactionGoal() {}

void Faction::make_state_for_gdscript(Dictionary &factions) {
  Array goal_status, spawn_desire, suggested_spawn_point, suggested_spawn_path;
  for(auto &goal : goals) {
    goal_status.append(static_cast<real_t>(goal.goal_success));
    spawn_desire.append(static_cast<real_t>(goal.spawn_desire));
    suggested_spawn_point.append(goal.suggested_spawn_point);
    suggested_spawn_path.append(goal.suggested_spawn_path);
  }
  Dictionary result;
  result["goal_status"] = goal_status;
  result["spawn_desire"] = spawn_desire;
  result["suggested_spawn_point"] = suggested_spawn_point;
  result["suggested_spawn_path"] = suggested_spawn_path;

  // Reset the recouped resources accumulator when reporting back.
  result["recouped_resources"] = recouped_resources;
  recouped_resources = 0;

  factions[static_cast<int>(faction_index)] = result;
}

void Faction::update_masks(const unordered_map<int,float> &affinities) {
  faction_mask_t new_enemy = 0;
  faction_mask_t new_friend = 0;
  const faction_mask_t one(1);
  for(faction_index_t i=0;i<FACTION_ARRAY_SIZE;i++)
    if(i!=faction_index) {
      int key = affinity_key(faction_index,i);
      unordered_map<int,float>::const_iterator it = affinities.find(key);
      float affinity = (it==affinities.end()) ? DEFAULT_AFFINITY : it->second;
      if(affinity>AFFINITY_EPSILON)
        new_friend |= one<<i;
      else if(affinity<-AFFINITY_EPSILON)
        new_enemy |= one<<i;
    }
  enemy_mask = new_enemy;
  friend_mask = new_friend;
}

Faction::Faction(Dictionary dict,const unordered_map<object_id,Planet> &planets,
                 const rid2id_t &rid2id):
  faction_index(get<faction_index_t>(dict,"faction")),
  threat_per_second(get<float>(dict,"threat_per_second")),
  faction_color(get<Color>(dict,"faction_color",Color(0.2,0.2,0.7,1.0))),
  recouped_resources(0),
  goals(), target_advice(), enemy_mask(0), friend_mask(0)
{
  Array goal_array = get<Array>(dict,"goals");
  goals.reserve(goal_array.size());
  for(int i=0,s=goal_array.size();i<s;i++)
    goals.emplace_back(goal_array[i],planets,rid2id);
}

Faction::~Faction() {}
