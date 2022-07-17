#include "SphereTool.hpp"

#include <array>
#include <cmath>
#include <cstdint>

#include <GodotGlobal.hpp>
#include <SurfaceTool.hpp>
#include <Mesh.hpp>
#include <ArrayMesh.hpp>
#include <Image.hpp>
#include <ImageTexture.hpp>
#include <vector>

#include "DVector3.hpp"
#include "FastProfilier.hpp"
#include "ScriptUtils.hpp"

using namespace godot;
using namespace std;

void SphereTool::_register_methods() {
  register_method("make_icosphere", &SphereTool::make_icosphere);
  register_method("make_cube_sphere_v2", &SphereTool::make_cube_sphere_v2);
}

SphereTool::SphereTool() {}
SphereTool::~SphereTool() {}

void SphereTool::_init() {}

void SphereTool::make_icosphere(String name,Vector3 center, float radius, int subs) {
  set_mesh(godot::make_icosphere(subs));
  set_name(name);
  translate(center);
  scale_object_local(Vector3(radius,radius,radius));
}

void SphereTool::make_cube_sphere_v2(String name,Vector3 center, float radius, int subs) {
  set_mesh(godot::make_cube_sphere_v2(radius,subs));
  set_name(name);
  translate(center);
}
