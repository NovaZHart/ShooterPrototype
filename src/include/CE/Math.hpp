#ifndef MATH_HPP
#define MATH_HPP

#include <cmath>
#include <algorithm>

#include "Vector3.hpp"
#include "DVector3.hpp"
#include "CE/Constants.hpp"

namespace godot {
  namespace CE {
    
    static const Vector3 x_axis(1,0,0);
    static const Vector3 y_axis(0,1,0);
    static const Vector3 z_axis(0,0,1);

    double rendezvous_time(Vector3 target_location,Vector3 target_velocity,
                           double interception_speed);

    std::pair<DVector3,double> plot_collision_course(DVector3 relative_position,DVector3 target_velocity,double max_speed);
    
    template<class T>
    double acos_clamp(T value) {
      return acos(std::clamp(static_cast<double>(value),-1.0,1.0));
    }

    template<class T>
    double asin_clamp(T value) {
      return asin(std::clamp(static_cast<double>(value),-1.0,1.0));
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
      Vector3 pos = object.get_position();
      return Vector3(pos.x,0,pos.z);
    }

    template<class T>
    DVector3 get_position_d(T &object) {
      DVector3 pos = object.get_position();
      return DVector3(pos.x,0,pos.z);
    }
    
    template<class T>
    Vector3 get_heading(T &object) {
      return unit_from_angle(object.get_rotation()[1]);
    }
    
    template<class T>
    DVector3 get_heading_d(T &object) {
      return unit_from_angle_d(object.get_rotation()[1]);
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
  
    inline real_t time_of_closest_approach(Vector3 dp,Vector3 dv) {
      real_t dv2 = dot2(dv,dv);
      return (dv2<1e-9) ? 0.0f : std::max(dot2(dp,dv)/dv2,0.0f);
    }
  }
}

#endif
