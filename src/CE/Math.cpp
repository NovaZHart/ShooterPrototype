#include "CE/Math.hpp"

#include "FastProfilier.hpp"

namespace godot {
  namespace CE {

    using namespace std;
    double rendezvous_time(Vector3 target_location,Vector3 target_velocity,
                           double interception_speed) {
      FAST_PROFILING_FUNCTION;
      double a = dot2(target_velocity,target_velocity) - interception_speed*interception_speed;
      double b = 2.0 * dot2(target_location,target_velocity);
      double c = dot2(target_location,target_location);
      double descriminant = b*b - 4*a*c;

      if(fabs(a)<1e-5)
        return -c/b;

      if(descriminant<0)
        return NAN;

      descriminant = sqrt(descriminant);
        
      double d1 = (-b + descriminant)/(2.0*a);
      double d2 = (-b - descriminant)/(2.0*a);
      double mn = min(d1,d2);
      double mx = max(d1,d2);

      if(mn>=0)
        return mn;
      else if(mx>=0)
        return mx;
      return NAN;
    }

    pair<DVector3,double> plot_collision_course(DVector3 relative_position,DVector3 target_velocity,double max_speed) {
      FAST_PROFILING_FUNCTION;
      // Returns desired velocity vector and time to collision.
      double target_speed = target_velocity.length();
      DVector3 relative_heading = relative_position.normalized();     // VrHat

      if(target_speed>max_speed)
        // Special case: cannot catch up to target. Instead, fly towards it.
        return pair<DVector3,double>(relative_heading*max_speed,NAN);
  
      double sina = cross2(relative_heading,target_velocity)/max_speed; // (VrHat x V0Hat) * v0Hat/vg
      double relative_angle = asin_clamp(sina);
      double distance = relative_position.length();
      double start_angle = angle_from_unit(relative_heading);         // angle of VrHat
      DVector3 course = unit_from_angle_d(start_angle+relative_angle)*max_speed;
      DVector3 relative_course = course-target_velocity;
      double relative_speed = max(0.01,relative_course.length());
  
      return pair<DVector3,double>(course,distance/relative_speed);
    }

  }
}
