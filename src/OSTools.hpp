#ifndef OSTOOLS_HPP
#define OSTOOLS_HPP

#include <Godot.hpp>

namespace godot {
  class OSTools: public Reference {
    GODOT_CLASS(OSTools, Reference)
  public:

    OSTools();
    ~OSTools();
    static void _register_methods();
    void _init();
    int make_process_high_priority();
  };
};

#endif
