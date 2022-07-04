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

#include "CE/CombatEngine.hpp"
#include "CE/Ship.hpp"
#include "CE/Projectile.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

Salvage::Salvage(Dictionary dict):
flotsam_mesh(get<Ref<Mesh>>(dict,"flotsam_mesh")),
flotsam_scale(get<float>(dict,"flotsam_scale",1.0f)),
cargo_name(get<String>(dict,"cargo_name")),
cargo_count(get<int>(dict,"cargo_count",1)),
cargo_unit_mass(get<real_t>(dict,"cargo_unit_mass",1.0f)),
cargo_unit_value(get<real_t>(dict,"cargo_unit_value",1.0f)),
armor_repair(get<real_t>(dict,"armor_repair",0.0f)),
structure_repair(get<real_t>(dict,"structure_repair",0.0f)),
fuel(get<real_t>(dict,"fuel",0.0f)),
spawn_duration(get<real_t>(dict,"spawn_duration",60.0f)),
grab_radius(get<real_t>(dict,"grab_radius",0.25f))
{
  if(cargo_count and cargo_unit_value<=0)
    Godot::print_warning("Salvageable \""+str(cargo_name)+"\" in flotsam has no value.",
                   __FUNCTION__,__FILE__,__LINE__);
}
Salvage::~Salvage() {}

Projectile::Projectile(object_id id,const Ship &ship,const Weapon &weapon,object_id alternative_target):
  id(id),
  source(ship.id),
  target(alternative_target>=0 ? alternative_target : ship.get_target()),
  mesh_id(weapon.mesh_id),
  guided(weapon.guided),
  guidance_uses_velocity(weapon.guidance_uses_velocity),
  auto_retarget(weapon.auto_retarget),
  damage(weapon.damage),
  impulse(weapon.impulse),
  blast_radius(weapon.blast_radius),
  detonation_range(weapon.detonation_range),
  turn_rate(weapon.projectile_turn_rate),
  always_drag(false),
  mass(weapon.projectile_mass),
  drag(weapon.projectile_drag),
  thrust(weapon.projectile_thrust),
  lifetime(weapon.projectile_lifetime),
  initial_velocity(weapon.initial_velocity),
  max_speed(weapon.terminal_velocity),
  heat_fraction(weapon.heat_fraction),
  energy_fraction(weapon.energy_fraction),
  thrust_fraction(weapon.thrust_fraction),
  faction(ship.faction),
  damage_type(weapon.damage_type),
  max_structure(weapon.projectile_structure),
  structure(max_structure),
  position(ship.position + weapon.position.rotated(y_axis,ship.rotation.y)),
  linear_velocity(),
  rotation(),
  angular_velocity(),
  forces(),
  age(0),
  scale(1.0f),
  visual_height(projectile_height),
  alive(true),
  direct_fire(weapon.direct_fire),
  possible_hit(true),
  integrate_forces(guided),
  salvage(),
  antimissile_damage(false)
{
  if(guided and direct_fire)
    Godot::print_warning(ship.name+" fired a direct fire weapon that is guided (2)",__FUNCTION__,__FILE__,__LINE__);
  // if(guided and target<0)
  //   // This can happen if the player fires with no target. The AI should never do this.
  //   Godot::print_warning(ship.name+" fired a guided projectile with no target (1)",__FUNCTION__,__FILE__,__LINE__);
  rotation.y = ship.rotation.y;
  if(weapon.turn_rate>0)
    rotation.y += weapon.rotation.y;
  else if(!weapon.guided) {
    real_t estimated_range = weapon.projectile_lifetime*weapon.terminal_velocity;
    rotation.y += asin_clamp(weapon.position.z/estimated_range);
  }
  rotation.y = fmodf(rotation.y,2*PI);

  if(guided and not thrust)
    Godot::print_warning("Guided weapon has no thrust",__FUNCTION__,__FILE__,__LINE__);

  linear_velocity = unit_from_angle(rotation.y)*initial_velocity + ship.linear_velocity;
}

// Create an anti-missile projectile
Projectile::Projectile(object_id id,const Ship &ship,const Weapon &weapon,Projectile &target,Vector3 position,real_t scale,real_t rotation):
  id(id),
  source(ship.id),
  target(-1),
  mesh_id(weapon.mesh_id),
  guided(false),
  guidance_uses_velocity(false),
  auto_retarget(false),
  damage(weapon.damage),
  impulse(false),
  blast_radius(0),
  detonation_range(0),
  turn_rate(0),
  always_drag(false),
  mass(weapon.projectile_mass),
  drag(weapon.projectile_drag),
  thrust(0),
  lifetime(weapon.projectile_lifetime ? weapon.projectile_lifetime : weapon.firing_delay),
  initial_velocity(weapon.initial_velocity),
  max_speed(weapon.terminal_velocity),
  heat_fraction(0),
  energy_fraction(0),
  thrust_fraction(0),
  faction(ship.faction),
  damage_type(DAMAGE_TYPELESS),
  max_structure(weapon.projectile_structure),
  structure(max_structure),
  position(position),
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
  salvage(),
  antimissile_damage(true)
{}

Projectile::Projectile(object_id id,const Ship &ship,const Weapon &weapon,Vector3 position,real_t scale,real_t rotation,object_id target):
  id(id),
  source(ship.id),
  target(target),
  mesh_id(weapon.mesh_id),
  guided(weapon.guided),
  guidance_uses_velocity(weapon.guidance_uses_velocity),
  auto_retarget(weapon.auto_retarget),
  damage(weapon.damage),
  impulse(weapon.impulse),
  blast_radius(weapon.blast_radius),
  detonation_range(weapon.detonation_range),
  turn_rate(weapon.projectile_turn_rate),
  always_drag(false),
  mass(weapon.projectile_mass),
  drag(weapon.projectile_drag),
  thrust(weapon.projectile_thrust),
  lifetime(weapon.projectile_lifetime),
  initial_velocity(weapon.initial_velocity),
  max_speed(weapon.terminal_velocity),
  heat_fraction(weapon.heat_fraction),
  energy_fraction(weapon.energy_fraction),
  thrust_fraction(weapon.thrust_fraction),
  faction(ship.faction),
  damage_type(weapon.damage_type),
  max_structure(weapon.projectile_structure),
  structure(max_structure),
  position(position),
  linear_velocity(),
  rotation(Vector3(0,rotation,0)),
  angular_velocity(),
  forces(),
  age(0),
  scale(scale),
  visual_height(projectile_height),
  alive(true),
  direct_fire(weapon.direct_fire),
  possible_hit(true),
  integrate_forces(false),
  salvage(),
  antimissile_damage(false)
{
  if(guided and direct_fire)
    Godot::print_warning(ship.name+" fired a direct fire weapon that is guided (2)",__FUNCTION__,__FILE__,__LINE__);
  // if(guided and target<0)
  //   // This can happen if the player fires with no target. The AI should never do this.
  //   Godot::print_warning(ship.name+" fired a guided projectile with no target (2)",__FUNCTION__,__FILE__,__LINE__);
}

Projectile::Projectile(object_id id,const Ship &ship,shared_ptr<const Salvage> salvage,Vector3 position,real_t rotation,Vector3 velocity,real_t mass,MultiMeshManager &multimeshes):
  id(id),
  source(ship.id),
  target(ship.get_target()),
  mesh_id(multimeshes.add_preloaded_mesh(salvage->flotsam_mesh)),
  guided(false),
  guidance_uses_velocity(false),
  auto_retarget(false),
  damage(0),
  impulse(0),
  blast_radius(0),
  detonation_range(salvage->grab_radius),
  turn_rate(0),
  always_drag(true),
  mass(mass),
  drag(.2),
  thrust(0),
  lifetime(salvage->spawn_duration),
  initial_velocity(velocity.length()),
  max_speed(velocity.length()),
  heat_fraction(0),
  energy_fraction(0),
  thrust_fraction(0),
  faction(FLOTSAM_FACTION),
  damage_type(DAMAGE_TYPELESS),
  max_structure(0),
  structure(max_structure),
  position(position),
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
  salvage(salvage),
  antimissile_damage(false)
{
  if(!salvage->flotsam_mesh.is_valid())
    Godot::print_error(ship.name+": salvage has no flotsam mesh",__FUNCTION__,__FILE__,__LINE__);
  else if(!mesh_id)
    Godot::print_error(ship.name+": got no mesh_id from flotsam mesh",__FUNCTION__,__FILE__,__LINE__);
}

Projectile::~Projectile() {}

real_t Projectile::take_damage(real_t amount) {
  if(not max_structure)
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
  double eta_without_thrust = dp.length()/max_speed + fabs(angle2(next_heading,dp.normalized()))/turn_rate;

  DVector3 next_velocity = linear_velocity;
  next_velocity -= linear_velocity*drag*delta;
  next_velocity += thrust*next_heading*delta/mass;
  
  DVector3 position_with_thrust = position+next_velocity*delta;
  dp=next_target_position-position_with_thrust;
  double eta_with_thrust = dp.length()/max_speed + fabs(angle2(next_heading,dp.normalized()))/turn_rate;

  return eta_with_thrust<eta_without_thrust;
}

void Projectile::integrate_projectile_forces(real_t thrust_fraction,bool drag,real_t delta) {
  FAST_PROFILING_FUNCTION;

  // Projectiles with direct fire are always at their destination.
  if(is_direct_fire() and !is_antimissile())
    return;

  // Integrate forces if requested.
  if(integrate_forces) {
    real_t mass=max(this->mass,1e-5f);
    if(drag and (always_drag ||
                 linear_velocity.length_squared()>max_speed*max_speed) )
      linear_velocity -= linear_velocity*drag*mass*delta;
    if(thrust and thrust_fraction>0)
      forces += thrust*thrust_fraction*get_heading(*this);
    linear_velocity += forces*delta/mass;
    forces = Vector3(0,0,0);
  }

  // Advance state by time delta
  rotation.y += angular_velocity.y*delta;
  position += linear_velocity*delta;
}

bool Projectile::collide_point_projectile(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;
  Vector3 point1(position.x,500,position.z);
  Vector3 point2(position.x,-500,position.z);
  Ship * p_ship = ce.space_intersect_ray_p_ship(point1,point2,ce.get_enemy_mask(faction));
  if(!p_ship)
    return false;

  if(damage)
    p_ship->take_damage(damage,damage_type,
                        heat_fraction,energy_fraction,thrust_fraction);
  if(impulse and not p_ship->immobile) {
    Vector3 impulse = this->impulse*linear_velocity.normalized();
    if(impulse.length_squared())
      PhysicsServer::get_singleton()->body_apply_central_impulse(p_ship->rid,impulse);
  }

  if(p_ship->fate==FATED_TO_FLY and salvage and p_ship->cargo_web_active)
    p_ship->salvage_projectile(ce,*this);
  return true;
}


bool Projectile::collide_projectile(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;
  projectile_hit_list_t hits = ce.find_projectile_collisions(*this,detonation_range);
  if(hits.empty())
    return false;

  real_t min_dist = numeric_limits<real_t>::infinity();
  Ship *closest = nullptr;
  Vector3 closest_pos(0,0,0);
  bool hit_something = false;

  for(auto &hit : hits) {
    Ship &ship = hit.second->second;
    if(ship.fate<=0) {
      real_t dist = ship.position.distance_to(position);
      if(dist<min_dist) {
        closest = &ship;
        closest_pos = hit.first;
        min_dist = dist;
      }
      hit_something = true;
    }
  }

  PhysicsServer * physics_server = PhysicsServer::get_singleton();
  
  if(hit_something) {
    bool have_impulse = impulse>1e-5;
    if(not salvage and blast_radius>1e-5) {
      projectile_hit_list_t blasted = ce.find_projectile_collisions(*this,blast_radius,ce.max_ships_hit_per_projectile_blast);

      for(auto &blastee : blasted) {
        Ship &ship = blastee.second->second;
        if(ship.fate<=0) {
          real_t distance = max(0.0f,ship.position.distance_to(position)-ship.radius);
          real_t dropoff = 1.0 - distance/blast_radius;
          dropoff*=dropoff;
          if(damage)
            ship.take_damage(damage*dropoff,damage_type,
                             heat_fraction,energy_fraction,thrust_fraction);
          if(have_impulse and not ship.immobile) {
            Vector3 impulse1 = linear_velocity.normalized();
            Vector3 impulse2 = (ship.position-position).normalized();
            Vector3 combined = impulse*(impulse1+impulse2)*dropoff/2;
            if(combined.length_squared())
              physics_server->body_apply_central_impulse(ship.rid,combined);
          }
        }
      }
    } else {
      Ship &ship = *closest;
      if(damage)
        closest->take_damage(damage,damage_type,
                             heat_fraction,energy_fraction,thrust_fraction);
      if(have_impulse and not ship.immobile) {
        Vector3 impulse = this->impulse*linear_velocity.normalized();
        if(impulse.length_squared())
          physics_server->body_apply_central_impulse(ship.rid,impulse);
      }
      if(ship.fate==FATED_TO_FLY and salvage and ship.cargo_web_active)
        ship.salvage_projectile(ce,*this);
    }
    return true;
  } else
    return false;
}

Ship * Projectile::get_projectile_target(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;

  Ship *target_iter = ce.ship_with_id(target);
  
  if(target_iter or not auto_retarget)
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
    return; // Target is dead.
  }
  if(max_speed<1e-5) {
    angular_velocity.y = 0;
    integrate_projectile_forces(1,true,delta);
    return; // Cannot track until we have a speed.
  }

  DVector3 relative_position = target.position - position;
  DVector3 course_velocity;
  double intercept_time;
  double lifetime_remaining = lifetime-age;
  
  if(guidance_uses_velocity) {
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
  double turn_rate = this->turn_rate;

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

  if(guided)
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
