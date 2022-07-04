#include <cstdint>
#include <cmath>
#include <limits>
#include <map>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>
#include <RID.hpp>

#include "CE/CombatEngine.hpp"
#include "CE/Utils.hpp"
#include "CE/Data.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

Dictionary CombatEngine::space_intersect_ray(PhysicsDirectSpaceState *space,Vector3 point1,Vector3 point2,int mask) {
  FAST_PROFILING_FUNCTION;
  if(not ship_locations.ray_is_nonempty(Vector2(point1.x,point1.z),Vector2(point2.x,point2.z)))
    return Dictionary();
  static Array empty = Array();
  return space->intersect_ray(point1,point2,empty,mask);
}

CombatEngine::CombatEngine():
  system_fuel_recharge(0),
  center_fuel_recharge(0),
  hyperspace(false),

  minimap(),
  
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
  VisibleContent *visible_content=content.get_visible_content();
  minimap.draw_minimap_contents(visible_content,new_canvas,map_center,map_radius,minimap_center,minimap_radius);
}



void CombatEngine::draw_minimap_rect_contents(RID new_canvas,Rect2 map,Rect2 minimap) {
  FAST_PROFILING_FUNCTION;
  VisibleContent *visible_content=content.get_visible_content();
  this->minimap.draw_minimap_rect_contents(visible_content,new_canvas,map,minimap);
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
      ship.ai_step(*this);
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
    ship.create_flotsam(*this);
  }
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


/**********************************************************************/

/* PROJECTILES */

/**********************************************************************/

void CombatEngine::integrate_projectiles() {
  FAST_PROFILING_FUNCTION;
  //vector<object_id> deleteme;
  for(projectiles_iter it=projectiles.begin();it!=projectiles.end();) {
    Projectile &projectile = it->second;

    bool have_died=false, have_moved=false, have_collided=false;

    projectile.step_projectile(*this,have_died,have_collided,have_moved);
    if(have_died) {
      if(projectile.is_missile())
        missile_locations.remove(projectile.id);
      if(projectile.is_flotsam())
        flotsam_locations.remove(projectile.id);
      if(projectile.is_antimissile())
        Godot::print("remove antimissile");
      it=projectiles.erase(it);
    } else {
      if(have_moved) {
        if(projectile.is_missile()) {
          Rect2 there(Vector2(projectile.position.x,projectile.position.z)
                      - Vector2(PROJECTILE_POINT_WIDTH/2,PROJECTILE_POINT_WIDTH/2),
                      Vector2(PROJECTILE_POINT_WIDTH,PROJECTILE_POINT_WIDTH));
          missile_locations.set_rect(projectile.id,there);
        }
        if(projectile.is_flotsam())
          flotsam_locations.set_rect(projectile.id,rect_for_circle(projectile.position,projectile.radius()));
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

void CombatEngine::create_flotsam_projectile(Ship &ship,shared_ptr<const Salvage> salvage_ptr,Vector3 position,real_t angle,Vector3 velocity,real_t flotsam_mass) {
  object_id new_id=idgen.next();
  std::pair<projectiles_iter,bool> emplaced = projectiles.emplace(new_id,Projectile(new_id,ship,salvage_ptr,position,angle,velocity,flotsam_mass,multimeshes));
  real_t radius = max(1e-5f,emplaced.first->second.detonation_range);
  flotsam_locations.set_rect(new_id,rect_for_circle(emplaced.first->second.position,radius));
  emplaced.first->second.possible_hit=false;
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

Ship *CombatEngine::space_intersect_ray_p_ship(Vector3 point1,Vector3 point2,int mask) {
  FAST_PROFILING_FUNCTION;

  if(not ship_locations.ray_is_nonempty(Vector2(point1.x,point1.z),
                                        Vector2(point2.x,point2.z)))
    // No possibility of any matches.
    return nullptr;
  
  static Array empty;
  Dictionary d=space->intersect_ray(point1,point2,empty,mask);
  rid2id_iter there=rid2id.find(static_cast<RID>(d["rid"]).get_id());
  if(there==rid2id.end())
    return nullptr;
  return ship_with_id(there->second);
}

void CombatEngine::add_salvaged_items(Ship &ship,const Projectile &projectile) {
  salvaged_items.emplace(ship.id,projectile.salvage);
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
