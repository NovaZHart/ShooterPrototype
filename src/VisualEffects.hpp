#ifndef VISUALEFFECTS_H
#define VISUALEFFECTS_H

#include <Shader.hpp>
#include <ArrayMesh.hpp>
#include <Ref.hpp>
#include <MeshInstance.hpp>
#include <AABB.hpp>
#include <Reference.hpp>
#include <VisualServer.hpp>
#include <ShaderMaterial.hpp>
#include <Texture.hpp>

#include <cmath>

#include "CombatEngineUtils.hpp"
#include "CombatEngineData.hpp"

namespace godot {
  class VisualEffects;

  const int EFFECTS_LIGHT_LAYER_MASK = 2;
  
  struct MeshEffect {
    enum mesh_effect_behavior {
      STATIONARY=0,
      CONSTANT_VELOCITY=1,
      CENTER_ON_TARGET1=2,
      VELOCITY_RELATIVE_TO_TARGET=3
    };

    Ref<Mesh> mesh;
    Ref<ShaderMaterial> shader_material;
    AABB lifetime_aabb;
    double start_time;
    real_t duration, time_shift;
    Vector3 velocity, relative_position;
    Transform transform;
    VisualRIDPtr instance;
    volatile bool ready, dead;
    mesh_effect_behavior behavior;
    CE::object_id target1, target2;
    MeshEffect(int dummy=0):
      mesh(), shader_material(), lifetime_aabb(), start_time(-9e9),
      duration(0.0f), time_shift(0.0f), velocity(0,0,0), relative_position(), 
      transform(), instance(), ready(false), dead(false),
      behavior(CONSTANT_VELOCITY), target1(-1), target2(-1)
    {}
    ~MeshEffect() {}
  };

  class VisualEffects: public Reference {
    GODOT_CLASS(VisualEffects, Reference)

    AABB visible_area;
    Vector3 visibility_expansion_rate;
    RID scenario;
    real_t delta;
    double now;
    CE::CheapRand32 rand;
    CE::object_id last_id;
    std::unordered_map<CE::object_id,MeshEffect> mesh_effects;
    std::vector<Vector3> vertex_holder;
    std::vector<Vector2> uv2_holder, uv_holder;
    Ref<Shader> spatial_rift_shader, zap_ball_shader, hyperspacing_polygon_shader, fade_out_texture;
    Ref<Texture> hyperspacing_texture, cargo_puff_texture;

    volatile CE::VisibleContent *visible_content;
    
    typedef std::unordered_map<CE::object_id,MeshEffect>::iterator mesh_effects_iter;
    typedef std::unordered_map<CE::object_id,MeshEffect>::const_iterator mesh_effects_citer;
    typedef std::unordered_map<CE::object_id,MeshEffect>::value_type mesh_effects_value;
  public:

    VisualEffects();
    ~VisualEffects();
    void _init();
    static void _register_methods();

    // Registered methods:
    void clear_all_effects();
    void set_shaders(Ref<Shader> spatial_rift_shader, Ref<Shader> zap_ball_shader,
                     Ref<Shader> hyperspacing_polygon_shader, Ref<Texture> hyperspacing_texture,
                     Ref<Shader> fade_out_texture,Ref<Texture> cargo_puff_texture);
    void set_visible_region(AABB visible_area, Vector3 expansion_rate);
    void set_scenario(RID scenario);
    void step_effects(real_t delta);

    // Interface for CombatEngine:
    void add_zap_pattern(real_t lifetime, Vector3 position, real_t radius, bool reverse);
    void add_zap_ball(real_t lifetime, Vector3 position, real_t radius, bool reverse);
    void add_hyperspacing_polygon(real_t duration, Vector3 position, real_t radius, bool reverse, CE::object_id id);
    void set_visible_content(CE::VisibleContent *visible);
    void add_cargo_web_puff(CE::object_id ship_id,Vector3 ship_position,Vector3 relative_position,Vector3 relative_velocity,real_t length,real_t duration,Ref<Texture> cargo_puff);
  
  private:
    CE::VisibleObject *get_object_or_make_stationary(CE::VisibleContent &vc,CE::object_id target,MeshEffect &effect);
    void step_effect(CE::VisibleContent &vc,MeshEffect &effect,VisualServer *visual_server);
    void free_unused_effects();
    void extend_zap_pattern(Vector3 left, Vector3 right, Vector3 center,
                            real_t extent, real_t radius, int depth);

    MeshEffect &add_MeshEffect(Array data, real_t duration, Vector3 position,
                               Ref<Shader> shader);
  };

}
#endif
