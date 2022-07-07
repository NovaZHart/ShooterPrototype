#ifndef ASTEROIDS_HPP
#define ASTEROIDS_HPP

#include <vector>
#include <cstdint>
#include <algorithm>
#include <unordered_set>
#include <unordered_map>

#include <Godot.hpp>
#include <Transform.hpp>
#include <Vector3.hpp>
#include <Color.hpp>
#include <Rect2.hpp>
#include <Vector2.hpp>

#include "hash_functions.hpp"
#include "CE/Types.hpp"
#include "CE/Constants.hpp"
#include "CE/MultimeshManager.hpp"
#include "CE/ObjectIdGenerator.hpp"

namespace godot {
  namespace CE {

    struct AsteroidState {
      // Stores the time-varying state and expensive calculations for one asteroid.
      // Updated as needed by Asteroid::update_state

      // Special constant for valid_time that indicates the state is uninitialized.
      // Should be positive so time<invalid_time is true.
      static constexpr real_t invalid_time = -1e20;

      real_t x,z;

      // Relatively expensive hash calculation from Asteroid members:
      uint32_t hash;

      // Last time at which Asteroid::update_state was called:
      real_t valid_time;

      // Four random numbers generated from the hash:
      Color random_numbers;

      // Does this state match that time?
      inline bool needs_update_to(real_t time) const {
        return time!=valid_time;
      }

      // Does the state have valid data?
      inline bool is_valid() const {
        return valid_time!=invalid_time;
      }

      // Pretend the state has invalid data so the next call to update_state will calculate it.
      inline void reset() {
        valid_time=invalid_time;
      }

      // Create a new AsteroidState with an invalid state.
      AsteroidState():
        x(0),y(0),hash(0),valid_time(invalid_time)
      {}
      ~AsteroidState() {}
    };
    
    class Asteroid {
    public:
      static const real_t max_rotation_speed;
      static const real_t min_scale;
      static const real_t max_scale;
      static const real_t scale_range;
    private:
      uint32_t mesh, product_count;
      int32_t product_id;
      real_t max_structure, theta, r, y;
      real_t structure;
    public:

      // Reset state to an asteroid at the same location, but with a
      // different product, mesh, and max structure.
      void reset_stats(const Asteroid &reference);
      
      // Reset state to an effectively-invincible asteroid at the same
      // location with the default mesh and no product
      void reset_stats();

      // Make a fully-healed copy of the given asteroid, with a different location.
      Asteroid(real_t theta,real_t r,real_t y,const Asteroid &reference);

      Asteroid(Dictionary d,uint32_t mesh);

      // Make an effectively invincible asteroid with mesh 0 at location 0:
      Asteroid();
      
      ~Asteroid();

      // Updates the location of the asteroid. If the state is
      // invalid, this will also initialize the hash and random
      // colors.
      void update_state(AsteroidState &state,real_t orbit_period,real_t inner_radius,real_t thickness);

      // Calculate the full transform for a multimesh instance based
      // on cached, non-time-varying, information in the asteroid
      // state.
      Transform calculate_transform(const AsteroidState &state) const;

      // Receive a specified amount of damage:
      inline double take_damage(double damage) {
        double structure_remaining = structure-damage;
        if(structure_remaining>0) {
          structure = structure_remaining;
          return 0;
        }
        structure = 0;
        return damage;
      }

      // Does the asteroid have any structure left?
      inline bool is_alive() const {
        return structure;
      }

      // When it explodes, should this asteroid generate flotsam?
      inline bool has_cargo() const {
        return product_id>=0 and product_count>0;
      }

      // Is this asteroid effectively invincible?
      inline bool is_invincible() const {
        max_structure>=effectively_infinite_hitpoints;
      }

      
      // Accessors and mutators
      
      inline Vector3 get_xyz(const AsteroidState &state) const {
        return Vector3(state.x,y,state.z);
      }
      inline Vector3 get_x0z(const AsteroidState &state) const {
        return Vector3(state.x,0,state.z);
      }
      
      inline real_t get_y() const {
        return y;
      }
      inline void set_y(real_t y) {
        this->y=y;
      }
      
      inline real_t get_theta() const {
        return theta;
      }
      inline void set_theta(real_t theta) {
        this->theta = theta;
      }
      
      inline real_t get_r() const {
        return r;
      }
      inline void set_r(real_t r) {
        this->r=r;
      }
     
      inline uint32_t get_mesh() const {
        return mesh;
      }
      inline void set_mesh(uint32_t mesh) {
        this->mesh=mesh;
      }

      inline int32_t get_product_id() const {
        return product_id;
      }
      inline void set_product_id(int32_t product_id) {
        this->product_id=product_id;
      }

      inline uint32_t get_product_count() const {
        return product_count;
      }
      inline void set_product_count(uint32_t product_count) {
        this->product_count=product_count;
      }

      inline real_t get_max_structure() const {
        return max_structure;
      }
      inline void set_max_structure(real_t max_structure) {
        this->max_structure = max_structure;
      }

      inline double get_structure() const {
        return structure;
      }
      inline void set_structure(double structure) {
        this->structure=structure;
      }
    };

    ////////////////////////////////////////////////////////////////////////

    class AsteroidPalette {
      std::vector<Asteroid> asteroids;
      std::vector<Ref<Mesh>> meshes;
      std::vector<real_t> accumulated_weights;
      static const Asteroid default_asteroid;
    public:
      AsteroidPalette(Array selection);
      const Asteroid &random_choice(CheapRand32 &rand) const;
      inline const std::vector<Ref<Mesh>> get_meshes() const {
        return meshes;
      }
      size_t count() const {
        return asteroids.size();
      }
      bool empty() const {
        return asteroids.empty();
      }
    };
    
    ////////////////////////////////////////////////////////////////////

    class AsteroidField {
      static const unsigned asteroid_layer_number_bit_shift = 32;
      static const uint64_t max_asteroids_per_layer = 1ULL << asteroid_layer_number_bit_shift;
      static const uint64_t asteroid_layer_mask = 0xffffffff00000000ULL;
      static const uint64_t index_layer_mask = 0xffffffffULL;

      struct AsteroidSearchResult {
        real_t start_theta, end_theta;
        bool any_intersect, all_intersect;
      };
      
      struct AsteroidLayer {
        // Represents all asteroids with the same orbital speed and region.
        // Not intended to be used outside AsteroidField.
        
        const real_t orbit_period, inner_radius, thickness, spacing, y;
        
        typedef std::vector<Asteroids> asteroid_storage;
        typedef typename asteroid_storage::iterator asteroid_storage_iter;
        typedef typename asteroid_storage::const_iterator asteroid_storage_citer;
        
        // All asteroids, sorted by angle and radius
        std::vector<Asteroid> asteroids;

        // Cached state of each asteroid.
        mutable std::vector<AsteroidState> state;
        
        AsteroidLayer(real_t orbit_period, real_t inner_radius, real_t thickness, real_t spacing, real_t y);
        
        ~AsteroidLayer();

        inline Asteroid *get_asteroid(object_id id) {
          return (id<0 or id>=asteroids.size()) ? nullptr : &asteroids[id];
        }

        inline const Asteroid *get_asteroid(object_id id) const {
          return (id<0 or id>=asteroids.size()) ? nullptr : &asteroids[id];
        }

        // Get, make, or update an AstroidState, assuming the id is a valid index and a is non-null
        inline AsteroidState *get_valid_state(object_id id, const Asteroid *a, real_t time) {
          AsteroidState *s = &state[id];
          if(s->needs_update_to(time))
            a->update_state(*s,orbit_period,inner_radius,thickness);
          return s;
        }
        inline const AsteroidState *get_valid_state(object_id id, const Asteroid *a, real_t time) const {
          AsteroidState *s = &state[id];
          if(s->needs_update_to(time))
            a->update_state(*s,orbit_period,inner_radius,thickness);
          return s;
        }

        int find_theta(real_t theta) const;
        AsteroidSearchResult theta_range_of_circle(Vector2 center,real_t radius);
        std::pair<AsteroidSearchResult,AsteroidSearchResult> theta_ranges_of_ray(Vector2 start,Vector2 end);
        
        void create_asteroids(const vector<real_t> &accumulated_weights,const vector<Asteroid> &reference_asteroids);

      private:
        void sort_asteroids();
      };

      AsteroidPalette palette;
      vector<AsteroidLayer> layers;
      ObjectIdGenerator idgen;
      double now;
      unordered_set<object_id> dead_asteroids;
      std::unordered_map<String,std::shared_ptr<const Salvage>> salvage;
      
    public:

      AsteroidField(real_t now,Array data);
      
      std::pair<const Asteroid*,const AsteroidState *> get(object_id id) const;

      void damage_asteroid(object_id id,real_t amount);
      
      void step_time(int64_t idelta,real_t delta,Rect2 visible_region);
      void add_content(Rect2 visible_region) const;
      
      std::size_t overlapping_rect(Rect2 rect,std::unordered_set<object_id> &results) const;
      std::size_t overlapping_circle(Vector2 center,real_t radius,std::unordered_set<object_id> &results) const;
      std::size_t overlapping_point(Vector2 point,std::unordered_set<object_id> &results) const;
      object_id cast_ray(Vector2 start,Vector2 end) const;

    private:
      inline std::pair<int,int> split_id(object_id id) {
        if(id<0)
          return std::pair<int,int>(-1,-1);
        else
          return std::pair<int,int>(id>>asteroid_layer_number_bit_shift,id&index_layer_mask);
      }
      inline object_id combined_id(int layer,int index) {
        if(layer<0 or index<0)
          return -1;
        else
          return (static_cast<uint64_t>(layer)<<asteroid_layer_number_bit_shift) |
            (static_cast<uint64_t>(index)&index_layer_mask);
      }
      
      object_id next_id(int layer) {
        return combined_id(layer,idgen.next());
      }
      
    };
  }
}

#endif
