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

#include "CE/CombatEngine.hpp"
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
  planet_goal_data(),
  goal_weight_data(),
  recouped_resources(0),
  goals(), target_advice(), enemy_mask(0), friend_mask(0),
  rand()
{
  Array goal_array = get<Array>(dict,"goals");
  goals.reserve(goal_array.size());
  for(int i=0,s=goal_array.size();i<s;i++)
    goals.emplace_back(goal_array[i],planets,rid2id);
}

Faction::~Faction() {}

PlanetGoalData Faction::update_planet_faction_goal(CombatEngine &ce, const Planet &planet, const FactionGoal &goal) {
  FAST_PROFILING_FUNCTION;
  float spawn_desire = min(100.0f,sqrtf(max(100.0f,planet.population))+sqrtf(max(0.0f,planet.industry)));
  PlanetGoalData result = { 0.0f,spawn_desire,-1 };
  
  if(goal.action == goal_planet) {
    result.goal_status = 1.0f;
    return result;
  }
  
  faction_mask_t one = static_cast<faction_mask_t>(1);
  faction_mask_t self_mask = one << faction_index;
  faction_mask_t target_mask = ce.get_enemy_mask(faction_index);
  target_mask = one<<goal.target_faction;
  
  float my_threat=0.0f, enemy_threat=0.0f;
  float radsq = goal.radius*goal.radius;
  for(auto &goal_datum : planet.get_goal_data()) {
    if(goal_datum.distsq>radsq)
      break;
    if(goal_datum.faction_mask==self_mask)
      my_threat = goal_datum.threat;
    else if(goal_datum.faction_mask&target_mask)
      enemy_threat = -goal_datum.threat;
  }
  float threat_weight = sqrtf(max(100.0f,fabsf(my_threat-enemy_threat))) / max(10.0f,threat_per_second*60);
  if(my_threat<enemy_threat)
    threat_weight = -threat_weight;

  result.planet = planet.id;
  result.goal_status = threat_weight;
  if(goal_raid)
    result.spawn_desire *= threat_weight;
  else
    result.spawn_desire *= -threat_weight;

  return result;
}

void Faction::update_one_faction_goal(CombatEngine &ce, FactionGoal &goal) {
  FAST_PROFILING_FUNCTION;
  
  planet_goal_data.reserve(ce.get_planets().size());
  goal_weight_data.reserve(ce.get_planets().size());
  planet_goal_data.clear();
  goal_weight_data.clear();

  vector<TargetAdvice> &target_advice = get_target_advice();
  int target_advice_start = target_advice.size();
  
  float accum = 0;
  float min_desire=0;
  float max_desire=0;
  for(planets_const_iter p_planet=ce.get_planets().begin();p_planet!=ce.get_planets().end();p_planet++) {
    object_id id = p_planet->first;
    if(goal.target_object_id>=0 and goal.target_object_id!=id) {
      //Godot::print("Skipping planet because it is not the target.");
      continue;
    }
    planet_goal_data.push_back(update_planet_faction_goal(ce,p_planet->second,goal));
    float spawn_desire = planet_goal_data.back().spawn_desire;
    if(planet_goal_data.size()<2)
      max_desire = min_desire = spawn_desire;
    else {
      min_desire = min(spawn_desire,min_desire);
      max_desire = max(spawn_desire,max_desire);
    }
    goal_weight_data.push_back(spawn_desire);
    TargetAdvice ta;
    ta.action = goal.action;
    ta.target_weight = spawn_desire;
    ta.radius = goal.radius;
    ta.planet = id;
    ta.position = p_planet->second.position;
    target_advice.push_back(ta);
  }

  for(size_t i=0;i<goal_weight_data.size();i++) {
    float &weight = goal_weight_data[i];
    weight -= min_desire;
    if(max_desire>min_desire)
      weight /= max_desire-min_desire;
    if(weight>1e-5)
      weight = 0.2 + 0.7*weight;
    accum += weight;
    weight = accum;
  }
  
  if(not goal_weight_data.size()) {
    //Godot::print("No goal weights. Bailing out.");
    goal.clear();
    return;
  }

  float val = accum * rand.randf();

  size_t i=0;
  while(i+1<goal_weight_data.size() and val>goal_weight_data[i])
    i++;

  const Planet *p_planet = ce.planet_with_id(planet_goal_data[i].planet);
  if(!p_planet) {
    //Godot::print("Planet goal data is invalid");
    goal.clear();
    return;
  }

  for(int j=target_advice_start,n=target_advice.size();j<n;j++) {
    if(max_desire==min_desire)
      target_advice[j].target_weight = 0.5;
    else {
      target_advice[j].target_weight -= min_desire;
      target_advice[j].target_weight /= max_desire-min_desire;
    }
    target_advice[j].target_weight *= goal.weight;
  }
  
  const Planet &planet = *p_planet;
  goal.suggested_spawn_point = planet.position;
  goal.suggested_spawn_path = planet.scene_tree_path;
  if(max_desire==min_desire)
    goal.spawn_desire = 0.5;
  else {
    goal.spawn_desire = (planet_goal_data[i].spawn_desire-min_desire);
    goal.spawn_desire /= max_desire-min_desire;
  }
  
  goal.goal_success = planet_goal_data[i].goal_status;
}
