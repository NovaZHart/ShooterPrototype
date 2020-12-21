#ifndef COMBATENGINEUTILS_HPP
#define COMBATENGINEUTILS_HPP

#include <assert.h>

#include <cstdint>
#include <cmath>
#include <algorithm>

#include <Vector3.hpp>
#include <Dictionary.hpp>
#include <RID.hpp>
#include <GodotGlobal.hpp>
#include <OS.hpp>

#include "DVector3.hpp"
#include "CombatEngineData.hpp"

#define ENABLE_PROFILING

namespace godot {

  class FastProfiling {
    char *signature;
    uint64_t ticks;
  public:
    FastProfiling(const char *p_function, const int p_line, char *&sig):
      signature(sig ? sig : sig=sign(p_function,p_line)),
      ticks(OS::get_singleton()->get_ticks_usec())
    {}
    ~FastProfiling() {
      uint64_t t = OS::get_singleton()->get_ticks_usec() - ticks;
      if (t > 0) {
        Godot::gdnative_profiling_add_data(signature, t);
      }
    }
  private:
    static char *sign(const char *p_function, const int p_line) {
      char *signature=new char[300];
      snprintf(signature, 300, "::%d::%s", p_line, p_function);
      return signature;
    }
  };

#ifdef ENABLE_PROFILING
#define FAST_PROFILING_FUNCTION     \
  static char *__function_profiling_sig = nullptr ;  \
  FastProfiling __function_profiling_prof(__FUNCTION__, __LINE__, __function_profiling_sig )
#else
#define FAST_PROFILING_FUNCTION
#endif

  
  namespace CE {
    static const Vector3 x_axis(1,0,0);
    static const Vector3 y_axis(0,1,0);
    static const Vector3 z_axis(0,0,1);

    inline double double_dot(const Vector3 &a,const Vector3 &b) {
      return double(a.x)*double(b.x)+double(a.y)*double(b.y)+double(a.z)*double(b.z);
    }

    inline double acos_clamp_dot(const Vector3 &a,const Vector3 &b) {
      return acos(std::clamp(double_dot(a,b),-1.0,1.0));
    }

    inline double asin_clamp_dot(const Vector3 &a,const Vector3 &b) {
      return asin(std::clamp(double_dot(a,b),-1.0,1.0));
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

    inline DVector3 unit_from_angle_d(double angle) {
      // x_axis.rotated(y_axis,angle)
      return DVector3(cos(angle),0,-sin(angle));
    }
    
    template<class T>
    Vector3 get_heading(T &object) {
      return unit_from_angle(object.rotation[1]);
    }
    
    template<class T>
    DVector3 get_heading_d(T &object) {
      return unit_from_angle(object.rotation[1]);
    }

    inline real_t lensq2(const Vector3 &a) {
      return a.x*a.x + a.z*a.z;
    }
    
    inline real_t dot2(const Vector3 &a, const Vector3 &b) {
      return a.x*b.x + a.z*b.z;
    }

    inline real_t cross2(const Vector3 &a, const Vector3 &b) {
      return a.z*b.x - a.x*b.z;
    }

    inline real_t angle_diff(const Vector3 &a,const Vector3 &b) {
      return atan2(b.x,-b.z)-atan2(a.x,-a.z);
    }

    inline real_t distsq(const Vector3 &a,const Vector3 &b) {
      return (a.x-b.x)*(a.x-b.x) + (a.z-b.z)*(a.z-b.z);
    }
    
    // from https://burtleburtle.net/bob/hash/integer.html
    uint32_t bob_full_avalanche(uint32_t a);


    inline real_t int2float(uint32_t i) {
      return real_t(i%1048576)/1048576.0f;
    }
    
    inline uint32_t state_for_name(const String &name) {
      return name.hash();
    }

    template<bool FIRST,class F,class C>
    CE::object_id select_target(const typename C::key_type &start,const F &selection_function,
                                const C&container) {
      typename C::const_iterator start_p = container.find(start);
      CE::object_id selection = (start_p==container.end()) ? -1 : start_p->second.id;
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
      int mask;
    public:
      select_mask(int mask);
      template<class I>
      inline bool operator () (I iter) const {
        return iter->second.collision_layer & mask;
      }
    };

    class select_nearest {
      Vector3 to;
      mutable real_t closest;
    public:
      select_nearest(const Vector3 &to);
      template<class I>
      bool operator () (I iter) const {
        real_t distance = to.distance_to(iter->second.position);
        if(distance<closest) {
          closest=distance;
          return true;
        }
        return false;
      }
    };

    template<class A,class B>
    class select_two {
      A one;
      B two;
    public:
      select_two(const A &one,const B&two):
        one(one), two(two)
      {}
      template<class I>
      bool operator () (I iter) const {
        return one(iter) && two(iter);
      }
    };
    
    template<class A,class B,class C>
    class select_three {
      A one;
      B two;
      C three;
    public:
      select_three(const A &one,const B&two,const C&three):
        one(one), two(two), three(three)
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
