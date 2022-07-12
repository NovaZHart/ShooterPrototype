#ifndef INTERSECTIONTEST_HPP
#define INTERSECTIONTEST_HPP

#include <memory>

#include <Godot.hpp>
#include "CE/AsteroidField.hpp"

namespace godot {
  class IntersectionTest: public Reference {
    GODOT_CLASS(IntersectionTest,Reference)
    
  public:
    IntersectionTest();
    ~IntersectionTest();
    void _init();
    static void _register_methods();
    void set_annulus(real_t inner,real_t outer);
    void set_asteroid_layer(Dictionary d);
    PoolVector3Array get_asteroids();
    Array cast_ray(Vector2 start, Vector2 end);
    Array intersect_circle(Vector2 center, real_t radius);
    Array intersect_rect(Rect2 rect);
    void step_time(real_t dt);

  private:
    real_t inner_radius, outer_radius;
    std::shared_ptr<CE::AsteroidLayer> layer_ptr;
    double now;
  };
}

#endif
