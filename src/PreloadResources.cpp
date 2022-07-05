#include "PreloadResources.hpp"

#include <ResourceLoader.hpp>
#include <GodotGlobal.hpp>
#include "FastProfilier.hpp"

using namespace std;
using namespace godot;

PreloadResources::PreloadResources():
  requests(), loaded()
{}

PreloadResources::~PreloadResources() {}

void PreloadResources::_register_methods() {
  register_method("add_resources",&PreloadResources::add_resources);
  register_method("load_resources",&PreloadResources::load_resources);
  register_method("free_all_resources",&PreloadResources::free_all_resources);
}

void PreloadResources::_init() {}

int PreloadResources::load_resources() {
  FAST_PROFILING_FUNCTION;
  ResourceLoader *loader = ResourceLoader::get_singleton();
  int count=0;
  for(auto &request : requests)
    if(loaded.find(request)==loaded.end()) {
      loaded.emplace(request,loader->load(request));
      count++;
    }
  return count;
}
        
void PreloadResources::add_resources(Array these) {
  FAST_PROFILING_FUNCTION;
  ResourceLoader *loader=ResourceLoader::get_singleton();
  for(int i=0,n=these.size();i<n;i++) {
    String path=these[i];
    if(not path.length())
      Godot::print_warning("Empty string sent to PreloadResources",__FUNCTION__,__FILE__,__LINE__);
    else if(not loader->exists(path))
      Godot::print_warning(path+": ResourceLoader says no resource exists at this path",__FUNCTION__,__FILE__,__LINE__);
    else
      requests.insert(these[i]);
  }
}

void PreloadResources::free_all_resources() {
  requests.clear();
  loaded.clear();
}
