#include <cmath>

#include "CE/AsteroidField.hpp"
#include "CE/CheapRand32.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

static const real_t tau = 2*PIf;
static const real_t angle_to_int = (1<<30)/tau;


////////////////////////////////////////////////////////////////////////

static AsteroidSearchResult theta_from(Vector2 a,Vector2 b) {
  return AsteroidSearchResult { angle_from_unit(a), angle_from_unit(b), true, false };
}

static AsteroidSearchResult shortest_theta_from(Vector2 a,Vector2 b) {
  AsteroidSearchResult r { angle_from_unit(a), angle_from_unit(b), true, false };
  real_t size = fmodf(r.end_theta-r.start_theta,tau);
  if(size>PIf)
    swap(r.start_theta,r.end_theta);
  return r;
}

static const AsteroidSearchResult no_match { 0.0f, 0.0f, false, false };
static const AsteroidSearchResult all_match { 0.0f, 0.0f, true, true };

////////////////////////////////////////////////////////////////////////


AsteroidField::AsteroidLayer::AsteroidLayer(real_t orbit_period, real_t inner_radius, real_t thickness, real_t spacing):
  orbit_period(orbit_period), inner_radius(inner_radius),
  thickness(thickness), spacing(spacing),
  asteroids(), state()
{}

AsteroidField::AsteroidLayer::~AsteroidLayer()
{}

int AsteroidField::AsteroidLayer::find_theta(real_t theta) {
  real_t modded = fmodf(theta,tau);
  Asteroid findme(modded,0,0,0);
  vector<Asteroid>::iterator bound =
    lower_bound(asteroids.begin,asteroids.end,findme,
                [&](const Asteroid &a,const Asteroid &b) {
                  return a.theta<b.theta;
                });
  return bound==theta.end() ? 0 : bound-theta.begin();
}

pair<AsteroidSearchResult,AsteroidSearchResult>
AsteroidField::AsteroidLayer::theta_ranges_of_ray(Vector2 start,Vector2 end) {
  real_t slen = start.length(), elen=end.length();
  real_t outer_radius = inner_radius+thickness;

  bool intersect_inner=false, intersect_outer=false;

  if(slen<inner_radius) {
    // Start inside inner circle.
    if(elen<inner_radius)
      // Start and end entirely within inner circle. No match.
      return pair(no_match,no_match);
    else if(elen>outer_radius) {
      // Start inside inner, end outside outer. Match the range of
      // intersection from inner to outer.
      Vector2 inner1, inner2;
      Vector2 outer1, outer2;
      intersect_outer = circle_intersection(outer_radius,center,search_radius,outer1,outer2);
      intersect_inner = circle_intersection(inner_radius,center,search_radius,inner1,inner2);
      if(intersect_inner and intersect_outer)
        return pair(shortest_theta_from(inner1,outer1),no_match);
     
      // Should not reach this line.
    } else {
      // Start inside the inner circle, end within the annulus.
      // Match from inner intersection to end point.
      Vector2 inner1, inner2;
      intersect_inner = circle_intersection(inner_radius,center,search_radius,inner1,inner2);
      if(intersect_inner)
        return pair(shortest_theta_from(inner1,end),no_match);
      // Should not reach this line.
    }
  } else if(slen>outer_radius) {
    // Start outside outer circle.
    if(elen>outer_radius) {
      // Both are outside.
      // Three possibilities:
      // 0-1 intersections with outer circle = no intersection (common special case)
      // 2 intersections with outer circle
      //    0-1 intersections with inner circle = outer circle theta range
      //    2 intersections with inner circle = two matching ranges

      Vector2 outer1, outer2;
      intersect_outer = circle_intersection(outer_radius,center,search_radius,outer1,outer2);
      if(not intersect_outer or outer1==outer2)
        // Ray is entirely outside the outer circle. No match.
        return pair(no_match,no_match);

      Vector2 inner1, inner2;
      intersect_inner = circle_intersection(inner_radius,center,search_radius,inner1,inner2);
      if(!intersect_inner or inner1==inner2)
        // Ray passes within annulus, but not through inner circle.
        // Match the range between the outer matches.
        return pair(shortest_theta_from(outer1,outer2),no_match);

      // Ray passes through the inner and outer circles. There are two regions that match.
      return pair(shortest_theta_from(outer1,inner1),shortest_theta_from(inner2,outer2));
    } else if(elen<inner_radius) {
      // Start outside, end inside. Match the range from inner to outer intersection.
      Vector2 outer1, outer2;
      intersect_outer = circle_intersection(outer_radius,center,search_radius,outer1,outer2);
      Vector2 inner1, inner2;
      intersect_inner = circle_intersection(inner_radius,center,search_radius,inner1,inner2);
      if(intersect_inner and intersect_outer)
        return pair(shortest_theta_from(inner1,outer1),no_match);
      // Should not reach this line.      
    } else {
      // Start outside outer, end within annulus. Match the range from outer intersection to end point
      Vector2 outer1, outer2;
      intersect_outer = circle_intersection(outer_radius,center,search_radius,outer1,outer2);
      if(intersect_outer)
        return pair(shortest_theta_from(outer1,end),no_match);
      // Should not reach this line.
    }
  } else {
    // Start inside the annulus
    if(elen>outer_radius) {
      // Start inside annulus, end outside the outer circle. Range is start point to outer intersection.
      Vector2 outer1, outer2;
      intersect_outer = circle_intersection(outer_radius,center,search_radius,outer1,outer2);
      if(intersect_outer)
        return pair(shortest_theta_from(start,outer1),no_match);
      // Should never reach this line.
    } else if(elen<inner_radius) {
      // Start inside annulus, end inside the inner circle. Range is start point to inner intersection.
      Vector2 inner1, inner2;
      intersect_inner = circle_intersection(inner_radius,center,search_radius,inner1,inner2);
      if(intersect_inner)
        return pair(shortest_theta_from(start,inner1),no_match);
      // Should never reach this line.
    } else {
      // Possibilities:
      // 0-1 intersections with inner circle = range from start to end
      // 2 intersections with inner circle = two matching ranges
      Vector2 inner1, inner2;
      intersect_inner = circle_intersection(inner_radius,center,search_radius,inner1,inner2);
      if(!intersect_inner or inner1==inner2)
        // Ray lies entirely within the annulus.
        return pair(shortest_theta_from(start,end),no_match);

      // Ray covers two areas within annulus saddling the inner circle
      return pair(shortest_theta_from(start,inner1),shortest_theta_from(inner2,end));
    }
  }
  
  // Should not reach this line.
  return pair(no_match,no_match);
}

AsteroidSearchResult AsteroidField::AsteroidLayer::theta_range_of_circle(Vector2 center,real_t search_radius) {
  real_t outer_radius = inner_radius+thickness;
  real_t clen = center.length();

  // Check for special cases. The vast majority of searches will match case 1 or 3.
  if(clen<thickness) {
    if(search_radius+clen<inner_radius)
      // Special case 1: circle lies entirely inside the inner circle of the annulus (no intersection)
      return no_match;
    if(search_radius-clen>=inner_radius and search_radius+clen<=outer_radius)
      // Special case 2: circle lies entirely within the annulus (all points match)
      return all_match;
  } else if(search_radius-clen>=outer_radius)
    // Special case 3: circle entirely encloses annulus (all points match)
    return all_match;

  Vector2 inner1, inner2;
  bool intersect_inner = circle_intersection(inner_radius,center,search_radius,
                                             inner1,inner2);

  Vector2 outer1, outer2;
  bool intersect_outer = circle_intersection(outer_radius,center,search_radius,
                                             outer1,outer2);

  if(intersect_inner) {
    if(intersect_outer) {
      AsteroidSearchResult inner_angles = theta_from(inner1,inner2);
      AsteroidSearchResult outer_angles = theta_from(outer1,outer2);
      real_t inner_range = fmodf(inner_angles.end_theta-inner_angles.start_theta,tau);
      real_t outer_range = fmodf(outer_angles.end_theta-outer_angles.start_theta,tau);
      return (inner_range>outer_range) ? inner_angles : outer_angles;
    } else
      return theta_from(inner1,inner2);
  } else if(intersect_outer)
    return theta_from(outer1,outer2);
  else
    return no_match;
}

void AsteroidField::AsteroidLayer::sort_asteroids() {
  std::sort(asteroids.begin(),asteroids.end(),[&](const Asteroid &a,const Asteroid &b) {
      return a.theta<b.theta;
    });
}

void AsteroidField::AsteroidLayer::create_asteroids(const AsteroidPalette &palette,CheapRand32 &rand) {
  real_t outer_radius = inner_radius+thickness;
  real_t annulus_area = PIf*(outer_radius*outer_radius-inner_radius*inner_radius);
  real_t spacing_area = PIf*spacing*spacing;
  asteroids.reserve(max(1,ceilf(annulus_area/spacing_area)));
  
  asteroids.clear();
  state.clear();
  
  real_t trimmed_thickness = thickness-2*Asteroid::max_scale;
  real_t theta_step = spacing/outer_radius/4;
    
  real_t radius_step = max(5,ceilf(trimmed_thickness/0.5));
  int radius_count = max(1,int(ceilf(trimmed_thickness/radius_step)));
  int radii_to_check = ceilf(spacing/radius_step);
  vector<real_t> last_theta_used(radius_count,-9e9f);
  vector<real_t> radius_of_bin(radius_count,0);
  vector<real_t> next_theta_used(radius_count,0);
  real_t diamond_halfwidth = spacing*sqrtf(2);

  {
    real_t radius = inner_radius+Asteroid::max_scale;
    for(int i=0;i<radius_count;i++,radius+=radius_step)
      radius_of_bin[i]=radius;
  }

  real_t theta = 0;
  do {
    // Randomly choose a radius bin to try to place an asteroid.
    int bin = rand.randi()%radius_count;
    real_t radius = radius_of_bin[bin];

    // Will it fit?
    bool too_big = false;
    int first_check = max(0,bin-radii_to_check);
    int last_check = min(radius_count-1,bin+radii_to_check);
    for(int check_bin=first_check;check_bin<=last_check;check_bin++) {
      real_t check_radius = radius_of_bin[check_bin];
      real_t y = radius-check_radius;
      real_t check_width = max(0.0f,diamond_halfwidth-fabsf(y));
      real_t theta_needed_here = check_width/check_radius * tau;
      if(theta-theta_used[check_bin]>theta_needed_here) {
        too_big=true;
        break;
      }
      // This part of the asteroid fits, so record the next value for
      // theta_used in case we decide to use this asteroid.
      next_theta_used[check_bin] = theta_needed_here+theta_used[check_bin];
    }

    if(!too_big) {
      // The asteroid fits. Update the last_theta_used and insert a new asteroid.
      for(int check_bin=first_check;check_bin<=last_check;check_bin++)
        last_theta_used[check_bin] = next_theta_used[check_bin];

      asteroids.emplace_back(theta,radius,y+rand.randf()-0.5,palette.random_choice(rand));
    } else
      // The asteroid does not fit. Increment theta and try again.
      theta += theta_step;
  } while(theta<tau);

  state.resize(asteroids);

  // FIXME: This should not be needed since the asteroids were generated in sorted order.
  sort_asteroids();
}

AsteroidField::AsteroidLayer::AsteroidLayer(real_t orbit_period, real_t inner_radius, real_t thickness, real_t spacing, real_t y):
  orbit_period(orbit_period),
  inner_radius(inner_radius),
  thickness(max(Asteroid::max_scale)*3,thickness),
  spacing(spacing),
  y(y),
  asteroids(),
  state()
{
  create_asteroids();
}

AsteroidField::AsteroidLayer::~AsteroidLayer() {}

////////////////////////////////////////////////////////////////////////

pair<const Asteroid *,const AsteroidState*> AsteroidField::get(object_id id) const {
  static const pair<const Asteroid*,const AsteroidState*> no_match(nullptr,nullptr);
  
  pair<int,int> split = split_id(id);
  if(split.first<0 or split.first>=layers.size())
    return no_match;

  const Asteroid *asteroid = layers[split.first].get_asteroid(split.second);
  if(!asteroid)
    return no_match;

  const AsteroidState *state = layers[split.first].get_valid_state(split.second,asteroid,now);

  return pair(asteroid,state);
}

bool AsteroidField::is_alive(object_id id) const {
  pair<int,int> split = split_id(id);
  if(split.first<0 or split.first>=layers.size())
    return false;

  Asteroid *asteroid = layers[split.first].get_asteroid(split.second);
  if(!asteroid)
    return false;

  return asteroid->is_alive();
}

double AsteroidField::damage_asteroid(object_id id,double damage) {
  pair<int,int> split = split_id(id);
  if(split.first<0 or split.first>=layers.size())
    return damage;

  Asteroid *asteroid = layers[split.first].get_asteroid(split.second);
  if(!asteroid)
    return damage;

  double remaining = asteroid.take_damage(damage);

  if(!asteroid.is_alive()) {
    dead_asteroids.insert(id);
    return remaining;
  } else
    return 0;
}

void AsteroidField::step_time(int64_t idelta,real_t delta,Rect2 visible_region) {
  now+=delta;

  for(auto it=dead_asteroids.begin();it!=dead_asteroids.end();) {
    object_id id = *it;
    pair<int,int> split = split_id(id);
    if(split.first>=0 and split.first<layers.size()) {
      const Asteroid *asteroid = layers[split.first].get_asteroid(split.second);
      if(asteroid and !asteroid->is_alive()) {
        asteroid.reset_state(

  }
}

object_id AsteroidField::cast_ray(Vector2 start,Vector2 end) const {
  real_t best_distsq = numeric_limits<real_t>::infinity();
  const Asteroid *best_asteroid = nullptr;
  const AsteroidState *best_state = nullptr;

  for(int ilayer=0;ilayer<layers.size();ilayer++) {
    const AsteroidLayer &layer = layers[ilayer];
    if(!layer.asteroids.size())
      continue; // Layer is empty. Should never happen.
    
    pair<AsteroidSearchResult,AsteroidSearchResult> range_pair = layer.theta_ranges_of_ray(start,end);
    AsteroidSearchResult ranges[2];
    ranges[0]=range_pair.first;
    ranges[1]=range_pair.second;

    int loop_start=0,loop_end=1;

    if(ranges[0].all_intersect or ranges[1].all_intersect)
      loop_end=0;
    else {
      if(!ranges[0].any_intersect)
        loop_start=1;
      if(!ranges[1].any_intersect)
        loop_end=0;
    }
    for(irange=loop_start;irange<=loop_end;irange++) {
      AsteroidSearchResult &range = ranges[irange];
      int itheta_start, itheta_after;
      if(range.all_intersect) {
        itheta_start = 0;
        itheta_end = layer.asteroids.size();
      } else {
        itheta_start = layer.find_theta(range.start_theta);
        itheta_end = layer.find_theta(range.end_theta)+1;
      }

      int itheta=itheta_start;
      int itheta_after = itheta_end+1;
      do {
        itheta=itheta%layer.asteroids.size();
        
        itheta++;
      } while(itheta!=itheta_after)
    }
  }
}
