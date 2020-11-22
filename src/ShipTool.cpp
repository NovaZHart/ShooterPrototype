#include "ShipTool.hpp"

#include <cmath>
#include <algorithm>

#include <Array.hpp>
#include <PhysicsDirectSpaceState.hpp>
#include <GodotGlobal.hpp>

const double FAST = 1e6;
const double PI = 3.141592653589793;

using namespace godot;
using namespace std;

void ShipTool::_register_methods() {
  register_method("guide_RigidProjectile", &ShipTool::guide_RigidProjectile);
  register_method("guide_AreaProjectile", &ShipTool::guide_AreaProjectile);

  register_method("request_move_to_attack", &ShipTool::request_move_to_attack);
  register_method("auto_fire", &ShipTool::auto_fire);
  register_method("auto_target", &ShipTool::auto_target);
  register_method("request_rotation", &ShipTool::request_rotation);
  register_method("request_primary_fire", &ShipTool::request_primary_fire);
  register_method("make_threat_vector", &ShipTool::make_threat_vector);
  register_method("request_thrust", &ShipTool::request_thrust);

  // These are overloaded. Only the RigidBody version should be sent to Godot
  typedef void (ShipTool::*t_request_heading)(RigidBody*,PhysicsDirectBodyState*,Vector3);
  t_request_heading f_request_heading = &ShipTool::request_heading;
  register_method("request_heading", f_request_heading);

  typedef bool (ShipTool::*t_move_to_intercept)(RigidBody*,PhysicsDirectBodyState*,double,double,Vector3,Vector3,bool,bool);
  t_move_to_intercept f_move_to_intercept = &ShipTool::move_to_intercept;
  register_method("move_to_intercept", f_move_to_intercept);
}

ShipTool::ShipTool() {}
ShipTool::~ShipTool() {}
void ShipTool::_init() {}

////////////////////////////////////////////////////////////////////////

// FIXME: These calls should be reduced to a few template functions
// using variable-length argument lists.

template<class R>
static R cast_2arg(Variant &v,const char *method,const Variant &arg1,const Variant &arg2) {
  const Variant *args[3] = {&arg1,&arg2,nullptr};
  Variant vv=v.call(method,args,2);
  return static_cast<R>(vv);
}

template<class R,class T>
static R cast_2arg(T &v,const char *method,const Variant &arg1,const Variant &arg2) {
  Variant vv=v->call(method,Array::make(arg1,arg2));
  return static_cast<R>(vv);
}

template<class R>
static R cast_1arg(Variant &v,const char *method,const Variant &arg) {
  const Variant *args[2] = {&arg,nullptr};
  Variant vv=v.call(method,args,1);
  return static_cast<R>(vv);
}

template<class R,class T>
static R cast_1arg(T &v,const char *method,const Variant &arg) {
  Variant vv=v->call(method,Array::make(arg));
  return static_cast<R>(vv);
}

static void call_1arg(Variant &v,const char *method,const Variant &arg) {
  const Variant *args[2] = {&arg,nullptr};
  v.call(method,args,1);
}

template<class T>
static void call_1arg(T &v,const char *method,const Variant &arg) {
  v->call(method,Array::make(arg));
}

template<class R>
static R cast_0arg(Variant &v,const char *method) {
  const Variant *args[1] = {nullptr};
  Variant vv=v.call(method,args,0);
  return static_cast<R>(vv);
}

template<class R,class T>
static R cast_0arg(T &v,const char *method) {
  Variant vv=v->call(method);
  return static_cast<R>(vv);
}

////////////////////////////////////////////////////////////////////////

template<class T>
static Vector3 position_now(const T *ship) {
  Vector3 here=ship->get_translation();
  return Vector3(here[0],0,here[2]);
}

static Vector3 position_now(const Area &projectile) {
  Vector3 here=projectile.get_translation();
  return Vector3(here[0],0,here[2]);
}

static Vector3 position_at_time(const RigidBody *ship,double t) {
  return position_now(ship) + t*ship->get_linear_velocity();
}

template<class T>
static Vector3 get_heading(const T &spatial) {
  return Vector3(1,0,0).rotated(Vector3(0,1,0),spatial->get_rotation()[1]);
}

static bool is_nil(const Variant &v) {
  return v.get_type() == Variant::NIL;
}

Vector3 ShipTool::make_threat_vector(RigidBody *ship, Array near_objects,
                                     double shape_radius, double t) {
  Vector3 my_position = position_at_time(ship,t);
  Vector2 threat_vector;
  double dw_div = 0;
  for(int i=0;i<near_objects.size();i++) {
    Variant dict_obj = near_objects[i];
    if(is_nil(dict_obj))
      continue;
    Dictionary dict=dict_obj;
    Variant object = dict["collider"];
    if(is_nil(object))
      continue;
    Vector3 obj_pos = cast_1arg<Vector3>(object,"position_at_time",t);
    Vector2 position(obj_pos[0] - my_position[0], obj_pos[2] - my_position[2]);
    double threat = cast_1arg<double>(object,"threat_at_time",t);
    double distance = position.length();
    double distance_weight = max(0.0,(shape_radius-distance)/shape_radius);
    double weight = distance_weight*threat;
    dw_div += distance_weight;
    threat_vector += weight * position.normalized();
  }
  return Vector3(threat_vector[0],0,threat_vector[1])/max(1.0,dw_div);
}

Vector3 ShipTool::aim_forward(RigidBody *ship, PhysicsDirectBodyState *state,
                              RigidBody *target) {
  Vector3 aim;
  Vector3 my_pos=position_now(ship), tgt_pos=position_now(target);
  Vector3 dp_ships = tgt_pos - my_pos;
  Vector3 dv = target->get_linear_velocity() - state->get_linear_velocity();
  Array children = ship->get_children();
  for(int i=0;i<children.size();i++) {
    Variant child = children[i];
    if(!child.has_method("is_a_turret") || cast_0arg<bool>(child,"is_a_turret"))
      continue;
    Spatial *weapon(child);
    if(!weapon)
      continue;
    Vector3 dp = dp_ships - position_now(weapon).rotated(Vector3(0,1,0),ship->get_rotation()[1]);
    double t = rendezvous_time(dp,dv,cast_0arg<double>(weapon,"get_projectile_speed"));
    if(isnan(t))
      return tgt_pos - my_pos;
    t = min(t,cast_0arg<double>(weapon,"get_projectile_lifetime"));
    aim += (dp+t*dv)*cast_1arg<double>(weapon,"threat_at_time",0.0);
  }
  return !aim.length() ? tgt_pos-my_pos : aim.normalized();
}

Vector3 ShipTool::stopping_point(RigidBody *ship,PhysicsDirectBodyState *state,Vector3 tgt_vel, bool &should_reverse) {
  should_reverse = false;

  Vector3 pos = position_now(ship);
  Vector3 rel_vel = state->get_linear_velocity() - tgt_vel;
  Vector3 heading = get_heading(ship);
  double speed = rel_vel.length();
  double accel = cast_0arg<double>(ship,"get_thrust")*state->get_inverse_mass();
  double reverse_accel = cast_0arg<double>(ship,"get_reverse_thrust")*state->get_inverse_mass();
  
  if(speed<=0)
    return pos;

  double max_angular_velocity = cast_0arg<double>(ship,"get_max_angular_velocity");
  double turn = acos(clamp(static_cast<double>(-rel_vel.normalized().dot(heading)),-1.0,1.0));
  double dist = speed*turn/max_angular_velocity + 0.5*speed*speed/accel;
  if(reverse_accel>1e-5) {
    double rev_dist = speed*(PI-turn)/max_angular_velocity + 0.5*speed*speed/reverse_accel;
    if(rev_dist < dist) {
      should_reverse = true;
      dist = rev_dist;
    }
  }
  
  return pos+dist*rel_vel.normalized();
}

Vector3 ShipTool::stopping_point_unlimited_thrust(RigidBody *ship,PhysicsDirectBodyState *state,Vector3 tgt_vel) {
  Vector3 pos = position_now(ship);
  Vector3 rel_vel = state->get_linear_velocity() - tgt_vel;
  Vector3 heading = get_heading(ship);
  double speed = rel_vel.length();
  
  if(speed<=0)
    return pos;

  double max_angular_velocity = cast_0arg<double>(ship,"get_max_angular_velocity");
  double turn = acos(clamp(static_cast<double>(-rel_vel.normalized().dot(heading)),-1.0,1.0));
  double dist = speed*turn/max_angular_velocity;
  
  return pos+dist*rel_vel.normalized();
}

double ShipTool::rendezvous_time(Vector3 target_location,Vector3 target_velocity, double interceptor_speed) {
  double a = target_velocity.dot(target_velocity) - interceptor_speed*interceptor_speed;
  double b = 2.0 * target_location.dot(target_velocity);
  double c = target_location.dot(target_location);
  double descriminant = b*b - 4*a*c;
	
  if(descriminant<0 or fabs(a)<1e-4)
    return nan("");
	
  double d1 = (-b + descriminant)/(2.0*a);
  double d2 = (-b - descriminant)/(2.0*a);
  double mn = min(d1,d2);
  double mx = max(d1,d2);

  if(mn>0)
    return mn;
  else if(mx>0)
    return mx;
  return nan("");
}

void ShipTool::request_move_to_attack(RigidBody *ship, PhysicsDirectBodyState *state, RigidBody *target) {
  move_to_attack(ship,state,target);
  auto_target(ship,state,target);
}

void ShipTool::auto_fire(RigidBody *ship,PhysicsDirectBodyState *state, RigidBody *target) {
  if (!cast_0arg<bool>(target,"is_a_ship")) {
    request_primary_fire(ship,state);
    return;
  }
  Vector3 aim = aim_forward(ship,state,target).normalized();
  request_heading(ship,state,aim);
  request_primary_fire(ship,state);
}

Dictionary ShipTool::check_target_lock(RigidBody *ship, PhysicsDirectBodyState *state, Vector3 point1,
                                       Vector3 point2, RigidBody *target) {
  target->set_collision_mask(target->get_collision_mask() | (1<<30));
  PhysicsDirectSpaceState *space = state->get_space_state();
  Dictionary result = space->intersect_ray(point1, point2, Array());
  target->set_collision_mask(target->get_collision_mask() ^ (1<<30));
  return result;
}

void ShipTool::auto_target(RigidBody *ship, PhysicsDirectBodyState *state, RigidBody *target) {
  if(!target->has_method("is_a_ship"))
    return;
  if(!cast_0arg<bool>(target,"is_a_ship"))
    return;

  Vector3 heading = get_heading(ship);
  Vector3 p = position_now(target);
  Vector3 dv_ship = target->get_linear_velocity() - state->get_linear_velocity();
  Vector3 dp_ship = p - position_now(ship) + dv_ship*state->get_step();
  Array children = ship->get_children();
  for(int i=0;i<children.size();i++) {
    Variant child = children[i];
    if(!child.has_method("is_a_turret")) // || cast_0arg<bool>(child,"is_a_turret"))
      continue;
    Spatial *weapon(child);
    if(!weapon)
      continue;
    Vector3 p_weapon = position_now(weapon).rotated(Vector3(0,1,0),ship->get_rotation()[1]);
    p_weapon[1]=5;
    Vector3 dp = dp_ship - p_weapon;
    Vector3 dv = heading*cast_0arg<double>(weapon,"get_projectile_speed") - dv_ship;
    dv *= cast_0arg<double>(weapon,"get_projectile_lifetime");
    Vector3 point1 = dp-dv+p;
    Vector3 point2 = dp+p;
    point1[1]=5;
    point2[1]=5;
    Dictionary result = check_target_lock(ship,state,point1,point2,target);
    if(!result.empty()) {
      request_primary_fire(ship,state);
      return;
    }
  }
}

void ShipTool::move_to_attack(RigidBody *ship, PhysicsDirectBodyState *state, RigidBody *target) {
  Vector3 heading = get_heading(ship);
  Vector3 dp = position_now(target) - position_now(ship);
  Variant weapon = cast_2arg<Variant>(ship,"get_first_weapon_or_null",true,true);
  if(is_nil(weapon))
    return;
  Vector3 aim = aim_forward(ship,state,target);
  request_heading(ship,state,aim.normalized());
	
  // Get the circle the ship would make while turning at maximum speed:
  double full_turn_time = 2*PI / cast_0arg<double>(ship,"get_max_angular_velocity");
  double turn_circumference = full_turn_time * cast_0arg<double>(ship,"get_max_speed");
  double turn_diameter = max(turn_circumference/PI,5.0);
	
  // Heuristic; needs improvement
  if(heading.dot(dp)>=0 && dp.length()>turn_diameter ||
     state->get_linear_velocity().dot(dp)<0 && heading.dot(dp.normalized())>0.9)
    request_thrust(ship,state,1.0,0.0);
}

bool ShipTool::move_to_intercept(RigidBody *ship, PhysicsDirectBodyState *state,double close, double slow,
                                 Vector3 tgt_pos, Vector3 tgt_vel,
                                 bool force_final_state,bool unlimited_thrust) {
  const double small_dot_product = 0.8;
  Vector3 position = position_now(ship);
  Vector3 heading = get_heading(ship);
  Vector3 tgt_pos1(tgt_pos[0],0,tgt_pos[2]);
  Vector3 dp = tgt_pos1 - position;
  Vector3 dv = tgt_vel - state->get_linear_velocity();
  double speed = dv.length();
  bool is_close = dp.length()<close;
  if(is_close && speed<slow) {
    if(force_final_state) {
      state->set_linear_velocity(tgt_vel);
    }
    return true;
  }
  bool should_reverse = false;
  if(unlimited_thrust)
    dp = tgt_pos1 - stopping_point_unlimited_thrust(ship, state, tgt_vel);
  else
    dp = tgt_pos1 - stopping_point(ship, state, tgt_vel, should_reverse);
  Vector3 dp_dir = dp.normalized();
  double dot = dp_dir.dot(heading);
  bool is_facing = dot > small_dot_product;
  if(unlimited_thrust || !is_close || (!is_facing && !should_reverse))
    request_heading(ship,state,dp_dir);
  else
    state->set_angular_velocity(Vector3(0,0,0));
  if(unlimited_thrust)
    velocity_to_heading(ship,state);
  else
    request_thrust(ship,state,double(is_facing),double(should_reverse && ! is_facing));
  return false;
}

void ShipTool::velocity_to_heading(RigidBody *projectile, PhysicsDirectBodyState *state) {
  // Projectiles always move in the direction they're pointing and never reduce speed.
  double step = state->get_step();
  Vector3 old_vel = state->get_linear_velocity();
  double max_speed = cast_0arg<double>(projectile,"get_max_speed");
  double invmass = state->get_inverse_mass();
  double next_speed = min(max_speed,old_vel.length()+cast_0arg<double>(projectile,"get_thrust")*invmass*step);
  double rotation = projectile->get_rotation()[1] + step*state->get_angular_velocity()[1];
  Vector3 new_vel = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation)*next_speed;
  Vector3 accel = (new_vel-old_vel)/step;
  state->add_central_force(accel/invmass);
}

void ShipTool::guide_RigidProjectile(RigidBody *projectile, PhysicsDirectBodyState *state,
                                     RigidBody *target, bool use_velocity) {
  double step = state->get_step();
  double max_speed = cast_0arg<double>(projectile,"get_max_speed");

  Vector3 velocity = projectile->get_linear_velocity();
  double speed = velocity.length();
  if(speed>max_speed)
    state->add_central_force(-0.1*speed*velocity);

  double max_angular_velocity = cast_0arg<double>(projectile,"get_max_angular_velocity");
  double accel = cast_0arg<double>(projectile,"get_thrust")*state->get_inverse_mass();
  if(accel<1e-5)
    return;
  Vector3 dp = position_now(target) - position_now(projectile);
  Vector3 dp_norm = dp.normalized();
  if(max_speed<1e-5)
    return;
  double intercept_time = dp.length()/max_speed;
  Vector3 heading=get_heading(projectile);
  bool is_facing_away = dp.dot(heading);
  if(use_velocity) {
    // Turn towards interception point based on target velocity.
    Vector3 tgt_vel = target->get_linear_velocity();
    if(dp_norm.dot(tgt_vel)<0) {
      // Target is moving towards projectile.
      Vector3 normal(dp_norm[2],0,-dp_norm[0]);
      double norm_tgt_vel = normal.dot(tgt_vel);
      double len = sqrt(max(0.0,max_speed*max_speed-norm_tgt_vel*norm_tgt_vel));
      dp = len*dp_norm + norm_tgt_vel*normal;
    } else {
      // Target is moving away from projectile.
      dp += intercept_time*tgt_vel;
      intercept_time = dp.length()/max_speed;
    }
    dp_norm=dp.normalized();
  }

  double cross = heading.cross(dp_norm)[1];
  double want_angular_velocity = asin(clamp(cross,-1.0,1.0));
  double actual_angular_velocity = want_angular_velocity;
  if(fabs(want_angular_velocity)>max_angular_velocity)
    actual_angular_velocity=copysign(max_angular_velocity,want_angular_velocity);

  state->set_angular_velocity(Vector3(0,actual_angular_velocity,0));
  velocity_to_heading(projectile,state);
}

void ShipTool::request_heading(RigidBody *ship, PhysicsDirectBodyState *state, Vector3 new_heading) {
  Vector3 new_normed = new_heading.normalized();
  Vector3 heading = get_heading(ship);
  double cross = -new_normed.cross(heading)[1];

  if(new_normed.dot(heading)>0) {
    double angle = asin(min(1.0,max(-1.0,cross/new_normed.length())));
    double actual_av = copysign(1.0,angle)*min(fabs(angle)/state->get_step(),cast_0arg<double>(ship,"get_max_angular_velocity"));
    state->set_angular_velocity(Vector3(0,actual_av,0));
  } else {
    double left = static_cast<double>(cross >= 0.0);
    double right = static_cast<double>(cross < 0.0);
    state->set_angular_velocity(Vector3(0,(left-right)*cast_0arg<double>(ship,"get_max_angular_velocity"),0));
  }
}

void ShipTool::request_rotation(RigidBody *ship, PhysicsDirectBodyState *state, double rotate) {
  if(fabs(rotate)>1e-3)
    state->add_torque(Vector3(0,rotate*cast_0arg<double>(ship,"get_rotation_torque"),0));
  else
    state->set_angular_velocity(Vector3(0,0,0));
}

void ShipTool::request_thrust(RigidBody *ship, PhysicsDirectBodyState *state,double forward,double reverse) {
  double ai_thrust = cast_0arg<double>(ship,"get_thrust")*min(1.0,fabs(forward)) - cast_0arg<double>(ship,"get_reverse_thrust")*min(1.0,fabs(reverse));
  Vector3 v_thrust = Vector3(ai_thrust,0,0).rotated(Vector3(0,1,0),ship->get_rotation().y);
  state->add_central_force(v_thrust);
}

void ShipTool::request_primary_fire(RigidBody *ship, PhysicsDirectBodyState *state) {
  call_1arg(ship,"set_ai_shoot",true);
}



////////////////////////////////////////////////////////////////////////



void ShipTool::guide_AreaProjectile(Area *projectile, double delta,
                                    RigidBody *target, bool use_velocity) {
  double max_speed = cast_0arg<double>(projectile,"get_max_speed");
  double max_angular_velocity = cast_0arg<double>(projectile,"get_max_angular_velocity");
  Vector3 dp = position_now(target) - position_now(projectile);
  Vector3 dp_norm = dp.normalized();
  double intercept_time = dp.length()/max_speed;
  Vector3 heading=get_heading(projectile);
  bool is_facing_away = dp.dot(heading)<0.0;
  if(use_velocity && intercept_time>0.5) {
    // Turn towards interception point based on target velocity.
    Vector3 tgt_vel = target->get_linear_velocity();
    if(dp_norm.dot(tgt_vel)<0) {
      // Target is moving towards projectile.
      Vector3 normal(dp_norm[2],0,-dp_norm[0]);
      double norm_tgt_vel = normal.dot(tgt_vel);
      double len = sqrt(max(0.0,max_speed*max_speed-norm_tgt_vel*norm_tgt_vel));
      dp = len*dp_norm + norm_tgt_vel*normal;
    } else {
      // Target is moving away from projectile.
      dp += intercept_time*tgt_vel;
      intercept_time = dp.length()/max_speed;
    }
    dp_norm=dp.normalized();
  }

  double cross = heading.cross(dp_norm)[1];
  double want_angular_velocity = asin(clamp(cross,-1.0,1.0));
  double actual_angular_velocity = want_angular_velocity;
  if(fabs(want_angular_velocity)>max_angular_velocity)
    actual_angular_velocity=copysign(max_angular_velocity,want_angular_velocity);

  call_1arg(projectile,"set_angular_velocity",Vector3(0,actual_angular_velocity,0));
  velocity_to_heading(projectile,delta);
}

void ShipTool::velocity_to_heading(Area *projectile, double delta) {
  // Projectiles always move in the direction they're pointing and never reduce speed.
  Vector3 old_vel = cast_0arg<Vector3>(projectile,"get_linear_velocity");
  double max_speed = cast_0arg<double>(projectile,"get_max_speed");
  double invmass = 1.0/cast_0arg<double>(projectile,"get_mass");
  double next_speed = min(max_speed,old_vel.length()
                          + cast_0arg<double>(projectile,"get_thrust")*invmass*delta);
  double rotation = projectile->get_rotation()[1]
    + delta*cast_0arg<Vector3>(projectile,"get_angular_velocity")[1];
  call_1arg(projectile,"set_linear_velocity",
            Vector3(1,0,0).rotated(Vector3(0,1,0),rotation)*next_speed);
}
