#ifndef CELESTIALOBJECT_HPP
#define CELESTIALOBJECT_HPP

#include <limits>
#include <vector>
#include "CE/ObjectIdGenerator.hpp"
#include "PropertyMacros.hpp"

namespace godot {
  namespace CE {
    class Ship;
    class Projectile;
    class Asteroid;
    class Planet;

    struct CelestialHit;
    struct CelestialIdHit;

    /********************************************************************/

    struct CelestialInfo {
      object_id id;
      Vector3 xyz;
      real_t radius;
    };
    /********************************************************************/

    class CelestialObject {
    public:
      enum Type {
        NOTHING=0,
        SHIP=1,
        PROJECTILE=2,
        PLANET=3,
        ASTEROID=4
      };
    private:
      const Type type;

    public:

      inline Type get_type() const { return type; }
      
      inline bool is_nothing() const { return type==NOTHING; }
      inline bool is_ship() const { return type==SHIP; }
      inline bool is_projectile() const { return type==PROJECTILE; }
      inline bool is_planet() const { return type==PLANET; }
      inline bool is_asteroid() const { return type==ASTEROID; }
      
      inline CelestialObject(Type type): type(type) {}

      virtual void get_object_info(CelestialInfo &info) const = 0;
      virtual object_id get_object_id() const = 0;
      virtual real_t get_object_radius() const = 0;
      virtual Vector3 get_object_xyz() const = 0;
      virtual Vector2 get_object_xz() const = 0;

      // Allow as_classname() to cast to references or pointers of known subtypes.
      // Use a macro, not a template, to ensure only certain types are allowed.
#define DEF_CAST_THIS(ClassName,function_name) \
      inline const ClassName &function_name () const { \
        return reinterpret_cast<const ClassName &>(*this); \
      } \
      inline ClassName &function_name () { \
        return reinterpret_cast<ClassName &>(*this); \
      } \
      inline const ClassName *function_name##_ptr () const { \
        return reinterpret_cast<const ClassName *>(this); \
      } \
      inline ClassName *function_name##_ptr () { \
        return reinterpret_cast<ClassName *>(this); \
      }

      // List of allowed classes and corresponding method name.
      DEF_CAST_THIS(Ship,as_ship);
      DEF_CAST_THIS(Projectile,as_projectile);
      DEF_CAST_THIS(Planet,as_planet);
      DEF_CAST_THIS(Asteroid,as_asteroid);
#undef DEF_CAST_THIS

    protected:
      // Ensure a CelestialObject can never be destructed. Most of the
      // instances are stored statically, so destructing a superclass
      // pointer will just crash the game.
      inline ~CelestialObject() {}
    };

    /********************************************************************/
    
    struct CelestialHit {
      CelestialObject *hit;
      Vector2 xz;
      real_t distance;
      CelestialHit():
        hit(nullptr), xz(), distance(std::numeric_limits<real_t>::infinity())
      {}
      CelestialHit(CelestialObject *hit,Vector2 xz,real_t distance):
        hit(hit),xz(xz),distance(distance)
      {}
      template<class T> CelestialHit(const CelestialIdHit &id_hit,const T &&container,Vector2 center);
      template<class T> CelestialHit(const CelestialIdHit &id_hit,const T &&container);

      // Methods expected by utility functions:
      inline Vector3 get_position() const {
        return get_x0z();
      }
      inline Vector2 get_xz() const {
        return xz;
      }
      inline Vector3 get_x0z() const {
        return Vector3(xz.x,0,xz.y);
      }
      inline Vector3 get_xyz() const {
        return get_x0z();
      }

      inline bool operator < (const CelestialHit &ce) const {
        return distance<ce.distance;
      }
      inline bool operator == (const CelestialHit &ce) const {
        return hit==ce.hit && xz==ce.xz && distance==ce.distance;
      }
    };

    /********************************************************************/

    struct CelestialIdHit {
      object_id hit;
      Vector2 xz;
      real_t distance;
      CelestialObject::Type type;
      
      CelestialIdHit():
        hit(-1), xz(), distance(std::numeric_limits<real_t>::infinity()),
        type(CelestialObject::NOTHING)
      {}
      CelestialIdHit(CelestialObject *hit,Vector2 xz,real_t distance):
        hit(hit ? hit->get_object_id() : -1),xz(xz),distance(distance),
        type(hit ? hit->get_type() : CelestialObject::NOTHING)
      {}
      CelestialIdHit(object_id hit,Vector2 xz,real_t distance,
                            CelestialObject::Type type):
        hit(hit),xz(xz),distance(distance),type(type)
      {}
      CelestialIdHit(const CelestialHit &ce):
        hit(ce.hit ? ce.hit->get_object_id() : -1), xz(ce.xz), distance(ce.distance),
        type(ce.hit ? ce.hit->get_type() : CelestialObject::NOTHING)
      {}

      // Methods expected by utility functions:
      inline Vector3 get_position() const {
        return get_x0z();
      }
      inline Vector2 get_xz() const {
        return xz;
      }
      inline Vector3 get_x0z() const {
        return Vector3(xz.x,0,xz.y);
      }
      inline Vector3 get_xyz() const {
        return get_x0z();
      }

      inline bool operator < (const CelestialIdHit &ce) const {
        return distance<ce.distance;
      }
      inline bool operator == (const CelestialIdHit &ce) const {
        return hit==ce.hit && xz==ce.xz && distance==ce.distance;
      }
    };

    /********************************************************************/

    // Find the id in the container and make a CelestialHit out of it.
    // If the id is not found, hit is nullptr.
    // If found, update the location and distance to center.
    template<class T>
    CelestialHit::CelestialHit(const CelestialIdHit &id_hit,const T &&container,Vector2 center) {
      auto found = container.find(id_hit.hit);
      if(found==container.end()) {
        hit=nullptr;
        xz=id_hit.xz;
        distance = id_hit.distance;
      } else {
        hit=&found->second;
        xz=found->get_xz();
        distance = xz.distance_to(center);
      }
    }

    // Find the id in the container and make a CelestialHit out of it.
    // If the id is not found, hit is nullptr.
    // Regardless, the xz and distance will be unchanged.
    template<class T>
    CelestialHit::CelestialHit(const CelestialIdHit &id_hit,const T &&container):
      xz(id_hit.xz), distance(id_hit.distance)
    {
      auto found = container.find(id_hit.hit);
      hit = found!=container.end() ? &found->second : nullptr;
    }

    typedef std::vector<CelestialHit> hit_list_t;
    typedef hit_list_t::iterator hit_list_iter;
    typedef hit_list_t::const_iterator hit_list_const_iter;

    typedef std::vector<CelestialIdHit> hit_id_list_t;
    typedef hit_id_list_t::iterator hit_id_list_iter;
    typedef hit_id_list_t::const_iterator hit_id_list_const_iter;

    template<class T>
    void hit_list_append_from_id(const hit_id_list_t &id_list,hit_list_t &ptr_list,const T &&container, Vector2 center) {
      for(auto &id_hit : id_list)
        ptr_list.emplace_back(id_hit,container,center);
    }

    template<class T>
    void hit_list_append_from_id(const hit_id_list_t &id_list,hit_list_t &ptr_list,const T &&container) {
      for(auto &id_hit : id_list)
        ptr_list.emplace_back(id_hit,container);
    }
  }
}

#endif
