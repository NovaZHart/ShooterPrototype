#ifndef COMBATENGINEDATA_H
#define COMBATENGINEDATA_H

// All constants MUST match CombatEngine.gd

#define FOREVER 189000000000 /* more ticks than a game should reach (about 100 years) */
#define TICKS_LONG_AGO -9999 /* for ticks before object began (just needs to be negative) */
#define FAST 9999999 /* faster than any object should move */
#define FAR 9999999 /* farther than any distance that should be considered */
#define BIG 9999999 /* bigger than any object should be */
#define PLAYER_COLLISION_LAYER_BITS 1
#define PI 3.141592653589793

#define THREAT_EPSILON 1.0f /* Threat difference that is considered 0 */
#define AFFINITY_EPSILON 1e-9f /* Affinity difference that is considered 0 */
#define FACTION_BIT_SHIFT 24
#define FACTION_TO_MASK 16777215 /* 2**FACTION_BIT_SHIFT-1 */
#define ALL_FACTIONS FACTION_TO_MASK
#define FACTION_ARRAY_SIZE 64
#define MAX_ALLOWED_FACTION 29
#define MIN_ALLOWED_FACTION 0
#define PLAYER_FACTION 0
#define FLOTSAM_FACTION 1
#define DEFAULT_AFFINITY 0.0f /* For factions pairs with no affinity */

#define NUM_DAMAGE_TYPES 10
#define DAMAGE_TYPELESS 0    /* Damage that ignores resist and passthru (only for anti-missile) */
#define DAMAGE_LIGHT 1       /* Non-standing electromagnetic fields (ie. lasers) */
#define DAMAGE_HE_PARTICLE 2 /* Non-zero mass particles with high energy (particle beam) */
#define DAMAGE_PIERCING 3    /* Small macroscopic things moving quickly (ie. bullets) */
#define DAMAGE_IMPACT 4      /* Larger things with high momentum (ie. asteroids) */
#define DAMAGE_EM_FIELD 5    /* Standing or low-frequency EM fields (ie. EMP or big magnet) */
#define DAMAGE_GRAVITY 6     /* Strong gravity or gravity waves */
#define DAMAGE_ANTIMATTER 7  /* Antimatter particles */
#define DAMAGE_HOT_MATTER 8  /* Explosion or beam of hot gas or plasma */
#define DAMAGE_PSIONIC 9     /* Mind over matter */

#define MAX_RESIST 0.75
#define MIN_RESIST -1.0
#define MIN_PASSTHRU 0.0
#define MAX_PASSTHRU 1.0

#define PROJECTILE_POINT_WIDTH 0.001

#define SALVAGE_TIME_LIMIT 60

#include <cstdint>
#include <unordered_set>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <utility>
#include <memory>

#include <Texture.hpp>
#include <Godot.hpp>
#include <Color.hpp>
#include <Vector2.hpp>
#include <Vector3.hpp>
#include <String.hpp>
#include <Area.hpp>
#include <RID.hpp>
#include <Dictionary.hpp>
#include <Array.hpp>
#include <PhysicsDirectSpaceState.hpp>
#include <Ref.hpp>
#include <VisualServer.hpp>
#include <ResourceLoader.hpp>
#include <CylinderShape.hpp>
#include <PhysicsServer.hpp>
#include <PhysicsDirectSpaceState.hpp>
#include <Resource.hpp>
#include <AABB.hpp>
#include <Transform.hpp>
#include <PoolArrays.hpp>
#include <OS.hpp>
#include <Mesh.hpp>

#include "DVector3.hpp"
#include "ObjectIdGenerator.hpp"
#include "MultiMeshManager.hpp"

namespace godot {
  namespace CE {

    enum visual_layers {
      below_planets=-39,
      below_ships=0,
      below_projectiles=25,
      projectile_height=27,
      above_projectiles=29
    };
    
    const int max_meshes=50;
    const int max_ships=700;
    const int max_planets=300;

    typedef int64_t ticks_t;
    const ticks_t ticks_per_second = 10800;
    const ticks_t ticks_per_minute = 648000;
    const ticks_t zero_ticks = 0;
    const ticks_t inactive_ticks = -1;
    const double thrust_loss_heal = 0.5;

    class AbstractCountdown {
      // Timer that counts down to zero.
      // A negative value means the timer is not running nor ringing.
      // Zero means the timer is ringing.
      ticks_t now;
    public:
      inline bool advance(ticks_t how_much) {
        if(active())
          return 0 == (now=std::max(zero_ticks,now-how_much));
        return false;
      }
      inline bool ticking() const { return now>0; }
      inline bool alarmed() const { return not now; }
      inline bool active() const { return now>=0; }
      inline void clear_alarm() { if(alarmed()) stop(); }
      inline void stop() { now=inactive_ticks; }
      inline ticks_t ticks_left() const { return now; }
    protected:
      inline ticks_t set_ticks(ticks_t what) { now=what; return now; }
      AbstractCountdown(const AbstractCountdown &o): now(o.now) {}
      AbstractCountdown(ticks_t now): now(now) {}
      AbstractCountdown(): now(inactive_ticks) {}
      AbstractCountdown & operator = (const AbstractCountdown &o) {
        now=o.now;
        return *this;
      }
      bool operator == (const AbstractCountdown &o) const {
        return now==o.now;
      }
    };

    template<ticks_t DURATION>
    class PresetCountdown: public AbstractCountdown {
      // A countdown timer whose duration is fixed.
    public:
      static const ticks_t duration = DURATION;
      PresetCountdown(): AbstractCountdown(inactive_ticks) {}
      PresetCountdown(ticks_t duration):
        AbstractCountdown(std::clamp(duration,inactive_ticks,DURATION))
      {}
      PresetCountdown(const PresetCountdown<DURATION> &o):
        AbstractCountdown(o)
      {}
      PresetCountdown<DURATION> &operator = (const PresetCountdown<DURATION> &o) {
        set_ticks(o.ticks_left());
        return *this;
      }
      bool operator == (const PresetCountdown<DURATION> &o) const {
        return o.ticks_left()==ticks_left();
      }
      inline ticks_t reset() { return set_ticks(DURATION); }
    };

    class Countdown: public AbstractCountdown {
      // A countdown timer whose duration is set in the constructor or
      // reset() method.
    public:
      Countdown(ticks_t duration=inactive_ticks): AbstractCountdown(duration) {}
      Countdown(const Countdown &o): AbstractCountdown(o) {}
      Countdown &operator = (const Countdown &o) {
        set_ticks(o.ticks_left());
        return *this;
      }
      bool operator == (const Countdown &o) const {
        return o.ticks_left()==ticks_left();
      }
      inline ticks_t reset(ticks_t duration) { return set_ticks(duration); }
    };
    
    class CheapRand32 {
      // Low-memory-footprint, fast, 32-bit, random number, generator
      // that produces high-quality random numbers.  Note: not
      // thread-safe; multiple threads may get the same random number
      // state sometimes. Numbers and state will always be valid though.
      uint32_t state;
    public:
      CheapRand32():
        state(bob_full_avalanche(static_cast<uint32_t>(OS::get_singleton()->get_ticks_msec()/10)))
      {};
      CheapRand32(uint32_t state): state(state) {}
      inline uint32_t randi() {
        // Random 32-bit integer, uniformly distributed.
        return state=bob_full_avalanche(state);
      }
      inline float randf() {
        // Random float in [0..1), uniformly distributed.
        return int2float(state=bob_full_avalanche(state));
      }
      inline float rand_angle() {
        return randf()*2*PI;
      }

      static inline uint32_t bob_full_avalanche(uint32_t a) {
        // Generator magic from https://burtleburtle.net/bob/hash/integer.html
        // Calls to this routine are why the class is not thread-safe.
        // There is no protection against updating the state twice at the same time.
        // That means the state will be valid, but two threads may see the same
        // state if they update it at the same time.
        a = (a+0x7ed55d16) + (a<<12);
        a = (a^0xc761c23c) ^ (a>>19);
        a = (a+0x165667b1) + (a<<5);
        a = (a+0xd3a2646c) ^ (a<<9);
        a = (a+0xfd7046c5) + (a<<3);
        a = (a^0xb55a4f09) ^ (a>>16);
        return a;
      }
      
      static inline float int2float(uint32_t i) {
        // Not the fastest int->float conversion method, but is
        // simpler and more portable than bit manipulation.
        return std::min(float(i%8388608)/8388608.0f,1.0f);
      }
    };
  
    typedef std::unordered_map<int32_t,object_id> rid2id_t;
    typedef std::unordered_map<int32_t,object_id>::iterator rid2id_iter;
    typedef std::unordered_map<int32_t,object_id>::iterator rid2id_const_iter;

    struct FactionGoal;
    struct Faction;
    struct ShipGoalData;
    struct PlanetGoalData;
    struct Planet;
    struct Projectile;
    struct Weapon;
    struct Ship;

    const int EFFECTS_LIGHT_LAYER_MASK = 2;

    enum goal_action_t {
      goal_patrol = 0,  // equal or surpass enemy threat; kill enemies
      goal_raid = 1,    // control airspace or retreat; kill high-value, low-threat, ships
      goal_planet = 2,  // travel from planet to jump, or from jump to planet
      goal_avoid_and_land = 3, // pick a planet with few enemies and land there
      goal_avoid_and_rift = 4 // pick a planet with few enemies, leave from there, exit
    };
    typedef int faction_index_t;
    typedef uint64_t faction_mask_t;

    struct FactionGoal {
      const goal_action_t action;
      const faction_index_t target_faction;
      const RID target_rid; // Of planet, or RID() for system
      const object_id target_object_id; // Of planet, or -1 for system
      const float weight;
      const float radius;
      float goal_success, spawn_desire;
      Vector3 suggested_spawn_point;
      static goal_action_t action_enum_for_string(String string_goal);
      static object_id id_for_rid(const RID &rid,const rid2id_t &rid2id);
      inline void clear() {
        goal_success = 0.0f;
        spawn_desire = -std::numeric_limits<float>::infinity();
        suggested_spawn_point = Vector3(0.0f,0.0f,0.0f);
      }
      FactionGoal(Dictionary dict,const std::unordered_map<object_id,Planet> &planets,
                  const rid2id_t &rid2id);
      ~FactionGoal();
    };

    struct ShipGoalData {
      float threat; // Ship.threat
      float distsq; // square of distance to target location
      faction_mask_t faction_mask; // Ship.faction_mask
      Vector3 position; // Ship.position
    };

    struct PlanetGoalData {
      float goal_status;
      float spawn_desire;
      object_id planet;
    };

    struct TargetAdvice {
      goal_action_t action;
      float target_weight, radius;
      object_id planet;
      Vector3 position;
    };
    
    struct Faction {
      const faction_index_t faction_index;
      const float threat_per_second;
      static inline int affinity_key(const faction_index_t from_faction,
                                     const faction_index_t to_faction) {
        return to_faction | (from_faction<<FACTION_BIT_SHIFT);
      }

      Faction(Dictionary dict,const std::unordered_map<object_id,Planet> &planets,
               const rid2id_t &rid2id);
      ~Faction();

      void update_masks(const std::unordered_map<int,float> &affinities);
      void make_state_for_gdscript(Dictionary &factions);

      inline const std::vector<FactionGoal> &get_goals() const {
        return goals;
      }
      inline std::vector<FactionGoal> &get_goals() {
        return goals;
      }
      inline const std::vector<TargetAdvice> &get_target_advice() const {
        return target_advice;
      }
      inline std::vector<TargetAdvice> &get_target_advice() {
        return target_advice;
      }
      inline void clear_target_advice(int nplanets) {
        target_advice.reserve(nplanets*goals.size());
        target_advice.clear();
      }
      inline faction_mask_t get_enemy_mask() const {
        return enemy_mask;
      }
      inline faction_mask_t get_friend_mask() const {
        return friend_mask;
      }
      inline void recoup_resources(float resources) {
        recouped_resources+=std::max(resources,0.0f);
      }
    private:
      float recouped_resources;
      std::vector<FactionGoal> goals;
      std::vector<TargetAdvice> target_advice;
      faction_mask_t enemy_mask, friend_mask;
    };
    typedef std::unordered_map<faction_index_t,CE::Faction> factions_t;
    typedef std::unordered_map<faction_index_t,CE::Faction>::iterator factions_iter;
    typedef std::unordered_map<faction_index_t,CE::Faction>::const_iterator factions_const_iter;

    struct Salvage {
      const String flotsam_mesh_path;
      const float flotsam_scale;
      const String cargo_name;
      const int cargo_count;
      const float cargo_unit_mass;
      const float armor_repair;
      const float structure_repair;
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
      real_t age, scale;
      bool alive, direct_fire, possible_hit, integrate_forces;
      const std::shared_ptr<const Salvage> salvage;
      inline real_t radius() const {
        return std::max(1e-5f,detonation_range);
      }
      real_t take_damage(real_t amount);
      Projectile(object_id id,const Ship &ship,const Weapon &weapon,Projectile &target,Vector3 position,real_t scale,real_t rotation);
      Projectile(object_id id,const Ship &ship,const Weapon &weapon,object_id alternative_target=-1);
      Projectile(object_id id,const Ship &ship,const Weapon &weapon,Vector3 position,real_t scale,real_t rotation,object_id target);
      Projectile(object_id id,const Ship &ship,std::shared_ptr<const Salvage> salvage,Vector3 position,real_t rotation,Vector3 velocity,real_t mass,MultiMeshManager &multimeshes);
      ~Projectile();
    };
    typedef std::unordered_map<object_id,Projectile>::iterator projectiles_iter;
    
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

    struct Planet {
      const object_id id;
      const Vector3 rotation, position;
      const Transform transform;
      const String name;
      const RID rid;
      const real_t radius;
      const float population, industry;
      
      Planet(Dictionary dict,object_id id);
      ~Planet();
      Dictionary update_status() const;
      void update_goal_data(const Planet &other);
      void update_goal_data(const std::unordered_map<object_id,Ship> &ships);
      inline const std::vector<ShipGoalData> &get_goal_data() const { return goal_data; }

    private:
      std::vector<ShipGoalData> goal_data;
    };
    typedef std::unordered_map<object_id,Planet>::iterator planets_iter;
    typedef std::unordered_map<object_id,Planet>::const_iterator planets_const_iter;
    typedef std::vector<std::pair<RID,object_id>> ship_hit_list_t;
    typedef std::vector<std::pair<RID,object_id>>::iterator ship_hit_list_iter;
    typedef std::vector<std::pair<RID,object_id>>::const_iterator ship_hit_list_const_iter;

    struct WeaponRanges {
      real_t guns, turrets, guided, unguided, antimissile, all;
    };

    // These enums MUST match globals/CombatEngine.gd.
    enum fate_t { FATED_TO_EXPLODE=-1, FATED_TO_FLY=0, FATED_TO_DIE=1, FATED_TO_LAND=2, FATED_TO_RIFT=3 };
    enum entry_t { ENTRY_COMPLETE=0, ENTRY_FROM_ORBIT=1, ENTRY_FROM_RIFT=2, ENTRY_FROM_RIFT_STATIONARY=3 };
    enum ship_ai_t { ATTACKER_AI=0, PATROL_SHIP_AI=1, RAIDER_AI=2, ARRIVING_MERCHANT_AI=3, DEPARTING_MERCHANT_AI=4 };
    enum ai_flags { DECIDED_NOTHING=0, DECIDED_TO_LAND=1, DECIDED_TO_RIFT=2, DECIDED_TO_FLEE=4, DECIDED_TO_SALVAGE=8 };

    typedef std::array<real_t,NUM_DAMAGE_TYPES> damage_array;
    
    struct Ship {
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
      const damage_array shield_resist, shield_passthru, armor_resist, armor_passthru;
      const damage_array structure_resist;
      const real_t max_cooling, max_energy, max_power, max_heat;
      const real_t shield_repair_heat, armor_repair_heat, structure_repair_heat;
      const real_t shield_repair_energy, armor_repair_energy, structure_repair_energy;
      const real_t only_forward_thrust_heat, only_reverse_thrust_heat, turning_thrust_heat;
      const real_t only_forward_thrust_energy, only_reverse_thrust_energy, turning_thrust_energy;
      const real_t rifting_damage_multiplier, cargo_web_radius, cargo_web_radiussq, cargo_web_strength;
      const Ref<Mesh> cargo_puff_mesh;
      
      real_t energy, heat, power, cooling, thrust, reverse_thrust, turning_thrust, efficiency, cargo_mass;
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
      
      // Physics server state; do not change:
      Vector3 rotation, position, linear_velocity, angular_velocity, heading;
      real_t drag, inverse_mass;
      Vector3 inverse_inertia;
      Transform transform;

      const std::vector<std::shared_ptr<const Salvage>> salvage;
      
      std::vector<Weapon> weapons;
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
      ticks_t tick_at_last_shot, ticks_since_targetting_change, ticks_since_ai_change;
      real_t damage_since_targetting_change;
      Vector3 threat_vector;
      ship_hit_list_t nearby_objects;
      ship_hit_list_t nearby_enemies;
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
            
      real_t visual_scale; // Intended to resize ship graphics when rifting
      object_id target;
      real_t cached_standoff_range;
      const Rect2 location_rect; // for SpaceHashes

    public:

      inline Rect2 get_location_rect_now() const {
        return Rect2(location_rect.position+Vector2(position.x,position.z),
                     location_rect.size);
      }

      inline Rect2 get_location_rect_at_0() const {
        return location_rect;
      }
      
      real_t get_standoff_range(const Ship &target,ticks_t idelta);
      
      // Determine how much money is recouped when this ship leaves the system alive:
      inline float recouped_resources() const {
        return cost * (0.3 + 0.4*armor/max_armor + 0.3*structure/max_structure)
          * (1.0f - std::clamp(tick/(300.0f*ticks_per_second),0.0f,1.0f) );
      }

      // Update internal state from the physics server:
      bool update_from_physics_server(PhysicsServer *server,bool hyperspace);

      // Update information derived from physics server info:
      void update_stats(PhysicsServer *state,bool hyperspace);

      // Pay for rotation or other constant usage:
      void apply_heat_and_energy_costs(real_t delta);
      
      // Repair the ship based on information from the system (or hyperspace):
      void heal(bool hyperspace,real_t system_fuel_recharge,real_t center_fuel_recharge,real_t delta);

      // Generate a Ship from GDScript objects:
      Ship(Dictionary dict, object_id id, MultiMeshManager &multimeshes);
      
      // Ship(const Ship &other); // There are strange crashes without this.
      
      ~Ship();
      
      // Update the ship's firing inaccuracy vectors:
      void update_confusion();

      // Generate the Salvage vector from GDScript datatypes:
      std::vector<std::shared_ptr<const Salvage>> get_salvage(Array a);

      // Generate the Weapon vector from GDScript datatypes:
      std::vector<Weapon> get_weapons(Array a, MultiMeshManager &multimeshes);

      // All damage, resist, and passthru logic:
      real_t take_damage(real_t damage,int type,real_t heat_fraction,real_t energy_fraction,real_t thrust_fraction);

      // update destination from rand
      Vector3 randomize_destination();

      // Update visual_scale:
      void set_scale(real_t scale);
      
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

        explosion_timer.advance(idelta);
        rift_timer.advance(idelta);
        no_target_timer.advance(idelta);
        range_check_timer.advance(idelta);
        shot_at_target_timer.advance(idelta);
        nearby_hostiles_timer.advance(idelta);
        salvage_timer.advance(idelta);
        confusion_timer.advance(idelta);
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

    class select_flying {
      // Filter for target selection logic. Allows only ships that are
      // not leaving the system nor already gone.
    public:
      select_flying() {};
      template<class I>
      bool operator () (I iter) const {
        return not iter->second.fate;
      }
    };

    
    typedef std::unordered_map<object_id,Ship>::iterator ships_iter;
    typedef std::unordered_map<object_id,Ship>::const_iterator ships_const_iter;
    typedef std::vector<std::pair<Vector3,ships_iter>> projectile_hit_list_t;

  
    static constexpr real_t hyperspace_display_ratio = 20.0f;

    // These constants MUST match globals/CombatEngine.gd.

    const float SPATIAL_RIFT_LIFETIME_SECS = 3.0f;
    const ticks_t SPATIAL_RIFT_LIFETIME_TICKS = roundf(SPATIAL_RIFT_LIFETIME_SECS*ticks_per_second);

    static const int PLAYER_GOAL_ATTACKER_AI = 1;
    static const int PLAYER_GOAL_LANDING_AI = 2;
    static const int PLAYER_GOAL_ARRIVING_MERCHANT_AI = 3;
    static const int PLAYER_GOAL_INTERCEPT = 4;
    static const int PLAYER_GOAL_RIFT = 5;
    
    static const int PLAYER_ORDERS_MAX_GOALS = 3;

    static const int PLAYER_ORDER_FIRE_PRIMARIES   = 0x0001;
    static const int PLAYER_ORDER_STOP_SHIP        = 0x0002;
    static const int PLAYER_ORDER_MAINTAIN_SPEED   = 0x0004;
    static const int PLAYER_ORDER_AUTO_TARGET      = 0x0008;
    static const int PLAYER_ORDER_TOGGLE_CARGO_WEB = 0x0010;
    
    static const int PLAYER_TARGET_CONDITION       = 0xF000;
    static const int PLAYER_TARGET_NEXT            = 0x1000;
    static const int PLAYER_TARGET_NEAREST         = 0x2000;

    static const int PLAYER_TARGET_SELECTION       = 0x0F00;
    static const int PLAYER_TARGET_ENEMY           = 0x0100;
    static const int PLAYER_TARGET_FRIEND          = 0x0200;
    static const int PLAYER_TARGET_PLANET          = 0x0400;
    static const int PLAYER_TARGET_OVERRIDE        = 0x0800;
    static const int PLAYER_TARGET_NOTHING         = 0x0F00;

    struct GoalsArray {
      int goal[PLAYER_ORDERS_MAX_GOALS];
      GoalsArray();
      GoalsArray(const Array &);
    };
    
    struct PlayerOverrides {
      const real_t manual_thrust, manual_rotation;
      const int orders, change_target;
      object_id target_id;
      const GoalsArray goals;
      PlayerOverrides();
      PlayerOverrides(Dictionary from,const rid2id_t &rid2id);
      ~PlayerOverrides();
    };
    typedef std::unordered_map<object_id,PlayerOverrides>::iterator player_orders_iter;

    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Internal data structures for visual thread
    // // // // // // // // // // // // // // // // // // // // // // // // 

    static const int VISIBLE_OBJECT_PROJECTILE = 0;
    static const int VISIBLE_OBJECT_PLANET = 1;
    static const int VISIBLE_OBJECT_SHIP = 2;
    static const int VISIBLE_OBJECT_HOSTILE = 4;
    static const int VISIBLE_OBJECT_PLAYER_TARGET = 8;
    static const int VISIBLE_OBJECT_PLAYER = 16;

    // FIXME: Implement this:
    const int VISIBLE_OBJECT_GOAL = 32;
  }
}


#endif
