#ifndef VISUALEFFECTS_H
#define VISUALEFFECTS_H

#include <Shader.hpp>
#include <ArrayMesh.hpp>
#include <Ref.hpp>
#include <MeshInstance.hpp>
#include <AABB.hpp>
#include <Reference.hpp>
#include <VisualServer.hpp>

#include "CombatEngineUtils.h"

namespace godot {
  namespace CE {
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
      MeshEffect();
      MeshEffect(const MeshEffect &o);
      ~MeshEffect();
    };

    class VisualEffects: public Reference {
      GODOT_CLASS(VisualEffects, Reference)

      RID scenario;
      real_t delta;
      double now;
      object_id last_id;
      std::unordered_map<object_id,MeshEffect> mesh_effects;
      std::vector<Vector3> vertex_holder;
      Ref<Shader> spatial_rift_shader;

      typedef std::unordered_map<object_id,MeshEffect>::iterator mesh_effects_iter;
      typedef std::unordered_map<object_id,MeshEffect>::const_iterator mesh_effects_citer;
    public:

      VisualEffects();
      ~VisualEffects();
      void _init();
      static void _register_methods();

      // Registered methods:
      void clear_all_effects();
      void free_unused_effects();
      void set_shaders(Ref<Shader> spatial_rift_shader);
      void step_effects(real_t delta, AABB visible_area, RID scenario);

      // Interface for CombatEngine:
      void add_spatial_rift(real_t lifetime, Vector3 position, real_t radius);

    private:
      void extend_rift(Vector3 left, Vector3 right, Vector3 center,
                       real_t extent, real_t radius);

    };

  }
}
#endif
