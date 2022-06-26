#include <cstdint>
#include <cmath>
#include <limits>
#include <map>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>
#include <RID.hpp>

#include "CombatEngine.hpp"
#include "CombatEngineUtils.hpp"
#include "CombatEngineData.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

const Color hostile_color(1,0,0,1);
const Color friendly_color(0,0,1,1);
const Color player_color(0,1,0,1);
const Color neutral_color(0.7,0.7,0.7);
const Color projectile_color = neutral_color;
const Color planet_color = neutral_color;

Dictionary CombatEngine::space_intersect_ray(PhysicsDirectSpaceState *space,Vector3 point1,Vector3 point2,int mask) {
  FAST_PROFILING_FUNCTION;
  if(not ship_locations.ray_is_nonempty(Vector2(point1.x,point1.z),Vector2(point2.x,point2.z)))
    return Dictionary();
  static Array empty = Array();
  return space->intersect_ray(point1,point2,empty,mask);
}

CombatEngine::CombatEngine():
  visual_effects(),
  multimeshes(),
  search_cylinder(CylinderShape::_new()),
  physics_server(PhysicsServer::get_singleton()),
  space(nullptr),
  
  rid2id(),
  planets(),
  ships(),
  projectiles(),
  player_orders(),
  weapon_rotations(),
  dead_ships(),
  idgen(),
  delta(1.0/60),
  idelta(delta*ticks_per_second),
  player_ship_id(-1),
  p_frame(0),
  
  factions(),
  affinities(),
  enemy_masks(),
  friend_masks(),
  self_masks(),
  need_to_update_affinity_masks(false),
  player_faction_index(0),
  player_faction_mask(static_cast<faction_mask_t>(1)<<player_faction_index),
  last_planet_updated(-1),
  last_faction_updated(FACTION_ARRAY_SIZE),
  faction_info(),

  encoded_salvaged_items(),
  flotsam_locations(position_box_size),
  ship_locations(position_box_size),

  update_request_id(),
  planet_goal_data(),
  goal_weight_data(),
  rand(),
  
  visual_server(VisualServer::get_singleton()),
  v_delta(0),
  v_camera_location(FAR,FAR,FAR),
  v_camera_size(BIG,BIG,BIG),
  scenario(),
  canvas(),
  reset_scenario(false),

  objects_found(),
  search_results(),

  content()

{
  search_cylinder->set_radius(search_cylinder_radius);
  search_cylinder->set_height(30);

  update_request_id.reserve(max_ships/10);
  objects_found.reserve(max_ships*10);
  rid2id.reserve(max_ships*10+max_planets);
  planets.reserve(max_planets);
  ships.reserve(max_ships);
  projectiles.reserve(max_ships*50);
  player_orders.reserve(50);
  search_results.reserve(100);
  dead_ships.reserve(max_ships/2);

  ship_locations.reserve(max_ships*1.5,max_ships*5*1.5);
}

CombatEngine::~CombatEngine() {}

void CombatEngine::_register_methods() {
  register_method("set_visual_effects", &CombatEngine::set_visual_effects);
  register_method("clear_ai", &CombatEngine::clear_ai);
  register_method("clear_visuals", &CombatEngine::clear_visuals);
  register_method("set_system_stats", &CombatEngine::set_system_stats);
  register_method("prepare_visual_frame", &CombatEngine::prepare_visual_frame);
  register_method("update_overhead_view", &CombatEngine::update_overhead_view);
  register_method("draw_minimap_contents", &CombatEngine::draw_minimap_contents);
  register_method("draw_minimap_rect_contents", &CombatEngine::draw_minimap_rect_contents);
  register_method("ai_step", &CombatEngine::ai_step);
  register_method("init_factions", &CombatEngine::init_factions);
}

void CombatEngine::_init() {}

/**********************************************************************/

/* Registered Methods */

/**********************************************************************/

void CombatEngine::clear_visuals() {
  // NOTE: entry point from gdscript
  multimeshes.clear_all_multimeshes();
}

void CombatEngine::clear_ai() {
  //NOTE: entry point from gdscript
  FAST_PROFILING_FUNCTION;
  
  // WARNING: caller must ensure no other CombatEngine call is active while running this.

  // Tell the AI to forget everything.
  planets.clear();
  ships.clear();
  projectiles.clear();
  player_orders.clear();
  dead_ships.clear();
  weapon_rotations.clear();
  missile_locations.clear();
  flotsam_locations.clear();
  ship_locations.clear();
  factions.clear();
  affinities.clear();
  for(int i=0;i<FACTION_ARRAY_SIZE;i++)
    enemy_masks[i] = friend_masks[i] = self_masks[i] = 0;
  need_to_update_affinity_masks=false;
  player_faction_index=0;
  player_faction_mask=1;
  last_planet_updated=-1;
  last_faction_updated=FACTION_ARRAY_SIZE;
  faction_info.clear();

  // Wipe out all visual content.
  content.clear();
}

void CombatEngine::set_visual_effects(Ref<VisualEffects> visual_effects) {
  this->visual_effects = visual_effects;
}

void CombatEngine::init_factions(Dictionary data) {
  FAST_PROFILING_FUNCTION;
  Dictionary affinity_data = data["affinities"];
  Array affinity_keys = affinity_data.keys();
  for(int i=0,s=affinity_keys.size();i<s;i++) {
    Variant key = affinity_keys[i];
    affinities[static_cast<int>(key)] = affinity_data[key];
  }

  Array active_factions = data["active_factions"];
  for(int i=0,s=active_factions.size();i<s;i++) {
    Dictionary faction_data = active_factions[i];
    faction_index_t faction_index = static_cast<faction_index_t>(faction_data["faction"]);
    factions.emplace(faction_index,Faction(faction_data,planets,rid2id));
  }

  player_faction_index = data["player_faction"];
  player_faction_mask = static_cast<faction_mask_t>(1)<<player_faction_index;

  update_affinity_masks();
}

// Main entry point to the AI code from godot.
Array CombatEngine::ai_step(real_t new_delta,Array new_ships,Array new_planets,
                            Array new_player_orders,RID player_ship_rid,
                            PhysicsDirectSpaceState *new_space,
                            Array update_request_rid) {
  FAST_PROFILING_FUNCTION;

  p_frame++;
  
  delta = new_delta;
  idelta = roundf(new_delta*ticks_per_second);
  ai_ticks += idelta;
  
  space = new_space;

  // Clear arrays and add any new ships or planets.
  setup_ai_step(new_player_orders,new_ships,new_planets,player_ship_rid);
  
  // Obtain the current state of each ship from the physics server.
  // Any that have no state were removed by another thread and are no
  // longer alive.
  update_ship_body_state();
  
  //FIXME: r*tree: update_position_map();

  // Integrate projectiles one timestep and delete dead ones
  integrate_projectiles();

  // Run ship AI one time step.
  step_all_ships();

  // If anyone shot a friend, the affinities may change.
  if(need_to_update_affinity_masks)
    update_affinity_masks();
  
  // Physics space may be deleted outside of the combat engine due to
  // a scene change, so do not retain the pointer.
  space=nullptr;

  // Pass the visible objects over to the visual thread for display.
  add_content();
  visual_effects->add_content();
  
  // Update the faction-level AI:
  faction_ai_step();
  
  Array result;
  update_ship_list(update_request_rid,result);
  result.push_back(weapon_rotations);
  make_faction_state_for_gdscript(faction_info);
  result.push_back(faction_info);
  encode_salvaged_items_for_gdscript(encoded_salvaged_items);
  result.push_back(encoded_salvaged_items);
  salvaged_items.clear();
  return result;
}

void CombatEngine::set_system_stats(bool hyperspace, real_t system_fuel_recharge, real_t center_fuel_recharge) {
  FAST_PROFILING_FUNCTION;
  this->hyperspace = hyperspace;
  this->system_fuel_recharge = system_fuel_recharge;
  this->center_fuel_recharge = center_fuel_recharge;
}

void CombatEngine::prepare_visual_frame(RID new_scenario) {
  //NOTE: entry point from gdscript
  FAST_PROFILING_FUNCTION;
  scenario=new_scenario;
  reset_scenario=true;
}

void CombatEngine::update_overhead_view(Vector3 location,Vector3 size,real_t projectile_scale) {
  FAST_PROFILING_FUNCTION;
  //NOTE: entry point from gdscript

  // Time has passed:
  multimeshes.time_passed(delta);

  // Location is center of camera view and size is the world-space
  // distance from x=left-right z=top-bottom. Y values are ignored.
  
  if(not scenario.is_valid()) {
    // Nowhere to display anything
    Godot::print_error("Scenario has invalid id",__FUNCTION__,__FILE__,__LINE__);
    multimeshes.clear_all_multimeshes();
    return;
  }

  pair<bool,VisibleContent*> newflag_content = content.update_visible_content();

  if(not newflag_content.first) {
    // Nothing new to display or nothing to display:
    if(not newflag_content.second)
      // Nothing to display
      multimeshes.clear_all_multimeshes();
    return;
  }

  VisibleContent *visible_content=newflag_content.second;

  visual_server = VisualServer::get_singleton();
  
  v_camera_location = location;
  v_camera_size = size;

  visual_effects->add_content();
  
  // Catalog projectiles and make MeshInfos in v_meshes for mesh_ids we don't have yet
  multimeshes.update_content(*visible_content,location,size);
  multimeshes.load_meshes();
  multimeshes.send_meshes_to_visual_server(projectile_scale,scenario,reset_scenario);

  visual_effects->set_combat_content(visible_content);
}


void CombatEngine::draw_minimap_contents(RID new_canvas,
                                         Vector2 map_center, real_t map_radius,
                                         Vector2 minimap_center, real_t minimap_radius) {
  FAST_PROFILING_FUNCTION;
  //NOTE: entry point from gdscript
  canvas=new_canvas;

  VisibleContent *visible_content=content.get_visible_content();
  
  if(!visible_content)
    return; // Nothing to display yet.
  
  // Draw ships and planets.
  for(auto &id_object : visible_content->ships_and_planets) {
    VisibleObject &object = id_object.second;
    Vector2 center(object.z,-object.x);
    const Color &color = pick_object_color(object);
    Vector2 loc = place_center(Vector2(object.z,-object.x),
                               map_center,map_radius,minimap_center,minimap_radius);
    if(object.flags & VISIBLE_OBJECT_PLANET) {
      real_t rad = object.radius/map_radius*minimap_radius;
      if(object.flags&VISIBLE_OBJECT_PLAYER_TARGET)
        draw_crosshairs(loc,rad,color);
      draw_anulus(loc,rad*3-0.75,rad*3+0.75,color,false);
    } else { // ship
      visual_server->canvas_item_add_circle(canvas,loc,min(2.5f,object.radius/2.0f),color);
      if(object.flags&(VISIBLE_OBJECT_PLAYER_TARGET|VISIBLE_OBJECT_PLAYER)) {
        draw_heading(object,loc,map_center,map_radius,minimap_center,minimap_radius,color);
        draw_velocity(object,loc,map_center,map_radius,minimap_center,minimap_radius,color);
      }
    }
  }

  // Draw only the projectiles within the minimap; skip outsiders.
  real_t outside=minimap_radius*0.95;
  real_t outside_squared = outside*outside;
  for(auto &projectile : visible_content->effects) {
    Vector2 minimap_scaled = (Vector2(projectile.center.y,-projectile.center.x)-map_center) /
      map_radius*minimap_radius;
    if(minimap_scaled.length_squared() > outside_squared)
      continue;
    visual_server->canvas_item_add_circle(canvas,minimap_center+minimap_scaled,1,projectile_color);
  }
}



void CombatEngine::draw_minimap_rect_contents(RID new_canvas,Rect2 map,Rect2 minimap) {
  FAST_PROFILING_FUNCTION;
  //NOTE: entry point from gdscript
  canvas=new_canvas;

  VisibleContent *visible_content=content.get_visible_content();

  if(!visible_content)
    return; // Nothing to display yet.

  Vector2 map_center = map.position+map.size/2.0f;
  Vector2 minimap_center = minimap.position+minimap.size/2.0f;
  Vector2 map_half_size(fabsf(map.size.x)/2.0f,fabsf(map.size.y)/2.0f);
  Vector2 minimap_half_size(fabsf(minimap.size.x)/2.0f,fabsf(minimap.size.y)/2.0f);
  Vector2 map_scale(minimap_half_size.x/map_half_size.x,minimap_half_size.y/map_half_size.y);
  real_t radius_scale = map_scale.length();

  // Draw ships and planets.
  for(auto &id_object : visible_content->ships_and_planets) {
    VisibleObject &object = id_object.second;
    Vector2 center(object.z,-object.x);
    const Color &color = pick_object_color(object);
    Vector2 loc = place_in_rect(Vector2(object.z,-object.x),
                                map_center,map_scale,minimap_center,minimap_half_size);
    if(object.flags & VISIBLE_OBJECT_PLANET) {
      real_t rad = object.radius*radius_scale;
      if(object.flags&VISIBLE_OBJECT_PLAYER_TARGET)
        draw_crosshairs(loc,rad,color);
      draw_anulus(loc,rad,rad+0.75,color,false);
    } else { // ship
      visual_server->canvas_item_add_circle(canvas,loc,min(2.5f,object.radius),color);
      if(object.flags&(VISIBLE_OBJECT_PLAYER_TARGET|VISIBLE_OBJECT_PLAYER)) {
        rect_draw_heading(object,loc,map_center,map_scale,minimap_center,minimap_half_size,color);
        rect_draw_velocity(object,loc,map_center,map_scale,minimap_center,minimap_half_size,color);
      }
    }
  }

  // Draw only the projectiles within the minimap; skip outsiders.
  //real_t outside=minimap_radius*0.95;
  //real_t outside_squared = outside*outside;
  int proj=0;
  for(auto &projectile : visible_content->effects) {
    if(++proj>200)
      break;
    Vector2 scaled = (Vector2(projectile.center.y,-projectile.center.x)-map_center) *map_scale;
    if(scaled.x>minimap_half_size.x or scaled.x<-minimap_half_size.x or
       scaled.y>minimap_half_size.y or scaled.y<-minimap_half_size.y)
      continue;
    visual_server->canvas_item_add_circle(canvas,minimap_center+scaled,1,projectile_color);
  }
}


/**********************************************************************/

/* Factions */

/**********************************************************************/

void CombatEngine::change_relations(faction_index_t from_faction,faction_index_t to_faction,
                                    float how_much,bool immediate_update) {
  // WARNING: THIS FUNCTION IS UNTESTED!
  FAST_PROFILING_FUNCTION;
  if(how_much==0.0f)
    return;

  int key = Faction::affinity_key(from_faction,to_faction);
  unordered_map<int,float>::iterator it = affinities.find(key);

  if(it==affinities.end()) {
    need_to_update_affinity_masks=true;
    affinities.emplace(key,how_much);
  } else {
    float old_affinity = it->second;
    float new_affinity = old_affinity+how_much;
    affinities[key] = new_affinity;
    if(not need_to_update_affinity_masks)
      need_to_update_affinity_masks = (old_affinity<0.0f) != (new_affinity<0.0f);
  }
  if(need_to_update_affinity_masks and immediate_update)
    update_affinity_masks();
}

void CombatEngine::make_faction_state_for_gdscript(Dictionary &result) {
  for(factions_iter p_faction=factions.begin();p_faction!=factions.end();p_faction++)
    p_faction->second.make_state_for_gdscript(result);
}

void CombatEngine::update_affinity_masks() {
  FAST_PROFILING_FUNCTION;
  for(auto &it : factions)
    it.second.update_masks(affinities);
  faction_mask_t one = static_cast<faction_mask_t>(1);
  for(int i=MIN_ALLOWED_FACTION;i<=MAX_ALLOWED_FACTION;i++) {
    self_masks[i] = one<<i;
    enemy_masks[i]=0;
    friend_masks[i]=0;
    for(int j=MIN_ALLOWED_FACTION;j<=MAX_ALLOWED_FACTION;j++) {
      if(i==j)
        continue; // Ignore self-hatred and self-desire
      int key = Faction::affinity_key(i,j);
      unordered_map<int,float>::iterator it = affinities.find(key);
      if(it==affinities.end())
        continue;
      else if(it->second>AFFINITY_EPSILON)
        friend_masks[i] |= one<<j;
      else if(it->second<-AFFINITY_EPSILON)
        enemy_masks[i] |= one<<j;
    }
  }
  need_to_update_affinity_masks = false;
}

PlanetGoalData CombatEngine::update_planet_faction_goal(const Faction &faction, const Planet &planet, const FactionGoal &goal) const {
  FAST_PROFILING_FUNCTION;
  float spawn_desire = min(100.0f,sqrtf(max(100.0f,planet.population))+sqrtf(max(0.0f,planet.industry)));
  PlanetGoalData result = { 0.0f,spawn_desire,-1 };
  
  if(goal.action == goal_planet) {
    result.goal_status = 1.0f;
    return result;
  }
  
  faction_mask_t one = static_cast<faction_mask_t>(1);
  faction_mask_t self_mask = one << faction.faction_index;
  faction_mask_t target_mask = enemy_masks[faction.faction_index];
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
  float threat_weight = sqrtf(max(100.0f,fabsf(my_threat-enemy_threat))) / max(10.0f,faction.threat_per_second*60);
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

void CombatEngine::update_one_faction_goal(Faction &faction, FactionGoal &goal) const {
  FAST_PROFILING_FUNCTION;
  planet_goal_data.reserve(planets.size());
  goal_weight_data.reserve(planets.size());
  planet_goal_data.clear();
  goal_weight_data.clear();

  std::vector<TargetAdvice> &target_advice = faction.get_target_advice();
  int target_advice_start = target_advice.size();
  
  float accum = 0;
  float min_desire=0;
  float max_desire=0;
  for(planets_const_iter p_planet=planets.begin();p_planet!=planets.end();p_planet++) {
    object_id id = p_planet->first;
    if(goal.target_object_id>=0 and goal.target_object_id!=id) {
      //Godot::print("Skipping planet because it is not the target.");
      continue;
    }
    planet_goal_data.push_back(update_planet_faction_goal(faction,p_planet->second,goal));
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

  planets_const_iter p_planet = planets.find(planet_goal_data[i].planet);
  if(p_planet==planets.end()) {
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
  
  const Planet &planet = p_planet->second;
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

void CombatEngine::update_all_faction_goals() {
  FAST_PROFILING_FUNCTION;
  planets_iter p_first=planets.end();
  for(planets_iter p_planet=planets.begin();p_planet!=planets.end();p_planet++) {
    if(p_first==planets.end()) {
      p_first = p_planet;
      p_first->second.update_goal_data(ships);
    } else
      p_planet->second.update_goal_data(p_first->second);
  }
  int planet_count = planets.size();
  for(auto &p_faction : factions) {
    Faction &faction = p_faction.second;
    faction.clear_target_advice(planet_count);
    for(auto &goal : faction.get_goals())
      update_one_faction_goal(faction,goal);
  }
  last_planet_updated = -1;
  last_faction_updated = FACTION_ARRAY_SIZE;
}

void CombatEngine::faction_ai_step() {
  // FIXME: Get this working.
  //  if(ai_ticks<ticks_per_second/2)
    update_all_faction_goals();
  // if(p_frame % 2) {
  //   // Update a planet on odd frames
  //   planets_iter p_planet = planets.find(last_planet_updated);
  //   if(p_planet!=planets.end())
  //     p_planet++;
  //   if(p_planet==planets.end())
  //     p_planet=planets.begin();
  //   if(p_planet!=planets.end()) {
  //     p_planet->second.update_goal_data(ships);
  //     last_planet_updated = p_planet->first;
  //   } else
  //     last_planet_updated = -1;
  // } else {
  //   // Update a faction on even frames
  //   factions_iter p_faction = factions.find(last_faction_updated);
  //   if(p_faction!=factions.end())
  //     p_faction++;
  //   if(p_faction==factions.end())
  //     p_faction=factions.begin();
  //   if(p_faction!=factions.end()) {
  //     Faction &faction = p_faction->second;
  //     faction.clear_target_advice(planets.size());
  //     for(auto &goal : faction.get_goals())
  //       update_one_faction_goal(faction,goal);
  //     last_faction_updated = p_faction->first;
  //   } else
  //     last_faction_updated = FACTION_ARRAY_SIZE;
  // }
}

/**********************************************************************/

/* Ships and Planets */

/**********************************************************************/

void CombatEngine::setup_ai_step(const Array &new_player_orders, const Array &new_ships,
                                 const Array &new_planets, const RID &player_ship_rid) {
  FAST_PROFILING_FUNCTION;
  
  physics_server = PhysicsServer::get_singleton();
  update_player_orders(new_player_orders);
  weapon_rotations.clear();  
  add_ships_and_planets(new_ships,new_planets);

  rid2id_iter player_ship_id_p = rid2id.find(player_ship_rid.get_id());
  player_ship_id = (player_ship_id_p==rid2id.end()) ? -1 : player_ship_id_p->second;

  if(player_ship_id>-1 and player_orders.find(player_ship_id)==player_orders.end())
    player_orders.emplace(player_ship_id,PlayerOverrides());
}

void CombatEngine::step_all_ships() {
  FAST_PROFILING_FUNCTION;
  for(ships_iter p_ship=ships.begin();p_ship!=ships.end();p_ship++) {
    Ship &ship = p_ship->second;
    if(ship.fate) {
      if(ship.fate==FATED_TO_EXPLODE)
        explode_ship(ship);
      else {
        ship_locations.remove(ship.id);
      }
    } else {
      ship.advance_time(idelta);
      ai_step_ship(ship);
      negate_drag_force(ship);
      ship.update_stats(physics_server,hyperspace);
      ship_locations.set_rect(ship.id,ship.get_location_rect_now());
      if(not hyperspace and (ship.fate==FATED_TO_RIFT or ship.fate==FATED_TO_LAND)) {
        factions_iter p_faction = factions.find(ship.faction);
        if(p_faction!=factions.end())
          p_faction->second.recoup_resources(ship.recouped_resources());
      }
    }
  }
}

void CombatEngine::update_ship_body_state() {
  FAST_PROFILING_FUNCTION;

  // Obtain the current state of each ship from the physics server.
  // Any that have no state were removed by another thread and are no
  // longer alive.
  for(auto &p_ship : ships) {
    Ship &ship = p_ship.second;
    if(ship.fate==FATED_TO_DIE)
      continue;
    if(not ship.update_from_physics_server(physics_server,hyperspace))
      ship.fate=FATED_TO_DIE; // Ship was removed, so treat it as dead.
  }
}

void CombatEngine::update_ship_list(const Array &update_request_rid, Array &result) {
  FAST_PROFILING_FUNCTION;
  
  // Translate the godot array into a more useful form.
  update_request_id.clear();
  for(int i=0,size=update_request_rid.size();i<size;i++) {
    rid2id_iter there=rid2id.find(static_cast<RID>(update_request_rid[i]).get_id());
    if(there!=rid2id.end())
      update_request_id.insert(there->second);
  }
  
  // Last pass through ships: remove destroyed ships and pass
  // information back to gdscript data structures.
  //vector<object_id> deleteme;
  for(ships_iter p_ship=ships.begin();p_ship!=ships.end();) {
    Ship &ship = p_ship->second;
    if(ship.fate>0 or update_request_id.find(ship.id)!=update_request_id.end())
      result.append(ship.update_status(ships,planets));
    if(ship.fate>0) {
      ship.collision_layer = 0;
      physics_server->body_set_collision_layer(ship.rid,0);
      physics_server->body_set_state(ship.rid,PhysicsServer::BODY_STATE_CAN_SLEEP,true);
      physics_server->body_set_state(ship.rid,PhysicsServer::BODY_STATE_SLEEPING,true);
      p_ship=ships.erase(p_ship);
      //deleteme.push_back(p_ship->first);
    } else
      p_ship++;
  }
  // for(auto &id : deleteme)
  //   ships.erase(id);

  // Provide information about requested planets:
  for(auto &p_planet : planets) {
    Planet &planet = p_planet.second;
    if(update_request_id.find(planet.id)!=update_request_id.end())
      result.append(planet.update_status());
  }
}

void CombatEngine::add_ships_and_planets(const Array &new_ships,const Array &new_planets) {
  FAST_PROFILING_FUNCTION;
  
  // Add new planets
  for(int i=0,size=new_planets.size();i<size;i++) {
    Dictionary planet = static_cast<Dictionary>(new_planets[i]);
    object_id id = idgen.next();
    pair<planets_iter,bool> pp_planet = planets.emplace(id, Planet(planet,id));
    rid2id[pp_planet.first->second.rid.get_id()] = id;
  }
  
  rid2id_t has_initial_target;
  
  // Add new ships
  for(int i=0,size=new_ships.size();i<size;i++) {
    Dictionary ship = static_cast<Dictionary>(new_ships[i]);
    object_id id = idgen.next();
    if(ship.has("initial_target"))
      has_initial_target[static_cast<RID>(ship["initial_target"]).get_id()] = id;
    Ship new_ship = Ship(ship,id,multimeshes);
    pair<ships_iter,bool> pp_ship = ships.emplace(id,new_ship);
    rid2id[pp_ship.first->second.rid.get_id()] = id;
    //bool hostile = is_hostile_towards(pp_ship.first->second.faction,player_faction_index);
    pp_ship.first->second.collision_layer = pp_ship.first->second.faction_mask;
    physics_server->body_set_collision_layer(pp_ship.first->second.rid,pp_ship.first->second.collision_layer);
  }

  // Set initial targets, if relevant
  for(rid2id_const_iter it=has_initial_target.begin();it!=has_initial_target.end();it++) {
    rid2id_iter target_id_ptr = rid2id.find(it->first);
    if(target_id_ptr!=rid2id.end()) {
      ships_iter self_ptr = ships.find(it->second);
      if(self_ptr!=ships.end() and
         ( planets.find(target_id_ptr->second)!=planets.end() or
           ships.find(target_id_ptr->second)!=ships.end()))
        self_ptr->second.new_target(target_id_ptr->second);
    }
  }
}

void CombatEngine::update_player_orders(const Array &new_player_orders) {
  FAST_PROFILING_FUNCTION;
  player_orders.clear();
  for(int i=0,size=new_player_orders.size();i<size;i++) {
    Dictionary orders = static_cast<Dictionary>(new_player_orders[i]);
    if(orders.empty())
      continue;
    
    uint32_t rid = static_cast<int>(orders["rid_id"]);
    if(not rid)
      continue;
    
    rid2id_iter it = rid2id.find(rid);
    if(it==rid2id.end())
      continue;

    player_orders.emplace(it->second,PlayerOverrides(orders,rid2id));
  }
}

void CombatEngine::negate_drag_force(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  // Negate the drag force if the ship is below its max speed. Exceptions:
  // 1. If the ship is immobile due to entering orbit or a spatial rift.
  // 2. In hyperspace, if the ship has no fuel.
  if(ship.immobile or (hyperspace and ship.fuel<=0))
    return;
  if(ship.linear_velocity.length_squared()<ship.max_speed*ship.max_speed)
    physics_server->body_add_central_force(ship.rid,-ship.drag_force);
}

bool CombatEngine::rift_ai(Ship &ship) {
  deactivate_cargo_web(ship);
  FAST_PROFILING_FUNCTION;
  if(ship.rift_timer.alarmed()) {
    // If the ship has already opened the rift, and survived the minimum duration,
    // it can vanish into the rift.
    ship.fate = FATED_TO_RIFT;
  } else if(not ship.rift_timer.active()) {
    if(request_stop(ship,Vector3(0,0,0),3.0f)) {
      // Once the ship is stopped, paralyze it and open a rift.
      ship.immobile = true;
      ship.inactive = true;
      ship.damage_multiplier = ship.rifting_damage_multiplier;
      ship.rift_timer.reset();
      if(visual_effects.is_valid()) {
        Vector3 rift_position = ship.position;
        rift_position.y = ship.visual_height+1.1f;
        // if(rift_position.y<ship.position.y)
        //   Godot::print_warning(str("Rift is below ship: ")+str(rift_position.y)+"<"+str(ship.position.y),__FUNCTION__,__FILE__,__LINE__);
        // else
        //   Godot::print(str("Rift at ")+str(rift_position.y)+" ship at "+str(ship.position.y)+" radius "+str(ship.radius*1.5f));
        visual_effects->add_hyperspacing_polygon(SPATIAL_RIFT_LIFETIME_SECS*2,rift_position,ship.radius*1.5f,false,ship.id);
        // visual_effects->add_zap_pattern(SPATIAL_RIFT_LIFETIME_SECS,rift_position,ship.radius*2.0f,true);
        // visual_effects->add_zap_ball(SPATIAL_RIFT_LIFETIME_SECS*2,rift_position,ship.radius*1.5f,false);
      }
    } else
      return false;
  } else {
    // During the rift animation, shrink the ship.
    real_t rift_fraction = ship.rift_timer.ticks_left()/real_t(SPATIAL_RIFT_LIFETIME_TICKS*2);
    ship.set_scale(rift_fraction);
  }
  return true;
}

void CombatEngine::explode_ship(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.explosion_timer.alarmed()) {
    ship.fate=FATED_TO_DIE;
    if(ship.explosion_radius>0 and (ship.explosion_damage>0 or ship.explosion_impulse!=0)) {
      Ref<PhysicsShapeQueryParameters> query(PhysicsShapeQueryParameters::_new());
      query->set_shape(search_cylinder);
      Transform trans;
      real_t scale = ship.explosion_radius / search_cylinder_radius;
      if(not ship_locations.circle_is_nonempty(Vector2(ship.position.x,ship.position.z),ship.explosion_radius))
        return;
      trans.scale(Vector3(scale,1,scale));
      trans.origin = Vector3(ship.position.x,5,ship.position.z);
      //query->set_transform(Transform(scale,0,0, 0,1,0, 0,0,scale, trans_x,5,trans_z));
      query->set_transform(trans);
      Array hits = space->intersect_shape(query,100);
      for(int i=0,size=hits.size();i<size;i++) {
        Dictionary hit=static_cast<Dictionary>(hits[i]);
        if(hit.empty())
          continue;
        ships_iter p_ship = ship_for_rid(static_cast<RID>(hit["rid"]).get_id());
        if(p_ship==ships.end())
          continue;
        Ship &other = p_ship->second;
        if(other.id==ship.id)
          continue;
        real_t distance = max(0.0f,other.position.distance_to(ship.position)-other.radius);
        real_t dropoff = 1.0 - distance/ship.explosion_radius;
        dropoff*=dropoff;
        other.take_damage(ship.explosion_damage*dropoff,ship.explosion_type,0.1,0,0);
        if(other.immobile)
          continue;
        if(not ship.immobile and ship.explosion_impulse!=0) {
          Vector3 impulse = ship.explosion_impulse * dropoff *
            (other.position-ship.position).normalized();
          if(impulse.length_squared())
            physics_server->body_apply_central_impulse(other.rid,impulse);
        }
      }
    }
    create_flotsam(ship);
  }
}

void CombatEngine::heal_ship(Ship &ship) {
  ship.heal(hyperspace,system_fuel_recharge,center_fuel_recharge,delta);
}

void CombatEngine::ai_step_ship(Ship &ship) {
  FAST_PROFILING_FUNCTION;

  heal_ship(ship);
  ship.apply_heat_and_energy_costs(delta);

  if(ship.at_first_tick) {
    factions_const_iter faction_it = factions.find(ship.faction);
    if(faction_it!=factions.end()) {
      ship.shield_ellipse = visual_effects->add_shield_ellipse(ship,ship.aabb,0.1,0.35,faction_it->second.faction_color);
      Godot::print(ship.name+" has ellipse "+str(ship.shield_ellipse)+" with color "+str(faction_it->second.faction_color));
    } else
      Godot::print_warning(ship.name+": has no faction",__FUNCTION__,__FILE__,__LINE__);
  }

  if(ship.entry_method!=ENTRY_COMPLETE and not init_ship(ship))
    return; // Ship has not yet fully arrived.

  for(auto &weapon : ship.weapons)
    weapon.reload(ship,idelta);
  
  if(ship.rift_timer.active())
    rift_ai(ship);
  else {
    player_orders_iter orders_p = player_orders.find(ship.id);
    bool have_orders = orders_p!=player_orders.end();
    if(have_orders) {
      PlayerOverrides &orders = orders_p->second;
      if(not apply_player_orders(ship,orders))
        apply_player_goals(ship,orders);
    } else
      switch(ship.ai_type) {
      case PATROL_SHIP_AI: patrol_ship_ai(ship); return;
      case RAIDER_AI: raider_ai(ship); return;
      case ARRIVING_MERCHANT_AI: arriving_merchant_ai(ship); return;
      case DEPARTING_MERCHANT_AI: departing_merchant_ai(ship); return;
      default: attacker_ai(ship); return;
      }

    if(ship.confusion_timer.alarmed()) {
      ship.update_confusion();
      ship.confusion_timer.reset();
    }
  }
  
  if(ship.cargo_web_active)
    use_cargo_web(ship);
}

bool CombatEngine::init_ship(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  // return false = ship does nothing else this timestep
  if(ship.entry_method == ENTRY_FROM_ORBIT) {
    // Ships entering from orbit start at maximum speed.
    if(ship.max_speed>0 and ship.max_speed<999999)
      set_velocity(ship,ship.heading*ship.max_speed);
    ship.entry_method=ENTRY_COMPLETE;
    ship.damage_multiplier=1.0;
    return false;
  } else if(ship.entry_method != ENTRY_FROM_RIFT and
            ship.entry_method != ENTRY_FROM_RIFT_STATIONARY) {
    // Invalid entry method; treat it as ENTRY_COMPLETE.
    ship.entry_method=ENTRY_COMPLETE;
    ship.damage_multiplier=1.0;
    return false;
  }
  if(ship.at_first_tick) {
    // Ship is arriving via spatial rift. Trigger the animation and start a timer.
    ship.immobile=true;
    ship.inactive=true;
    ship.damage_multiplier = ship.rifting_damage_multiplier;
    ship.rift_timer.reset();
    if(visual_effects.is_valid()) {
      Vector3 rift_position = ship.position;
      rift_position.y = ship.visual_height+1.1f;
      // if(rift_position.y<ship.position.y)
      //   Godot::print_warning(str("Rift is below ship: ")+str(rift_position.y)+"<"+str(ship.position.y),__FUNCTION__,__FILE__,__LINE__);
      // else
      //   Godot::print(str("Rift at ")+str(rift_position.y)+" ship at "+str(ship.position.y));
      visual_effects->add_hyperspacing_polygon(SPATIAL_RIFT_LIFETIME_SECS,rift_position,ship.radius*1.5f,true,ship.id);
      //visual_effects->add_zap_pattern(SPATIAL_RIFT_LIFETIME_SECS,rift_position,ship.radius*2.0f,true);
      //visual_effects->add_zap_ball(SPATIAL_RIFT_LIFETIME_SECS,rift_position,ship.radius*1.5f,true);
    } else
      Godot::print_warning("No visual_effects!!",__FUNCTION__,__FILE__,__LINE__);
    set_angular_velocity(ship,Vector3(0.0,15.0+ship.rand.randf()*15.0,0.0));
    return false;
  } else if(ship.rift_timer.alarmed()) {
    // Rift animation just completed.
    ship.rift_timer.clear_alarm();
    ship.immobile=false;
    ship.inactive=false;
    ship.damage_multiplier=1.0;
    if(ship.max_speed>0 and ship.max_speed<999999 and
       ship.entry_method!=ENTRY_FROM_RIFT_STATIONARY)
      set_velocity(ship,ship.heading*ship.max_speed);
    set_angular_velocity(ship,Vector3(0.0,0.0,0.0));
    ship.entry_method=ENTRY_COMPLETE;
    return false;
  }
  return false; // rift animation not yet complete
}

bool CombatEngine::apply_player_orders(Ship &ship,PlayerOverrides &overrides) {
  FAST_PROFILING_FUNCTION;
  // Returns true if goals should be ignored. This happens if the player
  // orders thrust, firing, or rotation.
  bool rotation=false, thrust=false;
  int target_selection = overrides.change_target&PLAYER_TARGET_SELECTION;
  bool target_nearest = overrides.change_target&PLAYER_TARGET_NEAREST;

  if(target_selection) {
    object_id target=ship.get_target();
    if(target_selection==PLAYER_TARGET_OVERRIDE) {
      target=overrides.target_id;
    } else {
      if(target_selection==PLAYER_TARGET_NOTHING) {
        target=-1;
      } else if(target_selection==PLAYER_TARGET_PLANET) {
        if(target_nearest) {
          target=select_target(target,select_nearest(ship.position),planets,false);
        } else {
          target=select_target(target,[] (const planets_const_iter &_p) { return true; },planets,true);
        }
      } else if(target_selection==PLAYER_TARGET_ENEMY or target_selection==PLAYER_TARGET_FRIEND) {
        int mask=0x7fffffff;
        if(target_selection==PLAYER_TARGET_ENEMY) {
          mask=enemy_masks[ship.faction];
          Godot::print("Player targets enemy with mask "+str(mask));
        } else if(target_selection==PLAYER_TARGET_FRIEND) {
          mask=friend_masks[ship.faction];
          Godot::print("Player targets enemy with mask "+str(mask));
        }
        if(target_nearest) {
          target=select_target(target,select_three(select_mask(mask),select_flying(),select_nearest(ship.position)),ships,false);
          Godot::print("Player targets nearest flying ship to "+str(ship.position));
        } else {
          target=select_target(target,select_two(select_mask(mask),select_flying()),ships,true);
          Godot::print("Player targets next flying ship");
        }
      }
      
      ship.new_target(target);
      overrides.target_id = target;
    }
  }

  if(overrides.orders&PLAYER_ORDER_AUTO_TARGET)
    ship.should_autotarget = not ship.should_autotarget;
  
  if(overrides.orders&PLAYER_ORDER_STOP_SHIP) {
    request_stop(ship,Vector3(0,0,0),3.0f);
    thrust = rotation = true;
  }

  if(overrides.orders&PLAYER_ORDER_TOGGLE_CARGO_WEB) {
    if(!ship.cargo_web_active)
      activate_cargo_web(ship);
    else
      deactivate_cargo_web(ship);
  }
  
  if(!rotation and fabsf(overrides.manual_rotation)>1e-5) {
    request_rotation(ship,overrides.manual_rotation);
    rotation=true;
  }
   
  if(!thrust and fabsf(overrides.manual_thrust)>1e-5) {
    request_thrust(ship,clamp(overrides.manual_thrust,0.0f,1.0f),
                   clamp(-overrides.manual_thrust,0.0f,1.0f));
    thrust=true;
  }
  
  if(!rotation)
    request_rotation(ship,0);

  if(overrides.orders&PLAYER_ORDER_FIRE_PRIMARIES) {
    ships_iter target_ptr = ships.find(ship.get_target());
    if(not rotation and ship.should_autotarget and target_ptr!=ships.end()) {
      bool in_range=false;
      Vector3 aim = aim_forward(ship,target_ptr->second,in_range);
        request_heading(ship,aim);
        rotation=true;
    }
    aim_turrets(ship,target_ptr);
    fire_primary_weapons(ship);
  }
  fire_antimissile_turrets(ship);
  return thrust or rotation;
}

void CombatEngine::activate_cargo_web(Ship &ship) {
  if(ship.cargo_web_active)
    return;
  ship.cargo_web_active = true;
  if(visual_effects.is_valid()) {
    if(ship.shield_ellipse>=0)
      visual_effects->set_visibility(ship.shield_ellipse,false);
    if(ship.cargo_web>=0)
      visual_effects->reset_effect(ship.cargo_web);
    else
      ship.cargo_web=visual_effects->add_cargo_web(ship,get_faction_color(ship.faction));
  }
}
void CombatEngine::deactivate_cargo_web(Ship &ship) {
  if(!ship.cargo_web_active)
    return;
  ship.cargo_web_active = false;
  if(visual_effects.is_valid()) {
    if(ship.shield_ellipse>=0)
      visual_effects->set_visibility(ship.shield_ellipse,true);
    if(ship.cargo_web>=0)
      visual_effects->set_visibility(ship.cargo_web,false);
  }
}

pair<DVector3,double> CombatEngine::plot_collision_course(DVector3 relative_position,DVector3 target_velocity,double max_speed) {
  FAST_PROFILING_FUNCTION;
  // Returns desired velocity vector and time to collision.
  double target_speed = target_velocity.length();
  DVector3 relative_heading = relative_position.normalized();     // VrHat

  if(target_speed>max_speed)
    // Special case: cannot catch up to target. Instead, fly towards it.
    return pair<DVector3,double>(relative_heading*max_speed,NAN);
  
  double sina = cross2(relative_heading,target_velocity)/max_speed; // (VrHat x V0Hat) * v0Hat/vg
  double relative_angle = asin_clamp(sina);
  double distance = relative_position.length();
  double start_angle = angle_from_unit(relative_heading);         // angle of VrHat
  DVector3 course = unit_from_angle_d(start_angle+relative_angle)*max_speed;
  DVector3 relative_course = course-target_velocity;
  double relative_speed = max(0.01,relative_course.length());
  
  return pair<DVector3,double>(course,distance/relative_speed);
}

void CombatEngine::use_cargo_web(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  Rect2 cargo_web_rect = rect_for_circle(ship.position,ship.cargo_web_radius);
  objects_found.clear();
  flotsam_locations.overlapping_rect(cargo_web_rect,objects_found);
  real_t thrust=ship.cargo_web_strength;
  for(auto &id : objects_found) {
    projectiles_iter proj_ptr = projectiles.find(id);
    if(proj_ptr!=projectiles.end()) {
      Projectile &proj = proj_ptr->second;
      
      Vector3 dp = ship.position-proj.position;

      real_t distsq = lensq2(dp);
      
      if(distsq>ship.cargo_web_radiussq)
        continue;
      if(!proj.possible_hit)
        proj.possible_hit = distsq<ship.radiussq;

      real_t terminal_velocity = thrust/max(.01f,proj.drag*proj.mass);
      pair<DVector3,double> collision_course = plot_collision_course(dp,ship.linear_velocity,terminal_velocity);
      //Vector3 velocity_correction = collision_course.first-proj.linear_velocity;
      //proj.forces += velocity_correction.normalized()*thrust;

      proj.forces += collision_course.first.normalized()*thrust;

      if(ship.rand.randf()<30*delta) {
        Vector3 ship_position(ship.position.x,ship.visual_height,ship.position.z);
        Vector3 puff_velocity = (ship.rand.randf()*0.1 + 0.3)*(collision_course.first);
        Vector3 random_perturbation = Vector3((ship.rand.randf()-1)/2,ship.rand.randf()/10,(ship.rand.randf()-1)/2);
        Vector3 puff_location = Vector3(proj.position.x,-1,proj.position.z)+random_perturbation;
        real_t duration = isnan(collision_course.second) ? .4f : collision_course.second;
        duration*=3.5;
        visual_effects->add_cargo_web_puff_MMIEffect(ship,puff_location,puff_velocity,1,duration,ship.cargo_puff_mesh);
      }
    }
  }
}

bool CombatEngine::apply_player_goals(Ship &ship,PlayerOverrides &overrides) {
  FAST_PROFILING_FUNCTION;
  for(int i=0;i<PLAYER_ORDERS_MAX_GOALS;i++)
    switch(overrides.goals.goal[i]) {
    case PLAYER_GOAL_ATTACKER_AI: {
      attacker_ai(ship);
      return true;
    }
    case PLAYER_GOAL_LANDING_AI: {
      planets_iter planet_p = planets.find(overrides.target_id);
      if(planet_p!=planets.end())
        ship.new_target(planet_p->first);
      landing_ai(ship);
      fire_antimissile_turrets(ship);
      return true;
    }
    case PLAYER_GOAL_ARRIVING_MERCHANT_AI: {
      arriving_merchant_ai(ship);
      return true;
    }
    case PLAYER_GOAL_INTERCEPT: {
      ships_iter target_p = ships.find(overrides.target_id);
      if(target_p!=ships.end()) {
        ship.new_target(target_p->first);
        move_to_attack(ship,target_p->second);
      }
      return true;
    }
    case PLAYER_GOAL_RIFT: {
      if(!rift_ai(ship))
        fire_antimissile_turrets(ship);
      return true;
    }
    }
  return false;
}

void CombatEngine::update_near_objects_using_godot_physics(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  //FIXME: UPDATE THIS TO FIND ENEMY PROJECTILES
  ship.nearby_objects.clear();
  if(not ship_locations.circle_is_nonempty(Vector2(ship.position.x,ship.position.z),search_cylinder_radius))
    // No possibility of hits
    return;
  Ref<PhysicsShapeQueryParameters> query(PhysicsShapeQueryParameters::_new());
  query->set_collision_mask(enemy_masks[ship.faction]);
  query->set_shape(search_cylinder);
  query->set_transform(ship.transform);
  Array near_objects = space->intersect_shape(query);
  int happy=0;
  for(int i=0,size=near_objects.size();i<size;i++) {
    Dictionary info = static_cast<Dictionary>(near_objects[i]);
    RID rid = static_cast<RID>(info["rid"]);
    rid2id_iter it = rid2id.find(rid.get_id());
    if(it==rid2id.end() or it->second<0)
      continue;
    ship.nearby_objects.emplace_back(rid,it->second);
    happy++;
  }
}

static bool compare_distance(const pair<real_t,pair<RID,object_id>> &a,const pair<real_t,pair<RID,object_id>> &b) {
  return a.first<b.first;
}

void CombatEngine::find_ships_in_radius(Vector3 position,real_t radius,faction_mask_t faction_mask,vector<pair<real_t,pair<RID,object_id>>> &results) {
  FAST_PROFILING_FUNCTION;
  results.clear();
  objects_found.clear();
  if(!ship_locations.overlapping_circle(Vector2(position.x,position.z),radius,objects_found)) {
    //Godot::print("No ships found in radius="+str(radius)+" of "+str(position));
    return;
  }

  for(auto &id : objects_found) {
    ships_iter ship_ptr = ships.find(id);
    if(ship_ptr!=ships.end()) {
      Ship &target = ship_ptr->second;
      if( (target.faction_mask&faction_mask) ) {
        real_t distance = (get_position(target)-position).length()-target.radius*0.707;
        if(distance<radius) {
          pair<RID,object_id> rid_id(target.rid,target.id);
          pair<real_t,pair<RID,object_id>> dist_rid_id(distance,rid_id);
          results.push_back(dist_rid_id);
        }
      }
    }
  }
  sort(results.begin(),results.end(),compare_distance);
}


void CombatEngine::update_near_objects_using_ship_locations(Ship &ship) {
  FAST_PROFILING_FUNCTION;

  if(!ship.nearby_hostiles_timer.alarmed())
    return;

  ship.nearby_hostiles_timer.reset();

  search_results.clear();
  find_ships_in_radius(get_position(ship),100,enemy_masks[ship.faction],search_results);
  ship.nearby_objects.clear();
  for(auto & r : search_results)
    ship.nearby_objects.push_back(r.second);
}

bool CombatEngine::should_update_targetting(Ship &ship,ships_iter &other) {
  if(other->second.fate!=FATED_TO_FLY)
    return true;
  else if(ship.shot_at_target_timer.alarmed()) {
    // After 15 seconds without firing, reevaluate target
    ship.shot_at_target_timer.reset();
    return true;
  } else if(ship.range_check_timer.alarmed()) {
    // Every 25 seconds reevaluate target if target is out of range
    ship.range_check_timer.reset();
    real_t target_distance = ship.position.distance_to(other->second.position);
    return target_distance > 1.5*ship.range.all;
  }
  real_t hp = ship.armor+ship.shields+ship.structure;
  return hp/4<ship.damage_since_targetting_change;
}

ships_iter CombatEngine::update_targetting(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  ships_iter target_ptr = ships.find(ship.get_target());
  bool pick_new_target = target_ptr==ships.end() ||
    should_update_targetting(ship,target_ptr);
  
  if(pick_new_target or target_ptr==ships.end()) {
    //FIXME: REPLACE THIS WITH PROPER TARGET SELECTION LOGIC
    object_id found=select_target(-1,select_three(select_mask(enemy_masks[ship.faction]),select_flying(),select_nearest(ship.position,200.0f)),ships,false);
    target_ptr = ships.find(found);
  }
  return target_ptr;
}

void CombatEngine::attacker_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;
  ships_iter target_ptr = update_targetting(ship);
  bool have_target = target_ptr!=ships.end();
  bool close_to_target = have_target and target_ptr->second.position.distance_to(ship.position)<100;
  
  if(close_to_target) {
    ship.new_target(target_ptr->first);
    move_to_attack(ship,target_ptr->second);
    aim_turrets(ship,target_ptr);
    auto_fire(ship,target_ptr);
  } else {
    if(not have_target)
      ship.clear_target();
    // FIXME: replace this with faction-level ai:
    if(ship.faction==player_faction_index) {
      landing_ai(ship);
      opportunistic_firing(ship);
    } else if(!rift_ai(ship))
      opportunistic_firing(ship);
  }
}

void CombatEngine::raider_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;

  if(ship.goal_target<0 and planets.size()>0) {
    ship.goal_target = select_target(-1,select_nearest(ship.position),planets,false);
    planets_iter p_planet = planets.find(ship.goal_target);
    if(p_planet!=planets.end())
      ship.destination = p_planet->second.position;
  }

  if(ship.ai_flags&DECIDED_TO_RIFT) {
    if(!rift_ai(ship))
      opportunistic_firing(ship);
    return;
  }
  
  ships_iter target_ptr = update_targetting(ship);
  bool low_health = ship.armor<ship.max_armor/3 and ship.shields<ship.max_shields/3;

  if(low_health) {
    if(!rift_ai(ship))
      opportunistic_firing(ship);
    ship.ai_flags=DECIDED_TO_RIFT;
    return;
  }

  bool have_target = target_ptr!=ships.end();
  bool close_to_target = have_target and target_ptr->second.position.distance_squared_to(ship.position)<100*100;

  projectiles_iter salvage_ptr;
  bool have_salvage = should_salvage(ship);
  if(have_salvage)
    salvage_ptr = projectiles.find(ship.salvage_target);
  else
    salvage_ptr = projectiles.end();
  
  bool close_to_salvage = have_salvage and salvage_ptr->second.position.distance_squared_to(ship.position)<ship.cargo_web_radiussq;

  if(close_to_salvage) {
    salvage_ai(ship);
  } else if(close_to_target) {
    if(ship.cargo_web_active)
      deactivate_cargo_web(ship);
    ship.ai_flags=DECIDED_NOTHING;
    move_to_attack(ship,target_ptr->second);
    aim_turrets(ship,target_ptr);
    auto_fire(ship,target_ptr);
    fire_antimissile_turrets(ship);
  } else {
    if(not have_target)
      ship.clear_target();
    if(ship.ai_flags==0) {
      float randf = ship.rand.randf();
      float scale = (ship.tick_at_last_shot-ship.tick)>ticks_per_minute ? .05 : .25;
      scale *= delta/3600;
      if(randf<scale)
        ship.ai_flags=DECIDED_TO_RIFT;
    }
    if(ship.cargo_web_active)
      deactivate_cargo_web(ship);
    if(ship.ai_flags&DECIDED_TO_RIFT) {
      if(!rift_ai(ship))
        opportunistic_firing(ship);
    } else if(have_salvage)
      salvage_ai(ship);
    else if(have_target) {
      move_to_attack(ship,target_ptr->second);
      opportunistic_firing(ship);
    } else {
      patrol_ai(ship);
      opportunistic_firing(ship);
    }
  }
}

void CombatEngine::salvage_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  projectiles_iter it = projectiles.find(ship.salvage_target);
  if(it==projectiles.end()) {
    ship.salvage_target=-1;
    patrol_ai(ship);
  } else {
    Vector3 ship_position=get_position(ship);
    Vector3 proj_position=get_position(it->second);
    Vector3 dp = proj_position-ship_position;
    pair<DVector3,double> course=plot_collision_course(dp,it->second.linear_velocity,ship.max_speed);
    Vector3 desired_heading=course.first.normalized();
    
    //move_to_intercept(ship,ship.cargo_web_radius/4,.01,proj_position,it->second.linear_velocity,false);
    request_heading(ship,desired_heading);
    real_t dot = dot2(ship.heading,desired_heading);
    request_thrust(ship,dot>0.95,dot<-0.95);
    
    if(dp.length_squared()<ship.cargo_web_radius*ship.cargo_web_radius)
      activate_cargo_web(ship);
    else if(ship.cargo_web_active)
      deactivate_cargo_web(ship);
    use_cargo_web(ship);
  }

  // Opportunistic firing
  opportunistic_firing(ship);
}

bool CombatEngine::should_salvage(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  projectiles_iter it = projectiles.find(ship.salvage_target);
  if(it!=projectiles.end())
    return true;

  if(ship.salvage_timer.active() and !ship.salvage_timer.alarmed())
    return false; 

  ship.salvage_timer.reset();

  real_t max_move = ship.max_speed*(SALVAGE_TIME_LIMIT-PI/ship.max_angular_velocity);
  if(max_move<0)
    return false;

  objects_found.clear();
  size_t count = flotsam_locations.overlapping_circle(Vector2(ship.position.x,ship.position.z),
                                                      min(50.0f,max_move),objects_found);
  if(!count) {
    return false;
  }

  DVector3 ship_position = get_position_d(ship);
  object_id best_id=-1;
  real_t best_time=numeric_limits<real_t>::infinity();
  
  for(auto &id : objects_found) {
    it = projectiles.find(id);
    if(it==projectiles.end()) {
      //Godot::print(ship.name+": projectile "+str(id)+" does not exist.");
      continue;
    }
    Projectile &proj = it->second;
    DVector3 dp = get_position(proj)-ship_position;
    pair<DVector3,double> course = plot_collision_course(dp,proj.linear_velocity,ship.max_speed);
    real_t life_remaining = proj.lifetime-proj.age;
    if(course.second>life_remaining) {
      //Godot::print(ship.name+": projectile "+str(proj.id)+" is too far: course_time="+str(course.second)+" life_remaining="+str(life_remaining));
      continue;
    }
    if(course.second<best_time) {
      best_time=course.second;
      best_id=id;
    }
  }
  if(isfinite(best_time)) {
    ship.salvage_target=best_id;
    return true;
  }
  return false;
}

void CombatEngine::choose_target_by_goal(Ship &ship,bool prefer_strong_targets,goal_action_t goal_filter,real_t min_weight_to_target,real_t override_distance) const {
  FAST_PROFILING_FUNCTION;

  // Minimum and maximum distances to target for calculations:
  real_t min_move = clamp(max(3.0f*ship.max_speed,ship.range.all),10.0f,30.0f);
  real_t max_move = clamp(20.0f*ship.max_speed+ship.range.all,100.0f,1000.0f);
  real_t move_scale = max(max_move-min_move,1.0f);

  factions_const_iter faction_it = factions.find(ship.faction);
  
  int i=0;
  object_id target = -1;
  real_t target_weight = -1.0f;

  for(ships_const_iter it=ships.begin();it!=ships.end();it++,i++) {
    real_t weight = 0.0f;
    const Ship &other = it->second;
    if(other.id==ship.id or not is_hostile_towards(ship.faction,other.faction))
      // Cannot harm the other ship, so don't target it.
      continue;

    real_t ship_dist = other.position.distance_to(ship.position);
    if(ship_dist>max_move and ship_dist>override_distance)
      // Ship is essentially infinitely far away, so ignore it.
      continue;

    weight  = clamp(-affinity_towards(ship.faction,other.faction),0.5f,2.0f);
    weight *= clamp((max_move-ship_dist)/move_scale, 0.1f, 1.0f);

    // Lower weight for potential targets much stronger than the ship.
    real_t rel_threat = max(100.0f,ship.threat)/other.threat;
    if(prefer_strong_targets)
      rel_threat = 1.0f/rel_threat;
    rel_threat = clamp(rel_threat,0.3f,1.0f);
    weight *= rel_threat;

    weight *= 10.0f;

    // Goal weight is now 1..10 for range times 0.15..2 for other factors

    if(ship.get_target() == other.id)
      weight += 5; // prefer the current target

    if(faction_it!=factions.end()) {
      real_t all_advice_weight_sq = 0;
      for(auto &advice : faction_it->second.get_target_advice()) {
        if(advice.action != goal_filter)
          continue; // ship does not contribute to this goal

        // Starting advice weight is goal weight multiplied by a number from 0..1:
        real_t advice_weight = advice.target_weight;

        // Reduce the weight based on distance to the goal, if the
        // goal cares about distance.
        if(advice.radius>0) {
          real_t dist = advice.position.distance_to(ship.position);
          if(advice.radius>dist)
            continue; // target is outside goal radius
          advice_weight *= (advice.radius-dist)/advice.radius;
        }

        if(advice_weight>0)
          all_advice_weight_sq += advice_weight*advice_weight;
      }

      // Use the square root of sum of squares to accumulate so the
      // relative values don't get too high if there are many goals.
      if(all_advice_weight_sq>0)
        weight += 5*sqrtf(all_advice_weight_sq);
    }

    if(weight<min_weight_to_target and ship_dist>override_distance)
      continue; // Ship is too unimportant to attack
    
    if(weight>target_weight) {
      target_weight = weight;
      target = other.id;
    }
  }

  if(target!=ship.get_target()) {
    ship.new_target(target);
    // if(target>=0) {
    //   ships_const_iter it=ships.find(target);
    // }
  }

  if(target<0 and ship.goal_target>0) {
    // No ship to target, and this ship is tracking a planet-based
    // goal, so we'll target that instead.

    target = -1;
    target_weight = -1.0f;

    object_id closest_planet = select_target(-1,select_nearest(ship.position),planets,false);

    const vector<TargetAdvice> &target_advice = faction_it->second.get_target_advice();
    unordered_map<object_id,float> weighted_planets;

    weighted_planets.reserve(target_advice.size()*2);

    real_t weight_sum=0;
    for(auto &advice : target_advice) {
      if(advice.action != goal_filter)
        continue; // ship does not contribute to this goal

      real_t weight = advice.target_weight;
      
      if(advice.planet == ship.goal_target)
        weight *= 1.5;
      if(advice.planet == closest_planet)
        weight *= 1.5;

      unordered_map<object_id,float>::iterator it=weighted_planets.find(advice.planet);
      if(it==weighted_planets.end())
        weighted_planets[advice.planet] = weight;
      else
        it->second += weight;
      weight_sum += weight;
    }

    real_t randf = ship.rand.randf()*weight_sum;
    unordered_map<object_id,float>::iterator choice = weighted_planets.begin();
    unordered_map<object_id,float>::iterator next = choice;

    while(next!=weighted_planets.end()) {
      if(randf<choice->second)
        break;
      randf -= choice->second;
      choice=next;
      next++;
    };

    if(choice!=weighted_planets.end())
      target = choice->first;

    if(target>=0) {
      // if(target != ship.goal_target) {
      //   planets_const_iter it=planets.find(target);
      // }
      ship.goal_target = target;
    }
  }
}

void CombatEngine::patrol_ship_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;

  if(ship.goal_target<0 and planets.size()>0) {
    // Initial goal target is the nearest planet.
    ship.goal_target = select_target(-1,select_nearest(ship.position),planets,false);
    planets_iter p_planet = planets.find(ship.goal_target);
    if(p_planet!=planets.end()) {
      ship.destination = p_planet->second.position;
      ship.goal_target = p_planet->second.id;
      //Godot::print("Ship "+str(ship.id)+" chose goal target "+p_planet->second.name);
    } // else
      // Godot::print("Ship "+str(ship.id)+" could not choose a goal target (invalid planet "+str(ship.goal_target)+")");
  }

  if(ship.ai_flags&DECIDED_TO_LAND) {
    landing_ai(ship);
    opportunistic_firing(ship);
    return;
  } else if(ship.ai_flags&DECIDED_TO_RIFT) {
    if(!rift_ai(ship))
      opportunistic_firing(ship);
    return;
  }

  bool low_health = ship.armor<ship.max_armor/5 and ship.shields<ship.max_shields/3 and ship.structure<ship.max_structure/2;

  if(low_health) {
    if(!rift_ai(ship))
      opportunistic_firing(ship);
    ship.ai_flags=DECIDED_TO_RIFT;
    return;
  }

  ships_iter target_ptr;
  bool find_new_target = false;
  if(ship.get_target()<0 and ship.no_target_timer.alarmed()) {
    ship.no_target_timer.reset();
    find_new_target = true;
  } else {
    target_ptr = ships.find(ship.get_target());
    if(target_ptr == ships.end())
      find_new_target = true;
    else
      find_new_target = should_update_targetting(ship,target_ptr);
  }
  if(find_new_target) {
    choose_target_by_goal(ship,false,goal_patrol,0.0f,30.0f);
    target_ptr = ships.find(ship.get_target());
  }

  bool have_target = target_ptr!=ships.end();
  bool close_to_target = have_target and target_ptr->second.position.distance_to(ship.position)<13*ship.max_speed;
  
  if(close_to_target) {
    ship.ai_flags=0;
    move_to_attack(ship,target_ptr->second);
    aim_turrets(ship,target_ptr);
    auto_fire(ship,target_ptr);
    fire_antimissile_turrets(ship);
  } else {
    if(not have_target)
      ship.clear_target();
    if(ship.ai_flags==0) {
      float randf = ship.rand.randf();
      float scale = (ship.tick_at_last_shot-ship.tick)>ticks_per_minute ? .05 : .15;
      scale *= delta/30;
      if(randf<scale)
        ship.ai_flags=DECIDED_TO_RIFT;
      else if(randf<2*scale)
        ship.ai_flags=DECIDED_TO_LAND;
    }
    if(ship.ai_flags&DECIDED_TO_LAND) {
      landing_ai(ship);
      opportunistic_firing(ship);
    } else if(ship.ai_flags&DECIDED_TO_RIFT) {
      if(!rift_ai(ship))
        opportunistic_firing(ship);
    } else if(have_target) {
      move_to_attack(ship,target_ptr->second);
      opportunistic_firing(ship);
    } else
      patrol_ai(ship);
  }
}

void CombatEngine::landing_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;

  if(ship.fate!=FATED_TO_FLY)
    return;

  planets_iter target = planets.find(ship.get_target());
  if(target == planets.end()) {
    object_id target_id = select_target(-1,select_nearest(ship.position),planets,false);
    target = planets.find(target_id);
    ship.new_target(target_id);
  }
  if(target == planets.end())
    // Nowhere to land!
    patrol_ai(ship);
  else if(move_to_intercept(ship, target->second.radius, 5.0, target->second.position,
                            Vector3(0,0,0), true)) {
    // Reached planet.
    // FIXME: implement factions, etc.:
    // if(target->second.can_land(ship))
    ship.fate = FATED_TO_LAND;
  }
}

planets_iter CombatEngine::choose_arriving_merchant_goal_target(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  // Get our target planet if there isn't one already.
  planets_iter target_ptr = planets.find(ship.goal_target);
  if(target_ptr==planets.end()) {
    target_ptr = planets.find(ship.get_target());
    if(target_ptr==planets.end()) {
      ship.new_target(select_target<>(ship.get_target(),select_nearest(ship.position),planets,false));
      ship.goal_target = ship.get_target();
      //Godot::print(ship.name+": arriving merchant is using the nearest planet "+str(ship.goal_target));
    } else {
      //Godot::print(ship.name+": arriving merchant is using its target as its goal target");
      ship.goal_target = ship.get_target();
    }
    target_ptr = planets.find(ship.goal_target);
    //Godot::print(ship.name+": arriving merchant chose "+target_ptr->second.name+" as its goal target");
  } else if(ship.get_target()!=ship.goal_target)
    ship.new_target(ship.goal_target);
  return target_ptr;
}

planets_iter CombatEngine::choose_arriving_merchant_action(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  ship.ticks_since_ai_change=0;
  planets_iter target_ptr = choose_arriving_merchant_goal_target(ship);
  if(target_ptr==planets.end()) {
    // Nowhere to go and nothing to do. Time to leave.
    ship.ai_flags = DECIDED_TO_RIFT;
    return target_ptr;
  }

  // If we're close to the destination, land regardless of hostiles.
  // If we're far away, rift. Otherwise, land or evade based on threat vector.
  
  ship.ai_flags = DECIDED_NOTHING;
  Vector3 destination = target_ptr->second.position;
  real_t dist2 = distance2(destination,ship.position)-target_ptr->second.radius;
  real_t too_far = 30*ship.max_speed, too_close = 2*ship.max_speed;

  // If we're far from the destination, rift away.
  if(dist2>too_far) {
    ship.ai_flags = DECIDED_TO_RIFT;
    return target_ptr;
  }

  // If we're close to the destination, land regardless of risks.
  if(dist2<too_close) {
    ship.ai_flags = DECIDED_TO_LAND;
    return target_ptr;
  }
  
  // If we're dying, leave.
  if(ship.armor<ship.max_armor/3 and ship.shields<ship.max_shields/3) {
    ship.ai_flags = DECIDED_TO_RIFT;
    return target_ptr;
  }
  
  // Evade or move to land, based on threat vector.
  update_near_objects_using_ship_locations(ship);
  make_threat_vector(ship,0.5);
  real_t threat_threshold = ship.threat/10;
  bool should_evade = (ship.threat_vector.length_squared() > threat_threshold*threat_threshold);
  ship.ai_flags = should_evade ? DECIDED_TO_FLEE : DECIDED_TO_LAND;
  return target_ptr;
}

void CombatEngine::arriving_merchant_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return;

  planets_iter target_ptr = planets.end();
 
  // If it is time to decide on our next action, ponder it.
  if(ship.ai_flags-=DECIDED_NOTHING or ship.ticks_since_ai_change>=ticks_per_second/4)
    choose_arriving_merchant_action(ship);

  if(ship.ai_flags==DECIDED_TO_RIFT) {
    if(!rift_ai(ship))
      opportunistic_firing(ship);
    return;
  }
  
  if(ship.ai_flags==DECIDED_TO_FLEE) {
    evade(ship);
    opportunistic_firing(ship);
    return;
  }

  if(target_ptr==planets.end())
    target_ptr = CombatEngine::choose_arriving_merchant_goal_target(ship);
  if(target_ptr!=planets.end()) {
    Planet &target = target_ptr->second;
    if(move_to_intercept(ship, target.radius, 5.0, target.position, Vector3(0,0,0), true))
      // Reached planet.
      ship.fate = FATED_TO_LAND;
    opportunistic_firing(ship);
    return;
  }

  Godot::print_warning(ship.name+": arriving merchant has nothing to do",__FUNCTION__,__FILE__,__LINE__);
  // Nowhere to go and nothing to do, so we may as well leave.
  if(!rift_ai(ship))
    opportunistic_firing(ship);
}

void CombatEngine::departing_merchant_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return;

  // If it is time to decide on our next action, ponder it.

  if(ship.ai_flags-=DECIDED_NOTHING or ship.ticks_since_ai_change>=ticks_per_second/4) {
    ship.ticks_since_ai_change=0;
    if(ship.armor<ship.max_armor/3 and ship.shields<ship.max_shields/3)
      ship.ai_flags = DECIDED_TO_RIFT;
    else {
      planets_iter target_ptr = planets.find(ship.goal_target);
      if(target_ptr==planets.end()) {
        ship.goal_target = select_target<>(-1,select_nearest(ship.position),planets,false);
        target_ptr = planets.find(ship.goal_target);
      }
      if(target_ptr!=planets.end() and distsq(target_ptr->second.position,ship.position)>200*200)
        ship.ai_flags = DECIDED_TO_RIFT;
      else {
        update_near_objects_using_ship_locations(ship);
        make_threat_vector(ship,0.5);
        real_t threat_threshold = ship.threat/10;
        bool should_evade = (ship.threat_vector.length_squared() > threat_threshold*threat_threshold);
        ship.ai_flags = should_evade ? DECIDED_TO_FLEE : DECIDED_TO_RIFT;
      }
    }
  }

  if(ship.ai_flags==DECIDED_TO_FLEE) {
    evade(ship);
    opportunistic_firing(ship);
    return;
  } else {
    if(!rift_ai(ship))
      opportunistic_firing(ship);
    return;
  }
}


void CombatEngine::opportunistic_firing(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  // Take shots when you can, without turning the ship to aim.
  ships_iter nowhere = ships.end();
  aim_turrets(ship,nowhere);
  auto_fire(ship,nowhere);
  fire_antimissile_turrets(ship);
}

bool CombatEngine::patrol_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return false;
  if(ship.position.distance_to(ship.destination)<10) {
    ship.randomize_destination();
    if(ship.goal_target>=0) {
      planets_iter p_planet = planets.find(ship.goal_target);
      if(p_planet!=planets.end())
        ship.destination += p_planet->second.position;
    }
  }
  move_to_intercept(ship, 5, 1, ship.destination, Vector3(0,0,0), false);
  return true;
}

Vector3 CombatEngine::make_threat_vector(Ship &ship, real_t t) {
  FAST_PROFILING_FUNCTION;
  //FIXME: UPDATE THIS TO INCLUDE PROJECTILES
  Vector3 my_position = ship.position + t*ship.linear_velocity;
  Vector2 threat_vector;
  real_t dw_div = 0;
  int checked=0;
  for(auto &rid_id : ship.nearby_objects) {
    ships_iter object_iter = ships.find(rid_id.second);
    if(object_iter==ships.end()) {
      continue;
    }
    Ship &object = object_iter->second;
    Vector3 obj_pos = object.position + t*object.linear_velocity;
    Vector2 position(obj_pos[0] - my_position[0], obj_pos[2] - my_position[2]);
    real_t distance = position.length();
    real_t distance_weight = max(0.0f,(search_cylinder_radius-distance)/search_cylinder_radius);
    real_t weight = distance_weight*object.threat;
    dw_div += distance_weight;
    threat_vector += weight * position.normalized();
    checked++;
  }
  Vector3 result = Vector3(threat_vector[0],0,threat_vector[1])/max(1.0f,dw_div);
  ship.threat_vector=result;
  return result;
}

void CombatEngine::evade(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  Vector3 reaction_vector=-ship.threat_vector.normalized();
  real_t dot = dot2(reaction_vector,ship.heading);
  
  request_thrust(ship,real_t(dot>=0),real_t(dot<0));
  request_heading(ship,reaction_vector);
}

bool CombatEngine::pull_back_to_standoff_range(Ship &ship,Ship &target,Vector3 &aim) {
  FAST_PROFILING_FUNCTION;

  if(not ship.reverse_thrust)
    // Cannot pull back without reverse thrusters.
    return false;

  real_t standoff_range=ship.get_standoff_range(target,idelta);

  if(not isfinite(standoff_range))
    // Cannot pull back to standoff range for an unarmed ship.
    return false;

  if(dot2(ship.heading,aim)>0) {
    real_t distance = (target.position-ship.position).length();
    if(distance<standoff_range*0.7)
      request_thrust(ship,0,1);
    else if(distance>standoff_range*.9)
      request_thrust(ship,1,0);
  }
    
  return false;
}

real_t CombatEngine::time_of_closest_approach(Vector3 dp,Vector3 dv) {
  real_t dv2 = dot2(dv,dv);
  if(dv2<1e-9)
    return 0;
  return max(dot2(dp,dv)/dv2,0.0f);
}

void CombatEngine::fire_antimissile_turrets(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(not ship.range.antimissile)
    return; // Ship has no anti-missile systems.

  faction_mask_t enemy_mask = enemy_masks[ship.faction];
  if(!enemy_mask)
    return; // Ship has no enemy factions, so no possible projectile matches.
  
  real_t antimissile_range=0;  
  for(auto &weapon : ship.weapons)
    if(weapon.antimissile and weapon.damage>0 and weapon.can_fire())
      antimissile_range = max(antimissile_range,weapon.projectile_range);

  if(antimissile_range<=0)
    return; // No anti-missile weapons are ready to fire.
  
  real_t range = ship.radius + antimissile_range;
  Vector2 center = Vector2(ship.position.x,ship.position.z);
  objects_found.clear();
  if(not missile_locations.overlapping_circle(center,range,objects_found))
    return; // No projectiles in range

  // Delete any projectiles that are not viable targets.
  for(auto iter=objects_found.begin();iter!=objects_found.end();) {
    object_id id = *iter;
    projectiles_iter proj_it = projectiles.find(id);
    if(proj_it==projectiles.end()) {
      iter = objects_found.erase(iter);
      Godot::print_warning("Found projectile "+str(id)+" in missile_locations that is not in projectiles hash",
                           __FUNCTION__,__FILE__,__LINE__);
      continue; // Projectile does not exist.
    }
    Projectile &proj = proj_it->second;
    if(proj.direct_fire or not proj.max_structure or not proj.alive) {
      iter = objects_found.erase(iter);
      continue; // Projectile is not a valid target.
    }
    if( not ( (1<<proj.faction) & enemy_mask )) {
      iter = objects_found.erase(iter);
      continue; // Projectile is not an enemy.
    }
    if(proj.structure<=0) {
      iter = objects_found.erase(iter);
      continue; // Projectile is already dead.
    }
    iter++;
  }

  //Godot::print(ship.name+": retained "+str(objects_found.size())+" potential targets for anti-missile systems.");
  
  // Have each weapon try to fire at a projectile.
  for(auto &weapon : ship.weapons) {
    size_t within_range = 0;
    if(weapon.antimissile and weapon.damage>0 and weapon.can_fire()) {
      Vector3 start = ship.position + weapon.position.rotated(y_axis,ship.rotation.y);
      projectiles_iter best = projectiles.end();
      real_t best_score = -numeric_limits<real_t>::infinity();
      for(auto &id : objects_found) {
        projectiles_iter proj_it = projectiles.find(id);
        Projectile &proj = proj_it->second;
        real_t distance = distance2(proj.position,start);
        if(distance<=weapon.projectile_range) {
          within_range++;
          real_t hits_to_kill = ceilf(proj.structure/weapon.damage);
          real_t arrival_time = distance/proj.max_speed;// FIXME: This is not an ideal solution.
          real_t hits_available = ceilf(arrival_time/weapon.reload_delay);
          real_t score = proj.damage;
          if(hits_available>hits_to_kill)
            score/=2;
          if(proj.target!=ship.id)
            score/=2;
          if(score>best_score) {
            best = proj_it;
            best_score = score;
          }
        } // end if distance<=weapon.projectile_range
      } // End objects loop
      
      if(best!=projectiles.end()) {
        // if(ship.id == player_ship_id)
        //   Godot::print(ship.name+": firing at projectile "+str(best->first)+" with "+str(weapon.node_path)+" damage "+str(weapon.damage)+" to structure "+str(best->second.structure));
        Vector3 dp = best->second.position-start;
        real_t dp_angle = angle_from_unit(dp);
        real_t rotation = dp_angle-ship.rotation.y;

        weapon_rotations[weapon.node_path] = weapon.rotation.y = fmodf(rotation,2*PI);

        Vector3 hit_position = best->second.position;
        Vector3 point1 = start;
        Vector3 projectile_position = (point1+hit_position)*0.5;
        real_t projectile_length = (hit_position-point1).length();
        real_t projectile_rotation = weapon.rotation.y+ship.rotation.y;
        
        create_antimissile_projectile(ship,weapon,best->second,projectile_position,projectile_length,projectile_rotation);
        best->second.take_damage(weapon.damage);
        if(not best->second.alive) {
          // if(ship.id == player_ship_id)
          //   Godot::print(ship.name+": projectile has died.");
          objects_found.erase(best->first);
        }
        // else if(ship.id == player_ship_id)
        //   Godot::print(ship.name+": projectile survived.");
      }
      // else
      //   Godot::print(ship.name+": anti-missile system "+str(weapon.node_path)+" has no targets. Available targets: "+str(remaining)+" within range: "+str(within_range));
    }
  } // end weapons loop
}

void CombatEngine::aim_turrets(Ship &ship,ships_iter &target) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;
  Vector3 ship_pos = ship.position;
  real_t ship_rotation = ship.rotation[1];
  Vector3 confusion = ship.confusion;
  real_t max_distsq = ship.range.turrets*1.5*ship.range.turrets*1.5;
  bool got_enemies = false, have_a_target=false;

  int num_eptrs=0;
  Ship *eptrs[12];
  
  for(auto &weapon : ship.weapons) {
    if(not weapon.is_turret)
      continue; // Not a turret.
    
    real_t travel = weapon.projectile_range;
    if(travel<1e-5)
      continue; // Avoid divide by zero for turrets with no range.

    if(weapon.antimissile) // handled by another function
      continue;

    if(!got_enemies) {
      const ship_hit_list_t &enemies = get_ships_within_turret_range(ship, 1.5);
      have_a_target = target!=ships.end();
      
      if(have_a_target) {
        real_t dp=target->second.position.distance_to(ship.position);
        have_a_target = dp*dp<max_distsq and have_a_target;
        eptrs[num_eptrs++] = &target->second;
      }
      for(auto it=enemies.begin();it<enemies.end() && num_eptrs<11;it++) {
        ships_iter enemy_iter = ships.find(it->second);
        if(enemy_iter==ships.end())
          continue;
        if(distsq(enemy_iter->second.position,ship.position)>max_distsq)
          break;
        eptrs[num_eptrs++] = &enemy_iter->second;
      }
      got_enemies = true;
    }
    
    // FIXME: implement weapon.get_opportunistic
    //bool opportunistic = false;
    
    Vector3 proj_start = ship_pos + weapon.position.rotated(y_axis,ship_rotation) + confusion;
    real_t turret_angular_velocity=0;
    real_t best_score = numeric_limits<real_t>::infinity();
    //int best_enemy = -1;
    real_t lifetime = weapon.projectile_lifetime;
    bool is_target = have_a_target;
    double turn_rate = weapon.turn_rate;
    real_t proj_rotation = ship_rotation + weapon.rotation.y;
    
    for(int i=0;i<num_eptrs;i++,is_target=false) {
      Ship &enemy = *eptrs[i];
      if(distsq(enemy.position,ship.position)>max_distsq)
        break;
      DVector3 dp = enemy.position - proj_start;
      pair<DVector3,double> course = plot_collision_course(dp,enemy.linear_velocity,weapon.terminal_velocity);
      double intercept_time = course.second;
      if(isnan(intercept_time))
        intercept_time = lifetime*2;
      DVector3 course_velocity = course.first-ship.linear_velocity;
      
      double course_angle = angle_from_unit(course_velocity.normalized());
      double angle_correction = course_angle-proj_rotation;
      double turn_time = fabsf(angle_correction/turn_rate);
      
      if(is_target) { // && PI/weapon.turn_rate+intercept_time>=.75*lifetime) {
        // We don't have time to hit a non-target, so focus on the target.
        turret_angular_velocity = clamp(angle_correction/delta,-turn_rate,turn_rate);
        best_score = 0;
        break;
      }
      
      double score = turn_time+intercept_time;

      if(score<best_score) {
        best_score=score;
        turret_angular_velocity = clamp(angle_correction/delta,-turn_rate,turn_rate);
      }
    }

    if(!isfinite(best_score)) {
      // This turret has nothing to target.
      // if(opportunistic) {
      //   //FIXME: INSERT CODE HERE
      // } else {
      // Aim turret forward
      // Vector3 to_center = ship.heading.rotated();
      real_t to_center = weapon.harmony_angle-weapon.rotation.y;
      if(to_center>PI)
        to_center-=2*PI;
      turret_angular_velocity = clamp(to_center/delta, -weapon.turn_rate, weapon.turn_rate);
      // }
    }

    weapon.rotation.y = fmodf(weapon.rotation.y+delta*turret_angular_velocity,2*PI);
    weapon_rotations[weapon.node_path] = weapon.rotation.y;
  }
}

Vector3 CombatEngine::aim_forward(Ship &ship,Ship &target,bool &in_range) {
  FAST_PROFILING_FUNCTION;
  Vector3 aim = Vector3(0,0,0);
  Vector3 my_pos=ship.position;
  Vector3 tgt_pos=target.position+ship.confusion;
  Vector3 dp_ships = tgt_pos - my_pos;
  Vector3 dv = target.linear_velocity - ship.linear_velocity;
  dp_ships += dv*delta;
  in_range=false;
  for(auto &weapon : ship.weapons) {
    if(weapon.is_turret or weapon.guided)
      continue;
    //Vector3 weapon_velocity = ship.linear_velocity + weapon.terminal_velocity*ship.heading;
    Vector3 dp = dp_ships - weapon.position.rotated(y_axis,ship.rotation.y);
    real_t t = rendezvous_time(dp,dv,weapon.terminal_velocity);
    if(isnan(t)) 
      continue;
    //return (tgt_pos - my_pos).normalized();
    in_range = in_range or t<weapon.projectile_lifetime;
    t = min(t,weapon.projectile_lifetime);
    aim += (dp+t*dv)*max(1.0f,weapon.threat);
  }
  return aim.length_squared() ? aim.normalized() : (tgt_pos-my_pos).normalized();
}

bool CombatEngine::request_stop(Ship &ship,Vector3 desired_heading,real_t max_speed) {
  FAST_PROFILING_FUNCTION;
  bool have_heading = desired_heading.length_squared()>1e-10;
  real_t speed = ship.linear_velocity.length();
  const real_t speed_epsilon = 0.01;
  real_t slow = max(max_speed,speed_epsilon);
  Vector3 velocity_norm = ship.linear_velocity.normalized();
  
  if(speed<slow) {
    set_velocity(ship,Vector3(0,0,0));
    if(have_heading)
      request_heading(ship,desired_heading);
    else
      set_angular_velocity(ship,Vector3(0,0,0));
    return true;
  }

  double stop_time = speed/(ship.inverse_mass*ship.thrust);
  //double limit = 0.8 + 0.2/(1.0+stop_time*stop_time*stop_time*speed_epsilon);
  double turn = acos_clamp_dot(-velocity_norm,ship.heading);
  double forward_turn_time = turn/ship.max_angular_velocity;

  if(ship.reverse_thrust>1e-5) {
    double forward_time = forward_turn_time + stop_time;
    double reverse_stop_time = speed/(ship.inverse_mass*ship.reverse_thrust);
    double reverse_turn_time = (PI/2-turn)/ship.max_angular_velocity;
    double reverse_time = reverse_turn_time + reverse_stop_time;
    if(have_heading) {
      double turn_from_backward = acos_clamp_dot(desired_heading,-velocity_norm);
      forward_time += turn_from_backward/ship.max_angular_velocity;
      
      double turn_from_forwards = acos_clamp_dot(desired_heading,velocity_norm);
      reverse_time += turn_from_forwards/ship.max_angular_velocity;
    }
    if(reverse_time<forward_time) {
      if(fabsf(request_heading(ship,velocity_norm))>0.9)
        request_thrust(ship,0,speed/(delta*ship.inverse_mass*ship.reverse_thrust));
      return false;
    }
  }
  if(fabsf(request_heading(ship,-velocity_norm))>0.9)
    request_thrust(ship,speed/(delta*ship.inverse_mass*ship.thrust),0);
  return false;
}

void CombatEngine::encode_salvaged_items_for_gdscript(Array result) {
  FAST_PROFILING_FUNCTION;
  result.clear();
  result.resize(salvaged_items.size());
  int next_index=0;
  for(auto &ship_id_salvage : salvaged_items) {
    if(not ship_id_salvage.second)
      continue;
    const Salvage &salvage = *ship_id_salvage.second;

    ships_iter ship_ptr = ships.find(ship_id_salvage.first);
    if(ship_ptr==ships.end())
      continue;
    const Ship &ship = ship_ptr->second;

    result[next_index++] = Dictionary::make("ship_name",ship.name,"product_name",salvage.cargo_name,
                                            "count",salvage.cargo_count,
                                            "unit_mass",salvage.cargo_unit_mass);
  }
  result.resize(next_index+1);
}

double CombatEngine::rendezvous_time(Vector3 target_location,Vector3 target_velocity,
                                     double interception_speed) {
  FAST_PROFILING_FUNCTION;
  double a = dot2(target_velocity,target_velocity) - interception_speed*interception_speed;
  double b = 2.0 * dot2(target_location,target_velocity);
  double c = dot2(target_location,target_location);
  double descriminant = b*b - 4*a*c;

  if(fabs(a)<1e-5)
    return -c/b;

  if(descriminant<0)
    return NAN;

  descriminant = sqrt(descriminant);
        
  double d1 = (-b + descriminant)/(2.0*a);
  double d2 = (-b - descriminant)/(2.0*a);
  double mn = min(d1,d2);
  double mx = max(d1,d2);

  if(mn>=0)
    return mn;
  else if(mx>=0)
    return mx;
  return NAN;
}

void CombatEngine::fire_primary_weapons(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;
  // FIXME: UPDATE ONCE SECONDARY WEAPONS EXIST
  for(auto &weapon : ship.weapons) {
    if(not weapon.can_fire())
      continue;
    if(weapon.antimissile)
      continue;
    if(weapon.direct_fire)
      fire_direct_weapon(ship,weapon,true);
    else
      create_projectile(ship,weapon);
  }
}

void CombatEngine::player_auto_target(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile or ship.inactive)
    return;
  ships_iter target = ships.find(ship.get_target());
  if(target!=ships.end()) {
    bool in_range=false;
    Vector3 aim = aim_forward(ship,target->second,in_range);
    request_heading(ship,aim);
  }
  fire_primary_weapons(ship);
}

Dictionary CombatEngine::check_target_lock(Ship &target, Vector3 point1, Vector3 point2) {
  FAST_PROFILING_FUNCTION;
  if(not ship_locations.ray_is_nonempty(Vector2(point1.x,point1.z),Vector2(point2.x,point2.z)))
    return Dictionary(); // no possibility of collisions
  int mask = physics_server->body_get_collision_mask(target.rid);
  physics_server->body_set_collision_mask(target.rid, mask | (1<<30));
  Dictionary result = space->intersect_ray(point1, point2, Array());
  physics_server->body_set_collision_mask(target.rid,mask);
  return result;
}

struct ship_cmp_by_range {
  const Vector3 &center;
  const std::unordered_map<object_id,Ship> &ships;
  ship_cmp_by_range(const Vector3 &center,const std::unordered_map<object_id,Ship> &ships):
    center(center),ships(ships)
  {}
  template<class T>
  bool operator () (const T &a, const T &b) const {
    std::unordered_map<object_id,Ship>::const_iterator aship = ships.find(a.second);
    std::unordered_map<object_id,Ship>::const_iterator bship = ships.find(b.second);
    return distsq(aship->second.position,center) < distsq(bship->second.position,center);
  }
};

const ship_hit_list_t &CombatEngine::get_ships_within_range(Ship &ship, real_t desired_range) {
  FAST_PROFILING_FUNCTION;
  real_t nearby_enemies_range=ship.nearby_enemies_range;
  int nearby_enemies_tick = ship.nearby_enemies_tick;
  int tick=ship.tick;
  if(nearby_enemies_range<desired_range || nearby_enemies_tick + ticks_per_second/6 < tick) {
    ship.nearby_enemies_tick = ship.tick;
    ship.nearby_enemies_range = desired_range;
    ship.nearby_enemies.clear();
    for(auto &other : ships) {
      if(!(other.second.faction_mask&enemy_masks[ship.faction]))
        continue; // not an enemy
      if(other.second.id==ship.id)
        continue; // do not target self
      if(ship.position.distance_to(other.second.position)>desired_range)
        continue; // out of range
      ship.nearby_enemies.emplace_back(other.second.rid,other.second.id);
    }
    sort(ship.nearby_enemies.begin(),ship.nearby_enemies.end(),ship_cmp_by_range(ship.position,ships));
  }
  return ship.nearby_enemies;
}
    
const ship_hit_list_t &
CombatEngine::get_ships_within_unguided_weapon_range(Ship &ship,real_t fudge_factor) {
  FAST_PROFILING_FUNCTION;
  return get_ships_within_range(ship,ship.range.unguided*fudge_factor);
}
    
const ship_hit_list_t &
CombatEngine::get_ships_within_weapon_range(Ship &ship,real_t fudge_factor) {
  FAST_PROFILING_FUNCTION;
  return get_ships_within_range(ship,ship.range.all*fudge_factor);
}
    
const ship_hit_list_t &
CombatEngine::get_ships_within_turret_range(Ship &ship, real_t fudge_factor) {
  FAST_PROFILING_FUNCTION;
  return get_ships_within_range(ship,ship.range.turrets*fudge_factor);
}

bool CombatEngine::fire_direct_weapon(Ship &ship,Weapon &weapon,bool allow_untargeted) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return false;
  Vector3 p_weapon = weapon.position.rotated(y_axis,ship.rotation.y);
  real_t weapon_range = weapon.projectile_range;
  real_t weapon_rotation;
  if(weapon.is_turret)
    weapon_rotation = weapon.rotation.y;
  else
    weapon_rotation = weapon.harmony_angle;

  weapon_rotation += ship.rotation.y;

  Vector3 projectile_heading = unit_from_angle(weapon_rotation);
  Vector3 point1 = p_weapon+ship.position;
  Vector3 point2 = point1 + projectile_heading*weapon_range;
  point1.y=5;
  point2.y=5;
  Dictionary result = space_intersect_ray(space,point1,point2,enemy_masks[ship.faction]);

  Vector3 hit_position=Vector3(0,0,0);
  object_id hit_target=-1;
  
  if(not result.empty()) {
    hit_position = CE::get<Vector3>(result,"position");
    ships_iter hit_ptr = ships.find(rid2id_default(rid2id,CE::get<RID>(result,"rid")));
    if(hit_ptr!=ships.end()) {
      hit_target=hit_ptr->first;
      
      // Direct fire projectiles do damage when launched.
      if(weapon.damage)
        hit_ptr->second.take_damage(weapon.damage*delta*ship.efficiency,weapon.damage_type,
                                    weapon.heat_fraction,weapon.energy_fraction,weapon.thrust_fraction);
      if(not hit_ptr->second.immobile and weapon.impulse) {
        Vector3 impulse = weapon.impulse*projectile_heading*delta*ship.efficiency;
        physics_server->body_apply_central_impulse(hit_ptr->second.rid,impulse);
      }
      if(not hit_position.length_squared())
        hit_position = hit_ptr->second.position;
    }
  }

  if(hit_target<0) {
    if(not allow_untargeted)
      return false;
    hit_position=point2;
  }

  ship.heat += weapon.firing_heat*ship.efficiency*delta;
  ship.energy -= weapon.firing_energy*ship.efficiency*delta;
  
  hit_position[1]=0;
  point1[1]=0;
  Vector3 projectile_position = (point1+hit_position)*0.5;
  real_t projectile_length = (hit_position-point1).length();
  create_direct_projectile(ship,weapon,projectile_position,projectile_length,
                           Vector3(0,weapon_rotation,0),hit_target);
  return true;
}

void CombatEngine::auto_fire(Ship &ship,ships_iter &target) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;
  const ship_hit_list_t &enemies = get_ships_within_weapon_range(ship,1.5);
  Vector3 p_ship = ship.position;
  real_t max_distsq = ship.range.all;

  Ship *eptrs[12];
  int num_eptrs=0;
  bool have_a_target = target!=ships.end();
  bool have_enemies=false;
  bool hit_detected=false;
  bool ships_in_range=false;
  
  for(auto &weapon : ship.weapons) {
    
    if(not weapon.can_fire())
      continue;

    real_t max_travel_squared = weapon.projectile_range;
    max_travel_squared *= max_travel_squared;

    if(weapon.guided) {
      if(have_a_target) {
        real_t travel_squared = target->second.position.distance_squared_to(ship.position);
        if(travel_squared<max_travel_squared) {
          create_projectile(ship,weapon,target->second.id);
          continue;
        }
      }
    } else if(hit_detected and not weapon.is_turret) {
      // If one non-turret non-guided weapon fires, all fire.
      if(weapon.direct_fire)
        fire_direct_weapon(ship,weapon,false);
      else
        create_projectile(ship,weapon);
      continue;
    }
    if(not have_enemies) {  
      AABB bound;
      if(have_a_target) {
        eptrs[num_eptrs++] = &target->second;
        ships_in_range = (distsq(target->second.position,ship.position) <= max_distsq);
      }
      for(auto it=enemies.begin();it<enemies.end() && num_eptrs<11;it++) {
        ships_iter enemy_iter = ships.find(it->second);
        if(enemy_iter==ships.end())
          continue;
        if(distsq(enemy_iter->second.position,ship.position)>max_distsq)
          break;
        eptrs[num_eptrs++] = &enemy_iter->second;
      }
      have_enemies=true;
      ships_in_range = ships_in_range or num_eptrs;
    }

    if(weapon.direct_fire and not ships_in_range)
      continue;
    
    real_t projectile_speed = weapon.terminal_velocity;
    real_t projectile_lifetime = weapon.projectile_lifetime;

    Vector3 p_weapon = weapon.position.rotated(y_axis,ship.rotation.y);
    p_weapon[1]=5;

    Vector3 weapon_rotation=Vector3(0,0,0);
    if(weapon.is_turret)
      weapon_rotation = weapon.rotation;

    for(int i=0;i<num_eptrs;i++) {
      const AABB &bound = eptrs[i]->aabb;
      Vector3 p_enemy = eptrs[i]->position+ship.confusion;
      Vector3 another1 = p_weapon+p_ship-p_enemy;

      if(weapon.guided and another1.length_squared()>max_travel_squared)
        break; // Enemies are out of range of this guided weapon.
      
      Vector3 projectile_velocity = ship.heading.rotated(y_axis,weapon_rotation.y)*projectile_speed;
      
      Vector3 v_enemy = eptrs[i]->linear_velocity;
      Vector3 another2 = another1 + projectile_lifetime*(projectile_velocity-v_enemy);
      another1[1]=0;
      another2[1]=0;
      if(bound.intersects_segment(another1,another2)) {
        if(not weapon.direct_fire) {
          hit_detected=true;
          create_projectile(ship,weapon,eptrs[i]->id);
          break;
        } else if(fire_direct_weapon(ship,weapon,false)) {
          hit_detected=true;
          break;
        }
      }
    }
  }
}

void CombatEngine::move_to_attack(Ship &ship,Ship &target) {
  FAST_PROFILING_FUNCTION;
  if(ship.weapons.empty() or ship.inactive or ship.immobile)
    return;

  bool in_range=false;
  Vector3 aim=aim_forward(ship,target,in_range);
  // if(not in_range) {
  //   Vector3 dp = get_position(ship)-get_position(target);
  //   if(dp.length_squared()<max(ship.radiussq,target.radiussq))
  //     in_range=true;
  // }

  real_t standoff_range=ship.get_standoff_range(target,idelta);
  
  if(in_range) {
    pull_back_to_standoff_range(ship,target,aim);
    request_heading(ship,aim);
  } else {
    move_to_intercept(ship,standoff_range*0.7,0,target.position,target.linear_velocity,false);
    return;
  }

  Vector3 dp = target.position - ship.position;
  real_t dotted = dot2(ship.heading,dp.normalized());
	
  // Heuristic; needs improvement
  if((dotted>=0.9 and dot2(ship.linear_velocity,dp)<0) or
     lensq2(dp)>max(100.0f,ship.turn_diameter_squared))
    request_thrust(ship,1.0,0.0);
  else if(dotted<-0.75 and ship.reverse_thrust>0)
    request_thrust(ship,0.0,1.0);
}

bool CombatEngine::move_to_intercept(Ship &ship,double close, double slow,
                                     DVector3 tgt_pos, DVector3 tgt_vel,
                                     bool force_final_state) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return false;
  const double big_dot_product = 0.95;
  DVector3 position = ship.position;
  DVector3 heading = get_heading_d(ship);
  DVector3 dp = tgt_pos - position;
  DVector3 dv = tgt_vel - DVector3(ship.linear_velocity);
  dp += dv*delta;
  double speed = dv.length();
  bool is_close = dp.length()<close;
  if(is_close && speed<slow) {
    if(force_final_state) {
      set_velocity(ship,Vector3(tgt_vel.x,0,tgt_vel.z));
      set_angular_velocity(ship,Vector3(0,0,0));
    }
    return true;
  }
  bool should_reverse = false;
  dp = tgt_pos - ship.stopping_point(tgt_vel, should_reverse);

  if(should_reverse and dp.length()<close*.95) {
    request_thrust(ship,0,1);
    return false;
  }

  DVector3 dp_dir = dp.normalized();
  double dot = dp_dir.dot(heading);
  bool is_facing = dot > big_dot_product;

  if( !is_close || !is_facing)
    request_heading(ship,Vector3(dp_dir.x,0,dp_dir.z));
  else
    set_angular_velocity(ship,Vector3(0,0,0));
  if(is_facing)
    request_thrust(ship,1,0);
  else if(should_reverse)
    request_thrust(ship,0,1);
  return false;
}

real_t CombatEngine::request_heading(Ship &ship, Vector3 new_heading) {
  FAST_PROFILING_FUNCTION;
  Vector3 norm_heading = new_heading.normalized();
  real_t cross = -cross2(norm_heading,ship.heading);
  real_t new_av=0, dot_product = dot2(norm_heading,ship.heading);
  
  if(dot_product>0) {
    double angle = asin_clamp(cross);
    new_av = copysign(1.0,angle)*min(fabsf(angle)/delta,ship.max_angular_velocity);
  } else
    new_av = cross<0 ? -ship.max_angular_velocity : ship.max_angular_velocity;
  set_angular_velocity(ship,Vector3(0,new_av,0));
  return dot_product;
}

void CombatEngine::request_rotation(Ship &ship, real_t rotation_factor) {
  FAST_PROFILING_FUNCTION;
  rotation_factor = clamp(rotation_factor,-1.0f,1.0f);
  set_angular_velocity(ship,Vector3(0,rotation_factor*ship.max_angular_velocity,0));
}

void CombatEngine::request_thrust(Ship &ship, real_t forward, real_t reverse) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile or (hyperspace and ship.fuel<=0))
    return;
  real_t ai_thrust = ship.thrust*clamp(forward,0.0f,1.0f) - ship.reverse_thrust*clamp(reverse,0.0f,1.0f);
  ship.energy -= delta*(ship.forward_thrust_energy*ship.thrust*clamp(forward,0.0f,1.0f) + ship.reverse_thrust_energy*ship.reverse_thrust*clamp(reverse,0.0f,1.0f));
  ship.heat += delta*(ship.forward_thrust_heat*ship.thrust*clamp(forward,0.0f,1.0f) + ship.reverse_thrust_heat*ship.reverse_thrust*clamp(reverse,0.0f,1.0f));
  Vector3 v_thrust = Vector3(ai_thrust,0,0).rotated(y_axis,ship.rotation.y);
  physics_server->body_add_central_force(ship.rid,v_thrust);
}

void CombatEngine::set_angular_velocity(Ship &ship,const Vector3 &angular_velocity) {
  FAST_PROFILING_FUNCTION;
  // Apply an impulse that gives the ship a new angular velocity.
  Vector3 change = angular_velocity-ship.angular_velocity;
  physics_server->body_apply_torque_impulse(ship.rid,change/ship.inverse_inertia);
  // Update our internal copy of the ship's angular velocity.
  ship.angular_velocity = angular_velocity;
}

void CombatEngine::set_velocity(Ship &ship,const Vector3 &velocity) {
  // Apply an impulse that gives the ship the new velocity.
  // Assumes the impulse is small, so we can ignore heat and energy
  FAST_PROFILING_FUNCTION;
  if(ship.inverse_mass<1e-5) {
    Godot::print_error(String("Invalid inverse mass ")+String(Variant(ship.inverse_mass)),__FUNCTION__,__FILE__,__LINE__);
    return;
  }
  physics_server->body_apply_central_impulse(ship.rid,(velocity-ship.linear_velocity)/ship.inverse_mass);
  // Update our internal copy of the ship's velocity.
  ship.linear_velocity = velocity;
}


/**********************************************************************/

/* PROJECTILES */

/**********************************************************************/

void CombatEngine::integrate_projectiles() {
  FAST_PROFILING_FUNCTION;
  //vector<object_id> deleteme;
  for(projectiles_iter it=projectiles.begin();it!=projectiles.end();) {
    Projectile &projectile = it->second;

    // Direct fire projectiles do damage when launched and last only one frame.
    // The exception is anti-missile projectiles which have to stay around for a few frames.
    if(projectile.direct_fire and not projectile.max_structure) {
      if(projectile.max_structure)
        missile_locations.remove(projectile.id);
      it=projectiles.erase(it);
      continue;
    }

    if(projectile.guided)
      guide_projectile(projectile);
    else {
      if(projectile.integrate_forces) {
        if(projectile.salvage)
          flotsam_locations.set_rect(projectile.id,rect_for_circle(projectile.position,projectile.radius()));
      }
      integrate_projectile_forces(projectile,1,true);
    }
    
    bool collided=false;
    if(projectile.possible_hit) {
      if(projectile.detonation_range>1e-5)
        collided = collide_projectile(projectile);
      else
        collided = collide_point_projectile(projectile);
      if(projectile.salvage)
        projectile.possible_hit=false;
    }
    
    if(collided or projectile.age > projectile.lifetime or (projectile.max_structure and not projectile.structure)) {
      if(projectile.salvage)
        flotsam_locations.remove(projectile.id);
      if(projectile.max_structure)
        missile_locations.remove(projectile.id);
      it=projectiles.erase(it);
    } else {
      if(projectile.max_structure) {
        Rect2 there(Vector2(projectile.position.x,projectile.position.z)-Vector2(PROJECTILE_POINT_WIDTH/2,PROJECTILE_POINT_WIDTH/2),
                    Vector2(PROJECTILE_POINT_WIDTH,PROJECTILE_POINT_WIDTH));
        missile_locations.set_rect(projectile.id,there);
      }
      it++;
    }
  }
}

void CombatEngine::create_direct_projectile(Ship &ship,Weapon &weapon,Vector3 position,real_t length,Vector3 rotation,object_id target) {
  FAST_PROFILING_FUNCTION;
  if(not weapon.can_fire())
    return;
  weapon.fire(ship,idelta);
  ship.tick_at_last_shot=ship.tick;
  object_id new_id=idgen.next();
  projectiles.emplace(new_id,Projectile(new_id,ship,weapon,position,length,rotation.y,target));
}

void CombatEngine::create_flotsam(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  for(auto & salvage_ptr : ship.salvage) {
    Vector3 v = ship.linear_velocity;
    real_t flotsam_mass = 10.0f;
    real_t speed = 50.0; //clamp(ship.explosion_impulse/flotsam_mass,10.0f,40.0f);
    speed = speed*(1+ship.rand.randf())/2;
    real_t angle = ship.rand.rand_angle();
    Vector3 heading = unit_from_angle(angle);
    v += heading*speed;
    object_id new_id=idgen.next();
    if(!salvage_ptr->flotsam_mesh.is_valid()) {
      Godot::print_warning(ship.name+": has a salvage with no flotsam mesh",__FUNCTION__,__FILE__,__LINE__);
      return;
    }
    std::pair<projectiles_iter,bool> emplaced = projectiles.emplace(new_id,Projectile(new_id,ship,salvage_ptr,ship.position,angle,v,flotsam_mass,multimeshes));
    real_t radius = max(1e-5f,emplaced.first->second.detonation_range);
    flotsam_locations.set_rect(new_id,rect_for_circle(emplaced.first->second.position,radius));
    emplaced.first->second.possible_hit=false;
  }
}

void CombatEngine::create_antimissile_projectile(Ship &ship,Weapon &weapon,Projectile &target,Vector3 position,real_t rotation,real_t length) {
  FAST_PROFILING_FUNCTION;
  if(not weapon.can_fire())
    return;
  weapon.fire(ship,idelta);
  // Do not update tick_at_last_shot since we're not shooting weapons at a ship target.
  object_id next = idgen.next();
  projectiles.emplace(next,Projectile(next,ship,weapon,target,position,rotation,length));
  ship.heat += weapon.firing_heat;
  ship.energy -= weapon.firing_energy;
}

void CombatEngine::create_projectile(Ship &ship,Weapon &weapon,object_id target) {
  FAST_PROFILING_FUNCTION;
  if(not weapon.can_fire())
    return;
  weapon.fire(ship,idelta);
  ship.tick_at_last_shot=ship.tick;
  object_id new_id=idgen.next();
  std::pair<projectiles_iter,bool> emplaced = projectiles.emplace(new_id,Projectile(new_id,ship,weapon,target));
  if(emplaced.first!=projectiles.end() and emplaced.first->second.max_structure) {
    Projectile &proj = emplaced.first->second;
    Rect2 there(Vector2(proj.position.x,proj.position.z)-Vector2(PROJECTILE_POINT_WIDTH/2,PROJECTILE_POINT_WIDTH/2),
                Vector2(PROJECTILE_POINT_WIDTH,PROJECTILE_POINT_WIDTH));
    missile_locations.set_rect(proj.id,there);
  }
  ship.heat += weapon.firing_heat;
  ship.energy -= weapon.firing_energy;
}

ships_iter CombatEngine::ship_for_rid(const RID &rid) {
  FAST_PROFILING_FUNCTION;
  rid2id_iter p_id = rid2id.find(rid.get_id());
  if(p_id == rid2id.end())
    // Ship no longer exists or target is not a ship.
    return ships.end();
  return ships.find(p_id->second);
}  

ships_iter CombatEngine::ship_for_rid(int rid_id) {
  FAST_PROFILING_FUNCTION;
  rid2id_iter p_id = rid2id.find(rid_id);
  if(p_id == rid2id.end())
    // Ship no longer exists or target is not a ship.
    return ships.end();
  return ships.find(p_id->second);
}

projectile_hit_list_t CombatEngine::find_projectile_collisions(Projectile &projectile,real_t radius,int max_results) {
  FAST_PROFILING_FUNCTION;
  projectile_hit_list_t result;

  if(not ship_locations.circle_is_nonempty(Vector2(projectile.position.x,projectile.position.z),radius)) {
    // No possibility of any hits.
    return result;
  }
  
  // FIXME: first pass with a boost r*tree
  if(radius>1e-5) {
    real_t trans_x(projectile.position.x), trans_z(projectile.position.z);
    real_t scale = radius / search_cylinder_radius;
    Ref<PhysicsShapeQueryParameters> query(PhysicsShapeQueryParameters::_new());
    query->set_collision_mask(enemy_masks[projectile.faction]);
    query->set_shape(search_cylinder);
    if(not ship_locations.circle_is_nonempty(Vector2(trans_x,trans_z),radius))
      return result; // No possibility of collision
    Transform trans;
    trans.scale(Vector3(scale,1,scale));
    trans.origin = Vector3(trans_x,5,trans_z);
    //query->set_transform(Transform(scale,0,0, 0,1,0, 0,0,scale, trans_x,5,trans_z));
    query->set_transform(trans);
    Array hits = space->intersect_shape(query,max_results);
    for(int i=0,size=hits.size();i<size;i++) {
      Dictionary hit=static_cast<Dictionary>(hits[i]);
      if(!hit.empty()) {
        ships_iter p_ship = ship_for_rid(static_cast<RID>(hit["rid"]).get_id());
        if(p_ship!=ships.end())
          result.emplace_back(p_ship->second.position,p_ship);
      }
    }
  } else {
    if(not ship_locations.point_is_nonempty(Vector2(projectile.position.x,projectile.position.z)))
      return result; // no possibility of collision
    Vector3 point1(projectile.position.x,500,projectile.position.z);
    Vector3 point2(projectile.position.x,-500,projectile.position.z);
    Dictionary hit = space->intersect_ray(point1, point2, Array(), enemy_masks[projectile.faction]);
    if(!hit.empty()) {
      ships_iter p_ship = ship_for_rid(static_cast<RID>(hit["rid"]).get_id());
      if(p_ship!=ships.end())
        result.emplace_back(static_cast<Vector3>(hit["position"]),p_ship);
    }
  }
  return result;
}

CE::ships_iter CombatEngine::space_intersect_ray_p_ship(Vector3 point1,Vector3 point2,int mask) {
  FAST_PROFILING_FUNCTION;

  if(not ship_locations.ray_is_nonempty(Vector2(point1.x,point1.z),
                                        Vector2(point2.x,point2.z)))
    // No possibility of any matches.
    return ships.end();
  
  static Array empty;
  Dictionary d=space->intersect_ray(point1,point2,empty,mask);
  rid2id_iter there=rid2id.find(static_cast<RID>(d["rid"]).get_id());
  if(there==rid2id.end())
    return ships.end();
  return ships.find(there->second);
}

void CombatEngine::salvage_projectile(Ship &ship,Projectile &projectile) {
  FAST_PROFILING_FUNCTION;
  if(projectile.salvage) {
    const Salvage & salvage = *projectile.salvage;
    salvaged_items.emplace(ship.id,projectile.salvage);
    if(salvage.structure_repair>0)
      ship.structure = min(double(ship.max_structure),ship.structure+salvage.structure_repair);
    if(salvage.armor_repair>0)
      ship.armor = min(double(ship.max_armor),ship.armor+salvage.armor_repair);
    if(salvage.cargo_unit_mass>0 and salvage.cargo_count>0) {
      float unit_mass = salvage.cargo_unit_mass/1000; // Convert kg->tons
      float old_mass = ship.cargo_mass;
      float original_max_mass = max(ship.cargo_mass,ship.max_cargo_mass);
      int pickup = floorf((original_max_mass-old_mass)/unit_mass);
      if(pickup>salvage.cargo_count)
        pickup=salvage.cargo_count;
      ship.cargo_mass = min(original_max_mass,old_mass+pickup*unit_mass);
      // if(ship.cargo_mass != old_mass)
      //   Godot::print(ship.name+" cargo mass increased from "+str(old_mass)+" to "+str(ship.cargo_mass)+" by picking up "+str(pickup)+" units of "+str(salvage.cargo_name));
    }
  }
}

bool CombatEngine::collide_point_projectile(Projectile &projectile) {
  FAST_PROFILING_FUNCTION;
  Vector3 point1(projectile.position.x,500,projectile.position.z);
  Vector3 point2(projectile.position.x,-500,projectile.position.z);
  ships_iter p_ship = space_intersect_ray_p_ship(point1,point2,enemy_masks[projectile.faction]);
  if(p_ship==ships.end())
    return false;

  if(projectile.damage)
    p_ship->second.take_damage(projectile.damage,projectile.damage_type,
                               projectile.heat_fraction,projectile.energy_fraction,projectile.thrust_fraction);
  if(projectile.impulse and not p_ship->second.immobile) {
    Vector3 impulse = projectile.impulse*projectile.linear_velocity.normalized();
    if(impulse.length_squared())
      physics_server->body_apply_central_impulse(p_ship->second.rid,impulse);
  }

  if(p_ship->second.fate==FATED_TO_FLY and projectile.salvage and p_ship->second.cargo_web_active)
    salvage_projectile(p_ship->second,projectile);
  return true;
}

bool CombatEngine::collide_projectile(Projectile &projectile) {
  FAST_PROFILING_FUNCTION;
  projectile_hit_list_t hits = find_projectile_collisions(projectile,projectile.detonation_range);
  if(hits.empty())
    return false;

  real_t min_dist = numeric_limits<real_t>::infinity();
  ships_iter closest = ships.end();
  Vector3 closest_pos(0,0,0);
  bool hit_something = false;

  for(auto &hit : hits) {
    Ship &ship = hit.second->second;
    if(ship.fate<=0) {
      real_t dist = ship.position.distance_to(projectile.position);
      if(dist<min_dist) {
        closest = hit.second;
        closest_pos = hit.first;
        min_dist = dist;
      }
      hit_something = true;
    }
  }

  if(hit_something) {
    bool have_impulse = projectile.impulse>1e-5;
    if(not projectile.salvage and projectile.blast_radius>1e-5) {
      projectile_hit_list_t blasted = find_projectile_collisions(projectile,projectile.blast_radius,max_ships_hit_per_projectile_blast);

      for(auto &blastee : blasted) {
        Ship &ship = blastee.second->second;
        if(ship.fate<=0) {
          real_t distance = max(0.0f,ship.position.distance_to(projectile.position)-ship.radius);
          real_t dropoff = 1.0 - distance/projectile.blast_radius;
          dropoff*=dropoff;
          if(projectile.damage)
            ship.take_damage(projectile.damage*dropoff,projectile.damage_type,
                             projectile.heat_fraction,projectile.energy_fraction,projectile.thrust_fraction);
          if(have_impulse and not ship.immobile) {
            Vector3 impulse1 = projectile.linear_velocity.normalized();
            Vector3 impulse2 = (ship.position-projectile.position).normalized();
            Vector3 combined = projectile.impulse*(impulse1+impulse2)*dropoff/2;
            if(combined.length_squared())
              physics_server->body_apply_central_impulse(ship.rid,combined);
          }
        }
      }
    } else {
      Ship &ship = closest->second;
      if(projectile.damage)
        closest->second.take_damage(projectile.damage,projectile.damage_type,
                                    projectile.heat_fraction,projectile.energy_fraction,projectile.thrust_fraction);
      if(have_impulse and not ship.immobile) {
        Vector3 impulse = projectile.impulse*projectile.linear_velocity.normalized();
        if(impulse.length_squared())
          physics_server->body_apply_central_impulse(ship.rid,impulse);
      }
      if(ship.fate==FATED_TO_FLY and projectile.salvage and ship.cargo_web_active)
        salvage_projectile(ship,projectile);
    }
    return true;
  } else
    return false;
}

ships_iter CombatEngine::get_projectile_target(Projectile &projectile) {
  FAST_PROFILING_FUNCTION;

  ships_iter target_iter = ships.find(projectile.target);
  
  if(target_iter != ships.end() or not projectile.auto_retarget)
    return target_iter;

  // Target is gone. Is the attacker still alive?
  
  ships_iter source_iter = ships.find(projectile.source);
  if(source_iter == ships.end())
    return target_iter;

  // Projectile target is now the new target of the attacker.
  projectile.target = source_iter->second.get_target();

  // Use the new target, if it exists.
  target_iter = ships.find(projectile.target);
  return target_iter;
}

void CombatEngine::guide_projectile(Projectile &projectile) {
  FAST_PROFILING_FUNCTION;

  ships_iter target_iter = get_projectile_target(projectile);
  if(target_iter == ships.end()) {
    projectile.angular_velocity.y = 0;
    integrate_projectile_forces(projectile,1,true);
    return; // Nothing to track.
  }

  Ship &target = target_iter->second;
  if(target.fate==FATED_TO_DIE) {
    projectile.angular_velocity.y = 0;
    integrate_projectile_forces(projectile,1,true);
    return; // Target is dead.
  }
  real_t max_speed = projectile.max_speed; // linear_velocity.length();
  if(max_speed<1e-5) {
    projectile.angular_velocity.y = 0;
    integrate_projectile_forces(projectile,1,true);
    return; // Cannot track until we have a speed.
  }

  DVector3 relative_position = target.position - projectile.position;
  DVector3 course_velocity;
  double intercept_time;
  double lifetime_remaining = projectile.lifetime-projectile.age;
  
  if(projectile.guidance_uses_velocity) {
    pair<DVector3,double> course = plot_collision_course(relative_position,target.linear_velocity,max_speed);
    intercept_time = course.second;
    course_velocity = course.first;

    if(!(intercept_time>1e-5)) // !(>) detects NaN
      intercept_time=1e-5;
  } else {
    course_velocity = relative_position.normalized()*max_speed;
    intercept_time = relative_position.length()/max_speed;
  }

  double intercept_time_ratio = intercept_time/max(1e-5,lifetime_remaining);

  double weight = 0.0;
  if(intercept_time_ratio>0.5)
    weight = min(1.0,2*(intercept_time_ratio-0.5));
  
  DVector3 velocity_correction = course_velocity-projectile.linear_velocity;
  DVector3 heading = get_heading_d(projectile);
  DVector3 desired_heading = velocity_correction.normalized()*(1-weight) + course_velocity.normalized()*weight;
  double desired_heading_angle = angle_from_unit(desired_heading);
  double heading_angle = angle_from_unit(heading);
  double angle_correction = desired_heading_angle-heading_angle;
  double turn_rate = projectile.turn_rate;

  bool should_thrust = dot2(heading,desired_heading)>0.95; // Don't thrust away from desired heading

  projectile.angular_velocity.y = clamp(angle_correction/delta,-turn_rate,turn_rate);

  integrate_projectile_forces(projectile,should_thrust,true);
}

bool CombatEngine::is_eta_lower_with_thrust(DVector3 target_position,DVector3 target_velocity,const Projectile &proj,DVector3 heading) {
  FAST_PROFILING_FUNCTION;
  DVector3 next_target_position = target_position+target_velocity*delta;
  next_target_position.y=0;
  DVector3 next_heading = heading+proj.angular_velocity*delta;
  DVector3 position = proj.position;
  position.y=0;
  
  DVector3 position_without_thrust = position+proj.linear_velocity*delta;
  DVector3 dp=next_target_position-position_without_thrust;
  double eta_without_thrust = dp.length()/proj.max_speed + fabs(angle2(next_heading,dp.normalized()))/proj.turn_rate;

  DVector3 next_velocity = proj.linear_velocity;
  next_velocity -= proj.linear_velocity*proj.drag*delta;
  next_velocity += proj.thrust*next_heading*delta/proj.mass;
  
  DVector3 position_with_thrust = position+next_velocity*delta;
  dp=next_target_position-position_with_thrust;
  double eta_with_thrust = dp.length()/proj.max_speed + fabs(angle2(next_heading,dp.normalized()))/proj.turn_rate;

  return eta_with_thrust<eta_without_thrust;
}

void CombatEngine::integrate_projectile_forces(Projectile &projectile,real_t thrust_fraction,bool drag) {
  FAST_PROFILING_FUNCTION;

  projectile.age += delta;

  // Projectiles with direct fire are always at their destination.
  if(projectile.direct_fire)
    return;

  // Integrate forces if requested.
  if(projectile.integrate_forces) {
    real_t mass=max(projectile.mass,1e-5f);
    if(drag and (projectile.always_drag ||
                 projectile.linear_velocity.length_squared()>projectile.max_speed*projectile.max_speed) )
      projectile.linear_velocity -= projectile.linear_velocity*projectile.drag*projectile.mass*delta;
    if(projectile.thrust and thrust_fraction>0)
      projectile.forces += projectile.thrust*thrust_fraction*get_heading(projectile);
    projectile.linear_velocity += projectile.forces*delta/mass;
    projectile.forces = Vector3(0,0,0);
  }

  // Advance state by time delta
  projectile.rotation.y += projectile.angular_velocity.y*delta;
  projectile.position += projectile.linear_velocity*delta;
}




/**********************************************************************/

/* Visual Thread and Physics->Visual communication */

/**********************************************************************/

// Send next batch of visible content to visual thread
void CombatEngine::add_content() {
  FAST_PROFILING_FUNCTION;
  VisibleContent *next = new VisibleContent();
  next->ships_and_planets.reserve(ships.size()+planets.size());
  ships_iter player_it = ships.find(player_ship_id);
  object_id player_target_id = (player_it==ships.end()) ? -1 : player_it->second.get_target();
  
  for(auto &it : ships) {
    Ship &ship = it.second;
    bool hostile = player_faction_mask&enemy_masks[ship.faction];
    VisibleObject visual(ship,hostile);
    if(ship.id == player_ship_id)
      visual.flags |= VISIBLE_OBJECT_PLAYER;
    else if(ship.id == player_target_id)
      visual.flags |= VISIBLE_OBJECT_PLAYER_TARGET;
    if(ship.faction_mask&enemy_masks[ship.faction])
      visual.flags |= VISIBLE_OBJECT_HOSTILE;
    next->ships_and_planets.emplace(ship.id,visual);
  }
  for(auto &it : planets) {
    Planet &planet = it.second;
    VisibleObject visual(planet);
    if(planet.id == player_target_id)
      visual.flags |= VISIBLE_OBJECT_PLAYER_TARGET;
    next->ships_and_planets.emplace(it.second.id,visual);
  }

  next->effects.reserve(projectiles.size());
  for(auto &it : projectiles) {
    next->effects.emplace_back(it.second);
    if(next->mesh_paths.find(it.second.mesh_id)==next->mesh_paths.end()) {
      String mesh_path = multimeshes.get_mesh_path(it.second.mesh_id);
      if(mesh_path.empty() and it.second.mesh_id<=0)
        Godot::print_warning("Mesh "+str(it.second.mesh_id)+" has no mesh path.",__FUNCTION__,__FILE__,__LINE__);
      else
        next->mesh_paths.emplace(it.second.mesh_id,mesh_path);
    }
  }
  // Prepend to linked list:
  content.push_content(next);
}


static inline bool origin_intersection(real_t end_x,real_t end_y,real_t bound_x,real_t bound_y,real_t &intersection) {
  if(end_x<bound_x)
    return false;
  intersection = end_y*bound_x/end_x;
  return intersection>-bound_y and intersection<bound_y;
}

Vector2 CombatEngine::place_in_rect(const Vector2 &map_location,
                                    const Vector2 &map_center,const Vector2 &map_scale,
                                    const Vector2 &minimap_center,const Vector2 &minimap_half_size) {
  FAST_PROFILING_FUNCTION;
  Vector2 centered = (map_location-map_center)*map_scale;
  real_t intersection;

  if(origin_intersection(centered.x,centered.y,minimap_half_size.x,minimap_half_size.y,intersection))
    // Object is to the left of the minimap.
    return Vector2(minimap_half_size.x,intersection)+minimap_center;

  if(origin_intersection(-centered.x,centered.y,minimap_half_size.x,minimap_half_size.y,intersection))
    // Object is to the right of the minimap.
    return Vector2(-minimap_half_size.x,intersection)+minimap_center;

  if(origin_intersection(centered.y,centered.x,minimap_half_size.y,minimap_half_size.x,intersection))
    // Object is below the minimap.
    return Vector2(intersection,minimap_half_size.y)+minimap_center;

  if(origin_intersection(-centered.y,centered.x,minimap_half_size.y,minimap_half_size.x,intersection))
    // Object is above the minimap.
    return Vector2(intersection,-minimap_half_size.y)+minimap_center;

  // Object is within the minimap.
  return centered+minimap_center;
}

Vector2 CombatEngine::place_center(const Vector2 &where,
                                   const Vector2 &map_center,real_t map_radius,
                                   const Vector2 &minimap_center,real_t minimap_radius) {
  FAST_PROFILING_FUNCTION;
  Vector2 minimap_scaled = (where-map_center)/map_radius*minimap_radius;
  real_t outside=minimap_radius*0.95;
  real_t outside_squared = outside*outside;
  if(minimap_scaled.length_squared() > outside_squared)
    minimap_scaled = minimap_scaled.normalized()*outside;
  return minimap_scaled + minimap_center;
}

void CombatEngine::draw_anulus(const Vector2 &center,real_t inner_radius,real_t outer_radius,
                               const Color &color,bool antialiased) {
  FAST_PROFILING_FUNCTION;
  real_t middle_radius = (inner_radius+outer_radius)/2;
  real_t thickness = fabsf(outer_radius-inner_radius);
  PoolVector2Array points;
  PoolColorArray colors;
  int npoints = 80; // clamp(int(middle_radius/thickness+3)/4,8,200);
  points.resize(npoints+1);
  colors.resize(npoints+1);

  PoolColorArray::Write write_colors=colors.write();
  Color *color_data = write_colors.ptr();
  
  for(int i=0;i<=npoints;i++)
    color_data[i]=color;
  
  PoolVector2Array::Write write_points=points.write();
  Vector2 *point_data=write_points.ptr();
  
  for(int i=0;i<npoints;i++) {
    real_t a = 2*PI*i/npoints;
    real_t x = sin(a)*middle_radius;
    real_t y = cos(a)*middle_radius;
    point_data[i] = center+Vector2(x,y);
  }
  
  point_data[npoints] = point_data[0];
  
  visual_server->canvas_item_add_polyline(canvas,points,colors,thickness,antialiased);
}

void CombatEngine::draw_crosshairs(const Vector2 &loc, real_t radius, const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector2 small_x(radius*1.5+1,0);
  Vector2 small_y(0,radius*1.5+1);
  Vector2 big_x(12,0);
  Vector2 big_y(0,12);
  visual_server->canvas_item_add_line(canvas,loc-big_x,loc-small_x,color,crosshairs_width,true);
  visual_server->canvas_item_add_line(canvas,loc+big_x,loc+small_x,color,crosshairs_width,true);
  visual_server->canvas_item_add_line(canvas,loc-big_y,loc-small_y,color,crosshairs_width,true);
  visual_server->canvas_item_add_line(canvas,loc+big_y,loc+small_y,color,crosshairs_width,true);
  draw_anulus(loc,big_x[0]-crosshairs_width/2,big_x[0]+crosshairs_width/2,color,true);
}

void CombatEngine::draw_velocity(VisibleObject &ship, const Vector2 &loc,
                                 const Vector2 &map_center,real_t map_radius,
                                 const Vector2 &minimap_center,real_t minimap_radius,
                                 const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector2 away = place_center(Vector2(ship.z,-ship.x)+Vector2(ship.vz,-ship.vx),
                              map_center,map_radius,minimap_center,minimap_radius);
  visual_server->canvas_item_add_line(canvas,loc,away,color,1.5,true);
}

void CombatEngine::draw_heading(VisibleObject &ship, const Vector2 &loc,
                                const Vector2 &map_center,real_t map_radius,
                                const Vector2 &minimap_center,real_t minimap_radius,
                                const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector3 heading3 = unit_from_angle(ship.rotation_y);
  Vector2 heading2(heading3.z,-heading3.x);
  Vector2 minimap_heading = place_center(Vector2(ship.z,-ship.x)+ship.max_speed*1.25*heading2,
                                         map_center,map_radius,minimap_center,minimap_radius);
  visual_server->canvas_item_add_line(canvas,loc,minimap_heading,color,1,true);
}

void CombatEngine::rect_draw_velocity(VisibleObject &ship, const Vector2 &loc,
                                      const Vector2 &map_center,const Vector2 &map_scale,
                                      const Vector2 &minimap_center,const Vector2 &minimap_half_size,
                                      const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector2 away = place_in_rect(Vector2(ship.z,-ship.x)+Vector2(ship.vz,-ship.vx),
                               map_center,map_scale,minimap_center,minimap_half_size);
  visual_server->canvas_item_add_line(canvas,loc,away,color,1.5,true);
}

void CombatEngine::rect_draw_heading(VisibleObject &ship, const Vector2 &loc,
                                     const Vector2 &map_center,const Vector2 &map_scale,
                                     const Vector2 &minimap_center,const Vector2 &minimap_half_size,
                                     const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector3 heading3 = unit_from_angle(ship.rotation_y);
  Vector2 heading2(heading3.z,-heading3.x);
  Vector2 minimap_heading = place_in_rect(Vector2(ship.z,-ship.x)+ship.max_speed*1.25*heading2,
                                          map_center,map_scale,minimap_center,minimap_half_size);
  visual_server->canvas_item_add_line(canvas,loc,minimap_heading,color,1,true);
}

const Color &CombatEngine::pick_object_color(VisibleObject &object) {
  FAST_PROFILING_FUNCTION;
  if(object.flags&VISIBLE_OBJECT_PLANET)
    return planet_color;
  if(object.flags&VISIBLE_OBJECT_PLAYER)
    return player_color;
  if(object.flags&VISIBLE_OBJECT_HOSTILE)
    return hostile_color;
  return friendly_color;
}
