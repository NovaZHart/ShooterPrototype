#ifndef MULTIMESHMANAGER_HPP
#define MULTIMESHMANAGER_HPP

#include <unordered_set>
#include <unordered_map>
#include <vector>
#include <algorithm>
#include <utility>

#include <Godot.hpp>

#include <Color.hpp>
#include <Vector2.hpp>
#include <Vector3.hpp>
#include <String.hpp>
#include <Area.hpp>
#include <RID.hpp>
#include <Dictionary.hpp>
#include <Array.hpp>
#include <PhysicsDirectSpaceState.hpp>
#include <Ref.hpp>
#include <VisualServer.hpp>
#include <ResourceLoader.hpp>
#include <CylinderShape.hpp>
#include <PhysicsServer.hpp>
#include <PhysicsDirectSpaceState.hpp>
#include <Resource.hpp>
#include <AABB.hpp>
#include <Transform.hpp>
#include <PoolArrays.hpp>
#include <Mesh.hpp>

#include "CE/ObjectIdGenerator.hpp"
#include "CE/InstanceEffect.hpp"
#include "hash_functions.hpp"

namespace godot {
  namespace CE {
    struct VisibleContent;
    struct InstanceEffect;
    
    // Any Mesh from projectiles that may be in a multimesh
    struct MeshInfo {
      const object_id id;
      const String resource_path;
      Ref<Resource> mesh_resource;
      Ref<Mesh> preloaded_mesh;
      RID mesh_rid, multimesh_rid, visual_rid;
      int instance_count, visible_instance_count, last_frame_used;
      bool invalid;
      PoolRealArray floats;
      Transform visual_instance_transform;
      MeshInfo(object_id,const String &);
      MeshInfo(object_id,Ref<Mesh> mesh_ref);
      ~MeshInfo();
    };

  
    // Tracks info about all projectiles that may end up as multimesh instances:
    struct MeshInstanceInfo {
      const real_t x, y, z, rotation_y, scale_x, scale_z;
      const Color data;
    };
    typedef std::unordered_multimap<object_id,MeshInstanceInfo> instance_locations_t;
    typedef std::unordered_multimap<object_id,MeshInstanceInfo>::iterator instlocs_iterator;

    typedef std::unordered_multimap<object_id,InstanceEffect> instance_effects_t;
    typedef std::unordered_multimap<object_id,InstanceEffect>::iterator insteff_iterator;

    typedef std::unordered_map<String,object_id> path2mesh_t;
    typedef std::unordered_map<object_id,String> mesh2path_t;

    class MultiMeshManager {
    public:
      typedef std::unordered_map<object_id,MeshInfo>::iterator v_meshes_iter;
      typedef std::unordered_map<object_id,MeshInfo>::iterator v_meshes_citer;
      typedef std::unordered_map<object_id,String>::iterator mesh2path_iter;
      typedef std::unordered_map<object_id,String>::const_iterator mesh2path_citer;
    private:
      ObjectIdGenerator idgen;
      int v_frame;
      VisualServer *visual_server;
      std::unordered_map<object_id,MeshInfo> v_meshes;

      // FIXME: these two should not have v_
      std::unordered_map<Ref<Mesh>,object_id> v_meshref2id;
      std::unordered_map<object_id,Ref<Mesh>> v_id2meshref;

      std::unordered_map<String,object_id> v_path2id;
      std::unordered_set<String> v_invalid_paths;
      std::unordered_map<String,object_id> path2mesh;
      std::unordered_map<object_id,String> mesh2path;
      ResourceLoader *loader;
      std::unordered_map<object_id,Transform> requested_transforms;
   
      // For temporary use in some functions:
      instance_locations_t instance_locations;
      instance_effects_t instance_effects;
      std::unordered_set<object_id> need_new_meshes;
    public:
      // These must be called at a time when neither the physics thread
      // nor visual thread are doing anything else:
      MultiMeshManager();
      ~MultiMeshManager();

      // Forbid copying:
      MultiMeshManager(const MultiMeshManager &) = delete;
      MultiMeshManager &operator = (const MultiMeshManager &) = delete;

      // These must be called from the physics thread:
      object_id add_mesh(const String &path);
      inline bool has_mesh(object_id id) {
        return mesh2path.find(id)!=mesh2path.end();
      }
      inline const String &get_mesh_path(object_id id) {
        return mesh2path[id];
      }
      // inline std::unordered_map<object_id,String>::const_iterator find_mesh_name(object_id id) const {
      //   return mesh2path.find(id);
      // }
      // inline std::unordered_map<object_id,String>::const_iterator mesh_name_end(object_id id) const {
      //   return mesh2path.end();
      // }

      inline void set_mesh_transform(object_id id,const Transform &trans) {
        requested_transforms.emplace(id,trans);
      }

      object_id add_preloaded_mesh(Ref<Mesh> mesh);
      inline bool has_mesh(Ref<Mesh> mesh) const {
        return v_meshref2id.find(mesh) != v_meshref2id.end();
      }
      inline object_id get_preloaded_mesh_id(Ref<Mesh> mesh) const {
        std::unordered_map<Ref<Mesh>,object_id>::const_iterator it=v_meshref2id.find(mesh);
        return (it==v_meshref2id.end()) ? -1 : it->second;
      }

      // All of these must be called from the visual thread:
      void time_passed(real_t delta);
      void send_meshes_to_visual_server(real_t projectile_scale,RID scenario,bool reset_scenario,bool loud=false);
      void load_meshes();
      void clear_all_multimeshes();
      void update_content(VisibleContent &visible_content,const Vector3 &location,const Vector3 &size);

    private:

      void warn_invalid_mesh(MeshInfo &mesh,const String &why);
      bool allocate_multimesh(MeshInfo &mesh_info,int count);
      bool load_mesh(MeshInfo &mesh_info);
      bool update_visual_instance(MeshInfo &mesh_info,RID scenaro,bool reset_scenario);
      void unused_multimesh(MeshInfo &mesh_info,bool force);
      void pack_visuals(const std::pair<instlocs_iterator,instlocs_iterator> &projectiles,
                        const std::pair<insteff_iterator,insteff_iterator> &effects,
                        PoolRealArray &floats,MeshInfo &mesh_info,real_t projectile_scale);
      void pack_instance_locations(const std::pair<instlocs_iterator,instlocs_iterator> &projectiles,
                                   PoolRealArray &floats,MeshInfo &mesh_info,real_t projectile_scale);
      void pack_instance_effects(const std::pair<insteff_iterator,insteff_iterator> &effects,
                                 PoolRealArray &floats,MeshInfo &mesh_info,real_t projectile_scale);
      void add_instance_mesh_id(VisibleContent &visible_content,object_id mesh_id);
    };
  }
}

#endif
