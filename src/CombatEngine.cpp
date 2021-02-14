#include <cstdint>
#include <cmath>
#include <limits>

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

Dictionary space_intersect_ray(PhysicsDirectSpaceState *space,Vector3 point1,Vector3 point2,int mask) {
  FAST_PROFILING_FUNCTION;
  static Array empty = Array();
  return space->intersect_ray(point1,point2,empty,mask);
}

CombatEngine::CombatEngine():
  visual_effects(),
  search_cylinder(CylinderShape::_new()),
  physics_server(PhysicsServer::get_singleton()),
  space(nullptr),
  
  rid2id(),
  planets(),
  ships(),
  projectiles(),
  player_orders(),
  path2mesh(),
  mesh2path(),
  weapon_rotations(),
  dead_ships(),
  last_id(0),
  delta(1.0/60),
  player_ship_id(-1),
  
  update_request_id(),
  
  loader(ResourceLoader::get_singleton()),
  visual_server(VisualServer::get_singleton()),
  v_meshes(),
  v_path2id(),
  v_invalid_paths(),
  v_delta(0),
  v_camera_location(FAR,FAR,FAR),
  v_camera_size(BIG,BIG,BIG),
  v_tick(0),
  scenario(),
  canvas(),
  reset_scenario(false),

  instance_locations(),
  need_new_meshes(),
  
  new_content(nullptr),
  visible_content(nullptr)

{
  const int max_meshes=50;
  const int max_ships=700;
  const int max_planets=300;
  
  search_cylinder->set_radius(search_cylinder_radius);
  search_cylinder->set_height(30);

  update_request_id.reserve(max_ships/10);
  instance_locations.reserve(max_ships*60);
  need_new_meshes.reserve(max_meshes);
  rid2id.reserve(max_ships*10+max_planets);
  planets.reserve(max_planets);
  ships.reserve(max_ships);
  projectiles.reserve(max_ships*50);
  player_orders.reserve(50);
  path2mesh.reserve(max_meshes);
  mesh2path.reserve(max_meshes);

  dead_ships.reserve(max_ships/2);

  v_meshes.reserve(max_meshes);
  v_path2id.reserve(max_meshes);
  v_invalid_paths.reserve(max_meshes);
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
  register_method("ai_step", &CombatEngine::ai_step);
}

void CombatEngine::_init() {}

/**********************************************************************/

/* Registered Methods */

/**********************************************************************/

void CombatEngine::clear_visuals() {
  // NOTE: entry point from gdscript
  clear_all_multimeshes();
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

  // Wipe out all visual content.
  VisibleContent *content=new_content;
  new_content=nullptr;
  visible_content=nullptr;
  while(content) {
    VisibleContent *next=content->next;
    delete content;
    content=next;
  }
}

void CombatEngine::set_visual_effects(Ref<VisualEffects> visual_effects) {
  this->visual_effects = visual_effects;
}


Array CombatEngine::ai_step(real_t new_delta,Array new_ships,Array new_planets,
                            Array new_player_orders,RID player_ship_rid,
                            PhysicsDirectSpaceState *new_space,
                            Array update_request_rid) {
  FAST_PROFILING_FUNCTION;

  delta = new_delta;
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
  
  // Physics space may be deleted outside of the combat engine due to
  // a scene change, so do not retain the pointer.
  space=nullptr;

  // Pass the visible objects over to the visual thread for display.
  add_content();

  Array result;
  update_ship_list(update_request_rid,result);
  result.push_back(weapon_rotations);
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
  v_tick++;

  // Location is center of camera view and size is the world-space
  // distance from x=left-right z=top-bottom. Y values are ignored.
  
  if(!new_content) {
    // Nothing to display yet.
    // Godot::print_warning("Null new_content pointer.",__FUNCTION__,__FILE__,__LINE__);
    clear_all_multimeshes();
    return;
  }

  if(not scenario.is_valid()) {
    // Nowhere to display anything
    Godot::print_error("Scenario has invalid id",__FUNCTION__,__FILE__,__LINE__);
    clear_all_multimeshes();
    return;
  }
  
  if(new_content==visible_content)
    // Nothing new to display.
    return;

  visual_server = VisualServer::get_singleton();
  
  visible_content = new_content;
  v_camera_location = location;
  v_camera_size = size;
  
  // Delete content from prior frames, and any content we skipped:
  VisibleContent *delete_list = visible_content->next;
  visible_content->next=nullptr;
  while(delete_list) {
    VisibleContent *delete_me=delete_list;
    delete_list=delete_list->next;
    delete delete_me;
  }

  // Catalog projectiles and make MeshInfos in v_meshes for mesh_ids we don't have yet
  instance_locations.clear();
  need_new_meshes.clear();
  catalog_projectiles(location,size,instance_locations,need_new_meshes);
  for(auto &mesh_id : need_new_meshes) {
    v_meshes_iter mesh_it = v_meshes.find(mesh_id);
    if(mesh_it==v_meshes.end())
      // Should never get here; catalog_projectiles already added the meshinfo
      continue;
    load_mesh(mesh_it->second);
  }

  // Update on-screen projectiles
  for(auto &vit : v_meshes) {
    MeshInfo &mesh_info = vit.second;
    int count = instance_locations.count(vit.first);
    
    if(!count) {
      unused_multimesh(mesh_info);
      continue;
    }

    pair<instlocs_iterator,instlocs_iterator> instances =
      instance_locations.equal_range(vit.first);

    mesh_info.last_tick_used=v_tick;

    // Make sure we have a multimesh with enough space
    if(!allocate_multimesh(mesh_info,count))
      continue;

    // Make sure we have a visual instance
    if(!update_visual_instance(mesh_info))
      continue;
    
    pack_projectiles(instances,mesh_info.floats,mesh_info,projectile_scale);
    
    // Send the instance data.
    visual_server->multimesh_set_visible_instances(mesh_info.multimesh_rid,count);
    mesh_info.visible_instance_count = count;
    visual_server->multimesh_set_as_bulk_array(mesh_info.multimesh_rid,mesh_info.floats);
  }
}


void CombatEngine::draw_minimap_contents(RID new_canvas,
                                         Vector2 map_center, real_t map_radius,
                                         Vector2 minimap_center, real_t minimap_radius) {
  FAST_PROFILING_FUNCTION;
  //NOTE: entry point from gdscript
  canvas=new_canvas;

  if(!visible_content)
    return; // Nothing to display yet.
  
  // Draw ships and planets.
  for(auto &object : visible_content->ships_and_planets) {
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
  const Color &color = projectile_color;
  for(auto &projectile : visible_content->projectiles) {
    Vector2 minimap_scaled = (Vector2(projectile.center.y,-projectile.center.x)-map_center) /
      map_radius*minimap_radius;
    if(minimap_scaled.length_squared() > outside_squared)
      continue;
    visual_server->canvas_item_add_circle(canvas,minimap_center+minimap_scaled,1,projectile_color);
  }
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
    } else {
      ai_step_ship(ship);
      negate_drag_force(ship);
      if(ship.updated_mass_stats)
        ship.update_stats(physics_server,true);
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
    if(not ship.update_from_physics_server(physics_server))
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
      result.append(planet.update_status(ships,planets));
  }
}

void CombatEngine::add_ships_and_planets(const Array &new_ships,const Array &new_planets) {
  FAST_PROFILING_FUNCTION;
  
  // Add new planets
  for(int i=0,size=new_planets.size();i<size;i++) {
    Dictionary planet = static_cast<Dictionary>(new_planets[i]);
    object_id id = last_id++;
    pair<planets_iter,bool> pp_planet = planets.emplace(id, Planet(planet,id));
    rid2id[pp_planet.first->second.rid.get_id()] = id;
  }

  // Add new ships
  for(int i=0,size=new_ships.size();i<size;i++) {
    Dictionary ship = static_cast<Dictionary>(new_ships[i]);
    object_id id = last_id++;
    Ship new_ship = Ship(ship,id,last_id,mesh2path,path2mesh);
    pair<ships_iter,bool> pp_ship = ships.emplace(id,new_ship);
    rid2id[pp_ship.first->second.rid.get_id()] = id;
    physics_server->body_set_collision_layer(pp_ship.first->second.rid,pp_ship.first->second.collision_layer);
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
  if(ship.immobile or hyperspace and ship.fuel<=0)
    return;
  if(ship.linear_velocity.length_squared()<ship.max_speed*ship.max_speed)
    physics_server->body_add_central_force(ship.rid,-ship.drag_force);
}

void CombatEngine::rift_ai(Ship &ship) {
  if(ship.tick_at_rift_start>=0 and ship.tick_at_rift_start+SPATIAL_RIFT_LIFETIME_TICKS<=ship.tick) {
    // If the ship has already opened the rift, and survived the minimum duration,
    // it can vanish into the rift.
    ship.fate = FATED_TO_RIFT;
    return;
  }

  if(ship.tick_at_rift_start<0 and request_stop(ship,Vector3(0,0,0),1.0f)) {
    // Once the ship is stopped, paralyze it and open a rift.
    ship.immobile = true;
    ship.inactive = true;
    ship.tick_at_rift_start = ship.tick;
    if(visual_effects.is_valid()) {
      Vector3 rift_position = ship.position;
      rift_position.y = ship.visual_height+1.1f;
      visual_effects->add_zap_pattern(SPATIAL_RIFT_LIFETIME_SECS,rift_position,ship.radius*2.0f,true);
      visual_effects->add_zap_ball(SPATIAL_RIFT_LIFETIME_SECS*2,rift_position,ship.radius*1.5f,false);
    }
  }

  if(ship.tick_at_rift_start>=0) {
    // During the rift animation, shrink the ship.
    real_t rift_fraction = (ship.tick-ship.tick_at_rift_start)/real_t(SPATIAL_RIFT_LIFETIME_TICKS*2);
    ship.set_scale(rift_fraction);
  }
}

void CombatEngine::explode_ship(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  ship.tick++;
  if(ship.tick>=ship.explosion_tick) {
    ship.fate=FATED_TO_DIE;
    if(ship.explosion_radius>0 and (ship.explosion_damage>0 or ship.explosion_impulse!=0)) {
      Ref<PhysicsShapeQueryParameters> query(PhysicsShapeQueryParameters::_new());
      query->set_shape(search_cylinder);
      Transform trans;
      real_t scale = ship.explosion_radius / search_cylinder_radius;
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
        other.take_damage(ship.explosion_damage*dropoff);
        if(other.immobile)
          continue;
        if(ship.explosion_impulse!=0) {
          Vector3 impulse = ship.explosion_impulse * dropoff *
            (other.position-ship.position).normalized();
          if(impulse.length_squared())
            physics_server->body_apply_central_impulse(other.rid,impulse);
        }
      }
    }
  }
}

void CombatEngine::ai_step_ship(Ship &ship) {
  FAST_PROFILING_FUNCTION;

  // Increment this ship's internal time counters:
  ship.tick++;

  ship.heal(hyperspace,system_fuel_recharge,center_fuel_recharge,delta);

  if(ship.entry_method!=ENTRY_COMPLETE and not init_ship(ship))
    return; // Ship has not yet fully arrived.
  
  if(ship.tick_at_rift_start>=0)
    rift_ai(ship);
  else {
    for(auto &weapon : ship.weapons)
      weapon.firing_countdown = max(static_cast<real_t>(0.0),weapon.firing_countdown-delta);
    player_orders_iter orders_p = player_orders.find(ship.id);
    bool have_orders = orders_p!=player_orders.end();
    if(have_orders) {
      PlayerOverrides &orders = orders_p->second;
      
      if(apply_player_orders(ship,orders))
        return;
      
      if(apply_player_goals(ship,orders))
        return;
      
      return;
    }
    // FIXME: replace this with a real ai  
    attacker_ai(ship);
  }
}

bool CombatEngine::init_ship(Ship &ship) {
  // return false = ship does nothing else this timestep
  if(ship.entry_method == ENTRY_FROM_ORBIT) {
    // Ships entering from orbit start at maximum speed.
    if(ship.max_speed>0 and ship.max_speed<999999)
      set_velocity(ship,ship.heading*ship.max_speed);
    ship.entry_method=ENTRY_COMPLETE;
    return false;
  } else if(ship.entry_method != ENTRY_FROM_RIFT and
            ship.entry_method != ENTRY_FROM_RIFT_STATIONARY) {
    // Invalid entry method; treat it as ENTRY_COMPLETE.
    ship.entry_method=ENTRY_COMPLETE;
    return false;
  }
  if(ship.tick==1) {
    // Ship is arriving via spatial rift. Trigger the animation and start a timer.
    ship.immobile=true;
    ship.inactive=true;
    ship.tick_at_rift_start = ship.tick;
    if(visual_effects.is_valid()) {
      Vector3 rift_position = ship.position;
      rift_position.y = ship.visual_height+1.1f;
      visual_effects->add_zap_pattern(SPATIAL_RIFT_LIFETIME_SECS,rift_position,ship.radius*2.0f,true);
      visual_effects->add_zap_ball(SPATIAL_RIFT_LIFETIME_SECS,rift_position,ship.radius*1.5f,true);
    }
    set_angular_velocity(ship,Vector3(0.0,15.0+ship.rand.randf()*15.0,0.0));
    return false;
  } else if(ship.tick_at_rift_start+SPATIAL_RIFT_LIFETIME_TICKS<=ship.tick) {
    // Rift animation just completed.
    ship.tick_at_rift_start=TICKS_LONG_AGO;
    ship.immobile=false;
    ship.inactive=false;
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
    object_id target=overrides.target_id;
    if(target_selection==PLAYER_TARGET_NOTHING)
      target=-1;
    else if(target_selection==PLAYER_TARGET_PLANET) {
      if(target_nearest)
        target=select_target<false>(target,select_nearest(ship.position),planets);
      else
        target=select_target<true>(target,[] (const planets_const_iter &p) { return true; },planets);
    } else if(target_selection==PLAYER_TARGET_ENEMY or target_selection==PLAYER_TARGET_FRIEND) {
      int mask=0x7fffffff;
      if(target_selection==PLAYER_TARGET_ENEMY)
        mask=ship.enemy_mask;
      else if(target_selection==PLAYER_TARGET_FRIEND)
        mask=ship.collision_layer;
      if(target_nearest)
        target=select_target<false>(target,select_three(select_mask(mask),select_flying(),select_nearest(ship.position)),ships);
      else
        target=select_target<true>(target,select_two(select_mask(mask),select_flying()),ships);
    }
    
    if(target!=overrides.target_id)
      overrides.target_id = ship.target = target;
    else if(target_selection==PLAYER_TARGET_OVERRIDE)
      ship.target = overrides.target_id;
  }

  if(overrides.orders&PLAYER_ORDER_STOP_SHIP) {
    request_stop(ship,Vector3(0,0,0),0);
    thrust = rotation = true;
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
    ships_iter target_ptr = ships.find(ship.target);
    if(!rotation and target_ptr!=ships.end()) {
      bool in_range=false;
      Vector3 aim = aim_forward(ship,target_ptr->second,in_range);
      request_heading(ship,aim);
      rotation=true;
    }
    aim_turrets(ship,target_ptr);
    fire_primary_weapons(ship);
  }

  return thrust or rotation;
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
        ship.target=planet_p->first;
      landing_ai(ship);
      return true;
    }
    case PLAYER_GOAL_COWARD_AI: {
      coward_ai(ship);
      return true;
    }
    case PLAYER_GOAL_INTERCEPT: {
      ships_iter target_p = ships.find(overrides.target_id);
      if(target_p!=ships.end()) {
        ship.target=target_p->first;
        move_to_attack(ship,target_p->second);
      }
      return true;
    }
    case PLAYER_GOAL_RIFT: {
      rift_ai(ship);
      return true;
    }
    }
  return false;
}

void CombatEngine::update_near_objects(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  //FIXME: UPDATE THIS TO FIND ENEMY PROJECTILES
  ship.nearby_objects.clear();
  Ref<PhysicsShapeQueryParameters> query(PhysicsShapeQueryParameters::_new());
  query->set_collision_mask(ship.enemy_mask);
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

ships_iter CombatEngine::update_targetting(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  ships_iter target_ptr = ships.find(ship.target);
  bool pick_new_target = target_ptr==ships.end();
  if(!pick_new_target) {
    //FIXME: REPLACE THIS WITH PROPER TARGET SELECTION LOGIC
    if(target_ptr->second.fate!=FATED_TO_FLY)
      pick_new_target = true;
    else if(ship.tick-ship.tick_at_last_shot>600)
      // After 10 seconds without firing, reevaluate target
      pick_new_target=true;
    else if(ship.tick%1200==0) {
      // After 20 seconds, if ship is out of range, reevaluate target
      real_t target_distance = ship.position.distance_to(target_ptr->second.position);
      pick_new_target = (target_distance > 1.5*ship.range.all);
    }
  }
  
  if(pick_new_target or target_ptr==ships.end()) {
    //FIXME: REPLACE THIS WITH PROPER TARGET SELECTION LOGIC
    object_id found=select_target<false>(-1,select_three(select_mask(ship.enemy_mask),select_flying(),select_nearest(ship.position,200.0f)),ships);
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
    ship.target=target_ptr->first;
    move_to_attack(ship,target_ptr->second);
    aim_turrets(ship,target_ptr);
    auto_fire(ship,target_ptr);
  } else {
    if(not have_target)
      ship.target=-1;
    // FIXME: replace this with faction-level ai:
    if(ship.team==0)
      landing_ai(ship);
    else
      rift_ai(ship);
  }
}

void CombatEngine::landing_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;

  if(ship.fate!=FATED_TO_FLY)
    return;

  planets_iter target = planets.find(ship.target);
  if(target == planets.end()) {
    object_id target_id = select_target<false>(-1,select_nearest(ship.position),planets);
    target = planets.find(target_id);
    ship.target=target_id;
  }
  if(target == planets.end())
    // Nowhere to land!
    patrol_ai(ship);
  else if(move_to_intercept(ship, target->second.radius, 3.0, target->second.position,
                            Vector3(0,0,0), true))
    // Reached planet.
    // FIXME: implement factions, etc.:
    // if(target->second.can_land(ship))
    ship.fate = FATED_TO_LAND;
}

void CombatEngine::coward_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return;
  update_near_objects(ship);
  make_threat_vector(ship,0.5);
  real_t threat_threshold = (ship.armor+ship.shields+ship.structure)*30; // FIXME: improve this
  if(ship.threat_vector.length_squared() > threat_threshold*threat_threshold)
    evade(ship);
  else {
    // When there are no threats, fly away from system center
    Vector3 pos = ship.position;
    Vector3 pos_norm = pos.normalized();
    if(pos_norm.length()<0.99)
      pos_norm = Vector3(1,0,0);
    move_to_intercept(ship, 1, FAR, pos_norm * max(real_t(100.0),pos.length()*2+10),
                      ship.max_speed * pos_norm, false);
  }
}

bool CombatEngine::patrol_ai(Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return false;
  if(ship.position.distance_to(ship.destination)<10)
    ship.randomize_destination();
  move_to_intercept(ship, 5, 1, ship.destination, Vector3(0,0,0), false);
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

void CombatEngine::aim_turrets(Ship &ship,ships_iter &target) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;
  Vector3 ship_pos = ship.position;
  Vector3 ship_vel = ship.linear_velocity;
  real_t ship_rotation = ship.rotation[1];
  Vector3 confusion = ship.confusion;
  real_t max_distsq = ship.range.turrets*1.5*ship.range.turrets*1.5;
  bool got_enemies = false;

  int num_eptrs=0;
  Ship *eptrs[12];
  
  for(auto &weapon : ship.weapons) {
    if(not weapon.is_turret)
      continue; // Not a turret.
    
    real_t travel = weapon.projectile_range;
    if(travel<1e-5)
      continue; // Avoid divide by zero for turrets with no range.

    if(!got_enemies) {
      const ship_hit_list_t &enemies = get_ships_within_turret_range(ship, 1.5);
      bool have_a_target = target!=ships.end();
      
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
    bool opportunistic = false;
    
    Vector3 proj_start = ship_pos + weapon.position.rotated(y_axis,ship_rotation) + confusion;
    Vector3 proj_heading = ship.heading.rotated(y_axis,weapon.rotation.y);
    real_t turret_angular_velocity=0;
    real_t best_score = numeric_limits<real_t>::infinity();
    int best_enemy = -1;

    for(int i=0;i<num_eptrs;i++) {
      Ship &enemy = *eptrs[i];
      if(distsq(enemy.position,ship.position)>max_distsq)
        break;
      Vector3 dp = enemy.position - proj_start;
      Vector3 dv = enemy.linear_velocity;
      if(!weapon.guided)
        dv -= ship_vel;
      real_t t = rendezvous_time(dp, dv, weapon.terminal_velocity);
      if(isnan(t) or t>weapon.projectile_lifetime)  {
        t = max(dp.length()/weapon.terminal_velocity, 2*weapon.projectile_lifetime);
      } else
        dp += dv*t;
      double angle_to_target = angle_diff(dp.normalized(),proj_heading);
      if(angle_to_target>PI)
        angle_to_target-=2*PI;
      real_t desired_angular_velocity = angle_to_target/delta;
      real_t turn_time = fabsf(angle_to_target/weapon.turn_rate);
      
      // Score is adjusted to favor ships that the projectile will strike.
      real_t score = turn_time + (PI/weapon.turn_rate)*t;
      if(score<best_score) {
        best_score=score;
        turret_angular_velocity = clamp(desired_angular_velocity, -weapon.turn_rate, weapon.turn_rate);
      }
    }
    
    if(fabsf(turret_angular_velocity)<=1e-9) {
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
    if(fabsf(turret_angular_velocity)>1e-9) {
      weapon.rotation.y = fmodf(weapon.rotation.y+delta*turret_angular_velocity,2*PI);
      weapon_rotations[weapon.node_path] = weapon.rotation.y;
    }
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
  double limit = 0.8 + 0.2/(1.0+stop_time*stop_time*stop_time*speed_epsilon);
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
      if(request_heading(ship,velocity_norm)<1e-3)
        request_thrust(ship,0,speed/(delta*ship.inverse_mass*ship.reverse_thrust));
      return false;
    }
  }
  if(request_heading(ship,-velocity_norm)<1e-3)
    request_thrust(ship,speed/(delta*ship.inverse_mass*ship.thrust),0);
  return false;
}

double CombatEngine::rendezvous_time(Vector3 target_location,Vector3 target_velocity,
                                     double interception_speed) {
  FAST_PROFILING_FUNCTION;
  double a = double_dot(target_velocity,target_velocity) - interception_speed*interception_speed;
  double b = 2.0 * double_dot(target_location,target_velocity);
  double c = double_dot(target_location,target_location);
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
    if(weapon.firing_countdown>0)
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
  ships_iter target = ships.find(ship.target);
  if(target!=ships.end()) {
    bool in_range=false;
    Vector3 aim = aim_forward(ship,target->second,in_range);
    request_heading(ship,aim);
  }
  fire_primary_weapons(ship);
}

Dictionary CombatEngine::check_target_lock(Ship &target, Vector3 point1, Vector3 point2) {
  FAST_PROFILING_FUNCTION;
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
  if(nearby_enemies_range<desired_range || nearby_enemies_tick + 10 < tick) {
    ship.nearby_enemies_range = desired_range;
    ship.nearby_enemies.clear();
    for(auto &other : ships) {
      if(!(other.second.collision_layer&ship.enemy_mask))
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
  Dictionary result = space_intersect_ray(space,point1,point2,ship.enemy_mask);
  //  Dictionary result = space->intersect_ray(point1, point2, Array(), ship.enemy_mask, true, false);

  Vector3 hit_position=Vector3(0,0,0);
  object_id hit_target=-1;
  
  if(not result.empty()) {
    hit_position = CE::get<Vector3>(result,"position");
    ships_iter hit_ptr = ships.find(rid2id_default(rid2id,CE::get<RID>(result,"rid")));
    if(hit_ptr!=ships.end()) {
      hit_target=hit_ptr->first;
      
      // Direct fire projectiles do damage when launched.
      if(weapon.damage)
        hit_ptr->second.take_damage(weapon.damage);
      if(weapon.impulse and not hit_ptr->second.immobile) {
        Vector3 impulse = weapon.impulse*projectile_heading;
        if(impulse.length_squared())
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
    if(weapon.firing_countdown>0)
      continue;
    
    if(weapon.guided and have_a_target) {
      real_t travel = target->second.position.distance_to(ship.position);
      real_t max_travel = weapon.projectile_range;
      if(travel<max_travel)
        create_projectile(ship,weapon);
      continue;
    }
    if(hit_detected and not weapon.is_turret) {
      // If one non-turret fires, all fire.
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
      Vector3 projectile_velocity = ship.heading.rotated(y_axis,weapon_rotation.y)*projectile_speed;
      Vector3 another1 = p_weapon+p_ship-p_enemy;
      Vector3 v_enemy = eptrs[i]->linear_velocity;
      Vector3 another2 = another1 + projectile_lifetime*(projectile_velocity-v_enemy);
      another1[1]=0;
      another2[1]=0;
      if(bound.intersects_segment(another1,another2)) {
        if(not weapon.direct_fire) {
          hit_detected=true;
          create_projectile(ship,weapon);
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
  if(in_range)
    request_heading(ship,aim);
  else {
    move_to_intercept(ship,0,0,target.position,target.linear_velocity,false);
    return;
  }

  Vector3 dp = target.position - ship.position;
  real_t dotted = dot2(ship.heading,dp.normalized());
	
  // Heuristic; needs improvement
  if(dotted>=0.9 and dot2(ship.linear_velocity,dp)<0 or
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

  if(should_reverse and dp.length()<close) {
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
  real_t new_av=0;
  
  if(dot2(norm_heading,ship.heading)>0) {
    double angle = asin_clamp(cross);
    new_av = copysign(1.0,angle)*min(fabsf(angle)/delta,ship.max_angular_velocity);
  } else
    new_av = cross<0 ? -ship.max_angular_velocity : ship.max_angular_velocity;
  set_angular_velocity(ship,Vector3(0,new_av,0));
  return new_av;
}

void CombatEngine::request_rotation(Ship &ship, real_t rotation_factor) {
  FAST_PROFILING_FUNCTION;
  rotation_factor = clamp(rotation_factor,-1.0f,1.0f);
  set_angular_velocity(ship,Vector3(0,rotation_factor*ship.max_angular_velocity,0));
}

void CombatEngine::request_thrust(Ship &ship, real_t forward, real_t reverse) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile or hyperspace and ship.fuel<=0)
    return;
  real_t ai_thrust = ship.thrust*clamp(forward,0.0f,1.0f) - ship.reverse_thrust*clamp(reverse,0.0f,1.0f);
  Vector3 v_thrust = Vector3(ai_thrust,0,0).rotated(y_axis,ship.rotation.y);
  physics_server->body_add_central_force(ship.rid,v_thrust);
}

void CombatEngine::set_angular_velocity(Ship &ship,const Vector3 &angular_velocity) {
  FAST_PROFILING_FUNCTION;
  // Apply an impulse that gives the ship a new angular velocity.
  physics_server->body_apply_torque_impulse(ship.rid,(angular_velocity-ship.angular_velocity)/ship.inverse_inertia);
  // Update our internal copy of the ship's angular velocity.
  ship.angular_velocity = angular_velocity;
}

void CombatEngine::set_velocity(Ship &ship,const Vector3 &velocity) {
  FAST_PROFILING_FUNCTION;
  // Apply an impulse that gives the ship the new velocity.
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

    if(projectile.direct_fire) {
      // Direct fire projectiles do damage when launched and last only one frame.
      it=projectiles.erase(it);
      //deleteme.push_back(it->first);
      continue;
    }
    
    projectile.age += delta;
    
    if(projectile.guided)
      guide_projectile(projectile);
    
    projectile.position += projectile.linear_velocity*delta;
    projectile.rotation += projectile.angular_velocity*delta;

    bool collided=false;
    if(projectile.detonation_range>1e-5)
      collided = collide_projectile(projectile);
    else
      collided = collide_point_projectile(projectile);
    
    if(collided or projectile.age > projectile.lifetime)
      it=projectiles.erase(it);
    else
      it++;
    //      deleteme.push_back(it->first);
  }
  //  for(auto &it : deleteme)
  //  projectiles.erase(it);
}

void CombatEngine::create_direct_projectile(Ship &ship,Weapon &weapon,Vector3 position,real_t length,Vector3 rotation,object_id target) {
  FAST_PROFILING_FUNCTION;
  if(weapon.firing_countdown>0)
    return;
  ship.tick_at_last_shot=ship.tick;
  weapon.firing_countdown = weapon.firing_delay;
  object_id new_id=last_id++;
  projectiles.emplace(new_id,Projectile(new_id,ship,weapon,position,length,rotation.y,target));
}

void CombatEngine::create_projectile(Ship &ship,Weapon &weapon) {
  FAST_PROFILING_FUNCTION;
  if(weapon.firing_countdown>0)
    return;
  ship.tick_at_last_shot=ship.tick;
  weapon.firing_countdown = weapon.firing_delay;
  object_id new_id=last_id++;
  projectiles.emplace(new_id,Projectile(new_id,ship,weapon));
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
  // FIXME: first pass with a boost r*tree
  if(radius>1e-5) {
    real_t trans_x(projectile.position.x), trans_z(projectile.position.z);
    real_t scale = radius / search_cylinder_radius;
    Ref<PhysicsShapeQueryParameters> query(PhysicsShapeQueryParameters::_new());
    query->set_collision_mask(projectile.collision_mask);
    query->set_shape(search_cylinder);
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
    Vector3 point1(projectile.position.x,500,projectile.position.z);
    Vector3 point2(projectile.position.x,-500,projectile.position.z);
    Dictionary hit = space->intersect_ray(point1, point2, Array(), projectile.collision_mask);
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
  static Array empty;
  Dictionary d=space->intersect_ray(point1,point2,empty,mask);
  rid2id_iter there=rid2id.find(static_cast<RID>(d["rid"]).get_id());
  if(there==rid2id.end())
    return ships.end();
  return ships.find(there->second);
}

bool CombatEngine::collide_point_projectile(Projectile &projectile) {
  FAST_PROFILING_FUNCTION;
  Vector3 point1(projectile.position.x,500,projectile.position.z);
  Vector3 point2(projectile.position.x,-500,projectile.position.z);
  ships_iter p_ship = space_intersect_ray_p_ship(point1,point2,projectile.collision_mask);
  if(p_ship==ships.end())
    return false;
  
  p_ship->second.take_damage(projectile.damage);
  if(projectile.impulse and not p_ship->second.immobile) {
    Vector3 impulse = projectile.impulse*projectile.linear_velocity.normalized();
    if(impulse.length_squared())
      physics_server->body_apply_central_impulse(p_ship->second.rid,impulse);
  }
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
    if(projectile.blast_radius>1e-5) {
      projectile_hit_list_t blasted = find_projectile_collisions(projectile,projectile.blast_radius,max_ships_hit_per_projectile_blast);

      for(auto &blastee : blasted) {
        Ship &ship = blastee.second->second;
        if(ship.fate<=0) {
          real_t distance = max(0.0f,ship.position.distance_to(projectile.position)-ship.radius);
          real_t dropoff = 1.0 - distance/projectile.blast_radius;
          dropoff*=dropoff;
          ship.take_damage(projectile.damage*dropoff);
          if(have_impulse and not ship.immobile) {
            Vector3 impulse = projectile.impulse*dropoff*
              (ship.position-projectile.position).normalized();
            if(impulse.length_squared())
              physics_server->body_apply_central_impulse(ship.rid,impulse);
          }
        }
      }
    } else {
      Ship &ship = closest->second;
      closest->second.take_damage(projectile.damage);
      if(have_impulse and not ship.immobile) {
        Vector3 impulse = projectile.impulse*projectile.linear_velocity.normalized();
        if(impulse.length_squared())
          physics_server->body_apply_central_impulse(ship.rid,impulse);
      }
    }
    return true;
  } else
    return false;
}

void CombatEngine::guide_projectile(Projectile &projectile) {
  FAST_PROFILING_FUNCTION;
  ships_iter target_iter = ships.find(projectile.target);
  if(target_iter == ships.end())
    return; // Nothing to track.

  Ship &target = target_iter->second;
  if(target.fate==FATED_TO_DIE)
    return; // Target is dead.
  real_t max_speed = projectile.max_speed;
  real_t max_angular_velocity = projectile.turn_rate;
  Vector3 dp = target.position - projectile.position;
  Vector3 dp_norm = dp.normalized();
  real_t intercept_time = dp.length()/max_speed;
  Vector3 heading = get_heading(projectile);
  bool is_facing_away = dot2(dp,heading)<0.0;
  real_t want_angular_velocity=0;

  if(projectile.guidance_uses_velocity) { // && intercept_time>0.1) {
    // // Turn towards interception point based on target velocity.
    Vector3 tgt_vel = target.linear_velocity;
    if(dot2(dp_norm,tgt_vel)<0) {
      // Target is moving towards projectile.
      Vector3 normal(dp_norm[2],0,-dp_norm[0]);
      real_t norm_tgt_vel = dot2(normal,tgt_vel);
      real_t len = sqrt(max(0.0f,max_speed*max_speed-norm_tgt_vel*norm_tgt_vel));
      dp = len*dp_norm + norm_tgt_vel*normal;
    } else {
      // Target is moving away from projectile.
      dp += intercept_time*tgt_vel;
      intercept_time = dp.length()/max_speed;
    }
    dp_norm=dp.normalized();
  }
  //    want_angular_velocity = (angle_to_intercept(projectile,target.position,target.linear_velocity).y-projectile.rotation.y)/delta;
//  }

    real_t cross = cross2(heading,dp_norm);
    want_angular_velocity = asin_clamp(cross);
  real_t actual_angular_velocity = clamp(want_angular_velocity,-max_angular_velocity,max_angular_velocity);

  projectile.angular_velocity = Vector3(0,actual_angular_velocity,0);
  velocity_to_heading(projectile);

  //FIXME: put in proper projectile force logic
}

void CombatEngine::velocity_to_heading(Projectile &projectile) {
  FAST_PROFILING_FUNCTION;

  projectile.rotation.y += projectile.angular_velocity.y*delta;
  if(projectile.thrust>0) {
    Vector3 old_vel = projectile.linear_velocity;
    real_t thrust = min(1.0f,projectile.thrust);
    real_t invmass = 1.0f/projectile.mass;
    real_t next_speed = min(projectile.max_speed,old_vel.length() + thrust*invmass*delta);
    projectile.linear_velocity = get_heading(projectile) * next_speed;
  } else
    projectile.linear_velocity = get_heading(projectile) * projectile.max_speed;
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
  object_id player_target_id = (player_it==ships.end()) ? -1 : player_it->second.target;
  
  for(auto &it : ships) {
    Ship &ship = it.second;
    VisibleObject &visual = next->ships_and_planets.emplace_back(ship);
    if(ship.id == player_ship_id)
      visual.flags |= VISIBLE_OBJECT_PLAYER;
    else if(ship.id == player_target_id)
      visual.flags |= VISIBLE_OBJECT_PLAYER_TARGET;
    if(ship.collision_layer&ship.enemy_mask)
      visual.flags |= VISIBLE_OBJECT_HOSTILE;
  }
  for(auto &it : planets) {
    Planet &planet = it.second;
    VisibleObject &visual = next->ships_and_planets.emplace_back(it.second);
    if(planet.id == player_target_id)
      visual.flags |= VISIBLE_OBJECT_PLAYER_TARGET;
  }

  next->projectiles.reserve(projectiles.size());
  for(auto &it : projectiles) {
    next->projectiles.emplace_back(it.second);
    if(next->mesh_paths.find(it.second.mesh_id)==next->mesh_paths.end())
      next->mesh_paths.emplace(it.second.mesh_id,mesh2path[it.second.mesh_id]);
  }
  // Prepend to linked list:
  next->next=new_content;
  new_content=next;
}

void CombatEngine::warn_invalid_mesh(MeshInfo &mesh,const String &why) {
  FAST_PROFILING_FUNCTION;
  if(!mesh.invalid) {
    mesh.invalid=true;
    Godot::print_error(mesh.resource_path+String(": ")+why+String(" Projectile will be invisible."),__FUNCTION__,__FILE__,__LINE__);
  }
}

bool CombatEngine::allocate_multimesh(MeshInfo &mesh_info,int count) {
  FAST_PROFILING_FUNCTION;
  if(not mesh_info.multimesh_rid.is_valid()) {
    mesh_info.multimesh_rid = visual_server->multimesh_create();
    if(not mesh_info.multimesh_rid.is_valid()) {
      // Could not create a multimesh, so do not display the mesh this frame.
      Godot::print_error("Visual server returned an invalid rid when asked for a new multimesh.",__FUNCTION__,__FILE__,__LINE__);
      return false;
    }
    visual_server->multimesh_set_mesh(mesh_info.multimesh_rid,mesh_info.mesh_rid);
    mesh_info.instance_count = max(count,8);
    visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,0);
  }

  if(mesh_info.instance_count < count) {
    mesh_info.instance_count = count*1.3;
    visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,0);
  } else if(mesh_info.instance_count > count*2.6) {
    int new_count = max(static_cast<int>(count*1.3),8);
    if(new_count<mesh_info.instance_count) {
      mesh_info.instance_count = new_count;
      visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,0);
    }
  }

  return true;
}

bool CombatEngine::update_visual_instance(MeshInfo &mesh_info) {
  FAST_PROFILING_FUNCTION;
  if(not mesh_info.visual_rid.is_valid()) {
    mesh_info.visual_rid = visual_server->instance_create2(mesh_info.multimesh_rid,scenario);
    if(not mesh_info.visual_rid.is_valid()) {
      Godot::print_error("Visual server returned an invalid rid when asked for visual instance for a multimesh.",__FUNCTION__,__FILE__,__LINE__);
      // Can't display this frame
      return false;
    }
    visual_server->instance_set_layer_mask(mesh_info.visual_rid,SHIP_LIGHT_LAYER_MASK);
    visual_server->instance_set_visible(mesh_info.visual_rid,true);
  } else if(reset_scenario)
    visual_server->instance_set_scenario(mesh_info.visual_rid,scenario);
  return true;
}

bool CombatEngine::load_mesh(MeshInfo &mesh_info) {
  FAST_PROFILING_FUNCTION;
  if(mesh_info.invalid)
    return false;
  if(loader->exists(mesh_info.resource_path)) {
    mesh_info.mesh_resource=loader->load(mesh_info.resource_path);
    Ref<Resource> mesh=mesh_info.mesh_resource;
    if(mesh_info.mesh_resource.ptr())
      mesh_info.mesh_rid = mesh_info.mesh_resource->get_rid();
    else
      mesh_info.mesh_rid = RID();
    if(not mesh_info.mesh_rid.is_valid()) {
      warn_invalid_mesh(mesh_info,"unable to load resource.");
      return false;
    } else if(!mesh->is_class("Mesh")) {
      warn_invalid_mesh(mesh_info,mesh->get_class()+"is not a Mesh.");
      return false;
    }
  } else {
    warn_invalid_mesh(mesh_info,"no resource at this path.");
    return false;
  }
  return true;
}

void CombatEngine::clear_all_multimeshes() {
  for(auto &it : v_meshes)
    unused_multimesh(it.second);
}

void CombatEngine::unused_multimesh(MeshInfo &mesh_info) {
  FAST_PROFILING_FUNCTION;
  // No instances in this multimesh. Should we delete it?
  if(!mesh_info.visual_rid.is_valid() and !mesh_info.multimesh_rid.is_valid())
    return;
  
  if(v_tick > mesh_info.last_tick_used+1200) {
    if(mesh_info.visual_rid.is_valid())
      visual_server->free_rid(mesh_info.visual_rid);
    if(mesh_info.multimesh_rid.is_valid())
      visual_server->free_rid(mesh_info.multimesh_rid);
    mesh_info.multimesh_rid = RID();
    mesh_info.visual_rid = RID();
  }
  if(mesh_info.multimesh_rid.is_valid()) {
    // Make sure unused multimeshes aren't too large.
    if(mesh_info.instance_count>16) {
      mesh_info.instance_count=8;
      visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,0);
    }
    if(mesh_info.visible_instance_count)
      visual_server->multimesh_set_visible_instances(mesh_info.multimesh_rid,0);
  }
  mesh_info.visible_instance_count=0;
}

void CombatEngine::pack_projectiles(const pair<instlocs_iterator,instlocs_iterator> &projectiles,
                                    PoolRealArray &floats,MeshInfo &mesh_info,real_t projectile_scale) {
  FAST_PROFILING_FUNCTION;
  // Change the float array so it is exactly as large as we need
  floats.resize(mesh_info.instance_count*12);
  int stop = mesh_info.instance_count*12;
  PoolRealArray::Write writer = floats.write();
  real_t *dataptr = writer.ptr();

  real_t scale_z = projectile_scale;
  
  // Fill in the transformations for the projectiles.
  int i=0;
  for(instlocs_iterator p_instance = projectiles.first;
      p_instance!=projectiles.second && i<stop;  p_instance++, i+=12) {
    MeshInstanceInfo &info = p_instance->second;
    real_t scale_x = info.scale_x ? info.scale_x : projectile_scale;
    float cos_ry=cosf(info.rotation_y);
    float sin_ry=sinf(info.rotation_y);
    dataptr[i + 0] = cos_ry*scale_x;
    dataptr[i + 1] = 0.0;
    dataptr[i + 2] = sin_ry*scale_z;
    dataptr[i + 3] = info.x;
    dataptr[i + 4] = 0.0;
    dataptr[i + 5] = 1.0;
    dataptr[i + 6] = 0.0;
    dataptr[i + 7] = PROJECTILE_HEIGHT;
    dataptr[i + 8] = -sin_ry*scale_x;
    dataptr[i + 9] = 0.0;
    dataptr[i + 10] = cos_ry*scale_z;
    dataptr[i + 11] = info.z;
  }
  
  // Use identity transforms for unused instances.
  for(;i<stop;i+=12) {
    dataptr[i + 0] = 1.0;
    dataptr[i + 1] = 0.0;
    dataptr[i + 2] = 0.0;
    dataptr[i + 3] = 0.0;
    dataptr[i + 4] = 0.0;
    dataptr[i + 5] = 1.0;
    dataptr[i + 6] = 0.0;
    dataptr[i + 7] = 0.0;
    dataptr[i + 8] = 0.0;
    dataptr[i + 9] = 0.0;
    dataptr[i + 10] = 1.0;
    dataptr[i + 11] = 0.0;
  }
}

void CombatEngine::catalog_projectiles(const Vector3 &location,const Vector3 &size,
                                       instance_locations_t &instance_locations,
                                       unordered_set<object_id> &need_new_meshes) {
  FAST_PROFILING_FUNCTION;
  real_t loc_min_x = min(location.x-size.x/2,location.x+size.x/2);
  real_t loc_max_x = max(location.x-size.x/2,location.x+size.x/2);
  real_t loc_min_y = min(location.z-size.z/2,location.z+size.z/2);
  real_t loc_max_y = max(location.z-size.z/2,location.z+size.z/2);

  for(auto &projectile : visible_content->projectiles) {
    object_id mesh_id = projectile.mesh_id;

    if(projectile.center.x-projectile.half_size.x > loc_max_x or
       projectile.center.x+projectile.half_size.x < loc_min_x or
       projectile.center.y-projectile.half_size.y > loc_max_y or
       projectile.center.y+projectile.half_size.y < loc_min_y)
      continue; // projectile is off-screen

    MeshInstanceInfo instance_info =
      { projectile.center.x, projectile.center.y, projectile.rotation_y, projectile.scale_x };
    instance_locations.emplace(mesh_id,instance_info);

    v_meshes_iter mit = v_meshes.find(mesh_id);
    if(mit==v_meshes.end()) {
      mesh_paths_iter pit = visible_content->mesh_paths.find(mesh_id);
      
      if(pit==visible_content->mesh_paths.end()) {
        // Should never get here. This means the physics thread
        // generated a projectile without sending its mesh resource path.
        pair<v_meshes_iter,bool> emplaced = v_meshes.emplace(mesh_id,MeshInfo(mesh_id,"(*unspecified resource*)"));
        warn_invalid_mesh(emplaced.first->second,"internal error: no mesh path sent from physics thread.");
        continue;
      }

      v_meshes.emplace(mesh_id,MeshInfo(mesh_id,pit->second));
      need_new_meshes.insert(mesh_id);
    }
  }
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
