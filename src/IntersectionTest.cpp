#include "IntersectionTest.hpp"
#include "CE/AsteroidField.hpp"
#include "CE/Utils.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

void IntersectionTest::_register_methods() {
  register_method("set_annulus",&IntersectionTest::set_annulus);
  register_method("cast_ray",&IntersectionTest::cast_ray);
  register_method("intersect_circle",&IntersectionTest::intersect_circle);
}

void IntersectionTest::_init() {}

void IntersectionTest::set_annulus(real_t inner,real_t outer) {
  inner_radius = max(0.01f,inner);
  outer_radius = max(inner_radius+0.01f,outer);
  Godot::print("Annulus request inner="+str(inner)+" outer="+str(outer));
  Godot::print("Annulus actual inner="+str(inner_radius)+" outer="+str(outer_radius));
}

Array IntersectionTest::intersect_circle(Vector2 center,real_t radius) {
  AsteroidSearchResult range = AsteroidSearchResult::theta_range_of_circle(center,radius,inner_radius,outer_radius);
  Array result;
  if(range.get_any_intersect()) {
    if(range.get_all_intersect())
      result.append(Vector2(0,TAUf-.001));
    else
      result.append(Vector2(range.get_start_theta(),range.get_end_theta()));
  }
  return result;
}

Array IntersectionTest::cast_ray(Vector2 start,Vector2 end) {
  Godot::print("Cast ray start="+str(start)+" to end="+str(end));
  pair<AsteroidSearchResult,AsteroidSearchResult> ranges =
    AsteroidSearchResult::theta_ranges_of_ray(start,end,inner_radius,outer_radius);
  Array result;
  for(int i=0;i<2;i++) {
    AsteroidSearchResult &range = i==0 ? ranges.first : ranges.second;
    if(range.get_any_intersect()) {
      if(range.get_all_intersect()) {
        Godot::print("Range "+str(i)+" has get_all_intersect=true");
        result.append(Vector2(0,TAUf-.001));
      } else {
        Godot::print("Range "+str(i)+" has theta range start="+str(range.get_start_theta())+" end="+str(range.get_end_theta()));
        result.append(Vector2(range.get_start_theta(),range.get_end_theta()));
      }
    } else
      Godot::print("Range "+str(i)+" has get_any_intersect=false");
  }
  return result;
}
