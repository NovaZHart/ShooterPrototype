#include <PoolArrays.hpp>
#include <VisualServer.hpp>

#include "FastProfilier.hpp"
#include "CE/Constants.hpp"
#include "CE/Minimap.hpp"
#include "CE/CombatEngine.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

const real_t Minimap::crosshairs_width = 1;
const Color Minimap::hostile_color(1,0,0,1);
const Color Minimap::friendly_color(0,0,1,1);
const Color Minimap::player_color(0,1,0,1);
const Color Minimap::neutral_color(0.7,0.7,0.7);
const Color Minimap::projectile_color = neutral_color;
const Color Minimap::planet_color = neutral_color;

Minimap::Minimap(): canvas() {}
Minimap::~Minimap() {}

static inline bool origin_intersection(real_t end_x,real_t end_y,real_t bound_x,real_t bound_y,real_t &intersection) {
  if(end_x<bound_x)
    return false;
  intersection = end_y*bound_x/end_x;
  return intersection>-bound_y and intersection<bound_y;
}

Vector2 Minimap::place_in_rect(const Vector2 &map_location,
                               const Vector2 &map_center,const Vector2 &map_scale,
                               const Vector2 &minimap_center,const Vector2 &minimap_half_size) {
  FAST_PROFILING_FUNCTION;
  Vector2 centered = (map_location-map_center)*map_scale;
  real_t intersection;

  if(origin_intersection(centered.x,centered.y,minimap_half_size.x,minimap_half_size.y,intersection))
    // Object is to the left of the minimap.
    return Vector2(minimap_half_size.x,intersection)+minimap_center;

  if(origin_intersection(-centered.x,centered.y,minimap_half_size.x,minimap_half_size.y,intersection))
    // Object is to the right of the minimap.
    return Vector2(-minimap_half_size.x,intersection)+minimap_center;

  if(origin_intersection(centered.y,centered.x,minimap_half_size.y,minimap_half_size.x,intersection))
    // Object is below the minimap.
    return Vector2(intersection,minimap_half_size.y)+minimap_center;

  if(origin_intersection(-centered.y,centered.x,minimap_half_size.y,minimap_half_size.x,intersection))
    // Object is above the minimap.
    return Vector2(intersection,-minimap_half_size.y)+minimap_center;

  // Object is within the minimap.
  return centered+minimap_center;
}

Vector2 Minimap::place_center(const Vector2 &where,
                              const Vector2 &map_center,real_t map_radius,
                              const Vector2 &minimap_center,real_t minimap_radius) {
  FAST_PROFILING_FUNCTION;
  Vector2 minimap_scaled = (where-map_center)/map_radius*minimap_radius;
  real_t outside=minimap_radius*0.95;
  real_t outside_squared = outside*outside;
  if(minimap_scaled.length_squared() > outside_squared)
    minimap_scaled = minimap_scaled.normalized()*outside;
  return minimap_scaled + minimap_center;
}

void Minimap::draw_anulus(const Vector2 &center,real_t inner_radius,real_t outer_radius,
                          const Color &color,bool antialiased) {
  FAST_PROFILING_FUNCTION;
  real_t middle_radius = (inner_radius+outer_radius)/2;
  real_t thickness = fabsf(outer_radius-inner_radius);
  PoolVector2Array points;
  PoolColorArray colors;
  int npoints = 80; // clamp(int(middle_radius/thickness+3)/4,8,200);
  points.resize(npoints+1);
  colors.resize(npoints+1);

  PoolColorArray::Write write_colors=colors.write();
  Color *color_data = write_colors.ptr();
  
  for(int i=0;i<=npoints;i++)
    color_data[i]=color;
  
  PoolVector2Array::Write write_points=points.write();
  Vector2 *point_data=write_points.ptr();
  
  for(int i=0;i<npoints;i++) {
    real_t a = 2*PI*i/npoints;
    real_t x = sin(a)*middle_radius;
    real_t y = cos(a)*middle_radius;
    point_data[i] = center+Vector2(x,y);
  }
  
  point_data[npoints] = point_data[0];
  
  VisualServer::get_singleton()->canvas_item_add_polyline(canvas,points,colors,thickness,antialiased);
}

void Minimap::draw_crosshairs(const Vector2 &loc, real_t radius, const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector2 small_x(radius*1.5+1,0);
  Vector2 small_y(0,radius*1.5+1);
  Vector2 big_x(12,0);
  Vector2 big_y(0,12);
  VisualServer *visual_server = VisualServer::get_singleton();
  visual_server->canvas_item_add_line(canvas,loc-big_x,loc-small_x,color,crosshairs_width,true);
  visual_server->canvas_item_add_line(canvas,loc+big_x,loc+small_x,color,crosshairs_width,true);
  visual_server->canvas_item_add_line(canvas,loc-big_y,loc-small_y,color,crosshairs_width,true);
  visual_server->canvas_item_add_line(canvas,loc+big_y,loc+small_y,color,crosshairs_width,true);
  draw_anulus(loc,big_x[0]-crosshairs_width/2,big_x[0]+crosshairs_width/2,color,true);
}

void Minimap::draw_velocity(VisibleObject &ship, const Vector2 &loc,
                                 const Vector2 &map_center,real_t map_radius,
                                 const Vector2 &minimap_center,real_t minimap_radius,
                                 const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector2 away = place_center(Vector2(ship.z,-ship.x)+Vector2(ship.vz,-ship.vx),
                              map_center,map_radius,minimap_center,minimap_radius);
  VisualServer::get_singleton()->canvas_item_add_line(canvas,loc,away,color,1.5,true);
}

void Minimap::draw_heading(VisibleObject &ship, const Vector2 &loc,
                                const Vector2 &map_center,real_t map_radius,
                                const Vector2 &minimap_center,real_t minimap_radius,
                                const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector3 heading3 = unit_from_angle(ship.rotation_y);
  Vector2 heading2(heading3.z,-heading3.x);
  Vector2 minimap_heading = place_center(Vector2(ship.z,-ship.x)+ship.max_speed*1.25*heading2,
                                         map_center,map_radius,minimap_center,minimap_radius);
  VisualServer::get_singleton()->canvas_item_add_line(canvas,loc,minimap_heading,color,1,true);
}

void Minimap::rect_draw_velocity(VisibleObject &ship, const Vector2 &loc,
                                      const Vector2 &map_center,const Vector2 &map_scale,
                                      const Vector2 &minimap_center,const Vector2 &minimap_half_size,
                                      const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector2 away = place_in_rect(Vector2(ship.z,-ship.x)+Vector2(ship.vz,-ship.vx),
                               map_center,map_scale,minimap_center,minimap_half_size);
  VisualServer::get_singleton()->canvas_item_add_line(canvas,loc,away,color,1.5,true);
}

void Minimap::rect_draw_heading(VisibleObject &ship, const Vector2 &loc,
                                     const Vector2 &map_center,const Vector2 &map_scale,
                                     const Vector2 &minimap_center,const Vector2 &minimap_half_size,
                                     const Color &color) {
  FAST_PROFILING_FUNCTION;
  Vector3 heading3 = unit_from_angle(ship.rotation_y);
  Vector2 heading2(heading3.z,-heading3.x);
  Vector2 minimap_heading = place_in_rect(Vector2(ship.z,-ship.x)+ship.max_speed*1.25*heading2,
                                          map_center,map_scale,minimap_center,minimap_half_size);
  VisualServer::get_singleton()->canvas_item_add_line(canvas,loc,minimap_heading,color,1,true);
}

const Color &Minimap::pick_object_color(VisibleObject &object) {
  FAST_PROFILING_FUNCTION;
  if(object.flags&VISIBLE_OBJECT_PLANET)
    return planet_color;
  if(object.flags&VISIBLE_OBJECT_PLAYER)
    return player_color;
  if(object.flags&VISIBLE_OBJECT_HOSTILE)
    return hostile_color;
  return friendly_color;
}

void Minimap::draw_minimap_contents(VisibleContent *visible_content, RID new_canvas,
                                         Vector2 map_center, real_t map_radius,
                                         Vector2 minimap_center, real_t minimap_radius) {
  FAST_PROFILING_FUNCTION;
  canvas=new_canvas;
  
  if(!visible_content)
    return; // Nothing to display yet.

  VisualServer *visual_server = VisualServer::get_singleton();
  
  // Draw ships and planets.
  for(auto &id_object : visible_content->ships_and_planets) {
    VisibleObject &object = id_object.second;
    Vector2 center(object.z,-object.x);
    const Color &color = pick_object_color(object);
    Vector2 loc = place_center(Vector2(object.z,-object.x),
                               map_center,map_radius,minimap_center,minimap_radius);
    if(object.flags & VISIBLE_OBJECT_PLANET) {
      real_t rad = object.radius/map_radius*minimap_radius;
      if(object.flags&VISIBLE_OBJECT_PLAYER_TARGET)
        draw_crosshairs(loc,rad,color);
      draw_anulus(loc,rad*3-0.75,rad*3+0.75,color,false);
    } else { // ship
      visual_server->canvas_item_add_circle(canvas,loc,min(2.5f,object.radius/2.0f),color);
      if(object.flags&(VISIBLE_OBJECT_PLAYER_TARGET|VISIBLE_OBJECT_PLAYER)) {
        draw_heading(object,loc,map_center,map_radius,minimap_center,minimap_radius,color);
        draw_velocity(object,loc,map_center,map_radius,minimap_center,minimap_radius,color);
      }
    }
  }
  
  // Draw only the projectiles within the minimap; skip outsiders.
  real_t outside=minimap_radius*0.95;
  real_t outside_squared = outside*outside;
  for(auto &projectile : visible_content->effects) {
    Vector2 minimap_scaled = (Vector2(projectile.center.y,-projectile.center.x)-map_center) /
      map_radius*minimap_radius;
    if(minimap_scaled.length_squared() > outside_squared)
      continue;
    visual_server->canvas_item_add_circle(canvas,minimap_center+minimap_scaled,1,projectile_color);
  }
}



void Minimap::draw_minimap_rect_contents(VisibleContent *visible_content,
                                              RID new_canvas,Rect2 map,Rect2 minimap) {
  FAST_PROFILING_FUNCTION;
  canvas=new_canvas;

  if(!visible_content)
    return; // Nothing to display yet.

  VisualServer *visual_server = VisualServer::get_singleton();

  Vector2 map_center = map.position+map.size/2.0f;
  Vector2 minimap_center = minimap.position+minimap.size/2.0f;
  Vector2 map_half_size(fabsf(map.size.x)/2.0f,fabsf(map.size.y)/2.0f);
  Vector2 minimap_half_size(fabsf(minimap.size.x)/2.0f,fabsf(minimap.size.y)/2.0f);
  Vector2 map_scale(minimap_half_size.x/map_half_size.x,minimap_half_size.y/map_half_size.y);
  real_t radius_scale = map_scale.length();

  // Draw ships and planets.
  for(auto &id_object : visible_content->ships_and_planets) {
    VisibleObject &object = id_object.second;
    Vector2 center(object.z,-object.x);
    const Color &color = pick_object_color(object);
    Vector2 loc = place_in_rect(Vector2(object.z,-object.x),
                                map_center,map_scale,minimap_center,minimap_half_size);
    if(object.flags & VISIBLE_OBJECT_PLANET) {
      real_t rad = object.radius*radius_scale;
      if(object.flags&VISIBLE_OBJECT_PLAYER_TARGET)
        draw_crosshairs(loc,rad,color);
      draw_anulus(loc,rad,rad+0.75,color,false);
    } else { // ship
      visual_server->canvas_item_add_circle(canvas,loc,min(2.5f,object.radius),color);
      if(object.flags&(VISIBLE_OBJECT_PLAYER_TARGET|VISIBLE_OBJECT_PLAYER)) {
        rect_draw_heading(object,loc,map_center,map_scale,minimap_center,minimap_half_size,color);
        rect_draw_velocity(object,loc,map_center,map_scale,minimap_center,minimap_half_size,color);
      }
    }
  }

  // Draw only the projectiles within the minimap; skip outsiders.
  //real_t outside=minimap_radius*0.95;
  //real_t outside_squared = outside*outside;
  int proj=0;
  for(auto &projectile : visible_content->effects) {
    if(++proj>200)
      break;
    Vector2 scaled = (Vector2(projectile.center.y,-projectile.center.x)-map_center) *map_scale;
    if(scaled.x>minimap_half_size.x or scaled.x<-minimap_half_size.x or
       scaled.y>minimap_half_size.y or scaled.y<-minimap_half_size.y)
      continue;
    visual_server->canvas_item_add_circle(canvas,minimap_center+scaled,1,projectile_color);
  }
}
