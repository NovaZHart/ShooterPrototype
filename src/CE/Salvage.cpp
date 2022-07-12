#include "CE/Salvage.hpp"
#include "CE/Utils.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

Salvage::Salvage(const Salvage &o,int cargo_count):
  flotsam_mesh(o.flotsam_mesh),
  flotsam_scale(o.flotsam_scale),
  cargo_name(o.cargo_name),
  cargo_count(cargo_count),
  cargo_unit_mass(o.cargo_unit_mass),
  cargo_unit_value(o.cargo_unit_value),
  armor_repair(o.armor_repair),
  structure_repair(o.structure_repair),
  fuel(o.fuel),
  spawn_duration(o.spawn_duration),
  grab_radius(o.grab_radius)
{}

Salvage::Salvage(Dictionary dict):
flotsam_mesh(get<Ref<Mesh>>(dict,"flotsam_mesh")),
flotsam_scale(get<float>(dict,"flotsam_scale",1.0f)),
cargo_name(get<String>(dict,"cargo_name")),
cargo_count(get<int>(dict,"cargo_count",1)),
cargo_unit_mass(get<real_t>(dict,"cargo_unit_mass",1.0f)),
cargo_unit_value(get<real_t>(dict,"cargo_unit_value",1.0f)),
armor_repair(get<real_t>(dict,"armor_repair",0.0f)),
structure_repair(get<real_t>(dict,"structure_repair",0.0f)),
fuel(get<real_t>(dict,"fuel",0.0f)),
spawn_duration(get<real_t>(dict,"spawn_duration",60.0f)),
grab_radius(get<real_t>(dict,"grab_radius",0.25f))
{
  if(cargo_count and cargo_unit_value<=0)
    Godot::print_warning("Salvageable \""+str(cargo_name)+"\" in flotsam has no value.",
                   __FUNCTION__,__FILE__,__LINE__);
}
Salvage::~Salvage() {}

////////////////////////////////////////////////////////////////////////

SalvagePalette::SalvagePalette(Dictionary from) {
  Array keys = from.keys();
  for(int i=0,s=keys.size();i<s;i++) {
    String key = keys[i];
    if(!key.empty()) {
      Dictionary value = from[key];
      if(!value.empty())
        salvage.emplace(key,make_shared<const Salvage>(value));
    }
  }
}

SalvagePalette::SalvagePalette():
  salvage()
{}

SalvagePalette::~SalvagePalette() {}

shared_ptr<Salvage> SalvagePalette::instance_salvage(const String &whut,CheapRand32 &rand) const {
  shared_ptr<const Salvage> original = get_salvage(whut);
  if(!original)
    return nullptr;

  real_t frac = min_product_fraction + product_fraction_range*rand.randf();
  int count = max(1.0f,original->cargo_count*frac);
  
  return make_shared<Salvage>(*original,count);
}
