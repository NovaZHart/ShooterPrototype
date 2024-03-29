#include <unordered_set>

#include "IntersectionTest.hpp"
#include "CE/AsteroidField.hpp"
#include "CE/Salvage.hpp"
#include "CE/Utils.hpp"
#include "CE/Constants.hpp"

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
  register_method("set_asteroid_field",&IntersectionTest::set_asteroid_field);
  register_method("overlapping_rect",&IntersectionTest::overlapping_rect);
  register_method("overlapping_circle",&IntersectionTest::overlapping_circle);
  register_method("first_in_circle",&IntersectionTest::first_in_circle);
  register_method("cast_ray_first_hit",&IntersectionTest::cast_ray_first_hit);
}

IntersectionTest::IntersectionTest():
  inner_radius(1), outer_radius(2), field_ptr()
{}

IntersectionTest::~IntersectionTest()
{}

void IntersectionTest::_init() {}

void IntersectionTest::set_asteroid_field(Array a) {
  shared_ptr<AsteroidPalette> no_asteroids = make_shared<AsteroidPalette>();
  shared_ptr<SalvagePalette> no_salvage = make_shared<SalvagePalette>();
  field_ptr = make_shared<AsteroidField>(0,a,no_asteroids,no_salvage,0);
  AsteroidPalette empty;
  CheapRand32 rand;
  field_ptr->generate_field();
}

void IntersectionTest::step_time(real_t delta,Rect2 visible_region) {
  if(field_ptr) {
    int64_t idelta = delta*ticks_per_second;
    field_ptr->step_time(idelta,delta,visible_region);
  }
}

void IntersectionTest::matches_to_array(PoolVector3Array &data,const hit_list_t &matches) const {
  size_t size = matches.size();
  data.resize(size);
  int found = 0;
  
  {
    PoolVector3Array::Write writer = data.write();
    Vector3 *dataptr = writer.ptr();
    
    for(auto hit : matches) {
      if(!hit.hit)
        continue;
      if(hit.hit->is_asteroid()) {
        Asteroid &asteroid = hit.hit->as_asteroid();
        Vector2 xz = hit.xz;
        real_t scale = asteroid.get_scale();
        dataptr[found] = Vector3(xz.x,xz.y,scale);
        found++;
      } else
        Godot::print_error("Non-asteroid found in asteroid hit list.",
                           __FUNCTION__,__FILE__,__LINE__);
    }
  }

  if(found!=data.size())
    data.resize(found);
}

PoolVector3Array IntersectionTest::overlapping_rect(Rect2 rect) const {
  PoolVector3Array results;
  if(field_ptr) {
    hit_list_t matches;
    field_ptr->overlapping_rect(rect,matches,1000000);
    matches_to_array(results,matches);
  }
  return results;
}

PoolVector3Array IntersectionTest::overlapping_circle(Vector2 center,real_t radius) const {
  PoolVector3Array results;
  if(field_ptr) {
    hit_list_t matches;
    field_ptr->overlapping_circle(center,radius,matches,1000000);
    matches_to_array(results,matches);
  }
  return results;
}

PoolVector3Array IntersectionTest::first_in_circle(Vector2 center,real_t radius) const {
  PoolVector3Array results;
  if(field_ptr) {
    hit_list_t matches;
    matches.push_back(field_ptr->first_in_circle(center,radius));
    matches_to_array(results,matches);
  }
  return results;
}

PoolVector3Array IntersectionTest::cast_ray_first_hit(Vector2 start,Vector2 end) const {
  PoolVector3Array results;
  if(field_ptr) {
    hit_list_t matches;
    CelestialHit hit = field_ptr->cast_ray(start,end);
    matches.push_back(hit);
    matches_to_array(results,matches);
  }
  return results;
}

PoolVector3Array IntersectionTest::get_asteroids() {
  PoolVector3Array asteroids;
  if(field_ptr) {
    size_t size = field_ptr->size();
    size_t found=0;
    asteroids.resize(size);

    {
      PoolVector3Array::Write writer = asteroids.write();
      Vector3 *dataptr = writer.ptr();
      
      for(const Asteroid *a : *field_ptr) {
        if(a) {
          if(found>=size) {
            Godot::print_error("More asteroids found ("+str(found)+") than purported size ("+str(size)+").",
                               __FUNCTION__,__FILE__,__LINE__);
            break;
          }
          
          Vector2 xz = a->get_xz();
          real_t scale = a->get_scale();
          dataptr[found] = Vector3(xz.x,xz.y,scale);
        } else
          Godot::print_error("Null asteroid data found in AsteroidField.",
                             __FUNCTION__,__FILE__,__LINE__);
        found++;
      }
    }

    if(found<size) {
      asteroids.resize(found);
      Godot::print_error("Fewer asteroids found ("+str(found)+") than purported size ("+str(size)+").",
                         __FUNCTION__,__FILE__,__LINE__);
    }
  }
  return asteroids;
}

void IntersectionTest::set_annulus(real_t inner,real_t outer) {
  inner_radius = max(0.01f,inner);
  outer_radius = max(inner_radius+0.01f,outer);
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
  pair<AsteroidSearchResult,AsteroidSearchResult> ranges =
    AsteroidSearchResult::theta_ranges_of_ray(start,end,inner_radius,outer_radius);
  Array result;
  for(int i=0;i<2;i++) {
    AsteroidSearchResult &range = i==0 ? ranges.first : ranges.second;
    if(range.get_any_intersect()) {
      if(range.get_all_intersect()) {
        result.append(Vector2(0,TAUf-.001));
      } else {
        result.append(Vector2(range.get_start_theta(),range.get_end_theta()));
      }
    }
  }
  return result;
}
