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

#define ENABLE_PROFILING

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
  
  class FastProfiling {
    const char *function;
    int line;
    char *sig;
    uint64_t ticks;
  public:
    explicit FastProfiling(const char *p_function, const int p_line, char *sig):
      function(p_function),line(p_line),sig(sig)
    {
      //      signature = sign(p_function,p_line,sig);
      ticks = tick();
    }
    ~FastProfiling() {
      uint64_t t = tick() - ticks;
      if(t>10) {
        if(sig[0]!=':')
          snprintf(sig, 1024, "::%d::%s", line, function);
        Godot::gdnative_profiling_add_data(sig, t);
      }
    }
  private:
    static uint64_t tick() {
      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC_RAW,&ts);
      return ((uint64_t)ts.tv_nsec / 1000L) + (uint64_t)ts.tv_sec * 1000000L;
    }
  };

#ifdef ENABLE_PROFILING
#define FAST_PROFILING_FUNCTION static char __function_profiling_sig[1024] = {'\0'} ; FastProfiling __function_profiling_prof(__func__, __LINE__, __function_profiling_sig )
#else
#define FAST_PROFILING_FUNCTION
#endif

  
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
    
    template<bool FIRST,class F,class C>
    object_id select_target(const typename C::key_type &start,const F &selection_function,
                                const C&container) {
      typename C::const_iterator start_p = container.find(start);
      object_id selection = (start_p==container.end()) ? -1 : start_p->second.id;
      typename C::const_iterator next = start_p;
      if(start_p==container.end()) {
        next=container.begin();
      } else {
        next++;
      }

      for(typename C::const_iterator it=next;it!=container.end();it++)
        if(selection_function(it)) {
          selection=it->first;
          if(FIRST) {
            return selection;
          }
        }
      for(typename C::const_iterator it=container.begin();it!=next;it++)
        if(selection_function(it)) {
          selection=it->first;
          if(FIRST) {
            return selection;
          }
        }
      return selection;
    }

    class select_mask {
      const int mask;
    public:
      select_mask(int mask): mask(mask) {}
      select_mask(const select_mask &other): mask(other.mask) {}
      template<class I>
      inline bool operator () (I iter) const {
        return iter->second.collision_layer & mask;
      }
    };

    class select_nearest {
      const Vector3 to;
      mutable real_t closest;
      const real_t max_range;
    public:
      select_nearest(const Vector3 &to,real_t max_range = std::numeric_limits<real_t>::infinity()):
        to(to),
        closest(std::numeric_limits<real_t>::infinity()),
        max_range(max_range)
      {}
      select_nearest(const select_nearest &other):
        to(other.to), closest(other.closest), max_range(other.max_range)
      {}
      template<class I>
      bool operator () (I iter) const {
        real_t distance = to.distance_to(iter->second.position);
        if(distance>max_range)
          return false;
        if(distance<closest) {
          closest=distance;
          return true;
        }
        return false;
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
      bool operator () (I iter) const {
        return one(iter) && two(iter);
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
      bool operator () (I iter) const {
        return one(iter) && two(iter) && three(iter);
      }
    };
    
    // class select_nearest_mask {
    //   select_nearest nearest;
    //   select_mask mask;
    // public:
    //   select_nearest_mask(const Vector3 &to,int mask);
    //   template<class I>
    //   inline bool operator () (I iter) const {
    //     return mask(iter) && nearest(iter);
    //   }
    // };
  }
}

#endif
