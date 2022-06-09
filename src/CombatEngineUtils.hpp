#ifndef COMBATENGINEUTILS_HPP
#define COMBATENGINEUTILS_HPP

#include <assert.h>
#include <time.h>

#include <cstdint>
#include <cmath>
#include <algorithm>
#include <limits>
#include <memory>

#include <Vector3.hpp>
#include <Dictionary.hpp>
#include <RID.hpp>
#include <GodotGlobal.hpp>
#include <OS.hpp>
#include <PoolArrays.hpp>

#include "DVector3.hpp"
#include "CombatEngineData.hpp"
#include "FastProfilier.hpp"

namespace godot {

  template<class T>
  String str(const T &t) {
    return String(Variant(t));
  }
  
  template<class T>
  struct FreeRID {
    RID rid;

    FreeRID(const RID &rid): rid(rid) {}
    ~FreeRID() {
      if(rid.get_id())
        T::get_singleton()->free_rid(rid);
    }
  };

  typedef std::shared_ptr<FreeRID<VisualServer>> VisualRIDPtr;
  typedef std::shared_ptr<FreeRID<PhysicsServer>> PhysicsRIDPtr;

  inline VisualRIDPtr allocate_visual_rid(RID rid) {
    return std::shared_ptr<FreeRID<VisualServer>>(new FreeRID<VisualServer>(rid));
  }

  inline VisualRIDPtr allocate_physics_rid(RID rid) {
    return std::shared_ptr<FreeRID<VisualServer>>(new FreeRID<VisualServer>(rid));
  }
  
 
  namespace CE {
    
    static const Vector3 x_axis(1,0,0);
    static const Vector3 y_axis(0,1,0);
    static const Vector3 z_axis(0,0,1);

    inline object_id rid2id_default(const rid2id_t &rid2id,const RID &rid,object_id default_id=-1) {
      auto it = rid2id.find(rid.get_id());
      return (it==rid2id.end()) ? default_id : it->second;
    }
    
    inline object_id rid2id_default(const rid2id_t &rid2id,int32_t rid_id,object_id default_id=-1) {
      auto it = rid2id.find(rid_id);
      return (it==rid2id.end()) ? default_id : it->second;
    }
    
    template<class T>
    double acos_clamp(T value) {
      double result = acos(std::clamp(static_cast<double>(value),-1.0,1.0));
      assert(result>-9e9 && result<9e9);
    }

    template<class T>
    double asin_clamp(T value) {
      return asin(std::clamp(static_cast<double>(value),-1.0,1.0));
    }

    template<class T>
    inline T get(const Dictionary &dict,const char *key) {
      return static_cast<T>(dict[key]);
    }

    template<class T>
    inline T get(const Dictionary &dict,const char *key,const T &default_value) {
      if(dict.has(key))
        return static_cast<T>(dict[key]);
      else
        return default_value;
    }

    inline Vector3 unit_from_angle(real_t angle) {
      // x_axis.rotated(y_axis,angle)
      return Vector3(cosf(angle),0,-sinf(angle));
    }

    inline DVector3 unit_from_angle(double angle) {
      // x_axis.rotated(y_axis,angle)
      return DVector3(cos(angle),0,-sin(angle));
    }

    inline DVector3 unit_from_angle_d(double angle) {
      // x_axis.rotated(y_axis,angle)
      return DVector3(cos(angle),0,-sin(angle));
    }

    inline real_t angle_from_unit(Vector3 angle) {
      return atan2f(-angle.z,angle.x);
    }

    inline double angle_from_unit(DVector3 angle) {
      return atan2(-angle.z,angle.x);
    }

    inline double angle_from_unit_d(DVector3 angle) {
      return atan2(-angle.z,angle.x);
    }

    template<class T>
    Vector3 get_position(T &object) {
      return Vector3(object.position.x,0,object.position.z);
    }

    template<class T>
    DVector3 get_position_d(T &object) {
      return DVector3(object.position.x,0,object.position.z);
    }
    
    template<class T>
    Vector3 get_heading(T &object) {
      return unit_from_angle(object.rotation[1]);
    }
    
    template<class T>
    DVector3 get_heading_d(T &object) {
      return unit_from_angle_d(object.rotation[1]);
    }

    inline real_t lensq2(const Vector3 &a) {
      return a.x*a.x + a.z*a.z;
    }
    
    inline real_t dot2(const Vector3 &a, const Vector3 &b) {
      return a.x*b.x + a.z*b.z;
    }
    
    inline double dot2(const DVector3 &a, const DVector3 &b) {
      return a.x*b.x + a.z*b.z;
    }

    inline real_t cross2(const Vector3 &a, const Vector3 &b) {
      return a.z*b.x - a.x*b.z;
    }

    inline double cross2(const DVector3 &a, const DVector3 &b) {
      return a.z*b.x - a.x*b.z;
    }

    inline float angle2(const Vector3 &a, const Vector3 &b) {
      return atan2f(cross2(a,b),dot2(a,b));
    }

    inline double angle2(const DVector3 &a, const DVector3 &b) {
      return atan2(cross2(a,b),dot2(a,b));
    }
    
    inline real_t angle_diff(const Vector3 &a,const Vector3 &b) {
      return fmodf(atan2(b.x,-b.z)-atan2(a.x,-a.z),2*PI);
    }

    inline real_t distsq(const Vector3 &a,const Vector3 &b) {
      return (a.x-b.x)*(a.x-b.x) + (a.z-b.z)*(a.z-b.z);
    }

    inline real_t distance2(const Vector3 &a,const Vector3 &b) {
      return sqrtf(distsq(a,b));
    }

    inline real_t acos_clamp_dot(const Vector3 &a,const Vector3 &b) {
      return acosf(std::clamp(dot2(a,b),-1.0f,1.0f));
    }

    inline real_t asin_clamp_dot(const Vector3 &a,const Vector3 &b) {
      return asinf(std::clamp(dot2(a,b),-1.0f,1.0f));
    }

    inline double acos_clamp_dot(const DVector3 &a,const DVector3 &b) {
      return acosf(std::clamp(dot2(a,b),-1.0,1.0));
    }

    inline double asin_clamp_dot(const DVector3 &a,const DVector3 &b) {
      return asinf(std::clamp(dot2(a,b),-1.0,1.0));
    }
    
    inline uint32_t state_for_name(const String &name) {
      return name.hash();
    }
    
    template<class F,class C>
    object_id select_target(const typename C::key_type &start,const F &selection_function,
                            const C&container, bool first) {
      typename C::const_iterator start_p = container.find(start);
      typename C::const_iterator best = start_p;
      typename C::const_iterator next = best;
      
      if(start_p==container.end()) {
        next=container.begin();
      } else {
        next++;
      }

      real_t best_score = 0;

      typename C::const_iterator it=next;
      do {
        if(it==container.end())
          it=container.begin();
        else {
          real_t result = selection_function(it);
          if(result>best_score) {
            best_score=result;
            best=it;
            if(first)
              break;
          }
          it++;
        }
      } while(it!=next);

      return best==container.end() ? -1 : best->first;
    }

    class select_mask {
      const int mask;
    public:
      select_mask(int mask): mask(mask) {}
      select_mask(const select_mask &other): mask(other.mask) {}
      template<class I>
      inline real_t operator () (I iter) const {
        return iter->second.collision_layer & mask;
      }
    };

    class select_nearest {
      const Vector3 to;
      mutable real_t closest;
      const real_t max_range_squared;
    public:
      select_nearest(const Vector3 &to,real_t max_range = std::numeric_limits<real_t>::infinity()):
        to(to),
        closest(std::numeric_limits<real_t>::infinity()),
        max_range_squared(max_range*max_range)
      {}
      select_nearest(const select_nearest &other):
        to(other.to), closest(other.closest),
        max_range_squared(other.max_range_squared)
      {}
      template<class I>
      real_t operator () (I iter) const {
        real_t distance_squared = distsq(to,iter->second.position);
        if(distance_squared>max_range_squared)
          return 0;
        else
          return 1/(1+distance_squared);
      }
    };

    template<class A,class B>
    class select_two {
      const A one;
      const B two;
    public:
      select_two(const A &one,const B&two):
        one(one), two(two)
      {}
      select_two(const select_two &other):
        one(other.one), two(other.two)
      {}
      template<class I>
      real_t operator () (I iter) const {
        real_t result_one=one(iter);
        if(result_one) {
          real_t result_two=two(iter);
          if(result_two)
            return result_one+result_two;
        }
        return 0;
      }
    };
    
    template<class A,class B,class C>
    class select_three {
      const A one;
      const B two;
      const C three;
    public:
      select_three(const A &one,const B&two,const C&three):
        one(one), two(two), three(three)
      {}
      select_three(const select_three &other):
        one(other.one), two(other.two), three(other.three)
      {}
      template<class I>
      real_t operator () (I iter) const {
        real_t result_one=one(iter);
        if(result_one) {
          real_t result_two=two(iter);
          if(result_two) {
            real_t result_three=three(iter);
            if(result_three)
              return result_one+result_two+result_three;
          }
        }
        return 0;
      }
    };
  }
}

#endif
