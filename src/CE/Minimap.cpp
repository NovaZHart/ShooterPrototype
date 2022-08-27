#include <PoolArrays.hpp>
#include <VisualServer.hpp>
#include <Geometry.hpp>

#include "FastProfilier.hpp"
#include "CE/Constants.hpp"
#include "CE/Minimap.hpp"
#include "CE/CombatEngine.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

const real_t Minimap::crosshairs_width = 1;
const Color Minimap::hostile_color(1,1,0,1);
const Color Minimap::friendly_color(0.1,0.1,1,1);
const Color Minimap::player_color(0,1,0,1);
const Color Minimap::neutral_color(0.7,0.7,0.7);
const Color Minimap::asteroid_field_color(0.6,0.6,0.4,0.2);
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

void Minimap::draw_asteroid_field(real_t inner_radius,real_t outer_radius,
                                  const Rect2 &map_region,const Rect2 &minimap,real_t radius_scale,
                                  const Vector2 &map_center,const Vector2 &map_scale,
                                  const Vector2 &minimap_center,const Vector2 &minimap_half_size) {
  // minimap = on-screen location in pixels
  // map_region = region of map that matches those pixels

  // Min & max allowed edges of the outer half of a polygon representing an arc of the annulus:
  const int min_edges = 5;
  const int max_edges = 200;

  Rect2 asteroid_field_search_region(Vector2(-(map_region.position.y+map_region.size.y),map_region.position.x),
                                     Vector2(map_region.size.y,map_region.size.x));
  
  if(AsteroidSearchResult::rect_entirely_outside_annulus(asteroid_field_search_region,inner_radius,outer_radius))
    return;

  Geometry * geo=godot::Geometry::get_singleton();
  VisualServer *visual_server = VisualServer::get_singleton();
  
  // Find the innermost and outermost radii from origin that the rect touches:
  real_t r_min_squared = rect_distance_squared_to(map_region,Vector2(0,0));
  real_t r_max_squared;
  {
    Vector2 UL=map_region.position, DR=UL+map_region.size;
    real_t LL = UL.x*UL.x, RR = DR.x*DR.x;
    real_t UU = UL.y*UL.y, DD = DR.y*DR.y;
    r_max_squared = max(UU,DD)+max(LL,RR);
  }

  // Need the radii, not squared, for next calculation:
  real_t r_min=max(sqrtf(r_min_squared),inner_radius);
  real_t r_max=min(sqrtf(r_max_squared),outer_radius);

  deque<AsteroidSearchResult> found,work;
    
  if(not AsteroidSearchResult::theta_ranges_of_rect(asteroid_field_search_region,found,work,inner_radius,outer_radius))
    return;
  if(found.size()>1)
    AsteroidSearchResult::merge_set(found);
  // Make a polygon for the view rect
  PoolVector2Array rectpool;
  rectpool.resize(4);
  {
    PoolVector2Array::Write writer=rectpool.write();
    Vector2 *rect=writer.ptr();
    
    Vector2 UL=minimap.position, DR=UL+minimap.size;

    if(UL.x>DR.x)
      swap(UL.x,DR.x);
    
    if(UL.y<DR.y)
      swap(UL.y,DR.y);
    
    real_t L = UL.x, R = DR.x;
    real_t U = UL.y, D = DR.y;

    rect[0] = Vector2(L,U);
    rect[1] = Vector2(R,U);
    rect[2] = Vector2(R,D);
    rect[3] = Vector2(L,D);
  }

  // if(!geo->is_polygon_clockwise(rectpool))
  //   Godot::print_error("Rect poly is not clockwise",__FUNCTION__,__FILE__,__LINE__);
  
  PoolVector2Array polypool;
  PoolColorArray colorpool;
  
  // Draw polygons for the annulus
  for(auto &range : found) {
    if(not range.get_any_intersect())
      continue;
    
    // Angle step of one pixel at distance r_max from the origin;
    real_t dtheta=1.0/(r_max*radius_scale);
    real_t theta_width=range.get_theta_width();

    // Number of edges of this arc along circle:
    int nthetam1=roundf(theta_width/dtheta);

    // Ensure there aren't too many or too few edges
    if(nthetam1<min_edges) {
      nthetam1=min_edges;
      dtheta=theta_width/nthetam1;
    } else if(nthetam1>max_edges) {
      nthetam1=max_edges;
      dtheta=theta_width/nthetam1;
    }

    int vertices=2*(nthetam1+1);

    // Find vertices for this polygon
    polypool.resize(vertices);
    {
      PoolVector2Array::Write writer=polypool.write();
      Vector2 *poly = writer.ptr();
      for(int itheta=0;itheta<=nthetam1;itheta++) {
        real_t theta;
        if(itheta==nthetam1)
          theta=range.get_end_theta();
        else
          theta=range.get_start_theta()+dtheta*itheta;

        Vector3 map_space_normal(cos(theta),0,-sin(theta));
        Vector2 outer_map_space(map_space_normal.z*r_max,-map_space_normal.x*r_max);
        Vector2 inner_map_space(map_space_normal.z*r_min,-map_space_normal.x*r_min);
        Vector2 outer=(outer_map_space-map_center)*map_scale+minimap_center;
        Vector2 inner=(inner_map_space-map_center)*map_scale+minimap_center;

        poly[itheta] = outer;
        poly[vertices-itheta-1] = inner;
      }
    }
    // if(!geo->is_polygon_clockwise(polypool))
    //   Godot::print_error("Annulus arc poly is not clockwise",__FUNCTION__,__FILE__,__LINE__);

    // Find the intersection with the view rect
    Array within = geo->intersect_polygons_2d(polypool,rectpool);

    // Draw the intersection
    for(int i=0,e=within.size();i<e;i++) {
      PoolVector2Array clipped=within[i];
      if(clipped.size()>2) {
        int nvert=clipped.size();
        colorpool.resize(nvert);
        {
          PoolColorArray::Write writer = colorpool.write();
          Color *colors = writer.ptr();
          for(int j=0;j<nvert;j++)
            colors[j]=asteroid_field_color;
        }
        visual_server->canvas_item_add_polygon(canvas,clipped,colorpool);
      }
    }
  }
}

void Minimap::draw_minimap_contents(VisibleContent *visible_content, RID new_canvas,
                                         Vector2 map_center, real_t map_radius,
                                         Vector2 minimap_center, real_t minimap_radius) {
  // FIXME: Add asteroid field to circular minimap, if I ever switch
  // back to using a circular minimap.

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
  int proj=0;
  for(auto &projectile : visible_content->effects) {
    if(++proj>MAX_PROJECTILES_IN_MINIMAP)
      break;
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

  // Draw asteroid fields under everything
  for(auto &inner_outer : visible_content->asteroid_fields)
    draw_asteroid_field(inner_outer.first,inner_outer.second,map,minimap,radius_scale,
                        map_center,map_scale,minimap_center,minimap_half_size);
  
  // Draw ships and planets.
  for(auto &id_object : visible_content->ships_and_planets) {
    VisibleObject &object = id_object.second;
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
  int proj=0;
  for(auto &projectile : visible_content->effects) {
    if(++proj>MAX_PROJECTILES_IN_MINIMAP)
      break;
    Vector2 scaled = (Vector2(projectile.center.y,-projectile.center.x)-map_center) *map_scale;
    if(scaled.x>minimap_half_size.x or scaled.x<-minimap_half_size.x or
       scaled.y>minimap_half_size.y or scaled.y<-minimap_half_size.y)
      continue;
    visual_server->canvas_item_add_circle(canvas,minimap_center+scaled,1,projectile_color);
  }
}
