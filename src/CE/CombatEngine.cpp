#include <cstdint>
#include <cmath>
#include <limits>
#include <map>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>
#include <RID.hpp>

#include "CE/Salvage.hpp"
#include "CE/CombatEngine.hpp"
#include "CE/Utils.hpp"
#include "CE/Data.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

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
  asteroid_fields(),
  player_orders(),
  salvaged_items(),
  weapon_rotations(),
  dead_ships(),
  idgen(),
  delta(1.0/60),
  idelta(delta*ticks_per_second),
  player_ship_id(-1),
  p_frame(0),
  ai_ticks(0),

  flotsam_weapon(make_shared<Weapon>(Weapon::CreateFlotsamPlaceholder())),
  
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
  rand(),
  
  visual_server(VisualServer::get_singleton()),
  v_delta(0),
  v_camera_location(FAR,FAR,FAR),
  v_camera_size(BIG,BIG,BIG),
  scenario(),
  reset_scenario(false),

  objects_found(),

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
  register_method("add_asteroid_field", &CombatEngine::add_asteroid_field);
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
  asteroid_fields.clear();
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

  // Update asteroids:
  step_asteroid_fields();
  
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

  visible_content->asteroid_fields.reserve(asteroid_fields.size());
  for(auto &field : asteroid_fields)
    visible_content->asteroid_fields.emplace_back(field.get_inner_radius(),field.get_outer_radius());
  
  // Catalog projectiles and make MeshInfos in v_meshes for mesh_ids we don't have yet
  multimeshes.update_content(*visible_content,location,size);
  multimeshes.load_meshes();
  multimeshes.send_meshes_to_visual_server(projectile_scale,scenario,reset_scenario);

  send_asteroid_meshes();

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


void CombatEngine::add_asteroid_field(Dictionary field_data) {
  shared_ptr<AsteroidPalette> ap=make_shared<AsteroidPalette>(field_data["asteroids"]);
  if(!ap->size())
    Godot::print_error("AsteroidPalette is empty. Asteroids will be invisible!",
                       __FUNCTION__,__FILE__,__LINE__);
  object_id id = (static_cast<object_id>(asteroid_fields.size())<<id_category_shift)
                 + first_asteroid_field_id_mask;
  shared_ptr<SalvagePalette> sp=make_shared<SalvagePalette>(field_data["salvage"]);
  asteroid_fields.emplace_back(0,godot::CE::get<Array>(field_data,"layers"),ap,sp,id);
  asteroid_fields.back().generate_field();
}

/**********************************************************************/

/* Asteroids */

/**********************************************************************/

void CombatEngine::damage_asteroid(Asteroid &asteroid,double damage,int damage_type) {
  object_id field_id = asteroid.get_id()>>id_category_shift;
  if(field_id<0 or static_cast<size_t>(field_id)>=asteroid_fields.size())
    Godot::print_error("Tried to damage an asteroid from invalid field number "+str(field_id),
                       __FUNCTION__,__FILE__,__LINE__);
  else
    asteroid_fields[field_id].damage_asteroid(*this,asteroid,damage,damage_type);
}

void CombatEngine::step_asteroid_fields() {
  Rect2 visible_area(Vector2(-100,-100),Vector2(200,200));
  if(visual_effects.is_valid())
    visible_area = visual_effects->get_visible_rect();
  for(auto &field : asteroid_fields)
    field.step_time(idelta,delta,visible_area);
}


void CombatEngine::send_asteroid_meshes() {
  for(auto &field : asteroid_fields)
    field.send_meshes(multimeshes);
}


void CombatEngine::add_asteroid_content(VisibleContent &content) {
  Rect2 visible_area(Vector2(-100,-100),Vector2(200,200));
  if(visual_effects.is_valid())
    visible_area = visual_effects->get_visible_rect();
  for(auto &field : asteroid_fields)
    field.add_content(visible_area,content);
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
      faction.update_one_faction_goal(*this,goal);
  }
  last_planet_updated = -1;
  last_faction_updated = FACTION_ARRAY_SIZE;
}

void CombatEngine::faction_ai_step() {
  update_all_faction_goals();
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
      objects_hit.clear();
      if(overlapping_circle(ship.get_xz(),ship.explosion_radius,MASK_ALL_FACTIONS,FIND_SHIPS|FIND_ASTEROIDS,objects_hit,SHIP_EXPLOSION_MAX_HITS)) {
        real_t blast_radius=ship.explosion_radius;
        real_t dropoff_denom = (1-BLAST_DAMAGE_AT_FULL_RADIUS)/(blast_radius*blast_radius);
        faction_mask_t enemy_mask = enemy_masks[ship.faction];
        for(auto &hit : objects_hit) {
          if(hit.hit->is_ship()) {
            Ship &other = hit.hit->as_ship();
            if(other.id==ship.id)
              continue;
            real_t distance = max(0.0f,other.position.distance_to(ship.position)-other.radius);
            real_t dropoff = 1-distance*distance*dropoff_denom;
            if( (other.faction_mask&enemy_mask) )
              other.take_damage(ship.explosion_damage*dropoff,ship.explosion_type,0.1,0,0);
            if(not other.immobile and ship.explosion_impulse!=0) {
              Vector3 impulse = ship.explosion_impulse * dropoff *
                (other.position-ship.position).normalized();
              if(impulse.length_squared())
                physics_server->body_apply_central_impulse(other.rid,impulse);
            }
          } else if(hit.hit->is_asteroid()) {
            Asteroid &asteroid = hit.hit->as_asteroid();
            real_t distance = max(0.0f,hit.xz.distance_to(ship.get_xz())-asteroid.get_radius());
            real_t dropoff = (1 - distance*distance*dropoff_denom);
            damage_asteroid(asteroid,ship.explosion_damage*dropoff,ship.explosion_type);
          }
        }
      }
    }
    ship.create_flotsam(*this);
  }
}

void CombatEngine::encode_salvaged_items_for_gdscript(Array result) {
  FAST_PROFILING_FUNCTION;
  result.clear();
  result.resize(salvaged_items.size());
  int i=0;
  for(auto &dict : salvaged_items) {
    if(!dict.size())
      Godot::print_warning("Empty dict seen in salvaged_items",
                           __FUNCTION__,__FILE__,__LINE__);
    result[i++]=dict;
  }
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
        missile_locations.remove(projectile.get_id());
      if(projectile.is_flotsam())
        flotsam_locations.remove(projectile.get_id());
      it=projectiles.erase(it);
    } else {
      if(have_moved) {
        if(projectile.is_missile()) {
          Rect2 there(Vector2(projectile.get_position().x,projectile.get_position().z)
                      - Vector2(PROJECTILE_POINT_WIDTH/2,PROJECTILE_POINT_WIDTH/2),
                      Vector2(PROJECTILE_POINT_WIDTH,PROJECTILE_POINT_WIDTH));
          missile_locations.set_rect(projectile.get_id(),there);
        }
        if(projectile.is_flotsam())
          flotsam_locations.set_rect(projectile.get_id(),rect_for_circle(projectile.get_position(),projectile.radius()));
      }
      it++;
    }
  }
}

void CombatEngine::create_direct_projectile(Ship &ship,shared_ptr<Weapon> weapon,Vector3 position,real_t length,Vector3 rotation,object_id target) {
  FAST_PROFILING_FUNCTION;
  if(not weapon->can_fire())
    return;
  weapon->fire(ship,idelta);
  ship.tick_at_last_shot=ship.tick;
  object_id new_id=idgen.next();
  projectiles.emplace(new_id,Projectile(new_id,ship,weapon,position,length,rotation.y,target));
}

void CombatEngine::create_flotsam_projectile(Ship *ship_ptr,shared_ptr<const Salvage> salvage_ptr,Vector3 position,real_t angle,Vector3 velocity,real_t flotsam_mass) {
  object_id new_id=idgen.next();
  std::pair<projectiles_iter,bool> emplaced = projectiles.emplace(new_id,Projectile(new_id,ship_ptr,salvage_ptr,position,angle,velocity,flotsam_mass,multimeshes,flotsam_weapon));
  real_t radius = max(1e-5f,emplaced.first->second.get_detonation_range());
  flotsam_locations.set_rect(new_id,rect_for_circle(emplaced.first->second.get_position(),radius));
  emplaced.first->second.set_possible_hit(false);
}

void CombatEngine::create_antimissile_projectile(Ship &ship,shared_ptr<Weapon> weapon,Projectile &target,Vector3 position,real_t rotation,real_t length) {
  FAST_PROFILING_FUNCTION;
  if(not weapon->can_fire())
    return;
  weapon->fire(ship,idelta);
  // Do not update tick_at_last_shot since we're not shooting weapons at a ship target.
  object_id next = idgen.next();
  projectiles.emplace(next,Projectile(next,ship,weapon,target,position,rotation,length));
  ship.heat += weapon->firing_heat;
  ship.energy -= weapon->firing_energy;
}

void CombatEngine::create_projectile(Ship &ship,shared_ptr<Weapon> weapon,object_id target) {
  FAST_PROFILING_FUNCTION;
  if(not weapon->can_fire())
    return;
  weapon->fire(ship,idelta);
  ship.tick_at_last_shot=ship.tick;
  object_id new_id=idgen.next();
  std::pair<projectiles_iter,bool> emplaced = projectiles.emplace(new_id,Projectile(new_id,ship,weapon,target));
  if(emplaced.first!=projectiles.end() and emplaced.first->second.get_max_structure()) {
    Projectile &proj = emplaced.first->second;
    Rect2 there(Vector2(proj.get_position().x,proj.get_position().z)-Vector2(PROJECTILE_POINT_WIDTH/2,PROJECTILE_POINT_WIDTH/2),
                Vector2(PROJECTILE_POINT_WIDTH,PROJECTILE_POINT_WIDTH));
    missile_locations.set_rect(proj.get_id(),there);
  }
  ship.heat += weapon->firing_heat;
  ship.energy -= weapon->firing_energy;
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

/**********************************************************************/

size_t CombatEngine::overlapping_circle(Vector2 center,real_t radius,faction_mask_t collision_mask,int find_what,hit_list_t &result,size_t max_hits) {
  if(!collision_mask)
    return 0;
  if(radius<=0)
    return overlapping_point(center,collision_mask,find_what,result,max_hits);

  size_t count=0;
  
  if( (find_what&FIND_MISSILES) ) {
    objects_found.clear();
    if(missile_locations.overlapping_circle(center,radius,objects_found))
      for(auto &id : objects_found) {
        Projectile *proj = projectile_with_id(id);
        if( (proj->get_faction_mask()&collision_mask) and proj->is_alive() and proj->is_missile()) {
          result.emplace_back(proj,proj->get_xz(),proj->get_xz().distance_to(center));
          if(++count>=max_hits)
            return count;
        }
      }
  }

  if( (find_what&FIND_SHIPS) ) {
    objects_found.clear();
    if(ship_locations.overlapping_circle(center,radius,objects_found)) {
      real_t scale = radius / search_cylinder_radius;
      Ref<PhysicsShapeQueryParameters> query(PhysicsShapeQueryParameters::_new());
      query->set_collision_mask(collision_mask);
      query->set_shape(search_cylinder);
      Transform trans;
      trans.scale(Vector3(scale,1,scale));
      trans.origin = to_xyz(center,ship_height);
      query->set_transform(trans);
      Array hits = space->intersect_shape(query,max_hits-count);
      for(int i=0,size=hits.size();i<size;i++) {
        Dictionary hit=hits[i];
        if(!hit.empty()) {
          ships_iter p_ship = ship_for_rid(static_cast<RID>(hit["rid"]).get_id());
          if(p_ship!=ships.end()) {
            result.emplace_back(&p_ship->second,p_ship->second.get_xz(),
                                p_ship->second.get_xz().distance_to(center));
            if(++count>=max_hits)
              return count;
          }
        }
      }
    }
  }

  if( (find_what&FIND_PLANETS) ) {
    for(auto &id_planet : planets) {
      Vector2 xz=id_planet.second.get_xz();
      real_t dist = xz.distance_to(center);
      if(dist<id_planet.second.get_radius()+radius) {
        result.emplace_back(&id_planet.second,xz,dist);
        if(++count>=max_hits)
          return count;
      }
    }
  }

  if( (find_what&FIND_ASTEROIDS) ) {
    for(auto &field : asteroid_fields) {
      count+=field.overlapping_circle(center,radius,result,max_hits-count);
      if(count>=max_hits)
        return count;
    }
  }

  return count;
}

/**********************************************************************/

size_t CombatEngine::overlapping_point(Vector2 point,faction_mask_t collision_mask,int find_what,hit_list_t &result,size_t max_hits) {
  if(!collision_mask)
    return 0;

  size_t count=0;
  
  if( (find_what&FIND_MISSILES) ) {
    objects_found.clear();
    if(missile_locations.overlapping_point(point,objects_found))
      for(auto &id : objects_found) {
        Projectile *proj = projectile_with_id(id);
        if( (proj->get_faction_mask()&collision_mask) and proj->is_alive() and proj->is_missile()) {
          result.emplace_back(proj,proj->get_xz(),proj->get_xz().distance_to(point));
          if(++count>=max_hits)
            return count;
        }
      }
  }

  if( (find_what&FIND_SHIPS) ) {
    objects_found.clear();
    if(ship_locations.overlapping_point(point,objects_found)) {
      Array hits = space->intersect_point(Vector3(point.x,ship_height,point.y),max_hits-count,Array(),collision_mask,true,false);
      for(int i=0,size=hits.size();i<size;i++) {
        Dictionary hit=hits[i];
        if(!hit.empty()) {
          ships_iter p_ship = ship_for_rid(static_cast<RID>(hit["rid"]).get_id());
          if(p_ship!=ships.end()) {
            result.emplace_back(&p_ship->second,p_ship->second.get_xz(),
                                p_ship->second.get_xz().distance_to(point));
            if(++count>=max_hits)
              return count;
          }
        }
      }
    }
  }

  if( (find_what&FIND_PLANETS) ) {
    for(auto &id_planet : planets) {
      Vector2 xz=id_planet.second.get_xz();
      real_t dist = xz.distance_to(point);
      if(dist<id_planet.second.get_radius()) {
        result.emplace_back(&id_planet.second,xz,dist);
        if(++count>=max_hits)
          return count;
      }
    }
  }

  if( (find_what&FIND_ASTEROIDS) ) {
    for(auto &field : asteroid_fields) {
      count+=field.overlapping_point(point,result,max_hits-count);
      if(count>=max_hits)
        return count;
    }
  }

  return count;
}

/**********************************************************************/

CelestialHit CombatEngine::first_in_circle(Vector2 center,real_t radius,faction_mask_t collision_mask,int find_what) {
  if(!collision_mask)
    return CelestialHit();
  if(radius<=0)
    return first_at_point(center,collision_mask,find_what);

  if( (find_what&FIND_MISSILES) ) {
    objects_found.clear();
    if(missile_locations.overlapping_circle(center,radius,objects_found))
      for(auto &id : objects_found) {
        Projectile *proj = projectile_with_id(id);
        if( (proj->get_faction_mask()&collision_mask) and proj->is_alive() and proj->is_missile())
          return CelestialHit(proj,proj->get_xz(),proj->get_xz().distance_to(center));
      }
  }

  if( (find_what&FIND_SHIPS) ) {
    objects_found.clear();
    if(ship_locations.overlapping_circle(center,radius,objects_found)) {
      real_t scale = radius / search_cylinder_radius;
      Ref<PhysicsShapeQueryParameters> query(PhysicsShapeQueryParameters::_new());
      query->set_collision_mask(collision_mask);
      query->set_shape(search_cylinder);
      Transform trans;
      trans.scale(Vector3(scale,1,scale));
      trans.origin = to_xyz(center,ship_height);
      query->set_transform(trans);
      Array hits = space->intersect_shape(query,10);
      for(int i=0,size=hits.size();i<size;i++) {
        Dictionary hit=hits[i];
        if(!hit.empty()) {
          ships_iter p_ship = ship_for_rid(static_cast<RID>(hit["rid"]).get_id());
          if(p_ship!=ships.end())
            return CelestialHit(&p_ship->second,p_ship->second.get_xz(),
                                p_ship->second.get_xz().distance_to(center));
        }
      }
    }
  }

  if( (find_what&FIND_PLANETS) ) {
    for(auto &id_planet : planets) {
      Vector2 xz=id_planet.second.get_xz();
      real_t dist = xz.distance_to(center);
      if(dist<id_planet.second.get_radius()+radius)
        return CelestialHit(&id_planet.second,xz,dist);
    }
  }

  if( (find_what&FIND_ASTEROIDS) ) {
    for(auto &field : asteroid_fields) {
      CelestialHit hit = field.first_in_circle(center,radius);
      if(hit.hit)
        return hit;
    }
  }

  return CelestialHit();
}

/**********************************************************************/

CelestialHit CombatEngine::first_at_point(Vector2 point,faction_mask_t collision_mask,int find_what) {
  if(!collision_mask)
    return CelestialHit();
  
  if( (find_what&FIND_MISSILES) ) {
    objects_found.clear();
    if(missile_locations.overlapping_point(point,objects_found))
      for(auto &id : objects_found) {
        Projectile *proj = projectile_with_id(id);
        if( (proj->get_faction_mask()&collision_mask) and proj->is_alive() and proj->is_missile())
          return CelestialHit(proj,proj->get_xz(),proj->get_xz().distance_to(point));
      }
  }

  if( (find_what&FIND_SHIPS) ) {
    objects_found.clear();
    if(ship_locations.rect_is_nonempty(Rect2(point-Vector2(0.5,0.5),point+Vector2(1,1)))) {
      Array hits = space->intersect_point(Vector3(point.x,ship_height,point.y),10,Array(),collision_mask,true,false);
      for(int i=0,size=hits.size();i<size;i++) {
        Dictionary hit=hits[i];
        if(!hit.empty()) {
          ships_iter p_ship = ship_for_rid(static_cast<RID>(hit["rid"]).get_id());
          if(p_ship!=ships.end())
            return CelestialHit(&p_ship->second,p_ship->second.get_xz(),
                                p_ship->second.get_xz().distance_to(point));
        }
      }
    }
  }
  
  if( (find_what&FIND_PLANETS) ) {
    for(auto &id_planet : planets) {
      Vector2 xz=id_planet.second.get_xz();
      real_t dist = xz.distance_to(point);
      if(dist<id_planet.second.get_radius())
        return CelestialHit(&id_planet.second,xz,dist);
    }
  }
  
  if( (find_what&FIND_ASTEROIDS) ) {
    for(auto &field : asteroid_fields) {
      CelestialHit hit = field.first_at_point(point);
      if(hit.hit)
        return hit;
    }
  }

  return CelestialHit();
}

/**********************************************************************/

CelestialHit CombatEngine::cast_ray(Vector2 start,Vector2 end,faction_mask_t collision_mask,int find_what) {
  if(!collision_mask)
    return CelestialHit();
  
  CelestialHit closest;
  
  if( (find_what&FIND_MISSILES) ) {
    Vector2 along=(end-start).normalized();
    Vector2 across(-along.y,along.x);
    objects_found.clear();
    if(missile_locations.overlapping_circle((start+end)*0.5f,start.distance_to(end)*0.5f+0.5f,objects_found))
      for(auto &id : objects_found) {
        Projectile *proj = projectile_with_id(id);
        if( (proj->get_faction_mask()&collision_mask) and proj->is_alive() and proj->is_missile()) {
          Vector2 xz=proj->get_xz();
          Vector2 to_proj=xz-start;
          real_t dist=to_proj.dot(along);
          real_t pretend_radius=0.25f;
          if(dist<closest.distance
             and to_proj.dot(across)<pretend_radius) {
            closest = CelestialHit(proj,xz,dist);
            if(closest.distance<pretend_radius)
              // We started "on top of" the missile
              return closest;
          }
        }
      }
  }
  
  if( (find_what&FIND_SHIPS) ) {
    Vector2 center = (start+end)*0.5f;
    real_t radius = start.distance_to(end)*0.5f;
    
    if(ship_locations.circle_is_nonempty(center,radius+1)) {
      // Does the ray start inside a ship?
      Array a=space->intersect_point(to_xyz(start,ship_height),1,empty_array,collision_mask);
      if(a.size()) {
        Dictionary d=a[0];
        rid2id_iter there=rid2id.find(static_cast<RID>(d["rid"]).get_id());
        if(there!=rid2id.end()) {
          Ship *ship=ship_with_id(there->second);
          if(ship) {
            // Projectile starts inside the ship.
            return CelestialHit(ship,start,0);
          }
        }
      }

      // Does the ray hit a ship?
      Dictionary d=space->intersect_ray(to_xyz(start,ship_height),to_xyz(end,ship_height),empty_array,collision_mask);
      rid2id_iter there=rid2id.find(static_cast<RID>(d["rid"]).get_id());
      if(there!=rid2id.end()) {
        Ship *ship=ship_with_id(there->second);
        if(ship) {
          Vector3 hit_location = static_cast<Vector3>(d["position"]);
          Vector2 hit_xz = to_xz(hit_location);
          real_t dist=start.distance_to(hit_xz);
          if(dist<closest.distance)
            closest = CelestialHit(ship,hit_xz,dist);
        }
      }
    }
  }

  if( (find_what&FIND_PLANETS) ) {
    for(auto &id_planet : planets) {
      // WARNING: UNTESTED!
      Planet &planet = id_planet.second;

      // Does the ray start inside a planet?
      real_t sdistsq=(start-planet.get_xz()).length_squared();
      real_t edistsq=(end-planet.get_xz()).length_squared();
      real_t radsq = planet.get_radius();
      radsq*=radsq;
      if(sdistsq<radsq and edistsq<radsq)
        return CelestialHit(&planet,start,0);

      // Does the ray intersect a planet?
      Vector2 segment[2] = { start,end };
      Vector2 intersection[2];
      real_t distances[2];
      int intersections=line_segment_intersect_circle(planet.get_radius(),segment,intersection,distances);
      if(intersections and distances[0]<closest.distance)
        closest=CelestialHit(&planet,intersection[0],distances[0]);
    }
  }

  if( (find_what&FIND_ASTEROIDS) ) {
    for(auto &field : asteroid_fields) {
      CelestialHit hit=field.cast_ray(start,end);
      if(!hit.distance)
        return hit;
      if(hit.distance<closest.distance)
        closest=hit;
    }
  }
  
  return closest;
}
  
Ship *CombatEngine::space_intersect_ray_p_ship(Vector3 point1,Vector3 point2,faction_mask_t mask) {
  FAST_PROFILING_FUNCTION;

  Vector3 center = (point1+point2)/2;
  real_t radius = distance2(point1,point2)/2;

  if(not ship_locations.circle_is_nonempty(Vector2(center.x,center.z),radius+1))
    // No possibility of any matches.
    return nullptr;
  
  // if(not ship_locations.ray_is_nonempty(Vector2(point1.x,point1.z),
  //                                       Vector2(point2.x,point2.z)))
  //   // No possibility of any matches.
  //   return nullptr;
  
  static Array empty;
  Dictionary d=space->intersect_ray(point1,point2,empty,mask);
  rid2id_iter there=rid2id.find(static_cast<RID>(d["rid"]).get_id());
  if(there==rid2id.end())
    return nullptr;
  return ship_with_id(there->second);
}

void CombatEngine::add_salvaged_items(Ship &ship,const String &product_name,int count,real_t unit_mass) {
  salvaged_items.push_back(Dictionary::make("ship_name",ship.name,"product_name",product_name,
                                            "count",count,
                                            "unit_mass",unit_mass));
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
    object_id mesh_id = it.second.get_mesh_id();
    if(next->mesh_paths.find(mesh_id)==next->mesh_paths.end()) {
      String mesh_path = multimeshes.get_mesh_path(mesh_id);
      if(mesh_path.empty() and mesh_id<=0)
        Godot::print_warning("Mesh "+str(mesh_id)+" has no mesh path.",__FUNCTION__,__FILE__,__LINE__);
      else
        next->mesh_paths.emplace(mesh_id,mesh_path);
    }
  }

  add_asteroid_content(*next);

  // Prepend to linked list:
  content.push_content(next);
}
