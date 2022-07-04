#include "CE/BaseShipAI.hpp"
#include "CE/Planet.hpp"
#include "CE/Ship.hpp"
#include "CE/Projectile.hpp"
#include "CE/CombatEngine.hpp"
#include "FastProfilier.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

BaseShipAI::~BaseShipAI() {}
BaseShipAI::BaseShipAI() {}


void BaseShipAI::do_land(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;

  if(ship.fate!=FATED_TO_FLY)
    return;

  Planet * target = ce.planet_with_id(ship.get_target());
  if(!target) {
    object_id target_id = select_target(-1,select_nearest(ship.position),ce.get_planets(),false);
    target = ce.planet_with_id(target_id);
    ship.new_target(target_id);
  }
  if(!target)
    // Nowhere to land!
    do_patrol(ce,ship);
  else if(ship.move_to_intercept(ce,target->radius, 5.0, target->position,
                                 Vector3(0,0,0), true)) {
    // Reached planet.
    // FIXME: implement factions, etc.:
    // if(target->can_land(ship))
    ship.fate = FATED_TO_LAND;
  }
}

bool BaseShipAI::do_patrol(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return false;
  if(distance2(ship.position,ship.destination)<10) {
    ship.randomize_destination();
    if(ship.goal_target>=0) {
      Planet * p_planet = ce.planet_with_id(ship.goal_target);
      if(p_planet)
        ship.destination += p_planet->position;
    }
  }
  ship.move_to_intercept(ce, 5, 1, ship.destination, Vector3(0,0,0), false);
  return true;
}

bool BaseShipAI::do_salvage(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  Projectile *it = ce.projectile_with_id(ship.salvage_target);
  if(!it)
    return false;

  Vector3 ship_position=get_position(ship);
  Vector3 proj_position=get_position(*it);
  Vector3 dp = proj_position-ship_position;
  pair<DVector3,double> course=plot_collision_course(dp,it->linear_velocity,ship.max_speed);
  Vector3 correction = course.first-ship.linear_velocity;
  Vector3 desired_heading=correction.normalized();
  
  //ship.move_to_intercept(ship.cargo_web_radius/4,.01,proj_position,it->linear_velocity,false);
  ship.request_heading(ce,desired_heading);
  real_t dot = dot2(ship.heading,desired_heading);
  ship.request_thrust(ce,dot>0.95,dot<-0.95);
  
  if(dp.length_squared()<ship.cargo_web_radiussq) {
    ship.activate_cargo_web(ce);
    use_cargo_web(ce,ship);
  } else if(ship.cargo_web_active)
    ship.deactivate_cargo_web(ce);

  opportunistic_firing(ce,ship);

  return true;
}

void BaseShipAI::do_evade(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  Vector3 reaction_vector=-ship.threat_vector.normalized();
  if(reaction_vector.length_squared()<1e-5) {
    ship.set_angular_velocity(ce,Vector3(0,0,0));
    ship.request_thrust(ce,1,0);
    return;
  }
  real_t dot = dot2(reaction_vector,ship.heading);
  
  ship.request_thrust(ce,real_t(dot>=0),real_t(dot<0));
  ship.request_heading(ce,reaction_vector);
}

bool BaseShipAI::do_rift(CombatEngine &ce,Ship &ship) {
  ship.deactivate_cargo_web(ce);
  FAST_PROFILING_FUNCTION;
  if(ship.rift_timer.alarmed()) {
    // If the ship has already opened the rift, and survived the minimum duration,
    // it can vanish into the rift.
    ship.fate = FATED_TO_RIFT;
  } else if(not ship.rift_timer.active()) {
    if(ship.request_stop(ce,Vector3(0,0,0),3.0f)) {
      // Once the ship is stopped, paralyze it and open a rift.
      ship.immobile = true;
      ship.inactive = true;
      ship.damage_multiplier = ship.rifting_damage_multiplier;
      ship.rift_timer.reset();
      if(ce.get_visual_effects().is_valid()) {
        Vector3 rift_position = ship.position;
        rift_position.y = ship.visual_height+1.1f;
        ce.get_visual_effects()->add_hyperspacing_polygon(SPATIAL_RIFT_LIFETIME_SECS*2,rift_position,ship.radius*1.5f,false,ship.id);
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

bool BaseShipAI::should_salvage(CombatEngine &ce,Ship &ship,real_t *returned_best_time) {
  FAST_PROFILING_FUNCTION;

  if(returned_best_time)
    *returned_best_time = numeric_limits<real_t>::infinity();
  
  if(ship.salvage_timer.active() and !ship.salvage_timer.alarmed())
    return false; 

  ship.salvage_timer.reset();

  real_t max_move = ship.max_speed*(SALVAGE_TIME_LIMIT-PI/ship.max_angular_velocity);
  if(max_move<0)
    return false;

  std::unordered_set<object_id> &objects_found = ce.get_objects_found();
  objects_found.clear();
  size_t count = ce.get_flotsam_locations().overlapping_circle(Vector2(ship.position.x,ship.position.z),
                                                               min(50.0f,max_move),objects_found);
  if(!count) {
    return false;
  }

  DVector3 ship_position = get_position_d(ship);
  object_id best_id=-1;
  real_t best_time=numeric_limits<real_t>::infinity();
  
  for(auto &id : objects_found) {
    const Projectile *it = ce.projectile_with_id(id);
    if(!it) {
      //Godot::print(ship.name+": projectile "+str(id)+" does not exist.");
      continue;
    }
    DVector3 dp = get_position(*it)-ship_position;
    pair<DVector3,double> course = plot_collision_course(dp,it->linear_velocity,ship.max_speed);
    real_t life_remaining = it->lifetime-it->age;
    if(course.second>life_remaining)
      continue;
    if(course.second<best_time) {
      best_time=course.second;
      best_id=id;
    }
  }
  if(isfinite(best_time)) {
    ship.salvage_target=best_id;
    if(returned_best_time)
      *returned_best_time=best_time;
    return true;
  }
  return false;
}

void BaseShipAI::fire_antimissile_turrets(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(not ship.range.antimissile)
    return; // Ship has no anti-missile systems.

  faction_mask_t enemy_mask = ce.get_enemy_mask(ship.faction);
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
  std::unordered_set<object_id> &objects_found = ce.get_objects_found();
  objects_found.clear();
  if(not ce.get_missile_locations().overlapping_circle(center,range,objects_found))
    return; // No projectiles in range

  // Delete any projectiles that are not viable targets.
  for(auto iter=objects_found.begin();iter!=objects_found.end();) {
    object_id id = *iter;
    Projectile *proj_it = ce.projectile_with_id(id);
    if(!proj_it) {
      iter = objects_found.erase(iter);
      Godot::print_warning("Found projectile "+str(id)+" in missile_locations that is not in projectiles hash",
                           __FUNCTION__,__FILE__,__LINE__);
      continue; // Projectile does not exist.
    }
    Projectile &proj = *proj_it;
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
      Projectile * best = nullptr;
      real_t best_score = -numeric_limits<real_t>::infinity();
      for(auto &id : objects_found) {
        Projectile * proj_it = ce.projectile_with_id(id);
        Projectile &proj = *proj_it;
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
      
      if(best) {
        Vector3 dp = best->position-start;
        real_t dp_angle = angle_from_unit(dp);
        real_t rotation = dp_angle-ship.rotation.y;

        weapon.rotation.y = fmodf(rotation,2*PI);
        ce.set_weapon_rotation(weapon.node_path,weapon.rotation.y);

        Vector3 hit_position = best->position;
        Vector3 point1 = start;
        Vector3 projectile_position = (point1+hit_position)*0.5;
        real_t projectile_length = (hit_position-point1).length();
        real_t projectile_rotation = weapon.rotation.y+ship.rotation.y;
        
        ce.create_antimissile_projectile(ship,weapon,*best,projectile_position,projectile_length,projectile_rotation);
        best->take_damage(weapon.damage);
        if(not best->alive)
          objects_found.erase(best->id);
      }
    }
  } // end weapons loop
}

void BaseShipAI::use_cargo_web(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  Rect2 cargo_web_rect = rect_for_circle(ship.position,ship.cargo_web_radius);
  std::unordered_set<object_id> &objects_found = ce.get_objects_found();
  objects_found.clear();
  ce.get_flotsam_locations().overlapping_rect(cargo_web_rect,objects_found);
  real_t thrust=ship.cargo_web_strength;
  for(auto &id : objects_found) {
    Projectile * proj_ptr = ce.projectile_with_id(id);
    if(proj_ptr) {
      Projectile &proj = *proj_ptr;
      
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

      if(ship.rand.randf()<30*ce.get_delta()) {
        Vector3 ship_position(ship.position.x,ship.visual_height,ship.position.z);
        Vector3 puff_velocity = (ship.rand.randf()*0.1 + 0.3)*(collision_course.first);
        Vector3 random_perturbation = Vector3((ship.rand.randf()-1)/2,ship.rand.randf()/10,(ship.rand.randf()-1)/2);
        Vector3 puff_location = Vector3(proj.position.x,-1,proj.position.z)+random_perturbation;
        real_t duration = isnan(collision_course.second) ? .4f : collision_course.second;
        duration*=3.5;
        ce.get_visual_effects()->add_cargo_web_puff_MMIEffect(ship,puff_location,puff_velocity,1,duration,ship.cargo_puff_mesh);
      }
    }
  }
}

void BaseShipAI::opportunistic_firing(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  // Take shots when you can, without turning the ship to aim.
  aim_turrets(ce,ship,nullptr);
  if(ship.efficiency>0.9)
    auto_fire(ce,ship,nullptr);
  fire_antimissile_turrets(ce,ship);
}

Vector3 BaseShipAI::make_threat_vector(CombatEngine &ce,Ship &ship, real_t t) {
  FAST_PROFILING_FUNCTION;
  //FIXME: UPDATE THIS TO INCLUDE PROJECTILES
  Vector3 my_position = ship.position + t*ship.linear_velocity;
  Vector2 threat_vector;
  real_t dw_div = 0;
  int checked=0;
  for(auto &rid_id : ship.nearby_objects) {
    Ship * object_iter = ce.ship_with_id(rid_id.second);
    if(!object_iter)
      continue;
    Ship &object = *object_iter;
    Vector3 obj_pos = object.position + t*object.linear_velocity;
    Vector2 position(obj_pos[0] - my_position[0], obj_pos[2] - my_position[2]);
    real_t distance = position.length();
    real_t distance_weight = max(0.0f,(ce.search_cylinder_radius-distance)/ce.search_cylinder_radius);
    real_t weight = distance_weight*object.threat;
    dw_div += distance_weight;
    threat_vector += weight * position.normalized();
    checked++;
  }
  Vector3 result = Vector3(threat_vector[0],0,threat_vector[1])/max(1.0f,dw_div);
  ship.threat_vector=result;
  return result;
}


void BaseShipAI::aim_turrets(CombatEngine &ce,Ship &ship,Ship *target) {
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
      const ship_hit_list_t &enemies = ce.get_ships_within_turret_range(ship, 1.5);
      have_a_target = !!target;
      
      if(have_a_target) {
        real_t dp=distance2(target->position,ship.position);
        have_a_target = dp*dp<max_distsq and have_a_target;
        eptrs[num_eptrs++] = target;
      }
      for(auto it=enemies.begin();it<enemies.end() && num_eptrs<11;it++) {
        Ship *enemy_iter = ce.ship_with_id(it->second);
        if(!enemy_iter)
          continue;
        if(distsq(enemy_iter->position,ship.position)>max_distsq)
          break;
        eptrs[num_eptrs++] = enemy_iter;
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
    const real_t delta = ce.get_delta();      
    
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
    ce.set_weapon_rotation(weapon.node_path, weapon.rotation.y);
  }
}

void BaseShipAI::fire_primary_weapons(CombatEngine &ce,Ship &ship) {
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
      fire_direct_weapon(ce,ship,weapon,true);
    else
      ce.create_projectile(ship,weapon);
  }
}


bool BaseShipAI::fire_direct_weapon(CombatEngine &ce,Ship &ship,Weapon &weapon,bool allow_untargeted) {
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
  Dictionary result = ce.space_intersect_ray(ce.get_space_state(),point1,point2,ce.get_enemy_mask(ship.faction));
  const real_t delta = ce.get_delta();      

  Vector3 hit_position=Vector3(0,0,0);
  object_id hit_target=-1;
  
  if(not result.empty()) {
    hit_position = get<Vector3>(result,"position");
    Ship * hit_ptr = ce.ship_with_id(rid2id_default(ce.get_rid2id(),get<RID>(result,"rid")));
    if(hit_ptr) {
      hit_target=hit_ptr->id;
      // Direct fire projectiles do damage when launched.
      if(weapon.damage)
        hit_ptr->take_damage(weapon.damage*delta*ship.efficiency,weapon.damage_type,
                             weapon.heat_fraction,weapon.energy_fraction,weapon.thrust_fraction);
      if(not hit_ptr->immobile and weapon.impulse) {
        Vector3 impulse = weapon.impulse*projectile_heading*delta*ship.efficiency;
        PhysicsServer::get_singleton()->body_apply_central_impulse(hit_ptr->rid,impulse);
      }
      if(not hit_position.length_squared())
        hit_position = hit_ptr->position;
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
  ce.create_direct_projectile(ship,weapon,projectile_position,projectile_length,
                              Vector3(0,weapon_rotation,0),hit_target);
  return true;
}

void BaseShipAI::auto_fire(CombatEngine &ce,Ship &ship,Ship *target) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;
  const ship_hit_list_t &enemies = ce.get_ships_within_weapon_range(ship,1.5);
  Vector3 p_ship = ship.position;
  real_t max_distsq = ship.range.all;

  Ship *eptrs[12];
  int num_eptrs=0;
  bool have_a_target = !!target;
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
        real_t travel_squared = target->position.distance_squared_to(ship.position);
        if(travel_squared<max_travel_squared) {
          ce.create_projectile(ship,weapon,target->id);
          continue;
        }
      }
    } else if(hit_detected and not weapon.is_turret) {
      // If one non-turret non-guided weapon fires, all fire.
      if(weapon.direct_fire)
        fire_direct_weapon(ce,ship,weapon,false);
      else
        ce.create_projectile(ship,weapon);
      continue;
    }
    if(not have_enemies) {  
      AABB bound;
      if(have_a_target) {
        eptrs[num_eptrs++] = target;
        ships_in_range = (distsq(target->position,ship.position) <= max_distsq);
      }
      for(auto it=enemies.begin();it<enemies.end() && num_eptrs<11;it++) {
        Ship *enemy_iter = ce.ship_with_id(it->second);
        if(!enemy_iter)
          continue;
        if(distsq(enemy_iter->position,ship.position)>max_distsq)
          break;
        eptrs[num_eptrs++] = enemy_iter;
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
          ce.create_projectile(ship,weapon,eptrs[i]->id);
          break;
        } else if(fire_direct_weapon(ce,ship,weapon,false)) {
          hit_detected=true;
          break;
        }
      }
    }
  }
}

Ship *BaseShipAI::update_targetting(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  Ship *target_ptr = ce.ship_with_id(ship.get_target());
  bool pick_new_target = !target_ptr || 
    ship.should_update_targetting(*target_ptr);
  
  if(pick_new_target) {
    //FIXME: REPLACE THIS WITH PROPER TARGET SELECTION LOGIC
    object_id found=select_target(-1,select_three(select_mask(ce.get_enemy_mask(ship.faction)),select_flying(),select_nearest(ship.position,200.0f)),ce.get_ships(),false);
    target_ptr = ce.ship_with_id(found);
  }
  return target_ptr;
}

void BaseShipAI::ai_step(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;

  ship.heal(ce);
  ship.apply_heat_and_energy_costs(ce);

  if(ship.at_first_tick) {
    Faction *faction_it = ce.faction_with_id(ship.faction);
    if(faction_it) {
      ship.shield_ellipse = ce.get_visual_effects()->
        add_shield_ellipse(ship,ship.aabb,0.1,0.35,faction_it->get_faction_color());
    } else
      Godot::print_warning(ship.name+": has no faction",__FUNCTION__,__FILE__,__LINE__);
  }

  if(ship.entry_method!=ENTRY_COMPLETE and not ship.init_ship(ce)) {
    ship.negate_drag_force(ce);
    return; // Ship has not yet fully arrived.
  }
  
  for(auto &weapon : ship.weapons)
    weapon.reload(ship,ce.get_idelta());
  
  if(ship.rift_timer.active())
    do_rift(ce,ship);
  else {
    PlayerOverrides *orders_p = ce.player_order_with_id(ship.id);
    bool have_orders = orders_p;
    if(have_orders) {
      PlayerOverrides &orders = *orders_p;
      if(not apply_player_orders(ce,ship,orders))
        apply_player_goals(ce,ship,orders);
    } else
      run_ai(ce,ship);
    /*
      switch(ship.ai_type) {
      case PATROL_SHIP_AI: patrol_ship_ai(ship); return;
      case RAIDER_AI: raider_ai(ship); return;
      case ARRIVING_MERCHANT_AI: arriving_merchant_ai(ship); return;
      case DEPARTING_MERCHANT_AI: departing_merchant_ai(ship); return;
      default: attacker_ai(ship); return;
      }
    */
    if(ship.confusion_timer.alarmed()) {
      ship.update_confusion();
      ship.confusion_timer.reset();
    }
  }
  
  if(ship.cargo_web_active)
    use_cargo_web(ce,ship);

  ship.negate_drag_force(ce);
}


void BaseShipAI::run_ai(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;
  Ship * target_ptr = update_targetting(ce,ship);
  bool have_target = !!target_ptr;
  bool close_to_target = have_target and distance2(target_ptr->position,ship.position)<100;
  
  if(close_to_target) {
    ship.new_target(target_ptr->id);
    ship.move_to_attack(ce,*target_ptr);
    aim_turrets(ce,ship,target_ptr);
    auto_fire(ce,ship,target_ptr);
  } else {
    if(not have_target)
      ship.clear_target();
    // FIXME: replace this with faction-level ai:
    if(ship.faction==ce.get_player_faction_index()) {
      do_land(ce,ship);
      opportunistic_firing(ce,ship);
    } else if(!do_rift(ce,ship))
      opportunistic_firing(ce,ship);
  }
}

bool BaseShipAI::apply_player_orders(CombatEngine &ce,Ship &ship,PlayerOverrides &overrides) {
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
          target=select_target(target,select_nearest(ship.position),ce.get_planets(),false);
        } else {
          target=select_target(target,[] (const planets_const_iter &_p) { return true; },ce.get_planets(),true);
        }
      } else if(target_selection==PLAYER_TARGET_ENEMY or target_selection==PLAYER_TARGET_FRIEND) {
        int mask=0x7fffffff;
        if(target_selection==PLAYER_TARGET_ENEMY) {
          mask=ce.get_enemy_mask(ship.faction);
          //Godot::print("Player targets enemy with mask "+str(mask));
        } else if(target_selection==PLAYER_TARGET_FRIEND) {
          mask=ce.get_friend_mask(ship.faction);
          //Godot::print("Player targets enemy with mask "+str(mask));
        }
        if(target_nearest) {
          target=select_target(target,select_three(select_mask(mask),select_flying(),select_nearest(ship.position)),ce.get_ships(),false);
          //Godot::print("Player targets nearest flying ship to "+str(ship.position));
        } else {
          target=select_target(target,select_two(select_mask(mask),select_flying()),ce.get_ships(),true);
          //Godot::print("Player targets next flying ship");
        }
      }
      
      ship.new_target(target);
      overrides.target_id = target;
    }
  }

  if(overrides.orders&PLAYER_ORDER_AUTO_TARGET)
    ship.should_autotarget = not ship.should_autotarget;
  
  if(overrides.orders&PLAYER_ORDER_STOP_SHIP) {
    ship.request_stop(ce,Vector3(0,0,0),3.0f);
    thrust = rotation = true;
  }

  if(overrides.orders&PLAYER_ORDER_TOGGLE_CARGO_WEB) {
    if(!ship.cargo_web_active)
      ship.activate_cargo_web(ce);
    else
      ship.deactivate_cargo_web(ce);
  }
  
  if(!rotation and fabsf(overrides.manual_rotation)>1e-5) {
    ship.request_rotation(ce,overrides.manual_rotation);
    rotation=true;
  }
   
  if(!thrust and fabsf(overrides.manual_thrust)>1e-5) {
    ship.request_thrust(ce,clamp(overrides.manual_thrust,0.0f,1.0f),
                        clamp(-overrides.manual_thrust,0.0f,1.0f));
    thrust=true;
  }
  
  if(!rotation)
    ship.request_rotation(ce,0);

  if(overrides.orders&PLAYER_ORDER_FIRE_PRIMARIES) {
    Ship * target_ptr = ce.ship_with_id(ship.get_target());
    if(not rotation and ship.should_autotarget and target_ptr) {
      bool in_range=false;
      Vector3 aim = ship.aim_forward(ce,*target_ptr,in_range);
      ship.request_heading(ce,aim);
        rotation=true;
    }
    aim_turrets(ce,ship,target_ptr);
    fire_primary_weapons(ce,ship);
  }
  fire_antimissile_turrets(ce,ship);
  return thrust or rotation;
}

bool BaseShipAI::apply_player_goals(CombatEngine &ce,Ship &ship,PlayerOverrides &overrides) {
  FAST_PROFILING_FUNCTION;
  for(int i=0;i<PLAYER_ORDERS_MAX_GOALS;i++)
    switch(overrides.goals.goal[i]) {
    case PLAYER_GOAL_LANDING_AI: {
      Planet *planet_p = ce.planet_with_id(overrides.target_id);
      if(planet_p)
        ship.new_target(planet_p->id);
      do_land(ce,ship);
      fire_antimissile_turrets(ce,ship);
      return true;
    }
    case PLAYER_GOAL_INTERCEPT: {
      Ship * target_p = ce.ship_with_id(overrides.target_id);
      if(target_p) {
        ship.new_target(target_p->id);
        ship.move_to_attack(ce,*target_p);
      }
      return true;
    }
    case PLAYER_GOAL_RIFT: {
      if(!do_rift(ce,ship))
        fire_antimissile_turrets(ce,ship);
      return true;
    }
    }
  return false;
}

void BaseShipAI::player_auto_target(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile or ship.inactive)
    return;
  Ship * target = ce.ship_with_id(ship.get_target());
  if(target) {
    bool in_range=false;
    Vector3 aim = ship.aim_forward(ce,*target,in_range);
    ship.request_heading(ce,aim);
  }
  fire_primary_weapons(ce,ship);
}

void BaseShipAI::choose_target_by_goal(CombatEngine &ce,Ship &ship,bool prefer_strong_targets,goal_action_t goal_filter,real_t min_weight_to_target,real_t override_distance) const {
  FAST_PROFILING_FUNCTION;

  // Minimum and maximum distances to target for calculations:
  real_t min_move = clamp(max(3.0f*ship.max_speed,ship.range.all),10.0f,30.0f);
  real_t max_move = clamp(20.0f*ship.max_speed+ship.range.all,100.0f,1000.0f);
  real_t move_scale = max(max_move-min_move,1.0f);

  Faction *faction_it = ce.faction_with_id(ship.faction);
  
  int i=0;
  object_id target = -1;
  real_t target_weight = -1.0f;

  for(ships_const_iter it=ce.get_ships().begin();it!=ce.get_ships().end();it++,i++) {
    real_t weight = 0.0f;
    const Ship &other = it->second;
    if(other.id==ship.id or not ce.is_hostile_towards(ship.faction,other.faction))
      // Cannot harm the other ship, so don't target it.
      continue;

    real_t ship_dist = distance2(other.position,ship.position);
    if(ship_dist>max_move and ship_dist>override_distance)
      // Ship is essentially infinitely far away, so ignore it.
      continue;

    weight  = clamp(-ce.affinity_towards(ship.faction,other.faction),0.5f,2.0f);
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

    if(faction_it) {
      real_t all_advice_weight_sq = 0;
      for(auto &advice : faction_it->get_target_advice()) {
        if(advice.action != goal_filter)
          continue; // ship does not contribute to this goal

        // Starting advice weight is goal weight multiplied by a number from 0..1:
        real_t advice_weight = advice.target_weight;

        // Reduce the weight based on distance to the goal, if the
        // goal cares about distance.
        if(advice.radius>0) {
          real_t dist = distance2(advice.position,ship.position);
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

    object_id closest_planet = select_target(-1,select_nearest(ship.position),ce.get_planets(),false);

    const vector<TargetAdvice> &target_advice = faction_it->get_target_advice();
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
