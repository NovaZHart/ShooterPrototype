#include <GodotGlobal.hpp>
#include "VisualEffects.hpp"

#include <GodotGlobal.hpp>

using namespace std;
using namespace godot;
using namespace godot::CE;

VisualEffects::VisualEffects():
  visible_area(Vector3(-100.0f,-50.0f,-100.0f),Vector3(200.0f,100.0f,200.0f)),
  visibility_expansion_rate(Vector3(10.0f,0.0f,10.0f)),
  scenario(), delta(1.0/60), now(0.0), rand(), last_id(0),
  mesh_effects(), vertex_holder(), uv_holder(), uv2_holder(), spatial_rift_shader(),
  zap_ball_shader()
{
  vertex_holder.reserve(2000);
  uv_holder.reserve(2000);
  uv2_holder.reserve(2000);
  mesh_effects.reserve(200);
}

VisualEffects::~VisualEffects() {}

void VisualEffects::_init() {}

void VisualEffects::_register_methods() {
  register_method("clear_all_effects", &VisualEffects::clear_all_effects);
  register_method("set_visible_region", &VisualEffects::set_visible_region);
  register_method("set_shaders", &VisualEffects::set_shaders);
  register_method("step_effects", &VisualEffects::step_effects);
  register_method("set_scenario", &VisualEffects::set_scenario);
}

void VisualEffects::set_shaders(Ref<Shader> spatial_rift_shader, Ref<Shader> zap_ball_shader,
                                Ref<Shader> hyperspacing_polygon_shader, Ref<Texture> hyperspacing_texture,
                                Ref<Shader> fade_out_texture, Ref<Texture> cargo_puff_texture) {
  this->spatial_rift_shader = spatial_rift_shader;
  this->zap_ball_shader = zap_ball_shader;
  this->hyperspacing_polygon_shader = hyperspacing_polygon_shader;
  this->hyperspacing_texture = hyperspacing_texture;
  this->fade_out_texture = fade_out_texture;
  this->cargo_puff_texture = cargo_puff_texture;
}

void VisualEffects::clear_all_effects() {
  mesh_effects.clear();
}

void VisualEffects::free_unused_effects() {
  for(mesh_effects_iter it=mesh_effects.begin();it!=mesh_effects.end();)
    if(it->second.dead)
      it = mesh_effects.erase(it);
    else
      it++;
    //    it = it->second.dead ? mesh_effects.erase(it) : ++it;
}

void VisualEffects::set_visible_region(AABB visible_area,Vector3 visibility_expansion_rate) {
  this->visible_area = visible_area;
  this->visibility_expansion_rate = Vector3(fabsf(visibility_expansion_rate.x),0.0f,
                                            fabsf(visibility_expansion_rate.z));
}

void VisualEffects::set_scenario(RID scenario) {
  this->scenario=scenario;
}

void VisualEffects::step_effects(real_t delta) {
  VisibleContent *content_ptr = (VisibleContent*)visible_content;
  if(!content_ptr) {
    Godot::print_warning("No visible content from combat engine!",__FUNCTION__,__FILE__,__LINE__);
    return;
  }
  VisibleContent &vc = *content_ptr;
  VisualServer *visual_server = VisualServer::get_singleton();
  this->delta=delta;
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
      else
        step_effect(vc,effect,visual_server);
    }
  }
  // FIXME: move this to another thread:
  free_unused_effects();
}

VisibleObject * VisualEffects::get_object_or_make_stationary(VisibleContent &vc,object_id target,MeshEffect &effect) {
  ships_and_planets_iter object_iter = vc.ships_and_planets.find(effect.target1);
  if(object_iter!=vc.ships_and_planets.end())
    return &object_iter->second;

  Godot::print("Object "+str(effect.target1)+" no longer exists.");
  effect.behavior=MeshEffect::STATIONARY;
  effect.shader_material->set_shader_param("death_time",float(now-effect.start_time+effect.time_shift));
  return nullptr;
}

void VisualEffects::step_effect(VisibleContent &vc,MeshEffect &effect,VisualServer *visual_server) {
  switch(effect.behavior) {
  case(MeshEffect::CENTER_ON_TARGET1): {
    VisibleObject *object = get_object_or_make_stationary(vc,effect.target1,effect);
    if(object and (object->x!=effect.transform.origin.x or object->z!=effect.transform.origin.z)) {
      effect.transform.origin.x = object->x;
      effect.transform.origin.z = object->z;
      visual_server->instance_set_transform(effect.instance->rid,effect.transform);
    }
  } break;
  case(MeshEffect::CONSTANT_VELOCITY): {
    if(effect.velocity.length_squared()>1e-10 and effect.instance->rid.get_id()) {
      effect.transform.origin += delta*effect.velocity;
      visual_server->instance_set_transform(effect.instance->rid,effect.transform);
    }
  } break;
  case(MeshEffect::VELOCITY_RELATIVE_TO_TARGET): {
    VisibleObject *object = get_object_or_make_stationary(vc,effect.target1,effect);
    if(object) {
      effect.relative_position += delta*effect.velocity;
      real_t x=object->x+effect.relative_position.x;
      real_t z=object->z+effect.relative_position.z;
      if(effect.transform.origin.x!=x or effect.transform.origin.z!=z) {
        effect.transform.origin.x = x;
        effect.transform.origin.z = z;
        visual_server->instance_set_transform(effect.instance->rid,effect.transform);
      }
    }
  } break;
  };
  if(effect.shader_material.is_valid())
    effect.shader_material->set_shader_param("time",float(now-effect.start_time+effect.time_shift));
}

void VisualEffects::set_visible_content(VisibleContent *visible) {
  visible_content=visible;
}

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

void VisualEffects::extend_zap_pattern(Vector3 left, Vector3 right, Vector3 center,
                                       real_t extent, real_t radius, int depth) {
  Vector3 tangent = right-left;
  real_t width = tangent.length();
  tangent = tangent.normalized();
  Vector3 normal = ((right+left)/2 - center).normalized();
  real_t length = rand.randf();
  length = (length*2.0 + 1.0)*extent*radius;
  
  real_t slide = rand.randf();
  slide = length * (slide-0.5) / 5;
  
  Vector3 next_left = left + normal*length + tangent*(width/3+slide);
  Vector3 next_right = right + normal*length + tangent*(-width/3+slide);
  real_t next_dist = sqrtf(3)/2*next_left.distance_to(next_right);
  Vector3 next_back = (next_left+next_right)/2+normal*next_dist;
  Vector3 next_center = (next_left+next_right+next_back)/3;

  Vector2 center2 = Vector2(center.x,center.z);
  Vector2 next_center2 = Vector2(next_center.x,next_center.z);

  vertex_holder.push_back(left);
  uv2_holder.push_back(center2);
  vertex_holder.push_back(next_right);
  uv2_holder.push_back(next_center2);
  vertex_holder.push_back(next_left);
  uv2_holder.push_back(next_center2);

  vertex_holder.push_back(next_right);
  uv2_holder.push_back(next_center2);
  vertex_holder.push_back(left);
  uv2_holder.push_back(center2);
  vertex_holder.push_back(right);
  uv2_holder.push_back(center2);

  vertex_holder.push_back(next_left);
  uv2_holder.push_back(next_center2);
  vertex_holder.push_back(next_right);
  uv2_holder.push_back(next_center2);
  vertex_holder.push_back(next_back);
  uv2_holder.push_back(next_center2);

  if(depth<3 or (depth<5 and width>0.05 and 0.7>=rand.randf()))
    extend_zap_pattern(next_left,next_back,next_center,extent/2,radius,depth+1);
  if(depth<3 or (depth<5 and width>0.05 and 0.7>=rand.randf()))
    extend_zap_pattern(next_back,next_right,next_center,extent/2,radius,depth+1);
}

void VisualEffects::add_zap_pattern(real_t halflife, Vector3 position, real_t radius, bool reverse) {
  if(not spatial_rift_shader.is_valid() or not (halflife>0.0f))
    return;

  vertex_holder.clear();
  uv2_holder.clear();

  const int sides=5;
  real_t angle = rand.rand_angle();
  Vector3 prior = unit_from_angle(angle)*radius/5;
  for(int i=0;i<5;i++) {
    Vector3 next = unit_from_angle(angle + 2*PI * real_t(i+1)/sides)*radius/5;
    vertex_holder.push_back(prior);
    vertex_holder.push_back(Vector3(0,0,0));
    vertex_holder.push_back(next);
    uv2_holder.push_back(Vector2(0,0));
    uv2_holder.push_back(Vector2(0,0));
    uv2_holder.push_back(Vector2(0,0));
    extend_zap_pattern(prior,next,Vector3(0,0,0),0.4f,radius,1);
    prior=next;
  }  

  PoolVector3Array pool_vertices;
  PoolVector2Array pool_uv2, pool_uv;
  int nvert = vertex_holder.size();
  {
    pool_vertices.resize(nvert);
    pool_uv2.resize(nvert);
    PoolVector3Array::Write write_vertices = pool_vertices.write();
    PoolVector2Array::Write write_uv2 = pool_uv2.write();
    Vector3 *vertices = write_vertices.ptr();
    Vector2 *uv2 = write_uv2.ptr();

    for(int i=0;i<nvert;i++) {
      vertices[i] = vertex_holder[i];
      uv2[i] = uv2_holder[i];
    }
  }

  Array data;
  data.resize(ArrayMesh::ARRAY_MAX);
  data[ArrayMesh::ARRAY_VERTEX] = pool_vertices;
  data[ArrayMesh::ARRAY_TEX_UV2] = pool_uv2;
  MeshEffect &effect = add_MeshEffect(data,halflife*2,position,spatial_rift_shader);

  if(not effect.dead) {
    if(reverse) {
      effect.time_shift = halflife;
      effect.shader_material->set_shader_param("time",halflife);
    } else {
      effect.shader_material->set_shader_param("time",0.0f);
    }
    effect.shader_material->set_shader_param("expansion_time",halflife);
    effect.ready=true;
  }
}


MeshEffect &VisualEffects::add_MeshEffect(Array data, real_t duration, Vector3 position,
                                          Ref<Shader> shader) {
  Ref<ArrayMesh> mesh = ArrayMesh::_new();

  int flags = 0;
  if(data[ArrayMesh::ARRAY_VERTEX].booleanize())
    flags |= ArrayMesh::ARRAY_COMPRESS_VERTEX;
  if(data[ArrayMesh::ARRAY_TEX_UV].booleanize())
    flags |= ArrayMesh::ARRAY_COMPRESS_TEX_UV;
  if(data[ArrayMesh::ARRAY_TEX_UV2].booleanize())
    flags |= ArrayMesh::ARRAY_COMPRESS_TEX_UV2;
  if(data[ArrayMesh::ARRAY_NORMAL].booleanize())
    flags |= ArrayMesh::ARRAY_COMPRESS_NORMAL;
  
  mesh->add_surface_from_arrays(Mesh::PRIMITIVE_TRIANGLES,data,Array(),flags);
  Ref<ShaderMaterial> material = ShaderMaterial::_new();
  material->set_shader(shader);
  mesh->surface_set_material(0,material);
  Transform trans;
  trans.origin = position;
  
  pair<mesh_effects_iter,bool> it = mesh_effects.insert(mesh_effects_value(last_id++,0));
  MeshEffect &effect = it.first->second;
  effect.mesh = mesh;
  effect.shader_material = material;
  effect.start_time = now;
  effect.duration = duration;
  effect.lifetime_aabb = mesh->get_aabb();
  effect.lifetime_aabb.position += trans.origin;
  effect.transform = trans;

  VisualServer *visual_server = VisualServer::get_singleton();
  RID rid = visual_server->instance_create2(mesh->get_rid(),scenario);
  visual_server->instance_set_transform(rid,trans);
  visual_server->instance_set_layer_mask(rid,EFFECTS_LIGHT_LAYER_MASK);
  visual_server->instance_geometry_set_cast_shadows_setting(rid,0);
  if(rid.get_id()) {
    effect.instance = allocate_visual_rid(rid);
  } else {
    Godot::print_error("Failed to make an instance for new effect",__FUNCTION__,__FILE__,__LINE__);
    effect.dead=true;
  }

  return effect;
}

void VisualEffects::add_cargo_web_puff(object_id ship_id,Vector3 ship_position,Vector3 relative_position,Vector3 relative_velocity,real_t length,real_t duration,Ref<Texture> cargo_puff) {
  if(not fade_out_texture.is_valid() or ship_id<0 or not cargo_puff.is_valid())
    return;

  PoolVector3Array pool_vertices;
  PoolVector2Array pool_uv;
  pool_vertices.resize(6);
  pool_uv.resize(6);
  PoolVector3Array::Write write_vertices = pool_vertices.write();
  PoolVector2Array::Write write_uv = pool_uv.write();
  Vector3 *vertices = write_vertices.ptr();
  Vector2 *uv = write_uv.ptr();
  
  vertices[0] = Vector3(-length/2,0,length/2);
  uv[0] = Vector2(0,1);
  vertices[1] = Vector3(-length/2,0,-length/2);
  uv[1] = Vector2(0,0);
  vertices[2] = Vector3(length/2,0,-length/2);
  uv[2] = Vector2(1,0);

  vertices[3] = Vector3(length/2,0,-length/2);
  uv[3] = Vector2(1,0);
  vertices[4] = Vector3(length/2,0,length/2);
  uv[4] = Vector2(1,1);
  vertices[5] = Vector3(-length/2,0,length/2);
  uv[5] = Vector2(0,1);
  
  Array data;
  data.resize(ArrayMesh::ARRAY_MAX);
  data[ArrayMesh::ARRAY_VERTEX] = pool_vertices;
  data[ArrayMesh::ARRAY_TEX_UV] = pool_uv;
  MeshEffect &effect = add_MeshEffect(data,duration,ship_position+relative_position,fade_out_texture);

  if(not effect.dead) {
    effect.behavior = MeshEffect::VELOCITY_RELATIVE_TO_TARGET;
    effect.velocity = relative_velocity;
    effect.target1 = ship_id;
    effect.relative_position = relative_position;
    effect.shader_material->set_shader_param("image_texture",cargo_puff);
    effect.shader_material->set_shader_param("time",0.0f);
    effect.shader_material->set_shader_param("death_time",duration);
    effect.shader_material->set_shader_param("duration",duration);
    effect.ready = true;
  }
}

void VisualEffects::add_hyperspacing_polygon(real_t duration, Vector3 position, real_t radius, bool reverse, int ship_id) {
  if(not hyperspacing_polygon_shader.is_valid() or not duration>0.0f or not hyperspacing_texture.is_valid())
    return;

  Godot::print("Add hyperspacing polygon");
  if(radius<1e-5)
    Godot::print_warning("Impossible ship radius!"+str(radius),__FUNCTION__,__FILE__,__LINE__);

  real_t scaled_radius=radius/0.95;
  PoolVector3Array pool_vertices;
  PoolVector2Array pool_uv;
  int polycount = clamp(int(roundf(PI*radius/0.1)),12,120);
  int nvert = polycount*3;
  pool_vertices.resize(nvert);
  pool_uv.resize(nvert);
  PoolVector3Array::Write write_vertices = pool_vertices.write();
  PoolVector2Array::Write write_uv = pool_uv.write();
  Vector3 *vertices = write_vertices.ptr();
  Vector2 *uv = write_uv.ptr();

  Vector3 prior=Vector3(sinf(0),0,cosf(0));
  for(int i=0;i<polycount;i++) {
    real_t next_angle = 2*PI*(i+1.0f)/polycount;
    Vector3 next = Vector3(sinf(next_angle),0,cosf(next_angle));
    
    vertices[i*3+0] = prior*scaled_radius;
    uv[i*3+0] = Vector2((prior.z+1)/2,(prior.x+1)/2);
    vertices[i*3+1] = Vector3();
    uv[i*3+1] = Vector2(0.5,0.5);
    vertices[i*3+2] = next*scaled_radius;
    uv[i*3+2] = Vector2((next.z+1)/2,(next.x+1)/2);

    prior=next;
  }

  Array data;
  data.resize(ArrayMesh::ARRAY_MAX);
  data[ArrayMesh::ARRAY_VERTEX] = pool_vertices;
  data[ArrayMesh::ARRAY_TEX_UV] = pool_uv;
  MeshEffect &effect = add_MeshEffect(data,duration,position,hyperspacing_polygon_shader);

  if(not effect.dead) {
    effect.shader_material->set_shader_param("half_animation",reverse);
    effect.shader_material->set_shader_param("time",0.0f);
    effect.shader_material->set_shader_param("death_time",duration);
    effect.shader_material->set_shader_param("radius",0.95);
    effect.shader_material->set_shader_param("falloff_thickness",0.05);
    effect.shader_material->set_shader_param("duration",duration);
    effect.shader_material->set_shader_param("texture_scale",1.0);
    effect.shader_material->set_shader_param("full_alpha",1.0);
    effect.shader_material->set_shader_param("texture_albedo",hyperspacing_texture);
    effect.target1=ship_id;
    effect.behavior=MeshEffect::CENTER_ON_TARGET1;
    effect.ready=true;
  }
}

void VisualEffects::add_zap_ball(real_t duration, Vector3 position, real_t radius, bool reverse) {
  if(not zap_ball_shader.is_valid() or not (duration>0.0f))
    return;
  int polycount = clamp(int(roundf(PI*radius/0.1)),12,120);

  PoolVector3Array pool_vertices;
  PoolVector2Array pool_uv;
  int nvert = polycount*3;
  pool_vertices.resize(nvert);
  pool_uv.resize(nvert);
  PoolVector3Array::Write write_vertices = pool_vertices.write();
  PoolVector2Array::Write write_uv = pool_uv.write();
  Vector3 *vertices = write_vertices.ptr();
  Vector2 *uv = write_uv.ptr();

  Vector3 prior=Vector3(sinf(0),0,cosf(0))*radius;
  for(int i=0;i<polycount;i++) {
    real_t next_angle = 2*PI*(i+1.0f)/polycount;
    Vector3 next = Vector3(sinf(next_angle),0,cosf(next_angle))*radius;
    
    vertices[i*3+0] = prior;
    uv[i*3+0] = Vector2((i+0.0f)/polycount,1.0f);
    vertices[i*3+1] = Vector3();
    uv[i*3+1] = Vector2((i+0.5f)/polycount,0.0f);
    vertices[i*3+2] = next;
    uv[i*3+2] = Vector2((i+1.0f)/polycount,1.0f);

    prior=next;
  }

  Array data;
  data.resize(ArrayMesh::ARRAY_MAX);
  data[ArrayMesh::ARRAY_VERTEX] = pool_vertices;
  data[ArrayMesh::ARRAY_TEX_UV] = pool_uv;
  MeshEffect &effect = add_MeshEffect(data,duration,position,zap_ball_shader);
  if(not effect.dead) {
    if(reverse) {
      effect.time_shift = duration/2;
      effect.shader_material->set_shader_param("time",duration/2);
    } else {
      effect.shader_material->set_shader_param("time",0.0f);
    }
    effect.shader_material->set_shader_param("duration",duration);
    effect.shader_material->set_shader_param("v_radius",radius);
    effect.ready=true;
  }
}
