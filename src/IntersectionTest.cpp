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
  register_method("intersect_rect",&IntersectionTest::intersect_rect);
  register_method("step_time",&IntersectionTest::step_time);
  register_method("get_asteroids",&IntersectionTest::get_asteroids);
  register_method("set_asteroid_layer",&IntersectionTest::set_asteroid_layer);
}

IntersectionTest::IntersectionTest():
  inner_radius(1), outer_radius(2), layer_ptr(), now(0)
{}

IntersectionTest::~IntersectionTest()
{}

void IntersectionTest::_init() {}

void IntersectionTest::set_asteroid_layer(Dictionary d) {
  layer_ptr = make_shared<AsteroidLayer>(d);
  AsteroidPalette empty;
  CheapRand32 rand;
  layer_ptr->generate_field(empty,rand);
}

void IntersectionTest::step_time(real_t dt) {
  now += dt;
}

PoolVector3Array IntersectionTest::get_asteroids() {
  PoolVector3Array asteroids;
  if(layer_ptr) {
    asteroids.resize(layer_ptr->size());

    PoolVector3Array::Write writer = asteroids.write();
    Vector3 *dataptr = writer.ptr();

    for(size_t index=0;index<layer_ptr->size();index++) {
      Asteroid *a = layer_ptr->get_asteroid(index);
      if(a) {
        AsteroidState *s = layer_ptr->get_valid_state(index,a,now);
        if(s) {
          Vector2 xz = s->get_xz();
          real_t scale = a->calculate_scale(*s);
          dataptr[index] = Vector3(xz.x,xz.y,scale);
          continue;
        }
      }
      dataptr[index] = Vector3(0,0,0);
    }
  }
  return asteroids;
}

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

Array IntersectionTest::intersect_rect(Rect2 rect) {
  deque<AsteroidSearchResult> ranges,work1;
  bool match = AsteroidSearchResult::theta_ranges_of_rect(rect,ranges,work1,inner_radius,outer_radius);
  Array result;
  if(match) {
     for(auto &range : ranges) {
       if(range.get_all_intersect())
         result.append(Vector2(0,TAUf-.001));
       else if(range.get_any_intersect())
         result.append(Vector2(range.get_start_theta(),range.get_end_theta()));
     }
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
