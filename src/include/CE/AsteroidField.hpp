#ifndef ASTEROIDFIELD_HPP
#define ASTEROIDFIELD_HPP

#include <cmath>
#include <algorithm>
#include <cstdint>
#include <vector>
#include <unordered_map>
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
#include "CE/Utils.hpp"
#include "hash_functions.hpp"

namespace godot {
  namespace CE {
    class CombatEngine;
    class VisibleContent;
    class AsteroidField;
    
    class AsteroidSearchResult {
      // Results from searching for a region of thetas matching a shape in an AsteroidLayer.
      // Not intended for use outside AsteroidField, except for unit tests.

      real_t start_theta, end_theta, theta_width;
      bool any_intersect, all_intersect;

      static constexpr real_t epsilon = 1e-4;
      
    public:

      inline real_t get_start_theta() const {
        return start_theta;
      }
      inline real_t get_end_theta() const {
        return end_theta;
      }
      inline real_t get_theta_width() const {
        return theta_width;
      }
      inline bool get_any_intersect() const {
        return any_intersect;
      }
      inline bool get_all_intersect() const {
        return all_intersect;
      }
      
      AsteroidSearchResult(real_t start, real_t end):
        start_theta(fmod(start+4*TAU,TAU)), end_theta(fmod(end+2*TAU,TAU)),
        theta_width(fmod(double(end_theta)-double(start_theta)+2*TAU,TAU)),
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
        if(fabsf(start_theta-o.start_theta)>epsilon)
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

      inline bool contains(double theta) const {
        if(any_intersect) {
          double dtheta = theta-double(start_theta);
          dtheta = fmod(dtheta+2*TAU,TAU);
          return dtheta < theta_width+epsilon;
        }
        return false;
      }

      // Creates a new AsteroidSearchResult where the range has been
      // expanded or shrunk by dtheta in each direction.
      AsteroidSearchResult expanded_by(real_t dtheta);
      
      // Merge multiple ranges into a smaller number of ranges that cover the same set.
      static void merge_set(std::deque<AsteroidSearchResult> &results);
      
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

      static bool rect_entirely_outside_annulus(Rect2 rect,real_t inner_radius,real_t outer_radius);
      
      // Find all thetas of an annulus that lie within the given rect.
      // If there are none, returns false and puts no_match in the results.
      // If there are any, they'll be in the results.
      static bool theta_ranges_of_rect(Rect2 rect,std::deque<AsteroidSearchResult> &results,std::deque<AsteroidSearchResult> &work1,real_t inner_radius,real_t outer_radius);
    };
    
  }
  
  template<>
  inline String str(const CE::AsteroidSearchResult &range) {
    if(range.get_all_intersect())
      return "[all match]";
    else if(!range.get_any_intersect())
      return "[no match]";
    else
      return "["+str(range.get_start_theta())+"..."+str(range.get_end_theta())+"]";
  }

  namespace CE {
    ////////////////////////////////////////////////////////////////////
           
    class AsteroidLayer {
      

      friend class AsteroidField;
      
      // Represents all asteroids with the same orbital speed and annulus.
      // Not intended to be used outside AsteroidField except for unit tests.
      
      // Radius of the inner circle of the annulus
      const real_t inner_radius;

      // Average y location of asteroids (will vary by +/-1)
      const real_t y;

      // Maximum speed an asteroid can rotate around its randomly-chosen axis
      const real_t max_rotation_speed;
      
      // Minimum x,y,z scale of asteroid
      const real_t min_scale;
      
      // Maximum x,y,z scale of asteroid
      const real_t max_scale;
      
      // max_scale-min_scale
      const real_t scale_range;

      // Difference between the outer and inner circles of the annulus
      const real_t thickness;
      
      // Radius of the outer circle of the annulus
      const real_t outer_radius;

      // Target mean distance between asteroids.
      const real_t spacing;

      // Tangential velocity of asteroids half way between the inner and outer radii
      const real_t mean_velocity;

      // Time it takes for an asteroid to go all the away around the circle.
      const real_t orbit_period;
      
      // TAUf/orbit_period = dtheta/dtime
      const real_t orbit_mult;

      // All asteroids, sorted by angle and radius
      std::vector<Asteroid> asteroids;
    public:
      typedef std::vector<Asteroid> asteroid_storage;
      typedef typename asteroid_storage::iterator asteroid_storage_iter;
      typedef typename asteroid_storage::const_iterator asteroid_storage_citer;

      AsteroidLayer(const Dictionary &d);
      ~AsteroidLayer();

      PROP_GET_VAL(real_t,mean_velocity);
      PROP_GET_VAL(real_t,orbit_period);
      PROP_GET_VAL(real_t,orbit_mult);
      PROP_GET_VAL(real_t,inner_radius);
      PROP_GET_VAL(real_t,thickness);
      PROP_GET_VAL(real_t,outer_radius);
      PROP_GET_VAL(real_t,spacing);
      PROP_GET_VAL(real_t,max_rotation_speed);
      PROP_GET_VAL(real_t,min_scale);
      PROP_GET_VAL(real_t,max_scale);
      PROP_GET_VAL(real_t,scale_range);
      PROP_GET_VAL(real_t,y);
      
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
      inline Asteroid *get_asteroid(object_id index,real_t time) {
        Asteroid *a = get_asteroid(index);
        if(a)
          update_state(*a,time);
        return a;
      }
      inline const Asteroid *get_asteroid(object_id index,real_t time) const {
        const Asteroid *a = get_asteroid(index);
        if(a)
          update_state(*a,time);
        return a;
      }

      // Ensure the asteroid has up-to-date knowledge of its state.
      inline bool update_state(const Asteroid &a,real_t time) const {
        if(a.state.needs_update_to(time)) {
          a.update_state(time,orbit_period,inner_radius,max_rotation_speed,min_scale,scale_range);
          return true;
        }
        return false;
      }

      inline const Asteroid &unsafe_get(object_id index) const {
        return asteroids[index];
      }
      inline Asteroid &unsafe_get(object_id index) {
        return asteroids[index];
      }

      inline const Asteroid &unsafe_get(object_id index, real_t time) const {
        const Asteroid &a = unsafe_get(index);
        update_state(a,time);
        return a;
      }
      inline Asteroid &unsafe_get(object_id index, real_t time) {
        Asteroid &a = unsafe_get(index);
        update_state(a,time);
        return a;
      }

      // upper_bound of theta
      int find_theta(real_t theta) const;

      // range of thetas to loop over
      std::pair<object_id,object_id> find_theta_range(const AsteroidSearchResult &r,double when) const;

      // How much has the annulus rotated by this time?
      inline real_t theta_time_shift(double when) const {
        return when*orbit_mult;
      }

      // Clears the asteroid layer and generates a new one from the given selection of asteroids.
      // WARNING: Asteroid pointers are invalid after this call.
      void generate_field(const AsteroidPalette &palette,CheapRand32 &rand,object_id asteroid_id_mask);
    };

    
    ////////////////////////////////////////////////////////////////////

    class AsteroidField {
      // Fields of asteroids; all are in annuli centered on the
      // origin.  Each has structure, and possibly salvage.  When an
      // asteroid is destroyed, it leaves behind a "slot" that is
      // filled with an asteroid when the "slot" goes off screen.
      
      // Constants for conversion from (layer number, asteroid index) pair to object_id and back again.
      static const unsigned asteroid_layer_number_bit_shift = 28;
      static const uint64_t max_asteroids_per_layer = 1ULL << asteroid_layer_number_bit_shift;
      static const uint64_t asteroid_layer_mask = 0xfff0000000ULL;
      static const uint64_t index_layer_mask =    0xfffffffULL;

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
      typedef std::unordered_map<object_id,real_t> dead_asteroids_t;
      dead_asteroids_t dead_asteroids;

      // Have we initialized the palette mesh_ids by sending the meshes to a MultiMeshManager?
      bool sent_meshes;

      // A number to bitwise-or with the object ids. Must only use the upper 24 bits.
      object_id field_id;

      // Combined size of layers
      real_t inner_radius;
      real_t outer_radius;
      real_t thickness;
      real_t max_scale;
    public:

      // Read asteroid layer descriptions (data) and generate asteroid layers using the specified palettes.
      AsteroidField(double now,Array data,std::shared_ptr<AsteroidPalette> asteroids,
                    std::shared_ptr<SalvagePalette> salvege,object_id field_id);

      ~AsteroidField();

      PROP_GET_VAL(object_id,field_id);
      PROP_GET_VAL(std::shared_ptr<const SalvagePalette>,salvage);
      PROP_GET_VAL(real_t,max_scale);
      PROP_GET_VAL(real_t,inner_radius);
      PROP_GET_VAL(real_t,outer_radius);
      PROP_GET_VAL(real_t,thickness);
      PROP_GET_VAL(double,now);
      PROP_GET_CONST_REF(AsteroidPalette,palette);
      PROP_GET_CONST_REF(dead_asteroids_t,dead_asteroids);
      PROP_HAVE_VAL(sent_meshes);
      PROP_GET_REF(CheapRand32,rand);
      
      class const_iterator {
        const AsteroidField *field;
        object_id id;
      public:
        inline const_iterator(): field(nullptr), id(-1) {}
        inline const_iterator(const AsteroidField *field,object_id id):
          field(field), id(id)
        {}
        inline const_iterator &operator ++() {
          id=field->id_after(id);
          return *this;
        }
        inline const_iterator operator ++(int) {
          const_iterator temp(*this);
          ++*this;
          return temp;
        }
        inline const_iterator &operator --() {
          id=field->id_before(id);
          return *this;
        }
        inline const_iterator operator --(int) {
          const_iterator temp(*this);
          --*this;
          return temp;
        }
        const Asteroid *operator *() const {
          return field->get(id);
        }
        inline bool operator == (const const_iterator &b) const {
          return id==b.id && field==b.field;
        }
        inline bool operator != (const const_iterator &b) const {
          return id!=b.id || field!=b.field;
        }
      };

      const_iterator find(object_id id) const;
      inline const_iterator begin() const {
        return const_iterator(this,0);
      }
      inline const_iterator end() const {
        return const_iterator(this,-1);
      }
      
      // Clears the asteroid field and generates a new one.
      // WARNING: Asteroid pointers are invalid after this call.
      void generate_field();
      
      // Return the asteroid and state for the given id, if it exists.
      // If a state is returned, it is up-to-date with the current time.
      Asteroid *get(object_id id);
      const Asteroid *get(object_id id) const;

      // Somebody shot that asteroid. Return the amount of overkill damage. Create flotsam if needed
      real_t damage_asteroid(CombatEngine &ce,Asteroid &asteroid,real_t amount,int damage_type);

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
      std::size_t overlapping_rect(Rect2 rect,hit_list_t &results,size_t max_matches);

      // Finds all asteroids overlapping the given circle.
      // Adds all matches to results and returns the number of matches.
      std::size_t overlapping_circle(Vector2 center,real_t radius,hit_list_t &results,size_t max_matches);

      // Finds all asteroids that contain the given point.
      // Adds all matches to results and returns the number of matches.
      inline std::size_t overlapping_point(Vector2 point,hit_list_t &results,size_t max_matches) {
        return overlapping_circle(point,0,results,max_matches);
      }

      inline bool empty() const {
        if(!layers.size())
          return true;
        for(auto &layer : layers)
          if(layer.size())
            return false;
        return true;
      }
      
      inline std::size_t size() const {
        std::size_t size=0;
        for(auto &layer : layers)
          size+=layer.size();
        return size;
      }
      
      // Finds an asteroid overlapping the given circle and returns it.
      // If there are multiple matches, the first match found is returned.
      // Returns -1 if nothing matches.
      CelestialHit first_in_circle(Vector2 center,real_t radius);

      // Finds an asteroid overlapping the given point and returns it.
      // If there are multiple matches, the first match found is returned.
      // Returns -1 if nothing matches.
      inline CelestialHit first_at_point(Vector2 point) {
        return first_in_circle(point,0);
      }

      // Return the id of the first asteroid that the given ray hits.
      CelestialHit cast_ray(Vector2 start,Vector2 end);

      object_id id_before(object_id id) const {
        if(id>=0) {
          size_t layer = (id&asteroid_layer_mask)>>asteroid_layer_number_bit_shift;
          int index = id&index_layer_mask;
          if(index>0)
            return id-1;
          if(layer>0)
            return unsafe_combined_id(layer,index);
        }
        return -1;
      }

      object_id id_after(object_id id) const {
        if(id>=0) {
          size_t layer = (id&asteroid_layer_mask)>>asteroid_layer_number_bit_shift;
          int index = id&index_layer_mask;
          if(layer<layers.size()) {
            int size = layers[layer].size();
            if(index<size-1)
              return id+1;
            else if(layer<layers.size()-1)
              return unsafe_combined_id(layer+1,0);
          }
        }
        return -1;
      }

      // Return the layer number and asteroid index of the given object id,
      // or -1,-1 if nothing matches.
      inline std::pair<int,int> split_id(object_id id) const {
        if(id<0)
          return std::pair<int,int>(-1,-1);
        else
          return unsafe_split_id(id);
      }
      
      inline std::pair<int,int> unsafe_split_id(object_id id) const {
        return std::pair<int,int>((id&asteroid_layer_mask)>>asteroid_layer_number_bit_shift,
                                  id&index_layer_mask);
      }
      
      // Given the layer number and asteroid index, returns the object id.
      // Will return -1 if either are <0
      inline object_id combined_id(int layer,int index) const {
        if(layer<0 or index<0)
          return -1;
        else
          return unsafe_combined_id(layer,index);
      }
      
      inline object_id unsafe_combined_id(int layer,int index) const {
        return (static_cast<object_id>(layer)<<asteroid_layer_number_bit_shift) |
          (static_cast<object_id>(index)&index_layer_mask) | field_id;
      }
    };
  }
}

#endif
