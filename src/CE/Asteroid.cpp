#include <assert.h>

#include "CE/Asteroid.hpp"
#include "CE/Utils.hpp"
#include "hash_functions.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

const DamageArray AsteroidTemplate::default_resistances {
  // Typeless, light, he particle:
  0.0f, 0.0f, 0.0f,
  // Piercing, impact:
  -0.2, -0.3,
  // EM field, gravity:
  0.0f, 0.0f,
  // Antimatter:
  -1.0f,
  // Explosive, psionic, plasma, charge:
  -0.1f, 0.0f, 0.0f, 0.0f,
  // Rift, temporal, bio, lifeforce:
  -0.3f, 0.0f, 0.5f, 0.75f,
  // Unreality
  0.0f
};
  
AsteroidTemplate::AsteroidTemplate(const Dictionary &dict,object_id mesh_id):
  mesh(get<Ref<Mesh>>(dict,"mesh")),
  mesh_id(mesh_id),
  color_data(get<Color>(dict,"color_data")),
  salvage(get<String>(dict,"salvage")),
  max_structure(get<real_t>(dict,"max_structure",EFFECTIVELY_INFINITE_HITPOINTS)),
  resistances(dict.has("resistances")
              ? DamageArray(dict["resistances"],MIN_ASTEROID_RESISTANCE,
                            MAX_ASTEROID_RESISTANCE)
              : default_resistances)
{}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

AsteroidTemplate::AsteroidTemplate():
  mesh(), mesh_id(-1), color_data(0,0,0,0), 
  salvage(), max_structure(EFFECTIVELY_INFINITE_HITPOINTS)
{}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

AsteroidTemplate::~AsteroidTemplate()
{}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

void Asteroid::get_object_info(CelestialInfo &info) const {
  info = { id, get_xyz(), get_scale() };
}
object_id Asteroid::get_object_id() const {
  return id;
}
real_t Asteroid::get_object_radius() const {
  return get_scale();
}
Vector3 Asteroid::get_object_xyz() const {
  return get_xyz();
}
Vector2 Asteroid::get_object_xz() const {
  return get_xz();
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

real_t Asteroid::take_damage(real_t damage,int type) {
  const DamageArray &resistances = get_resistances();
  apply_damage(damage,state.structure,type,resistances);
  return damage;
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

void Asteroid::set_template(shared_ptr<const AsteroidTemplate> temp) {
  this->templ = templ;
  invalidate_state();
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

void Asteroid::update_state(real_t when,real_t orbit_period,real_t inner_radius,real_t max_rotation_speed,real_t min_scale,real_t scale_range) const {
  FAST_PROFILING_FUNCTION;
  static const std::hash<String> salvage_hash;
  static const std::hash<real_t> time_hash;
  
  if(state.get_valid_time()==when)
    // State is valid and up to date, so there's nothing to do.
    return;

  // If flag initialize is true, the asteroid has not yet been
  // generated, or died and is being regenerated. That means we need
  // new random numbers, a new shape, new rotation, and new
  // max_structure.
  bool initialize = !state.is_valid();
  
  if(initialize) {
    // Get a decent hash.
    static const real_t angle_to_int = (1<<30)/TAUf;
    uint32_t hash = fmodf(theta,TAUf) * angle_to_int;
    hash = CheapRand32::hash(hash);
    hash ^= static_cast<uint32_t>(fmodf(r,1)*(1<<30));
    hash = CheapRand32::hash(hash);
    hash ^= static_cast<uint32_t>(fmodf(y,1024)*(1<<20));
    hash = CheapRand32::hash(hash);
    hash ^= static_cast<uint32_t>(fmodf(orbit_period*1024,1048576.0f)*(1<<20));
    hash = CheapRand32::hash(hash);
    if(templ) {
      size_t sh = salvage_hash(templ->get_cargo());
      hash ^= sh;
      hash = CheapRand32::hash(hash);
      hash ^= sh>>32;
    }
    hash = CheapRand32::hash(hash);
    hash ^= time_hash(when);

    // Use the hash to generate some random numbers.
    state.set_random_numbers(CheapRand32(hash).rand_color());
  }

  real_t theta_now = theta-when*TAUf/orbit_period;
  real_t r_now = inner_radius + r;

  state.x = r_now*cosf(theta_now);
  state.z = -r_now*sinf(theta_now);
  
  if(initialize) {
    state.rotation_speed = state.random_numbers.r*max_rotation_speed;
    state.scale = state.random_numbers.b*scale_range + min_scale;
    if(templ)
      state.max_structure = state.scale*state.scale*templ->get_max_structure();
    else
      state.max_structure = EFFECTIVELY_INFINITE_HITPOINTS;
    state.structure = state.max_structure;
  }

  state.set_valid_time(when);
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

Transform Asteroid::calculate_transform() const {
  FAST_PROFILING_FUNCTION;
  real_t rotation_speed = state.get_rotation_speed();
  real_t rotation_phase = calculate_rotation_phase();
  real_t rotation_angle = rotation_phase + rotation_speed*state.get_valid_time();
  
  real_t scale_xyz = state.get_scale();
  
  Vector3 rotation_axis(state.random_numbers.r,state.random_numbers.g,state.random_numbers.a);
  rotation_axis.normalize();
  
  Transform trans;
  
  trans.basis.rotate(rotation_axis,rotation_angle);
  trans.basis.scale(Vector3(scale_xyz,scale_xyz,scale_xyz));
  trans.origin=get_xyz();

  return trans;
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

AsteroidPalette::AsteroidPalette(Array selection) {
  FAST_PROFILING_FUNCTION;
  int size=selection.size();
  if(!size)
    Godot::print_error("Empty array sent to AsteroidPalette! Asteroids will be invisible.",
                       __FUNCTION__,__FILE__,__LINE__);
  asteroids.reserve(size);
  accumulated_weights.reserve(size);
  real_t weight_accum=0;
  for(int i=0;i<size;i++) {
    Variant vitem=selection[i];
    if(vitem.get_type()!=Variant::ARRAY) {
      Godot::print_error("Non-array sent as an asteroid palette item.",
                         __FUNCTION__,__FILE__,__LINE__);
      continue;
    }
    Array item = vitem;
    if(item.size()!=2) {
      Godot::print_warning("Asteroid palette list items must have 2 elements, not "+str(item.size()),
                           __FUNCTION__,__FILE__,__LINE__);
      continue;
    }
    
    real_t weight = item[0];
    Dictionary asteroid_data = item[1];
    if(weight<=0) {
      Godot::print_warning("Non-positive asteroid palette weight "+str(weight),
                           __FUNCTION__,__FILE__,__LINE__);
      continue;
    }
    if(!asteroid_data.size()) {
      Godot::print_warning("Empty asteroid information in an asteroid ",
                           __FUNCTION__,__FILE__,__LINE__);
      continue;
    }
    
    asteroids.emplace_back(make_shared<AsteroidTemplate>(asteroid_data));
    weight_accum += weight;
    accumulated_weights.push_back(weight_accum);
  }
  if(!size)
    Godot::print_error("No asteroids in palette! Asteroids will be invisible.",
                       __FUNCTION__,__FILE__,__LINE__);
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

AsteroidPalette::AsteroidPalette(const AsteroidPalette &a,bool deep_copy):
  asteroids(a.asteroids),
  accumulated_weights(a.accumulated_weights)
{
  FAST_PROFILING_FUNCTION;
  if(deep_copy && asteroids.size())
    for(auto & ptr : asteroids)
      ptr = make_shared<AsteroidTemplate>(*ptr);
}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

AsteroidPalette::AsteroidPalette():
  asteroids(), accumulated_weights()
{}

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

shared_ptr<const AsteroidTemplate> AsteroidPalette::default_asteroid;

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * */

shared_ptr<const AsteroidTemplate> AsteroidPalette::random_choice(CheapRand32 &rand) const {
  if(!empty()) {
    real_t random_weight = rand.randf()*accumulated_weights.back();
    vector<real_t>::const_iterator there = upper_bound(accumulated_weights.begin(),accumulated_weights.end(),random_weight);
    return asteroids[there-accumulated_weights.begin()];
  } else
    return get_default_asteroid();
}
