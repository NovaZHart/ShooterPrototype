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

#include "hash_String.hpp"
#include "ObjectIdGenerator.hpp"

namespace godot {
  namespace CE {
    // From CombatEngineData.hpp
    class Ship;
    class Planet;
    class Projectile;
  }
  struct ProjectileMesh;
  struct MeshInfo;
  struct MeshInstanceInfo;
  struct VisibleObject;
  struct VisibleProjectile;
  struct VisibleContent;

  struct ProjectileMesh {
    object_id id;
    RID mesh_id;

    bool has_multimesh;
    RID multimesh_id;
    int instance_count, visible_instance_count;

    ProjectileMesh(RID, object_id);
    ~ProjectileMesh();
  };
    

  // Any Mesh from projectiles that may be in a multimesh
  struct MeshInfo {
    const object_id id;
    const String resource_path;
    Ref<Resource> mesh_resource;
    RID mesh_rid, multimesh_rid, visual_rid;
    int instance_count, visible_instance_count, last_frame_used;
    bool invalid;
    PoolRealArray floats;
    MeshInfo(object_id,const String &);
    ~MeshInfo();
  };

  
  // Tracks info about all projectiles that may end up as multimesh instances:
  struct MeshInstanceInfo {
    const real_t x, z, rotation_y, scale_x;
  };
  typedef std::unordered_multimap<object_id,MeshInstanceInfo> instance_locations_t;
  typedef std::unordered_multimap<object_id,MeshInstanceInfo>::iterator instlocs_iterator;

  // A planet or ship to be displayed on the screen (minimap or main viewer)
  struct VisibleObject {
    const real_t x, z, radius, rotation_y, vx, vz, max_speed;
    int flags;
    VisibleObject(const CE::Ship &,bool hostile);
    VisibleObject(const CE::Planet &);
  };

  // A projectile to be displayed on-screen (minimap or main viewer)
  struct VisibleProjectile {
    const real_t rotation_y, scale_x;
    const Vector2 center, half_size;
    const int type;
    const object_id mesh_id;
    VisibleProjectile(const CE::Projectile &);
  };
  typedef std::vector<VisibleProjectile>::iterator visible_projectiles_iter;

  typedef std::unordered_map<object_id,String>::iterator mesh_paths_iter;
  typedef std::unordered_map<object_id,VisibleObject> ships_and_planets_t;
  typedef ships_and_planets_t::iterator ships_and_planets_iter;
  typedef ships_and_planets_t::const_iterator ships_and_planets_citer;
    
  // The output of the physics timestep from CombatEngine, to be
  // processed in the visual timestep.  This is placed in a
  // thread-safe linked list.  It is the only means by which the
  // physics and visual threads communicate in GDNative.
  struct VisibleContent {
    ships_and_planets_t ships_and_planets;
    std::vector<VisibleProjectile> projectiles;
    std::unordered_map<object_id,String> mesh_paths;
    VisibleContent *next;
    VisibleContent();
    ~VisibleContent();
  };

  typedef std::unordered_map<String,object_id,hash_String> path2mesh_t;
  typedef std::unordered_map<object_id,String> mesh2path_t;

  class MultiMeshManager {
  public:
    typedef std::unordered_map<object_id,MeshInfo>::iterator v_meshes_iter;
  private:
    ObjectIdGenerator idgen;
    int v_frame;
    VisualServer *visual_server;
    std::unordered_map<object_id,MeshInfo> v_meshes;
    std::unordered_map<String,object_id,hash_String> v_path2id;
    std::unordered_set<String,hash_String> v_invalid_paths;
    std::unordered_map<String,object_id,hash_String> path2mesh;
    std::unordered_map<object_id,String> mesh2path;
    ResourceLoader *loader;
   
    // For temporary use in some functions:
    instance_locations_t instance_locations;
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

    // All of these must be called from the visual thread:
    void time_passed(real_t delta);
    void send_meshes_to_visual_server(real_t projectile_scale,RID scenario,bool reset_scenario);
    void load_meshes();
    void clear_all_multimeshes();
    void update_content(VisibleContent &visible_content,const Vector3 &location,const Vector3 &size);

  private:

    void warn_invalid_mesh(MeshInfo &mesh,const String &why);
    bool allocate_multimesh(MeshInfo &mesh_info,int count);
    bool load_mesh(MeshInfo &mesh_info);
    bool update_visual_instance(MeshInfo &mesh_info,RID scenaro,bool reset_scenario);
    void unused_multimesh(MeshInfo &mesh_info);
    void pack_projectiles(const std::pair<instlocs_iterator,instlocs_iterator> &projectiles,
                          PoolRealArray &floats,MeshInfo &mesh_info,real_t projectile_scale);
  };
}

#endif
