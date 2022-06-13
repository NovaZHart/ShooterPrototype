#include <GodotGlobal.hpp>
#include "VisualEffects.hpp"

#include <GodotGlobal.hpp>

using namespace std;
using namespace godot;
using namespace godot::CE;

VisualEffect::VisualEffect(object_id effect_id,double start_time,real_t duration,real_t time_shift,
                           const Vector3 &position,real_t rotation,const AABB &lifetime_aabb,
                           bool expire_out_of_view):
  id(effect_id), lifetime_aabb(lifetime_aabb), start_time(start_time),
  duration(duration), time_shift(time_shift), rotation(rotation),
  velocity(), relative_position(), position(),
  instance(), ready(false), dead(false), expire_out_of_view(expire_out_of_view),
  behavior(), target1(-1)
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

void MeshEffect::step_effect(VisualServer *visual_server,double time,bool update_transform,bool update_death,real_t projectile_scale) {
  FAST_PROFILING_FUNCTION;
  if(update_transform) {
    Transform trans = calculate_transform();
    visual_server->instance_set_transform(instance->rid,trans);
  }
  if(shader_material.is_valid()) {
    float effect_time=time-start_time+time_shift;
    if(update_death)
      shader_material->set_shader_param("death_time",effect_time);
    shader_material->set_shader_param("time",effect_time);
    shader_material->set_shader_param("projectile_scale",projectile_scale);
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
                                                 const Vector3 &position,real_t rotation,const AABB &lifetime_aabb,
                                                 bool expire_out_of_view):
  VisualEffect(effect_id,start_time,duration,time_shift,position,rotation,lifetime_aabb,expire_out_of_view),
  mesh_id(mesh_id), data(start_time,duration,duration), half_size(Vector2(lifetime_aabb.size.x/2,lifetime_aabb.size.y/2))
{}
MultiMeshInstanceEffect::~MultiMeshInstanceEffect() {}

void MultiMeshInstanceEffect::step_effect(VisualServer *visual_server,double time,bool update_transform,bool update_death,real_t projectile_scale) {
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
  fade_out_texture(), hyperspacing_texture(), cargo_puff_texture(),
  shield_ellipse_shader(), content(), combat_content(nullptr)
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
  register_method("step_effects", &VisualEffects::step_effects);
  register_method("set_scenario", &VisualEffects::set_scenario);
  register_method("free_unused_effects", &VisualEffects::free_unused_effects);

  register_property<VisualEffects, Ref<Shader>>("spatial_rift_shader", &VisualEffects::spatial_rift_shader, Ref<Shader>());
  register_property<VisualEffects, Ref<Shader>>("zap_ball_shader", &VisualEffects::zap_ball_shader, Ref<Shader>());
  register_property<VisualEffects, Ref<Shader>>("hyperspacing_polygon_shader", &VisualEffects::hyperspacing_polygon_shader, Ref<Shader>());
  register_property<VisualEffects, Ref<Shader>>("fade_out_texture", &VisualEffects::fade_out_texture, Ref<Shader>());
  register_property<VisualEffects, Ref<Shader>>("shield_ellipse_shader", &VisualEffects::shield_ellipse_shader, Ref<Shader>());
  register_property<VisualEffects, Ref<Texture>>("hyperspacing_texture", &VisualEffects::hyperspacing_texture, Ref<Texture>());
  register_property<VisualEffects, Ref<Texture>>("cargo_puff_texture", &VisualEffects::cargo_puff_texture, Ref<Texture>());
  register_property<VisualEffects, Ref<Texture>>("shield_texture", &VisualEffects::shield_texture, Ref<Texture>());
}

void VisualEffects::clear_all_effects() {
  mesh_effects.clear();
}

void VisualEffects::free_unused_effects() {
  FAST_PROFILING_FUNCTION;
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

void VisualEffects::step_effects(real_t delta,Vector3 location,Vector3 size,real_t projectile_scale) {
  FAST_PROFILING_FUNCTION;
  VisualServer *visual_server = VisualServer::get_singleton();
  this->delta=delta;
  now+=delta;

  AABB clipping_area(visible_area.position - visibility_expansion_rate*4,
                     visible_area.size + visibility_expansion_rate*8);

  // Step all Mesh-based effects
  for(mesh_effects_iter it=mesh_effects.begin();it!=mesh_effects.end();it++) {
    VisualEffect &effect = it->second;
    if(not effect.ready or effect.dead)
      continue;
    step_effect(effect,visual_server,clipping_area,projectile_scale);
  }

  // Step all effects that are MultiMeshInstances:
  for(mmi_effects_iter it=mmi_effects.begin();it!=mmi_effects.end();it++) {
    VisualEffect &effect = it->second;
    if(not effect.ready or effect.dead)
      continue;
    step_effect(effect,visual_server,clipping_area,projectile_scale);
  }

  step_multimeshes(delta,location,size);
}

void VisualEffects::step_multimeshes(real_t delta,Vector3 location,Vector3 size) {
  FAST_PROFILING_FUNCTION;
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

void VisualEffects::step_effect(VisualEffect &effect,VisualServer *visual_server,const AABB &clipping_area,real_t projectile_scale) {
  FAST_PROFILING_FUNCTION;
  if(effect.duration and (now-effect.start_time)>effect.duration) {
    effect.dead=true;
    return;
  }

  if(effect.expire_out_of_view) {
    if(not clipping_area.intersects(effect.lifetime_aabb)) {
      effect.dead=true;
      return;
    }
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
    } else {
      if(not effect.duration)
        effect.dead=true;
      update_death=true;
    }
  } break;
  case(CENTER_AND_ROTATE_ON_TARGET1): {
    VisibleObject *object = get_object_or_make_stationary(effect.target1,effect);
    if(object) {
      if(object->x!=effect.position.x or object->z!=effect.position.z
         or object->rotation_y!=effect.rotation) {
        effect.position.x = object->x;
        effect.position.z = object->z;
        effect.rotation = object->rotation_y;
        update_transform=true;
      }
    } else {
      if(not effect.duration)
        effect.dead=true;
      update_death=true;
    }
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
    } else {
      if(not effect.duration)
        effect.dead=true;
      update_death=true;
    }
  } break;
  case STATIONARY: { /* nothing to do */ } break;
  };
  effect.step_effect(visual_server,now,update_transform,update_death,projectile_scale);
}

void VisualEffects::add_content() {
  FAST_PROFILING_FUNCTION;
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
                                          real_t rotation,Ref<Shader> shader,
                                          bool expire_out_of_view) {
  FAST_PROFILING_FUNCTION;
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
  if(data[ArrayMesh::ARRAY_COLOR].booleanize())
    flags |= ArrayMesh::ARRAY_COMPRESS_COLOR;
  
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
  effect.expire_out_of_view = expire_out_of_view;
  if(effect.expire_out_of_view) {
    effect.lifetime_aabb = mesh->get_aabb();
    effect.lifetime_aabb.position += position;
  }

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
                                                      real_t rotation,bool expire_out_of_view) {
  FAST_PROFILING_FUNCTION;
  object_id mesh_id=multimeshes.get_preloaded_mesh_id(mesh);
  if(mesh_id<0) {
    mesh_id=multimeshes.add_preloaded_mesh(mesh);
  }

  object_id effect_id=idgen.next();
  AABB aabb = expire_out_of_view ? mesh->get_aabb() : AABB();
  pair<mmi_effects_iter,bool> it =
    mmi_effects.emplace(effect_id,MultiMeshInstanceEffect(effect_id,mesh_id,now,duration,0,position,rotation,
                                                          aabb,expire_out_of_view));

  return it.first->second;
}

void VisualEffects::add_cargo_web_puff_MeshEffect(const godot::CE::Ship &ship,Vector3 relative_position,Vector3 relative_velocity,real_t length,real_t duration,Ref<Texture> cargo_puff) {
  FAST_PROFILING_FUNCTION;
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
  MeshEffect &effect = add_MeshEffect(data,duration,ship.position+relative_position,0,fade_out_texture,true);

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
  FAST_PROFILING_FUNCTION;
  real_t aabb_growth = (velocity.length())*duration;

  if(not is_circle_visible(ship.position,length*2+aabb_growth)) {
    return;
  }
  if(cargo_puff.is_null()) {
    return;
  }
  
  MultiMeshInstanceEffect &effect = add_MMIEffect(cargo_puff,duration,position,0,false);

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
  FAST_PROFILING_FUNCTION;
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
  MeshEffect &effect = add_MeshEffect(data,duration,position,0,hyperspacing_polygon_shader,false);

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
  } else {
    Godot::print_warning("Hyperspacing polygon is dead on arrival.",__FUNCTION__,__FILE__,__LINE__);
  }
}

inline Vector3 negX(Vector3 v) {
  return Vector3(-v.x,v.y,v.z);
}

inline Vector3 negZ(Vector3 v) {
  return Vector3(v.x,v.y,-v.z);
}

inline Vector3 negXZ(Vector3 v) {
  return Vector3(-v.x,v.y,-v.z);
}

////////////////////////////////////////////////////////////////////////

void VisualEffects::add_shield_ellipse(const Ship &ship,const AABB &aabb,real_t requested_spacing,real_t thickness,Color faction_color) {
  FAST_PROFILING_FUNCTION;
  static bool printed=false;
  static const real_t sqrt2 = sqrtf(2);
  real_t rect_width=fabsf(aabb.size.x/2);
  real_t ellipse_width=rect_width/sqrt2;
  real_t rect_height=fabsf(aabb.size.z/2);
  real_t ellipse_height=rect_height/sqrt2;
  
  real_t max_radius=ellipse_width;
  real_t min_radius=ellipse_width;
  if(ellipse_height>max_radius)
    max_radius=ellipse_height;
  if(ellipse_width<min_radius)
    min_radius=ellipse_height;
  real_t high_ratio = max_radius/min_radius;
  assert(high_ratio>0);

  if(ship.name=="player_ship")
    Godot::print("MAKING ELLIPSE FOR PLAYER SHIP");

  // Expand the ellipse a little bit so the innermost part of each
  // outer edge is outside the ellipse. This formula is approximate,
  // based on squishing a circle.
  real_t effective_radius=(max_radius+min_radius)/2;
  assert(effective_radius>0.2);
  real_t spacing = clamp(requested_spacing,0.04f,effective_radius/2);
  real_t expand_radius = (effective_radius-spacing)*high_ratio;
  assert(expand_radius>0);
  ellipse_width += expand_radius;
  ellipse_height += expand_radius;
  max_radius = max(ellipse_width,ellipse_height);
  min_radius = min(ellipse_width,ellipse_height);
  high_ratio = max_radius/min_radius;

  // There must be a multiple of four edges along the circumference of the ellipse.
  // This approximation comes from Srinivasa Ramanujan
  real_t rama_h = ((ellipse_width-ellipse_height)*(ellipse_width-ellipse_height)) /
    ((ellipse_width+ellipse_height)*(ellipse_width+ellipse_height));
  assert(rama_h>=0);
  real_t approximate_circumference = PI*(ellipse_width+ellipse_height)*(1+3*rama_h/(10+sqrtf(4-3*rama_h)));
  assert(approximate_circumference>0);
  real_t outer_edges_f = ceilf(approximate_circumference/(spacing*4))*4;
  int outer_edges=outer_edges_f;
  spacing = approximate_circumference/outer_edges;

  assert(outer_edges>=8);
  
  PoolColorArray pool_colors;
  PoolVector3Array pool_vertices;
  PoolVector2Array pool_uv;
  
  {
    int nvert = outer_edges*6;
    pool_vertices.resize(nvert);
    pool_uv.resize(nvert);
    pool_colors.resize(nvert);
    PoolVector3Array::Write write_vertices = pool_vertices.write();
    PoolVector2Array::Write write_uv = pool_uv.write();
    PoolColorArray::Write write_color = pool_colors.write();
    Vector3 *vertices = write_vertices.ptr();
    Vector2 *uv = write_uv.ptr();
    Color *colors = write_color.ptr();

    for(int j=0;j<nvert;j++)
      colors[j]=faction_color;

    Vector2 prior_mid=Vector2(ellipse_width*sinf(0),ellipse_height*cosf(0));
    Vector2 prior_thickness = prior_mid.normalized()*thickness/2;
    Vector2 prior_inner = prior_mid-prior_thickness;
    Vector2 prior_outer = prior_mid+prior_thickness;
    real_t prior_t=0;
    int i=0;
  
    for(int end_i=outer_edges/4;i<end_i;i++) {
      real_t t=(i+1)/outer_edges_f;
      real_t tt=t*4;
      real_t next_angle = (PI*tt)/(ellipse_width+ellipse_height);
      next_angle *= (ellipse_height + tt*(ellipse_width-ellipse_height)/2);

      Vector2 next_mid=Vector2(ellipse_width*sinf(next_angle),ellipse_height*cosf(next_angle));
      Vector2 next_thickness = next_mid.normalized()*thickness/2;
      Vector2 next_inner = next_mid-next_thickness;
      Vector2 next_outer = next_mid+next_thickness;
      
      vertices[i*6+0] = Vector3(prior_outer.x,0,prior_outer.y);
      vertices[i*6+1] = Vector3(prior_inner.x,0,prior_inner.y);
      vertices[i*6+2] = Vector3(next_outer.x,0,next_outer.y);

      uv[i*6+0] = Vector2(prior_t,1);
      uv[i*6+1] = Vector2(prior_t,0);
      uv[i*6+2] = Vector2(t,1);
      
      vertices[i*6+3] = Vector3(prior_inner.x,0,prior_inner.y);
      vertices[i*6+4] = Vector3(next_inner.x,0,next_inner.y);
      vertices[i*6+5] = Vector3(next_outer.x,0,next_outer.y);

      uv[i*6+3] = Vector2(prior_t,0);
      uv[i*6+4] = Vector2(t,0);
      uv[i*6+5] = Vector2(t,1);

      prior_outer=next_outer;
      prior_inner=next_inner;
      prior_t=t;
    }

    // Second Quadrant is the same as the first, but reversed order and -Y
    for(int j=outer_edges/4-1;j>=0;i++,j--) {
      real_t t=(i+1)/outer_edges_f;
      vertices[i*6+0] = negZ(vertices[j*6+1]);
      vertices[i*6+1] = negZ(vertices[j*6+0]);
      vertices[i*6+2] = negZ(vertices[j*6+2]);

      uv[i*6+0] = Vector2(0.5-uv[j*6+1].x,uv[j*6+1].y);
      uv[i*6+1] = Vector2(0.5-uv[j*6+0].x,uv[j*6+0].y);
      uv[i*6+2] = Vector2(0.5-uv[j*6+2].x,uv[j*6+2].y);

      vertices[i*6+3] = negZ(vertices[j*6+3]);
      vertices[i*6+4] = negZ(vertices[j*6+5]);
      vertices[i*6+5] = negZ(vertices[j*6+4]);

      uv[i*6+3] = Vector2(0.5-uv[j*6+3].x,uv[j*6+3].y);
      uv[i*6+4] = Vector2(0.5-uv[j*6+5].x,uv[j*6+5].y);
      uv[i*6+5] = Vector2(0.5-uv[j*6+4].x,uv[j*6+4].y);

      prior_t=t;
    }

    // Third quadrant is the same as the first, but with -X and -Y
    for(int j=0;j<outer_edges/4;i++,j++) {
      real_t t=(i+1)/outer_edges_f;
      vertices[i*6+0] = negXZ(vertices[j*6+0]);
      vertices[i*6+1] = negXZ(vertices[j*6+1]);
      vertices[i*6+2] = negXZ(vertices[j*6+2]);

      uv[i*6+0] = Vector2(0.5+uv[j*6+0].x,uv[j*6+0].y);
      uv[i*6+1] = Vector2(0.5+uv[j*6+1].x,uv[j*6+1].y);
      uv[i*6+2] = Vector2(0.5+uv[j*6+2].x,uv[j*6+2].y);
      
      vertices[i*6+3] = negXZ(vertices[j*6+3]);
      vertices[i*6+4] = negXZ(vertices[j*6+4]);
      vertices[i*6+5] = negXZ(vertices[j*6+5]);

      uv[i*6+3] = Vector2(0.5+uv[j*6+3].x,uv[j*6+3].y);
      uv[i*6+4] = Vector2(0.5+uv[j*6+4].x,uv[j*6+4].y);
      uv[i*6+5] = Vector2(0.5+uv[j*6+5].x,uv[j*6+5].y);

      prior_t=t;
    }

    // Fourth quadrant is the same as the first, but reversed order and -X 
    for(int j=outer_edges/4-1;j>=0;i++,j--) {
      real_t t=(i+1)/outer_edges_f;
      vertices[i*6+0] = negX(vertices[j*6+1]);
      vertices[i*6+1] = negX(vertices[j*6+0]);
      vertices[i*6+2] = negX(vertices[j*6+2]);

      uv[i*6+0] = Vector2(1-uv[j*6+1].x,uv[j*6+1].y);
      uv[i*6+1] = Vector2(1-uv[j*6+0].x,uv[j*6+0].y);
      uv[i*6+2] = Vector2(1-uv[j*6+2].x,uv[j*6+2].y);

      vertices[i*6+3] = negX(vertices[j*6+3]);
      vertices[i*6+4] = negX(vertices[j*6+5]);
      vertices[i*6+5] = negX(vertices[j*6+4]);

      uv[i*6+3] = Vector2(1-uv[j*6+3].x,uv[j*6+3].y);
      uv[i*6+4] = Vector2(1-uv[j*6+5].x,uv[j*6+5].y);
      uv[i*6+5] = Vector2(1-uv[j*6+4].x,uv[j*6+4].y);

      prior_t=t;
    }
  }
  
  Array data;
  data.resize(ArrayMesh::ARRAY_MAX);
  data[ArrayMesh::ARRAY_VERTEX] = pool_vertices;
  data[ArrayMesh::ARRAY_TEX_UV] = pool_uv;
  data[ArrayMesh::ARRAY_COLOR] = pool_colors;
  Vector3 position=ship.position;
  position.y=below_ships;

  if(ship.name=="player_ship")
    Godot::print("PLAYER SHIP VISUAL HEIGHT "+str(position.y));

  MeshEffect &effect = add_MeshEffect(data,0,position,0,shield_ellipse_shader,false);
  
  if(not effect.dead) {
    effect.target1=ship.id;
    effect.behavior=CENTER_AND_ROTATE_ON_TARGET1;
    effect.shader_material->set_shader_param("shield_texture",shield_texture);
    effect.ready=true;
  } else
    Godot::print_warning("Shield ellipse is dead on arrival",__FUNCTION__,__FILE__,__LINE__);

  printed=true;
}
