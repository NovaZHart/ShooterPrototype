#ifndef SCRIPTUTILS_HPP
#define SCRIPTUTILS_HPP

#include <Godot.hpp>
#include <Reference.hpp>
#include <String.hpp>
#include <Array.hpp>

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
  };

}
#endif
