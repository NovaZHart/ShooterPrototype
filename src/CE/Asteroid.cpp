#include <assert.h>

#include "CE/Asteroid.hpp"
#include "CE/Utils.hpp"
#include "hash_functions.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

AsteroidTemplate::AsteroidTemplate(const Dictionary &dict,object_id mesh_id):
  mesh(get<Ref<Mesh>>(dict,"mesh")),
  mesh_id(mesh_id),
  color_data(get<Color>(dict,"color_data")),
  salvage(get<String>(dict,"salvage")),
  max_structure(get<real_t>(dict,"max_structure",EFFECTIVELY_INFINITE_HITPOINTS))
{}

////////////////////////////////////////////////////////////////////////

AsteroidTemplate::AsteroidTemplate():
  mesh(), mesh_id(-1), color_data(0,0,0,0), 
  salvage(), max_structure(EFFECTIVELY_INFINITE_HITPOINTS)
{}

////////////////////////////////////////////////////////////////////////

AsteroidTemplate::~AsteroidTemplate()
{}

////////////////////////////////////////////////////////////////////////

double Asteroid::take_damage(double damage) {
  double overkill = damage-structure;
  if(overkill>=0) {
    structure = 0;
    return overkill;
  } else {
    structure = -overkill;
    return 0;
  }
}

////////////////////////////////////////////////////////////////////////

void Asteroid::set_template(shared_ptr<const AsteroidTemplate> temp) {
  this->templ = templ;
  structure = templ ? templ->get_max_structure() : EFFECTIVELY_INFINITE_HITPOINTS;
}

////////////////////////////////////////////////////////////////////////

void Asteroid::update_state(AsteroidState &state,real_t when,real_t orbit_period,real_t inner_radius,real_t max_rotation_speed,real_t min_scale,real_t scale_range,bool initialize) const {
  FAST_PROFILING_FUNCTION;
  static const std::hash<String> salvage_hash;
  static const std::hash<real_t> time_hash;
  if(state.get_valid_time()==when)
    return;
  
  if(!state.is_valid()) {
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
    hash ^= static_cast<uint32_t>(fmodf(get_max_structure()*1024,1048576.0f));
    hash = CheapRand32::hash(hash);
    if(templ) {
      size_t sh = salvage_hash(templ->get_cargo());
      hash ^= sh;
      hash = CheapRand32::hash(hash);
      hash ^= sh>>32;
    }
    hash = CheapRand32::hash(hash);
    hash ^= time_hash(when);
    //hash = CheapRand32::hash(hash);  // constructor will hash one more time for us

    // Use the hash to generate some random numbers.
    state.set_random_numbers(CheapRand32(hash).rand_color());
  }

  real_t theta_now = theta-when*TAUf/orbit_period;
  real_t r_now = inner_radius + r;

  state.x = r_now*cosf(theta_now);
  state.z = -r_now*sinf(theta_now);
  state.rotation_speed = state.random_numbers.r*max_rotation_speed;
  state.scale = state.random_numbers.b*scale_range + min_scale;
  state.set_valid_time(when);
}

////////////////////////////////////////////////////////////////////////

Transform Asteroid::calculate_transform(const AsteroidState &state) const {
  FAST_PROFILING_FUNCTION;
  real_t rotation_speed = state.get_rotation_speed();
  real_t rotation_phase = calculate_rotation_phase(state);
  real_t rotation_angle = rotation_phase + rotation_speed*state.get_valid_time();
  
  real_t scale_xyz = state.get_scale();
  
  Vector3 rotation_axis(state.random_numbers.r,state.random_numbers.g,state.random_numbers.a);
  rotation_axis.normalize();
  
  Transform trans;
  
  trans.basis.rotate(rotation_axis,rotation_angle);
  trans.basis.scale(Vector3(scale_xyz,scale_xyz,scale_xyz));
  trans.origin=get_xyz(state);

  return trans;
}

////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////////////////

AsteroidPalette::AsteroidPalette(const AsteroidPalette &a,bool deep_copy):
  asteroids(a.asteroids),
  accumulated_weights(a.accumulated_weights)
{
  FAST_PROFILING_FUNCTION;
  if(deep_copy && asteroids.size())
    for(auto & ptr : asteroids)
      ptr = make_shared<AsteroidTemplate>(*ptr);
}

////////////////////////////////////////////////////////////////////////

AsteroidPalette::AsteroidPalette():
  asteroids(), accumulated_weights()
{}

////////////////////////////////////////////////////////////////////////

shared_ptr<const AsteroidTemplate> AsteroidPalette::default_asteroid;

////////////////////////////////////////////////////////////////////////

shared_ptr<const AsteroidTemplate> AsteroidPalette::random_choice(CheapRand32 &rand) const {
  if(!empty()) {
    real_t random_weight = rand.randf()*accumulated_weights.back();
    vector<real_t>::const_iterator there = upper_bound(accumulated_weights.begin(),accumulated_weights.end(),random_weight);
    return asteroids[there-accumulated_weights.begin()];
  } else
    return get_default_asteroid();
}