#ifndef PRELOADRESOURCES_HPP
#define PRELOADRESOURCES_HPP

#include <map>
#include <set>

#include <Godot.hpp>

#include <String.hpp>
#include <Array.hpp>
#include <Ref.hpp>
#include <Resource.hpp>
#include <Mesh.hpp>
#include <Ref.hpp>

#include "hash_functions.hpp"

namespace godot {
  class PreloadResources: public Reference {
    GODOT_CLASS(PreloadResources, Reference)

    std::set<String> requests;
    std::map<String,Ref<Resource>> loaded;
  public:

    PreloadResources();
    ~PreloadResources();
    static void _register_methods();
    void _init();
    int load_resources();
    void add_resources(Array these);
  private:
    Ref<Resource> load_resource(String path);
  };
};

#endif
