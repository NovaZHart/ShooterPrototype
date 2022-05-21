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
#include "hash_functions.hpp"

namespace godot {
  class VisualEffects;
  namespace CE {
    class Ship;
  }
  
  const int EFFECTS_LIGHT_LAYER_MASK = 2;

  enum mesheffect_behavior {
    STATIONARY=0,
    CONSTANT_VELOCITY=1,
    CENTER_ON_TARGET1=2,
    VELOCITY_RELATIVE_TO_TARGET=3
  };

  struct VisualEffect {
    object_id id;
    AABB lifetime_aabb;
    double start_time;
    real_t duration, time_shift, rotation;
    Vector3 velocity, relative_position, position;
    VisualRIDPtr instance;
    volatile bool ready, dead;
    mesheffect_behavior behavior;
    object_id target1;
    
    virtual void step_effect(VisualServer *visual_server,double when,bool update_transform,bool update_death) = 0;
    inline Transform calculate_transform() const {
      return Transform(Basis(Vector3(0,rotation,0)),position);
    }

    VisualEffect(object_id effect_id,double start_time,real_t duration,real_t time_shift,
                 const Vector3 &position,real_t rotation,const AABB &lifetime_aabb);
    VisualEffect();
    virtual ~VisualEffect();
  };
  
  struct MeshEffect: public VisualEffect {
    Ref<Mesh> mesh;
    Ref<ShaderMaterial> shader_material;

    void step_effect(VisualServer *visual_server,double when,bool update_transform,bool update_death) override;

    MeshEffect();
    virtual ~MeshEffect();
  };

  struct MultiMeshInstanceEffect: public VisualEffect {
    object_id mesh_id;
    Color data;
    Vector2 half_size;

    inline void set_time(real_t time) {
      data[0]=time;
    }
    inline real_t get_time() const {
      return data[0];
    }
    inline void set_death_time(real_t time) {
      data[1]=time;
    }
    inline real_t get_death_time() const {
      return data[1];
    }
    inline real_t set_duration(real_t time) {
      return data[2]=time;
    }
    inline real_t get_duration() const {
      return data[2];
    }

    void step_effect(VisualServer *visual_server,double when,bool update_transform,bool update_death) override;
    
    explicit MultiMeshInstanceEffect();
    MultiMeshInstanceEffect(object_id effect_id,object_id mesh_id,double start_time,
                            real_t duration,real_t time_shift,
                            const Vector3 &position,real_t rotation,const AABB &lifetime_aabb);
    virtual ~MultiMeshInstanceEffect();
  };
  
  class VisualEffects: public Reference {
    GODOT_CLASS(VisualEffects, Reference)

    MultiMeshManager multimeshes;
    AABB visible_area;
    Vector3 visibility_expansion_rate;
    RID scenario;
    real_t delta;
    double now;
    CE::CheapRand32 rand;
    ObjectIdGenerator idgen;
    std::unordered_map<object_id,MeshEffect> mesh_effects;
    std::unordered_map<object_id,MultiMeshInstanceEffect> mmi_effects;
    std::vector<Vector3> vertex_holder;
    std::vector<Vector2> uv2_holder, uv_holder;
    Ref<Shader> spatial_rift_shader, zap_ball_shader, hyperspacing_polygon_shader, fade_out_texture;
    Ref<Texture> hyperspacing_texture, cargo_puff_texture;
    VisibleContentManager content;
    VisibleContent *combat_content;
    
    bool reset_scenario;
    
    typedef std::unordered_map<object_id,MeshEffect>::iterator mesh_effects_iter;
    typedef std::unordered_map<object_id,MeshEffect>::const_iterator mesh_effects_citer;
    typedef std::unordered_map<object_id,MeshEffect>::value_type mesh_effects_value;
    
    typedef std::unordered_map<object_id,MultiMeshInstanceEffect>::iterator mmi_effects_iter;
    typedef std::unordered_map<object_id,MultiMeshInstanceEffect>::const_iterator mmi_effects_citer;
    typedef std::unordered_map<object_id,MultiMeshInstanceEffect>::value_type mmi_effects_value;
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
    void step_effects(real_t delta,Vector3 location,Vector3 size);

    // Interface for CombatEngine:
    inline void set_combat_content(VisibleContent *v) {
      combat_content=v;
    }
    void add_hyperspacing_polygon(real_t duration, Vector3 position, real_t radius, bool reverse, object_id ship_id);
    void set_visible_content(VisibleContent *visible);
    void add_cargo_web_puff_MeshEffect(const godot::CE::Ship &ship,Vector3 relative_position,Vector3 relative_velocity,real_t length,real_t duration,Ref<Texture> cargo_puff);
    void add_cargo_web_puff_MMIEffect(const godot::CE::Ship &ship,Vector3 relative_position,Vector3 relative_velocity,real_t length,real_t duration,Ref<Mesh> cargo_puff);
    void add_content();
    
    // Utilities:
    bool is_circle_visible(const Vector3 &position, real_t radius) const;
    
  private:
    void step_multimeshes(real_t delta,Vector3 location,Vector3 size);
    VisibleObject * get_object_or_make_stationary(object_id target,VisualEffect &effect);
    void step_effect(VisualEffect &effect,VisualServer *visual_server);
    void free_unused_effects();
    void extend_zap_pattern(Vector3 left, Vector3 right, Vector3 center,
                            real_t extent, real_t radius, int depth);

    MultiMeshInstanceEffect &add_MMIEffect(Ref<Mesh> mesh, real_t duration, Vector3 position,
                                           real_t rotation);
    
    MeshEffect &add_MeshEffect(Array data, real_t duration, Vector3 position,
                               real_t rotation, Ref<Shader> shader);
  };

}
#endif
