#include <cstdint>
#include <cmath>
#include <limits>
#include <map>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>
#include <RID.hpp>

#include "CombatEngineUtils.hpp"
#include "CombatEngineData.hpp"
#include "MultiMeshManager.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

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

object_id MultiMeshManager::add_mesh(const String &path) {
  path2mesh_t::iterator it = path2mesh.find(path);
  if(it == path2mesh.end()) {
    object_id id = idgen.next();
    path2mesh.emplace(path,id);
    mesh2path.emplace(id,path);
    return id;
  }
  return it->second;
}

void MultiMeshManager::send_meshes_to_visual_server(real_t projectile_scale,RID scenario,bool reset_scenario) {
  // Update on-screen projectiles
  for(auto &vit : v_meshes) {
    MeshInfo &mesh_info = vit.second;
    int count = instance_locations.count(vit.first);
    
    if(!count) {
      unused_multimesh(mesh_info);
      continue;
    }

    pair<instlocs_iterator,instlocs_iterator> instances =
      instance_locations.equal_range(vit.first);

    mesh_info.last_frame_used=v_frame;

    // Make sure we have a multimesh with enough space
    if(!allocate_multimesh(mesh_info,count))
      continue;

    // Make sure we have a visual instance
    if(!update_visual_instance(mesh_info,scenario,reset_scenario))
      continue;
    
    pack_projectiles(instances,mesh_info.floats,mesh_info,projectile_scale);
    
    // Send the instance data.
    visual_server->multimesh_set_visible_instances(mesh_info.multimesh_rid,count);
    mesh_info.visible_instance_count = count;
    visual_server->multimesh_set_as_bulk_array(mesh_info.multimesh_rid,mesh_info.floats);
  }
}

void MultiMeshManager::load_meshes() {
  for(auto &mesh_id : need_new_meshes) {
    v_meshes_iter mesh_it = v_meshes.find(mesh_id);
    if(mesh_it==v_meshes.end())
      // Should never get here; catalog_projectiles already added the meshinfo
      continue;
    load_mesh(mesh_it->second);
  }
}

void MultiMeshManager::warn_invalid_mesh(MeshInfo &mesh,const String &why) {
  FAST_PROFILING_FUNCTION;
  if(!mesh.invalid) {
    mesh.invalid=true;
    Godot::print_error(mesh.resource_path+String(": ")+why+String(" Projectile will be invisible."),__FUNCTION__,__FILE__,__LINE__);
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
    visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,0);
  }

  if(mesh_info.instance_count < count) {
    mesh_info.instance_count = count*1.3;
    visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,0);
  } else if(mesh_info.instance_count > count*2.6) {
    int new_count = max(static_cast<int>(count*1.3),8);
    if(new_count<mesh_info.instance_count) {
      mesh_info.instance_count = new_count;
      visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,0);
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
  for(auto &it : v_meshes)
    unused_multimesh(it.second);
}

void MultiMeshManager::unused_multimesh(MeshInfo &mesh_info) {
  FAST_PROFILING_FUNCTION;
  // No instances in this multimesh. Should we delete it?
  if(!mesh_info.visual_rid.is_valid() and !mesh_info.multimesh_rid.is_valid())
    return;
  
  if(v_frame > mesh_info.last_frame_used+1200) {
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
      visual_server->multimesh_allocate(mesh_info.multimesh_rid,mesh_info.instance_count,1,0,0);
    }
    if(mesh_info.visible_instance_count)
      visual_server->multimesh_set_visible_instances(mesh_info.multimesh_rid,0);
  }
  mesh_info.visible_instance_count=0;
}


void MultiMeshManager::pack_projectiles(const pair<instlocs_iterator,instlocs_iterator> &projectiles,
                                    PoolRealArray &floats,MeshInfo &mesh_info,real_t projectile_scale) {
  FAST_PROFILING_FUNCTION;
  // Change the float array so it is exactly as large as we need
  floats.resize(mesh_info.instance_count*12);
  int stop = mesh_info.instance_count*12;
  PoolRealArray::Write writer = floats.write();
  real_t *dataptr = writer.ptr();

  real_t scale_z = projectile_scale;
  
  // Fill in the transformations for the projectiles.
  int i=0;
  for(instlocs_iterator p_instance = projectiles.first;
      p_instance!=projectiles.second && i<stop;  p_instance++, i+=12) {
    MeshInstanceInfo &info = p_instance->second;
    real_t scale_x = info.scale_x ? info.scale_x : projectile_scale;
    float cos_ry=cosf(info.rotation_y);
    float sin_ry=sinf(info.rotation_y);
    dataptr[i + 0] = cos_ry*scale_x;
    dataptr[i + 1] = 0.0;
    dataptr[i + 2] = sin_ry*scale_z;
    dataptr[i + 3] = info.x;
    dataptr[i + 4] = 0.0;
    dataptr[i + 5] = 1.0;
    dataptr[i + 6] = 0.0;
    dataptr[i + 7] = PROJECTILE_HEIGHT;
    dataptr[i + 8] = -sin_ry*scale_x;
    dataptr[i + 9] = 0.0;
    dataptr[i + 10] = cos_ry*scale_z;
    dataptr[i + 11] = info.z;
  }
  
  // Use identity transforms for unused instances.
  for(;i<stop;i+=12) {
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
  }
}

void MultiMeshManager::update_content(VisibleContent &visible_content,
                                      const Vector3 &location,const Vector3 &size) {
  FAST_PROFILING_FUNCTION;

  instance_locations.clear();
  need_new_meshes.clear();
  
  real_t loc_min_x = min(location.x-size.x/2,location.x+size.x/2);
  real_t loc_max_x = max(location.x-size.x/2,location.x+size.x/2);
  real_t loc_min_y = min(location.z-size.z/2,location.z+size.z/2);
  real_t loc_max_y = max(location.z-size.z/2,location.z+size.z/2);

  for(auto &projectile : visible_content.projectiles) {
    object_id mesh_id = projectile.mesh_id;

    if(projectile.center.x-projectile.half_size.x > loc_max_x or
       projectile.center.x+projectile.half_size.x < loc_min_x or
       projectile.center.y-projectile.half_size.y > loc_max_y or
       projectile.center.y+projectile.half_size.y < loc_min_y)
      continue; // projectile is off-screen

    MeshInstanceInfo instance_info =
      { projectile.center.x, projectile.center.y, projectile.rotation_y, projectile.scale_x };
    instance_locations.emplace(mesh_id,instance_info);

    v_meshes_iter mit = v_meshes.find(mesh_id);
    if(mit==v_meshes.end()) {
      mesh_paths_iter pit = visible_content.mesh_paths.find(mesh_id);
      
      if(pit==visible_content.mesh_paths.end()) {
        // Should never get here. This means the physics thread
        // generated a projectile without sending its mesh resource path.
        pair<v_meshes_iter,bool> emplaced = v_meshes.emplace(mesh_id,MeshInfo(mesh_id,"(*unspecified resource*)"));
        warn_invalid_mesh(emplaced.first->second,"internal error: no mesh path sent from physics thread.");
        continue;
      }

      v_meshes.emplace(mesh_id,MeshInfo(mesh_id,pit->second));
      need_new_meshes.insert(mesh_id);
    }
  }
}


