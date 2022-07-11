#include <algorithm>

#include "CE/Math.hpp"

#include "FastProfilier.hpp"

namespace godot {
  namespace CE {

    // Intersection of a circle at the origin and a line segment
    // Returns the number of points of intersection.
    // Input: radius is the radius of the circle (center is the origin)
    // Input: line[2] has two points on the line.
    // Output: intersection[2] will receive the zero, one, or two points of intersection
    int line_segment_intersect_circle(real_t radius,const Vector2 line[2],Vector2 intersection[2]) {
      Vector2 d = line[1]-line[0];
      real_t dr2=d.length_squared();
      real_t dr = sqrtf(dr2);
      Vector2 dn = dr ? d/dr : d;
      
      real_t dcross=line[0].cross(line[1]);
      real_t Q2 = radius*radius*dr2-dcross*dcross;
      if(Q2<0)
        return 0;

      real_t x0=dcross*d.y, y0=-dcross*d.x;
      
      if(Q2==0) {
        intersection[0].x=x0/dr2;
        intersection[0].y=y0/dr2;
        real_t along = intersection[0].dot(dn);
        return (along>=0 and along<=dr) ? 1 : 0;
      }

      real_t Q=sqrtf(Q2);
      real_t xp=d.x*Q*(d.y<0 ? -1 : 1);
      real_t yp=fabsf(d.y)*Q;

      Vector2 p0((x0+xp)/dr2,(y0+yp)/dr2);
      Vector2 p1((x0-xp)/dr2,(y0-yp)/dr2);

      int count=0;
      real_t along0 = p0.dot(dn);
      if(along0>=0 and along0<=dr)
        intersection[count++] = p0;
      real_t along1 = p1.dot(dn);
      if(along1>=0 and along1<=dr)
        intersection[count++] = p1;

      if(count==2 and along1<along0)
        std::swap(intersection[0],intersection[1]);
      
      return count;
    }

    // Intersection of a circle at the origin and a line.
    // Returns the number of points of intersection.
    // Input: radius is the radius of the circle (center is the origin)
    // Input: line[2] has two points on the line.
    // Output: intersection[2] will receive the zero, one, or two points of intersection
    int line_intersect_circle(real_t radius,const Vector2 line[2],Vector2 intersection[2]) {
      Vector2 d = line[1]-line[0];
      real_t dr2=d.length_squared();
      real_t dcross=line[0].cross(line[1]);
      real_t Q2 = radius*radius*dr2-dcross*dcross;
      if(Q2<0)
        return 0;

      real_t x0=dcross*d.y, y0=-dcross*d.x;
      
      if(Q2==0) {
        intersection[0].x=x0/dr2;
        intersection[0].y=y0/dr2;
        intersection[1] = intersection[0];
        return 1;
      }

      real_t Q=sqrtf(Q2);
      real_t xp=d.x*Q*(d.y<0 ? -1 : 1);
      real_t yp=fabsf(d.y)*Q;

      intersection[0].x = (x0+xp)/dr2;
      intersection[0].y = (y0+yp)/dr2;
      
      intersection[1].x = (x0-xp)/dr2;
      intersection[1].y = (y0-yp)/dr2;
      
      return 2;
    }
    
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
      return true;
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
