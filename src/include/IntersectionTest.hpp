#ifndef INTERSECTIONTEST_HPP
#define INTERSECTIONTEST_HPP

#include <unordered_set>
#include <memory>

#include <PoolArrays.hpp>
#include <Godot.hpp>
#include "CE/AsteroidField.hpp"
#include "CE/CelestialObject.hpp"

namespace godot {
  class IntersectionTest: public Reference {
    GODOT_CLASS(IntersectionTest,Reference)
    
  public:
    IntersectionTest();
    ~IntersectionTest();
    void _init();
    static void _register_methods();
    void set_annulus(real_t inner,real_t outer);
    void set_asteroid_field(Array a);
    PoolVector3Array get_asteroids();
    Array cast_ray(Vector2 start, Vector2 end);
    Array intersect_circle(Vector2 center, real_t radius);
    Array intersect_rect(Rect2 rect);
    void step_time(real_t delta,Rect2 visible_region);

    
    PoolVector3Array overlapping_rect(Rect2 rect) const;
    PoolVector3Array overlapping_circle(Vector2 center,real_t radius) const;
    PoolVector3Array first_in_circle(Vector2 center,real_t radius) const;
    PoolVector3Array cast_ray_first_hit(Vector2 start,Vector2 end) const;
    
  private:
    void matches_to_array(PoolVector3Array &data,const CE::hit_list_t &matches) const;
    
    real_t inner_radius, outer_radius;
    std::shared_ptr<CE::AsteroidField> field_ptr;
  };
}

#endif
