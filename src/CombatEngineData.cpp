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
  instance_id(get<RID>(dict,"instance_id")),
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
  s["instance_id"]=instance_id;
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
  max_angular_velocity(o.max_angular_velocity),
  threat(o.threat),
  max_shields(o.max_shields),
  max_armor(o.max_armor),
  max_structure(o.max_structure),
  heal_shields(o.heal_shields),
  heal_armor(o.heal_armor),
  heal_structure(o.heal_structure),
  aabb(o.aabb),
  radius(o.radius),
  collision_layer(o.collision_layer),
  enemy_mask(o.enemy_mask),
  range(o.range),
  explosion_damage(o.explosion_damage),
  explosion_radius(o.explosion_radius),
  explosion_impulse(o.explosion_impulse),
  explosion_delay(o.explosion_delay),
  explosion_tick(o.explosion_tick),
  fate(o.fate),
  shields(o.shields),
  armor(o.armor),
  structure(o.structure),
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
  target(o.target),
  threat_vector(o.threat_vector),
  nearby_objects(o.nearby_objects),
  nearby_enemies(o.nearby_enemies),
  nearby_enemies_tick(o.nearby_enemies_tick),
  nearby_enemies_range(o.nearby_enemies_range),
  random_state(o.random_state),
  destination(o.destination),
  aim_multiplier(o.aim_multiplier),
  confusion_multiplier(o.confusion_multiplier),
  confusion(o.confusion),
  confusion_velocity(o.confusion_velocity),
  max_speed(o.max_speed),
  turn_diameter_squared(o.turn_diameter_squared)
{}

Ship::Ship(Dictionary dict, object_id id, object_id &last_id,
           mesh2path_t &mesh2path,path2mesh_t &path2mesh):
  id(id),
  name(get<String>(dict,"name")),
  rid(get<RID>(dict,"rid")),
  thrust(get<real_t>(dict,"thrust")),
  reverse_thrust(get<real_t>(dict,"reverse_thrust",0)),
  max_angular_velocity(get<real_t>(dict,"turn_rate")),
  threat(get<real_t>(dict,"threat")),
  max_shields(get<real_t>(dict,"max_shields",0)),
  max_armor(get<real_t>(dict,"max_armor",0)),
  max_structure(get<real_t>(dict,"max_structure")),
  heal_shields(get<real_t>(dict,"heal_shields",0)),
  heal_armor(get<real_t>(dict,"heal_armor",0)),
  heal_structure(get<real_t>(dict,"heal_structure",0)),
  aabb(get<AABB>(dict,"aabb")),
  radius((aabb.size.x+aabb.size.z)/2.0),
  collision_layer(get<int>(dict,"collision_layer")),
  enemy_mask(get<int>(dict,"enemy_mask")),

  explosion_damage(get<real_t>(dict,"explosion_damage",0)),
  explosion_radius(get<real_t>(dict,"explosion_radius",0)),
  explosion_impulse(get<real_t>(dict,"explosion_impulse",0)),
  explosion_delay(get<int>(dict,"explosion_delay",0)),
  explosion_tick(0),
  
  fate(FATED_TO_FLY),
  //  turn_diameter(max_speed()*2.0/max_angular_velocity),

  shields(get<real_t>(dict,"shields",max_shields)),
  armor(get<real_t>(dict,"armor",max_armor)),
  structure(get<real_t>(dict,"structure",max_structure)),
  
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
  inverse_mass(1.0/get<real_t>(dict,"mass",1.0f)),
  inverse_inertia(get<Vector3>(dict,"inverse_inertia",Vector3(0,1,0))),
  transform(get<Transform>(dict,"transform")),
  
  weapons(get_weapons(get<Array>(dict,"weapons"),last_id,mesh2path,path2mesh)),
  range(make_ranges(weapons)),
  tick(0),
  tick_at_last_shot(TICKS_LONG_AGO),
  target(-1),
  threat_vector(),
  nearby_objects(), nearby_enemies(),
  nearby_enemies_tick(TICKS_LONG_AGO),
  nearby_enemies_range(0),
  random_state(bob_full_avalanche(id)),
  destination(randomize_destination()),

  aim_multiplier(1.0),
  confusion_multiplier(0.1),
  confusion(Vector3()),
  confusion_velocity(Vector3()),

  max_speed(max(thrust,reverse_thrust)/drag*inverse_mass),
  turn_diameter_squared(make_turn_diameter_squared())
{}

Ship::~Ship()
{}

void Ship::update_confusion() {
  bool is_firing = tick_at_last_shot+1 <= tick;
  aim_multiplier = 0.99*aim_multiplier + 0.01*(is_firing ? 0.5 : 2.0);
  if(confusion.x!=0 or confusion.y!=0)
    confusion_velocity -= 0.001*confusion.normalized();

  real_t random_angle = 2*PI*int2float(random_state=bob_full_avalanche(random_state));
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
  float x=int2float(random_state=bob_full_avalanche(random_state));
  float z=int2float(random_state=bob_full_avalanche(random_state));
  return destination=Vector3(100*(x-0.5),0,100*(z-0.5));
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
  // s["rotation"]=rotation;
  // s["position"]=position;
  // s["linear_velocity"]=linear_velocity;
  // s["mass"]=1.0/inverse_mass;
  // s["inverse_inertia"]=inverse_inertia;
  // s["transform"]=transform;
  s["name"]=name;
  s["rid"]=rid;
  // s["drag"]=drag;
  // s["thrust"]=thrust;
  // s["reverse_thrust"]=reverse_thrust;
  // s["turn_rate"]=max_angular_velocity;
  // s["threat"]=threat;
  s["shields"]=shields;
  s["armor"]=armor;
  s["structure"]=structure;
  s["max_shields"]=max_shields;
  s["max_armor"]=max_armor;
  s["max_structure"]=max_structure;
  // s["heal_shields"]=heal_shields;
  // s["heal_armor"]=heal_armor;
  // s["heal_structure"]=heal_structure;
  // s["aabb"]=aabb;
  s["radius"] = radius;
  // s["collision_layer"]=collision_layer;
  Dictionary r;
  {
    r["guns"]=range.guns;
    r["turrets"]=range.turrets;
    r["guided"]=range.guided;
    r["unguided"]=range.unguided;
    r["all"]=range.all;
  }
  s["ranges"]=r;
  // s["tick"]=tick;
  // s["tick_at_last_shot"]=tick_at_last_shot;
  s["destination"]=destination;
  // s["threat_vector"]=threat_vector;
  // s["confusion"]=confusion;

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

  // Array weapon_status;
  // for(auto &weapon : weapons)
  //   weapon_status.append(weapon.make_status_dict());
  // s["weapons"]=weapon_status;
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
