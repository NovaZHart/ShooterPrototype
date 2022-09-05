#ifndef SCRIPTUTILS_HPP
#define SCRIPTUTILS_HPP

#include <Godot.hpp>
#include <Reference.hpp>
#include <String.hpp>
#include <Array.hpp>
#include <ArrayMesh.hpp>
#include <Image.hpp>

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

    Ref<ArrayMesh> make_circle(real_t radius,int polycount,bool angle_radius) const;
    
    Ref<ArrayMesh> make_icosphere(float radius, int subs) const;
    Ref<ArrayMesh> make_cube_sphere_v2(float radius, int subs) const;
    Ref<Image> make_lookup_tiles_c192() const;
    Ref<Image> make_lookup_tiles_c96() const;
    Ref<Image> make_hash_cube8(uint32_t hash) const;
    Ref<Image> make_hash_cube16(uint32_t hash) const;
    Ref<Image> make_hash_square32(uint32_t hash) const;
    Ref<Image> generate_impact_craters(real_t max_size,real_t min_size,int requested_count,uint32_t seed) const;
    Ref<Image> generate_planet_ring_noise(uint32_t log2,uint32_t seed,real_t weight_power) const;
    Ref<ArrayMesh> make_annulus_mesh(real_t middle_radius, real_t thickness, int steps) const;
    bool update_base_stats_from_ships(Object *target, Array ships_array) const;
  };

  
  class HyperspaceFleetStats {
    real_t full_mass_sum; // fleet-wide total of empty_mass + cargo_mass
    real_t total_mass; // fleet-wide total of full ship mass + armor mass + fuel mass
    real_t hyperthrust_weighted; // hyperthrust sum weighted by forward_thrust
    real_t forward_thrust_sum;
    real_t reverse_thrust_sum;
    real_t turning_thrust_sum;
    real_t max_shields_sum;
    real_t max_armor_sum;
    real_t max_structure_sum;
    real_t armor_sum;
    real_t max_fuel_sum;
    real_t fuel_sum;
    real_t fuel_efficiency_weighted; // fuel-weighted sum of fuel efficiency
    real_t drag_weighted; // mass-weighted sum of drag
    real_t turn_drag_weighted; // mass-weighted sum of turn drag
    real_t armor_inverse_density_weighted; // armor-weighted sum of armor_inverse_density
    real_t fuel_inverse_density_weighted; // fuel-weighted sum of fuel_inverse_density
    real_t heat_capacity_weighted; // mass-weighted sum of heat capacity
    real_t cooling_sum;
    real_t forward_thrust_heat_weighted; // forward_thrust_heat sum weighted by forward_thrust
    real_t reverse_thrust_heat_weighted; // reverse_thrust_heat sum weighted by reverse_thrust
    real_t turning_thrust_heat_weighted; // turning_thrust_heat sum weighted by turning_thrust
    real_t forward_thrust_energy_weighted; // forward_thrust_energy sum weighted by forward_thrust
    real_t reverse_thrust_energy_weighted; // reverse_thrust_energy sum weighted by reverse_thrust
    real_t turning_thrust_energy_weighted; // turning_thrust_energy sum weighted by turning_thrust
    real_t battery_sum;
    real_t power_sum;
  public:
    HyperspaceFleetStats();
    ~HyperspaceFleetStats();
    void sum_ship(const Dictionary &ship);
    void apply_to_ship(Object &ship) const;
  };

}
#endif
