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
#include "SpaceHash.hpp"
#include "DVector3.hpp"

namespace godot {
      
  class CombatEngine: public Reference {
    GODOT_CLASS(CombatEngine, Reference)

    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Game mechanics constants and settings:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    static constexpr float position_box_size = 10.0f;
    static const int max_ships_hit_per_projectile_blast = 100;
    static constexpr float search_cylinder_radius = 30.0f;
    static constexpr real_t crosshairs_width = 1;
    real_t system_fuel_recharge, center_fuel_recharge;
    bool hyperspace;

    
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
    std::unordered_map<object_id,CE::Planet> planets;
    std::unordered_map<object_id,CE::Ship> ships;
    std::unordered_map<object_id,CE::Projectile> projectiles;
    std::unordered_map<object_id,CE::PlayerOverrides> player_orders;
    std::unordered_multimap<object_id,std::shared_ptr<const CE::Salvage>> salvaged_items;
    Dictionary weapon_rotations;
    std::unordered_set<object_id> dead_ships;
    ObjectIdGenerator idgen;
    real_t delta;
    CE::ticks_t idelta;
    object_id player_ship_id;
    int p_frame;
    int ai_ticks; // ticks since last reset

    std::unordered_map<CE::faction_index_t,CE::Faction> factions;
    std::unordered_map<int,float> affinities;
    CE::faction_mask_t enemy_masks[FACTION_ARRAY_SIZE];
    CE::faction_mask_t friend_masks[FACTION_ARRAY_SIZE];
    CE::faction_mask_t self_masks[FACTION_ARRAY_SIZE];
    bool need_to_update_affinity_masks;
    CE::faction_index_t player_faction_index;
    CE::faction_mask_t player_faction_mask;
    object_id last_planet_updated;
    int last_faction_updated;
    Dictionary faction_info;
    Array encoded_salvaged_items;

    SpaceHash<object_id> flotsam_locations;
    SpaceHash<object_id> ship_locations;
    SpaceHash<object_id> missile_locations;
    
    // For temporary use in some functions:
    std::unordered_set<object_id> update_request_id;
    mutable std::vector<CE::PlanetGoalData> planet_goal_data;
    mutable std::vector<float> goal_weight_data;
    mutable CE::CheapRand32 rand;
    
    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Members for the visual thread:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    VisualServer *visual_server;
    real_t v_delta;
    Vector3 v_camera_location, v_camera_size;
    int v_frame;
    RID scenario, canvas;
    bool reset_scenario;

    // For temporary use in some functions:
    std::unordered_set<object_id> objects_found;
    std::vector<std::pair<real_t,std::pair<RID,object_id>>> search_results;
    
    // Sending data from physics to visual thread:
    VisibleContentManager content;
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
    void draw_minimap_rect_contents(RID new_canvas,Rect2 map,Rect2 minimap);

  protected:


    // FIXME: missing sorted_enemy_list()

    // // // // // // // // // // // // // // // // // // // // // // // //
    // Faction methods
    // // // // // // // // // // // // // // // // // // // // // // // //
    inline bool is_hostile_towards(CE::faction_index_t from_faction,CE::faction_index_t to_faction) const {
      return enemy_masks[from_faction]&static_cast<CE::faction_index_t>(1)<<to_faction;
    }
    inline bool is_friendly_towards(CE::faction_index_t from_faction,CE::faction_index_t to_faction) const {
      return friend_masks[from_faction]&static_cast<CE::faction_index_t>(1)<<to_faction;
    }
    inline real_t affinity_towards(CE::faction_index_t from_faction,CE::faction_index_t to_faction) const {
      int key = CE::Faction::affinity_key(from_faction,to_faction);
      std::unordered_map<int,float>::const_iterator it = affinities.find(key);
      return (it==affinities.end()) ? DEFAULT_AFFINITY : it->second;
    }
    void change_relations(CE::faction_index_t from_faction,CE::faction_index_t to_faction,
                          real_t how_much,bool immediate_update);
    void make_faction_state_for_gdscript(Dictionary &result);
    void update_affinity_masks();
    CE::PlanetGoalData update_planet_faction_goal(const CE::Faction &faction, const CE::Planet &planet, const CE::FactionGoal &goal) const;
    void update_one_faction_goal(CE::Faction &faction, CE::FactionGoal &goal) const;
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
    void negate_drag_force(CE::Ship &ship);
    void rift_ai(CE::Ship &ship);
    void explode_ship(CE::Ship &ship);
    void ai_step_ship(CE::Ship &ship);
    bool init_ship(CE::Ship &ship);

    bool pull_back_to_standoff_range(CE::Ship &ship,CE::Ship &target,Vector3 &aim);
    real_t time_of_closest_approach(Vector3 dp,Vector3 dv);
    void fire_antimissile_turrets(CE::Ship &ship);
    void activate_cargo_web(CE::Ship &ship);
    void deactivate_cargo_web(CE::Ship &ship);
    void use_cargo_web(CE::Ship &ship);
    bool apply_player_orders(CE::Ship &ship,CE::PlayerOverrides &overrides);
    bool apply_player_goals(CE::Ship &ship,CE::PlayerOverrides &overrides);
    void update_near_objects_using_godot_physics(CE::Ship &ship);
    void find_ships_in_radius(Vector3 position,real_t radius,CE::faction_mask_t faction_mask,std::vector<std::pair<real_t,std::pair<RID,object_id>>> &results);
    void update_near_objects_using_ship_locations(CE::Ship &ship);
    bool should_update_targetting(CE::Ship &ship,CE::ships_iter &other);
    CE::ships_iter update_targetting(CE::Ship &ship);
    void attacker_ai(CE::Ship &ship);
    void patrol_ship_ai(CE::Ship &ship);
    void raider_ai(CE::Ship &ship);
    void salvage_ai(CE::Ship &ship);
    bool should_salvage(CE::Ship &ship);
    void landing_ai(CE::Ship &ship);
    void arriving_merchant_ai(CE::Ship &ship);
    bool patrol_ai(CE::Ship &ship);
    void choose_target_by_goal(CE::Ship &ship,bool prefer_strong_targets,CE::goal_action_t goal_filter,real_t min_weight_to_target,real_t override_distance,bool avoid_targets) const;
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
    std::pair<DVector3,double> plot_collision_course(DVector3 relative_position,DVector3 target_velocity,double max_speed);
    bool move_to_intercept(CE::Ship &ship,double close, double slow,
                           DVector3 tgt_pos, DVector3 tgt_vel,
                           bool force_final_state);
    real_t request_heading(CE::Ship &ship, Vector3 new_heading);
    void request_rotation(CE::Ship &ship, real_t rotation_factor);
    void request_thrust(CE::Ship &ship, real_t forward, real_t reverse);
    void set_angular_velocity(CE::Ship &ship,const Vector3 &angular_velocity);
    void set_velocity(CE::Ship &ship,const Vector3 &velocity);
    void heal_ship(CE::Ship &ship);
    void encode_salvaged_items_for_gdscript(Array result);
    
    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Projectile methods:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    void integrate_projectiles();
    void create_direct_projectile(CE::Ship &ship,CE::Weapon &weapon,Vector3 position,real_t length,Vector3 rotation,object_id target);
    void create_flotsam(CE::Ship &ship);
    void create_antimissile_projectile(CE::Ship &ship,CE::Weapon &weapon,CE::Projectile &target,Vector3 position,real_t rotation,real_t length);
    void create_projectile(CE::Ship &ship,CE::Weapon &weapon,object_id target=-1);
    CE::ships_iter ship_for_rid(const RID &rid);
    CE::ships_iter ship_for_rid(int rid_id);
    CE::projectile_hit_list_t find_projectile_collisions(CE::Projectile &projectile,real_t radius,int max_results=32);
    bool collide_point_projectile(CE::Projectile &projectile);
    CE::ships_iter space_intersect_ray_p_ship(Vector3 point1,Vector3 point2,int mask);
    bool collide_projectile(CE::Projectile &projectile);
    void salvage_projectile(CE::Ship &ship,CE::Projectile &projectile);
    CE::ships_iter get_projectile_target(CE::Projectile &projectile);
    void guide_projectile(CE::Projectile &projectile);
    bool is_eta_lower_with_thrust(DVector3 target_position,DVector3 target_velocity,const CE::Projectile &proj,DVector3 heading,DVector3 desired_heading);
    void integrate_projectile_forces(CE::Projectile &projectile, real_t thrust_fraction, bool drag);
    Dictionary space_intersect_ray(PhysicsDirectSpaceState *space,Vector3 point1,Vector3 point2,int mask);

    // // // // // // // // // // // // // // // // // // // // // // // // 
    // Visual methods:
    // // // // // // // // // // // // // // // // // // // // // // // // 

    void add_content(); // physics thread sends data to visual thread
    
    Vector2 place_center(const Vector2 &where,
                         const Vector2 &map_center,float map_radius,
                         const Vector2 &minimap_center,float minimap_radius);
    Vector2 place_in_rect(const Vector2 &map_location,
                          const Vector2 &map_center,const Vector2 &map_scale,
                          const Vector2 &minimap_center,const Vector2 &minimap_half_size);
    void draw_anulus(const Vector2 &center,float inner_radius,float outer_radius,
                     const Color &color,bool antialiased);
    void draw_crosshairs(const Vector2 &loc, float minimap_radius, const Color &color);
    void rect_draw_velocity(VisibleObject &ship, const Vector2 &loc,
                            const Vector2 &map_center,const Vector2 &map_scale,
                            const Vector2 &minimap_center,const Vector2 &minimap_half_size,
                            const Color &color);
    void rect_draw_heading(VisibleObject &ship, const Vector2 &loc,
                           const Vector2 &map_center,const Vector2 &map_scale,
                           const Vector2 &minimap_center,const Vector2 &minimap_half_size,
                           const Color &color);

    void draw_velocity(VisibleObject &ship, const Vector2 &loc,
                       const Vector2 &map_center,real_t map_radius,
                       const Vector2 &minimap_center,real_t minimap_radius,
                       const Color &color);
    void draw_heading(VisibleObject &ship, const Vector2 &loc,
                      const Vector2 &map_center,real_t map_radius,
                      const Vector2 &minimap_center,real_t minimap_radius,
                      const Color &color);
    const Color &pick_object_color(VisibleObject &object);
  };

}

#endif
