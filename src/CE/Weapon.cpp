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

#include "CE/Weapon.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

Weapon::Weapon(const Weapon::CreateFlotsamPlaceholder &p):
  damage(0),
  impulse(0),
  initial_velocity(10), // overridden in Projectile
  projectile_mass(10),
  projectile_drag(.2),
  projectile_thrust(0),
  projectile_lifetime(10), // overridden in Projectile
  projectile_structure(0),
  projectile_turn_rate(0),
  firing_delay(1),
  turn_rate(0),
  blast_radius(0),
  detonation_range(2), // overridden in Projectile
  threat(0),
  heat_fraction(0),
  energy_fraction(0),
  thrust_fraction(0),
  firing_energy(0),
  firing_heat(0),
  antimissile(false),
  direct_fire(false),
  guided(false),
  guidance_uses_velocity(false),
  auto_retarget(false),
  mesh_id(-1),
  terminal_velocity(0),
  projectile_range(0),
  node_path(),
  is_turret(false),
  damage_type(0),
  reload_delay(0),
  reload_energy(0),
  reload_heat(0),
  ammo_capacity(0),
  ammo(0),
  position(),
  rotation(),
  firing_countdown(),
  reload_countdown(),
  harmony_angle(0)
{}

Weapon::Weapon(Dictionary dict,MultiMeshManager &multimeshes):
  damage(get<real_t>(dict,"damage")),
  impulse(get<real_t>(dict,"impulse")),
  initial_velocity(get<real_t>(dict,"initial_velocity")),
  projectile_mass(get<real_t>(dict,"projectile_mass")),
  projectile_drag(get<real_t>(dict,"projectile_drag")),
  projectile_thrust(get<real_t>(dict,"projectile_thrust")),
  projectile_lifetime(max(1.0f/60.0f,get<real_t>(dict,"projectile_lifetime"))),
  projectile_structure(get<real_t>(dict,"projectile_structure",0)),
  projectile_turn_rate(get<real_t>(dict,"projectile_turn_rate")),
  firing_delay(get<real_t>(dict,"firing_delay")),
  turn_rate(get<real_t>(dict,"turn_rate")),
  blast_radius(get<real_t>(dict,"blast_radius")),
  detonation_range(get<real_t>(dict,"detonation_range")),
  threat(get<real_t>(dict,"threat")),
  heat_fraction(get<real_t>(dict,"heat_fraction")),
  energy_fraction(get<real_t>(dict,"energy_fraction")),
  thrust_fraction(get<real_t>(dict,"thrust_fraction")),
  firing_energy(get<real_t>(dict,"firing_energy")),
  firing_heat(get<real_t>(dict,"firing_heat")),
  antimissile(get<bool>(dict,"antimissile")),
  direct_fire(antimissile or firing_delay<1e-5),
  guided(not direct_fire and get<bool>(dict,"guided")),
  guidance_uses_velocity(get<bool>(dict,"guidance_uses_velocity")),
  auto_retarget(get<bool>(dict,"auto_retarget")),
  mesh_id(multimeshes.add_mesh(get<String>(dict,"projectile_mesh_path"))),
  terminal_velocity((projectile_drag>0 and projectile_thrust>0 and projectile_drag>0) ? projectile_thrust/(projectile_drag*projectile_mass) : initial_velocity),
  projectile_range(projectile_lifetime*terminal_velocity),
  node_path(get<NodePath>(dict,"node_path")),
  is_turret(turn_rate>1e-5),
  damage_type(clamp(get<int>(dict,"damage_type"),0,NUM_DAMAGE_TYPES-1)),
  reload_delay(max(0.0f,get<real_t>(dict,"reload_delay"))),
  reload_energy(max(0.0f,get<real_t>(dict,"reload_energy"))),
  reload_heat(max(0.0f,get<real_t>(dict,"reload_heat"))),
  ammo_capacity(max(0,get<int>(dict,"ammo_capacity"))),
  ammo(max(0,get<int>(dict,"ammo_capacity"))),
  position(get<Vector3>(dict,"position")),
  rotation(get<Vector3>(dict,"rotation")),
  firing_countdown(0), reload_countdown(0),
  harmony_angle(asin_clamp(position.z/projectile_range))
{
  if(not ammo_capacity)
    ammo=-1;
}

Weapon::~Weapon()
{}

void Weapon::reload(Ship &ship,ticks_t idelta) {
  firing_countdown.advance(idelta*ship.efficiency);
  if(ammo_capacity and reload_delay) {
    reload_countdown.advance(idelta*ship.efficiency);
    if(not reload_countdown.ticking() and ammo<ammo_capacity) {
      ammo++;
      if(reload_energy)
        ship.energy -= reload_energy;
      if(reload_heat)
        ship.heat += reload_heat;
      reload_countdown.reset(reload_delay*ticks_per_second);
    }
  }
}

void Weapon::fire(Ship &ship,ticks_t idelta) {
  firing_countdown.reset(firing_delay*ticks_per_second);
  if(ammo_capacity)
    ammo--;
}

Dictionary Weapon::make_status_dict() const {
  Dictionary s;
  s["damage"]=damage;
  s["impulse"]=impulse;
  s["initial_velocity"]=initial_velocity;
  s["projectile_mass"]=projectile_mass;
  s["projectile_drag"]=projectile_drag;
  s["projectile_thrust"]=projectile_thrust;
  s["projectile_lifetime"]=projectile_lifetime;
  s["projectile_turn_rate"]=projectile_turn_rate;
  s["projectile_structure"]=projectile_structure;
  s["firing_delay"]=firing_delay;
  s["blast_radius"]=blast_radius;
  s["detonation_range"]=detonation_range;
  s["threat"]=threat;
  s["direct_fire"]=direct_fire;
  s["guided"]=guided;
  s["antimissile"]=guided;
  s["auto_retarget"]=auto_retarget;
  s["guidance_uses_velocity"]=guidance_uses_velocity;
  s["position"]=position;
  s["rotation"]=rotation;
  if(ammo_capacity)
    s["ammo"]=ammo;
  //  s["instance_id"]=instance_id;
  s["firing_countdown"]=firing_countdown.ticks_left()/real_t(ticks_per_second);
  return s;
}
