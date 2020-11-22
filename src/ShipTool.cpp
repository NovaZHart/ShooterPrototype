#include "ShipTool.hpp"

#include <cmath>
#include <algorithm>

#include <Array.hpp>
#include <PhysicsDirectSpaceState.hpp>

const double PI = 3.141592653589793;

using namespace godot;
using namespace std;

void ShipTool::_register_methods() {
  register_method("request_move_to_attack", &ShipTool::request_move_to_attack);
  register_method("auto_fire", &ShipTool::auto_fire);
  register_method("auto_target", &ShipTool::auto_target);
  register_method("request_rotation", &ShipTool::request_rotation);
  register_method("request_thrust", &ShipTool::request_thrust);
  register_method("request_primary_fire", &ShipTool::request_primary_fire);
  register_method("make_threat_vector", &ShipTool::make_threat_vector);

  register_method("request_heading", &ShipTool::request_heading); // bad
  register_method("move_to_intercept", &ShipTool::move_to_intercept); // bad
}

ShipTool::ShipTool() {}
ShipTool::~ShipTool() {}
void ShipTool::_init() {}

static bool is_nil(const Variant &v) {
  return v.get_type() == Variant::NIL;
}

static double double_2arg(Variant &v,const char *method,const Variant &arg1,const Variant &arg2) {
  const Variant *args[3] = {&arg1,&arg2,nullptr};
  Variant vv=v.call(method,args,1);
  return static_cast<double>(vv);
}

static double double_2arg(Object *v,const char *method,const Variant &arg1,const Variant &arg2) {
  Variant vv=v->call(method,Array::make(arg1,arg2));
  return static_cast<double>(vv);
}

static double double_1arg(Variant &v,const char *method,const Variant &arg) {
  const Variant *args[2] = {&arg,nullptr};
  Variant vv=v.call(method,args,1);
  return static_cast<double>(vv);
}

static double double_1arg(Object *v,const char *method,const Variant &arg) {
  Variant vv=v->call(method,Array::make(arg));
  return static_cast<double>(vv);
}

static double double_0arg(Variant &v,const char *method) {
  const Variant *args[1] = {nullptr};
  Variant vv=v.call(method,args,0);
  return static_cast<double>(vv);
}

static double double_0arg(Object *v,const char *method) {
  Variant vv=v->call(method);
  return static_cast<double>(vv);
}

static bool bool_0arg(Variant &v,const char *method) {
  const Variant *args[1] = {nullptr};
  Variant vv=v.call(method,args,0);
  return static_cast<bool>(vv);
}

static bool bool_0arg(Object *v,const char *method) {
  Variant vv=v->call(method);
  return static_cast<bool>(vv);
}

static Variant call_2arg(Variant &v,const char *method,const Variant &arg1,const Variant &arg2) {
  const Variant *args[3] = {&arg1,&arg2,nullptr};
  return v.call(method,args,1);
}

static Variant call_2arg(Object *v,const char *method,const Variant &arg1,const Variant &arg2) {
  return v->call(method,Array::make(arg1,arg2));
}

static Variant call_1arg(Variant &v,const char *method,const Variant &arg) {
  const Variant *args[2] = {&arg,nullptr};
  return v.call(method,args,1);
}

static Variant call_1arg(Object *v,const char *method,const Variant &arg) {
  return v->call(method,Array::make(arg));
}

static Variant call_0arg(Variant &v,const char *method) {
  const Variant *args[1] = {nullptr};
  return v.call(method,args,0);
}

static Variant call_0arg(Object *v,const char *method) {
  return v->call(method);
}

static Vector3 position_now(const RigidBody *ship) {
  Vector3 here=ship->get_translation();
  return Vector3(here[0],0,here[2]);
}

static Vector3 position_at_time(const RigidBody *ship,double t) {
  return position_now(ship) + t*ship->get_linear_velocity();
}
static Vector3 position_at_time(const RigidBody *ship,PhysicsDirectBodyState *state,double t) {
  return position_now(ship) + t*state->get_linear_velocity();
}

static Vector3 get_heading(const RigidBody *ship) {
  return Vector3(1,0,0).rotated(Vector3(0,1,0),ship->get_rotation()[1]);
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
    Vector3 obj_pos = call_1arg(object,"position_at_time",t);
    Vector2 position(obj_pos[0] - my_position[0], obj_pos[2] - my_position[2]);
    double threat = call_1arg(object,"threat_at_time",t);
    double distance = position.length();
    double distance_weight = max(0.0,(shape_radius-distance)/shape_radius);
    double weight = distance_weight*threat;
    dw_div += distance_weight;
    threat_vector += weight * position.normalized();
  }
  return Vector3(threat_vector[0],0,threat_vector[1])/max(1.0,dw_div);
}

Vector3 ShipTool::aim_forward(RigidBody *ship, Variant &weapon, PhysicsDirectBodyState *state,
                                     RigidBody *target) {
  if(is_nil(weapon))
    return Vector3();
  Vector3 my_pos=position_now(ship), tgt_pos=position_now(target);
  Vector3 dp = tgt_pos - my_pos;
  Vector3 dv = target->get_linear_velocity() - state->get_linear_velocity();
  double t = rendezvous_time(dp,dv,call_0arg(weapon,"get_projectile_speed"));
  if(isnan(t))
    return tgt_pos - my_pos;
  t = min(t,double_0arg(weapon,"get_projectile_lifetime"));
  return dp + t*dv;
}
Vector3 ShipTool::stopping_point(RigidBody *ship,PhysicsDirectBodyState *state,Vector3 tgt_vel, bool &should_reverse) {
  should_reverse = false;

  Vector3 pos = position_now(ship);
  Vector3 rel_vel = state->get_linear_velocity() - tgt_vel;
  Vector3 heading = get_heading(ship);
  double speed = rel_vel.length();
  double accel = double_0arg(ship,"get_thrust")*state->get_inverse_mass();
  double reverse_accel = double_0arg(ship,"get_reverse_thrust")*state->get_inverse_mass();
  
  if(speed<=0)
    return pos;

  double max_angular_velocity = call_0arg(ship,"get_max_angular_velocity");
  double turn = acos(clamp(static_cast<double>(-rel_vel.normalized().dot(heading)),-1.0,1.0));
  double dist = speed*turn/max_angular_velocity + 0.5*speed*speed/accel;
  if(false) { //reverse_accel>0) {
    double rev_dist = speed*(PI-turn)/max_angular_velocity + 0.5*speed*speed/reverse_accel;
    if(rev_dist < dist) {
      should_reverse = true;
      dist = rev_dist;
    }
  }
  
  return pos+dist*rel_vel.normalized();
}

double ShipTool::rendezvous_time(Vector3 target_location,Vector3 target_velocity, double interceptor_speed) {
  double a = target_velocity.dot(target_velocity) - interceptor_speed*interceptor_speed;
  double b = 2.0 * target_location.dot(target_velocity);
  double c = target_location.dot(target_location);
  double descriminant = b*b - 4*a*c;
	
  if(descriminant<0 or abs(a)<1e-4)
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
  if (!static_cast<bool>(call_0arg(target,"is_a_ship"))) {
    request_primary_fire(ship,state);
    return;
  }
  Variant weapon = call_2arg(ship,"get_first_weapon_or_null",true,false);
  if(is_nil(weapon))
    return;
  Vector3 aim = aim_forward(ship,weapon,state,target).normalized();
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
  Variant weapon = call_2arg(ship,"get_first_weapon_or_null",true,false);
  if(is_nil(weapon))
    return;
  if(!call_0arg(target,"is_a_ship"))
    return;

  Vector3 heading = get_heading(ship);
  Vector3 p = position_now(target);
  Vector3 dp = p - position_now(ship);
  Vector3 dv = target->get_linear_velocity() - state->get_linear_velocity();
  dp += dv*state->get_step();
  dv = heading*double_0arg(weapon,"get_projectile_speed") - dv;
  dv *= double_0arg(weapon,"get_projectile_lifetime");
  Vector3 point1 = dp-dv+p;
  Vector3 point2 = dp+p;
  point1[1]=5;
  point2[1]=5;
  Dictionary result = check_target_lock(ship,state,point1,point2,target);
  if(!result.empty())
    request_primary_fire(ship,state);
}

void ShipTool::move_to_attack(RigidBody *ship, PhysicsDirectBodyState *state, RigidBody *target) {
  Vector3 heading = get_heading(ship);
  Vector3 dp = position_now(target) - position_now(ship);
  Variant weapon = call_2arg(ship,"get_first_weapon_or_null",true,true);
  if(is_nil(weapon))
    return;
  Vector3 aim = aim_forward(ship,weapon,state,target);
  request_heading(ship,state,aim.normalized());
	
  // Get the circle the ship would make while turning at maximum speed:
  double full_turn_time = 2*PI / double_0arg(ship,"get_max_angular_velocity");
  double turn_circumference = full_turn_time * double_0arg(ship,"get_max_speed");
  double turn_diameter = max(turn_circumference/PI,5.0);
	
  // Heuristic; needs improvement
  if(heading.dot(dp)>=0 && dp.length()>turn_diameter ||
     state->get_linear_velocity().dot(dp)<0 && heading.dot(dp.normalized())>0.9)
    request_thrust(ship,state,1.0,0.0);
}

bool ShipTool::move_to_intercept(RigidBody *ship, PhysicsDirectBodyState *state,double close, double slow,
                                 Vector3 tgt_pos, Vector3 tgt_vel,
                                 bool force_final_state) {
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
      ship->set_translation(Vector3(position[0],ship->get_translation()[1],position[2]));
      state->set_linear_velocity(tgt_vel);
    }
    return true;
  }
  bool should_reverse = false;
  dp = tgt_pos1 - stopping_point(ship, state, tgt_vel, should_reverse);
  Vector3 dp_dir = dp.normalized();
  double dot = dp_dir.dot(heading);
  bool is_facing = dot > small_dot_product;
  if(!is_close || (!is_facing && !should_reverse))
    request_heading(ship,state,dp_dir);
  else
    state->set_angular_velocity(Vector3(0,0,0));
  request_thrust(ship,state,double(is_facing),double(should_reverse && ! is_facing));
  return false;
};
void ShipTool::request_heading(RigidBody *ship, PhysicsDirectBodyState *state, Vector3 new_heading) {
  Vector3 heading = get_heading(ship);
  double cross = -new_heading.cross(heading)[1];

  if(new_heading.dot(heading)>0) {
    double angle = asin(min(1.0,max(-1.0,cross/new_heading.length())));
    double actual_av = copysign(1.0,angle)*min(abs(angle)/state->get_step(),double_0arg(ship,"get_max_angular_velocity"));
    state->set_angular_velocity(Vector3(0,actual_av,0));
  } else {
    double left = static_cast<double>(cross >= 0.0);
    double right = static_cast<double>(cross < 0.0);
    state->set_angular_velocity(Vector3(0,(left-right)*double_0arg(ship,"get_max_angular_velocity"),0));
  }
};

void ShipTool::request_rotation(RigidBody *ship, PhysicsDirectBodyState *state, double rotate) {
  if(abs(rotate)>1e-3)
    state->add_torque(Vector3(0,rotate*double_0arg(ship,"get_rotation_torque"),0));
  else
    state->set_angular_velocity(Vector3(0,0,0));
}

void ShipTool::request_thrust(RigidBody *ship, PhysicsDirectBodyState *state,double forward,double reverse) {
  double ai_thrust = double_0arg(ship,"get_thrust")*min(1.0,abs(forward)) - double_0arg(ship,"get_reverse_thrust")*min(1.0,abs(reverse));
  Vector3 v_thrust = Vector3(ai_thrust,0,0).rotated(Vector3(0,1,0),ship->get_rotation().y);
  state->add_central_force(v_thrust);
}

void ShipTool::request_primary_fire(RigidBody *ship, PhysicsDirectBodyState *state) {
  call_1arg(ship,"set_ai_shoot",true);
}
