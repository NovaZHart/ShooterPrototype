#ifndef SHIP_HPP
#define SHIP_HPP

#include <unordered_map>
#include <array>
#include <vector>
#include <memory>

#include "Godot.hpp"
#include "RID.hpp"
#include "String.hpp"
#include "AABB.hpp"
#include "Ref.hpp"
#include "Mesh.hpp"
#include "Vector3.hpp"
#include "Transform.hpp"
#include "Rect2.hpp"
#include "Dictionary.hpp"
#include "PhysicsServer.hpp"

#include "CE/BaseShipAI.hpp"
#include "CE/Types.hpp"
#include "CE/Constants.hpp"
#include "CE/MultiMeshManager.hpp"
#include "CE/CheapRand32.hpp"
#include "CE/ObjectIdGenerator.hpp"
#include "CE/Countdowns.hpp"
#include "CE/Weapon.hpp"
#include "CE/Projectile.hpp"
#include "CE/Planet.hpp"
#include "CE/CelestialObject.hpp"
#include "CE/DamageArray.hpp"
#include "DVector3.hpp"
#include "PropertyMacros.hpp"

namespace godot {
  namespace CE {
    class CombatEngine;

    class Ship: public CelestialObject {
    public:
      struct WeaponRanges {
        real_t guns, turrets, guided, unguided, antimissile, all;
      };
    public:
      const object_id id;
      const String name; // last element of node path
      const RID rid; // of rigid body
      const real_t cost;
      const real_t max_thrust, max_reverse_thrust, max_turning_thrust, hyperthrust_ratio, max_cargo_mass;
      const real_t threat, visual_height;
      const real_t max_shields, max_armor, max_structure, max_fuel;
      const real_t heal_shields, heal_armor, heal_structure, heal_fuel;
      const real_t fuel_efficiency;
      const AABB aabb; // of ship, either guessed or from GDScript ShipSpecs
      const real_t turn_drag;
      const real_t radius, radiussq; // effective radius of ship from aabb (and squared)
      const real_t empty_mass, fuel_inverse_density, armor_inverse_density;
      const faction_index_t faction; // faction number
      const faction_mask_t faction_mask; // 2<<faction
      const real_t explosion_damage, explosion_radius, explosion_impulse;
      const int explosion_delay;
      const int explosion_type; // damage type of explosion
      const DamageArray shield_resist, shield_passthru, armor_resist, armor_passthru;
      const DamageArray structure_resist;
      const real_t max_cooling, max_energy, max_power, max_heat;
      const real_t shield_repair_heat, armor_repair_heat, structure_repair_heat;
      const real_t shield_repair_energy, armor_repair_energy, structure_repair_energy;
      const real_t only_forward_thrust_heat, only_reverse_thrust_heat, turning_thrust_heat;
      const real_t only_forward_thrust_energy, only_reverse_thrust_energy, turning_thrust_energy;
      const real_t rifting_damage_multiplier, cargo_web_radius, cargo_web_radiussq, cargo_web_strength;
      const Ref<Mesh> cargo_puff_mesh;
      
      real_t energy, heat, power, cooling, thrust, reverse_thrust, turning_thrust, efficiency;
      real_t cargo_mass, salvaged_value;
      real_t forward_thrust_heat, reverse_thrust_heat, forward_thrust_energy, reverse_thrust_energy;
      double thrust_loss;

      Countdown explosion_timer;
      fate_t fate;
      entry_t entry_method;
      double shields, armor, structure;
      real_t fuel;

      ship_ai_t ai_type;
      int ai_flags;
      goal_action_t goal_action;
      object_id goal_target;
      object_id salvage_target;
      real_t ai_work;

      object_id shield_ellipse, cargo_web;
      
      // Physics server state; do not change:
      Vector3 rotation, position, linear_velocity, angular_velocity, heading;
      real_t drag, inverse_mass;
      Vector3 inverse_inertia;
      Transform transform;

      const std::vector<std::shared_ptr<const Salvage>> salvage;
      
      std::vector<std::shared_ptr<Weapon>> weapons;
      const WeaponRanges range;

      // Lifetime counter:
      ticks_t tick;

      // Targeting and firing logic:
      PresetCountdown<ticks_per_second*3> rift_timer, no_target_timer;
      PresetCountdown<ticks_per_second*25> range_check_timer;
      PresetCountdown<ticks_per_second*15> shot_at_target_timer;
      PresetCountdown<ticks_per_second/12> standoff_range_timer;
      PresetCountdown<ticks_per_second/4> nearby_hostiles_timer;
      PresetCountdown<ticks_per_second/4> salvage_timer;
      PresetCountdown<ticks_per_second/60> confusion_timer;
      ticks_t tick_at_last_shot, ticks_since_targetting_change, ticks_since_ai_change, ticks_since_ai_check;
      real_t damage_since_targetting_change;
      Vector3 threat_vector;
      hit_id_list_t nearby_objects;
      hit_id_list_t nearby_enemies;
      ticks_t nearby_enemies_tick;
      real_t nearby_enemies_range;

      // Ship-local random number generator (just 32 bits)
      CheapRand32 rand;

      // Where we want to go; meaning depends on active ai.
      Vector3 destination;

      // Projectile collision checks use 2<<collision_layer as a mask.
      int collision_layer;

      // Randomize where we shoot:
      real_t aim_multiplier, confusion_multiplier;
      Vector3 confusion, confusion_velocity;

      // Cached calculations, updated when other info changes:
      real_t max_speed; // Terminal linear velocity
      real_t max_angular_velocity; // Terminal angular velocity
      real_t turn_diameter_squared;
      Vector3 drag_force; // Drag term in the integrated force equation
      
      bool updated_mass_stats; // Have we updated the mass and calculated values yet?
      bool cargo_web_active;
      bool immobile; // Ship cannot move for any reason
      bool inactive; // Do not run ship AI
      real_t damage_multiplier; // Reduce damage while rifting.
      bool should_autotarget; // Player only: disable auto-targeting.
      bool at_first_tick; // true iff this is the frame at which the ship spawned

    private:

      std::shared_ptr<BaseShipAI> ai;
      real_t visual_scale; // Intended to resize ship graphics when rifting
      object_id target;
      real_t cached_standoff_range;
      const Rect2 location_rect; // for SpaceHashes

    public:

      void get_object_info(CelestialInfo &info) const override;
      object_id get_object_id() const override;
      real_t get_object_radius() const override;
      Vector3 get_object_xyz() const override;
      Vector2 get_object_xz() const override;

      PROP_GET_VAL(object_id,id);
      PROP_GET_VAL(faction_index_t,faction);
      PROP_GET_VAL(faction_mask_t,faction_mask);
      PROP_GETSET_VAL(real_t,energy);
      PROP_GETSET_VAL(real_t,heat);
      PROP_GETSET_VAL(real_t,power);
      PROP_GETSET_VAL(real_t,cooling);
      PROP_GETSET_VAL(real_t,thrust);
      PROP_GETSET_VAL(real_t,reverse_thrust);
      PROP_GETSET_VAL(real_t,turning_thrust);
      PROP_GETSET_VAL(real_t,efficiency);
      PROP_GETSET_VAL(real_t,cargo_mass);
      PROP_GETSET_VAL(real_t,salvaged_value);
      PROP_GETSET_VAL(real_t,forward_thrust_heat);
      PROP_GETSET_VAL(real_t,reverse_thrust_heat);
      PROP_GETSET_VAL(real_t,forward_thrust_energy);
      PROP_GETSET_VAL(real_t,reverse_thrust_energy);
      PROP_GETSET_VAL(double,thrust_loss);
      PROP_GETSET_CONST_REF(Countdown,explosion_timer);
      PROP_GETSET_VAL(fate_t,fate);
      PROP_GETSET_VAL(ship_ai_t,ai_type);
      PROP_GETSET_VAL(entry_t,entry_method);
      PROP_GETSET_VAL(double,shields);
      PROP_GETSET_VAL(double,armor);
      PROP_GETSET_VAL(double,structure);
      PROP_GETSET_VAL(real_t,fuel);
      PROP_GETSET_VAL(int,ai_flags);
      PROP_GETSET_VAL(goal_action_t,goal_action);
      PROP_GETSET_VAL(object_id,goal_target);
      PROP_GETSET_VAL(object_id,salvage_target);
      PROP_GETSET_VAL(real_t,ai_work);
      PROP_GETSET_VAL(object_id,shield_ellipse);
      PROP_GETSET_VAL(object_id,cargo_web);
      PROP_GET_VAL(std::vector<std::shared_ptr<const Salvage>>,salvage);
      PROP_GETSET_CONST_REF(std::vector<std::shared_ptr<Weapon>>,weapons);
      PROP_GETSET_VAL(ticks_t,tick);
      PROP_GETSET_REF(PresetCountdown<ticks_per_second*3>,rift_timer);
      PROP_GETSET_REF(PresetCountdown<ticks_per_second*3>,no_target_timer);
      PROP_GETSET_REF(PresetCountdown<ticks_per_second*25>,range_check_timer);
      PROP_GETSET_REF(PresetCountdown<ticks_per_second*15>,shot_at_target_timer);
      PROP_GETSET_REF(PresetCountdown<ticks_per_second/12>,standoff_range_timer);
      PROP_GETSET_REF(PresetCountdown<ticks_per_second/4>,nearby_hostiles_timer);
      PROP_GETSET_REF(PresetCountdown<ticks_per_second/4>,salvage_timer);
      PROP_GETSET_REF(PresetCountdown<ticks_per_second/60>,confusion_timer);
      PROP_GETSET_VAL(ticks_t,tick_at_last_shot);
      PROP_GETSET_VAL(ticks_t,ticks_since_targetting_change);
      PROP_GETSET_VAL(ticks_t,ticks_since_ai_change);
      PROP_GETSET_VAL(ticks_t,ticks_since_ai_check);
      PROP_GETSET_VAL(real_t,damage_since_targetting_change);
      PROP_GETSET_REF(Vector3,threat_vector);
      PROP_GETSET_REF(hit_id_list_t,nearby_objects);
      PROP_GETSET_REF(hit_id_list_t,nearby_enemies);
      PROP_GETSET_VAL(ticks_t,nearby_enemies_tick);
      PROP_GETSET_VAL(real_t,nearby_enemies_range);
      PROP_GETSET_REF(CheapRand32,rand);
      PROP_GETSET_REF(Vector3,destination);
      PROP_GETSET_VAL(int,collision_layer);
      PROP_GETSET_VAL(real_t,aim_multiplier);
      PROP_GETSET_VAL(real_t,confusion_multiplier);
      PROP_GETSET_VAL(real_t,max_speed);
      PROP_GETSET_VAL(real_t,max_angular_velocity);
      PROP_GETSET_VAL(real_t,turn_diameter_squared);
      PROP_GETSET_REF(Vector3,drag_force);
      PROP_GETSET_VAL(bool,updated_mass_stats);
      PROP_GETSET_VAL(bool,immobile);
      PROP_GETSET_VAL(bool,inactive);
      PROP_GETSET_VAL(real_t,damage_multiplier);
      PROP_GETSET_VAL(bool,should_autotarget);
      PROP_GETSET_VAL(bool,at_first_tick);
      
      inline Vector2 get_xz() const {
        return Vector2(position.x,position.z);
      }
      inline Vector3 get_x0z() const {
        return Vector3(position.x,0,position.z);
      }
      inline Vector3 get_xyz() const {
        return Vector3(position.x,visual_height,position.z);
      }

      inline Vector3 get_position() const {
        return position;
      }
      inline Vector3 get_rotation() const {
        return rotation;
      }
      
      inline Rect2 get_location_rect_now() const {
        return Rect2(location_rect.position+Vector2(position.x,position.z),
                     location_rect.size);
      }

      inline Rect2 get_location_rect_at_0() const {
        return location_rect;
      }

      inline void ai_step(CombatEngine &ce) {
        if(ai)
          ai->ai_step(ce,*this);
      }

      const hit_id_list_t &get_ships_within_range(CombatEngine &ce, real_t desired_range);
      const hit_id_list_t &get_ships_within_unguided_weapon_range(CombatEngine &ce,real_t fudge_factor);
      const hit_id_list_t &get_ships_within_weapon_range(CombatEngine &ce,real_t fudge_factor);
      const hit_id_list_t &get_ships_within_turret_range(CombatEngine &ce, real_t fudge_factor);

      bool pull_back_to_standoff_range(const CombatEngine &ce,Ship &target,Vector3 &aim);
      bool request_stop(const CombatEngine &ce,Vector3 desired_heading,real_t max_speed);
      Vector3 aim_forward(const CombatEngine &ce,Ship &target,bool &in_range);
      void move_to_attack(const CombatEngine &ce,Ship &target);
      bool move_to_intercept(const CombatEngine &ce,double close, double slow,
                             DVector3 tgt_pos, DVector3 tgt_vel,
                             bool force_final_state);
      bool init_ship(CombatEngine &ce);
      void activate_cargo_web(CombatEngine &ce);
      void deactivate_cargo_web(CombatEngine &ce);
      
      void negate_drag_force(const CombatEngine &ce);
      real_t request_heading(const CombatEngine &ce,Vector3 new_heading);
      void request_rotation(const CombatEngine &ce,real_t rotation_factor);
      void request_thrust(const CombatEngine &ce,real_t forward, real_t reverse);
      void set_angular_velocity(const CombatEngine &ce,const Vector3 &angular_velocity);
      void set_velocity(const CombatEngine &ce,const Vector3 &velocity);
      void create_flotsam(CombatEngine &ce);
      
      real_t get_standoff_range(const Ship &target);
      
      // Determine how much money is recouped when this ship leaves the system alive:
      inline float recouped_resources() const {
        return cost * (0.3 + 0.4*armor/max_armor + 0.3*structure/max_structure)
          * (1.0f - std::clamp(tick/(300.0f*ticks_per_second),0.0f,1.0f) ) + salvaged_value;
      }
      
      static WeaponRanges make_ranges(const std::vector<std::shared_ptr<Weapon>> &weapons);
      
      bool should_update_targetting(Ship &other);

      void salvage_projectile(CombatEngine &ce,const Projectile &projectile);
      
      // Update internal state from the physics server:
      bool update_from_physics_server(PhysicsServer *server,bool hyperspace);

      // Update information derived from physics server info:
      void update_stats(PhysicsServer *state,bool hyperspace);

      // Pay for rotation or other constant usage:
      void apply_heat_and_energy_costs(const CombatEngine &ce);
      
      // Repair the ship based on information from the system (or hyperspace):
      void heal(const CombatEngine &ce);

      // Generate a Ship from GDScript objects:
      Ship(Dictionary dict, object_id id, MultiMeshManager &multimeshes);
      
      // Ship(const Ship &other); // There are strange crashes without this.
      
      ~Ship();
      
      // Update the ship's firing inaccuracy vectors:
      void update_confusion();

      // Generate the Salvage vector from GDScript datatypes:
      std::vector<std::shared_ptr<const Salvage>> get_salvage(Array a);

      // Generate the Weapon vector from GDScript datatypes:
      std::vector<std::shared_ptr<Weapon>> get_weapons(Array a, MultiMeshManager &multimeshes);

      // All damage, resist, and passthru logic:
      real_t take_damage(real_t damage,int type,real_t heat_fraction,real_t energy_fraction,real_t thrust_fraction);

      // update destination from rand
      Vector3 randomize_destination();

      // Update visual_scale:
      void set_scale(real_t scale);

      void update_near_objects(CombatEngine &ce);
        
      DVector3 stopping_point(DVector3 tgt_vel, bool &should_reverse) const;

      // Return a Dictionary to pass back to GDScript with the ship's info:
      Dictionary update_status(const std::unordered_map<object_id,Ship> &ships,
                               const std::unordered_map<object_id,Planet> &planets) const;

      inline object_id get_target() const { return target; }
      inline void new_target(object_id t) {
        if(t!=target) {
          ticks_since_targetting_change = 0;
          damage_since_targetting_change = 0;
          shot_at_target_timer.reset();
          standoff_range_timer.reset();
          cached_standoff_range=0;
          no_target_timer.reset();
          range_check_timer.reset();
          target = t;
        }
      }
      inline void clear_target() {
        if(target!=-1) {
          ticks_since_targetting_change = 0;
          damage_since_targetting_change = 0;
          shot_at_target_timer.reset();
          standoff_range_timer.reset();
          cached_standoff_range=0;
          no_target_timer.reset();
          range_check_timer.reset();
          target = -1;
        }
      }

      inline void advance_time(ticks_t idelta) {
        at_first_tick = not tick;
        tick += idelta;
        ticks_since_targetting_change+=idelta;
        ticks_since_ai_change+=idelta;
        ticks_since_ai_check+=idelta;

        explosion_timer.advance(idelta);
        rift_timer.advance(idelta);
        no_target_timer.advance(idelta);
        range_check_timer.advance(idelta);
        shot_at_target_timer.advance(idelta);
        nearby_hostiles_timer.advance(idelta);
        salvage_timer.advance(idelta);
        confusion_timer.advance(idelta);
        standoff_range_timer.advance(idelta);
      }

    private:
      void heal_stat(double &stat,double new_value,real_t heal_energy,real_t heal_heat);
      
      inline real_t make_turn_diameter_squared() const {
        // This is a surprisingly expensive calculation, according to profiling.
        // It is cached, and only updated when needed.
        real_t turn_diameter = (2*PI/max_angular_velocity) * max_speed / PI;
        return turn_diameter*turn_diameter;
      }
    };

    typedef std::unordered_map<object_id,::godot::CE::Ship>::iterator ships_iter;
    typedef std::unordered_map<object_id,::godot::CE::Ship>::const_iterator ships_const_iter;
  }
}

#endif
