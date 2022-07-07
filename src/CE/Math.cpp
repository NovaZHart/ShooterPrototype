#include "CE/Math.hpp"

#include "FastProfilier.hpp"

namespace godot {
  namespace CE {
    // Intersection of a circle at the origin and a circle not at the origin.
    // Return value is yes/no: is there an intersection?
    // Point1 & point2 are the points of intersection if return value is true
    // Arc of circle 1 that resides in circle 2 is point1..point2
    bool circle_intersection(real_t radius1,Vector2 center2, real_t radius2,
                             Vector2 &point1, Vector2 &point2) {
      real_t len = center2.length();

      if(len+radius2<radius1)
        return false; // circle2 entirely within circle1
      else if(len-radius2>radius1)
        return false; // circle2 entirely outside circle1
      else if(!len)
        return false; // circle1 == circle2
      
      Vector2 norm = center2/len;
      real_t x = (radius1*radius1-radius2*radius2+len*len)/(2*len);
      real_t x2 = radius1*radius1-x;
      if(x2<=0)
        return false;
      real_t y = sqrtf(x2);

      Vector2 p1(x*norm.x-y*norm.y, x*norm.y+y*norm.x);
      Vector2 p2(x*norm.x+y*norm.y, x*norm.y-y*norm.x);

      Vector2 connect = p2-p1;
      if(connect.cross(center2)<0) {
        point2=p1;
        point1=p2;
      } else {
        point1=p1;
        point2=p2;
      }
    }

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
