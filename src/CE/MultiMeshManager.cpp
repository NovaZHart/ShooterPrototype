#include <cstdint>
#include <limits>
#include <map>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>
#include <RID.hpp>

#include "CE/Ship.hpp"
#include "CE/VisualEffects.hpp"
#include "CE/Utils.hpp"
#include "CE/Data.hpp"
#include "CE/MultiMeshManager.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

MeshInfo::MeshInfo(object_id id, const String &resource_path):
  id(id),
  resource_path(resource_path),
  mesh_resource(),
  mesh_rid(), multimesh_rid(), visual_rid(),
  instance_count(0),
  visible_instance_count(0),
  last_frame_used(0),
  invalid(false),
  floats()
{}

MeshInfo::MeshInfo(object_id id, Ref<Mesh> mesh):
  id(id),
  resource_path(mesh->get_path()),
  mesh_resource(mesh),
  preloaded_mesh(mesh),
  mesh_rid(mesh->get_rid()), multimesh_rid(), visual_rid(),
  instance_count(0),
  visible_instance_count(0),
  last_frame_used(0),
  invalid(false),
  floats()
{}

MeshInfo::~MeshInfo() {
  bool have_multimesh = not multimesh_rid.is_valid();
  bool have_visual = not visual_rid.is_valid();
  if(have_multimesh or have_visual) {
    VisualServer *server=VisualServer::get_singleton();
    if(have_visual)
      server->free_rid(visual_rid);
    if(have_multimesh)
      server->free_rid(multimesh_rid);
  }
}
  
VisibleContent::VisibleContent():
  ships_and_planets(),
  effects(),
  mesh_paths(),
  instances(),
  next(nullptr)
{}

VisibleContent::~VisibleContent() {}

MultiMeshManager::MultiMeshManager():
  idgen(),
  v_frame(0),
  visual_server(VisualServer::get_singleton()),
  v_meshes(),
  v_path2id(),
  v_invalid_paths(),
  path2mesh(),
  mesh2path(),
  loader(ResourceLoader::get_singleton()),
  instance_locations(),
  need_new_meshes()
{
  v_meshes.reserve(max_meshes);
  instance_locations.reserve(max_ships*60);
  v_path2id.reserve(max_meshes);
  v_invalid_paths.reserve(max_meshes);
  need_new_meshes.reserve(max_meshes);
  path2mesh.reserve(max_meshes);
  mesh2path.reserve(max_meshes);
}

MultiMeshManager::~MultiMeshManager() {}

void MultiMeshManager::time_passed(real_t delta) {
  v_frame++;
}

object_id MultiMeshManager::add_preloaded_mesh(Ref<Mesh> meshref) {
  FAST_PROFILING_FUNCTION;
  if(!meshref.is_valid()) {
    Godot::print_warning("WARNING: Null mesh sent to add_preloaded_mesh.",__FUNCTION__,__FILE__,__LINE__);
    return -1;
  }
  std::unordered_map<Ref<Mesh>,object_id>::const_iterator it=v_meshref2id.find(meshref);
  if(it==v_meshref2id.end()) {
    object_id id=idgen.next();
    v_meshref2id.emplace(meshref,id);
    v_id2meshref.emplace(id,meshref);
    return id;
  } else
    return it->second;
}

object_id MultiMeshManager::add_mesh(const String &path) {
  FAST_PROFILING_FUNCTION;
  path2mesh_t::iterator it = path2mesh.find(path);
  if(it == path2mesh.end()) {
    object_id id = idgen.next();
    path2mesh.emplace(path,id);
    mesh2path.emplace(id,path);
    return id;
  }
  return it->second;
}

void MultiMeshManager::send_meshes_to_visual_server(real_t projectile_scale,RID scenario,bool reset_scenario,bool loud) {
  FAST_PROFILING_FUNCTION;
  // Update on-screen projectiles
  for(auto &vit : v_meshes) {
    if(loud)
      Godot::print("Got a mesh.");
    MeshInfo &mesh_info = vit.second;
    int count = instance_locations.count(vit.first) + instance_effects.count(vit.first);
    
    if(!count) {
      if(loud) {
        if(mesh_info.preloaded_mesh.is_valid())
          Godot::print("Unused pre-loaded mesh found with resource path \""+mesh_info.preloaded_mesh->get_path()+"\" name=\""+mesh_info.preloaded_mesh->get_name()+"\"");
        else
          Godot::print("Unused mesh found with resource path \""+mesh_info.resource_path+"\"");
      }
      unused_multimesh(mesh_info);
      continue;
    }

    pair<instlocs_iterator,instlocs_iterator> instlocs =
      instance_locations.equal_range(vit.first);
    pair<insteff_iterator,insteff_iterator> insteffs =
      instance_effects.equal_range(vit.first);

    mesh_info.last_frame_used=v_frame;

    // Make sure we have a multimesh with enough space
    if(!allocate_multimesh(mesh_info,count)) {
      if(loud)
        Godot::print_warning("allocate_multimesh failed",__FUNCTION__,__FILE__,__LINE__);
      continue;
    }

    // Make sure we have a visual instance
    if(!update_visual_instance(mesh_info,scenario,reset_scenario)) {
      if(loud)
        Godot::print_warning("update_visual_instance failed",__FUNCTION__,__FILE__,__LINE__);
      continue;
    }
    
    pack_visuals(instlocs,insteffs,mesh_info.floats,mesh_info,projectile_scale);
    
    // Send the instance data.
    visual_server->multimesh_set_visible_instances(mesh_info.multimesh_rid,count);
    mesh_info.visible_instance_count = count;
    if(loud)
      Godot::print("          ... mesh count is "+str(count));
    visual_server->multimesh_set_as_bulk_array(mesh_info.multimesh_rid,mesh_info.floats);
  }
  if(loud && !(v_frame%600)) {
    int instances=0, meshes=0, multimeshes=0, visuals=0;
    for(auto &id_info : v_meshes) {
      MeshInfo &info = id_info.second;
      instances += info.instance_count;
      meshes += info.mesh_rid.is_valid();
      multimeshes += info.multimesh_rid.is_valid();
      visuals += info.visual_rid.is_valid();
    }
    Godot::print("MultiMeshManager counts: instances="+str(instances)+" meshes="+str(meshes)+" multimeshes="+str(multimeshes)+" visuals="+str(visuals));
  }
}

void MultiMeshManager::load_meshes() {
  FAST_PROFILING_FUNCTION;
  for(auto &mesh_id : need_new_meshes) {
    v_meshes_iter mesh_it = v_meshes.find(mesh_id);
    if(mesh_it==v_meshes.end())
      // Should never get here; update_content already added the meshinfo
      continue;
    load_mesh(mesh_it->second);
  }
}

void MultiMeshManager::warn_invalid_mesh(MeshInfo &mesh,const String &why) {
  FAST_PROFILING_FUNCTION;
  if(!mesh.invalid) {
    mesh.invalid=true;
    if(mesh.preloaded_mesh.is_valid())
      Godot::print_error(String("Preloaded mesh ")+mesh.preloaded_mesh->get_path()+String(": ")+why+String(" Effect will be invisible."),__FUNCTION__,__FILE__,__LINE__);
    else
      Godot::print_error(mesh.resource_path+String(": ")+why+String(" Effect will be invisible."),__FUNCTION__,__FILE__,__LINE__);
  }
}

bool MultiMeshManager::allocate_multimesh(MeshInfo &mesh_info,int count) {
  FAST_PROFILING_FUNCTION;
  if(not mesh_info.multimesh_rid.is_valid()) {
    mesh_info.multimesh_rid = visual_server->multimesh_create();
    if(not mesh_info.multimesh_rid.is_valid()) {
      // Could not create a multimesh, so do not display the mesh this frame.
      Godot::print_error("Visual server returned an invalid rid when asked for a new multimesh.",__FUNCTION__,__FILE__,__LINE__);
      return false;
    }
    visual_server->multimesh_set_mesh(mesh_info.multimesh_rid,mesh_info.mesh_rid);
    mesh_info.instance_count = max(count,8);
    visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,2,2);
  }

  if(mesh_info.instance_count < count) {
    mesh_info.instance_count = count*1.3;
    visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,2,2);
  } else if(mesh_info.instance_count > count*2.6) {
    int new_count = max(static_cast<int>(count*1.3),8);
    if(new_count<mesh_info.instance_count) {
      mesh_info.instance_count = new_count;
      visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,2,2);
    }
  }

  return true;
}

bool MultiMeshManager::update_visual_instance(MeshInfo &mesh_info,RID scenario,bool reset_scenario) {
  FAST_PROFILING_FUNCTION;
  if(not mesh_info.visual_rid.is_valid()) {
    mesh_info.visual_rid = visual_server->instance_create2(mesh_info.multimesh_rid,scenario);
    if(not mesh_info.visual_rid.is_valid()) {
      Godot::print_error("Visual server returned an invalid rid when asked for visual instance for a multimesh.",__FUNCTION__,__FILE__,__LINE__);
      // Can't display this frame
      return false;
    }
    visual_server->instance_set_layer_mask(mesh_info.visual_rid,EFFECTS_LIGHT_LAYER_MASK);
    visual_server->instance_set_visible(mesh_info.visual_rid,true);
    visual_server->instance_geometry_set_cast_shadows_setting(mesh_info.visual_rid,0);
  } else if(reset_scenario)
    visual_server->instance_set_scenario(mesh_info.visual_rid,scenario);
  return true;
}

bool MultiMeshManager::load_mesh(MeshInfo &mesh_info) {
  FAST_PROFILING_FUNCTION;
  if(mesh_info.invalid)
    return false;
  if(loader->exists(mesh_info.resource_path)) {
    mesh_info.mesh_resource=loader->load(mesh_info.resource_path);
    Ref<Resource> mesh=mesh_info.mesh_resource;
    if(mesh_info.mesh_resource.ptr())
      mesh_info.mesh_rid = mesh_info.mesh_resource->get_rid();
    else
      mesh_info.mesh_rid = RID();
    if(not mesh_info.mesh_rid.is_valid()) {
      warn_invalid_mesh(mesh_info,"unable to load resource.");
      return false;
    } else if(!mesh->is_class("Mesh")) {
      warn_invalid_mesh(mesh_info,mesh->get_class()+"is not a Mesh.");
      return false;
    }
  } else {
    warn_invalid_mesh(mesh_info,"no resource at this path.");
    return false;
  }
  return true;
}

void MultiMeshManager::clear_all_multimeshes() {
  FAST_PROFILING_FUNCTION;
  for(auto &it : v_meshes)
    unused_multimesh(it.second);
}

void MultiMeshManager::unused_multimesh(MeshInfo &mesh_info) {
  FAST_PROFILING_FUNCTION;
  // No instances in this multimesh. Should we delete it?
  if(!mesh_info.visual_rid.is_valid() and !mesh_info.multimesh_rid.is_valid())
    return;
  
  if(v_frame > mesh_info.last_frame_used+1200) {
    //Godot::print("Freeing a multimesh");
    if(mesh_info.visual_rid.is_valid())
      visual_server->free_rid(mesh_info.visual_rid);
    if(mesh_info.multimesh_rid.is_valid())
      visual_server->free_rid(mesh_info.multimesh_rid);
    mesh_info.multimesh_rid = RID();
    mesh_info.visual_rid = RID();
  }
  if(mesh_info.multimesh_rid.is_valid()) {
    // Make sure unused multimeshes aren't too large.
    if(mesh_info.instance_count>16) {
      mesh_info.instance_count=8;
      visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,2);
    }
    if(mesh_info.visible_instance_count)
      visual_server->multimesh_set_visible_instances(mesh_info.multimesh_rid,0);
  }
  mesh_info.visible_instance_count=0;
}


void MultiMeshManager::pack_visuals(const pair<instlocs_iterator,instlocs_iterator> &visuals,
                                    const pair<insteff_iterator,insteff_iterator> &effects,
                                    PoolRealArray &floats,MeshInfo &mesh_info,real_t projectile_scale) {
  FAST_PROFILING_FUNCTION;
  
  // Change the float array so it is exactly as large as we need
  const int nfloat=20;
  floats.resize(mesh_info.instance_count*nfloat);
  int stop = mesh_info.instance_count*nfloat;
  PoolRealArray::Write writer = floats.write();
  real_t *dataptr = writer.ptr();

  // Calculate transforms for VisibleEffects
  int i=0;
  for(instlocs_iterator p_instance = visuals.first;
      p_instance!=visuals.second && i<stop;  p_instance++, i+=nfloat) {
    MeshInstanceInfo &info = p_instance->second;
    real_t scale_x = info.scale_x ? info.scale_x : projectile_scale;
    real_t scale_z = info.scale_z ? info.scale_z : projectile_scale;

    float cos_ry=cosf(info.rotation_y);
    float sin_ry=sinf(info.rotation_y);
    dataptr[i + 0] = cos_ry*scale_x;
    dataptr[i + 1] = 0.0;
    dataptr[i + 2] = sin_ry*scale_z;
    dataptr[i + 3] = info.x;
    dataptr[i + 4] = 0.0;
    dataptr[i + 5] = 1.0;
    dataptr[i + 6] = 0.0;
    dataptr[i + 7] = info.y;
    dataptr[i + 8] = -sin_ry*scale_x;
    dataptr[i + 9] = 0.0;
    dataptr[i + 10] = cos_ry*scale_z;
    dataptr[i + 11] = info.z;
    dataptr[i + 12] = 0;
    dataptr[i + 13] = 0;
    dataptr[i + 14] = 0;
    dataptr[i + 15] = 0;
    dataptr[i + 16] = info.data[0];
    dataptr[i + 17] = info.data[1];
    dataptr[i + 18] = info.data[2];
    dataptr[i + 19] = info.data[3];
  }

  // Copy the transforms for InstanceEffects
  for(insteff_iterator p_instance = effects.first;
      p_instance!=effects.second && i<stop;  p_instance++, i+=nfloat) {
    InstanceEffect &instance = p_instance->second;
    const Basis &b = instance.transform.basis;
    const Vector3 &o = instance.transform.origin;
    const Color &c = instance.color_data;
    const Color &d = instance.instance_data;
    dataptr[i + 0] = b[0][0];
    dataptr[i + 1] = b[0][1];
    dataptr[i + 2] = b[0][2];
    dataptr[i + 3] = b[1][0];
    dataptr[i + 4] = b[1][1];
    dataptr[i + 5] = b[1][2];
    dataptr[i + 6] = b[2][0];
    dataptr[i + 7] = b[2][1];
    dataptr[i + 8] = b[2][2];
    dataptr[i + 9] = o.x;
    dataptr[i + 10] = o.y;
    dataptr[i + 11] = o.z;
    dataptr[i + 12] = c.r;
    dataptr[i + 13] = c.g;
    dataptr[i + 14] = c.b;
    dataptr[i + 15] = c.a;
    dataptr[i + 16] = d.r;
    dataptr[i + 17] = d.g;
    dataptr[i + 18] = d.b;
    dataptr[i + 19] = d.a;
  }
  
  // Use identity transforms for unused instances.
  // Use identity transforms for unused instances.
  for(;i<stop;i+=nfloat) {
    dataptr[i + 0] = 1.0;
    dataptr[i + 1] = 0.0;
    dataptr[i + 2] = 0.0;
    dataptr[i + 3] = 0.0;
    dataptr[i + 4] = 0.0;
    dataptr[i + 5] = 1.0;
    dataptr[i + 6] = 0.0;
    dataptr[i + 7] = 0.0;
    dataptr[i + 8] = 0.0;
    dataptr[i + 9] = 0.0;
    dataptr[i + 10] = 1.0;
    dataptr[i + 11] = 0.0;
    dataptr[i + 12] = 0.0;
    dataptr[i + 13] = 0.0;
    dataptr[i + 14] = 0.0;
    dataptr[i + 15] = 0.0;
    dataptr[i + 16] = 0.0;
    dataptr[i + 17] = 0.0;
    dataptr[i + 18] = 0.0;
    dataptr[i + 19] = 0.0;
  }
}

void MultiMeshManager::update_content(VisibleContent &visible_content,
                                      const Vector3 &location,const Vector3 &size) {
  FAST_PROFILING_FUNCTION;
  instance_locations.clear();
  instance_effects.clear();
  need_new_meshes.clear();
  
  real_t loc_min_x = min(location.x-size.x/2,location.x+size.x/2);
  real_t loc_max_x = max(location.x-size.x/2,location.x+size.x/2);
  real_t loc_min_y = min(location.z-size.z/2,location.z+size.z/2);
  real_t loc_max_y = max(location.z-size.z/2,location.z+size.z/2);

  for(auto &effect : visible_content.effects) {
    object_id mesh_id = effect.mesh_id;
    if(effect.center.x-effect.half_size.x > loc_max_x or
       effect.center.x+effect.half_size.x < loc_min_x or
       effect.center.y-effect.half_size.y > loc_max_y or
       effect.center.y+effect.half_size.y < loc_min_y)
      continue; // projectile is off-screen

    MeshInstanceInfo instance_info =
      {
        effect.center.x,   // instance_info.x
        effect.y,          // .y
        effect.center.y,   // .z
        effect.rotation_y, // .rotation_y
        effect.scale_x,    // .scale_x
        effect.scale_z,    // .scale_z
        effect.data        // .data
      };

    instance_locations.emplace(mesh_id,instance_info);
    add_instance_mesh_id(visible_content,mesh_id);
  }

  for(auto &instance : visible_content.instances) {
    Vector2 center(instance.transform.origin.x,instance.transform.origin.z);
    
    if(center.x-instance.half_size.x > loc_max_x or
       center.x+instance.half_size.x < loc_min_x or
       center.y-instance.half_size.y > loc_max_y or
       center.y+instance.half_size.y < loc_min_y)
      continue; // projectile is off-screen

    object_id mesh_id = instance.mesh_id;
    instance_effects.emplace(mesh_id,instance);
    add_instance_mesh_id(visible_content,mesh_id);
  }
}

void MultiMeshManager::add_instance_mesh_id(VisibleContent &visible_content,object_id mesh_id) {
  v_meshes_iter mit = v_meshes.find(mesh_id);
  if(mit==v_meshes.end()) {
    mesh_paths_iter pit = visible_content.mesh_paths.find(mesh_id);
      
    if(pit==visible_content.mesh_paths.end() or pit->second.empty()) {
      auto id_meshref=v_id2meshref.find(mesh_id);
      //preloaded_meshes_iter pmi = visible_content.preloaded_meshes.find(mesh_id);
      if(id_meshref==v_id2meshref.end() or not id_meshref->second.is_valid()) {
        // Should never get here. This means the physics thread
        // generated an effect without sending its mesh resource path.
        pair<v_meshes_iter,bool> emplaced = v_meshes.emplace(mesh_id,MeshInfo(mesh_id,"(*unspecified resource*)"));
        warn_invalid_mesh(emplaced.first->second,"internal error: no mesh path or preloaded mesh sent from physics thread.");
        return;
      }
      v_meshes.emplace(mesh_id,MeshInfo(mesh_id,id_meshref->second));
    } else {
      v_meshes.emplace(mesh_id,MeshInfo(mesh_id,pit->second));
      need_new_meshes.insert(mesh_id);
    }
  }
}
