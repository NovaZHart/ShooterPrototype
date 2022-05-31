#include <GodotGlobal.hpp>
#include "VisualEffects.hpp"

#include <GodotGlobal.hpp>

using namespace std;
using namespace godot;
using namespace godot::CE;

VisualEffect::VisualEffect(object_id effect_id,double start_time,real_t duration,real_t time_shift,
                           const Vector3 &position,real_t rotation,const AABB &lifetime_aabb):
  id(effect_id), lifetime_aabb(lifetime_aabb), start_time(start_time),
  duration(duration), time_shift(time_shift), rotation(rotation),
  velocity(), relative_position(), position(),
  instance(), ready(false), dead(false), behavior(), target1(-1)
{
  this->lifetime_aabb.position += position;
}

VisualEffect::VisualEffect():
  lifetime_aabb(), start_time(-9e9),
  duration(0.0f), time_shift(0.0f), rotation(),
  velocity(0,0,0), relative_position(), 
  position(), instance(), ready(false), dead(false),
  behavior(CONSTANT_VELOCITY), target1(-1)
{}
VisualEffect::~VisualEffect()
{}

////////////////////////////////////////////////////////////////////////

MeshEffect::MeshEffect():
  VisualEffect(), mesh(), shader_material()
{}
MeshEffect::~MeshEffect() {}

void MeshEffect::step_effect(VisualServer *visual_server,double time,bool update_transform,bool update_death) {
  if(update_transform) {
    Transform trans = calculate_transform();
    visual_server->instance_set_transform(instance->rid,trans);
  }
  if(shader_material.is_valid()) {
    float effect_time=time-start_time+time_shift;
    if(update_death)
      shader_material->set_shader_param("death_time",effect_time);
    shader_material->set_shader_param("time",effect_time);
  } else {
    Godot::print_warning("Invalid shader material.",__FUNCTION__,__FILE__,__LINE__);
  }
}

////////////////////////////////////////////////////////////////////////

MultiMeshInstanceEffect::MultiMeshInstanceEffect():
  VisualEffect(), mesh_id(-1), data()
{}
MultiMeshInstanceEffect::MultiMeshInstanceEffect(object_id effect_id,object_id mesh_id,double start_time,
                                                 real_t duration,real_t time_shift,
                                                 const Vector3 &position,real_t rotation,const AABB &lifetime_aabb):
  VisualEffect(effect_id,start_time,duration,time_shift,position,rotation,lifetime_aabb),
  mesh_id(mesh_id), data(start_time,duration,duration), half_size(Vector2(lifetime_aabb.size.x/2,lifetime_aabb.size.y/2))
{}
MultiMeshInstanceEffect::~MultiMeshInstanceEffect() {}

void MultiMeshInstanceEffect::step_effect(VisualServer *visual_server,double time,bool update_transform,bool update_death) {
  float effect_time=time-start_time+time_shift;
  set_time(effect_time);
  if(update_death)
    set_death_time(effect_time);
}

////////////////////////////////////////////////////////////////////////

VisualEffects::VisualEffects():
  multimeshes(),
  visible_area(Vector3(-100.0f,-50.0f,-100.0f),Vector3(200.0f,100.0f,200.0f)),
  visibility_expansion_rate(Vector3(10.0f,0.0f,10.0f)),
  scenario(), delta(1.0/60), now(0.0), rand(), idgen(),
  mesh_effects(), mmi_effects(), vertex_holder(), uv2_holder(), uv_holder(),
  spatial_rift_shader(), zap_ball_shader(), hyperspacing_polygon_shader(),
  fade_out_texture(), hyperspacing_texture(), cargo_puff_texture(), content(),
  combat_content(nullptr)
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
  register_method("free_unused_effects", &VisualEffects::free_unused_effects);
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
  for(mmi_effects_iter it=mmi_effects.begin();it!=mmi_effects.end();)
    if(it->second.dead)
      it = mmi_effects.erase(it);
    else
      it++;
}

void VisualEffects::set_visible_region(AABB visible_area,Vector3 visibility_expansion_rate) {
  this->visible_area = visible_area;
  this->visibility_expansion_rate = Vector3(fabsf(visibility_expansion_rate.x),0.0f,
                                            fabsf(visibility_expansion_rate.z));
}

void VisualEffects::set_scenario(RID new_scenario) {
  scenario=new_scenario;
  reset_scenario=true;
}

void VisualEffects::step_effects(real_t delta,Vector3 location,Vector3 size) {
  VisualServer *visual_server = VisualServer::get_singleton();
  this->delta=delta;
  now+=delta;

  // Step all Mesh-based effects
  for(mesh_effects_iter it=mesh_effects.begin();it!=mesh_effects.end();it++) {
    VisualEffect &effect = it->second;
    if(not effect.ready or effect.dead)
      continue;
    step_effect(effect,visual_server);
  }

  // Step all effects that are MultiMeshInstances:
  for(mmi_effects_iter it=mmi_effects.begin();it!=mmi_effects.end();it++) {
    VisualEffect &effect = it->second;
    if(not effect.ready or effect.dead)
      continue;
    step_effect(effect,visual_server);
  }

  step_multimeshes(delta,location,size);
}

void VisualEffects::step_multimeshes(real_t delta,Vector3 location,Vector3 size) {
  multimeshes.time_passed(delta);
  pair<bool,VisibleContent *> newflag_visible = content.update_visible_content();
  if(!newflag_visible.second) {
    // No content yet. This is expected in the first frame.
    //Godot::print_warning("No visible content in visual effects!",__FUNCTION__,__FILE__,__LINE__);
    return;
  }
  if(!newflag_visible.first)
    // No new content. This will happen when multiple visual frames occur between two physics frames.
    return;

  multimeshes.update_content(*newflag_visible.second,location,size);
  multimeshes.load_meshes();
  multimeshes.send_meshes_to_visual_server(1,scenario,reset_scenario,false);
}

VisibleObject * VisualEffects::get_object_or_make_stationary(object_id target,VisualEffect &effect) {
  ships_and_planets_iter object_iter = combat_content->ships_and_planets.find(target);
  if(object_iter!=combat_content->ships_and_planets.end())
    return &object_iter->second;
  effect.behavior=STATIONARY;
  return nullptr;
}

void VisualEffects::step_effect(VisualEffect &effect,VisualServer *visual_server) {
  if((now-effect.start_time)>effect.duration) {
    effect.dead=true;
    return;
  }

  AABB expanded(visible_area.position - visibility_expansion_rate*effect.duration,
                visible_area.size + 2*visibility_expansion_rate*effect.duration);
  if(not expanded.intersects(effect.lifetime_aabb)) {
    effect.dead=true;
    return;
  }
      
  bool update_transform=false, update_death=false;
  switch(effect.behavior) {
  case(CENTER_ON_TARGET1): {
    VisibleObject *object = get_object_or_make_stationary(effect.target1,effect);
    if(object) {
      if(object->x!=effect.position.x or object->z!=effect.position.z) {
        effect.position.x = object->x;
        effect.position.z = object->z;
        update_transform=true;
      }
    } else
      update_death=true;
  } break;
  case(CONSTANT_VELOCITY): {
    effect.position += delta*effect.velocity;
    update_transform=true;
  } break;
  case(VELOCITY_RELATIVE_TO_TARGET): {
    VisibleObject *object = get_object_or_make_stationary(effect.target1,effect);
    if(object) {
      effect.relative_position += delta*effect.velocity;
      real_t x=object->x+effect.relative_position.x;
      real_t z=object->z+effect.relative_position.z;
      if(effect.position.x!=x or effect.position.z!=z) {
        effect.position.x = x;
        effect.position.z = z;
        update_transform=true;
      }
    } else
      update_death=true;
  } break;
  case STATIONARY: { /* nothing to do */ } break;
  };
  effect.step_effect(visual_server,now,update_transform,update_death);
}

void VisualEffects::add_content() {
  VisibleContent *next = new VisibleContent();
  next->effects.reserve(mmi_effects.size());
  for(auto &id_effect : mmi_effects) {
    MultiMeshInstanceEffect &effect=id_effect.second;
    if(effect.ready and not effect.dead)
      next->effects.emplace_back(effect);
  }
  content.push_content(next);
}

/* - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - */

MeshEffect &VisualEffects::add_MeshEffect(Array data, real_t duration, Vector3 position,
                                          real_t rotation,Ref<Shader> shader) {
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
  
  pair<mesh_effects_iter,bool> it = mesh_effects.insert(mesh_effects_value(idgen.next(),MeshEffect()));
  MeshEffect &effect = it.first->second;
  effect.rotation = rotation;
  effect.position = position;
  effect.mesh = mesh;
  effect.shader_material = material;
  effect.start_time = now;
  effect.duration = duration;
  effect.lifetime_aabb = mesh->get_aabb();
  effect.lifetime_aabb.position += position;

  VisualServer *visual_server = VisualServer::get_singleton();
  RID rid = visual_server->instance_create2(mesh->get_rid(),scenario);
  visual_server->instance_set_transform(rid,effect.calculate_transform());
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


MultiMeshInstanceEffect &VisualEffects::add_MMIEffect(Ref<Mesh> mesh, real_t duration, Vector3 position,
                                                      real_t rotation) {
  object_id mesh_id=multimeshes.get_preloaded_mesh_id(mesh);
  if(mesh_id<0) {
    mesh_id=multimeshes.add_preloaded_mesh(mesh);
  }

  object_id effect_id=idgen.next();
  pair<mmi_effects_iter,bool> it =
    mmi_effects.emplace(effect_id,MultiMeshInstanceEffect(effect_id,mesh_id,now,duration,0,position,rotation,
                                                          mesh->get_aabb()));
  return it.first->second;
}

void VisualEffects::add_cargo_web_puff_MeshEffect(const godot::CE::Ship &ship,Vector3 relative_position,Vector3 relative_velocity,real_t length,real_t duration,Ref<Texture> cargo_puff) {
  real_t aabb_growth = (ship.max_speed + relative_velocity.length())*duration;

  if(not is_circle_visible(ship.position,length*2+aabb_growth) or cargo_puff.is_null())
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
  MeshEffect &effect = add_MeshEffect(data,duration,ship.position+relative_position,0,fade_out_texture);

  effect.lifetime_aabb.grow_by(aabb_growth);
  
  if(not effect.dead) {
    effect.behavior = CONSTANT_VELOCITY; // VELOCITY_RELATIVE_TO_TARGET;
    effect.velocity = relative_velocity;
    effect.target1 = ship.id;
    effect.relative_position = relative_position;
    effect.shader_material->set_shader_param("image_texture",cargo_puff);
    effect.shader_material->set_shader_param("time",0.0f);
    effect.shader_material->set_shader_param("death_time",duration);
    effect.shader_material->set_shader_param("duration",duration);
    effect.ready = true;
  }
}

void VisualEffects::add_cargo_web_puff_MMIEffect(const godot::CE::Ship &ship,Vector3 position,Vector3 velocity,real_t length,real_t duration,Ref<Mesh> cargo_puff) {
  real_t aabb_growth = (velocity.length())*duration;

  if(not is_circle_visible(ship.position,length*2+aabb_growth)) {
    return;
  }
  if(cargo_puff.is_null()) {
    return;
  }
  
  MultiMeshInstanceEffect &effect = add_MMIEffect(cargo_puff,duration,position,0);

  if(not effect.dead) {
    effect.lifetime_aabb.grow_by(aabb_growth);
    effect.behavior = CONSTANT_VELOCITY;
    effect.velocity = velocity;
    effect.target1 = ship.id;
    effect.position = position;
    effect.ready = true;
  }
}

bool VisualEffects::is_circle_visible(const Vector3 &position, real_t radius) const {
  Vector3 start=visible_area.position, end=visible_area.position+visible_area.size;
  if(position.x-radius>=end.x or position.x+radius<start.x or
     position.z-radius>end.z  or position.z+radius<start.z)
    return false;
  return true;
}

void VisualEffects::add_hyperspacing_polygon(real_t duration, Vector3 position, real_t radius, bool reverse, object_id ship_id) {
  if(not is_circle_visible(position,radius) or not (duration>0.0f))
    return;

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
  MeshEffect &effect = add_MeshEffect(data,duration,position,0,hyperspacing_polygon_shader);

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
    effect.behavior=CENTER_ON_TARGET1;
    effect.ready=true;
  }
}
