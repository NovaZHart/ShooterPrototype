#include "CE/SpecializedShipAI.hpp"

#include "CE/CombatEngine.hpp"
#include "CE/Utils.hpp"
#include "CE/Data.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

PatrolShipAI::~PatrolShipAI() {}
PatrolShipAI::PatrolShipAI() {}
void PatrolShipAI::run_ai(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;

  if(ship.goal_target<0 and ce.get_planets().size()>0) {
    // Initial goal target is the nearest planet.
    ship.goal_target = select_target(-1,select_nearest(ship.position),ce.get_planets(),false);
    Planet *p_planet = ce.planet_with_id(ship.goal_target);
    if(p_planet) {
      ship.destination = p_planet->position;
      ship.goal_target = p_planet->id;
    }
  }

  if(ship.ai_flags&DECIDED_TO_LAND) {
    do_land(ce,ship);
    opportunistic_firing(ce,ship);
    return;
  } else if(ship.ai_flags&DECIDED_TO_RIFT) {
    if(!do_rift(ce,ship))
      opportunistic_firing(ce,ship);
    return;
  }

  bool low_health = ship.armor<ship.max_armor/5 and ship.shields<ship.max_shields/3 and ship.structure<ship.max_structure/2;

  if(low_health) {
    if(!do_rift(ce,ship))
      opportunistic_firing(ce,ship);
    ship.ai_flags=DECIDED_TO_RIFT;
    return;
  }

  Ship *target_ptr=nullptr;
  bool find_new_target = false;
  if(ship.get_target()<0 and ship.no_target_timer.alarmed()) {
    ship.no_target_timer.reset();
    find_new_target = true;
  } else {
    target_ptr = ce.ship_with_id(ship.get_target());
    if(!target_ptr)
      find_new_target = true;
    else
      find_new_target = ship.should_update_targetting(*target_ptr);
  }
  if(find_new_target) {
    ce.choose_target_by_goal(ship,false,goal_patrol,0.0f,30.0f);
    target_ptr = ce.ship_with_id(ship.get_target());
  }

  bool have_target = !!target_ptr;
  bool close_to_target = have_target and distance2(target_ptr->position,ship.position)<13*ship.max_speed;
  
  if(close_to_target) {
    ship.ai_flags=0;
    ship.move_to_attack(ce,*target_ptr);
    aim_turrets(ce,ship,target_ptr);
    auto_fire(ce,ship,target_ptr);
    fire_antimissile_turrets(ce,ship);
  } else {
    if(not have_target)
      ship.clear_target();
    if(ship.ai_flags==0) {
      float randf = ship.rand.randf();
      float scale = (ship.tick_at_last_shot-ship.tick)>ticks_per_minute ? .05 : .15;
      scale *= ce.get_delta()/30;
      if(randf<scale)
        ship.ai_flags=DECIDED_TO_RIFT;
      else if(randf<2*scale)
        ship.ai_flags=DECIDED_TO_LAND;
    }
    if(ship.ai_flags&DECIDED_TO_LAND) {
      do_land(ce,ship);
      opportunistic_firing(ce,ship);
    } else if(ship.ai_flags&DECIDED_TO_RIFT) {
      if(!do_rift(ce,ship))
        opportunistic_firing(ce,ship);
    } else if(have_target) {
      ship.move_to_attack(ce,*target_ptr);
      opportunistic_firing(ce,ship);
    } else
      do_patrol(ce,ship);
  }
}

////////////////////////////////////////////////////////////////////////

ArrivingMerchantAI::~ArrivingMerchantAI() {}
ArrivingMerchantAI::ArrivingMerchantAI() {}

void ArrivingMerchantAI::run_ai(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return;
    
  Planet *target_ptr = nullptr;
 
  // If it is time to decide on our next action, ponder it.
  if(ship.ai_flags==DECIDED_NOTHING or ship.ticks_since_ai_check>=ticks_per_second/4)
    choose_arriving_merchant_action(ce,ship);

  if(ship.ai_flags==DECIDED_TO_RIFT) {
    if(!do_rift(ce,ship))
      opportunistic_firing(ce,ship);
    return;
  }
  
  if(ship.ai_flags==DECIDED_TO_FLEE) {
    do_evade(ce,ship);
    opportunistic_firing(ce,ship);
    return;
  }

  if(!target_ptr)
    target_ptr = choose_arriving_merchant_goal_target(ce,ship);
  if(target_ptr) {
    Planet &target = *target_ptr;
    if(ship.move_to_intercept(ce, target.radius, 5.0, target.position, Vector3(0,0,0), true))
      // Reached planet.
      ship.fate = FATED_TO_LAND;
    opportunistic_firing(ce,ship);
    return;
  }

  Godot::print_warning(ship.name+": arriving merchant has nothing to do",__FUNCTION__,__FILE__,__LINE__);
  // Nowhere to go and nothing to do, so we may as well leave.
  if(!do_rift(ce,ship))
    opportunistic_firing(ce,ship);
}
  
Planet *ArrivingMerchantAI::choose_arriving_merchant_goal_target(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  // Get our target planet if there isn't one already.
  Planet * target_ptr = ce.planet_with_id(ship.goal_target);
  if(!target_ptr) {
    target_ptr = ce.planet_with_id(ship.get_target());
    if(!target_ptr) {
      ship.new_target(select_target<>(ship.get_target(),select_nearest(ship.position),ce.get_planets(),false));
      ship.goal_target = ship.get_target();
      //Godot::print(ship.name+": arriving merchant is using the nearest planet "+str(ship.goal_target));
    } else {
      //Godot::print(ship.name+": arriving merchant is using its target as its goal target");
      ship.goal_target = ship.get_target();
    }
    target_ptr = ce.planet_with_id(ship.goal_target);
    //Godot::print(ship.name+": arriving merchant chose "+target_ptr->second.name+" as its goal target");
  } else if(ship.get_target()!=ship.goal_target)
    ship.new_target(ship.goal_target);
  return target_ptr;
}

Planet *ArrivingMerchantAI::choose_arriving_merchant_action(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  ship.ticks_since_ai_check=0;
  Planet *target_ptr = choose_arriving_merchant_goal_target(ce,ship);
  if(!target_ptr) {
    // Nowhere to go and nothing to do. Time to leave.
    ship.ai_flags = DECIDED_TO_RIFT;
    return target_ptr;
  }

  // If we're close to the destination, land regardless of hostiles.
  // If we're far away, rift. Otherwise, land or evade based on threat vector.
  
  ship.ai_flags = DECIDED_NOTHING;
  Vector3 destination = target_ptr->position;
  real_t dist2 = distance2(destination,ship.position)-target_ptr->radius;
  real_t too_far = 30*ship.max_speed, too_close = 2*ship.max_speed;
    
  // If we're far from the destination, rift away.
  if(dist2>too_far) {
    ship.ai_flags = DECIDED_TO_RIFT;
    return target_ptr;
  }
    
  // If we're close to the destination, land regardless of risks.
  if(dist2<too_close) {
    ship.ai_flags = DECIDED_TO_LAND;
    return target_ptr;
  }
  
  // If we're dying, leave. Civilians will stay longer than they should
  // since they're panicking.
  if(ship.structure<0.5*ship.max_structure or
     (!ship.armor and !ship.shields and ship.structure<0.75*ship.max_structure)) {
    ship.ai_flags = DECIDED_TO_RIFT;
    return target_ptr;
  }
    
  // Evade or move to land, based on threat vector.
  ship.update_near_objects(ce);
  make_threat_vector(ce,ship,0.5);
  real_t threat_threshold = ship.threat/10;
  bool should_evade = (ship.threat_vector.length_squared() > threat_threshold*threat_threshold);
  ship.ai_flags = should_evade ? DECIDED_TO_FLEE : DECIDED_TO_LAND;
  return target_ptr;
}

////////////////////////////////////////////////////////////////////////

DepartingMerchantAI::~DepartingMerchantAI() {}
DepartingMerchantAI::DepartingMerchantAI() {}

void DepartingMerchantAI::run_ai(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.immobile)
    return;

  // If it is time to decide on our next action, ponder it.
  if(ship.ai_flags==DECIDED_NOTHING or ship.ticks_since_ai_check>=ticks_per_second/4)
    decide_departing_merchant_ai_action(ce,ship);

  if(ship.ai_flags==DECIDED_TO_WANDER) {
    // We're too close to the planet, so wander away.
    Planet * target_ptr = ce.planet_with_id(ship.goal_target);
    if(target_ptr) {
      Planet &planet = *target_ptr;
      Vector3 planet_loc = get_position(planet);
      Vector3 direction = (get_position(ship)-planet_loc).normalized();
      ship.request_heading(ce,direction);
      if(dot2(ship.heading,direction)>=0)
        ship.request_thrust(ce,1,0);
      else
        ship.request_thrust(ce,0,1);
    } else if(do_rift(ce,ship)) // Departure planet is gone, so just rift away
      return;
  } else if(ship.ai_flags==DECIDED_TO_FLEE)
    // Flee in terror because of nearby threats.
    do_evade(ce,ship);
  else if(do_rift(ce,ship))    // Time to rift away.
    return;

  opportunistic_firing(ce,ship);
}

void DepartingMerchantAI::decide_departing_merchant_ai_action(CombatEngine &ce,Ship &ship) {
  ship.ticks_since_ai_check=0;
  if(ship.armor<ship.max_armor/3 and ship.shields<ship.max_shields/3) {
    ship.ai_flags = DECIDED_TO_RIFT;
    return;
  }
    
  Planet * target_ptr = ce.planet_with_id(ship.goal_target);
  if(!target_ptr) {
    ship.goal_target = select_target<>(-1,select_nearest(ship.position),ce.get_planets(),false);
    target_ptr = ce.planet_with_id(ship.goal_target);
  }

  bool is_too_far = false, is_too_close = false;

  if(target_ptr) {
    Planet &planet = *target_ptr;
    real_t dist2 = distance2(planet.position,ship.position)-ship.radius-planet.radius;

    if(dist2<clamp(2*ship.max_speed,5.0f,15.0f)) // too close to rift away
      is_too_close=true;
    else if(dist2>min(150.0f,30*ship.max_speed)) // distance at which to give up and rift
      is_too_far=true;
  } else
    Godot::print_warning(ship.name+": no goal target to leave from in decide_departing_merchant_ai_action",
                         __FUNCTION__,__FILE__,__LINE__);

  if(is_too_far) {
    ship.ai_flags = DECIDED_TO_RIFT;
    return;
  }
  
  ship.update_near_objects(ce);
  make_threat_vector(ce,ship,0.5);
  real_t threat_threshold = ship.threat/10;
  bool should_evade = (ship.threat_vector.length_squared() > threat_threshold*threat_threshold);
  if(should_evade) {
    ship.ai_flags = DECIDED_TO_FLEE;
    return;
  }
    
  if(is_too_close)
    ship.ai_flags = DECIDED_TO_WANDER;
  else
    ship.ai_flags = DECIDED_TO_RIFT;
}

////////////////////////////////////////////////////////////////////////

RaiderAI::~RaiderAI() {}
RaiderAI::RaiderAI() {}

void RaiderAI::run_ai(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  if(ship.inactive)
    return;
  
  // If the ship decided to rift, there's nothing left to consider.
  if(0 != (ship.ai_flags&DECIDED_TO_RIFT)) {
    ship.deactivate_cargo_web(ce);
    if(!do_rift(ce,ship))
      opportunistic_firing(ce,ship);
    return;
  }

  if(ship.goal_target<0 and ce.get_planets().size()>0) {
    ship.goal_target = select_target(-1,select_nearest(ship.position),ce.get_planets(),false);
    Planet * p_planet = ce.planet_with_id(ship.goal_target);
    if(p_planet)
      ship.destination = p_planet->position;
  }

  // If it is time to decide on our next action, ponder it.
  if(!(ship.ai_flags&DECIDED_TO_RIFT) and ship.ticks_since_ai_check>=ticks_per_second/4)
    decide_raider_ai_action(ce,ship);

  if(ship.ai_flags&DECIDED_TO_FLEE) {
    ship.deactivate_cargo_web(ce);
    do_evade(ce,ship);
    opportunistic_firing(ce,ship);
    return;
  }

  bool close_to_target=false;
  Ship * target_ptr = nullptr;
  
  if(ship.ai_flags&DECIDED_TO_FIGHT) {
    target_ptr = update_targetting(ce,ship);
    close_to_target = !!target_ptr
      and target_ptr->position.distance_squared_to(ship.position)<900;
  }

  if(!close_to_target and ship.ai_flags&DECIDED_TO_SALVAGE and do_salvage(ce,ship))
    return;

  ship.deactivate_cargo_web(ce);
  
  if(target_ptr) {
    ship.move_to_attack(ce,*target_ptr);
    aim_turrets(ce,ship,target_ptr);
    if(ship.efficiency>0.9)
      auto_fire(ce,ship,target_ptr);
    fire_antimissile_turrets(ce,ship);
  } else {
    // Nothing to do.
    target_ptr = update_targetting(ce,ship);
    do_patrol(ce,ship);
    opportunistic_firing(ce,ship);
  }  
}

void RaiderAI::decide_raider_ai_action(CombatEngine &ce,Ship &ship) {
  FAST_PROFILING_FUNCTION;
  ship.ticks_since_ai_check=0;

  if(ship.structure<0.667*ship.max_structure) {
    // Panic time. Only hope is to rift away.
    Godot::print(ship.name+": severe damage, so rift");
    ship.ai_flags = DECIDED_TO_RIFT;
    return;
  }

  if(ship.ai_flags&DECIDED_TO_FLEE) {
    // We're already fleeing. Should we keep doing it?
    if(ship.shields<0.75*ship.max_shields or ship.efficiency<0.9) {
      if(ship.shields<ship.ai_work and ship.ticks_since_ai_change>3*ticks_per_second) {
        // Shields don't seem to be recharging.
        Godot::print(ship.name+": shields are not recharging, so rift");
        ship.ai_flags = DECIDED_TO_RIFT;
        return;
      }
      // Shields are recharging, but aren't 75% yet, so keep fleeing.
      ship.update_near_objects(ce);
      make_threat_vector(ce,ship,0.5);
      return;
    } else {
      // We're done fleeing.
      ship.ticks_since_ai_change=0;
      ship.ai_flags = DECIDED_TO_FIGHT;
    }
  }

  // If shields are low, flee to recharge unless we have a lot of armor left.
  // Or, if efficiency is low, flee to recharge efficiency.
  if( (ship.shields<0.1*ship.max_shields and ship.armor<0.5*ship.max_armor) or ship.efficiency<0.6) {
    ship.ai_flags = DECIDED_TO_FLEE;
    ship.ai_work = ship.shields;
    ship.ticks_since_ai_change=0;
    ship.update_near_objects(ce);
    make_threat_vector(ce,ship,0.5);
    return;
  }

  // If we have enough cargo, it is time to leave.
  bool have_enough_cargo= ship.cargo_mass >= ship.max_cargo_mass or ship.cargo_mass>ship.empty_mass;
  if(!have_enough_cargo)
    have_enough_cargo = ship.salvaged_value>5e4*ship.max_cargo_mass
      or (ship.cost and ship.salvaged_value>ship.cost*0.5);
  if(have_enough_cargo) {
    Godot::print(ship.name+": have enough cargo ("+str(ship.salvaged_value)+" worth) so rift");
    ship.ai_flags = DECIDED_TO_RIFT;
    ship.ticks_since_ai_change=0;
    return;
  }

  // Should we salvage cargo?
  real_t salvage_time=9e9; // initialized by should_salvage
  if(should_salvage(ce,ship,&salvage_time)) {
    ship.ai_flags = DECIDED_TO_SALVAGE;
    // If we're salvaging cargo, only consider fighting instead if we're far from the salvage.
    if(salvage_time>3)
      ship.ai_flags &= DECIDED_TO_FIGHT;
    return;
  } else
    // Nothing else to do, so let's fight.
    ship.ai_flags = DECIDED_TO_FIGHT;
}
