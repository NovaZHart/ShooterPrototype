#include <SurfaceTool.hpp>
#include <ArrayMesh.hpp>

#include "ScriptUtils.hpp"
#include "SphereTool.hpp"
#include "CE/Utils.hpp"
#include "CE/VisualEffects.hpp"

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
  register_method("make_circle", &ScriptUtils::make_circle);
  //ScriptUtils::update_base_stats_from_ships
  register_method("update_base_stats_from_ships", &ScriptUtils::update_base_stats_from_ships);
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

Ref<ArrayMesh> ScriptUtils::make_circle(real_t radius,int polycount,bool angle_radius) const {
  Ref<ArrayMesh> am = ArrayMesh::_new();
  Array data = godot::CE::make_circle(radius,polycount,angle_radius);
  am->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,data,Array(),
    ArrayMesh::ARRAY_VERTEX|ArrayMesh::ARRAY_TEX_UV|ArrayMesh::ARRAY_TEX_UV2);
  return am;
}

HyperspaceFleetStats::HyperspaceFleetStats() {
  memset(this,0,sizeof(HyperspaceFleetStats));
}
HyperspaceFleetStats::~HyperspaceFleetStats() {}

static inline void accum_or_set(real_t &to,real_t weight,real_t value) {
  if(weight)
    to+=value*weight;
  else if(!to)
    to=value;
}
  
void HyperspaceFleetStats::sum_ship(const Dictionary &ship) {
  real_t ship_full_mass = get<real_t>(ship,"empty_mass",100.0f) + get<real_t>(ship,"cargo_mass");
  real_t ship_fuel_invd = get<real_t>(ship,"fuel_inverse_density",10.0f);
  real_t ship_fuel_efficiency = get<real_t>(ship,"fuel_efficiency",0.9f);
  real_t ship_armor_invd = get<real_t>(ship,"armor_inverse_density",200.0f);
  real_t ship_max_fuel = get<real_t>(ship,"max_fuel");
  real_t ship_fuel = get<real_t>(ship,"fuel",ship_max_fuel);
  real_t ship_max_armor = get<real_t>(ship,"max_armor");
  real_t ship_armor = get<real_t>(ship,"armor",ship_max_armor);
  real_t ship_total_mass = ship_full_mass + ship_armor*ship_armor_invd + ship_fuel*ship_fuel_invd;
  real_t ship_forward_thrust = get<real_t>(ship,"thrust");
  real_t ship_reverse_thrust = get<real_t>(ship,"reverse_thrust");
  real_t ship_turning_thrust = get<real_t>(ship,"turning_thrust");

  if(!ship_armor_invd) {
    Godot::print_error("Zero armor_inverse_density in update_base_stats_from_ships",
                       __FUNCTION__,__FILE__,__LINE__);
  }
  
  full_mass_sum += ship_full_mass;
  total_mass += ship_total_mass;
  accum_or_set(hyperthrust_weighted,ship_forward_thrust,get<real_t>(ship,"hyperthrust"));
  forward_thrust_sum += ship_forward_thrust;
  reverse_thrust_sum += ship_reverse_thrust;
  turning_thrust_sum += ship_turning_thrust;
  max_shields_sum += get<real_t>(ship,"max_shields");
  max_armor_sum += ship_max_armor;
  max_structure_sum += get<real_t>(ship,"max_structure");
  armor_sum += ship_armor;
  max_fuel_sum += ship_max_fuel;
  fuel_sum += ship_fuel;
  accum_or_set(fuel_efficiency_weighted,ship_fuel,ship_fuel_efficiency);
  drag_weighted += get<real_t>(ship,"drag",0.5)*ship_total_mass;
  turn_drag_weighted += get<real_t>(ship,"turn_drag",0.5)*ship_total_mass;
  accum_or_set(armor_inverse_density_weighted,ship_armor,ship_armor_invd);
  accum_or_set(fuel_inverse_density_weighted,ship_fuel,ship_fuel_invd);
  accum_or_set(heat_capacity_weighted,ship_total_mass,get<real_t>(ship,"heat_capacity"));
  cooling_sum += get<real_t>(ship,"cooling");
  accum_or_set(forward_thrust_heat_weighted,ship_forward_thrust,get<real_t>(ship,"forward_thrust_heat"));
  accum_or_set(reverse_thrust_heat_weighted,ship_reverse_thrust,get<real_t>(ship,"reverse_thrust_heat"));
  accum_or_set(turning_thrust_heat_weighted,ship_turning_thrust,get<real_t>(ship,"turning_thrust_heat"));
  accum_or_set(forward_thrust_energy_weighted,ship_forward_thrust,get<real_t>(ship,"forward_thrust_energy"));
  accum_or_set(reverse_thrust_energy_weighted,ship_reverse_thrust,get<real_t>(ship,"reverse_thrust_energy"));
  accum_or_set(turning_thrust_energy_weighted,ship_turning_thrust,get<real_t>(ship,"turning_thrust_energy"));
  battery_sum += get<real_t>(ship,"battery");
  power_sum += get<real_t>(ship,"power");

  if(!armor_inverse_density_weighted) {
    Godot::print_error("Zero armor_inverse_density_weighted in update_base_stats_from_ships",
                       __FUNCTION__,__FILE__,__LINE__);
  }
  
}

static inline real_t div_weight(real_t value_sum,real_t weight_sum) {
  if(weight_sum)
    return value_sum/weight_sum;
  else
    return value_sum;
}
  
void HyperspaceFleetStats::apply_to_ship(Object &ship) const {
  ship.set("base_mass",full_mass_sum);
  if(not (full_mass_sum>0))
    Godot::print_error("Total empty_mass+cargo_mass of fleet is zero in update_base_stats_from_ships.",
                       __FUNCTION__,__FILE__,__LINE__);
  ship.set("base_hyperthrust",div_weight(hyperthrust_weighted,forward_thrust_sum));
  if(not (forward_thrust_sum>0))
    Godot::print_error("No thrust found in any ships sent to update_base_stats_from_ships.",
                       __FUNCTION__,__FILE__,__LINE__);
  ship.set("base_thrust",forward_thrust_sum);
  ship.set("base_reverse_thrust",reverse_thrust_sum);
  ship.set("base_turning_thrust",turning_thrust_sum);
  ship.set("base_shields",max_shields_sum);
  ship.set("base_armor",max_armor_sum);
  ship.set("initial_armor",armor_sum);
  ship.set("base_structure",max_structure_sum);
  ship.set("base_fuel",max_fuel_sum);
  if(not (max_fuel_sum>0))
    Godot::print_error("No max_fuel found in any ships sent to update_base_stats_from_ships.",
                       __FUNCTION__,__FILE__,__LINE__);
  ship.set("initial_fuel",fuel_sum);
  if(not (fuel_sum>0))
    Godot::print_error("No fuel found in any ships sent to update_base_stats_from_ships.",
                       __FUNCTION__,__FILE__,__LINE__);
  ship.set("fuel_efficiency",div_weight(fuel_efficiency_weighted,fuel_sum));
  ship.set("base_drag",div_weight(drag_weighted,total_mass));
  ship.set("base_turn_drag",div_weight(turn_drag_weighted,total_mass));
  ship.set("armor_inverse_density",div_weight(armor_inverse_density_weighted,armor_sum));
  ship.set("fuel_inverse_density",div_weight(fuel_inverse_density_weighted,fuel_sum));
  ship.set("base_heat_capacity",div_weight(heat_capacity_weighted,total_mass));
  ship.set("base_cooling",cooling_sum);
  ship.set("base_forward_thrust_heat",div_weight(forward_thrust_heat_weighted,forward_thrust_sum));
  ship.set("base_reverse_thrust_heat",div_weight(reverse_thrust_heat_weighted,reverse_thrust_sum));
  ship.set("base_turning_thrust_heat",div_weight(turning_thrust_heat_weighted,turning_thrust_sum));
  ship.set("base_forward_thrust_energy",div_weight(forward_thrust_energy_weighted,forward_thrust_sum));
  ship.set("base_reverse_thrust_energy",div_weight(reverse_thrust_energy_weighted,reverse_thrust_sum));
  ship.set("base_turning_thrust_energy",div_weight(turning_thrust_energy_weighted,turning_thrust_sum));
  ship.set("base_battery",battery_sum);
  ship.set("base_power",power_sum);
}
  
bool ScriptUtils::update_base_stats_from_ships(Object *target, Array ships_array) const {
  if(!target) {
    Godot::print_error("Null target sent to update_base_stats_from_ship.",__FUNCTION__,__FILE__,__LINE__);
    return false;
  }
  int ship_count = ships_array.size();
  if(!ship_count) {
    Godot::print_error("Empty ships_array sent to update_base_stats_from_ship.",__FUNCTION__,__FILE__,__LINE__);
    return false;
  }
  
  HyperspaceFleetStats stats;
  for(int i=0;i<ship_count;i++)
    stats.sum_ship(ships_array[i]);
  stats.apply_to_ship(*target);

  return true;
}
  
} // End namespace.
