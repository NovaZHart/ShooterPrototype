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
  salvage()
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
  lifetime(weapon.firing_delay*4),
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
  linear_velocity(),
  rotation(Vector3(0,rotation,0)),
  angular_velocity(),
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
  salvage()
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
  salvage(salvage)
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

  age += delta;

  // Projectiles with direct fire are always at their destination.
  if(direct_fire)
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
