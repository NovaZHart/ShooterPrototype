#include <cmath>

#include <Variant.hpp>

#include "CE/Utils.hpp"
#include "CE/VisibleContent.hpp"
#include "CE/AsteroidField.hpp"
#include "CE/CheapRand32.hpp"
#include "CE/CombatEngine.hpp"
#include "CE/Salvage.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

// Convenience functions and constants that are object-local.

static const AsteroidSearchResult no_match = AsteroidSearchResult::no_match;
static const AsteroidSearchResult all_match = AsteroidSearchResult::all_match;

static real_t theta_from_vector(Vector2 v) {
  return fmod(angle_from_unit(v)+20*TAU,TAU);
}

////////////////////////////////////////////////////////////////////////

static AsteroidSearchResult theta_from(Vector2 a,Vector2 b) {
  return AsteroidSearchResult(theta_from_vector(a), theta_from_vector(b));
}

////////////////////////////////////////////////////////////////////////

static AsteroidSearchResult shortest_theta_from(Vector2 a,Vector2 b) {
  AsteroidSearchResult r(angle_from_unit(a), angle_from_unit(b));
  real_t size = fmod(r.get_end_theta()-r.get_start_theta()+20*TAU,TAU);
  return (size>PIf) ? r.negation() : r;
}

////////////////////////////////////////////////////////////////////////

static AsteroidSearchResult longest_theta_from(Vector2 a,Vector2 b) {
  AsteroidSearchResult r(angle_from_unit(a), angle_from_unit(b));
  real_t size = fmod(r.get_end_theta()-r.get_start_theta()+20*TAU,TAU);
  return (size<PIf) ? r.negation() : r;
}

////////////////////////////////////////////////////////////////////////

const AsteroidSearchResult AsteroidSearchResult::no_match = AsteroidSearchResult(false);
const AsteroidSearchResult AsteroidSearchResult::all_match = AsteroidSearchResult(true);

////////////////////////////////////////////////////////////////////////

pair<AsteroidSearchResult,AsteroidSearchResult>
AsteroidSearchResult::minus(const AsteroidSearchResult &region) const {
  FAST_PROFILING_FUNCTION;
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
    
    if(contains(region.end_theta)) {
      if(region.contains(start_theta))
        // Subtract a region that contains the edges of this. Return
        // negation of result.
        return result(region.negation(),no_match);
      else
        // Subtract a region entirely within this. Two regions match.
        return result(AsteroidSearchResult(start_theta,region.start_theta),
                      AsteroidSearchResult(region.end_theta,end_theta));
    } else
      // Subtract later part of this.
      return result(AsteroidSearchResult(start_theta,region.start_theta),
                    no_match);
  }
  
  if(region.contains(end_theta))
    // Subtract a region that is a superset of this; result is empty.
    return result(no_match,no_match);
  if(region.contains(start_theta))
    // Subtract a region that is the start half of this
    return result(AsteroidSearchResult(region.end_theta,end_theta),
                  no_match);

  // Subtract a region entirely outside of this.
  return result(*this,no_match);
}

////////////////////////////////////////////////////////////////////////

pair<bool,AsteroidSearchResult>
AsteroidSearchResult::merge(const AsteroidSearchResult &region) const {
  FAST_PROFILING_FUNCTION;
  typedef pair<bool,AsteroidSearchResult> result;
  if(all_intersect or region.all_intersect) // merge with entire circle => entire circle
    return result(true,all_intersect);
  if(!any_intersect) // merge with empty set => original set
    return result(true,region);
  if(!region.all_intersect) // merge with empty set => original set
    return result(true,*this);
  
  if(contains(region.start_theta)) {
    // Merge a region which begins within this.
    
    if(contains(region.end_theta))
      // Region is entirely within this, so we're adding nothing.
      return result(true,*this);
    else
      // Add to end of this.
      return result(true,AsteroidSearchResult(start_theta,region.end_theta));
  }
  
  if(region.contains(end_theta))
    // Add a region that is a superset of this; result is the other region.
    return result(true,region);
  if(region.contains(start_theta))
    // Add a region that is the start half of this
    return result(true,AsteroidSearchResult(region.start_theta,end_theta));

  // Cannot merge with a region that is entirely outside of this.
  return result(false,no_match);
}

////////////////////////////////////////////////////////////////////////

AsteroidSearchResult AsteroidSearchResult::expanded_by(real_t dtheta) {
  FAST_PROFILING_FUNCTION;
  if(all_intersect or !any_intersect or !dtheta)
    return *this;

  real_t theta_sum = 2*dtheta+theta_width;
  if(theta_sum>=TAUf) // expanded to full circle
    return all_match;
  if(theta_sum<=0) // shrunk to null set
    return no_match;

  return AsteroidSearchResult(start_theta-dtheta,end_theta+dtheta);
}

////////////////////////////////////////////////////////////////////////

void AsteroidSearchResult::merge_set(deque<AsteroidSearchResult> results) {
  FAST_PROFILING_FUNCTION;
  if(results.size()<2)
    return;

  for(size_t loops_since_merge=0; loops_since_merge<results.size(); loops_since_merge++) {

    // Consider whether we can merge "mergeme" with anything in the deque.
    AsteroidSearchResult mergeme = results.front();
    results.pop_front();

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

pair<AsteroidSearchResult,AsteroidSearchResult>
AsteroidSearchResult::theta_ranges_of_ray(Vector2 start,Vector2 end,real_t inner_radius,real_t outer_radius) {
  FAST_PROFILING_FUNCTION;
  typedef pair<AsteroidSearchResult,AsteroidSearchResult> result;
  real_t slen = start.length(), elen=end.length();

  int intersect_inner=0, intersect_outer=0;
  Vector2 line[2] = { start,end };
  
  if(slen<inner_radius) {
    // Start inside inner circle.
    if(elen<inner_radius)
      // Start and end entirely within inner circle. No match.
      return result(no_match,no_match);
    else if(elen>outer_radius) {
      // Start inside inner, end outside outer. Match the range of
      // intersection from inner to outer.
      Vector2 outer[2];
      intersect_outer = line_segment_intersect_circle(outer_radius,line,outer);
      Vector2 inner[2];
      intersect_inner = line_segment_intersect_circle(inner_radius,line,inner);
      if(intersect_inner and intersect_outer) {
        return result(shortest_theta_from(inner[0],outer[0]),no_match);
      }
     
      // Should not reach this line.
    } else {
      // Start inside the inner circle, end within the annulus.
      // Match from inner intersection to end point.
      Vector2 inner[2];
      intersect_inner = line_segment_intersect_circle(inner_radius,line,inner);
      if(intersect_inner)
        return result(shortest_theta_from(inner[0],end),no_match);
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

      Vector2 outer[2];
      intersect_outer = line_segment_intersect_circle(outer_radius,line,outer);
      if(intersect_outer<2) {
        // Ray is entirely outside the outer circle. No match.
        return result(no_match,no_match);
      }

      Vector2 inner[2];
      intersect_inner = line_segment_intersect_circle(inner_radius,line,inner);
      if(intersect_inner<2) {
        // Ray passes within annulus, but not through inner circle.
        // Match the range between the outer matches.
        return result(shortest_theta_from(outer[0],outer[1]),no_match);
      }

      // Ray passes through the inner and outer circles. There are two regions that match.
      return result(shortest_theta_from(outer[0],inner[0]),shortest_theta_from(inner[1],outer[1]));
    } else if(elen<inner_radius) {
      // Start outside, end inside. Match the range from inner to outer intersection.
      Vector2 inner[2];
      intersect_inner = line_segment_intersect_circle(inner_radius,line,inner);
      Vector2 outer[2];
      intersect_outer = line_segment_intersect_circle(outer_radius,line,outer);
      if(intersect_inner and intersect_outer)
        return result(shortest_theta_from(inner[0],outer[0]),no_match);
      // Should not reach this line.      
    } else {
      // Start outside outer, end within annulus. Match the range from outer intersection to end point
      Vector2 inner[2];
      intersect_inner = line_segment_intersect_circle(inner_radius,line,inner);
      
      Vector2 outer[2];
      intersect_outer = line_segment_intersect_circle(outer_radius,line,outer);

      if(intersect_inner==2) {
        return result(shortest_theta_from(outer[0],inner[0]),
                      shortest_theta_from(inner[1],end));
      } else if(intersect_outer)
        return result(shortest_theta_from(outer[0],end),no_match);
      // Should not reach this line.
    }
  } else {
    // Start inside the annulus
    if(elen>outer_radius) {
      // Start inside annulus, end outside the outer circle. Range is start point to outer intersection.
      Vector2 outer[2];
      intersect_outer = line_segment_intersect_circle(outer_radius,line,outer);
      if(intersect_outer)
        return result(shortest_theta_from(start,outer[0]),no_match);
      // Should never reach this line.
    } else if(elen<inner_radius) {
      // Start inside annulus, end inside the inner circle. Range is start point to inner intersection.
      Vector2 inner[2];
      intersect_inner = line_segment_intersect_circle(inner_radius,line,inner);
      if(intersect_inner)
        return result(shortest_theta_from(start,inner[0]),no_match);
      // Should never reach this line.
    } else {
      // Possibilities:
      // 0-1 intersections with inner circle = range from start to end
      // 2 intersections with inner circle = two matching ranges
      Vector2 inner[2];
      intersect_inner = line_segment_intersect_circle(inner_radius,line,inner);
      if(intersect_inner<2)
        // Ray lies entirely within the annulus.
        return result(shortest_theta_from(start,end),no_match);

      // Ray covers two areas within annulus saddling the inner circle
      return result(shortest_theta_from(start,inner[0]),shortest_theta_from(inner[1],end));
    }
  }
  
  // Should not reach this line.
  return result(no_match,no_match);
}

////////////////////////////////////////////////////////////////////////

AsteroidSearchResult AsteroidSearchResult::theta_range_of_circle(Vector2 center,real_t search_radius,real_t inner_radius,real_t outer_radius) {
  FAST_PROFILING_FUNCTION;
  real_t clen = center.length();
  
  // Check for special cases.

  // Circle is entirely within inner circle or beyond outer circle.
  if(search_radius+clen<inner_radius or clen-search_radius>outer_radius) {
    // Special case 1: circle lies entirely inside the inner circle of the annulus (no intersection)
    return no_match;
  }
  if(search_radius-clen>=inner_radius and search_radius+clen<=outer_radius) {
    // Special case 2: circle lies entirely within the annulus and contains origin (all points match)
    return all_match;
  }
  if(search_radius-clen>=inner_radius) {
    // Special case 3: circle entirely encloses annulus (all points match)
    return all_match;
  }
  if(clen-search_radius>=inner_radius and clen+search_radius<=outer_radius) {
    // Special case 2: circle lies entirely within the annulus but does not contain origin (all points match)
    real_t theta_halfwidth = atanf(search_radius/center.length());
    real_t mid_theta = angle_from_unit(center);
    return AsteroidSearchResult(mid_theta-theta_halfwidth,mid_theta+theta_halfwidth);
  }

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
      real_t inner_range = fmodf(inner_angles.get_end_theta()-inner_angles.get_start_theta()+20*TAUf,TAUf);
      real_t outer_range = fmodf(outer_angles.get_end_theta()-outer_angles.get_start_theta()+20*TAUf,TAUf);
      return (inner_range>outer_range) ? inner_angles : outer_angles;
    } else
      return theta_from(inner1,inner2);
  } else if(intersect_outer)
    return theta_from(outer1,outer2);
  else
    return no_match;
}

////////////////////////////////////////////////////////////////////////

bool AsteroidSearchResult::rect_entirely_outside_annulus(Rect2 rect,real_t inner_radius,real_t outer_radius) {
  FAST_PROFILING_FUNCTION;

  Vector2 points[5] = {
    rect.position,
    Vector2(rect.position.x+rect.size.x,rect.position.y),
    Vector2(rect.position.x+rect.size.x,rect.position.y+rect.size.y),
    Vector2(rect.position.x,rect.position.y+rect.size.y),
    rect.position
  };

  // Check for common special cases:
  //   - rectangle is entirely within the inner circle.
  //   - rectangle is entirely outside the outer_circle.
  {
    real_t ir2 = inner_radius*inner_radius;
    real_t or2 = outer_radius*outer_radius;
    int within_inner=0, outside_outer=0;
    for(int i=0;i<4;i++) {
      if(points[i].length_squared()<ir2)
        within_inner++;
      else if(points[i].length_squared()>or2)
        outside_outer++;
    }
    if(within_inner==4) {
      // Rectangle is entirely inside the inner circle, so overlap is impossible.
      return true;
    }

    if(outside_outer==4) {
      // All four points are outside the outer circle.
      // BUT: the rectangle may still overlap.

      // What quadrant are the points in?
      real_t quadrant[4];
      for(int i=0;i<4;i++)
        quadrant[i] = copysignf(1,points[i].x) + copysignf(2,points[i].y);

      if(quadrant[0]==quadrant[1] and quadrant[1]==quadrant[2] and quadrant[2]==quadrant[3]) {
        // All points of the rectangle are outside the outer circle
        // and in the same quadrant, so overlap is impossible.
        return true;
      }
    }
  }
  return false;
}

////////////////////////////////////////////////////////////////////////

bool AsteroidSearchResult::theta_ranges_of_rect(Rect2 rect,deque<AsteroidSearchResult> &results,deque<AsteroidSearchResult> &work1,real_t inner_radius,real_t outer_radius) {
  FAST_PROFILING_FUNCTION;

  Vector2 points[5] = {
    rect.position,
    Vector2(rect.position.x+rect.size.x,rect.position.y),
    Vector2(rect.position.x+rect.size.x,rect.position.y+rect.size.y),
    Vector2(rect.position.x,rect.position.y+rect.size.y),
    rect.position
  };
  static const int xdir[4] = { 0, 1, 0, -1 };
  static const int ydir[4] = { -1, 0, 1, 0 };

  results.clear();

  int within_annulus=0; // How many points are between the inner and outer radii?
    
  // Check for common special cases:
  //   - rectangle is entirely within the inner circle.
  //   - rectangle is entirely outside the outer_circle.
  {
    real_t ir2 = inner_radius*inner_radius;
    real_t or2 = outer_radius*outer_radius;
    int within_inner=0, outside_outer=0, segment_outside_inner=0;
    for(int i=0;i<4;i++) {
      if((xdir[i] && fabsf(points[i].y)>inner_radius) or
         (ydir[i] && fabsf(points[i].y)>inner_radius))
        segment_outside_inner++;
      if(points[i].length_squared()<ir2)
        within_inner++;
      else if(points[i].length_squared()>or2)
        outside_outer++;
      else
        within_annulus++;
    }
    if(within_inner==4) {
      // Rectangle is entirely inside the inner circle, so overlap is impossible.
      results.push_back(no_match);
      return false;
    }

    if(outside_outer==4 or segment_outside_inner==4) {
      // All four points are outside the outer circle.
      // BUT: the rectangle may still overlap.

      // What quadrant are the points in?
      real_t quadrant[4];
      for(int i=0;i<4;i++)
        quadrant[i] = copysignf(1,points[i].x) + copysignf(2,points[i].y);
      
      if(outside_outer==4 && quadrant[0]==quadrant[1] and quadrant[1]==quadrant[2] and quadrant[2]==quadrant[3]) {
        // All points of the rectangle are outside the outer circle
        // and in the same quadrant, so overlap is impossible.
        results.push_back(no_match);
        return false;
      }

      if(segment_outside_inner==4 &&
         quadrant[0]!=quadrant[1] && quadrant[0]!=quadrant[2] && quadrant[0]!=quadrant[3] &&
         quadrant[1]!=quadrant[2] && quadrant[1]!=quadrant[3] && quadrant[2]!=quadrant[3]) {
        // Special case: entire inner circle is within the rect
        results.push_back(all_match);
        return true;
      }
    }

  }

  if(within_annulus==4) {
    // All points are within the annulus. Are all line segments within the annulus?
    int segments_within=0;
    for(int i=0;i<4;i++) {
      Vector2 intersection[2];
      if(!line_segment_intersect_circle(inner_radius,points+i,intersection))
        segments_within++;
    }
    if(segments_within==4) {
      // Easy special case. All segments are in the annulus, so we
      // look at the segment theta ranges.
      for(int i=0;i<4;i++)
        results.push_back(shortest_theta_from(points[i],points[i+1]));
      AsteroidSearchResult::merge_set(results);
      return true;
    }
  }
  
  // Find all regions that should NOT be in the intersection, and put them in the work1 array.
  work1.clear();
  for(int side=0;side<4;side++) {
    Vector2 *side_points=points+side;
    
    real_t dr;
    real_t dir;
    Vector2 flip(1,1);
    if(ydir[side]) {
      //flip.y=ydir[side];
      dir=ydir[side];
      dr=-dir*side_points[0].y;
    } else {
      //flip.x=xdir[side];
      dir=xdir[side];
      dr=-dir*side_points[0].x;
    }
    
    if(dr>outer_radius) { // Case F
      // Entire annulus was removed.
      results.push_back(no_match);
      return false;
    } else if(dr<-inner_radius) { // Cases A & B
      continue;
    } else if(fabsf(dr)<1e-5) {
      Vector2 intersection[2];
      line_intersect_circle(inner_radius,side_points,intersection);
      work1.push_back(theta_from(intersection[1],intersection[0]));
    } else if(dr>0) { // Cases D & E
      Vector2 intersection[2];
      int n=line_intersect_circle(outer_radius,side_points,intersection);
      if(n>1) {
        intersection[0]*=flip;
        intersection[1]*=flip;
        if(dir<0)
          swap(intersection[0],intersection[1]);
        work1.push_back(longest_theta_from(intersection[0],intersection[1]));
      }
    } else { // Case C
      Vector2 intersection[2];
      int n=line_intersect_circle(inner_radius,side_points,intersection);
      if(n>1) {
        intersection[0]*=flip;
        intersection[1]*=flip;
        if(dir<0)
          swap(intersection[0],intersection[1]);
        work1.push_back(shortest_theta_from(intersection[0],intersection[1]));
      }
    }
  }

  // Starting with the universal set in results, subtract from
  // "results" each region of work1.
  if(!work1.empty()) {
    // At least one region was removed. What is left?
    results.push_back(all_match);
    
    for(auto &r : work1) {
      for(auto it=results.begin();it!=results.end();) {
        pair<AsteroidSearchResult,AsteroidSearchResult> minused=it->minus(r);
        if(!minused.first.get_any_intersect()) {
          // Entirely eliminated this range.
          it=results.erase(it);
          continue;
        }
        *it = minused.first;
        if(!minused.second.get_any_intersect()) {
          // Reduce the size of this range.
          it++;
          continue;
        }
        // Range was split in two. Push to the front so we don't loop over this new location.
        results.push_front(minused.second);
        it++;
      }
    }
    
    AsteroidSearchResult::merge_set(results);
    switch(results.size()) {
    case 0:
      return false; // should never happen
    case 1:
      return results.front().get_any_intersect();
    default:
      return true;
    }
  }
  return work1.empty();
}

////////////////////////////////////////////////////////////////////////


AsteroidLayer::AsteroidLayer(const Dictionary &d):
  inner_radius(max(0.0f,get<real_t>(d,"inner_radius"))),
  y(asteroid_height),
  max_rotation_speed(max(0.0f,get<real_t>(d,"max_rotation_speed",TAUf/4))),
  min_scale(max(0.01f,get<real_t>(d,"min_scale",0.4))),
  max_scale(max(min_scale,get<real_t>(d,"max_scale",1.4))),
  scale_range(max_scale-min_scale),
  thickness(max(max_scale*3,get<real_t>(d,"thickness"))),
  outer_radius(inner_radius+thickness),
  spacing(max(min_scale,get<real_t>(d,"spacing",max_scale*2))),
  mean_velocity(get<real_t>(d,"mean_velocity")),
  orbit_period(TAUf*(inner_radius+thickness/2)/mean_velocity),
  orbit_mult(orbit_period ? TAUf/orbit_period : 1),
  asteroids(),
  state()
{}

////////////////////////////////////////////////////////////////////////

AsteroidLayer::~AsteroidLayer()
{}

////////////////////////////////////////////////////////////////////////

int AsteroidLayer::find_theta(real_t theta) const {
  FAST_PROFILING_FUNCTION;
  real_t modded = fmod(theta+20*TAU,TAU);
  Asteroid findme(modded,0,0,0);
  struct compare {
    bool operator () (const Asteroid &a,const Asteroid &b) {
      return a.theta<b.theta;
    }
  };
  vector<Asteroid>::const_iterator bound =
    lower_bound(asteroids.begin(),asteroids.end(),findme,compare());
  return bound==asteroids.end() ? 0 : bound-asteroids.begin();
}

////////////////////////////////////////////////////////////////////////

std::pair<object_id,object_id> AsteroidLayer::find_theta_range(const AsteroidSearchResult &range,double when) const {
  FAST_PROFILING_FUNCTION;
  // What range of indices do we search?

  if(!range.get_any_intersect())
    return std::pair<object_id,object_id>(0,0);

  int itheta1=0, itheta2=0;
  if(!range.get_all_intersect()) {
    real_t theta0 = when*orbit_mult;
    itheta1 = find_theta(range.get_start_theta()+theta0);
    itheta2 = find_theta(range.get_end_theta()+theta0);
  }
  
  if(itheta1==itheta2)
    itheta1 = (itheta2+1)%size();

  return std::pair<object_id,object_id>(itheta1,itheta2);
}

////////////////////////////////////////////////////////////////////////

void AsteroidLayer::generate_field(const AsteroidPalette &palette,CheapRand32 &rand) {
  FAST_PROFILING_FUNCTION;
  real_t annulus_area = PIf*(outer_radius*outer_radius-inner_radius*inner_radius);
  real_t spacing_area = PIf*spacing*spacing;
  asteroids.reserve(max(1.0f,ceilf(annulus_area/spacing_area)));
  
  asteroids.clear();
  state.clear();
  
  real_t trimmed_thickness = thickness-2*max_scale;
  real_t theta_step = spacing/outer_radius/4;
    
  real_t radius_step = max(0.2f,max_scale*0.1f);
  int radius_count = max(1,int(ceilf(trimmed_thickness/radius_step)));
  vector<real_t> last_theta_used(radius_count,-9e9f);
  vector<real_t> radius_of_bin(radius_count,0);
  vector<real_t> next_theta_used(radius_count,0);
  int asteroid_tries=max(1,radius_count/5);
  int radii_to_check = ceilf(spacing/(radius_step*2))*2;
  
  {
    real_t radius = inner_radius+max_scale;
    for(int i=0;i<radius_count;i++,radius+=radius_step)
      radius_of_bin[i]=radius;
  }

  real_t theta = 0;
  do {
    int placed = 0;
    for(int tries=0;tries<asteroid_tries;tries++) {
      // Randomly choose a radius bin to try to place an asteroid.
      int bin = rand.randi()%radius_count;
      real_t radius = radius_of_bin[bin];

      // Will it fit?
      bool too_big = false;
      int first_check = max(0,bin-radii_to_check/2);
      int last_check = min(radius_count-1,bin+radii_to_check/2);
      for(int check_bin=first_check;check_bin<=last_check;check_bin++) {
        real_t check_radius = radius_of_bin[check_bin];
        real_t y = radius-check_radius;
        real_t check_width = sqrtf(spacing*spacing-y*y);
        real_t theta_needed_here = atanf(check_width/check_radius);
        if(theta-last_theta_used[check_bin]<theta_needed_here) {
          too_big=true;
          break;
        }
        // This part of the asteroid fits, so record the next value for
        // theta_used in case we decide to use this asteroid.
        next_theta_used[check_bin] = theta_needed_here+theta;
      }

      if(!too_big) {
        placed++;
        // The asteroid fits. Update the last_theta_used and insert a new asteroid.
        for(int check_bin=first_check;check_bin<=last_check;check_bin++)
          last_theta_used[check_bin] = next_theta_used[check_bin];

        real_t ay = rand.randf()*30-40;

        asteroids.emplace_back(theta,radius-inner_radius,ay,palette.random_choice(rand));
        break;
      }
    }
    if(!placed) {
      real_t maxlast=-9e9;
      real_t minlast=9e9;
      for(auto &t : last_theta_used) {
        maxlast=max(maxlast,t);
        minlast=min(minlast,t);
      }
    }
    theta += theta_step;
  } while(theta<TAUf);

  state.resize(asteroids.size());
}

////////////////////////////////////////////////////////////////////////

AsteroidField::AsteroidField(double now,Array data,std::shared_ptr<AsteroidPalette> asteroids,
                             std::shared_ptr<SalvagePalette> salvage):
  palette(*asteroids,true),
  rand(),
  salvage(salvage),
  layers(),
  now(now),
  dead_asteroids(),
  sent_meshes(false)
{
  FAST_PROFILING_FUNCTION;
  layers.reserve(data.size());
  for(int i=0,e=data.size();i<e;i++) {
    Variant v=data[i];
    if(v.get_type() != Variant::DICTIONARY) {
      Godot::print_warning("Ignoring non-dictionary in AsteroidField data.",
                           __FUNCTION__,__FILE__,__LINE__);
      continue;
    }
    layers.emplace_back(static_cast<Dictionary>(v));
  }

  if(layers.size()) {
    inner_radius=numeric_limits<real_t>::infinity();
    outer_radius=-numeric_limits<real_t>::infinity();
    max_scale=-numeric_limits<real_t>::infinity();
    for(auto &layer : layers) {
      inner_radius = min(inner_radius,layer.get_inner_radius());
      outer_radius = max(outer_radius,layer.get_outer_radius());
      max_scale = max(max_scale,layer.get_max_scale());
    }
  } else {
    Godot::print_error("No asteroid layers in AsteroidField!",
                       __FUNCTION__,__FILE__,__LINE__);
    inner_radius = 100;
    outer_radius = 100.1;
    max_scale = 1;
  }
  thickness = outer_radius-inner_radius;
}

////////////////////////////////////////////////////////////////////////

AsteroidField::~AsteroidField()
{}

////////////////////////////////////////////////////////////////////////

void AsteroidField::generate_field() {
  for(auto &layer : layers)
    layer.generate_field(palette,rand);
}

////////////////////////////////////////////////////////////////////////

AsteroidField::const_iterator AsteroidField::find(object_id id) const {
  pair<int,int> split = split_id(id);
  if(split.first<0 or static_cast<size_t>(split.first)>=layers.size())
    return end();
  return const_iterator(this,id);
}

////////////////////////////////////////////////////////////////////////

pair<const Asteroid *,const AsteroidState*> AsteroidField::get(object_id id) const {
  FAST_PROFILING_FUNCTION;
  static const pair<const Asteroid*,const AsteroidState*> no_match(nullptr,nullptr);
  
  pair<int,int> split = split_id(id);
  if(split.first<0 or static_cast<size_t>(split.first)>=layers.size())
    return no_match;

  const Asteroid *asteroid = layers[split.first].get_asteroid(split.second);
  if(!asteroid)
    return no_match;

  const AsteroidState *state = layers[split.first].get_valid_state(split.second,asteroid,now);

  return pair(asteroid,state);
}

////////////////////////////////////////////////////////////////////////

double AsteroidField::damage_asteroid(CombatEngine &ce,object_id id,double damage) {
  FAST_PROFILING_FUNCTION;
  pair<int,int> split = split_id(id);
  if(split.first<0 or static_cast<size_t>(split.first)>=layers.size())
    return damage;

  AsteroidLayer &layer = layers[split.first];
  Asteroid *asteroid = layer.get_asteroid(split.second);
  if(!asteroid)
    return damage;

  double remaining = asteroid->take_damage(damage);

  if(!asteroid->is_alive()) {
    // Mark the asteroid as dead so we make a new one later.
    dead_asteroids.insert(id);

    // If the asteroid had cargo, make flotsam.
    std::shared_ptr<const Salvage> salvage_ptr = salvage->get_salvage(asteroid->get_cargo());
    if(salvage_ptr) {
      AsteroidState *state = layer.get_valid_state(split.second,asteroid,now);
      if(state) {
        real_t r = asteroid->get_r()+layer.inner_radius;
        real_t speed = r*layer.orbit_mult;
        Vector3 position = asteroid->get_x0z(*state);
        Vector3 pnorm = position.normalized();
        Vector3 velocity(-pnorm.z*speed,0,pnorm.x*speed);
        ce.create_flotsam_projectile(nullptr,salvage_ptr,position,ce.rand_angle(),velocity,FLOTSAM_MASS);
      }
    }
    return remaining;
  } else
    return 0;
}

////////////////////////////////////////////////////////////////////////

bool AsteroidField::is_alive(object_id id) const {
  FAST_PROFILING_FUNCTION;
  pair<int,int> split = split_id(id);
  if(split.first<0 or static_cast<size_t>(split.first)>=layers.size())
    return false;

  const Asteroid *asteroid = layers[split.first].get_asteroid(split.second);
  if(!asteroid)
    return false;

  return asteroid->is_alive();
}

////////////////////////////////////////////////////////////////////////

void AsteroidField::step_time(int64_t idelta,real_t delta,Rect2 visible_region) {
  FAST_PROFILING_FUNCTION;
  now+=delta;
  real_t rnow = now;

  Rect2 search_region = visible_region.grow(max_scale+1);

  for(auto it=dead_asteroids.begin();it!=dead_asteroids.end();) {
    object_id id = *it;
    pair<int,int> split = split_id(id);
    if(split.first>=0 and static_cast<size_t>(split.first)<layers.size()) {
      AsteroidLayer &layer = layers[split.first];
      Asteroid *asteroid = layer.get_asteroid(split.second);
      
      if(!asteroid or asteroid->is_alive())
        continue;

      // Only spawn a new asteroid if this one is off screen.
      AsteroidState *state = layer.get_valid_state(split.second,asteroid,rnow);
      if(!state or search_region.has_point(asteroid->get_xz(*state)))
        continue;

      // Replace the asteroid's stats
      asteroid->set_template(palette.random_choice(rand));

      // Ensure the state is reinitialized next time it is needed.
      state->reset();
    }
  }
}

////////////////////////////////////////////////////////////////////////

void AsteroidField::send_meshes(MultiMeshManager &mmm) {
  Transform trans;
  if(!sent_meshes) {
    for(auto & pal : palette) {
      Ref<Mesh> m=pal->get_mesh();
      if(!m.is_valid()) {
        Godot::print_error("Null mesh found in AsteroidField.",__FUNCTION__,__FILE__,__LINE__);
        continue;
      }
      object_id id=mmm.add_preloaded_mesh(m);
      if(id<0) {
        Godot::print_error("Negative mesh id from MultiMeshManager.",__FUNCTION__,__FILE__,__LINE__);
        continue;
      }
      pal->set_mesh_id(id);
      if(pal->get_mesh_id()!=id)
        Godot::print_error("Unable to set mesh id in send_meshes.",__FUNCTION__,__FILE__,__LINE__);
    }
    sent_meshes = true;
  }
}

////////////////////////////////////////////////////////////////////////

void AsteroidField::add_content(Rect2 visible_region,VisibleContent &content) {
  FAST_PROFILING_FUNCTION;
  // Search a slightly larger region due to asteroid scaling.
  Rect2 search_region = visible_region.grow(max_scale*2+1);

  if(AsteroidSearchResult::rect_entirely_outside_annulus(search_region,inner_radius,outer_radius))
    return;
  
  deque<AsteroidSearchResult> found,work;

  real_t valid_time = now;

  for(size_t ilayer = 0;ilayer<layers.size();ilayer++) {
    const AsteroidLayer &layer = layers[ilayer];
    if(AsteroidSearchResult::theta_ranges_of_rect(search_region,found,work,layer.inner_radius,layer.outer_radius)) {
      for(auto &range : found) {
        if(!range.get_any_intersect())
          continue;
        
        // What range of indices do we search?
        pair<object_id,object_id> itheta_range = layer.find_theta_range(range,valid_time);
        object_id itheta1=itheta_range.first, itheta2=itheta_range.second;
      
        // Search all indices within the range.
        int itheta = itheta1-1;
        do {
          // Go to the next index. This may need to loop around the end of the array.
          itheta = (itheta+1)%layer.size();
        
          // Get the asteroid and its up-to-date state.
          pair<const Asteroid*,const AsteroidState *> a_s = layer.unsafe_get(itheta,valid_time);
          const Asteroid *a = a_s.first;
          const AsteroidState *s = a_s.second;
          shared_ptr<const AsteroidTemplate> t = a->get_template();
          real_t r=s->get_scale();
          Vector2 loc = a->get_xz(*s);
          real_t dd=rect_distance_squared_to(search_region,loc);

          if(dd<r*r) {
            // Calculate the transform, and put everything in a new InstanceEffect
            content.instances.push_back(InstanceEffect {
                t->get_mesh_id(), a->calculate_transform(*s),
                  t->get_color_data(), s->get_instance_data(),
                  Vector2(r,r) });
          }
        } while(itheta!=itheta2);
      }
    }
  }
}

////////////////////////////////////////////////////////////////////////

std::size_t AsteroidField::overlapping_rect(Rect2 rect,std::unordered_set<object_id> &results) const {
  FAST_PROFILING_FUNCTION;
  // Search a slightly larger region due to asteroid scaling.
  Rect2 search_region = rect.grow(max_scale+1);

  if(AsteroidSearchResult::rect_entirely_outside_annulus(search_region,inner_radius,outer_radius)) {
    return 0;
  }
  
  deque<AsteroidSearchResult> found,work;

  real_t valid_time = now;
  size_t count=0;

  for(size_t ilayer = 0;ilayer<layers.size();ilayer++) {
    const AsteroidLayer &layer = layers[ilayer];
    assert(layer.min_scale>0);
    assert(layer.max_scale>0);
    assert(layer.inner_radius>=inner_radius);
    assert(layer.outer_radius<=outer_radius);
    assert(layer.scale_range>0);
    if(AsteroidSearchResult::theta_ranges_of_rect(search_region,found,work,layer.inner_radius,layer.outer_radius)) {
      for(auto &range : found) {
        if(!range.get_any_intersect()) {
          continue;
        }

        // What range of indices do we search?
        pair<object_id,object_id> itheta_range = layer.find_theta_range(range,valid_time);
        object_id itheta1=itheta_range.first, itheta2=itheta_range.second;

        size_t matches = 0;
        // Search all indices within the range.
        int itheta = itheta1-1;
        do {
          // Go to the next index. This may need to loop around the end of the array.
          itheta = (itheta+1)%layer.size();
        
          // Get the asteroid and its up-to-date state.
          pair<const Asteroid*,const AsteroidState *> a_s = layer.unsafe_get(itheta,valid_time);
          const Asteroid *a = a_s.first;
          const AsteroidState *s = a_s.second;
          real_t r=s->get_scale();
          real_t d=rect_distance_to(rect,a->get_xz(*s));

          if(d<r) {
            results.insert(combined_id(ilayer,itheta));
            count++;
            matches++;
          }
        } while(itheta!=itheta2);
      }
    }
  }
  return count;
}

////////////////////////////////////////////////////////////////////////

std::size_t AsteroidField::overlapping_circle(Vector2 center,real_t radius,std::unordered_set<object_id> &results) const {
  FAST_PROFILING_FUNCTION;
  size_t count=0;
  real_t expanded_radius = radius+max_scale+1;
  real_t valid_time = now;
  real_t clen = center.length();
  
  if(expanded_radius+clen<inner_radius or clen-expanded_radius>outer_radius) {
    // Circle does not overlap asteroid field at all.
    return 0;
  }

  for(size_t ilayer = 0;ilayer<layers.size();ilayer++) {
    const AsteroidLayer &layer = layers[ilayer];
    AsteroidSearchResult range = AsteroidSearchResult::theta_range_of_circle(center,expanded_radius,layer.inner_radius,layer.outer_radius);
    if(!range.get_any_intersect())
      continue;

    // What range of indices do we search?
    pair<object_id,object_id> itheta_range = layer.find_theta_range(range,valid_time);
    object_id itheta1=itheta_range.first, itheta2=itheta_range.second;
    
    // Search all indices within the range.
    int itheta = itheta1-1;
    do {
      // Go to the next index. This may need to loop around the end of the array.
      itheta = (itheta+1)%layer.size();
      
      // Get the asteroid and its up-to-date state.
      pair<const Asteroid*,const AsteroidState *> a_s = layer.unsafe_get(itheta,valid_time);
      const Asteroid *a = a_s.first;
      const AsteroidState *s = a_s.second;
      real_t r=s->get_scale();
      Vector2 loc=a->get_xz(*s);
      real_t combined_radius = r+radius;

      if(center.distance_squared_to(loc)<=combined_radius*combined_radius) {
        results.insert(combined_id(ilayer,itheta));
        count++;
      }
    } while(itheta!=itheta2);
  }
  return count;
}

////////////////////////////////////////////////////////////////////////

object_id AsteroidField::first_in_circle(Vector2 center,real_t radius) const {
  FAST_PROFILING_FUNCTION;
  real_t expanded_radius = radius+max_scale+1;
  real_t valid_time = now;
  real_t clen = center.length();
  
  if(expanded_radius+clen<inner_radius or clen-expanded_radius>outer_radius) {
    // Circle does not overlap asteroid field at all.
    return -1;
  }
  
  for(size_t ilayer = 0;ilayer<layers.size();ilayer++) {
    const AsteroidLayer &layer = layers[ilayer];
    AsteroidSearchResult range = AsteroidSearchResult::theta_range_of_circle(center,expanded_radius,layer.inner_radius,layer.outer_radius);
    if(!range.get_any_intersect())
      continue;

    // What range of indices do we search?
    pair<object_id,object_id> itheta_range = layer.find_theta_range(range,valid_time);
    object_id itheta1=itheta_range.first, itheta2=itheta_range.second;
    
    // Search all indices within the range.
    int itheta = itheta1-1;
    do {
      // Go to the next index. This may need to loop around the end of the array.
      itheta = (itheta+1)%layer.size();
      
      // Get the asteroid and its up-to-date state.
      pair<const Asteroid*,const AsteroidState *> a_s = layer.unsafe_get(itheta,valid_time);
      const Asteroid *a = a_s.first;
      const AsteroidState *s = a_s.second;
      real_t r=s->get_scale();
      Vector2 loc=a->get_xz(*s);
      real_t combined_radius = r+radius;

      if(center.distance_squared_to(loc)<=combined_radius*combined_radius)
        return combined_id(ilayer,itheta);
    } while(itheta!=itheta2);
  }
  return -1;
}

////////////////////////////////////////////////////////////////////////

object_id AsteroidField::cast_ray(Vector2 start,Vector2 end) const {
  FAST_PROFILING_FUNCTION;
  real_t slen=start.length(), elen=end.length();
  
  if(slen<inner_radius && elen<inner_radius) {
    // Segment is inside innermost inner radius, so no possible match.
    return -1;
  }

  if(slen>outer_radius && elen>outer_radius) {
    Vector2 segment[2] = { start,end };
    Vector2 intersection[2];
    if(line_segment_intersect_circle(outer_radius,segment,intersection)<2) {
      // Segment is outside outermost outer radius, so no possible match.
      return -1;
    }
  }
  
  real_t closest_approach = numeric_limits<real_t>::infinity();
  object_id closest_id = -1;
  real_t valid_time = now;

  Vector2 diff = end-start;
  real_t length = diff.length();
  Vector2 direction = length ? diff/length : Vector2(1,0);
  Vector2 normal(-direction.y,direction.x);
  
  for(size_t ilayer=0;ilayer<layers.size();ilayer++) {
    const AsteroidLayer &layer = layers[ilayer];
    if(!layer.asteroids.size())
      continue; // Layer is empty. Should never happen.

    // Find the theta ranges of all possible intersections of the ray with this layer.
    pair<AsteroidSearchResult,AsteroidSearchResult> range_pair = AsteroidSearchResult::theta_ranges_of_ray(start,end,layer.inner_radius,layer.outer_radius);
    AsteroidSearchResult ranges[2];
    ranges[0]=range_pair.first;
    ranges[1]=range_pair.second;

    // Are we searching zero, one, or two ranges?
    size_t loop_start=0,loop_end=1;
    if(ranges[0].get_all_intersect() or ranges[1].get_all_intersect())
      loop_end=0;
    else {
      if(!ranges[0].get_any_intersect())
        loop_start=1;
      if(!ranges[1].get_any_intersect())
        loop_end=0;
    }

    // Find the asteroid closest to the beginning of the ray.
    for(size_t irange=loop_start;irange<=loop_end;irange++) {
      AsteroidSearchResult range = ranges[irange].expanded_by(layer.max_scale/layer.inner_radius);

      if(!range.get_any_intersect())
        continue;
      
      pair<object_id,object_id> itheta_range = layer.find_theta_range(range,valid_time);
      object_id itheta1=itheta_range.first, itheta2=itheta_range.second;

      int itheta=itheta1-1;
      do {
        itheta = (itheta+1)%layer.size();

        // Get the asteroid and its up-to-date state.
        pair<const Asteroid*,const AsteroidState *> a_s = layer.unsafe_get(itheta,valid_time);
        const Asteroid *a = a_s.first;
        const AsteroidState *s = a_s.second;
        Vector2 location = a->get_xz(*s);
        real_t radius=s->get_scale();

        Vector2 relative_location = location-start;
        real_t along = relative_location.dot(direction);
        real_t approach = along-radius;
        if(approach>length or along+radius<0)
          // Asteroid is before or after ray
          continue;
        real_t across = fabsf(relative_location.dot(normal));
        if(across>radius)
          // Ray does not pass through asteroid
          continue;

        if(approach<=0)
          // Start point is within asteroid, so this is a final match.
          return combined_id(ilayer,itheta);
        
        if(approach<closest_approach) {
          // This is closer than the next best match, so record it.
          closest_approach = approach;
          closest_id = combined_id(ilayer,itheta);
        }
        itheta++;
      } while(itheta!=itheta2);
    }
  }
  
  return closest_id;
}
