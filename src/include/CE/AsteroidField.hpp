#ifndef ASTEROIDFIELD_HPP
#define ASTEROIDFIELD_HPP

#include <cmath>
#include <algorithm>
#include <cstdint>
#include <vector>
#include <unordered_set>
#include <memory>
#include <deque>

#include <Godot.hpp>
#include <Vector2.hpp>
#include <Array.hpp>
#include <Rect2.hpp>

#include "CE/Asteroid.hpp"
#include "CE/Types.hpp"
#include "CE/Constants.hpp"
#include "CE/MultiMeshManager.hpp"
#include "CE/ObjectIdGenerator.hpp"

namespace godot {
  namespace CE {
    class CombatEngine;
    class VisibleContent;
    
    class AsteroidSearchResult {
      // Results from searching for a region of thetas matching a shape in an AsteroidLayer.
      // Not intended for use outside AsteroidField, except for unit tests.
      
      real_t start_theta, end_theta, theta_width;
      bool any_intersect, all_intersect;

    public:

      inline real_t get_start_theta() const {
        return start_theta;
      }
      inline real_t get_end_theta() const {
        return end_theta;
      }
      inline bool get_any_intersect() const {
        return any_intersect;
      }
      inline bool get_all_intersect() const {
        return all_intersect;
      }
      
      AsteroidSearchResult(real_t start, real_t end):
        start_theta(fmod(start+20*TAU,TAU)), end_theta(fmodf(end+20*TAU,TAU)),
        theta_width(fmod(end_theta-start_theta+20*TAU,TAU)),
        any_intersect(true), all_intersect(false)
      {}

      AsteroidSearchResult(bool all): // true = all match, false = no match
        start_theta(0), end_theta(0),
        theta_width(all ? TAUf : 0),
        any_intersect(all), all_intersect(all)
      {}

      AsteroidSearchResult(): // no match
        start_theta(0), end_theta(0), theta_width(0),
        any_intersect(false), all_intersect(false)
      {}

      static const AsteroidSearchResult no_match;
      static const AsteroidSearchResult all_match;

      inline bool operator == (const AsteroidSearchResult & o) const {
        return any_intersect==o.any_intersect && all_intersect==o.all_intersect
          && start_theta==o.start_theta && end_theta==o.end_theta;
      }
      inline bool operator < (const AsteroidSearchResult & o) const {
        if(any_intersect!=o.any_intersect)
          return any_intersect<o.any_intersect;
        if(all_intersect!=o.all_intersect)
          return all_intersect<o.all_intersect;
        if(start_theta!=o.start_theta)
          return start_theta<o.start_theta;
        return end_theta<o.end_theta;
      }

      inline AsteroidSearchResult negation() const {
        if(all_intersect)
          return no_match;
	if(!any_intersect)
          return all_match;
        return AsteroidSearchResult(end_theta,start_theta);
      }
        
      inline real_t contains(real_t theta) const {
        return any_intersect ? (fmod(theta-start_theta+20*TAU,TAU) <= theta_width) : false;
      }

      // Creates a new AsteroidSearchResult where the range has been
      // expanded or shrunk by dtheta in each direction.
      AsteroidSearchResult expanded_by(real_t dtheta);
      
      // Merge multiple ranges into a smaller number of ranges that cover the same set.
      static void merge_set(std::deque<AsteroidSearchResult> results);
      
      // Remove the region, returning the zero, one, or two regions of remaining thetas:
      std::pair<AsteroidSearchResult,AsteroidSearchResult> minus(const AsteroidSearchResult &region) const;

      // Merge the region with this one, if possible. If impossible,
      // returns false. If possible, returns true and the merged
      // region.
      std::pair<bool,AsteroidSearchResult> merge(const AsteroidSearchResult &region) const;

      // Find all thetas of an annulus that overlap the given ray.
      static std::pair<AsteroidSearchResult,AsteroidSearchResult> theta_ranges_of_ray(Vector2 start,Vector2 end,real_t inner_radius,real_t outer_radius);

      // Find all thetas of an annulus that lie within the given circle.
      static AsteroidSearchResult theta_range_of_circle(Vector2 center,real_t radius,real_t inner_radius,real_t outer_radius);

      // Find all thetas of an annulus that lie within the given rect.
      // If there are none, returns false and puts no_match in the results.
      // If there are any, they'll be in the results.
      static bool theta_ranges_of_rect(Rect2 rect,std::deque<AsteroidSearchResult> &results,std::deque<AsteroidSearchResult> &work1,real_t inner_radius,real_t outer_radius);
    };

    ////////////////////////////////////////////////////////////////////
           
    struct AsteroidLayer {
      // Represents all asteroids with the same orbital speed and annulus.
      // Not intended to be used outside AsteroidField except for unit tests.

      // Time it takes for an asteroid to go all the away around the circle.
      const real_t orbit_period;
      
      // TAUf/orbit_period = dtheta/dtime
      const real_t orbit_mult;
      
      // Radius of the inner circle of the annulus
      const real_t inner_radius;

      // Difference between the outer and inner circles of the annulus
      const real_t thickness;
      
      // Radius of the outer circle of the annulus
      const real_t outer_radius;

      // Target mean distance between asteroids.
      const real_t spacing;

      // Average y location of asteroids (will vary by +/-1)
      const real_t y;
        
      typedef std::vector<Asteroid> asteroid_storage;
      typedef typename asteroid_storage::iterator asteroid_storage_iter;
      typedef typename asteroid_storage::const_iterator asteroid_storage_citer;
        
      // All asteroids, sorted by angle and radius
      std::vector<Asteroid> asteroids;

      // Cached state of each asteroid.
      mutable std::vector<AsteroidState> state;

      AsteroidLayer(const Dictionary &d);
      ~AsteroidLayer();

      inline size_t size() const {
        return asteroids.size();
      }
      
      // Return the asteroid at the given index, or nullptr if there is none
      inline Asteroid *get_asteroid(object_id index) {
        return (index<0 or static_cast<size_t>(index)>=asteroids.size()) ? nullptr : &asteroids[index];
      }
      inline const Asteroid *get_asteroid(object_id index) const {
        return (index<0 or static_cast<size_t>(index)>=asteroids.size()) ? nullptr : &asteroids[index];
      }

      // Get, make, or update an AstroidState, assuming the index is a valid index and a is non-null
      inline AsteroidState *get_valid_state(object_id index, const Asteroid *a, real_t time) {
        AsteroidState *s = &state[index];
        if(s->needs_update_to(time))
          a->update_state(*s,time,orbit_period,inner_radius,!s->is_valid());
        return s;
      }
      inline const AsteroidState *get_valid_state(object_id index, const Asteroid *a, real_t time) const {
        AsteroidState *s = &state[index];
        if(s->needs_update_to(time))
          a->update_state(*s,time,orbit_period,inner_radius,!s->is_valid());
        return s;
      }

      // upper_bound of theta
      int find_theta(real_t theta) const;

      // How much has the annulus rotated by this time?
      inline real_t theta_time_shift(double when) const {
        return when*orbit_mult;
      }

      // Clears the asteroid layer and generates a new one from the given selection of asteroids.
      // WARNING: Asteroid and AsteroidState pointers are invalid after this call.
      void generate_field(const AsteroidPalette &palette,CheapRand32 &rand);

    private:
      // Sort asteroids by increasing theta
      // FIXME: This should not be necessary because they're generated in sorted order.
      void sort_asteroids();
    };

    
    ////////////////////////////////////////////////////////////////////

    class AsteroidField {
      // Fields of asteroids; all are in annuli centered on the
      // origin.  Each has structure, and possibly salvage.  When an
      // asteroid is destroyed, it leaves behind a "slot" that is
      // filled with an asteroid when the "slot" goes off screen.
      
      // Constants for conversion from (layer number, asteroid index) pair to object_id and back again.
      static const unsigned asteroid_layer_number_bit_shift = 32;
      static const uint64_t max_asteroids_per_layer = 1ULL << asteroid_layer_number_bit_shift;
      static const uint64_t asteroid_layer_mask = 0xffffffff00000000ULL;
      static const uint64_t index_layer_mask = 0xffffffffULL;

      // The selection of asteroids to choose from. These will be
      // instanced as needed throughout the asteroid layers.
      AsteroidPalette palette;

      CheapRand32 rand;
      
      // The selection of flotsam that asteroids can generate upon destruction.
      std::shared_ptr<const SalvagePalette> salvage;

      // All layers of asteroids.
      std::vector<AsteroidLayer> layers;

      // Current time.
      double now;

      // All asteroids that have been destroyed. New ones will be
      // generated in the same place after they're off-screen.
      std::unordered_set<object_id> dead_asteroids;

      // Have we initialized the palette mesh_ids by sending the meshes to a MultiMeshManager?
      bool sent_meshes;
    public:

      // Read asteroid layer descriptions (data) and generate asteroid layers using the specified palettes.
      AsteroidField(double now,Array data,std::shared_ptr<AsteroidPalette> asteroids,
                    std::shared_ptr<SalvagePalette> salvege);

      ~AsteroidField();

      // Clears the asteroid field and generates a new one.
      // WARNING: Asteroid and AsteroidState pointers are invalid after this call.
      void generate_field(CheapRand32 &rand);
      
      // Return the asteroid and state for the given id, if it exists.
      // If a state is returned, it is up-to-date with the current time.
      std::pair<const Asteroid*,const AsteroidState *> get(object_id id) const;

      // Somebody shot that asteroid. Return the amount of overkill damage. Create flotsam if needed
      double damage_asteroid(CombatEngine &ce,object_id id,double amount);

      // Is this asteroid still alive?
      bool is_alive(object_id id) const;
      
      // Increment the current time. Generate new asteroids to replace dead ones outside the visible_region.
      void step_time(int64_t idelta,real_t delta,Rect2 visible_region);

      // Send palette meshes to a multimesh manager to get mesh ids
      void send_meshes(MultiMeshManager &mmm);
      
      // Update multimeshes for asteroids overlapping the visible region.
      void add_content(Rect2 visible_region,VisibleContent &content);

      // Finds all asteroids overlapping the given rect.
      // Adds all matches to results and returns the number of matches.
      std::size_t overlapping_rect(Rect2 rect,std::unordered_set<object_id> &results) const;

      // Finds all asteroids overlapping the given circle.
      // Adds all matches to results and returns the number of matches.
      std::size_t overlapping_circle(Vector2 center,real_t radius,std::unordered_set<object_id> &results) const;

      // Finds all asteroids that contain the given point.
      // Adds all matches to results and returns the number of matches.
      inline std::size_t overlapping_point(Vector2 point,std::unordered_set<object_id> &results) const {
        return overlapping_circle(point,0,results);
      }

      // Finds an asteroid overlapping the given circle and returns it.
      // If there are multiple matches, the first match found is returned.
      // Returns -1 if nothing matches.
      object_id first_in_circle(Vector2 center,real_t radius) const;

      // Finds an asteroid overlapping the given point and returns it.
      // If there are multiple matches, the first match found is returned.
      // Returns -1 if nothing matches.
      inline object_id first_at_point(Vector2 point) const {
        return first_in_circle(point,0);
      }

      // Return the id of the first asteroid that the given ray hits.
      object_id cast_ray(Vector2 start,Vector2 end) const;

    private:

      // Return the layer number and asteroid index of the given object id,
      // or -1,-1 if nothing matches.
      static inline std::pair<int,int> split_id(object_id id) {
        if(id<0)
          return std::pair<int,int>(-1,-1);
        else
          return std::pair<int,int>(id>>asteroid_layer_number_bit_shift,id&index_layer_mask);
      }

      // Given the layer number and asteroid index, returns the object id.
      // Will return -1 if either are <0
      static inline object_id combined_id(int layer,int index) {
        if(layer<0 or index<0)
          return -1;
        else
          return (static_cast<uint64_t>(layer)<<asteroid_layer_number_bit_shift) |
            (static_cast<uint64_t>(index)&index_layer_mask);
      }
    };
  }
}

#endif
