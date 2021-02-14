#include <GodotGlobal.hpp>
#include "VisualEffects.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

VisualEffects::VisualEffects():
  visible_area(Vector3(-100.0f,-50.0f,-100.0f),Vector3(200.0f,100.0f,200.0f)),
  visibility_expansion_rate(Vector3(10.0f,0.0f,10.0f)),
  scenario(), delta(1.0/60), now(0.0), rand(), last_id(0),
  mesh_effects(), vertex_holder(), spatial_rift_shader()
{
  vertex_holder.reserve(2000);
  mesh_effects.reserve(200);
}

VisualEffects::~VisualEffects() {}

void VisualEffects::_init() {}

void VisualEffects::_register_methods() {
  register_method("clear_all_effects", &VisualEffects::clear_all_effects);
  register_method("set_visible_region", &VisualEffects::set_visible_region);
  register_method("set_shaders", &VisualEffects::set_shaders);
  register_method("step_effects", &VisualEffects::step_effects);
}

void VisualEffects::set_shaders(Ref<Shader> spatial_rift_shader) {
  this->spatial_rift_shader = spatial_rift_shader;
}

void VisualEffects::clear_all_effects() {
  mesh_effects.clear();
}

void VisualEffects::free_unused_effects() {
  for(mesh_effects_iter it=mesh_effects.begin();it!=mesh_effects.end();)
    it = it->second.dead ? mesh_effects.erase(it) : ++it;
}

void VisualEffects::set_visible_region(AABB visible_area,Vector3 visibility_expansion_rate) {
  this->visible_area = visible_area;
  this->visibility_expansion_rate = Vector3(fabsf(visibility_expansion_rate.x),0.0f,
                                            fabsf(visibility_expansion_rate.z));
}

void VisualEffects::step_effects(real_t delta, RID scenario) {
  VisualServer *visual_server = VisualServer::get_singleton();
  this->delta=delta;
  this->scenario=scenario;
  now+=delta;
  for(mesh_effects_iter it=mesh_effects.begin();it!=mesh_effects.end();it++) {
    MeshEffect &effect = it->second;
    if(not effect.ready or effect.dead)
      continue;
    
    if((now-effect.start_time)>effect.duration)
      effect.dead=true;
    else {
      AABB expanded(visible_area.position - visibility_expansion_rate*effect.duration,
                    visible_area.size + 2*visibility_expansion_rate*effect.duration);
      if(not expanded.intersects(effect.lifetime_aabb))
        effect.dead=true;
      else {
        if(effect.velocity.length_squared()>1e-10 and effect.instance->rid.get_id()) {
          effect.transform.origin += delta*effect.velocity;
          visual_server->instance_set_transform(effect.instance->rid,effect.transform);
        }
        if(effect.shader_material.is_valid())
          effect.shader_material->set_shader_param("time",float(now-effect.start_time));
      }
    }
  }
  // FIXME: move this to another thread:
  free_unused_effects();
}

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

// Spatial Rift

void VisualEffects::extend_rift(Vector3 left, Vector3 right, Vector3 center,
                                real_t extent, real_t radius, int depth) {
  Vector3 tangent = right-left;
  real_t width = tangent.length();
  tangent = tangent.normalized();

  Vector3 normal = ((right+left)/2 - center).normalized();
  real_t length = rand.randf();
  length = (length/2 + 0.5)*extent*radius;
  
  real_t slide = rand.randf();
  slide = length * (slide-0.5) / 5;
  
  Vector3 next_left = left + normal*length + tangent*(width/4+slide);
  Vector3 next_right = right + normal*length + tangent*(-width/4+slide);
  real_t next_dist = sqrtf(3)/2;
  Vector3 next_back = (next_left+next_right)/2+normal*next_dist;
  Vector3 next_center = (next_left+next_right+next_back)/3;

  Vector3 down(-2*radius,-5*radius,2*radius);

  Godot::print("Extend rift vectors: left="+str(left)+" next_left="+str(next_left)+" right="+str(right)+" next_right="+str(next_right)+" center="+str(center)+" next_center="+str(next_center)+" next_back="+str(next_back));
  
  vertex_holder.push_back(left);
  vertex_holder.push_back(center);
  vertex_holder.push_back(Vector3(0,0,0));
  vertex_holder.push_back(next_left);
  vertex_holder.push_back(next_center);
  vertex_holder.push_back(Vector3(1,0,0));
  vertex_holder.push_back(left+down);
  vertex_holder.push_back(center+down);
  vertex_holder.push_back(Vector3(0,1,0));
  
  vertex_holder.push_back(next_left);
  vertex_holder.push_back(next_center);
  vertex_holder.push_back(Vector3(1,0,0));
  vertex_holder.push_back(next_left+down);
  vertex_holder.push_back(next_center+down);
  vertex_holder.push_back(Vector3(1,1,0));
  vertex_holder.push_back(left+down);
  vertex_holder.push_back(center+down);
  vertex_holder.push_back(Vector3(0,1,0));

  vertex_holder.push_back(next_right+down);
  vertex_holder.push_back(next_center+down);
  vertex_holder.push_back(Vector3(1,1,0));
  vertex_holder.push_back(next_right);
  vertex_holder.push_back(next_center);
  vertex_holder.push_back(Vector3(1,0,0));
  vertex_holder.push_back(right+down);
  vertex_holder.push_back(center+down);
  vertex_holder.push_back(Vector3(0,1,0));

  vertex_holder.push_back(next_right);
  vertex_holder.push_back(next_center);
  vertex_holder.push_back(Vector3(1,0,0));
  vertex_holder.push_back(right);
  vertex_holder.push_back(center);
  vertex_holder.push_back(Vector3(0,0,0));
  vertex_holder.push_back(right+down);
  vertex_holder.push_back(center+down);
  vertex_holder.push_back(Vector3(0,1,0));

  if(depth<5 and width>0.05 and 0.7>=rand.randf())
    extend_rift(next_left,next_back,next_center,extent/2,radius,depth+1);
  else {
    vertex_holder.push_back(next_left);
    vertex_holder.push_back(next_center);
    vertex_holder.push_back(Vector3(0,0,0));
    vertex_holder.push_back(next_back);
    vertex_holder.push_back(next_center);
    vertex_holder.push_back(Vector3(1,0,0));
    vertex_holder.push_back(next_back+down);
    vertex_holder.push_back(next_center+down);
    vertex_holder.push_back(Vector3(1,1,0));

    vertex_holder.push_back(next_back);
    vertex_holder.push_back(next_center);
    vertex_holder.push_back(Vector3(1,0,0));
    vertex_holder.push_back(next_back+down);
    vertex_holder.push_back(next_center+down);
    vertex_holder.push_back(Vector3(1,1,0));
    vertex_holder.push_back(next_left+down);
    vertex_holder.push_back(next_center+down);
    vertex_holder.push_back(Vector3(0,1,0));
  }

  if(depth<5 and width>0.05 and 0.7>=rand.randf())
    extend_rift(next_right,next_back,next_center,extent/2,radius,depth+1);
  else {
    vertex_holder.push_back(next_right+down);
    vertex_holder.push_back(next_center+down);
    vertex_holder.push_back(Vector3(0,1,0));
    vertex_holder.push_back(next_back);
    vertex_holder.push_back(next_center);
    vertex_holder.push_back(Vector3(1,0,0));
    vertex_holder.push_back(next_right);
    vertex_holder.push_back(next_center);
    vertex_holder.push_back(Vector3(0,0,0));

    vertex_holder.push_back(next_right+down);
    vertex_holder.push_back(next_center+down);
    vertex_holder.push_back(Vector3(0,1,0));
    vertex_holder.push_back(next_back+down);
    vertex_holder.push_back(next_center+down);
    vertex_holder.push_back(Vector3(1,1,0));
    vertex_holder.push_back(next_back);
    vertex_holder.push_back(next_center);
    vertex_holder.push_back(Vector3(1,0,0));
  }
}

void VisualEffects::add_spatial_rift(real_t halflife, Vector3 position, real_t radius) {
  if(not spatial_rift_shader.is_valid()) {
    Godot::print("No shader. Skip rift.");
    return;
  }
  if(not (halflife>0.0f)) {
    Godot::print("No shader. Skip halflife.");
    return;
  }

  vertex_holder.clear();
  Vector3 tri[3];
  real_t angle = rand.rand_angle();
  for(int i=0;i<3;i++)
    tri[i] = unit_from_angle(angle+2*PI/3*i)*radius/5 + position;
  extend_rift(tri[0],tri[1],position,0.4f,radius,1);
  extend_rift(tri[1],tri[2],position,0.4f,radius,1);
  extend_rift(tri[2],tri[0],position,0.4f,radius,1);

  PoolVector3Array pool_vertices;
  PoolVector2Array pool_uv2, pool_uv;
  int nvert = vertex_holder.size()/3;
  {
    pool_vertices.resize(nvert);
    pool_uv2.resize(nvert);
    pool_uv.resize(nvert);
    PoolVector3Array::Write write_vertices = pool_vertices.write();
    PoolVector2Array::Write write_uv2 = pool_uv2.write();
    PoolVector2Array::Write write_uv = pool_uv.write();
    Vector3 *vertices = write_vertices.ptr();
    Vector2 *uv2 = write_uv2.ptr();
    Vector2 *uv = write_uv.ptr();
    
    for(int i=0;i<nvert;i++) {
      vertices[i] = vertex_holder[i*3];
      uv2[i] = Vector2(vertex_holder[i*3+1].x,vertex_holder[i*3+1].z);
      uv[i] = Vector2(vertex_holder[i*3+2].x,vertex_holder[i*3+2].y);
    }
  }

  Array data;
  data.resize(ArrayMesh::ARRAY_MAX);
  data[ArrayMesh::ARRAY_VERTEX] = pool_vertices;
  data[ArrayMesh::ARRAY_TEX_UV] = pool_uv;
  data[ArrayMesh::ARRAY_TEX_UV2] = pool_uv2;
  Ref<ArrayMesh> mesh = ArrayMesh::_new();
  Godot::print("Rift array mesh data: "+String(Variant(data)));
  mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,data,Array(),ArrayMesh::ARRAY_COMPRESS_VERTEX|ArrayMesh::ARRAY_COMPRESS_TEX_UV2|ArrayMesh::ARRAY_COMPRESS_TEX_UV);
  Ref<ShaderMaterial> material = ShaderMaterial::_new();
  material->set_shader(spatial_rift_shader);
  material->set_shader_param("time",0.0f);
  material->set_shader_param("expansion_time",halflife);
  mesh->surface_set_material(0,material);

  pair<mesh_effects_iter,bool> it = mesh_effects.insert(mesh_effects_value(last_id++,0));
  MeshEffect &effect = it.first->second;
  effect.mesh = mesh;
  effect.shader_material = material;
  effect.start_time = now;
  effect.duration = halflife;
  effect.lifetime_aabb = mesh->get_aabb();
  effect.lifetime_aabb.position += position;
  effect.transform.basis = position;

  VisualServer *visual_server = VisualServer::get_singleton();
  RID rid = visual_server->instance_create2(mesh->get_rid(),scenario);
  if(rid.get_id()) {
    effect.instance = allocate_visual_rid(rid);
    effect.ready=true;
  } else
    effect.dead=true;
}
