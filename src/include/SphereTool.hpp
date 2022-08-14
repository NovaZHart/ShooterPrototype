#ifndef SPHERETOOL_H
#define SPHERETOOL_H

#include <ArrayMesh.hpp>
#include <Godot.hpp>
#include <MeshInstance.hpp>
#include <Image.hpp>
#include <Ref.hpp>

namespace godot {

  Ref<ArrayMesh> make_icosphere(int subs);
  Ref<ArrayMesh> make_cube_sphere_v2(float radius, int subs);
  Ref<Image> make_lookup_tiles_c192();
  Ref<Image> make_lookup_tiles_c96();
  Ref<Image> make_hash_cube8(uint32_t hash);
  Ref<Image> make_hash_cube16(uint32_t hash);
  Ref<Image> make_hash_square32(uint32_t hash);
  Ref<Image> generate_impact_craters(real_t max_size,real_t min_size,int requested_count,uint32_t seed);
  
  class SphereTool: public MeshInstance {
    GODOT_CLASS(SphereTool, MeshInstance)
    
  public:
    static void _register_methods();
    SphereTool();
    ~SphereTool();
    void _init();
    void make_icosphere(String name,Vector3 center, float radius, int subs);
    void make_cube_sphere_v2(String name,Vector3 center, float radius, int subs);
};

}
#endif
