#ifndef VISIBLECONTENT_HPP
#define VISIBLECONTENT_HPP

#include <vector>
#include <unordered_map>

#include <String.hpp>
#include <Vector2.hpp>
#include <Color.hpp>

#include "CE/Ship.hpp"
#include "CE/Planet.hpp"
#include "CE/MultiMeshManager.hpp"
#include "CE/Projectile.hpp"

namespace godot {
  namespace CE {
    struct MultiMeshInstanceEffect;
    class Projectile;
    class Asteroid;
    
    // A planet or ship to be displayed on the screen (minimap or main viewer)
    struct VisibleObject {
      const real_t x, z, radius, rotation_y, vx, vz, max_speed;
      int flags;
      VisibleObject(const Ship &,bool hostile);
      VisibleObject(const Planet &);
    };

    // Visual effect with full mesh instance data.
    struct InstanceEffect {
      const object_id mesh_id;
      Transform transform;
      Color color_data, instance_data;
    };
    
    // A projectile or passive visual effect:
    struct VisibleEffect {
      const real_t rotation_y, scale_x, scale_z, y;
      const Vector2 center;
      const Vector2 half_size;
      const Color data;
      const object_id mesh_id;
      VisibleEffect(const MultiMeshInstanceEffect &);
      VisibleEffect(const Projectile &);
    };
  
    typedef std::vector<VisibleEffect>::iterator visible_effects_iter;
    typedef std::vector<VisibleEffect>::const_iterator visible_effects_citer;

    typedef std::unordered_map<object_id,String>::iterator mesh_paths_iter;
    typedef std::unordered_map<object_id,object_id>::iterator preloaded_meshes_iter;
    typedef std::unordered_map<object_id,VisibleObject> ships_and_planets_t;
    typedef ships_and_planets_t::iterator ships_and_planets_iter;
    typedef ships_and_planets_t::const_iterator ships_and_planets_citer;
  
    struct VisibleContent {
      // The output of the physics timestep from CombatEngine, to be
      // processed in the visual timestep.  This is placed in a
      // thread-safe linked list.  It is the only means by which the
      // physics and visual threads communicate in GDNative.
      ships_and_planets_t ships_and_planets;
      std::vector<VisibleEffect> effects;
      std::unordered_map<object_id,String> mesh_paths;
      std::vector<InstanceEffect> instances;
      //std::unordered_map<object_id,object_id> preloaded_meshes;
      VisibleContent *next;
      VisibleContent();
      ~VisibleContent();
    };

    class VisibleContentManager {
      VisibleContent *volatile new_content; // content being prepared by combat engine
      VisibleContent *visible_content; // content presently on screen
    public:
      VisibleContentManager();
      ~VisibleContentManager();
      void clear();
      VisibleContent *push_content(VisibleContent *next);

      std::pair<bool,VisibleContent*> update_visible_content();

      inline VisibleContent * get_new_content() {
        return new_content;
      }
      inline const VisibleContent * get_new_content() const {
        return new_content;
      }

      inline VisibleContent * get_visible_content() {
        return visible_content;
      }
      inline const VisibleContent * get_visible_content() const {
        return visible_content;
      }
      
    };
  }
}
#endif
