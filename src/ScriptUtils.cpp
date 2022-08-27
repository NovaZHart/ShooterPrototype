#include <SurfaceTool.hpp>

#include "ScriptUtils.hpp"
#include "SphereTool.hpp"
#include "CE/Utils.hpp"

namespace godot {

using namespace godot::CE;
using namespace std;


void ScriptUtils::_register_methods() {
  register_method("_init", &ScriptUtils::_init);
  register_method("noop", &ScriptUtils::noop);
  register_method("string_join", &ScriptUtils::string_join);
  register_method("make_icosphere", &ScriptUtils::make_icosphere);
  register_method("make_cube_sphere_v2", &ScriptUtils::make_cube_sphere_v2);
  register_method("make_lookup_tiles_c96", &ScriptUtils::make_lookup_tiles_c96);
  register_method("make_lookup_tiles_c192", &ScriptUtils::make_lookup_tiles_c192);
  register_method("make_hash_cube16", &ScriptUtils::make_hash_cube16);
  register_method("make_hash_cube8", &ScriptUtils::make_hash_cube8);
  register_method("make_hash_square32", &ScriptUtils::make_hash_square32);
  register_method("generate_impact_craters", &ScriptUtils::generate_impact_craters);
  register_method("generate_planet_ring_noise", &ScriptUtils::generate_planet_ring_noise);
  register_method("make_annulus_mesh", &ScriptUtils::make_annulus_mesh);
}

void ScriptUtils::_init() {}
ScriptUtils::ScriptUtils() {}
ScriptUtils::~ScriptUtils() {}
void ScriptUtils::noop() const {}

static inline void append(wchar_t *buf,int &used,const wchar_t *w) {
  for(;*w;w++)
    buf[used++]=*w;
}

static inline void append(wchar_t *buf,int &used,const String &s) {
  const wchar_t *w=s.unicode_str();
  append(buf,used,w);
}

String ScriptUtils::string_join(Array a,String sep) const {
  const wchar_t *wsep = sep.unicode_str();
   
  int seplen=sep.length();
  int asize = a.size();

  int bufsize=seplen*(asize-1)+1;
  for(int i=0;i<asize;i++)
    bufsize+=static_cast<String>(a[i]).length();

  wchar_t *buf = new wchar_t[bufsize];
  int used=0;
  
  for(int i=0;i<asize-1;i++) {
    append(buf,used,static_cast<String>(a[i]));
    append(buf,used,wsep);
  }

  append(buf,used,static_cast<String>(a[asize-1]));
  buf[used]=0;

  String result(buf);
  delete[] buf;
  return result;
}


typedef vector<Vector3> vectorVector3;
typedef vector<vectorVector3> vectorVectorVector3;

Ref<ArrayMesh> ScriptUtils::make_icosphere(float radius, int subs) const {
  return godot::make_icosphere(subs);
}
Ref<ArrayMesh> ScriptUtils::make_cube_sphere_v2(float radius, int subs) const {
  return godot::make_cube_sphere_v2(radius,subs);
}
Ref<Image> ScriptUtils::make_lookup_tiles_c192() const {
  return godot::make_lookup_tiles_c192();
}
Ref<Image> ScriptUtils::make_lookup_tiles_c96() const {
  return godot::make_lookup_tiles_c96();
}
Ref<Image> ScriptUtils::make_hash_cube16(uint32_t hash) const {
  return godot::make_hash_cube16(hash);
}
Ref<Image> ScriptUtils::make_hash_cube8(uint32_t hash) const {
  return godot::make_hash_cube8(hash);
}
Ref<Image> ScriptUtils::make_hash_square32(uint32_t hash) const {
  return godot::make_hash_square32(hash);
}
Ref<Image> ScriptUtils::generate_impact_craters(real_t max_size,real_t min_size,int requested_count,uint32_t seed) const {
  return godot::generate_impact_craters(max_size,min_size,requested_count,seed);
}
Ref<Image> ScriptUtils::generate_planet_ring_noise(uint32_t log2,uint32_t seed,real_t weight_power) const {
  return godot::generate_planet_ring_noise(log2,seed,weight_power);
}

Ref<ArrayMesh> ScriptUtils::make_annulus_mesh(real_t middle_radius, real_t thickness, int steps) const {
  return godot::make_annulus_mesh(middle_radius,thickness,steps);
}
}
