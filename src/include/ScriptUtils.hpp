#ifndef SCRIPTUTILS_HPP
#define SCRIPTUTILS_HPP

#include <Godot.hpp>
#include <Reference.hpp>
#include <String.hpp>
#include <Array.hpp>
#include <ArrayMesh.hpp>
#include <Image.hpp>

namespace godot {

  Ref<ArrayMesh> make_icosphere(int subs);
  Ref<ArrayMesh> make_cube_sphere_v2(float radius, int subs);
  Ref<Image> make_lookup_tiles_c224();
  Ref<Image> make_lookup_tiles_c112();

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

    Ref<ArrayMesh> make_icosphere(float radius, int subs) const;
    Ref<ArrayMesh> make_cube_sphere_v2(float radius, int subs) const;
    Ref<Image> make_lookup_tiles_c224() const;
    Ref<Image> make_lookup_tiles_c112() const;
  };

}
#endif
