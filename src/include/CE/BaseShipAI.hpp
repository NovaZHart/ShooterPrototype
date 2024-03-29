#ifndef BASESHIPAI_HPP
#define BASESHIPAI_HPP

#include <memory>
#include <Vector3.hpp>
#include "CE/Faction.hpp"

namespace godot {
  namespace CE {
    class Ship;
    class CombatEngine;
    struct Planet;
    struct PlayerOverrides;
    class Weapon;
    
    class BaseShipAI {
      // FIXME: Move stuff from Ship to here.
    public:

      void do_land(CombatEngine &ce,Ship &ship);
      bool do_patrol(CombatEngine &ce,Ship &ship);
      bool do_salvage(CombatEngine &ce,Ship &ship);
      void do_evade(CombatEngine &ce,Ship &ship);
      bool do_rift(CombatEngine &ce,Ship &ship);
      //bool rift_ai(CE::Ship &ship);

      bool should_salvage(CombatEngine &ce,Ship &ship,real_t *returned_best_time);
      void fire_antimissile_turrets(CombatEngine &ce,Ship &ship);
      void use_cargo_web(CombatEngine &ce,Ship &ship);
      void opportunistic_firing(CombatEngine &ce,Ship &ship);
      Vector3 make_threat_vector(CombatEngine &ce,Ship &ship, real_t t);
      void aim_turrets(CombatEngine &ce,Ship &ship,Ship *target);
      void fire_primary_weapons(CombatEngine &ce,Ship &ship);
      bool fire_direct_weapon(CombatEngine &ce,Ship &ship,std::shared_ptr<Weapon> weapon_ptr,bool allow_untargeted);
      void auto_fire(CombatEngine &ce,Ship &ship, Ship *target);
      Ship *update_targetting(CombatEngine &ce,Ship &ship);

      bool apply_player_orders(CombatEngine &ce,Ship &ship,PlayerOverrides &overrides);
      bool apply_player_goals(CombatEngine &ce,Ship &ship,PlayerOverrides &overrides);
      void player_auto_target(CombatEngine &ce,Ship &ship);

      void ai_step(CombatEngine &ce,Ship &ship);

      void choose_target_by_goal(CombatEngine &ce,Ship &ship,bool prefer_strong_targets,
                                 goal_action_t goal_filter,real_t min_weight_to_target,
                                 real_t override_distance) const;
  
      virtual ~BaseShipAI();
      BaseShipAI();
    protected:
      virtual void run_ai(CombatEngine &ce,Ship &ship);
    };
  }
}

#endif
