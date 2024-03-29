#ifndef SCRIPTUTILS_HPP
#define SCRIPTUTILS_HPP

#include <Godot.hpp>
#include <Reference.hpp>
#include <String.hpp>
#include <Array.hpp>
#include <ArrayMesh.hpp>
#include <Image.hpp>

namespace godot {

  class ScriptUtils: public Reference {
    GODOT_CLASS(ScriptUtils,Reference)

  public:
    void _init();
    ScriptUtils();
    ~ScriptUtils();
    static void _register_methods();
                                   
    void noop() const;
    String string_join(Array a,String sep) const;
    String string_join_no_sep(Array a) const;

    Ref<ArrayMesh> make_circle(real_t radius,int polycount,bool angle_radius) const;
    
    Ref<ArrayMesh> make_icosphere(float radius, int subs) const;
    Ref<ArrayMesh> make_cube_sphere_v2(float radius, int subs) const;
    Ref<Image> make_lookup_tiles_c192() const;
    Ref<Image> make_lookup_tiles_c96() const;
    Ref<Image> make_hash_cube8(uint32_t hash) const;
    Ref<Image> make_hash_cube16(uint32_t hash) const;
    Ref<Image> make_hash_square32(uint32_t hash) const;
    Ref<Image> generate_impact_craters(real_t max_size,real_t min_size,int requested_count,uint32_t seed) const;
    Ref<Image> generate_planet_ring_noise(uint32_t log2,uint32_t seed,real_t weight_power) const;
    Ref<ArrayMesh> make_annulus_mesh(real_t middle_radius, real_t thickness, int steps) const;
  };

}
#endif
