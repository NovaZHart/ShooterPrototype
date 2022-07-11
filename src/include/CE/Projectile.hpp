#ifndef PROJECTILE_HPP
#define PROJECTILE_HPP

#include "Godot.hpp"
#include "String.hpp"
#include "Ref.hpp"
#include "Vector3.hpp"

#include <memory>

#include "DVector3.hpp"
#include "CE/ObjectIdGenerator.hpp"
#include "CE/Weapon.hpp"

namespace godot {
  namespace CE {
    class Ship;
    class Projectile;
    struct Salvage;
    struct MultiMeshManager;
    class CombatEngine;
  
    class Projectile {
      const object_id id;
      const std::shared_ptr<const Weapon> weapon;
      const object_id source;
      object_id target;
      const object_id mesh_id;
      const bool always_drag;
      const real_t lifetime, max_speed, detonation_range;
      const faction_index_t faction;
      double structure;
      Vector3 position, old_position, linear_velocity, rotation, angular_velocity, forces;
      real_t age, scale, visual_height;
      bool alive, direct_fire, possible_hit, integrate_forces;
      const std::shared_ptr<const Salvage> salvage;
    public:
      inline object_id get_id() const {
        return id;
      }
      inline object_id get_source() const {
        return source;
      }
      inline object_id get_target() const {
        return target;
      }
      inline object_id get_mesh_id() const {
        return mesh_id;
      }
      inline bool get_guided() const {
        return weapon->guided;
      }
      inline bool get_guidance_uses_velocity() const {
        return weapon->guidance_uses_velocity;
      }
      inline bool get_auto_retarget() const {
        return weapon->auto_retarget;
      }
      inline real_t get_damage() const {
        return weapon->damage;
      }
      inline real_t get_impulse() const {
        return weapon->impulse;
      }
      inline real_t get_blast_radius() const {
        return weapon->blast_radius;
      }
      inline real_t get_detonation_range() const {
        return detonation_range;
      }
      inline real_t get_turn_rate() const {
        return weapon->projectile_turn_rate;
      }
      inline bool get_always_drag() const {
        return always_drag;
      }
      inline real_t get_mass() const {
        return weapon->projectile_mass;
      }
      inline real_t get_drag() const {
        return weapon->projectile_drag;
      }
      inline real_t get_thrust() const {
        return weapon->projectile_thrust;
      }
      inline real_t get_lifetime() const {
        return lifetime;
      }
      inline real_t get_initial_velocity() const {
        return weapon->initial_velocity;
      }
      inline real_t get_max_speed() const {
        return max_speed;
      }
      inline real_t get_heat_fraction() const {
        return weapon->heat_fraction;
      }
      inline real_t get_energy_fraction() const {
        return weapon->energy_fraction;
      }
      inline real_t get_thrust_fraction() const {
        return weapon->thrust_fraction;
      }
      inline faction_index_t get_faction() const {
        return faction;
      }
      inline int get_damage_type() const {
        return weapon->damage_type;
      }
      inline double get_max_structure() const {
        return weapon->projectile_structure;
      }
      inline double get_structure() const {
        return structure;
      }
      inline Vector3 get_position() const {
        return position;
      }
      inline Vector3 get_old_position() const {
        return old_position;
      }
      inline Vector3 get_linear_velocity() const {
        return linear_velocity;
      }
      inline Vector3 get_rotation() const {
        return rotation;
      }
      inline Vector3 get_angular_velocity() const {
        return angular_velocity;
      }
      inline Vector3 get_forces() const {
        return forces;
      }
      inline real_t get_age() const {
        return age;
      }
      inline real_t get_scale() const {
        return scale;
      }
      inline real_t get_visual_height() const {
        return visual_height;
      }

      inline void apply_force(Vector3 F) {
        forces += F;
      }
      
      inline bool get_possible_hit() const {
        return possible_hit;
      }
      inline void set_possible_hit(bool h) {
        possible_hit = h;
      }

      inline bool get_integrate_forces() const {
        return integrate_forces;
      }
      inline std::shared_ptr<const Salvage> get_salvage() const {
        return salvage;
      }
      
      inline bool is_antimissile() const {
        return weapon->antimissile;
      }
      inline bool is_alive() const {
        return alive;
      }
      inline bool is_missile() const {
        return !!weapon->projectile_structure;
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

      Projectile(object_id id,const Ship &ship,std::shared_ptr<const Weapon> weapon,object_id alternative_target);
      Projectile(object_id id,const Ship &ship,std::shared_ptr<const Weapon> weapon,Projectile &target,Vector3 position,real_t scale,real_t rotation);
      Projectile(object_id id,const Ship &ship,std::shared_ptr<const Weapon> weapon,Vector3 position,real_t scale,real_t rotation,object_id target);
      Projectile(object_id id,const Ship *ship,std::shared_ptr<const Salvage> salvage,Vector3 position,real_t rotation,Vector3 velocity,real_t mass,MultiMeshManager &multimeshes,std::shared_ptr<const Weapon> weapon_placeholder);
      
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
