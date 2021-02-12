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

#include <cmath>

#include "CombatEngineUtils.hpp"

namespace godot {
  class VisualEffects;
  
  struct MeshEffect {
    Ref<Mesh> mesh;
    Ref<ShaderMaterial> shader_material;
    AABB lifetime_aabb;
    double start_time;
    real_t duration;
    Vector3 velocity;
    Transform transform;
    VisualRIDPtr instance;
    volatile bool ready, dead;
    MeshEffect(int dummy=0):
      mesh(), shader_material(), lifetime_aabb(), start_time(-9e9),
      duration(0.0f), velocity(0,0,0), transform(), instance(), ready(false), dead(false)
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
    Ref<Shader> spatial_rift_shader;

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
    void free_unused_effects();
    void set_shaders(Ref<Shader> spatial_rift_shader);
    void set_visual_region(AABB visible_area, Vector3 expansion_rate);
    void step_effects(real_t delta, RID scenario);

    // Interface for CombatEngine:
    void add_spatial_rift(real_t lifetime, Vector3 position, real_t radius);

  private:
    void extend_rift(Vector3 left, Vector3 right, Vector3 center,
                     real_t extent, real_t radius);

  };

}
#endif
