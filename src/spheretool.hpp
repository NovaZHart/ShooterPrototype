#ifndef SPHERETOOL_H
#define SPHERETOOL_H

#include <Godot.hpp>
#include <MeshInstance.hpp>

namespace godot {

class SphereTool: public MeshInstance {
    GODOT_CLASS(SphereTool, MeshInstance)

public:
    static void _register_methods();
    SphereTool();
    ~SphereTool();
    void _init();
    void _process(float delta);
    void make_icosphere(String name,Vector3 center, float radius, int subs);
    void make_cube_sphere(String name,Vector3 center, float radius, int subs);
};

}
#endif
