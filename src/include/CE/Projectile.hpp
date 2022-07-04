#ifndef PROJECTILE_HPP
#define PROJECTILE_HPP

#include "Godot.hpp"
#include "String.hpp"
#include "Ref.hpp"
#include "Vector3.hpp"

#include <memory>

#include "DVector3.hpp"
#include "CE/ObjectIdGenerator.hpp"

namespace godot {
  namespace CE {
    class Ship;
    struct Weapon;
    struct Projectile;
    struct Salvage;
    struct MultiMeshManager;
    class CombatEngine;
    
    struct Salvage {
      const Ref<Mesh> flotsam_mesh;
      const float flotsam_scale;
      const String cargo_name;
      const int cargo_count;
      const float cargo_unit_mass;
      const float cargo_unit_value;
      const float armor_repair;
      const float structure_repair;
      const float fuel;
      const float spawn_duration;
      const float grab_radius;

      Salvage(Dictionary dict);
      ~Salvage();
    };
  
    struct Projectile {
      const object_id id;
      const object_id source;
      object_id target;
      const object_id mesh_id;
      const bool guided, guidance_uses_velocity, auto_retarget;
      const real_t damage, impulse, blast_radius, detonation_range, turn_rate;
      const bool always_drag;
      const real_t mass, drag, thrust, lifetime, initial_velocity, max_speed;
      const real_t heat_fraction, energy_fraction, thrust_fraction;
      //const int collision_mask;
      const faction_index_t faction;
      const int damage_type;
      const double max_structure;
      double structure;
      Vector3 position, linear_velocity, rotation, angular_velocity, forces;
      real_t age, scale, visual_height;
      bool alive, direct_fire, possible_hit, integrate_forces;
      const std::shared_ptr<const Salvage> salvage;
      const bool antimissile_damage;
      
    public:

      inline bool is_antimissile() const {
        return antimissile_damage;
      }
      inline bool is_missile() const {
        return max_structure;
      }
      inline bool is_flotsam() const {
        return !!salvage;
      }
      inline bool is_direct_fire() const {
        return direct_fire;
      }
      
      inline real_t radius() const {
        return std::max(1e-5f,detonation_range);
      }
      real_t take_damage(real_t amount);
      Projectile(object_id id,const Ship &ship,const Weapon &weapon,Projectile &target,Vector3 position,real_t scale,real_t rotation);
      Projectile(object_id id,const Ship &ship,const Weapon &weapon,object_id alternative_target=-1);
      Projectile(object_id id,const Ship &ship,const Weapon &weapon,Vector3 position,real_t scale,real_t rotation,object_id target);
      Projectile(object_id id,const Ship &ship,std::shared_ptr<const Salvage> salvage,Vector3 position,real_t rotation,Vector3 velocity,real_t mass,MultiMeshManager &multimeshes);
      ~Projectile();

      bool is_eta_lower_with_thrust(DVector3 target_position,DVector3 target_velocity,DVector3 heading,real_t delta);
      bool collide_projectile(CombatEngine &ce);
      Ship *get_projectile_target(CombatEngine &ce);
      void guide_projectile(CombatEngine &ce);
      void step_projectile(CombatEngine &ce,bool &have_died,bool &have_collided,bool &have_moved);
      void integrate_projectile_forces(real_t thrust_fraction,bool drag,real_t delta);
      bool collide_point_projectile(CombatEngine &ce);
    };

    typedef std::unordered_map<object_id,Projectile>::iterator projectiles_iter;
  }
}

#endif
