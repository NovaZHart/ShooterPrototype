#ifndef MINIMAP_HPP
#define MINIMAP_HPP

#include <RID.hpp>
#include <Vector2.hpp>
#include <Color.hpp>
#include "CE/VisibleContent.hpp"
#include "CE/AsteroidField.hpp"

namespace godot {
  namespace CE {
    class Minimap {
      RID canvas;
      static const real_t crosshairs_width;
      static const Color hostile_color, friendly_color, player_color, neutral_color,
        projectile_color, planet_color, asteroid_field_color;
    public:
      Minimap();
      ~Minimap();

      void draw_minimap_contents(VisibleContent *visible_content,
                                 RID new_canvas, Vector2 map_center, real_t map_radius,
                                 Vector2 minimap_center, real_t minimap_radius);
      void draw_minimap_rect_contents(VisibleContent *visible_content,
                                      RID new_canvas,Rect2 map,Rect2 minimap);
    private:
      void draw_asteroid_field_polygon(real_t r_min,real_t r_max,real_t start_theta,
                                       real_t end_theta,real_t theta_width,real_t radius_scale,
                                       Vector2 map_scale,Vector2 map_center,Vector2 minimap_center,
                                       PoolVector2Array &rectpool);

      void draw_asteroid_field(real_t inner_radius,real_t outer_radius,
                               const Rect2 &map_region,const Rect2 &minimap,real_t radius_scale,
                               const Vector2 &map_center,const Vector2 &map_scale,
                               const Vector2 &minimap_center,const Vector2 &minimap_half_size);
      Vector2 place_center(const Vector2 &where,
                           const Vector2 &map_center,real_t map_radius,
                           const Vector2 &minimap_center,real_t minimap_radius);
      Vector2 place_in_rect(const Vector2 &map_location,
                            const Vector2 &map_center,const Vector2 &map_scale,
                            const Vector2 &minimap_center,const Vector2 &minimap_half_size);
      void draw_anulus(const Vector2 &center,real_t inner_radius,real_t outer_radius,
                       const Color &color,bool antialiased);
      void draw_crosshairs(const Vector2 &loc, real_t minimap_radius, const Color &color);
      void rect_draw_velocity(VisibleObject &ship, const Vector2 &loc,
                              const Vector2 &map_center,const Vector2 &map_scale,
                              const Vector2 &minimap_center,const Vector2 &minimap_half_size,
                              const Color &color);
      void rect_draw_heading(VisibleObject &ship, const Vector2 &loc,
                             const Vector2 &map_center,const Vector2 &map_scale,
                             const Vector2 &minimap_center,const Vector2 &minimap_half_size,
                             const Color &color);

      void draw_velocity(VisibleObject &ship, const Vector2 &loc,
                         const Vector2 &map_center,real_t map_radius,
                         const Vector2 &minimap_center,real_t minimap_radius,
                         const Color &color);
      void draw_heading(VisibleObject &ship, const Vector2 &loc,
                        const Vector2 &map_center,real_t map_radius,
                        const Vector2 &minimap_center,real_t minimap_radius,
                        const Color &color);
      const Color &pick_object_color(VisibleObject &object);
    };
  }
}

#endif
