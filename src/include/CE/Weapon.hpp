#ifndef WEAPON_HPP
#define WEAPON_HPP

#include "NodePath.hpp"
#include "Vector3.hpp"
#include "Dictionary.hpp"

#include "CE/Countdowns.hpp"
#include "CE/Types.hpp"

namespace godot {
  namespace CE {
    class MultiMeshManager;
    struct Ship;
    
    struct Weapon {
      const real_t damage, impulse, initial_velocity;
      const real_t projectile_mass, projectile_drag, projectile_thrust, projectile_lifetime, projectile_structure;
      const real_t projectile_turn_rate;
      const real_t firing_delay, turn_rate, blast_radius, detonation_range, threat;
      const real_t heat_fraction, energy_fraction, thrust_fraction, firing_energy, firing_heat;
      const bool antimissile, direct_fire, guided, guidance_uses_velocity, auto_retarget;
      const object_id mesh_id;
      const real_t terminal_velocity, projectile_range;
      const NodePath node_path;
      const bool is_turret;
      const int damage_type;
      
      const real_t reload_delay, reload_energy, reload_heat;
      const int ammo_capacity;
      
      int ammo;

      Vector3 position, rotation;
      const real_t harmony_angle;
      Countdown firing_countdown;
      Countdown reload_countdown;

      void reload(Ship &ship,ticks_t idelta);
      void fire(Ship &ship,ticks_t idelta);
      
      inline bool can_fire() const {
        return ammo and not firing_countdown.ticking();
      }

      Weapon(Dictionary dict,MultiMeshManager &multimeshes);
      ~Weapon();
      Dictionary make_status_dict() const;
    };
  }
}

#endif
