#include "CombatEngineData.hpp"
#include "CombatEngineUtils.hpp"

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

ProjectileMesh::ProjectileMesh(RID mesh_rid,object_id id):
  id(id),
  mesh_id(mesh_id),
  has_multimesh(false),
  multimesh_id(),
  instance_count(0),
  visible_instance_count(0)
{}

ProjectileMesh::~ProjectileMesh() {}

Projectile::Projectile(object_id id,const Ship &ship,const Weapon &weapon):
  id(id),
  target(ship.target),
  mesh_id(weapon.mesh_id),
  guided(weapon.guided),
  guidance_uses_velocity(weapon.guidance_uses_velocity),
  damage(weapon.damage),
  impulse(weapon.impulse),
  blast_radius(weapon.blast_radius),
  detonation_range(weapon.detonation_range),
  turn_rate(weapon.projectile_turn_rate),
  mass(weapon.projectile_mass),
  drag(weapon.projectile_drag),
  thrust(weapon.projectile_thrust),
  lifetime(weapon.projectile_lifetime),
  initial_velocity(weapon.initial_velocity),
  max_speed(weapon.terminal_velocity),
  position(ship.position + weapon.position.rotated(y_axis,ship.rotation.y)),
  collision_mask(ship.enemy_mask),
  linear_velocity(),
  rotation(),
  angular_velocity(),
  age(0),
  scale(1.0f),
  alive(true),
  direct_fire(weapon.direct_fire)
{
  rotation.y = ship.rotation.y;
  if(weapon.turn_rate>0)
    rotation.y += weapon.rotation.y;
  else if(!weapon.guided) {
    real_t estimated_range = weapon.projectile_lifetime*weapon.terminal_velocity;
    rotation.y += asin_clamp(weapon.position.z/estimated_range);
  }
  linear_velocity = initial_velocity * x_axis.rotated(y_axis,rotation.y) + ship.linear_velocity;
}

Projectile::Projectile(object_id id,const Ship &ship,const Weapon &weapon,Vector3 position,real_t scale,real_t rotation,object_id target):
  id(id),
  target(target),
  mesh_id(weapon.mesh_id),
  guided(weapon.guided),
  guidance_uses_velocity(weapon.guidance_uses_velocity),
  damage(weapon.damage),
  impulse(weapon.impulse),
  blast_radius(weapon.blast_radius),
  detonation_range(weapon.detonation_range),
  turn_rate(weapon.projectile_turn_rate),
  mass(weapon.projectile_mass),
  drag(weapon.projectile_drag),
  thrust(weapon.projectile_thrust),
  lifetime(weapon.projectile_lifetime),
  initial_velocity(weapon.initial_velocity),
  max_speed(weapon.terminal_velocity),
  position(position),
  collision_mask(-1),
  linear_velocity(),
  rotation(Vector3(0,rotation,0)),
  angular_velocity(),
  age(0),
  scale(scale),
  alive(true),
  direct_fire(weapon.direct_fire)
{}

Projectile::~Projectile() {}

object_id make_mesh_id(const String &path,object_id &last_id,mesh2path_t &mesh2path,path2mesh_t &path2mesh) {
  path2mesh_t::iterator it = path2mesh.find(path);
  if(it == path2mesh.end()) {
    object_id id = last_id++;
    path2mesh.emplace(path,id);
    mesh2path.emplace(id,path);
    return id;
  }
  return it->second;
}

Weapon::Weapon(Dictionary dict,object_id &last_id,
               mesh2path_t &mesh2path,
               path2mesh_t &path2mesh):
  damage(get<real_t>(dict,"damage")),
  impulse(get<real_t>(dict,"impulse")),
  initial_velocity(get<real_t>(dict,"initial_velocity")),
  projectile_mass(get<real_t>(dict,"projectile_mass")),
  projectile_drag(get<real_t>(dict,"projectile_drag")),
  projectile_thrust(get<real_t>(dict,"projectile_thrust")),
  projectile_lifetime(max(1.0f/60.0f,get<real_t>(dict,"projectile_lifetime"))),
  projectile_turn_rate(get<real_t>(dict,"projectile_turn_rate")),
  firing_delay(get<real_t>(dict,"firing_delay")),
  turn_rate(get<real_t>(dict,"turn_rate")),
  blast_radius(get<real_t>(dict,"blast_radius")),
  detonation_range(get<real_t>(dict,"detonation_range")),
  threat(get<real_t>(dict,"threat")),
  direct_fire(firing_delay<1e-5),
  guided(not direct_fire and get<bool>(dict,"guided")),
  guidance_uses_velocity(get<bool>(dict,"guidance_uses_velocity")),
  //  instance_id(get<RID>(dict,"instance_id")),
  mesh_id(make_mesh_id(get<String>(dict,"projectile_mesh_path"),last_id,mesh2path,path2mesh)),
  terminal_velocity((projectile_drag>0 and projectile_thrust>0) ? projectile_thrust/projectile_drag : initial_velocity),
  projectile_range(projectile_lifetime*terminal_velocity),
  node_path(get<NodePath>(dict,"node_path")),
  is_turret(turn_rate>1e-5),
  position(get<Vector3>(dict,"position")),
  rotation(get<Vector3>(dict,"rotation")),
  harmony_angle(asin_clamp(position.z/projectile_range)),
  firing_countdown(0)
{}

Weapon::~Weapon()
{}

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
  s["firing_delay"]=firing_delay;
  s["blast_radius"]=blast_radius;
  s["detonation_range"]=detonation_range;
  s["threat"]=threat;
  s["direct_fire"]=direct_fire;
  s["guided"]=guided;
  s["guidance_uses_velocity"]=guidance_uses_velocity;
  s["position"]=position;
  s["rotation"]=rotation;
  //  s["instance_id"]=instance_id;
  s["firing_countdown"]=firing_countdown;
  return s;
}

Planet::Planet(Dictionary dict,object_id id):
  id(id),
  rotation(get<Vector3>(dict,"rotation")),
  position(get<Vector3>(dict,"position")),
  transform(get<Transform>(dict,"transform")),
  name(get<String>(dict,"name")),
  rid(get<RID>(dict,"rid")),
  radius(get<real_t>(dict,"radius"))
{}

Planet::~Planet()
{}

Dictionary Planet::update_status(const unordered_map<object_id,Ship> &ships,
                                 const unordered_map<object_id,Planet> &planets) const {
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

WeaponRanges make_ranges(const vector<Weapon> &weapons) {
  WeaponRanges r = {0,0,0,0,0};
  
  for(auto &weapon : weapons) {
    real_t range = weapon.projectile_lifetime*weapon.terminal_velocity;
    if(weapon.turn_rate>0)
      r.turrets = max(r.turrets,range);
    else
      r.guns = max(r.guns,range);
    if(weapon.guided)
      r.guided = max(r.guided,range);
    else
      r.unguided = max(r.unguided,range);
  }
  r.all = max(r.guns,r.turrets);
  
  return r;
}

Ship::Ship(const Ship &o):
  id(o.id),
  name(o.name),
  rid(o.rid),
  thrust(o.thrust),
  reverse_thrust(o.reverse_thrust),
  turn_thrust(o.turn_thrust),
  threat(o.threat),
  max_shields(o.max_shields),
  max_armor(o.max_armor),
  max_structure(o.max_structure),
  max_fuel(o.max_fuel),
  heal_shields(o.heal_shields),
  heal_armor(o.heal_armor),
  heal_structure(o.heal_structure),
  heal_fuel(o.heal_fuel),
  fuel_efficiency(o.fuel_efficiency),
  aabb(o.aabb),
  turn_drag(o.turn_drag),
  radius(o.radius),
  empty_mass(o.empty_mass),
  cargo_mass(o.cargo_mass),
  fuel_density(o.fuel_density),
  armor_density(o.armor_density),
  collision_layer(o.collision_layer),
  enemy_mask(o.enemy_mask),
  team(o.team),
  enemy_team(o.enemy_team),
  range(o.range),
  explosion_damage(o.explosion_damage),
  explosion_radius(o.explosion_radius),
  explosion_impulse(o.explosion_impulse),
  explosion_delay(o.explosion_delay),
  explosion_tick(o.explosion_tick),
  fate(o.fate),
  entry_method(o.entry_method),
  shields(o.shields),
  armor(o.armor),
  structure(o.structure),
  fuel(o.fuel),
  rotation(o.rotation),
  position(o.position),
  linear_velocity(o.linear_velocity),
  angular_velocity(o.angular_velocity),
  heading(o.heading),
  drag(o.drag),
  inverse_mass(o.inverse_mass),
  inverse_inertia(o.inverse_inertia),
  transform(o.transform),
  weapons(o.weapons),
  tick(o.tick),
  tick_at_last_shot(o.tick_at_last_shot),
  tick_at_rift_start(o.tick_at_rift_start),
  target(o.target),
  threat_vector(o.threat_vector),
  nearby_objects(o.nearby_objects),
  nearby_enemies(o.nearby_enemies),
  nearby_enemies_tick(o.nearby_enemies_tick),
  nearby_enemies_range(o.nearby_enemies_range),
  rand(o.rand),
  destination(o.destination),
  aim_multiplier(o.aim_multiplier),
  confusion_multiplier(o.confusion_multiplier),
  confusion(o.confusion),
  confusion_velocity(o.confusion_velocity),
  max_speed(o.max_speed),
  max_angular_velocity(o.max_angular_velocity),
  turn_diameter_squared(o.turn_diameter_squared),
  updated_mass_stats(o.updated_mass_stats),
  immobile(o.immobile),
  inactive(o.inactive),
  visual_scale(o.visual_scale)
{}

Ship::Ship(Dictionary dict, object_id id, object_id &last_id,
           mesh2path_t &mesh2path,path2mesh_t &path2mesh):
  id(id),
  name(get<String>(dict,"name")),
  rid(get<RID>(dict,"rid")),
  thrust(get<real_t>(dict,"thrust")),
  reverse_thrust(get<real_t>(dict,"reverse_thrust",0)),
  turn_thrust(get<real_t>(dict,"turn_thrust",0)),
  threat(get<real_t>(dict,"threat")),
  max_shields(get<real_t>(dict,"max_shields",0)),
  max_armor(get<real_t>(dict,"max_armor",0)),
  max_structure(get<real_t>(dict,"max_structure")),
  max_fuel(get<real_t>(dict,"max_fuel")),
  heal_shields(get<real_t>(dict,"heal_shields",0)),
  heal_armor(get<real_t>(dict,"heal_armor",0)),
  heal_structure(get<real_t>(dict,"heal_structure",0)),
  heal_fuel(get<real_t>(dict,"heal_fuel",0)),
  fuel_efficiency(get<real_t>(dict,"fuel_efficiency",1.0)),
  aabb(get<AABB>(dict,"aabb")),
  turn_drag(get<real_t>(dict,"turn_drag")),
  radius((aabb.size.x+aabb.size.z)/2.0),
  empty_mass(get<real_t>(dict,"empty_mass",0)),
  cargo_mass(get<real_t>(dict,"cargo_mass",0)),
  fuel_density(get<real_t>(dict,"fuel_density",0)),
  armor_density(get<real_t>(dict,"armor_density",0)),
  team(clamp(get<int>(dict,"team"),0,1)),
  enemy_team(1-team),
  collision_layer(1<<team),
  enemy_mask(1<<enemy_team),
  
  explosion_damage(get<real_t>(dict,"explosion_damage",0)),
  explosion_radius(get<real_t>(dict,"explosion_radius",0)),
  explosion_impulse(get<real_t>(dict,"explosion_impulse",0)),
  explosion_delay(get<int>(dict,"explosion_delay",0)),
  explosion_tick(0),
  
  fate(FATED_TO_FLY),
  entry_method(static_cast<entry_t>(get<int>(dict,"entry_method",static_cast<int>(ENTRY_COMPLETE)))),
  //  turn_diameter(max_speed()*2.0/max_angular_velocity),

  shields(get<real_t>(dict,"shields",max_shields)),
  armor(get<real_t>(dict,"armor",max_armor)),
  structure(get<real_t>(dict,"structure",max_structure)),
  fuel(get<real_t>(dict,"fuel",max_fuel)),
  
  // These eight will be replaced by the PhysicsDirectBodyState every
  // timestep.  The GDScript code must make sure mass and drag are set
  // correctly in the RigidBody object before sending it to the
  // CombatEngine.
  rotation(get<Vector3>(dict,"rotation",Vector3(0,0,0))),
  position(get<Vector3>(dict,"position",Vector3(0,0,0))),
  linear_velocity(get<Vector3>(dict,"linear_velocity",Vector3(0,0,0))),
  angular_velocity(get<Vector3>(dict,"angular_velocity",Vector3(0,0,0))),
  heading(get_heading(*this)),
  drag(get<real_t>(dict,"drag")),
  inverse_mass(1.0/(empty_mass+cargo_mass+fuel*fuel_density/1000.0+armor*armor_density/1000.0)),
  inverse_inertia(get<Vector3>(dict,"inverse_inertia",Vector3(0,1,0))),
  transform(get<Transform>(dict,"transform")),
  
  weapons(get_weapons(get<Array>(dict,"weapons"),last_id,mesh2path,path2mesh)),
  range(make_ranges(weapons)),
  tick(0),
  tick_at_last_shot(TICKS_LONG_AGO),
  tick_at_rift_start(TICKS_LONG_AGO),
  target(-1),
  threat_vector(),
  nearby_objects(), nearby_enemies(),
  nearby_enemies_tick(TICKS_LONG_AGO),
  nearby_enemies_range(0),
  rand(),
  destination(randomize_destination()),

  aim_multiplier(1.0),
  confusion_multiplier(0.1),
  confusion(Vector3()),
  confusion_velocity(Vector3()),

  max_speed(0),
  max_angular_velocity(0),
  turn_diameter_squared(0),
  updated_mass_stats(false),
  immobile(false),
  inactive(false),
  visual_scale(1.0)
{
  if(not (drag<999999 and drag>1e-6))
    Godot::print(String("New ship has an invalid drag ")+String(Variant(drag)));
  if(not (inverse_mass<999999))
    Godot::print(String("New ship has an invalid inverse mass ")+String(Variant(inverse_mass)));
  if(not (turn_drag<999999 and turn_drag>1e-6))
    Godot::print(String("New ship has an invalid turn drag ")+String(Variant(turn_drag)));
  if(not (thrust<999999 and thrust>=0))
    Godot::print(String("New ship has an invalid thrust ")+String(Variant(thrust)));
  if(not (reverse_thrust<999999 and reverse_thrust>=0))
    Godot::print(String("New ship has an invalid reverse_thrust ")+String(Variant(reverse_thrust)));
  max_speed = max(thrust,reverse_thrust)/drag*inverse_mass;
  if(not (max_speed<999999 and max_speed>=0))
    Godot::print(String("New ship's calculated max speed is invalid ")+String(Variant(max_speed)));
  max_angular_velocity = turn_thrust/turn_drag*inverse_mass*PI/30.0f; // convert from RPM
  turn_diameter_squared = make_turn_diameter_squared();
}

Ship::~Ship()
{}

bool Ship::update_from_physics_server(PhysicsServer *physics_server) {
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
  
  update_stats(physics_server,false);
  return true;
}

void Ship::update_stats(PhysicsServer *physics_server,bool update_server) {
  real_t new_mass = empty_mass+cargo_mass;
  if(max_fuel>=.001)
    fuel*clamp(fuel_density/max_fuel,0.0f,1.0f);
  if(max_armor>=.001)
    armor*clamp(armor_density/max_armor,0.0f,1.0f);
  real_t old_mass = 1.0/inverse_mass;
  inverse_mass = 1.0f/new_mass;
  drag_force = -linear_velocity*drag/inverse_mass;
  max_speed = max(thrust,reverse_thrust)/drag*inverse_mass;
  max_angular_velocity = turn_thrust/turn_drag*inverse_mass*PI/30.0f;
  turn_diameter_squared = make_turn_diameter_squared();

  if(fabsf(new_mass-old_mass)>0.01f)
    physics_server->body_set_param(rid,PhysicsServer::BODY_PARAM_MASS,1.0/inverse_mass);
  updated_mass_stats = false;
}

void Ship::heal(bool hyperspace,real_t system_fuel_recharge,real_t center_fuel_recharge,real_t delta) {
  shields = min(shields+heal_shields*delta,max_shields);
  armor = min(armor+heal_armor*delta,max_armor);
  structure = min(structure+heal_structure*delta,max_structure);

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
  bool is_firing = tick_at_last_shot+1 <= tick;
  aim_multiplier = 0.99*aim_multiplier + 0.01*(is_firing ? 0.5 : 2.0);
  if(confusion.x!=0 or confusion.y!=0)
    confusion_velocity -= 0.001*confusion.normalized();

  real_t random_angle = rand.rand_angle();
  Vector3 random_unit = Vector3(cos(random_angle),0,-sin(random_angle));
  
  confusion_velocity = 0.99*(confusion_velocity + 0.01*random_unit);
  confusion = 0.999*(confusion+confusion_velocity*(confusion_multiplier*aim_multiplier));
}

real_t Ship::take_damage(real_t damage) {
  real_t taken;
  
  if(fate!=FATED_TO_FLY)
    return damage; // already dead or leaving, so cannot take more damage
  
  if(damage>0) {
    taken=min(shields,damage);
    damage-=taken;
    shields-=taken;
    
    if(damage>0) {
      taken=min(armor,damage);
      damage-=taken;
      armor-=taken;
      updated_mass_stats=true;
      
      if(damage>0) {
        taken=min(structure,damage);
        damage-=taken;
        structure-=taken;
      }
    }
  }

  if(structure<=0) {
    explosion_tick = tick+explosion_delay;
    fate = (explosion_tick>tick) ? FATED_TO_EXPLODE : FATED_TO_DIE;
  }
  
  return damage;
}

Vector3 Ship::randomize_destination() {
  float x=rand.randf();
  float z=rand.randf();
  return destination=Vector3(100*(x-0.5),0,100*(z-0.5));
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

std::vector<Weapon> Ship::get_weapons(Array a,object_id &last_id,
                                      mesh2path_t &mesh2path, path2mesh_t &path2mesh) {
  vector<Weapon> result;
  int s=a.size();
  for(int i=0;i<s;i++)
    result.emplace_back(static_cast<Dictionary>(a[i]),last_id,mesh2path,path2mesh);
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

VisibleObject::VisibleObject(const Ship &ship):
  x(ship.position.x),
  z(ship.position.z),
  radius((ship.aabb.size.x+ship.aabb.size.z)/2.0),
  rotation_y(ship.rotation.y),
  vx(ship.linear_velocity.x),
  vz(ship.linear_velocity.z),
  max_speed(ship.max_speed),
  flags(VISIBLE_OBJECT_SHIP | (ship.enemy_mask&PLAYER_COLLISION_LAYER_BITS ? VISIBLE_OBJECT_HOSTILE : 0))
{}

VisibleObject::VisibleObject(const Planet &planet):
  x(planet.position.x),
  z(planet.position.z),
  radius(planet.radius),
  rotation_y(0),
  vx(0),
  vz(0),
  max_speed(0),
  flags(VISIBLE_OBJECT_PLANET)
{}

VisibleProjectile::VisibleProjectile(const Projectile &projectile):
  rotation_y(projectile.rotation.y),
  scale_x(projectile.direct_fire ? projectile.scale : 0),
  center(projectile.position.x,projectile.position.z),
  half_size(projectile.direct_fire ? Vector2(projectile.scale,projectile.scale) : Vector2(0.1f,0.1f)),
  type(VISIBLE_OBJECT_PROJECTILE),
  mesh_id(projectile.mesh_id)
{}

MeshInfo::MeshInfo(object_id id, const String &resource_path):
  id(id),
  resource_path(resource_path),
  mesh_resource(),
  mesh_rid(), multimesh_rid(), visual_rid(),
  instance_count(0),
  visible_instance_count(0),
  last_tick_used(0),
  invalid(false),
  floats()
{}

MeshInfo::~MeshInfo() {
  bool have_multimesh = not multimesh_rid.is_valid();
  bool have_visual = not visual_rid.is_valid();
  if(have_multimesh or have_visual) {
    VisualServer *server=VisualServer::get_singleton();
    if(have_visual)
      server->free_rid(visual_rid);
    if(have_multimesh)
      server->free_rid(multimesh_rid);
  }
}
  
VisibleContent::VisibleContent():
  ships_and_planets(),
  projectiles(),
  mesh_paths(),
  next(nullptr)
{}

VisibleContent::~VisibleContent() {}
