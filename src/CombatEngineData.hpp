#ifndef COMBATENGINEDATA_H
#define COMBATENGINEDATA_H

#include "DVector3.hpp"

#define FOREVER 189000000000 /* more ticks than a game should reach (about 100 years) */
#define TICKS_LONG_AGO -9999 /* for ticks before object began (just needs to be negative) */
#define FAST 9999999 /* faster than any object should move */
#define FAR 9999999 /* farther than any distance that should be considered */
#define BIG 9999999 /* bigger than any object should be */
#define PLAYER_COLLISION_LAYER_BITS 1
#define PROJECTILE_HEIGHT 27
#define PI 3.141592653589793

#include <unordered_set>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <utility>

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

namespace godot {
  namespace CE {
    typedef int object_id;
      
    struct hash_String {
      inline int operator() (const String &s) const {
        return s.hash();
      }
    };
  
    typedef std::unordered_map<String,object_id,hash_String> path2mesh_t;
    typedef std::unordered_map<object_id,String> mesh2path_t;
    typedef std::unordered_map<int32_t,object_id> rid2id_t;
    typedef std::unordered_map<int32_t,object_id>::iterator rid2id_iter;
    typedef std::unordered_map<int32_t,object_id>::iterator rid2id_const_iter;

    const int SHIP_LIGHT_LAYER_MASK = 4;
  
    struct ProjectileMesh {
      object_id id;
      RID mesh_id;

      bool has_multimesh;
      RID multimesh_id;
      int instance_count, visible_instance_count;

      ProjectileMesh(RID, object_id);
      ~ProjectileMesh();
    };

    struct Projectile;
    struct Weapon;
    struct Ship;
    
    struct Projectile {
      const object_id id;
      const object_id target;
      const object_id mesh_id;
      const bool guided, guidance_uses_velocity;
      const real_t damage, impulse, blast_radius, detonation_range, turn_rate;
      const real_t mass, drag, thrust, lifetime, initial_velocity, max_speed;
      const int collision_mask;
      Vector3 position, linear_velocity, rotation, angular_velocity;
      real_t age, scale;
      bool alive, direct_fire;
      Projectile(object_id id,const Ship &ship,const Weapon &weapon);
      Projectile(object_id id,const Ship &ship,const Weapon &weapon,Vector3 position,real_t scale,real_t rotation,object_id target);
      ~Projectile();
    };
    typedef std::unordered_map<object_id,Projectile>::iterator projectiles_iter;
    
    struct Weapon {
      const real_t damage, impulse, initial_velocity;
      const real_t projectile_mass, projectile_drag, projectile_thrust, projectile_lifetime;
      const real_t projectile_turn_rate;
      const real_t firing_delay, turn_rate, blast_radius, detonation_range, threat;
      const bool direct_fire, guided, guidance_uses_velocity;
      const RID instance_id;
      const object_id mesh_id;
      const real_t terminal_velocity, projectile_range;
      const NodePath node_path;
      const bool is_turret;
      
      Vector3 position, rotation;
      const real_t harmony_angle;
      real_t firing_countdown;
      
      Weapon(Dictionary dict,object_id &last_id,mesh2path_t &mesh2path,path2mesh_t &path2mesh);
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
      
      Planet(Dictionary dict,object_id id);
      ~Planet();
      Dictionary update_status(const std::unordered_map<object_id,Ship> &ships,
                               const std::unordered_map<object_id,Planet> &planets) const;
    };
    typedef std::unordered_map<object_id,Planet>::iterator planets_iter;
    typedef std::unordered_map<object_id,Planet>::const_iterator planets_const_iter;
    typedef std::vector<std::pair<RID,object_id>> ship_hit_list_t;
    typedef std::vector<std::pair<RID,object_id>>::iterator ship_hit_list_iter;
    typedef std::vector<std::pair<RID,object_id>>::const_iterator ship_hit_list_const_iter;

    struct WeaponRanges {
      real_t guns, turrets, guided, unguided, all;
    };

    enum fate_t { FATED_TO_EXPLODE=-1, FATED_TO_FLY=0, FATED_TO_DIE=1, FATED_TO_LAND=2 };
    
    struct Ship {
      const object_id id;
      const String name; // last element of node path
      const RID rid; // of rigid body
      const real_t thrust, reverse_thrust;
      const real_t max_angular_velocity;
      const real_t threat;
      const real_t max_shields, max_armor, max_structure;
      const real_t heal_shields, heal_armor, heal_structure;
      const AABB aabb;
      const real_t radius;
      const int collision_layer, enemy_mask;
      const real_t explosion_damage, explosion_radius, explosion_impulse;
      const int explosion_delay;
      
      int explosion_tick;
      
      fate_t fate;
      
      real_t shields, armor, structure;
      Vector3 rotation, position, linear_velocity, angular_velocity, heading;
      real_t drag, inverse_mass;
      Vector3 inverse_inertia;
      Transform transform;
      std::vector<Weapon> weapons;
      const WeaponRanges range;
      int tick, tick_at_last_shot;
      object_id target;
      Vector3 threat_vector;
      ship_hit_list_t nearby_objects;
      ship_hit_list_t nearby_enemies;
      int nearby_enemies_tick;
      real_t nearby_enemies_range;
      uint32_t random_state;
      Vector3 destination;

      real_t aim_multiplier, confusion_multiplier;
      Vector3 confusion, confusion_velocity;

      const real_t max_speed,turn_diameter_squared;

      inline Vector3 drag_force() const {
        return -linear_velocity*drag/inverse_mass;
      }

      Ship(const Ship &other);
      Ship(Dictionary dict, object_id id, object_id &last_id,
           mesh2path_t &mesh2path,path2mesh_t &path2mesh);
      ~Ship();
      void update_confusion();
      std::vector<Weapon> get_weapons(Array a, object_id &last_id, mesh2path_t &mesh2path, path2mesh_t &path2mesh);
      real_t take_damage(real_t damage);
      Vector3 randomize_destination();
      DVector3 stopping_point(DVector3 tgt_vel, bool &should_reverse) const;
      Dictionary update_status(const std::unordered_map<object_id,Ship> &ships,
                               const std::unordered_map<object_id,Planet> &planets) const;
    private:
      inline real_t make_turn_diameter_squared() const {
        real_t turn_diameter = (2*PI/max_angular_velocity) * max_speed / PI;
        return turn_diameter*turn_diameter;
      }
    };

    class select_flying {
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

  


    static const int PLAYER_GOAL_ATTACKER_AI = 1;
    static const int PLAYER_GOAL_LANDING_AI = 2;
    static const int PLAYER_GOAL_COWARD_AI = 3;
    static const int PLAYER_GOAL_INTERCEPT = 4;
    
    static const int PLAYER_ORDERS_MAX_GOALS = 3;

    static const int PLAYER_ORDER_FIRE_PRIMARIES = 1;
    static const int PLAYER_ORDER_STOP_SHIP = 2;
    static const int PLAYER_ORDER_MAINTAIN_SPEED = 4;
    
    static const int PLAYER_TARGET_CONDITION = 0xF00;
    static const int PLAYER_TARGET_NEXT = 0x100;
    static const int PLAYER_TARGET_NEAREST = 0x200;

    static const int PLAYER_TARGET_SELECTION = 0xF0;
    static const int PLAYER_TARGET_ENEMY = 0x10;
    static const int PLAYER_TARGET_FRIEND = 0x20;
    static const int PLAYER_TARGET_PLANET = 0x30;
    static const int PLAYER_TARGET_OVERRIDE= 0x40;
    static const int PLAYER_TARGET_NOTHING = 0xF0;

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

    struct VisibleObject {
      const real_t x, z, radius, rotation_y, vx, vz, max_speed;
      int flags;
      VisibleObject(const Ship &);
      VisibleObject(const Planet &);
    };

    struct VisibleProjectile {
      const real_t rotation_y, scale_x;
      const Vector2 center, half_size;
      const int type;
      const object_id mesh_id;
      VisibleProjectile(const Projectile &);
    };
    typedef std::vector<VisibleProjectile>::iterator visible_projectiles_iter;

    struct MeshInstanceInfo {
      const real_t x, z, rotation_y, scale_x;
    };
    typedef std::unordered_multimap<object_id,MeshInstanceInfo> instance_locations_t;
    typedef std::unordered_multimap<object_id,MeshInstanceInfo>::iterator instlocs_iterator;
    
    struct VisibleContent {
      std::vector<VisibleObject> ships_and_planets;
      std::vector<VisibleProjectile> projectiles;
      std::unordered_map<object_id,String> mesh_paths;
      VisibleContent *next;
      VisibleContent();
      ~VisibleContent();
    };
    typedef std::unordered_map<object_id,String>::iterator mesh_paths_iter;
    
    struct MeshInfo {
      const object_id id;
      const String resource_path;
      Ref<Resource> mesh_resource;
      RID mesh_rid, multimesh_rid, visual_rid;
      int instance_count, visible_instance_count, last_tick_used;
      bool invalid;
      PoolRealArray floats;
      MeshInfo(object_id,const String &);
      ~MeshInfo();
    };

  }
}


#endif
