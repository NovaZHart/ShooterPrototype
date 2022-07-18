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
  register_method("make_lookup_tiles_c112", &ScriptUtils::make_lookup_tiles_c112);
  register_method("make_lookup_tiles_c224", &ScriptUtils::make_lookup_tiles_c224);
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
Ref<Image> ScriptUtils::make_lookup_tiles_c224() const {
  return godot::make_lookup_tiles_c224();
}
Ref<Image> ScriptUtils::make_lookup_tiles_c112() const {
  return godot::make_lookup_tiles_c112();
}
}
