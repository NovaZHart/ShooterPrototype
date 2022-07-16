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
#include <PhysicsServer.hpp>

#include "CE/Salvage.hpp"
#include "CE/CombatEngine.hpp"
#include "CE/Ship.hpp"
#include "CE/Projectile.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

Projectile::Projectile(object_id id,const Ship &ship,shared_ptr<const Weapon> weapon,object_id alternative_target):
  CelestialObject(PROJECTILE),
  id(id),
  weapon(weapon),
  source(ship.id),
  target(alternative_target>=0 ? alternative_target : ship.get_target()),
  mesh_id(weapon->mesh_id),
  always_drag(false),
  lifetime(weapon->projectile_lifetime),
  max_speed(weapon->terminal_velocity),
  detonation_range(weapon->detonation_range),
  faction(ship.faction),
  structure(weapon->projectile_structure),
  position(ship.position + weapon->get_position().rotated(y_axis,ship.rotation.y)),
  old_position(position),
  linear_velocity(),
  rotation(),
  angular_velocity(),
  forces(),
  age(0),
  scale(1.0f),
  visual_height(projectile_height),
  alive(true),
  direct_fire(weapon->direct_fire),
  possible_hit(true),
  integrate_forces(weapon->guided),
  salvage()
{
  if(get_guided() and is_direct_fire())
    Godot::print_warning(ship.name+" fired a direct fire weapon that is guided (2)",__FUNCTION__,__FILE__,__LINE__);
  // if(guided and target<0)
  //   // This can happen if the player fires with no target. The AI should never do this.
  //   Godot::print_warning(ship.name+" fired a guided projectile with no target (1)",__FUNCTION__,__FILE__,__LINE__);
  rotation.y = ship.rotation.y;
  if(weapon->turn_rate>0)
    rotation.y += weapon->get_rotation().y;
  else if(!weapon->guided) {
    real_t estimated_range = weapon->projectile_lifetime*weapon->terminal_velocity;
    rotation.y += asin_clamp(weapon->get_position().z/estimated_range);
  }
  rotation.y = fmodf(rotation.y,2*PI);

  if(get_guided() and not get_thrust())
    Godot::print_warning("Guided weapon has no thrust",__FUNCTION__,__FILE__,__LINE__);

  linear_velocity = unit_from_angle(rotation.y)*get_initial_velocity() + ship.linear_velocity;
}

// Create an anti-missile projectile
Projectile::Projectile(object_id id,const Ship &ship,shared_ptr<const Weapon> weapon,Projectile &target,Vector3 position,real_t scale,real_t rotation):
  CelestialObject(PROJECTILE),
  id(id),
  weapon(weapon),
  source(ship.id),
  target(-1),
  mesh_id(weapon->mesh_id),
  always_drag(false),
  lifetime(weapon->projectile_lifetime ? weapon->projectile_lifetime : weapon->firing_delay),
  max_speed(weapon->terminal_velocity),
  detonation_range(0),
  faction(ship.faction),
  structure(weapon->projectile_structure),
  position(position),
  old_position(position),
  linear_velocity(ship.linear_velocity),
  rotation(Vector3(0,rotation,0)),
  angular_velocity(Vector3(0,0,0)),
  forces(),
  age(0),
  scale(scale),
  visual_height(above_projectiles),
  alive(true),
  direct_fire(true),
  possible_hit(false),
  integrate_forces(false),
  salvage()
{}

Projectile::Projectile(object_id id,const Ship &ship,shared_ptr<const Weapon> weapon,Vector3 position,real_t scale,real_t rotation,object_id target):
  CelestialObject(PROJECTILE),
  id(id),
  weapon(weapon),
  source(ship.id),
  target(target),
  mesh_id(weapon->mesh_id),
  always_drag(false),
  lifetime(weapon->projectile_lifetime),
  max_speed(weapon->terminal_velocity),
  detonation_range(weapon->detonation_range),
  faction(ship.faction),
  structure(weapon->projectile_structure),
  position(position),
  old_position(position),
  linear_velocity(),
  rotation(Vector3(0,rotation,0)),
  angular_velocity(),
  forces(),
  age(0),
  scale(scale),
  visual_height(projectile_height),
  alive(true),
  direct_fire(weapon->direct_fire),
  possible_hit(true),
  integrate_forces(false),
  salvage()
{
  if(get_guided() and is_direct_fire())
    Godot::print_warning(ship.name+" fired a direct fire weapon that is guided (2)",__FUNCTION__,__FILE__,__LINE__);
  // if(guided and target<0)
  //   // This can happen if the player fires with no target. The AI should never do this.
  //   Godot::print_warning(ship.name+" fired a guided projectile with no target (2)",__FUNCTION__,__FILE__,__LINE__);
}

Projectile::Projectile(object_id id,const Ship *ship,shared_ptr<const Salvage> salvage,Vector3 position,real_t rotation,Vector3 velocity,real_t mass,MultiMeshManager &multimeshes,shared_ptr<const Weapon> weapon_placeholder):
  CelestialObject(PROJECTILE),
  id(id),
  weapon(weapon_placeholder),
  source(ship ? ship->id : -1),
  target(ship ? ship->get_target() : -1),
  mesh_id(multimeshes.add_preloaded_mesh(salvage->flotsam_mesh)),
  always_drag(true),
  lifetime(salvage->spawn_duration),
  max_speed(velocity.length()),
  detonation_range(salvage->grab_radius),
  faction(FLOTSAM_FACTION),
  structure(weapon->projectile_structure),
  position(position),
  old_position(position),
  linear_velocity(velocity),
  rotation(Vector3(0,rotation,0)),
  angular_velocity(),
  forces(),
  age(0),
  scale(salvage->flotsam_scale),
  visual_height(flotsam_height),
  alive(true),
  direct_fire(false),
  possible_hit(false),
  integrate_forces(true),
  salvage(salvage)
{
  if(!salvage->flotsam_mesh.is_valid()) {
    String name = ship ? ship->name : String("Non-ship flotsam");
    Godot::print_error(ship->name+": salvage has no flotsam mesh",__FUNCTION__,__FILE__,__LINE__);
  } else if(!mesh_id) {
    String name = ship ? ship->name : String("Non-ship flotsam");
    Godot::print_error(ship->name+": got no mesh_id from flotsam mesh",__FUNCTION__,__FILE__,__LINE__);
  }
}

Projectile::~Projectile() {}

void Projectile::get_object_info(CelestialInfo &info) const {
  info = { id, position, 1e-5 };
}
object_id Projectile::get_object_id() const {
  return id;
}
real_t Projectile::get_object_radius() const {
  return 1e-5;
}
Vector3 Projectile::get_object_xyz() const {
  return position;
}
Vector2 Projectile::get_object_xz() const {
  return Vector2(position.x,position.z);
}

real_t Projectile::take_damage(real_t amount) {
  if(not is_missile())
    return amount;
  double after = structure-amount;
  if(after<=0) {
    structure=0;
    alive=false;
    return -after;
  }
  structure=after;
  return 0;
}

bool Projectile::is_eta_lower_with_thrust(DVector3 target_position,DVector3 target_velocity,DVector3 heading,real_t delta) {
  FAST_PROFILING_FUNCTION;
  DVector3 next_target_position = target_position+target_velocity*delta;
  next_target_position.y=0;
  DVector3 next_heading = heading+angular_velocity*delta;
  DVector3 position = this->position;
  position.y=0;
  
  DVector3 position_without_thrust = position+linear_velocity*delta;
  DVector3 dp=next_target_position-position_without_thrust;
  double eta_without_thrust = dp.length()/max_speed + fabs(angle2(next_heading,dp.normalized()))/get_turn_rate();

  DVector3 next_velocity = linear_velocity;
  next_velocity -= linear_velocity*get_drag()*delta;
  next_velocity += get_thrust()*next_heading*delta/get_mass();
  
  DVector3 position_with_thrust = position+next_velocity*delta;
  dp=next_target_position-position_with_thrust;
  double eta_with_thrust = dp.length()/max_speed + fabs(angle2(next_heading,dp.normalized()))/get_turn_rate();

  return eta_with_thrust<eta_without_thrust;
}

void Projectile::integrate_projectile_forces(real_t thrust_fraction,bool drag,real_t delta) {
  FAST_PROFILING_FUNCTION;

  // Projectiles with direct fire are always at their destination.
  if(is_direct_fire() and !is_antimissile())
    return;

  // Integrate forces if requested.
  if(integrate_forces) {
    real_t mass=max(get_mass(),1e-5f);
    if(drag and (always_drag ||
                 linear_velocity.length_squared()>max_speed*max_speed) )
      linear_velocity -= linear_velocity*get_drag()*mass*delta;
    if(get_thrust() and thrust_fraction>0)
      forces += get_thrust()*thrust_fraction*CE::get_heading(*this);
    linear_velocity += forces*delta/mass;
    forces = Vector3(0,0,0);
  }

  // Advance state by time delta
  rotation.y += angular_velocity.y*delta;
  position += linear_velocity*delta;
}

bool Projectile::collide_point_projectile(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;
  Vector3 point1(position.x,ship_height,position.z);
  Vector3 point2(old_position.x,ship_height,old_position.z);
  Ship * p_ship = ce.space_intersect_ray_p_ship(point1,point2,ce.get_enemy_mask(faction));
  if(!p_ship)
    return false;

  if(salvage) {
    if(!p_ship->fate==FATED_TO_FLY) {
      //Godot::print("Ship is not salvaging because it is not fated to fly.");
      return false;
    } else if(!p_ship->cargo_web_active) {
      //Godot::print("Ship is not salvaging because its cargo web is inactive.");
      return false;
    } else {
      //Godot::print("Ship should salvage projectile.");
      p_ship->salvage_projectile(ce,*this);
    }
  }

  if(get_damage())
    p_ship->take_damage(get_damage(),get_damage_type(),
                        get_heat_fraction(),get_energy_fraction(),get_thrust_fraction());
  if(get_impulse() and not p_ship->immobile) {
    Vector3 impulse = get_impulse()*linear_velocity.normalized();
    if(impulse.length_squared())
      PhysicsServer::get_singleton()->body_apply_central_impulse(p_ship->rid,impulse);
  }
  return true;
}


bool Projectile::collide_projectile(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;
  
  Vector3 collision_location;
  faction_mask_t collision_mask=ce.get_enemy_mask(faction);
  hit_list_t hits = ce.find_projectile_collisions(position,old_position,collision_mask,detonation_range,true,collision_location,ce.max_ships_searched_for_detonation_range);
  
  if(hits.empty())
    return false;

  real_t min_dist = numeric_limits<real_t>::infinity();
  Ship *closest = nullptr;
  Vector3 closest_pos(0,0,0);
  bool hit_something = false;

  for(auto &hit : hits) {
    if(!hit.hit->is_ship())
      continue;
    Ship &ship = hit.hit->as_ship();
    if(ship.fate<=0) {
      if(hit.distance<min_dist) {
        closest = &ship;
        closest_pos = hit.get_x0z();
        min_dist = hit.distance;
      }
      hit_something = true;
    }
  }

  PhysicsServer * physics_server = PhysicsServer::get_singleton();
  
  if(hit_something) {
    bool have_impulse = get_impulse()>1e-5;
    if(not salvage and get_blast_radius()>1e-5) {
      Vector3 discard;
      hit_list_t blasted = ce.find_projectile_collisions(collision_location,collision_location,collision_mask,get_blast_radius(),false,discard,ce.max_ships_hit_per_projectile_blast);

      for(auto &blastee : blasted) {
        if(!blastee.hit->is_ship())
          continue;
        Ship &ship = blastee.hit->as_ship();
        if(ship.fate<=0) {
          real_t distance = max(0.0f,ship.position.distance_to(position)-ship.radius);
          real_t dropoff = 1.0 - distance/get_blast_radius();
          dropoff*=dropoff;
          if(get_damage())
            ship.take_damage(get_damage()*dropoff,get_damage_type(),
                             get_heat_fraction(),get_energy_fraction(),get_thrust_fraction());
          if(have_impulse and not ship.immobile) {
            Vector3 impulse1 = linear_velocity.normalized();
            Vector3 impulse2 = (ship.position-position).normalized();
            Vector3 combined = get_impulse()*(impulse1+impulse2)*dropoff/2;
            if(combined.length_squared())
              physics_server->body_apply_central_impulse(ship.rid,combined);
          }
        }
      }
    } else {
      Ship &ship = *closest;
      if(salvage) {
        if(!ship.fate==FATED_TO_FLY) {
          //Godot::print("Ship is not salvaging because it is not fated to fly.");
          return false;
        } else if(!ship.cargo_web_active) {
          //Godot::print("Ship is not salvaging because its cargo web is inactive.");
          return false;
        } else {
          //Godot::print("Ship should salvage projectile.");
          ship.salvage_projectile(ce,*this);
        }
      }
      if(get_damage())
        closest->take_damage(get_damage(),get_damage_type(),
                             get_heat_fraction(),get_energy_fraction(),get_thrust_fraction());
      if(have_impulse and not ship.immobile) {
        Vector3 impulse = get_impulse()*linear_velocity.normalized();
        if(impulse.length_squared())
          physics_server->body_apply_central_impulse(ship.rid,impulse);
      }
    }
    return true;
  } else
    return false;
}

Ship * Projectile::get_projectile_target(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;

  Ship *target_iter = ce.ship_with_id(target);
  
  if(target_iter or not get_auto_retarget())
    return target_iter;

  // Target is gone. Is the attacker still alive?
  
  Ship * source_iter = ce.ship_with_id(source);
  if(!source_iter)
    return target_iter;

  // Projectile target is now the new target of the attacker.
  target = source_iter->get_target();

  // Use the new target, if it exists.
  target_iter = ce.ship_with_id(target);
  return target_iter;
}

void Projectile::guide_projectile(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;

  real_t delta = ce.get_delta();
  Ship * target_iter = get_projectile_target(ce);
  if(!target_iter) {
    angular_velocity.y = 0;
    integrate_projectile_forces(1,true,delta);
    return; // Nothing to track.
  }

  Ship &target = *target_iter;
  if(target.fate==FATED_TO_DIE) {
    angular_velocity.y = 0;
    integrate_projectile_forces(1,true,delta);
    Godot::print("guided projectile target is dead");
    return; // Target is dead.
  }
  if(max_speed<1e-5) {
    angular_velocity.y = 0;
    integrate_projectile_forces(1,true,delta);
    Godot::print("guided projectile has no max speed");
    return; // Cannot track until we have a speed.
  }

  DVector3 relative_position = target.position - position;
  DVector3 course_velocity;
  double intercept_time;
  double lifetime_remaining = lifetime-age;
  
  if(get_guidance_uses_velocity()) {
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
  
  DVector3 velocity_correction = course_velocity-linear_velocity;
  DVector3 heading = get_heading_d(*this);
  DVector3 desired_heading = velocity_correction.normalized()*(1-weight) + course_velocity.normalized()*weight;
  double desired_heading_angle = angle_from_unit(desired_heading);
  double heading_angle = angle_from_unit(heading);
  double angle_correction = desired_heading_angle-heading_angle;
  double turn_rate = get_turn_rate();

  bool should_thrust = dot2(heading,desired_heading)>0.95; // Don't thrust away from desired heading

  angular_velocity.y = clamp(angle_correction/delta,-turn_rate,turn_rate);
  
  integrate_projectile_forces(should_thrust,true,delta);
}

void Projectile::step_projectile(CombatEngine &ce,bool &have_died,bool &have_collided,bool &have_moved) {
  have_collided = false;
  have_moved = false;
  
  real_t delta = ce.get_delta();
  age += delta;
  
  // Direct fire projectiles do damage when launched and last only one frame.
  // The exception is anti-missile projectiles which have to stay around for a few frames.
  if(is_direct_fire() && !is_antimissile()) {
    have_died = true;
    return;
  }

  old_position=position;
  
  if(get_guided())
    guide_projectile(ce);
  else
    integrate_projectile_forces(1,true,delta);
  have_moved = true;
  
  if(possible_hit) {
    if(detonation_range>1e-5)
      have_collided = collide_projectile(ce);
    else
      have_collided = collide_point_projectile(ce);
    if(salvage)
      possible_hit=false;
  }

  have_died = have_collided or age > lifetime or (is_missile() and not structure);
}
