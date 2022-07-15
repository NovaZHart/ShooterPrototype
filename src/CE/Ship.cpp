#include <cstdint>
#include <cmath>
#include <limits>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>
#include <PhysicsServer.hpp>

#include "CE/SpecializedShipAI.hpp"
#include "CE/BaseShipAI.hpp"
#include "CE/CombatEngine.hpp"
#include "CE/VisualEffects.hpp"
#include "CE/Data.hpp"
#include "CE/Utils.hpp"
#include "CE/MultiMeshManager.hpp"
#include "CE/Math.hpp"
#include "CE/Salvage.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;


Ship::WeaponRanges Ship::make_ranges(const vector<shared_ptr<Weapon>> &weapons) {
  Ship::WeaponRanges r = {0,0,0,0,0,0};
  
  for(auto &weapon_ptr : weapons) {
    Weapon &weapon = *weapon_ptr;
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

static inline Ship::damage_array to_damage_array(Variant var,real_t clamp_min,real_t clamp_max) {
  PoolRealArray a = static_cast<PoolRealArray>(var);
  PoolRealArray::Read reader = a.read();
  const real_t *reals = reader.ptr();
  Ship::damage_array d;
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
  salvaged_value(max(0.0f,get<real_t>(dict,"salvaged_value",0))),
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
  ai_work(0),

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
  inverse_mass(1.0/(empty_mass+cargo_mass+fuel_inverse_density*fuel+armor/armor_inverse_density)),
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

  ai(),
  
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

  switch(ai_type) {
  case PATROL_SHIP_AI:
    ai = make_shared<PatrolShipAI>();
    break;
  case RAIDER_AI:
    ai = make_shared<RaiderAI>();
    break;
  case ARRIVING_MERCHANT_AI:
    ai = make_shared<ArrivingMerchantAI>();
    break;
  case DEPARTING_MERCHANT_AI:
    ai =make_shared<DepartingMerchantAI>();
    break;
  default:
    ai = make_shared<BaseShipAI>();
  };
}

Ship::~Ship()
{}


bool Ship::pull_back_to_standoff_range(const CombatEngine &ce,Ship &target,Vector3 &aim) {
  FAST_PROFILING_FUNCTION;

  if(not reverse_thrust)
    // Cannot pull back without reverse thrusters.
    return false;

  real_t standoff_range=get_standoff_range(target);

  if(not isfinite(standoff_range))
    // Cannot pull back to standoff range for an unarmed ship.
    return false;

  if(dot2(heading,aim)>0) {
    real_t distance = (target.position-position).length();
    if(distance<standoff_range*0.7)
      request_thrust(ce,0,1);
    else if(distance>standoff_range*.9)
      request_thrust(ce,1,0);
  }
    
  return false;
}

bool Ship::request_stop(const CombatEngine &ce,Vector3 desired_heading,real_t max_speed) {
  FAST_PROFILING_FUNCTION;
  bool have_heading = desired_heading.length_squared()>1e-10;
  real_t speed = linear_velocity.length();
  const real_t speed_epsilon = 0.01;
  real_t slow = max(max_speed,speed_epsilon);
  Vector3 velocity_norm = linear_velocity.normalized();
  
  if(speed<slow) {
    set_velocity(ce,Vector3(0,0,0));
    if(have_heading)
      request_heading(ce,desired_heading);
    else
      set_angular_velocity(ce,Vector3(0,0,0));
    return true;
  }

  double stop_time = speed/(inverse_mass*thrust);
  //double limit = 0.8 + 0.2/(1.0+stop_time*stop_time*stop_time*speed_epsilon);
  double turn = acos_clamp_dot(-velocity_norm,heading);
  double forward_turn_time = turn/max_angular_velocity;

  real_t delta = ce.get_delta();
  
  if(reverse_thrust>1e-5) {
    double forward_time = forward_turn_time + stop_time;
    double reverse_stop_time = speed/(inverse_mass*reverse_thrust);
    double reverse_turn_time = (PI/2-turn)/max_angular_velocity;
    double reverse_time = reverse_turn_time + reverse_stop_time;
    if(have_heading) {
      double turn_from_backward = acos_clamp_dot(desired_heading,-velocity_norm);
      forward_time += turn_from_backward/max_angular_velocity;
      
      double turn_from_forwards = acos_clamp_dot(desired_heading,velocity_norm);
      reverse_time += turn_from_forwards/max_angular_velocity;
    }
    if(reverse_time<forward_time) {
      if(fabsf(request_heading(ce,velocity_norm))>0.9)
        request_thrust(ce,0,speed/(delta*inverse_mass*reverse_thrust));
      return false;
    }
  }
  if(fabsf(request_heading(ce,-velocity_norm))>0.9)
    request_thrust(ce,speed/(delta*inverse_mass*thrust),0);
  return false;
}

Vector3 Ship::aim_forward(const CombatEngine &ce,Ship &target,bool &in_range) {
  FAST_PROFILING_FUNCTION;
  Vector3 aim = Vector3(0,0,0);
  Vector3 my_pos=position;
  Vector3 tgt_pos=target.position+confusion;
  Vector3 dp_ships = tgt_pos - my_pos;
  Vector3 dv = target.linear_velocity - linear_velocity;
  dp_ships += dv*ce.get_delta();
  in_range=false;
  for(auto &weapon_ptr : weapons) {
    Weapon &weapon = *weapon_ptr;
    if(weapon.is_turret or weapon.guided)
      continue;
    //Vector3 weapon_velocity = linear_velocity + weapon.terminal_velocity*heading;
    Vector3 dp = dp_ships - weapon.get_position().rotated(y_axis,rotation.y);
    real_t t = rendezvous_time(dp,dv,weapon.terminal_velocity);
    if(isnan(t)) 
      continue;
    //return (tgt_pos - my_pos).normalized();
    in_range = in_range or t<weapon.projectile_lifetime;
    t = min(t,weapon.projectile_lifetime);
    aim += (dp+t*dv)*max(1.0f,weapon.threat);
  }
  return aim.length_squared() ? aim.normalized() : (tgt_pos-my_pos).normalized();
}

void Ship::move_to_attack(const CombatEngine &ce,Ship &target) {
  FAST_PROFILING_FUNCTION;
  if(weapons.empty() or inactive or immobile)
    return;

  bool in_range=false;
  Vector3 aim=aim_forward(ce,target,in_range);
  // if(not in_range) {
  //   Vector3 dp = get_position(*this)-get_position(target);
  //   if(dp.length_squared()<max(radiussq,target.radiussq))
  //     in_range=true;
  // }

  real_t standoff_range=get_standoff_range(target);
  
  if(in_range) {
    pull_back_to_standoff_range(ce,target,aim);
    request_heading(ce,aim);
  } else {
    move_to_intercept(ce,standoff_range*0.7,0,target.position,target.linear_velocity,false);
    return;
  }

  Vector3 dp = target.position - position;
  real_t dotted = dot2(heading,dp.normalized());
	
  // Heuristic; needs improvement
  if((dotted>=0.9 and dot2(linear_velocity,dp)<0) or
     lensq2(dp)>max(100.0f,turn_diameter_squared))
    request_thrust(ce,1.0,0.0);
  else if(dotted<-0.75 and reverse_thrust>0)
    request_thrust(ce,0.0,1.0);
}

bool Ship::move_to_intercept(const CombatEngine &ce,double close, double slow,
                             DVector3 tgt_pos, DVector3 tgt_vel,
                             bool force_final_state) {
  FAST_PROFILING_FUNCTION;
  if(immobile)
    return false;
  const double big_dot_product = 0.99;
  DVector3 position = this->position;
  DVector3 heading = get_heading_d(*this);
  DVector3 dp = tgt_pos - position;
  DVector3 dv = tgt_vel - DVector3(linear_velocity);
  real_t delta = ce.get_delta();
  dp += dv*delta;
  double speed = dv.length();
  bool is_close = dp.length()<close;
  if(is_close && speed<slow) {
    if(force_final_state) {
      set_velocity(ce,Vector3(tgt_vel.x,0,tgt_vel.z));
      set_angular_velocity(ce,Vector3(0,0,0));
    }
    return true;
  }
  bool should_reverse = false;
  dp = tgt_pos - stopping_point(tgt_vel, should_reverse);

  if(should_reverse and dp.length()<close*.95) {
    request_thrust(ce,0,1);
    return false;
  }

  DVector3 dp_dir = dp.normalized();
  double dot = dp_dir.dot(heading);
  bool is_facing = dot > big_dot_product;

  if( !is_close || !is_facing)
    request_heading(ce,Vector3(dp_dir.x,0,dp_dir.z));
  else
    set_angular_velocity(ce,Vector3(0,0,0));
  if(is_facing)
    request_thrust(ce,1,0);
  else if(should_reverse)
    request_thrust(ce,0,1);
  return false;
}

bool Ship::init_ship(CombatEngine &ce) {
  Ref<VisualEffects> &visual_effects = ce.get_visual_effects();
  FAST_PROFILING_FUNCTION;
  // return false = ship does nothing else this timestep
  if(entry_method == ENTRY_FROM_ORBIT) {
    // Ships entering from orbit start at maximum speed.
    if(max_speed>0 and max_speed<999999)
      set_velocity(ce,heading*max_speed);
    entry_method=ENTRY_COMPLETE;
    damage_multiplier=1.0;
    return false;
  } else if(entry_method != ENTRY_FROM_RIFT and
            entry_method != ENTRY_FROM_RIFT_STATIONARY) {
    // Invalid entry method; treat it as ENTRY_COMPLETE.
    entry_method=ENTRY_COMPLETE;
    damage_multiplier=1.0;
    return false;
  }
  if(at_first_tick) {
    // Ship is arriving via spatial rift. Trigger the animation and start a timer.
    immobile=true;
    inactive=true;
    damage_multiplier = rifting_damage_multiplier;
    rift_timer.reset();
    if(visual_effects.is_valid()) {
      Vector3 rift_position = position;
      rift_position.y = visual_height+1.1f;
      visual_effects->add_hyperspacing_polygon(SPATIAL_RIFT_LIFETIME_SECS,rift_position,radius*1.5f,true,id);
    } else
      Godot::print_warning("No visual_effects!!",__FUNCTION__,__FILE__,__LINE__);
    set_angular_velocity(ce,Vector3(0.0,15.0+rand.randf()*15.0,0.0));
    return false;
  } else if(rift_timer.alarmed()) {
    // Rift animation just completed.
    rift_timer.clear_alarm();
    immobile=false;
    inactive=false;
    damage_multiplier=1.0;
    if(max_speed>0 and max_speed<999999 and
       entry_method!=ENTRY_FROM_RIFT_STATIONARY)
      set_velocity(ce,heading*max_speed);
    set_angular_velocity(ce,Vector3(0.0,0.0,0.0));
    entry_method=ENTRY_COMPLETE;
    return false;
  }
  return false; // rift animation not yet complete
}

void Ship::activate_cargo_web(CombatEngine &ce) {
  if(cargo_web_active)
    return;
  cargo_web_active = true;
  Ref<VisualEffects> &visual_effects = ce.get_visual_effects();
  if(visual_effects.is_valid()) {
    if(shield_ellipse>=0)
      visual_effects->set_visibility(shield_ellipse,false);
    if(cargo_web>=0)
      visual_effects->reset_effect(cargo_web);
    else
      cargo_web=visual_effects->add_cargo_web(*this,ce.get_faction_color(faction));
  }
}

void Ship::deactivate_cargo_web(CombatEngine &ce) {
  if(!cargo_web_active)
    return;
  cargo_web_active = false;
  Ref<VisualEffects> &visual_effects = ce.get_visual_effects();
  if(visual_effects.is_valid()) {
    if(shield_ellipse>=0)
      visual_effects->set_visibility(shield_ellipse,true);
    if(cargo_web>=0)
      visual_effects->set_visibility(cargo_web,false);
  }
}

void Ship::negate_drag_force(const CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;
  // Negate the drag force if the ship is below its max speed. Exceptions:
  // 1. If the ship is immobile due to entering orbit or a spatial rift.
  // 2. In hyperspace, if the ship has no fuel.
  if(immobile or (ce.is_in_hyperspace() and fuel<=0))
    return;
  if(linear_velocity.length_squared()<max_speed*max_speed)
    PhysicsServer::get_singleton()->body_add_central_force(rid,-drag_force);
}

real_t Ship::request_heading(const CombatEngine &ce,Vector3 new_heading) {
  FAST_PROFILING_FUNCTION;
  Vector3 norm_heading = new_heading.normalized();
  real_t cross = -cross2(norm_heading,heading);
  real_t new_av=0, dot_product = dot2(norm_heading,heading);
  
  if(dot_product>0) {
    double angle = asin_clamp(cross);
    new_av = copysign(1.0,angle)*min(fabsf(angle)/ce.get_delta(),max_angular_velocity);
  } else
    new_av = cross<0 ? -max_angular_velocity : max_angular_velocity;
  set_angular_velocity(ce,Vector3(0,new_av,0));
  return dot_product;
}

void Ship::request_rotation(const CombatEngine &ce,real_t rotation_factor) {
  FAST_PROFILING_FUNCTION;
  rotation_factor = clamp(rotation_factor,-1.0f,1.0f);
  set_angular_velocity(ce,Vector3(0,rotation_factor*max_angular_velocity,0));
}

void Ship::request_thrust(const CombatEngine &ce,real_t forward, real_t reverse) {
  FAST_PROFILING_FUNCTION;
  if(immobile or (ce.is_in_hyperspace() and fuel<=0))
    return;
  real_t ai_thrust = thrust*clamp(forward,0.0f,1.0f) - reverse_thrust*clamp(reverse,0.0f,1.0f);
  real_t delta = ce.get_delta();
  energy -= delta*(forward_thrust_energy*thrust*clamp(forward,0.0f,1.0f) + reverse_thrust_energy*reverse_thrust*clamp(reverse,0.0f,1.0f));
  heat += delta*(forward_thrust_heat*thrust*clamp(forward,0.0f,1.0f) + reverse_thrust_heat*reverse_thrust*clamp(reverse,0.0f,1.0f));
  Vector3 v_thrust = Vector3(ai_thrust,0,0).rotated(y_axis,rotation.y);
  PhysicsServer::get_singleton()->body_add_central_force(rid,v_thrust);
}

void Ship::set_angular_velocity(const CombatEngine &ce,const Vector3 &new_angular_velocity) {
  FAST_PROFILING_FUNCTION;
  // Apply an impulse that gives the ship a new angular velocity.
  Vector3 change = new_angular_velocity-angular_velocity;
  PhysicsServer::get_singleton()->body_apply_torque_impulse(rid,change/inverse_inertia);
  // Update our internal copy of the ship's angular velocity.
  angular_velocity = new_angular_velocity;
}

void Ship::set_velocity(const CombatEngine &ce,const Vector3 &velocity) {
  // Apply an impulse that gives the ship the new velocity.
  // Assumes the impulse is small, so we can ignore heat and energy
  FAST_PROFILING_FUNCTION;
  if(inverse_mass<1e-5) {
    Godot::print_error(String("Invalid inverse mass ")+String(Variant(inverse_mass)),__FUNCTION__,__FILE__,__LINE__);
    return;
  }
  PhysicsServer::get_singleton()->body_apply_central_impulse(rid,(velocity-linear_velocity)/inverse_mass);
  // Update our internal copy of the ship's velocity.
  linear_velocity = velocity;
}

void Ship::salvage_projectile(CombatEngine &ce,const Projectile &projectile) {
  FAST_PROFILING_FUNCTION;
  if(projectile.get_salvage()) {
    const Salvage & salvage = *projectile.get_salvage();
    if(salvage.structure_repair>0)
      structure = min(double(max_structure),structure+salvage.structure_repair);
    if(salvage.armor_repair>0)
      armor = min(double(max_armor),armor+salvage.armor_repair);
    if(salvage.fuel>0)
      fuel = min(max_fuel,fuel+salvage.fuel);
    if(salvage.cargo_unit_mass>0 and salvage.cargo_count>0) {
      float unit_mass = salvage.cargo_unit_mass/1000; // Convert kg->tons
      float old_mass = cargo_mass;
      float original_max_mass = max(cargo_mass,max_cargo_mass);
      int pickup = floorf((original_max_mass-old_mass)/unit_mass);
      if(pickup>salvage.cargo_count)
        pickup=salvage.cargo_count;
      cargo_mass = min(original_max_mass,old_mass+pickup*unit_mass);
      salvaged_value += pickup*salvage.cargo_unit_value;
      //Godot::print(name+" gained "+str(pickup*unit_mass)+"tn (of "+str(max_cargo_mass)+" max) and "+str(pickup*salvage.cargo_unit_value)+" (tot "+str(salvaged_value)+") by picking up "+str(pickup)+" units of "+str(salvage.cargo_name)+" ship cost "+str(cost));
      ce.add_salvaged_items(*this,salvage.cargo_name,pickup,unit_mass);
    }
  }
}

bool Ship::should_update_targetting(Ship &other) {
  if(other.fate!=FATED_TO_FLY)
    return true;
  else if(shot_at_target_timer.alarmed()) {
    // After 15 seconds without firing, reevaluate target
    shot_at_target_timer.reset();
    return true;
  } else if(range_check_timer.alarmed()) {
    // Every 25 seconds reevaluate target if target is out of range
    range_check_timer.reset();
    real_t target_distance = distance2(position,other.position);
    return target_distance > 1.5*range.all+10;
  }
  real_t hp = armor+shields+structure;
  return hp/4<damage_since_targetting_change;
}

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

real_t Ship::get_standoff_range(const Ship &target) {
  FAST_PROFILING_FUNCTION;

  if(cached_standoff_range>1e-5 and not standoff_range_timer.alarmed()) {
    // Don't calculate until we need to.
    return cached_standoff_range;
  }
  
  standoff_range_timer.reset();
  
  real_t standoff_range = NAN;
  
  if(not weapons.size()) {
    // No weapons means no standoff range
    //Godot::print("Unarmed ship "+name+" cannot have a standoff range.");
    return cached_standoff_range = NAN;
  }
  
  for(auto &weapon_ptr : weapons) {
    Weapon &weapon = *weapon_ptr;

    if(weapon.antimissile)
      continue;
    
    Vector3 weapon_position=CE::get_position(weapon);

    real_t range=weapon_position.x;
    
    if(weapon.guided) {
      // Guided weapon range depends on turn time.
      if(weapon.get_ammo() or weapon.reload_delay) {
        real_t turn_time = weapon.is_turret ? 0 : PI/weapon.projectile_turn_rate;
        range += max(0.0f,weapon.projectile_range-weapon.terminal_velocity*turn_time);
      }
    } else
      range += weapon.projectile_range;

    // if(range<1)
    //   Godot::print_warning(str(weapon.node_path)+" range is implausibly small: "+str(range),
    //                        __FUNCTION__,__FILE__,__LINE__);

    if(isfinite(standoff_range))
      standoff_range = min(standoff_range,range);
    else
      standoff_range = range;
  }

  // Godot::print("Ship "+name+" standoff range to "+target.name+" is "+str(standoff_range));
  
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

void Ship::apply_heat_and_energy_costs(const CombatEngine &ce) {
  if(not immobile) { // ship does not pay to spin while arriving via a rift
    real_t angular_speed = angular_velocity.length();
    if(angular_speed) {
      real_t mag = clamp(angular_speed/max_angular_velocity,0.0f,1.0f)*turning_thrust*ce.get_delta();
      energy -= mag*turning_thrust_energy;
      heat += mag*turning_thrust_heat;
    }
  }
}

void Ship::heal(const CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;
  real_t delta = ce.get_delta();
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

  if(ce.is_in_hyperspace() and fuel>0.0f) {
    real_t new_fuel = clamp(fuel-delta/inverse_mass*linear_velocity.length()/
                            (hyperspace_display_ratio*fuel_efficiency*1000.0f),
                            0.0f,max_fuel);
    if(fabsf(fuel-new_fuel)>1e-6)
      updated_mass_stats = true;
    fuel = new_fuel;
  } else if(fuel<max_fuel) {
    real_t recharge = ce.get_system_fuel_recharge();
    real_t effective_distance = 10.0f+position.length()/hyperspace_display_ratio;
    recharge += ce.get_center_fuel_recharge()*10.0f/effective_distance;
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
                           const Ship::damage_array &resists,
                           const Ship::damage_array &passthrus,bool allow_passthru) {
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


std::vector<shared_ptr<Weapon>> Ship::get_weapons(Array a,MultiMeshManager &multimeshes) {
  vector<shared_ptr<Weapon>> result;
  int s=a.size();
  for(int i=0;i<s;i++)
    result.emplace_back(make_shared<Weapon>(static_cast<Dictionary>(a[i]),multimeshes));
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


void Ship::update_near_objects(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;

  if(!nearby_hostiles_timer.alarmed())
    return;

  nearby_hostiles_timer.reset();

  vector<pair<real_t,pair<RID,object_id>>> search_results = ce.get_search_results();
  search_results.clear();
  ce.find_ships_in_radius(godot::CE::get_position(*this),100,ce.get_enemy_mask(faction),search_results);
  nearby_objects.clear();
  for(auto & r : search_results)
    nearby_objects.push_back(r.second);
}

void Ship::create_flotsam(CombatEngine &ce) {
  FAST_PROFILING_FUNCTION;
  for(auto & salvage_ptr : salvage) {
    Vector3 v = linear_velocity;
    real_t flotsam_mass = FLOTSAM_MASS;
    real_t speed = EXPLOSION_FLOTSAM_INITIAL_SPEED;
    speed = speed*(1+rand.randf())/2;
    real_t angle = rand.rand_angle();
    Vector3 heading = unit_from_angle(angle);
    v += heading*speed;
    if(!salvage_ptr->flotsam_mesh.is_valid()) {
      Godot::print_warning(name+": has a salvage with no flotsam mesh",__FUNCTION__,__FILE__,__LINE__);
      return;
    }
    ce.create_flotsam_projectile(this,salvage_ptr,position,angle,v,flotsam_mass);
  }
}
