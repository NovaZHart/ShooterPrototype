#include "ScriptUtils.hpp"

#include "CE/Utils.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;


void ScriptUtils::_register_methods() {
  register_method("_init", &ScriptUtils::_init);
  register_method("noop", &ScriptUtils::noop);
  register_method("string_join", &ScriptUtils::string_join);
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
