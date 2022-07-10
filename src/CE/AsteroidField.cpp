#include <cmath>

#include <Variant.hpp>

#include "CE/AsteroidField.hpp"
#include "CE/CheapRand32.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

// Convenience functions and constants that are object-local.

static const AsteroidSearchResult no_match = AsteroidSearchResult::no_match;
static const AsteroidSearchResult all_match = AsteroidSearchResult::all_match;

static AsteroidSearchResult theta_from(Vector2 a,Vector2 b) {
  return AsteroidSearchResult(angle_from_unit(a), angle_from_unit(b));
}

static AsteroidSearchResult shortest_theta_from(Vector2 a,Vector2 b) {
  AsteroidSearchResult r(angle_from_unit(a), angle_from_unit(b));
  real_t size = fmodf(r.end_theta-r.start_theta,TAUf);
  return (size>PIf) ? r.negation() : r;
}

static AsteroidSearchResult longest_theta_from(Vector2 a,Vector2 b) {
  AsteroidSearchResult r(angle_from_unit(a), angle_from_unit(b));
  real_t size = fmodf(r.end_theta-r.start_theta,TAUf);
  return (size<PIf) ? r.negation() : r;
}

////////////////////////////////////////////////////////////////////////

const AsteroidSearchResult AsteroidSearchResult::no_match = AsteroidSearchResult(false);
const AsteroidSearchResult AsteroidSearchResult::all_match = AsteroidSearchResult(true);

AsteroidSearchResult::AsteroidSearchResult(real_t start, real_t end):
  start_theta(fmodf(start,TAUf)),
  end_theta(fmodf(end,TAUf)),
  theta_width(fmodf(end_theta-start_theta,TAUf)),
  any_intersect(true),
  all_intersect(false)
{}

pair<AsteroidSearchResult,AsteroidSearchResult>
AsteroidSearchResult::minus(const AsteroidSearchResult &region) const {
  typedef pair<AsteroidSearchResult,AsteroidSearchResult> result;
  if(region.all_intersect     // subtract universal set => nothing left
     or !any_intersect)       // subtract from empty set => empty set
    return result(no_match,no_match);
  if(!region.any_intersect)
    return result(*this,no_match); // subtract nothing => return this
  if(all_intersect) // subtract from entire circle => return opposite region
    return result(region.negation(),no_match);
  
  if(contains(region.start_theta)) {
    // Subtract a region which begins within this.
    
    if(contains(region.end_theta))
      // Subtract a region entirely within this. Two regions match.
      return result(AsteroidSearchResult(start_theta,region.start_theta),
                    AsteroidSearchResult(region.end_theta,end_theta));
    else
      // Subtract later part of this.
      return result(AsteroidSearchResult(start_theta,region.start_theta),
                    no_match);
  }
  
  if(region->contains(end_theta))
    // Subtract a region that is a superset of this; result is empty.
    return result(no_match,no_match);
  if(region->contains(start_theta))
    // Subtract a region that is the start half of this
    return result(AsteroidSearchResult(region.end_theta,end_theta),
                  no_match);

  // Subtract a region entirely outside of this.
  return result(*this,no_match);
}


pair<bool,AsteroidSearchResult>
AsteroidSearchResult::merge(const AsteroidSearchResult &one) const {
  typedef pair<bool,AsteroidSearchResult> result;
  if(all_intersect or region.all_intersect) // merge with entire circle => entire circle
    return result(true,all_intersect);
  if(!any_intersect) // merge with empty set => original set
    return result(true,one);
  if(!region.all_intersect) // merge with empty set => original set
    return result(true,*this);
  
  if(contains(region.start_theta)) {
    // Merge a region which begins within this.
    
    if(contains(region.end_theta))
      // Region is entirely within this, so we're adding nothing.
      return result(true,*this);
    else
      // Add to end of this.
      return result(true,AsteroidSearchResult(start_theta,one.end_theta));
  }
  
  if(region->contains(end_theta))
    // Add a region that is a superset of this; result is the other region.
    return result(true,one);
  if(region->contains(start_theta))
    // Subtract a region that is the start half of this
    return result(AsteroidSearchResult(region.end_theta,end_theta),
                no_match);

  // Cannot merge with a region that is entirely outside of this.
  return result(false,no_match);
}


AsteroidSearchResult AsteroidSearchResult::expanded_by(real_t dtheta) {
  if(all_intersect or !any_intersect or !dtheta)
    return *this;

  real_t theta_sum = 2*dtheta+theta_width;
  if(theta_sum>=TAUf) // expanded to full circle
    return all_match;
  if(theta_sum<=0) // shrunk to null set
    return no_match;

  return AsteroidSearchResult(start_theta-dtheta,end_theta+dtheta);
}

static void AsteroidSearchResult::merge_set(deque<AsteroidSearchResult> results) {
  if(results.size()<2)
    return;

  for(int loops_since_merge; loops_since_merge<results.size(); loops_since_merge++) {

    // Consider whether we can merge "mergeme" with anything in the deque.
    AsteroidSearchResult mergeme = results.pop_front();

    // Loop over all other elements of the deck. Check each one and remove it if we merged.
    for(auto checkme=results.begin();checkme!=results.end();) {

      // Can we merge these two elements?
      pair<bool,AsteroidSearchResult> check=checkme->merge(mergeme);
      if(check.first) {
        
        // Successful merge, so update our loop counter.
        loops_since_merge = 0;

        // Replace the range considered for merge with the new merged value.
        mergeme = check.second;

        if(mergeme.all_intersect) {
          // The new range includes everything. We're done.
          results.clear();
          break;
        } else
          // The new range is not all-inclusive, so we may not be done.
          checkme = results.erase(checkme);
      } else
        // Can't merge the elements, so check the next.
        checkme++;
    }
    
    results.push_back(mergeme);
  }
}

////////////////////////////////////////////////////////////////////////


AsteroidLayer::AsteroidLayer(const Dictionary &d):
  orbit_period(get<real_t>(d,"orbit_period")),
  orbit_mult(orbit_period ? TAUf/orbit_period : 1),
  inner_radius(max(0.0f,get<real_t>(d,"inner_radius"))),
  thickness(max(Asteroid::max_scale*3,get<real_t>(d,"thickness"))),
  outer_radius(inner_radius+thickness),
  spacing(max(Asteroid::min_scale,get<real_t>(d,"spacing",Asteroid::max_scale*2))),
  y(asteroid_height),
  asteroids(),
  state()
}

AsteroidLayer::~AsteroidLayer()
{}

int AsteroidLayer::find_theta(real_t theta) {
  real_t modded = fmodf(theta,TAUf);
  Asteroid findme(modded,0,0,0);
  vector<Asteroid>::iterator bound =
    lower_bound(asteroids.begin,asteroids.end,findme,
                [&](const Asteroid &a,const Asteroid &b) {
                  return a.theta<b.theta;
                });
  return bound==theta.end() ? 0 : bound-theta.begin();
}

pair<AsteroidSearchResult,AsteroidSearchResult>
AsteroidLayer::theta_ranges_of_ray(Vector2 start,Vector2 end) {
  real_t slen = start.length(), elen=end.length();

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

AsteroidSearchResult AsteroidLayer::theta_range_of_circle(Vector2 center,real_t search_radius) {
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
      real_t inner_range = fmodf(inner_angles.end_theta-inner_angles.start_theta,TAUf);
      real_t outer_range = fmodf(outer_angles.end_theta-outer_angles.start_theta,TAUf);
      return (inner_range>outer_range) ? inner_angles : outer_angles;
    } else
      return theta_from(inner1,inner2);
  } else if(intersect_outer)
    return theta_from(outer1,outer2);
  else
    return no_match;
}



bool AsteroidLayer::theta_ranges_of_rect(Rect2 rect,deque<AsteroidSearchResult> &results,dequeue<AsteroidSearchResult> &work1) {

  Vector2 points[5] = {
    rect.position,
    Vector2(rect.position.x+rect.size.x,rect.position.y),
    Vector2(rect.position.x+rect.size.x,rect.position.y+rect.size.y),
    Vector2(rect.position.x,rect.position.y+rect.size.y),
    rect.position
  };
  static const int xdir[4] = { -1, 0, 1, 0 };
  static const int ydir[4] = { 0, -1, 0, 1 };

  results.clear();
  
  {
    // Check for a common special case: rectangle is entirely within the inner circle.
    real_t ir2 = inner_radius*inner_radius;
    int within_inner=0;
    for(int i=0;i<4;i++)
      if(points[i].length_squared()<ir2)
        within_inner++;
    if(within_inner==4) {
      results.push_back(no_match);
      return false;
    }
  }
  
  work1.clear();
  for(int side=0;side<4;side++) {
    Vector2 *side_points=points+side;
    
    real_t dr;
    
    if(ydir)
      dr=ydir*side_points[0].y;
    else
      dr=xdir*side_points[0].x;

    if(dr>outer_radius) { // Case F
      // Entire annulus was removed.
      results.push_back(no_match);
      return false;
    } else if(dr<-inner_radius) // Cases A & B
      continue;
    else if(dr>0) { // Cases D & E
      Vector2 intersection[2];
      int n=line_intersect_circle(outer_radius,side_points,intersection);
      if(n>1)
        work1.push_back(longest_theta_from(intersection[0],intersection[1]));
    } else { // Case C
      Vector2 intersection[2];
      int n=line_intersect_circle(inner_radius,side_points,intersection);
      if(n>1)
        work1.push_back(shortest_theta_from(intersection[0],intersection[1]));
    }
  }

  if(!work1.empty()) {
    // At least one region was removed. What is left?
    results.push_back(all_match);
    
    for(auto &r : work1)
      for(auto it=results.begin();it!=results.end();) {
        pair<AsteroidSearchResult,AsteroidSearchResult> minused=work1->minus(*it);
        if(minused.first.no_intersection) {
          it++;
          continue;
        }
        *it = minused.first;
        if(minused.second.no_intersection)
          continue;
        it.push_back(minused.second);
      }

    AsteroidSearchResult::merge_set(results);
    switch(results.size()) {
    case 0:
      return false; // should never happen
    case 1:
      return !results.front().no_intersection;
    default:
      return true;
    }
  }

  return work1.empty();
}

void AsteroidLayer::generate_field(const AsteroidPalette &palette,CheapRand32 &rand) {
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
      real_t theta_needed_here = check_width/check_radius * TAUf;
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
  } while(theta<TAUf);

  state.resize(asteroids);

  // FIXME: This should not be needed since the asteroids were generated in sorted order.
  sort_asteroids();
}


void AsteroidLayer::sort_asteroids() {
  std::sort(asteroids.begin(),asteroids.end(),[&](const Asteroid &a,const Asteroid &b) {
      return a.theta<b.theta;
    });
}

////////////////////////////////////////////////////////////////////////

AsteroidField::AsteroidField(double now,Array data,std::shared_ptr<AsteroidPalette> asteroids,
                             std::shared_ptr<SalvagePalette> salvege):
  palette(asteroids),
  salvate(salvage),
  layers(),
  now(now),
  dead_asteroids()
{
  layers.reserve(data.size);
  for(int i=0,e=data.size();i<e;i++) {
    Variant v=data[i];
    if(v.get_type() != Variant::DICTIONARY) {
      godot::print_warning("Ignoring non-dictionary in AsteroidField data.",
                           __FUNCTION__,__FILE__,__LINE__);
      continue;
    }
    layers.emplace_back(static_cast<Dictionary>(v));
  }
  if(!layers.size())
    godot::print_error("No asteroid layers in AsteroidField!",
                       __FUNCTION__,__FILE__,__LINE__);
}

AsteroidField::~AsteroidField();

void AsteroidField::generate_field(CheapRand32 &rand) {
  for(auto &layer : layers)
    layer.generate_field(palette,rand);
}

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

bool AsteroidField::is_alive(object_id id) const {
  pair<int,int> split = split_id(id);
  if(split.first<0 or split.first>=layers.size())
    return false;

  Asteroid *asteroid = layers[split.first].get_asteroid(split.second);
  if(!asteroid)
    return false;

  return asteroid->is_alive();
}

void AsteroidField::step_time(int64_t idelta,real_t delta,Rect2 visible_region) {
  now+=delta;
  real_t rnow = now;

  Rect2 search_region = visible_region.expand(Asteroid.max_scale+1);

  for(auto it=dead_asteroids.begin();it!=dead_asteroids.end();) {
    object_id id = *it;
    pair<int,int> split = split_id(id);
    if(split.first>=0 and split.first<layers.size()) {
      AsteroidLayer &layer = layers[split.first];
      Asteroid *asteroid = layer.get_asteroid(split.second);
      
      if(!asteroid or asteroid->is_alive())
        continue;

      // Only spawn a new asteroid if this one is off screen.
      AsteroidState *state = layer.get_valid_state(split.second,asteroid,rnow);
      if(!state or search_region.has_point(asteroid->get_xy(*state)))
        continue;

      // Replace the asteroid's stats
      asteroid->set_template(palette.random_choice());

      // Ensure the state is reinitialized next time it is needed.
      state->reset();
    }
  }
}

void AsteroidField::add_content(Rect2 visible_region,VisibleContent &content) const {
  deque<AsteroidSearchResult> found;

  // Search a slightly larger region due to asteroid scaling.
  Rect2 search_region = visible_region.expand(Asteroid.max_scale+1);
  real_t valid_time = now;

  // Search each layer.
  for(auto &layer : layers) {
    found.clear();

    // What theta ranges does this rect overlap?
    if(layer.theta_ranges_of_rect(search_region,found)) {
      real_t theta0 = layer.theta_time_shift(now);
      for(auto &range : found) {
        if(!range.any_intersect)
          continue;

        // What range of indices do we search?
        int itheta1, itheta2;
        if(range.all_intersect)
          itheta1 = itheta2 = 0;
        else {
          int itheta1 = found.find_theta(range.start_theta+theta0);
          int itheta2 = found.find_theta(range.end_theta+theta0);
        }

        // Search all indices within the range.
        int itheta = itheta1-1;
        do {
          // Go to the next index. This may need to loop around the end of the array.
          itheta = (itheta+1)%layer.size();

          // Get the asteroid and its up-to-date state.
          const Asteroid *a = layer.get_asteroid(itheta);
          if(!a or !a->is_visible())
            continue;
          
          const AsteroidState *s = layer.get_valid_state(itheta,a,valid_time);
          if(!s)
            continue;

          if(!search_region.has_point(a->get_xz(state)))
            continue;

          // Get the template, for its mesh id and color
          const shared_ptr<const AsteroidTemplate> *t = a->get_template();
          if(!t)
            continue;

          // Calculate the transform, and put everything in a new InstanceEffect
          content->instances.push_back(InstanceEffect {
              t->get_mesh_id(), a->calculate_transform(*s),
                t->get_color_data(), s->get_instance_data() });
        } while(itheta!=itheta1);
      }
    }
  }
}

std::size_t AsteroidField::overlapping_circle(Vector2 center,real_t radius,std::unordered_set<object_id> &results) const {
  size_t count=0;
  real_t expanded_radius = radius+Asteroid.max_scale+1;
  real_t radius_squared = radius*radius;
  for(int ilayer = 0;ilayer<layers.size();ilayer++) {
    AsteroidLayer &layer = layers[ilayer];
    AsteroidSearchResult range = layer.theta_range_of_circle(center,search_radius);

    // What range of indices do we search?
    int itheta1, itheta2;
    if(range.all_intersect)
      itheta1 = itheta2 = 0;
    else {
      int itheta1 = found.find_theta(range.start_theta+theta0);
      int itheta2 = found.find_theta(range.end_theta+theta0);
    }
    
    // Search all indices within the range.
    int itheta = itheta1-1;
    do {
      // Go to the next index. This may need to loop around the end of the array.
      itheta = (itheta+1)%layer.size();
      
      // Get the asteroid and its up-to-date state.
      const Asteroid *a = layer.get_asteroid(itheta);
      if(!a)
        continue;
      const AsteroidState *s = layer.get_valid_state(itheta,a,valid_time);
      if(!s)
        continue;

      real_t combined_radius = a->calculate_scale(state)+radius;

      if(center.distance_squared_to(Vector2(a->get_xz(state)))<=combined_radius*combined_radius) {
        results.push_back(combined_id(ilayer,itheta));
        count++;
      }
    } while(itheta!=itheta1);
  }
  return count;
}

object_id AsteroidField::first_in_circle(Vector2 center,real_t radius) const {
  real_t expanded_radius = radius+Asteroid.max_scale+1;
  real_t radius_squared = radius*radius;
  for(int ilayer = 0;ilayer<layers.size();ilayer++) {
    AsteroidLayer &layer = layers[ilayer];
    AsteroidSearchResult range = layer.theta_range_of_circle(center,search_radius);

    // What range of indices do we search?
    int itheta1, itheta2;
    if(range.all_intersect)
      itheta1 = itheta2 = 0;
    else {
      int itheta1 = found.find_theta(range.start_theta+theta0);
      int itheta2 = found.find_theta(range.end_theta+theta0);
    }
    
    // Search all indices within the range.
    int itheta = itheta1-1;
    do {
      // Go to the next index. This may need to loop around the end of the array.
      itheta = (itheta+1)%layer.size();
      
      // Get the asteroid and its up-to-date state.
      const Asteroid *a = layer.get_asteroid(itheta);
      if(!a)
        continue;
      const AsteroidState *s = layer.get_valid_state(itheta,a,valid_time);
      if(!s)
        continue;

      real_t combined_radius = a->calculate_scale(state)+radius;

      if(center.distance_squared_to(Vector2(a->get_xz(state)))<=combined_radius*combined_radius)
        return combined_id(ilayer,itheta);
    } while(itheta!=itheta1);
  }
  return -1;
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

    if(ranges[0].all_intersect or ranges[1].all_intersect)
      loop_end=0;

    int loop_start=0,loop_end=1;

    if(!ranges[0].any_intersect)
      loop_start=1;
    if(!ranges[1].any_intersect)
      loop_end=0;
    
    for(irange=loop_start;irange<=loop_end;irange++) {
      AsteroidSearchResult range = ranges[irange].expanded_by(Asteroid::max_scale/layer.inner_radius);
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
