#ifndef COMBATENGINE_H
#define COMBATENTINE_H

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

#include "CombatEngineData.hpp"
#include "VisualEffects.hpp"

namespace godot {
      
  class CombatEngine: public Reference {
    GODOT_CLASS(CombatEngine, Reference)

    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Game mechanics constants and settings:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    static const int max_ships_hit_per_projectile_blast = 100;
    static constexpr float search_cylinder_radius = 30.0f;
    static constexpr real_t crosshairs_width = 1;
    real_t system_fuel_recharge, center_fuel_recharge;
    bool hyperspace;
  
    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Members for the physics thread:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    Ref<VisualEffects> visual_effects;
    
    Ref<CylinderShape> search_cylinder;
    PhysicsServer *physics_server;
    PhysicsDirectSpaceState *space;
    std::unordered_map<int32_t,CE::object_id> rid2id;
    std::unordered_map<CE::object_id,CE::Planet> planets;
    std::unordered_map<CE::object_id,CE::Ship> ships;
    std::unordered_map<CE::object_id,CE::Projectile> projectiles;
    std::unordered_map<CE::object_id,CE::PlayerOverrides> player_orders;
    std::unordered_map<String,CE::object_id,CE::hash_String> path2mesh;
    std::unordered_map<CE::object_id,String> mesh2path;
    Dictionary weapon_rotations;
    std::unordered_set<CE::object_id> dead_ships;
    CE::object_id last_id;
    real_t delta;
    CE::object_id player_ship_id;

    std::unordered_map<faction_index_t,CE::Faction> factions;
    std::unordered_map<int,float> affinities;
    faction_mask_t enemy_masks[MAX_ACTIVE_FACTIONS];
    faction_mask_t friend_masks[MAX_ACTIVE_FACTIONS];
    faction_mask_t self_masks[MAX_ACTIVE_FACTIONS];
    bool need_to_update_affinity_masks;

    // For temporary use in some functions:
    std::unordered_set<CE::object_id> update_request_id;
    
    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Members for the visual thread:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    ResourceLoader *loader;
    VisualServer *visual_server;
    std::unordered_map<CE::object_id,CE::MeshInfo> v_meshes;
    typedef std::unordered_map<CE::object_id,CE::MeshInfo>::iterator v_meshes_iter;
    std::unordered_map<String,CE::object_id,CE::hash_String> v_path2id;
    std::unordered_set<String,CE::hash_String> v_invalid_paths;
    real_t v_delta;
    Vector3 v_camera_location, v_camera_size;
    int v_tick;
    RID scenario, canvas;
    bool reset_scenario;

    // For temporary use in some functions:
    CE::instance_locations_t instance_locations;
    std::unordered_set<CE::object_id> need_new_meshes;
    
    // Sending data from physics to visual thread:
    CE::VisibleContent *volatile new_content;
    CE::VisibleContent *visible_content;
    
  public:

    
    CombatEngine();
    ~CombatEngine();

    // // // // // // // // // // // // // // // // // // // // // // // // 
    // These methods are visible to Godot:
    // // // // // // // // // // // // // // // // // // // // // // // // 
    
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

  protected:


    // FIXME: missing sorted_enemy_list()

    // // // // // // // // // // // // // // // // // // // // // // // //
    // Faction methods
    // // // // // // // // // // // // // // // // // // // // // // // //
    inline bool is_hostile_towards(faction_index_t from_faction,faction_index_t to_faction) const {
      return enemy_masks(from_faction)&static_cast<faction_index_t>(1)<<to_faction;
    }
    inline bool is_friendly_towards(faction_index_t from_faction,faction_index_t to_faction) const {
      return friend_masks(from_faction)&static_cast<faction_index_t>(1)<<to_faction;
    }
    void change_relations(faction_index_t from_faction,faction_index_t to_faction,
                          float how_much,bool immediate_update);
    void update_affinity_masks();
    
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
    void negate_drag_force(CE::Ship &ship);
    void rift_ai(CE::Ship &ship);
    void explode_ship(CE::Ship &ship);
    void ai_step_ship(CE::Ship &ship);
    bool init_ship(CE::Ship &ship);
    bool apply_player_orders(CE::Ship &ship,CE::PlayerOverrides &overrides);
    bool apply_player_goals(CE::Ship &ship,CE::PlayerOverrides &overrides);
    void update_near_objects(CE::Ship &ship);
    CE::ships_iter update_targetting(CE::Ship &ship);
    void attacker_ai(CE::Ship &ship);
    void landing_ai(CE::Ship &ship);
    void coward_ai(CE::Ship &ship);
    bool patrol_ai(CE::Ship &ship);
    Vector3 make_threat_vector(CE::Ship &ship, real_t t);
    void evade(CE::Ship &ship);
    void aim_turrets(CE::Ship &ship,CE::ships_iter &target);
    Vector3 aim_forward(CE::Ship &ship,CE::Ship &target,bool &in_range);
    bool request_stop(CE::Ship &ship,Vector3 desired_heading,real_t max_speed);
    double rendezvous_time(Vector3 target_location,Vector3 target_velocity,
                           double interception_speed);
    void fire_primary_weapons(CE::Ship &ship);
    void player_auto_target(CE::Ship &ship);
    Dictionary check_target_lock(CE::Ship &target, Vector3 point1, Vector3 point2);
    const CE::ship_hit_list_t &get_ships_within_range(CE::Ship &ship, real_t desired_range);
    const CE::ship_hit_list_t &get_ships_within_unguided_weapon_range(CE::Ship &ship,real_t fudge_factor);
    const CE::ship_hit_list_t &get_ships_within_weapon_range(CE::Ship &ship,real_t fudge_factor);
    const CE::ship_hit_list_t &get_ships_within_turret_range(CE::Ship &ship, real_t fudge_factor);
    bool fire_direct_weapon(CE::Ship &ship,CE::Weapon &weapon,bool allow_untargeted);
    void auto_fire(CE::Ship &ship, CE::ships_iter &target);
    void move_to_attack(CE::Ship &ship,CE::Ship &target);
    bool move_to_intercept(CE::Ship &ship,double close, double slow,
                           DVector3 tgt_pos, DVector3 tgt_vel,
                           bool force_final_state);
    real_t request_heading(CE::Ship &ship, Vector3 new_heading);
    void request_rotation(CE::Ship &ship, real_t rotation_factor);
    void request_thrust(CE::Ship &ship, real_t forward, real_t reverse);
    void set_angular_velocity(CE::Ship &ship,const Vector3 &angular_velocity);
    void set_velocity(CE::Ship &ship,const Vector3 &velocity);

    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Projectile methods:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    void integrate_projectiles();
    void create_direct_projectile(CE::Ship &ship,CE::Weapon &weapon,Vector3 position,real_t length,Vector3 rotation,CE::object_id target);
    void create_projectile(CE::Ship &ship,CE::Weapon &weapon);
    CE::ships_iter ship_for_rid(const RID &rid);
    CE::ships_iter ship_for_rid(int rid_id);
    CE::projectile_hit_list_t find_projectile_collisions(CE::Projectile &projectile,real_t radius,int max_results=32);
    bool collide_point_projectile(CE::Projectile &projectile);
    CE::ships_iter space_intersect_ray_p_ship(Vector3 point1,Vector3 point2,int mask);
    bool collide_projectile(CE::Projectile &projectile);
    void guide_projectile(CE::Projectile &projectile);
    void velocity_to_heading(CE::Projectile &projectile);


    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Visual methods:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    void add_content(); // physics thread sends data to visual thread
    
    void warn_invalid_mesh(CE::MeshInfo &mesh,const String &why);
    bool allocate_multimesh(CE::MeshInfo &mesh_info,int count);
    bool update_visual_instance(CE::MeshInfo &mesh_info);
    bool load_mesh(CE::MeshInfo &mesh_info);
    void clear_all_multimeshes();
    void unused_multimesh(CE::MeshInfo &mesh_info);
    void pack_projectiles(const std::pair<CE::instlocs_iterator,CE::instlocs_iterator> &projectiles,
                          PoolRealArray &floats,CE::MeshInfo &mesh_info,real_t projectile_scale);
    void catalog_projectiles(const Vector3 &location,const Vector3 &size,
                             CE::instance_locations_t &instance_locations,
                             std::unordered_set<CE::object_id> &need_new_meshes);
    Vector2 place_center(const Vector2 &where,
                         const Vector2 &map_center,float map_radius,
                         const Vector2 &minimap_center,float minimap_radius);
    void draw_anulus(const Vector2 &center,float inner_radius,float outer_radius,
                     const Color &color,bool antialiased);
    void draw_crosshairs(const Vector2 &loc, float minimap_radius, const Color &color);
    void draw_velocity(CE::VisibleObject &ship, const Vector2 &loc,
                       const Vector2 &map_center,real_t map_radius,
                       const Vector2 &minimap_center,real_t minimap_radius,
                       const Color &color);
    void draw_heading(CE::VisibleObject &ship, const Vector2 &loc,
                      const Vector2 &map_center,real_t map_radius,
                      const Vector2 &minimap_center,real_t minimap_radius,
                      const Color &color);
    const Color &pick_object_color(CE::VisibleObject &object);
  };

}

#endif
