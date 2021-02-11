#include "VisualEffects.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

MeshEffect::~MeshEffect() {
  if(instance.get_id())
    VisualServer::get_singleton()->free_rid(instance);
}

VisualEffects::VisualEffects():
  erasure_mutex(), scenario(), delta(1.0/60), now(0.0), last_id(0),
  mesh_effects(), vertex_holder(), spatial_rift_shader()
{
  vertex_holder.reserve(2000);
  mesh_effects.reserve(200);
}

VisualEffects::~VisualEffects() {}

VisualEffects::_init() {}

void VisualEffects::_register_methods() {
  register_method("free_effects", &VisualEffects::free_effects);
  register_method("set_shaders", &VisualEffects::set_shaders);
  register_method("step_effects", &VisualEffects::step_effects);
}

void VisualEffects::free_effects() {
  lock_guard<mutex> lock(erasure_mutex);
  for(mesh_effects_iter it=mesh_effects.begin();it!=mesh_effects.end();)
    it = it->dead ? mesh_effects.erase(it) : ++it;
}

void VisualEffects::step_effects(real_t delta, AABB visible_area, RID scenario) {
  lock_guard<mutex> lock(erasure_mutex);
  this->delta=delta;
  this->scenario=scenario;
  now+=delta;
  for(mesh_effects_iter it=mesh_effects.begin();it!=mesh_effects.end();it++) {
    if(not it->ready or it->dead)
      continue;
    
    if((now-it->start_time)>it->duration
       or not visible_area.intersects(it->lifetime_aabb))
      it->dead=true;
    if(not it->dead and it->velocity and it->instance->get_id()) {
      it->transform.origin += delta*it->velocity;
      visual_server->instance_set_transform(*(it->instance),it->transform);
    }
  }
  // FIXME: move this to another thread:
  free_effects();
}

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

// Spatial Rift

void VisualEffects::extend_rift(Vector3 left, Vector3 right, Vector3 center,
                                real_t extent, real_t radius) {
  Vector3 tanget = right-left;
  real_t width = tangent.length();
  tanget = tangent.normalized();

  Vector3 normal = ((right+left)/2 - center).normalized();
  real_t length = rand.randf();
  length = (length/2 + 0.5)*extent*radius;
  
  real_t slide = rand.randf();
  slide = length * (slide-0.5) / 5;
  
  Vector3 next_left = left + normal*length + tangent*(width/4+slide);
  Vector3 next_right = right + normal*length + tangent*(-width/4+slide);
  const next_dist = sqrtf(3)/2;
  Vector3 next_back = (next_left+next_right)/2+normal*next_dist;
  Vector3 next_center = (next_left+next_right+next_center)/3;

  Vector3 down(-2*radius,-5*radius,2*radius);
  
  vertex_holder.append(left);
  vertex_holder.append(center);
  vertex_holder.append(next_left);
  vertex_holder.append(next_center);
  vertex_holder.append(left+down);
  vertex_holder.append(center+down);
  
  vertex_holder.append(next_left);
  vertex_holder.append(next_center);
  vertex_holder.append(next_left+down);
  vertex_holder.append(next_center+down);
  vertex_holder.append(left+down);
  vertex_holder.append(center+down);

  vertex_holder.append(next_right+down);
  vertex_holder.append(next_center+down);
  vertex_holder.append(next_right);
  vertex_holder.append(next_center);
  vertex_holder.append(right+down);
  vertex_holder.append(center+down);

  vertex_holder.append(next_right);
  vertex_holder.append(next_center);
  vertex_holder.append(right);
  vertex_holder.append(center);
  vertex_holder.append(right+down);
  vertex_holder.append(center+down);

  if(width>0.05 and 0.7>=rand.randf())
    extend_rift(next_left,next_back,next_center,extent/2,radius);
  else {
    vertex_holder.append(next_left);
    vertex_holder.append(next_center);
    vertex_holder.append(next_back);
    vertex_holder.append(next_center);
    vertex_holder.append(next_back+down);
    vertex_holder.append(next_center+down);

    vertex_holder.append(next_back);
    vertex_holder.append(next_center);
    vertex_holder.append(next_back+down);
    vertex_holder.append(next_center+down);
    vertex_holder.append(next_left+down);
    vertex_holder.append(next_center+down);
  }

  if(width>0.05 and 0.7>=rand.randf())
    extend_rift(next_right,next_back,next_center,extent/2,radius);
  else {
    vertex_holder.append(next_right+down);
    vertex_holder.append(next_center+down);
    vertex_holder.append(next_back);
    vertex_holder.append(next_center);
    vertex_holder.append(next_right);
    vertex_holder.append(next_center);

    vertex_holder.append(next_right+down);
    vertex_holder.append(next_center+down);
    vertex_holder.append(next_back+down);
    vertex_holder.append(next_center+down);
    vertex_holder.append(next_back);
    vertex_holder.append(next_center);
  }
}

void VisualEffects::add_spatial_rift(real_t lifetime, Vector3 position, real_t radius) {
  if(not spatial_rift_shader.is_valid())
    return;
  if(not (lifetime>0.0f))
    return;

  vertex_holder.clear();
  Vector3 tri[3];
  real_t angle = rand.rand_angle();
  for(int i=0;i<3;i++)
    tri[i] = unit_from_angle(angle+2*PI/3*i)*radius/5 + position;
  extend_rift(tri[0],tri[1],position,0.4f,radius);
  extend_rift(tri[1],tri[2],position,0.4f,radius);
  extend_rift(tri[2],tri[0],position,0.4f,radius);

  PoolVector3Array pool_vertices;
  PoolVector2Array pool_uv2;
  int nvert = vertex_holder.size()/2;
  {
    pool_vertices.resize(nvert);
    pool_uv2.resize(nvert);
    PoolVector3Array::Write write_vertices = pool_vertices.write();
    PoolVector2Array::Write write_uv2 = pool_uv2.write();
    Vector3 *vertices = write_vertices.ptr();
    Vector2 *uv2 = write_uv2.ptr();
    
    for(int i=0;i<nvert;i++) {
      vertices[i] = vertex_holder[i*2];
      uv2[i] = Vector2(vertex_holder[i*2+1].x-vertex_holder[i*2+0].x,
                       vertex_holder[i*2+1].z-vertex_holder[i*2+0].z);
    }
  }

  Array data;
  data.resize(ArrayMesh::ARRAY_MAX);
  data[ArrayMesh::ARRAY_VERTEX] = pool_vertices;
  data[ArrayMesh::ARRAY_TEX_UV2] = pool_uv2;
  Ref<ArrayMesh> mesh = ArrayMesh::_new();
  mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,data,Array(),ArrayMesh::ARRAY_COMPRESS_VERTEX|ArrayMesh::ARRAY_COMPRESS_TEX_UV2);
  Ref<ShaderMaterial> material = ShaderMaterial::_new();
  material->set_shader(spatial_rift_shader);
  material->set_shader_param("time",0.0f);
  mesh->surface_set_material(0,material);

  mesh_effects_iter it = mesh_effects.insert(last_id++);
  it->mesh = mesh;
  it->shader_material = material;
  it->start_time = now;
  it->duration = duration;
  it->aabb = mesh->get_aabb();
  it->aabb.position += position;
  it->transform.basis = position;

  VisualServer *visual_server = VisualServer::get_singleton();
  RID rid = visual_server->instance_create2(mesh->get_rid(),scenario);
  if(rid.get_id()) {
    it->instance = allocate_visual_rid(rid);
    it->ready=true;
  } else
    it->dead=true;
}
