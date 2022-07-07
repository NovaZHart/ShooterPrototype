#include "CE/Asteroid.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

static const real_t tau = 2*PIf;
static const real_t angle_to_int = (1<<30)/tau;
const real_t Asteroid::max_rotation_speed = tau/4;
const real_t Asteroid::min_scale = 0.4;
const real_t Asteroid::max_scale = 1.4;
const real_t Asteroid::scale_range = fabsf(Asteroid::max_scale-Asteroid::min_scale);

AsteroidState():
  x(0),y(0),hash(0),valid_time(invalid_time)
{}

void Asteroid::update_state(AsteroidState &state,real_t when,real_t orbit_period,real_t inner_radius,real_t thickness,bool initialize) {
  if(state.valid_time==when)
    return;
  
  if(!state.is_valid()) {
    // Get a decent hash.
    uint32_t hash = fmodf(theta,tau) * angle_to_int;
    hash = CheapRand32::hash(hash);
    hash ^= fmodf(r,1)*1<<30;
    hash = CheapRand32::hash(hash);
    hash ^= fmodf(y,1024)*1<<20;
    hash = CheapRand32::hash(hash);
    hash ^= fmodf(orbit_period*1024,1048576.0f)*1<<20;
    hash = CheapRand32::hash(hash);
    hash ^= fmodf(max_structure*1024,1048576.0f);
    hash = CheapRand32::hash(hash);
    hash ^= product_count;
    hash = CheapRand32::hash(hash);
    hash ^= product_id;
    hash = CheapRand32::hash(hash);
    state.hash = hash;

    random_numbers = Color(CheapRand32::int2float(CheapRand32::hash(hash+123)),
                           CheapRand32::int2float(CheapRand32::hash(hash+456)),
                           CheapRand32::int2float(CheapRand32::hash(hash+789)),
                           CheapRand32::int2float(CheapRand32::hash(hash+90909)));
  }

  real_t theta_now = when*tau/orbit_period+theta;
  real_t r_now = inner_radius + r*thickness;

  state.x = r_now*cosf(theta_now);
  state.z = -r_now*sinf(theta_now);

  state.valid_time = when;
}

Transform Asteroid::calculate_transform(const AsteroidState &state) {
  real_t rotation_speed = state.random_numbers.r * max_rotation_speed;
  real_t rotation_phase = state.random_numbers.g * tau;
  real_t rotation_angle = rotation_phase + rotation_speed*state.valid_time;
  
  real_t scale_xyz = state.random_numbers.b*scale_range + min_scale;
  
  Vector3 rotation_axis(state.random_numbers.r,state.random_numbers.g,state.random_numbers.a);
  rotation_axis.normalize();
  
  Transform trans;
  
  trans.rotate(rotation_axis,rotation_angle);
  trans.scale(Vector3(scale_xyz,scale_xyz,scale_xyz));
  trans.translate(get_xyz());

  return trans;
}

Asteroid::Asteroid(Dictionary data,int mesh_index):
  mesh_index(mesh_index),
  product_count(max(static_cast<uint32_t>(0),get<uint32_t>(data,"product_count",0))),
  product_id(get<int32_t>(data,"product_id",0)),
  max_structure(get<double>(data,"max_structure",effectively_infinite_hitpoints)),
  theta(0),r(0),y(0),
  structure(max_structure)
{}

Asteroid::Asteroid(real_t theta,real_t r,real_t y,const Asteroid &reference):
  mesh_index(reference.mesh_index),
  product_count(reference.product_count), product_id(reference.product_id),
  max_structure(reference.max_structure),
  theta(theta),r(r),y(y),
  structure(max_structure)
{}  

Asteroid::Asteroid():
  max_structure(effectively_infinite_hitpoints),
  theta(theta), r(r), y(0),
  structure(max_structure)
{}

////////////////////////////////////////////////////////////////////////

AsteroidPalette::AsteroidPalette(Array selection) {
  int size=selection.size();
  asteroids.reserve(size);
  weights.reserve(size);
  int count=0;
  real_t weight_accum=0;
  for(int i=0;i<size;i++) {
    Array item=selection[i];
    if(item.size()!=2)
      continue;
    
    real_t weight = item[0];
    Dictionary asteroid_data = item[1];
    if(weight<=0 or !asteroid_data.size())
      continue;

    String mesh_path = asteroid_data["asteroid_mesh_path"];
    if(mesh_path.empty())
      continue;
    
    asteroids.emplace_back(asteroid_data,count);
    weight_accum += weight;
    accumulated_weights.push_back(weight_accum);
    meshes.push_back(mesh_path);
    count++;
  }
}

const Asteroid AsteroidPalette::default_asteroid = Asteroid();

const Asteroid &AsteroidPalette::random_choice(CheapRand32 &rand) const {
  if(!empty()) {
    real_t random_weight = rand.randf()*accumulated_weights.back();
    vector<real_t>::const_iterator there = upper_bound(accumulated_weights.start(),accumulated_weights.end(),random_weight);
    return asteroids[there-accumulated_weights.begin()];
  } else
    return default_asteroid;
}
