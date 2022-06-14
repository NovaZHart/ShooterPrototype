#include "CombatEngineData.hpp"
#include "CombatEngineUtils.hpp"
#include "MultiMeshManager.hpp"

#include <cstdint>
#include <cmath>
#include <limits>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>

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
    if(pit!=planets.end())
      suggested_spawn_point = pit->second.position;
  }
}

FactionGoal::~FactionGoal() {}

void Faction::make_state_for_gdscript(Dictionary &factions) {
  Array goal_status, spawn_desire, suggested_spawn_point;
  for(auto &goal : goals) {
    goal_status.append(static_cast<real_t>(goal.goal_success));
    spawn_desire.append(static_cast<real_t>(goal.spawn_desire));
    suggested_spawn_point.append(goal.suggested_spawn_point);
  }
  Dictionary result;
  result["goal_status"] = goal_status;
  result["spawn_desire"] = spawn_desire;
  result["suggested_spawn_point"] = suggested_spawn_point;

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
  recouped_resources(0),
  goals(), target_advice(), enemy_mask(0), friend_mask(0)
{
  Array goal_array = get<Array>(dict,"goals");
  goals.reserve(goal_array.size());
  for(int i=0,s=goal_array.size();i<s;i++)
    goals.emplace_back(goal_array[i],planets,rid2id);
}

Faction::~Faction() {}

Salvage::Salvage(Dictionary dict):
flotsam_mesh_path(get<String>(dict,"flotsam_mesh_path")),
flotsam_scale(get<float>(dict,"flotsam_scale")),
cargo_name(get<String>(dict,"cargo_name")),
cargo_count(get<int>(dict,"cargo_count")),
cargo_unit_mass(get<real_t>(dict,"cargo_unit_mass")),
armor_repair(get<real_t>(dict,"armor_repair")),
structure_repair(get<real_t>(dict,"structure_repair")),
spawn_duration(get<real_t>(dict,"spawn_duration")),
grab_radius(get<real_t>(dict,"grab_radius"))
{}
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
  mesh_id(multimeshes.add_mesh(salvage->flotsam_mesh_path)),
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
  drag(1),
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
  position(Vector3(position.x,below_ships,position.z)),
  linear_velocity(velocity),
  rotation(Vector3(0,rotation,0)),
  angular_velocity(),
  forces(),
  age(0),
  scale(salvage->flotsam_scale),
  alive(true),
  direct_fire(false),
  possible_hit(false),
  integrate_forces(true),
  salvage(salvage)
{}

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
  ammo(get<int>(dict,"ammo",ammo_capacity)),
  position(get<Vector3>(dict,"position")),
  rotation(get<Vector3>(dict,"rotation")),
  harmony_angle(asin_clamp(position.z/projectile_range)),
  firing_countdown(0), reload_countdown(0)
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

Planet::Planet(Dictionary dict,object_id id):
  id(id),
  rotation(get<Vector3>(dict,"rotation")),
  position(get<Vector3>(dict,"position")),
  transform(get<Transform>(dict,"transform")),
  name(get<String>(dict,"name")),
  rid(get<RID>(dict,"rid")),
  radius(get<real_t>(dict,"radius")),
  population(get<real_t>(dict,"population")),
  industry(get<real_t>(dict,"industry")),
  goal_data()
{}

Planet::~Planet()
{}

Dictionary Planet::update_status() const {
  Dictionary s;
  // s["rotation"] = rotation;
  // s["position"] = position;
  // s["transform"] = transform;
  s["type"] = "planet";
  s["name"] = name;
  s["rid"] = rid;
  s["radius"] = radius;
  s["alive"] = true;
  return s;
}

void Planet::update_goal_data(const Planet &other) {
  FAST_PROFILING_FUNCTION;
  goal_data = other.goal_data;
  for(auto &goal_datum : goal_data)
    goal_datum.distsq = goal_datum.position.distance_squared_to(position);
  sort(goal_data.begin(),goal_data.end(),[] (const ShipGoalData &a,const ShipGoalData &b) {
      return a.distsq<b.distsq;
    });
}

void Planet::update_goal_data(const std::unordered_map<object_id,Ship> &ships) {
  FAST_PROFILING_FUNCTION;
  goal_data.reserve(ships.size());
  goal_data.clear();
  for(ships_const_iter p_ship=ships.begin();p_ship!=ships.end();p_ship++) {
    ShipGoalData d = {
      p_ship->second.threat,
      p_ship->second.position.distance_squared_to(position),
      p_ship->second.faction,
      p_ship->second.position
    };
    goal_data.emplace_back(d);
  }
  sort(goal_data.begin(),goal_data.end(),[] (const ShipGoalData &a,const ShipGoalData &b) {
      return a.distsq<b.distsq;
    });
}

WeaponRanges make_ranges(const vector<Weapon> &weapons) {
  WeaponRanges r = {0,0,0,0,0,0};
  
  for(auto &weapon : weapons) {
    real_t range = weapon.projectile_lifetime*weapon.terminal_velocity;
    if(weapon.antimissile)
      r.antimissile = max(r.antimissile,range);
    else {
      if(weapon.turn_rate>0)
        r.turrets = max(r.turrets,range);
      else
        r.guns = max(r.guns,range);
      if(weapon.guided)
        r.guided = max(r.guided,range);
      else
        r.unguided = max(r.unguided,range);
    }
  }
  r.all = max(r.guns,r.turrets);
  
  return r;
}

static inline damage_array to_damage_array(Variant var,real_t clamp_min,real_t clamp_max) {
  PoolRealArray a = static_cast<PoolRealArray>(var);
  PoolRealArray::Read reader = a.read();
  const real_t *reals = reader.ptr();
  damage_array d;
  int a_size=a.size(), d_size=d.size();
  for(int i=0;i<d_size;i++)
    d[i] = (i<a_size) ? clamp(reals[i],clamp_min,clamp_max) : 0;
  d[DAMAGE_TYPELESS]=0; // typeless ignores resistances and passthrus
  return d;
}

Rect2 location_rect_for_aabb(const AABB &aabb,real_t expand) {
  real_t xsize=aabb.size.x*expand, zsize=aabb.size.z*expand;
  return Rect2(Vector2(-xsize/2,-zsize/2),Vector2(xsize,zsize));
}

Ship::Ship(Dictionary dict, object_id id, MultiMeshManager &multimeshes):
  id(id),
  name(get<String>(dict,"name")),
  rid(get<RID>(dict,"rid")),
  cost(max(0.0f,get<real_t>(dict,"cost"))),
  max_thrust(max(0.0f,get<real_t>(dict,"thrust"))),
  max_reverse_thrust(max(0.0f,get<real_t>(dict,"reverse_thrust",0))),
  max_turning_thrust(max(0.0f,get<real_t>(dict,"turning_thrust",0))),
  hyperthrust_ratio(max(0.0f,1.0f + get<real_t>(dict,"hyperthrust",0.0f))),
  max_cargo_mass(max(0.0f,get<real_t>(dict,"max_cargo",0))),
  threat(max(0.0f,get<real_t>(dict,"threat"))),
  visual_height(get<real_t>(dict,"visual_height",5.0f)),
  max_shields(max(1e-5f,get<real_t>(dict,"max_shields",0))),
  max_armor(max(1e-5f,get<real_t>(dict,"max_armor",0))),
  max_structure(max(1e-5f,get<real_t>(dict,"max_structure"))),
  max_fuel(max(0.0f,get<real_t>(dict,"max_fuel"))),
  heal_shields(max(0.0f,get<real_t>(dict,"heal_shields",0))),
  heal_armor(max(0.0f,get<real_t>(dict,"heal_armor",0))),
  heal_structure(max(0.0f,get<real_t>(dict,"heal_structure",0))),
  heal_fuel(max(0.0f,get<real_t>(dict,"heal_fuel",0))),
  fuel_efficiency(max(0.0f,get<real_t>(dict,"fuel_efficiency",1.0))),
  aabb(get<AABB>(dict,"aabb")),
  turn_drag(max(1e-5f,get<real_t>(dict,"turn_drag"))),
  radius(max(0.01f,sqrt(aabb.size.x*aabb.size.x+aabb.size.z*aabb.size.z))*0.6f),
  radiussq(radius*radius),
  empty_mass(max(0.0f,get<real_t>(dict,"empty_mass",0))),
  fuel_inverse_density(max(0.0f,get<real_t>(dict,"fuel_inverse_density",10.0f))),
  armor_inverse_density(max(0.0f,get<real_t>(dict,"armor_inverse_density",200.0f))),
  faction(clamp(get<int>(dict,"faction_index",0),MIN_ALLOWED_FACTION,MAX_ALLOWED_FACTION)),
  faction_mask(static_cast<faction_mask_t>(1)<<faction),
  
  explosion_damage(max(0.0f,get<real_t>(dict,"explosion_damage",0))),
  explosion_radius(max(0.0f,get<real_t>(dict,"explosion_radius",0))),
  explosion_impulse(get<real_t>(dict,"explosion_impulse",0)),
  explosion_delay(max(0,get<int>(dict,"explosion_delay",0))),
  explosion_type(clamp(get<int>(dict,"explosion_type",DAMAGE_EXPLOSIVE),0,NUM_DAMAGE_TYPES-1)),

  shield_resist(to_damage_array(dict["shield_resist"],MIN_RESIST,MAX_RESIST)),
  shield_passthru(to_damage_array(dict["shield_passthru"],MIN_PASSTHRU,MAX_PASSTHRU)),
  armor_resist(to_damage_array(dict["armor_resist"],MIN_RESIST,MAX_RESIST)),
  armor_passthru(to_damage_array(dict["armor_passthru"],MIN_PASSTHRU,MAX_PASSTHRU)),
  structure_resist(to_damage_array(dict["structure_resist"],MIN_RESIST,MAX_RESIST)),

  max_cooling(get<real_t>(dict,"cooling")),
  max_energy(max(1e-5f,get<real_t>(dict,"battery"))),
  max_power(max(1e-5f,get<real_t>(dict,"power"))),
  max_heat(max(1e-5f,get<real_t>(dict,"heat_capacity")*empty_mass)),

  shield_repair_heat(max(0.0f,get<real_t>(dict,"shield_repair_heat"))),
  armor_repair_heat(max(0.0f,get<real_t>(dict,"armor_repair_heat"))),
  structure_repair_heat(max(0.0f,get<real_t>(dict,"structure_repair_heat"))),
  shield_repair_energy(max(0.0f,get<real_t>(dict,"shield_repair_energy"))),
  armor_repair_energy(max(0.0f,get<real_t>(dict,"armor_repair_energy"))),
  structure_repair_energy(max(0.0f,get<real_t>(dict,"structure_repair_energy"))),
  only_forward_thrust_heat(max(0.0f,get<real_t>(dict,"forward_thrust_heat"))/1000.0f),
  only_reverse_thrust_heat(max(0.0f,get<real_t>(dict,"reverse_thrust_heat"))/1000.0f),
  turning_thrust_heat(max(0.0f,get<real_t>(dict,"turning_thrust_heat"))/1000.0f),
  only_forward_thrust_energy(max(0.0f,get<real_t>(dict,"forward_thrust_energy"))/1000.0f),
  only_reverse_thrust_energy(max(0.0f,get<real_t>(dict,"reverse_thrust_energy"))/1000.0f),
  turning_thrust_energy(max(0.0f,get<real_t>(dict,"turning_thrust_energy"))/1000.0f),

  rifting_damage_multiplier(clamp(get<real_t>(dict,"rifting_damage_multiplier",0.3f),0.0f,1.0f)),
  cargo_web_radius(radius+get<real_t>(dict,"cargo_web_add_radius",0)),
  cargo_web_radiussq(cargo_web_radius*cargo_web_radius),
  cargo_web_strength(get<real_t>(dict,"cargo_web_strength",900)),
  cargo_puff_mesh(get<Ref<Mesh>>(dict,"cargo_puff_mesh")),

  energy(max_energy),
  heat(0.0f),
  power(max_power),
  cooling(max_cooling),
  thrust(max_thrust),
  reverse_thrust(max_reverse_thrust),
  turning_thrust(max_turning_thrust),
  efficiency(1),
  cargo_mass(max(0.0f,get<real_t>(dict,"cargo_mass",0))),
  forward_thrust_heat(only_forward_thrust_heat),
  reverse_thrust_heat(only_reverse_thrust_heat),
  forward_thrust_energy(only_forward_thrust_energy),
  reverse_thrust_energy(only_reverse_thrust_energy),
  thrust_loss(0.0f),
  
  explosion_timer(),
  fate(FATED_TO_FLY),
  
  entry_method(static_cast<entry_t>(get<int>(dict,"entry_method",static_cast<int>(ENTRY_COMPLETE)))),
  //  turn_diameter(max_speed()*2.0/max_angular_velocity),

  shields(max(0.0f,get<real_t>(dict,"shields",max_shields))),
  armor(max(0.0f,get<real_t>(dict,"armor",max_armor))),
  structure(max(0.0f,get<real_t>(dict,"structure",max_structure))),
  fuel(max(0.0f,get<real_t>(dict,"fuel",max_fuel))),
  ai_type(static_cast<ship_ai_t>(get<int>(dict,"ai_type",ATTACKER_AI))),
  ai_flags(DECIDED_NOTHING),
  goal_action(goal_patrol),
  goal_target(-1),
  salvage_target(-1),

  shield_ellipse(-1),
  cargo_web(-1),
  
  // These eight will be replaced by the PhysicsDirectBodyState every
  // timestep.  The GDScript code must make sure mass and drag are set
  // correctly in the RigidBody object before sending it to the
  // CombatEngine.
  rotation(get<Vector3>(dict,"rotation",Vector3(0,0,0))),
  position(get<Vector3>(dict,"position",Vector3(0,0,0))),
  linear_velocity(get<Vector3>(dict,"linear_velocity",Vector3(0,0,0))),
  angular_velocity(get<Vector3>(dict,"angular_velocity",Vector3(0,0,0))),
  heading(get_heading(*this)),
  drag(max(1e-5f,get<real_t>(dict,"drag"))),
  inverse_mass(1.0/(empty_mass+cargo_mass+fuel_inverse_density*fuel+armor_inverse_density*armor)),
  inverse_inertia(get<Vector3>(dict,"inverse_inertia",Vector3(0,1,0))),
  transform(get<Transform>(dict,"transform")),

  salvage(get_salvage(get<Array>(dict,"salvage"))),
  
  weapons(get_weapons(get<Array>(dict,"weapons"),multimeshes)),
  range(make_ranges(weapons)),
  tick(0),
  rift_timer(inactive_ticks),
  no_target_timer(),
  range_check_timer(),
  shot_at_target_timer(),
  standoff_range_timer(),
  nearby_hostiles_timer(),
  salvage_timer(),
  confusion_timer(),
  tick_at_last_shot(TICKS_LONG_AGO),
  ticks_since_targetting_change(TICKS_LONG_AGO),
  ticks_since_ai_change(TICKS_LONG_AGO),
  damage_since_targetting_change(0),
  threat_vector(),
  nearby_objects(),
  nearby_enemies(),
  nearby_enemies_tick(TICKS_LONG_AGO),
  nearby_enemies_range(0),
  rand(),
  destination(randomize_destination()),
  collision_layer(0),
  
  aim_multiplier(1.0),
  confusion_multiplier(0.1),
  confusion(Vector3()),
  confusion_velocity(Vector3()),

  max_speed(0),
  max_angular_velocity(0),
  turn_diameter_squared(0),
  drag_force(),
  updated_mass_stats(false),
  cargo_web_active(false),
  immobile(false),
  inactive(false),
  damage_multiplier(1.0f),
  should_autotarget(true),
  at_first_tick(true),

  visual_scale(1.0),
  target(-1),
  cached_standoff_range(0),
  location_rect(location_rect_for_aabb(aabb,radius/6))
{
  if(max_energy<=1e-5)
    Godot::print_warning(name+String(": new ship has invalid max_energy (battery)."),__FUNCTION__,__FILE__,__LINE__);
  if(max_heat<=1e-5)
    Godot::print_warning(name+String(": new ship has invalid max_heat (heat_capacity*empty_mass)."),__FUNCTION__,__FILE__,__LINE__);
  if(max_power<=1e-5)
    Godot::print_warning(name+String(": new ship has invalid max_power (power)."),__FUNCTION__,__FILE__,__LINE__);
  if(not (drag<999999 and drag>1e-6))
    Godot::print_warning(name+String(": new ship has an invalid drag ")+String(Variant(drag)),__FUNCTION__,__FILE__,__LINE__);
  if(not (inverse_mass<999999))
    Godot::print_warning(name+String(": new ship has an invalid inverse mass ")+String(Variant(inverse_mass)),__FUNCTION__,__FILE__,__LINE__);
  if(not (turn_drag<999999 and turn_drag>1e-6))
    Godot::print_warning(name+String(": new ship has an invalid turn drag ")+String(Variant(turn_drag)),__FUNCTION__,__FILE__,__LINE__);
  if(not (thrust<999999 and thrust>=0))
    Godot::print_warning(name+String(": new ship has an invalid thrust ")+String(Variant(thrust)),__FUNCTION__,__FILE__,__LINE__);
  if(not (reverse_thrust<999999 and reverse_thrust>=0))
    Godot::print_warning(name+String(": new ship has an invalid reverse_thrust ")+String(Variant(reverse_thrust)),__FUNCTION__,__FILE__,__LINE__);
  max_speed = max(thrust,reverse_thrust)/drag*inverse_mass;
  if(not (max_speed<999999 and max_speed>=0))
    Godot::print_warning(name+String(": new ship's calculated max speed is invalid ")+String(Variant(max_speed)),__FUNCTION__,__FILE__,__LINE__);
  max_angular_velocity = turning_thrust/turn_drag*inverse_mass*PI/30.0f; // convert from RPM
  turn_diameter_squared = make_turn_diameter_squared();
  if(name=="player_ship") {
    Godot::print(name+": max thrust energy: r="+str(reverse_thrust_energy*max_reverse_thrust)+" s="+str(forward_thrust_energy*max_thrust)+" t="+str(turning_thrust_energy*max_turning_thrust));
    Godot::print(name+": max thrust heat: r="+str(reverse_thrust_heat*max_reverse_thrust)+" s="+str(forward_thrust_heat*max_thrust)+" t="+str(turning_thrust_heat*max_turning_thrust));
    Godot::print(name+": power="+str(power)+" Cooling="+str(cooling));
    Godot::print(name+": max_energy="+str(max_energy)+" max_heat="+str(max_heat));
  }

  nearby_hostiles_timer.reset();
}

Ship::~Ship()
{}

bool Ship::update_from_physics_server(PhysicsServer *physics_server,bool hyperspace) {
  FAST_PROFILING_FUNCTION;
  PhysicsDirectBodyState *state = physics_server->body_get_direct_state(rid);
  if(not state)
    return false;
  transform=state->get_transform();
  rotation=transform.basis.get_euler_xyz();
  heading=get_heading(*this);
  position=Vector3(transform.origin.x,0,transform.origin.z);
  linear_velocity=state->get_linear_velocity();
  angular_velocity=state->get_angular_velocity();
  
  Vector3 new_inverse_inertia = state->get_inverse_inertia();
  if(not (new_inverse_inertia.length()>1e-9))
    Godot::print_warning(String("Physics engine sent invalid inverse inertia ")+String(Variant(new_inverse_inertia)),__FUNCTION__,__FILE__,__LINE__);
  else
    inverse_inertia=new_inverse_inertia;
  
  real_t new_inverse_mass = state->get_inverse_mass();
  if(not (new_inverse_mass>1e-9)) {
    Godot::print_warning(String("Physics engine sent invalid inverse mass ")+String(Variant(new_inverse_mass))+". Will replace with prior value "+String(Variant(inverse_mass))+".",__FUNCTION__,__FILE__,__LINE__);
    physics_server->body_set_param(rid,PhysicsServer::BODY_PARAM_MASS,1.0/inverse_mass);
  } else
    inverse_mass=new_inverse_mass;
  
  real_t new_drag = state->get_total_linear_damp();
  if(not (new_drag>1e-9 and new_drag<999999)) {
    Godot::print_warning(String("Physics engine sent invalid linear damp ")+String(Variant(new_drag))+". Will replace with prior value "+String(Variant(drag))+".",__FUNCTION__,__FILE__,__LINE__);
    physics_server->body_set_param(rid,PhysicsServer::BODY_PARAM_LINEAR_DAMP,drag);
  } else
    drag=new_drag;
  
  update_stats(physics_server,hyperspace);
  return true;
}

void Ship::update_stats(PhysicsServer *physics_server, bool hyperspace) {
  FAST_PROFILING_FUNCTION;
  real_t new_mass = empty_mass+cargo_mass;
  real_t thrust_multiplier = hyperspace ? hyperthrust_ratio : 1.0f;
  if(max_fuel>=.001)
    new_mass += fuel/fuel_inverse_density;
  if(max_armor>=.001)
    new_mass += armor/armor_inverse_density;
  real_t old_mass = 1.0/inverse_mass;

  efficiency = 1.0;
  if(max_heat>0) {
    heat = clamp(heat,0.0f,1.3f*max_heat);
    if(heat>max_heat)
      efficiency -= 2*(heat-max_heat)/max_heat;
  }
  if(max_energy>0) {
    energy = clamp(energy,-0.3f*max_energy,max_energy);
    if(energy<0)
      efficiency -= -2*energy/max_energy;
  }

  efficiency = clamp(efficiency,0.4f,1.4f);
  
  if(max_thrust) {
    thrust = max_thrust * thrust_multiplier *
      clamp(efficiency*(max_thrust-thrust_loss)/max_thrust, 0.4, 1.6);
    if(max_reverse_thrust)
      reverse_thrust = max_reverse_thrust * thrust_multiplier *
        clamp(efficiency * (max_reverse_thrust - thrust_loss*max_reverse_thrust/max_thrust)/max_reverse_thrust, 0.4, 1.6);
    if(max_turning_thrust)
      turning_thrust = max_turning_thrust *
        clamp(efficiency * (max_turning_thrust - thrust_loss*max_turning_thrust/max_thrust)/max_turning_thrust, 0.4, 1.6);
  }

  inverse_mass = 1.0f/new_mass;
  drag_force = -linear_velocity*drag/inverse_mass;
  max_speed = max(thrust,reverse_thrust)/drag*inverse_mass;
  max_angular_velocity = turning_thrust/turn_drag*inverse_mass*PI/30.0f;
  turn_diameter_squared = make_turn_diameter_squared();

  if(fabsf(new_mass-old_mass)>0.01f)
    physics_server->body_set_param(rid,PhysicsServer::BODY_PARAM_MASS,new_mass);
  updated_mass_stats = true;
}

real_t Ship::get_standoff_range(const Ship &target,ticks_t idelta) {
  FAST_PROFILING_FUNCTION;

  if(cached_standoff_range>1e-5 and not standoff_range_timer.alarmed()) {
    // Don't calculate until we need to.
    return cached_standoff_range;
  }
  
  standoff_range_timer.reset();
  
  real_t standoff_range = numeric_limits<real_t>::infinity();
  
  if(not weapons.size()) {
    // No weapons means no standoff range
    //Godot::print("Unarmed ship "+name+" cannot have a standoff range.");
    return cached_standoff_range = standoff_range;
  }
  
  Vector3 dp_ships = get_position(target) - get_position(*this);
  real_t distance = dp_ships.length();
  
  for(auto &weapon : weapons) {
    Vector3 dp_weapon = dp_ships - get_position(weapon).rotated(y_axis,rotation.y);

    // The weapon may be closer to the target than the ship. Consider
    // this when deciding the standoff range.
    real_t untraveled_distance = dp_weapon.length() - distance;

    if(weapon.guided) {
      // Guided weapon range depends on turn time.
      if(weapon.ammo or weapon.reload_delay) {
        real_t turn_time = weapon.is_turret ? 0 : PI/weapon.projectile_turn_rate;
        real_t travel = max(0.0f,weapon.projectile_range-weapon.terminal_velocity*turn_time);
        standoff_range = min(standoff_range,travel+untraveled_distance);
      }
    } else
      standoff_range = min(standoff_range,weapon.projectile_range-untraveled_distance);
  }

  if(standoff_range<2) {
    Godot::print_warning(name+" standoff range is implausibly small: "+str(standoff_range),
                         __FUNCTION__,__FILE__,__LINE__);
  }
  
  //Godot::print("Ship "+name+" standoff range to "+target.name+" is "+str(standoff_range));
  
  return cached_standoff_range = max(0.0f,standoff_range);
}

void Ship::heal_stat(double &stat,double new_value,real_t heal_energy,real_t heal_heat) {
  real_t diff=max(0.0,stat-new_value);
  stat=new_value;
  if(heal_energy)
    energy-=heal_energy*diff;
  if(heal_heat)
    heat+=heal_heat*diff;
}

void Ship::apply_heat_and_energy_costs(real_t delta) {
  if(not immobile) { // ship does not pay to spin while arriving via a rift
    real_t angular_speed = angular_velocity.length();
    if(angular_speed) {
      real_t mag = clamp(angular_speed/max_angular_velocity,0.0f,1.0f)*turning_thrust*delta;
      energy -= mag*turning_thrust_energy;
      heat += mag*turning_thrust_heat;
    }
  }
}

void Ship::heal(bool hyperspace,real_t system_fuel_recharge,real_t center_fuel_recharge,real_t delta) {
  FAST_PROFILING_FUNCTION;
  energy = clamp(energy+power*delta,-max_energy,max_energy);
  heat = clamp(heat-cooling*delta,0.0f,2.0f*max_heat);
  if(thrust_loss) {
    thrust_loss *= pow(thrust_loss_heal,delta);
    if(thrust_loss<.01)
      thrust_loss=0;
  }

  heal_stat(shields,min(shields+heal_shields*delta*efficiency,double(max_shields)),
            shield_repair_energy,shield_repair_heat);
  if(heal_armor)
    heal_stat(armor, min(armor+heal_armor*delta*efficiency,double(max_armor)),
              armor_repair_energy,armor_repair_heat);
  heal_stat(structure, min(structure+heal_structure*delta*efficiency,double(max_structure)),
            structure_repair_energy,structure_repair_heat);

  if(hyperspace and fuel>0.0f) {
    real_t new_fuel = clamp(fuel-delta/inverse_mass*linear_velocity.length()/
                            (hyperspace_display_ratio*fuel_efficiency*1000.0f),
                            0.0f,max_fuel);
    if(fabsf(fuel-new_fuel)>1e-6)
      updated_mass_stats = true;
    fuel = new_fuel;
  } else if(fuel<max_fuel) {
    real_t recharge = system_fuel_recharge;
    real_t effective_distance = 10.0f+position.length()/hyperspace_display_ratio;
    recharge += center_fuel_recharge*10.0f/effective_distance;
    real_t new_fuel = clamp(fuel+delta*heal_fuel*recharge/1000.0f,0.0f,max_fuel);
    if(fabsf(fuel-new_fuel)>1e-6)
      updated_mass_stats = true;
    fuel = new_fuel;
  }
}

void Ship::update_confusion() {
  bool is_firing = tick_at_last_shot==tick;
  aim_multiplier = 0.99*aim_multiplier + 0.01*(is_firing ? 0.5 : 2.0);
  if(confusion.x!=0 or confusion.y!=0)
    confusion_velocity -= 0.001*confusion.normalized();

  real_t random_angle = rand.rand_angle();
  Vector3 random_unit = Vector3(cos(random_angle),0,-sin(random_angle));
  
  confusion_velocity = 0.99*(confusion_velocity + 0.01*random_unit);
  confusion = 0.999*(confusion+confusion_velocity*(confusion_multiplier*aim_multiplier));
}

static real_t apply_damage(real_t &damage,double &life,int type,
                           const damage_array &resists,
                           const damage_array &passthrus,bool allow_passthru) {
  // Apply damage of the given type to life (shields, armor, or structure) based on
  // resistances (resist) and optionally passthru (if non-null)
  // On return:
  //   damage = amount of damage not applied
  //   life = life remaining after damage is applied

  // Assumes 0<=type<NUM_DAMAGE_TYPES

  if(life<=0 or damage<=0)
    return 0.0f;

  real_t applied = 1.0 - resists[type];
  if(applied<1e-5)
    return 0.0f;

  real_t passed = 0.0f;
  real_t taken = damage;

  if(allow_passthru) {
    real_t passthru = passthrus[type];
    if(passthru>=1.0)
      return 0.0f; // All damage is passed, so we have no more to do.
    if(passthru>0) {
      taken = (1.0-passthru)*damage;
      passed = passthru*damage;
    }
  }

  // Apply resistance to damage:
  taken *= applied;

  if(taken>life) {
    // Too much damage for life.
    // Pass remaining damage, after reversing resistances:
    passed += (taken-life)/applied;
    life = 0;
  } else
    life -= taken;

  damage = passed;
  return taken;
}

real_t Ship::take_damage(real_t damage,int type,real_t heat_fraction,real_t energy_fraction,real_t thrust_fraction) {
  // Applies damage of the given type to the ship, considering fate,
  // resistances, and passthru. If structure becomes 0, marks the ship
  // as FATED_TO_EXPLODE or FATED_TO_DIE, as appropriate. Returns the
  // amount of damage not applied. Ships that are not FATED_TO_FLY
  // will not apply any damage or change their fate.  Assumes
  // 0<=type<NUM_DAMAGE_TYPES
  FAST_PROFILING_FUNCTION;

  // Returns the overkill damage (damage remaining after ship died from it).
  
  damage*=damage_multiplier;

  if(fate!=FATED_TO_FLY)
    return damage; // already dead or leaving, so cannot take more damage

  real_t remaining=damage;
  real_t shield_damage=0, armor_damage=0, structure_damage=0;
  
  if(remaining>0) {
    shield_damage = cargo_web_active ? 0 : apply_damage(remaining,shields,type,shield_resist,shield_passthru,true);
    if(remaining>0) {
      armor_damage = apply_damage(remaining,armor,type,armor_resist,armor_passthru,true);
      if(remaining>0)
        structure_damage = apply_damage(remaining,structure,type,structure_resist,armor_passthru,false);
    }
  }

  if(structure<=0) {
    // Structure is 0, so ship should explode.
    explosion_timer.reset(explosion_delay/60.0f);
    fate = FATED_TO_EXPLODE;
  } else {
    damage_since_targetting_change += damage;

    if(heat_fraction) {
      heat += heat_fraction*((shield_damage/2+armor_damage)/2+structure_damage);
    }
    if(energy_fraction)
      energy -= energy_fraction*((shield_damage/2+armor_damage)/2+structure_damage);
    if(thrust_fraction)
      thrust_loss += thrust_fraction*((shield_damage/2+armor_damage)/2+structure_damage);
  }
  
  return remaining;
}

Vector3 Ship::randomize_destination() {
  real_t r=sqrt(rand.randf())*100;
  real_t a=rand.randf()*2*PI;
  return destination = unit_from_angle(a)*r;
}

void Ship::set_scale(real_t new_scale) {
  visual_scale = new_scale;
}

DVector3 Ship::stopping_point(DVector3 tgt_vel, bool &should_reverse) const {
  FAST_PROFILING_FUNCTION;
  should_reverse = false;
  
  DVector3 pos = position;
  DVector3 rel_vel = DVector3(linear_velocity)-tgt_vel;
  DVector3 rel_vel_norm = rel_vel.normalized();
  DVector3 heading = this->heading;
  double speed = rel_vel.length();
  
  if(speed<=0)
    return pos;

  double max_angular_velocity = this->max_angular_velocity;
  double accel = double(thrust)*double(inverse_mass);
  double reverse_accel = double(reverse_thrust)*double(inverse_mass);
  double turn = ::acos(std::clamp(-rel_vel_norm.dot(heading),-1.0,1.0));
  double dist = speed*turn/max_angular_velocity + 0.5*speed*speed/accel;
  if(reverse_accel>1e-5) {
    double rev_dist = speed*(PI-turn)/max_angular_velocity + 0.5*speed*speed/reverse_accel;
    if(rev_dist < dist) {
      should_reverse = true;
      dist = rev_dist;
    }
  }
  return pos+rel_vel_norm*dist*1.3;
}

Dictionary Ship::update_status(const unordered_map<object_id,Ship> &ships,
                               const unordered_map<object_id,Planet> &planets) const {
  FAST_PROFILING_FUNCTION;
  Dictionary s;
  s["type"] = "ship";
  s["fate"] = int(fate);
  s["alive"] = fate!=FATED_TO_DIE;
  s["mass"]=1.0/inverse_mass;
  s["name"]=name;
  s["rid"]=rid;
  s["shields"]=shields;
  s["fuel"]=fuel;
  s["armor"]=armor;
  s["structure"]=structure;
  s["max_shields"]=max_shields;
  s["max_armor"]=max_armor;
  s["max_structure"]=max_structure;
  s["max_fuel"]=max_fuel;
  s["energy"]=energy;
  s["max_energy"]=max_energy;
  s["heat"]=heat;
  s["max_heat"]=max_heat;
  s["efficiency"]=efficiency;
  s["max_efficiency"]=max(1.6f,efficiency);
  s["radius"] = radius;
  s["visual_scale"] = visual_scale;
  Dictionary r;
  {
    r["guns"]=range.guns;
    r["turrets"]=range.turrets;
    r["guided"]=range.guided;
    r["unguided"]=range.unguided;
    r["all"]=range.all;
  }
  s["ranges"]=r;
  s["destination"]=destination;
  s["faction_index"]=faction;
  s["cargo_web_active"]=cargo_web_active;
  
  ships_const_iter target_p = ships.find(target);
  if(target_p!=ships.end() and target_p->second.structure>0) {
    s["target_rid"] = target_p->second.rid;
    s["target_name"] = target_p->second.name;
    s["target_type"] = "ship";
  } else {
    planets_const_iter target_p = planets.find(target);
    if(target_p!=planets.end()) {
      s["target_rid"] = target_p->second.rid;
      s["target_name"] = target_p->second.name;
      s["target_type"] = "planet";
    } else {
      s["target_rid"] = RID();
      s["target_name"] = "null";
      s["target_type"] = "unknown";
    }
  }

  return s;
}

GoalsArray::GoalsArray() {
  for(int i=0;i<PLAYER_ORDERS_MAX_GOALS;i++)
    goal[i] = 0;
}

GoalsArray::GoalsArray(const Array &a) {
  int i=0, s=a.size();
  for(;i<PLAYER_ORDERS_MAX_GOALS && i<s;i++)
    goal[i] = static_cast<int>(a[i]);
  for(;i<PLAYER_ORDERS_MAX_GOALS;i++)
    goal[i] = 0;
}

std::vector<Weapon> Ship::get_weapons(Array a,MultiMeshManager &multimeshes) {
  vector<Weapon> result;
  int s=a.size();
  for(int i=0;i<s;i++)
    result.emplace_back(static_cast<Dictionary>(a[i]),multimeshes);
  return result;
}

std::vector<std::shared_ptr<const Salvage>> Ship::get_salvage(Array a) {
  vector<std::shared_ptr<const Salvage>> result;
  int s=a.size();
  for(int i=0;i<s;i++) {
    result.emplace_back(make_shared<const Salvage>(static_cast<Dictionary>(a[i])));
  }
  return result;
}

PlayerOverrides::PlayerOverrides():
  manual_thrust(0),
  manual_rotation(0),
  orders(0),
  change_target(0),
  target_id(-1),
  goals()
{}

PlayerOverrides::PlayerOverrides(Dictionary from,const rid2id_t &rid2id):
  manual_thrust(get<real_t>(from,"manual_thrust")),
  manual_rotation(get<real_t>(from,"manual_rotation")),
  orders(get<int>(from,"orders")),
  change_target(get<int>(from,"change_target")),
  target_id(rid2id_default(rid2id,get<RID>(from,"target_rid").get_id(),-1)),
  goals(get<Array>(from,"goals"))
{}

PlayerOverrides::~PlayerOverrides() {}
