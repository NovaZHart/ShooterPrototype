#include "CE/Asteroid.hpp"
#include "CE/Utils.hpp"
#include "hash_functions.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

const real_t Asteroid::max_rotation_speed = TAUf/4;
const real_t Asteroid::min_scale = 0.4;
const real_t Asteroid::max_scale = 1.4;
const real_t Asteroid::scale_range = fabsf(Asteroid::max_scale-Asteroid::min_scale);

AsteroidTemplate::AsteroidTemplate(const Dictionary &dict,object_id mesh_id):
  mesh(get<Ref<Mesh>>(dict,"mesh")),
  mesh_id(mesh_id),
  color_data(get<Color>(dict,"color_data")),
  salvage(get<String>(dict,"salvage")),
  max_structure(get<real_t>(dict,"max_structure",EFFECTIVELY_INFINITE_HITPOINTS))
{}

AsteroidTemplate::AsteroidTemplate():
  mesh(), mesh_id(-1), color_data(0,0,0,0), 
  salvage(), max_structure(EFFECTIVELY_INFINITE_HITPOINTS)
{}

AsteroidTemplate::~AsteroidTemplate() {

}

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

void Asteroid::set_template(shared_ptr<const AsteroidTemplate> temp) {
  this->templ = templ;
  structure = templ ? templ->get_max_structure() : EFFECTIVELY_INFINITE_HITPOINTS;
}

void Asteroid::update_state(AsteroidState &state,real_t when,real_t orbit_period,real_t inner_radius,real_t thickness,bool initialize) const {
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

  real_t theta_now = when*TAUf/orbit_period+theta;
  real_t r_now = inner_radius + r*thickness;

  state.x = r_now*cosf(theta_now);
  state.z = -r_now*sinf(theta_now);

  state.set_valid_time(when);
}

Transform Asteroid::calculate_transform(const AsteroidState &state) const {
  real_t rotation_speed = calculate_rotation_speed(state);
  real_t rotation_phase = calculate_rotation_phase(state);
  real_t rotation_angle = rotation_phase + rotation_speed*state.get_valid_time();
  
  real_t scale_xyz = calculate_scale(state);
  
  Vector3 rotation_axis(state.random_numbers.r,state.random_numbers.g,state.random_numbers.a);
  rotation_axis.normalize();
  
  Transform trans;
  
  trans.rotate(rotation_axis,rotation_angle);
  trans.scale(Vector3(scale_xyz,scale_xyz,scale_xyz));
  trans.translate(get_xyz(state));

  return trans;
}

////////////////////////////////////////////////////////////////////////

AsteroidPalette::AsteroidPalette(Array selection) {
  int size=selection.size();
  asteroids.reserve(size);
  accumulated_weights.reserve(size);
  real_t weight_accum=0;
  for(int i=0;i<size;i++) {
    Array item=selection[i];
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
}

AsteroidPalette::AsteroidPalette(const AsteroidPalette &a,bool deep_copy):
  asteroids(a.asteroids),
  accumulated_weights(a.accumulated_weights)
{
  if(deep_copy)
    for(auto & ptr : asteroids)
      ptr = make_shared<AsteroidTemplate>(*ptr);
}

shared_ptr<const AsteroidTemplate> AsteroidPalette::default_asteroid;

shared_ptr<const AsteroidTemplate> AsteroidPalette::random_choice(CheapRand32 &rand) const {
  if(!empty()) {
    real_t random_weight = rand.randf()*accumulated_weights.back();
    vector<real_t>::const_iterator there = upper_bound(accumulated_weights.begin(),accumulated_weights.end(),random_weight);
    return asteroids[there-accumulated_weights.begin()];
  } else
    return get_default_asteroid();
}
