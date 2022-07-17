#ifndef COMBATENGINE_H
#define COMBATENGINE_H

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

#include "CE/AsteroidField.hpp"
#include "CE/Minimap.hpp"
#include "CE/Data.hpp"
#include "CE/VisualEffects.hpp"
#include "SpaceHash.hpp"
#include "DVector3.hpp"

namespace godot {
  namespace CE {      
    class CombatEngine: public Reference {
      GODOT_CLASS(CombatEngine, Reference)

      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Game mechanics constants and settings:
      // // // // // // // // // // // // // // // // // // // // // // // // 

    public:

      static const int FIND_MISSILES = 1;
      static const int FIND_SHIPS = 2;
      static const int FIND_PLANETS = 4;
      static const int FIND_ASTEROIDS = 8;

      static const object_id id_category_shift = 48;
      static const object_id ship_id_mask = static_cast<object_id>(1)<<id_category_shift;
      static const object_id planet_id_mask = static_cast<object_id>(2)<<id_category_shift;
      static const object_id projectile_id_mask = static_cast<object_id>(3)<<id_category_shift;
      static const object_id first_asteroid_field_id_mask = static_cast<object_id>(4)<<id_category_shift;
      
      static constexpr float position_box_size = 10.0f;
      static const int max_ships_hit_per_projectile_blast = 100;
      static constexpr float search_cylinder_radius = 30.0f;
      static const int max_ships_searched_for_detonation_range = 32;
      
      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Statistics for this solar system
      // // // // // // // // // // // // // // // // // // // // // // // // 
    private:
      real_t system_fuel_recharge, center_fuel_recharge;
      bool hyperspace;

      Minimap minimap;
    
      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Management of Projectiles and Animations (physics & visual thread)
      // // // // // // // // // // // // // // // // // // // // // // // // 
    
      Ref<VisualEffects> visual_effects;
      MultiMeshManager multimeshes;
    
      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Members for the physics thread:
      // // // // // // // // // // // // // // // // // // // // // // // // 
    
      Ref<CylinderShape> search_cylinder;
      PhysicsServer *physics_server;
      PhysicsDirectSpaceState *space;
      std::unordered_map<int32_t,object_id> rid2id;
      std::unordered_map<object_id,Planet> planets;
      std::unordered_map<object_id,Ship> ships;
      std::unordered_map<object_id,Projectile> projectiles;
      std::vector<AsteroidField> asteroid_fields;
      std::unordered_map<object_id,PlayerOverrides> player_orders;
      std::vector<Dictionary> salvaged_items;
      Dictionary weapon_rotations;
      std::unordered_set<object_id> dead_ships;
      ObjectIdGenerator idgen;
      real_t delta;
      ticks_t idelta;
      object_id player_ship_id;
      int p_frame;
      int ai_ticks; // ticks since last reset

      std::shared_ptr<const Weapon> flotsam_weapon;
      
      std::unordered_map<faction_index_t,Faction> factions;
      std::unordered_map<int,float> affinities;
      faction_mask_t enemy_masks[FACTION_ARRAY_SIZE];
      faction_mask_t friend_masks[FACTION_ARRAY_SIZE];
      faction_mask_t self_masks[FACTION_ARRAY_SIZE];
      bool need_to_update_affinity_masks;
      faction_index_t player_faction_index;
      faction_mask_t player_faction_mask;
      object_id last_planet_updated;
      int last_faction_updated;
      Dictionary faction_info;
      Array encoded_salvaged_items;

      SpaceHash<object_id> flotsam_locations;
      SpaceHash<object_id> ship_locations;
      SpaceHash<object_id> missile_locations;

      Array empty_array;
      
      // For temporary use in some functions:
      std::unordered_set<object_id> update_request_id;
      mutable CheapRand32 rand;
    
      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Members for the visual thread:
      // // // // // // // // // // // // // // // // // // // // // // // // 

      VisualServer *visual_server;
      real_t v_delta;
      Vector3 v_camera_location, v_camera_size;
      int v_frame;
      RID scenario;
      bool reset_scenario;

      // For temporary use in some functions:
      std::unordered_set<object_id> objects_found;
      hit_list_t objects_hit;
      
      // Sending data from physics to visual thread:
      VisibleContentManager content;
    public:
    
      CombatEngine();
      ~CombatEngine();

      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Accessors
      // // // // // // // // // // // // // // // // // // // // // // // // 
    public:

      // Allow const access to generate random numbers
      inline uint32_t randi() const {
        return rand.randi();
      }
      inline float randf() const {
        // Random float in [0..1), uniformly distributed.
        return rand.randf();
      }
      inline float rand_angle() const {
        return rand.rand_angle();
      }
      inline Color rand_color() const {
        return rand.rand_color();
      }
      
      faction_index_t get_player_faction_index() const {
        return player_faction_index;
      }
      faction_mask_t get_player_faction_mask() const {
        return player_faction_mask;
      }
      
      std::unordered_set<object_id> &get_objects_found() {
        return objects_found;
      }
      hit_list_t &get_objects_hit() {
        return objects_hit;
      }

      PhysicsDirectSpaceState *get_space_state() {
        return space;
      }
      
      const SpaceHash<object_id> &get_flotsam_locations() const {
        return flotsam_locations;
      }
      const SpaceHash<object_id> &get_ship_locations() const {
        return ship_locations;
      }
      const SpaceHash<object_id> &get_missile_locations() const {
        return missile_locations;
      }
      const std::unordered_map<int32_t,object_id> get_rid2id() const {
        return rid2id;
      }
      
      real_t get_delta() const {
        return delta;
      }
      ticks_t get_idelta() const {
        return idelta;
      }
      real_t get_system_fuel_recharge() const {
        return system_fuel_recharge;
      }
      real_t get_center_fuel_recharge() const {
        return center_fuel_recharge;
      }
      bool is_in_hyperspace() const {
        return hyperspace;
      }
      Ref<VisualEffects> &get_visual_effects() {
        return visual_effects;
      }

      void set_weapon_rotation(const NodePath &np,real_t rotation) {
        weapon_rotations[np] = rotation;
      }
      
      inline Color get_faction_color(faction_index_t faction) const {
        auto it = factions.find(faction);
        return it==factions.end() ? Color(1,1,1,1) : it->second.get_faction_color();
      }
      inline bool is_hostile_towards(faction_index_t from_faction,faction_index_t to_faction) const {
        return enemy_masks[from_faction]&static_cast<faction_index_t>(1)<<to_faction;
      }
      inline bool is_friendly_towards(faction_index_t from_faction,faction_index_t to_faction) const {
        return friend_masks[from_faction]&static_cast<faction_index_t>(1)<<to_faction;
      }
      inline real_t affinity_towards(faction_index_t from_faction,faction_index_t to_faction) const {
        int key = Faction::affinity_key(from_faction,to_faction);
        auto it = affinities.find(key);
        return (it==affinities.end()) ? DEFAULT_AFFINITY : it->second;
      }
      
      Faction *faction_with_id(object_id id) {
        auto it = factions.find(id);
        return it == factions.end() ? nullptr : &it->second;
      }
      const Faction *faction_with_id(object_id id) const {
        auto it = factions.find(id);
        return it == factions.end() ? nullptr : &it->second;
      }

      Ship *ship_with_id(object_id id) {
        auto it = ships.find(id);
        return it == ships.end() ? nullptr : &it->second;
      }
      const Ship *ship_with_id(object_id id) const {
        auto it = ships.find(id);
        return it == ships.end() ? nullptr : &it->second;
      }

      PlayerOverrides *player_order_with_id(object_id id) {
        auto it = player_orders.find(id);
        return it == player_orders.end() ? nullptr : &it->second;
      }
      const PlayerOverrides *player_order_with_id(object_id id) const {
        auto it = player_orders.find(id);
        return it == player_orders.end() ? nullptr : &it->second;
      }

      Planet *planet_with_id(object_id id) {
        auto it = planets.find(id);
        return it == planets.end() ? nullptr : &it->second;
      }
      const Planet *planet_with_id(object_id id) const {
        auto it = planets.find(id);
        return it == planets.end() ? nullptr : &it->second;
      }

      Projectile *projectile_with_id(object_id id) {
        auto it = projectiles.find(id);
        return it == projectiles.end() ? nullptr : &it->second;
      }
      const Projectile *projectile_with_id(object_id id) const {
        auto it = projectiles.find(id);
        return it == projectiles.end() ? nullptr : &it->second;
      }

      const std::unordered_map<object_id,Planet> &get_planets() const {
        return planets;
      }
      const std::unordered_map<object_id,Projectile> &get_projectiles() const {
        return projectiles;
      }
      const std::unordered_map<object_id,Ship> &get_ships() const {
        return ships;
      }

      faction_mask_t get_enemy_mask(faction_index_t faction) const {
        return enemy_masks[faction];
      }
      faction_mask_t get_friend_mask(faction_index_t faction) const {
        return friend_masks[faction];
      }
      faction_mask_t get_self_mask(faction_index_t faction) const {
        return self_masks[faction];
      }



      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Collision detection
      // // // // // // // // // // // // // // // // // // // // // // // // 
    public:      

      size_t overlapping_circle(Vector2 center,real_t radius,faction_mask_t collision_mask,int find_what,hit_list_t &list,size_t max_hits);
      size_t overlapping_point(Vector2 point,faction_mask_t collision_mask,int find_what,hit_list_t &list,size_t max_hits);


      CelestialHit first_at_point(Vector2 point,faction_mask_t collision_mask,int find_what);
      CelestialHit first_in_circle(Vector2 start,real_t radius,faction_mask_t collision_mask,int find_what);

      CelestialHit cast_ray(Vector2 start,Vector2 end,faction_mask_t collision_mask,int find_what);

      // FIXME: Cannot implement cast_circle yet due to godot physics slowness
      // CelestialHit cast_circle(Vector2 start,Vector2 end,real_t radius,faction_mask_t collision_mask,int find_what);

    private:
      Ship *space_intersect_ray_p_ship(Vector3 point1,Vector3 point2,faction_mask_t mask);

      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Ship utilities for other classes
      // // // // // // // // // // // // // // // // // // // // // // // // 
    public:      

      ships_iter ship_for_rid(const RID &rid);
      ships_iter ship_for_rid(int rid_id);
      void explode_ship(Ship &ship);

      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Projectile creation
      // // // // // // // // // // // // // // // // // // // // // // // // 
    public:      
      void create_direct_projectile(Ship &ship,std::shared_ptr<Weapon> weapon,Vector3 position,real_t length,Vector3 rotation,object_id target);
      void create_flotsam_projectile(Ship *ship,std::shared_ptr<const Salvage> salvage_ptr,Vector3 position,real_t angle,Vector3 velocity,real_t flotsam_mass);
      void create_antimissile_projectile(Ship &ship,std::shared_ptr<Weapon> weapon,Projectile &target,Vector3 position,real_t rotation,real_t length);
      void create_projectile(Ship &ship,std::shared_ptr<Weapon> weapon,object_id target=-1);
      
      // // // // // // // // // // // // // // // // // // // // // // // // 
      // These methods are visible to Godot:
      // // // // // // // // // // // // // // // // // // // // // // // // 
    public:

      static void _register_methods();
      void _init();
      void clear_ai();
      void clear_visuals();
      void set_visual_effects(Ref<VisualEffects> visual_effects);
      void init_factions(Dictionary data);
      Array ai_step(real_t new_delta,Array new_ships,Array new_planets,
                    Array new_player_orders,RID player_ship_rid,
                    PhysicsDirectSpaceState *new_space,
                    Array update_request_rid);
      void set_system_stats(bool hyperspace, real_t system_fuel_recharge, real_t center_fuel_recharge);
      void prepare_visual_frame(RID new_scenario);
      void update_overhead_view(Vector3 location,Vector3 size,real_t projectile_scale);
      void draw_minimap_contents(RID new_canvas, Vector2 map_center, float map_radius,
                                 Vector2 minimap_center, float minimap_radius);
      void draw_minimap_rect_contents(RID new_canvas,Rect2 map,Rect2 minimap);
      void add_asteroid_field(Dictionary field_data);

    public: // FIXME: Some of these should be private


      // FIXME: missing sorted_enemy_list()

      // // // // // // // // // // // // // // // // // // // // // // // //
      // Faction methods
      // // // // // // // // // // // // // // // // // // // // // // // //
      void change_relations(faction_index_t from_faction,faction_index_t to_faction,
                            real_t how_much,bool immediate_update);
      void make_faction_state_for_gdscript(Dictionary &result);
      void update_affinity_masks();
      void update_all_faction_goals();
      void faction_ai_step();


      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Ship methods 
      // // // // // // // // // // // // // // // // // // // // // // // // 

      void setup_ai_step(const Array &new_player_orders, const Array &new_ships,
                         const Array &new_planets, const RID &player_ship_rid);
      void step_all_ships();
      void update_ship_body_state();
      void update_ship_list(const Array &update_request_rid, Array &result);
      void add_ships_and_planets(const Array &new_ships,const Array &new_planets);
      void update_player_orders(const Array &new_player_orders);

      void encode_salvaged_items_for_gdscript(Array result);

      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Asteroid methods:
      // // // // // // // // // // // // // // // // // // // // // // // // 

      void damage_asteroid(Asteroid &asteroid,double damage,int damage_type);
      void step_asteroid_fields();
      void send_asteroid_meshes();
      void add_asteroid_content(VisibleContent &content);
      
      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Projectile methods:
      // // // // // // // // // // // // // // // // // // // // // // // // 

      void integrate_projectiles();
      void add_salvaged_items(Ship &ship,const String &product_name,int count,real_t unit_mass);
      
      // // // // // // // // // // // // // // // // // // // // // // // // 
      // Visual methods:
      // // // // // // // // // // // // // // // // // // // // // // // // 

      void add_content(); // physics thread sends data to visual thread
    
    };
  }
}

#endif
