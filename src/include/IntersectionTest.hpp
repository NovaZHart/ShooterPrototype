#ifndef INTERSECTIONTEST_HPP
#define INTERSECTIONTEST_HPP

#include <Godot.hpp>

namespace godot {
  class IntersectionTest: public Reference {
    GODOT_CLASS(IntersectionTest,Reference)
    
  public:
    void _init();
    static void _register_methods();
    void set_annulus(real_t inner,real_t outer);
    Array cast_ray(Vector2 start, Vector2 end);
    Array intersect_circle(Vector2 center, real_t radius);
    Array intersect_rect(Rect2 rect);
    
  private:
    real_t inner_radius, outer_radius;
  };
}

#endif
