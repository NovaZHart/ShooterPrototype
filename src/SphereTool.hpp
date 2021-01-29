#ifndef SPHERETOOL_H
#define SPHERETOOL_H

#include <Godot.hpp>
#include <MeshInstance.hpp>
#include <Image.hpp>
#include <Ref.hpp>

namespace godot {

class SphereTool: public MeshInstance {
    GODOT_CLASS(SphereTool, MeshInstance)

public:
    static void _register_methods();
    SphereTool();
    ~SphereTool();
    void _init();
    void make_icosphere(String name,Vector3 center, float radius, int subs);
    void make_cube_sphere_v2(String name,Vector3 center, float radius, int subs);
    Ref<Image> make_lookup_tiles_c224() const;
};

}
#endif
