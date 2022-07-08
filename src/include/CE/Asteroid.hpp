#ifndef ASTEROIDS_HPP
#define ASTEROIDS_HPP

#include <vector>
#include <cstdint>
#include <string>
#include <memory>

#include "Ref.hpp"
#include "Mesh.hpp"
#include "Array.hpp"
#include "Godot.hpp"
#include "Color.hpp"
#include "Transform.hpp"
#include "Dictionary.hpp"
#include "Vector2.hpp"
#include "Vector3.hpp"

#include "CE/CheapRand32.hpp"

namespace godot {
  namespace CE {

    struct AsteroidState {
      // Stores the time-varying state and expensive calculations for one asteroid.
      // Updated as needed by Asteroid::update_state

      // Special constant for valid_time that indicates the state is uninitialized.
      // Should be positive so time<invalid_time is true.
      static constexpr real_t invalid_time = -1e20;

      // Location of the asteroid.
      real_t x,z;

      // Relatively expensive hash calculation from Asteroid members:
      CheapRand32 rand;

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
      // Maximum speed an asteroid can rotate around its randomly-chosen axis
      static const real_t max_rotation_speed;

      // Minimum x,y,z scale of asteroid
      static const real_t min_scale;

      // Maximum x,y,z scale of asteroid
      static const real_t max_scale;

      // max_scale-min_scale
      static const real_t scale_range;
    private:
      // Mesh for this asteroid
      int mesh_index;

      // Name of the flotsam from the SalvagePalette for when this asteroid is destroyed
      wstring salvage;

      // Structure of asteroid when totally undamaged.
      real_t max_structure;

      // Location of the asteroid in a cylindrical coordinate system at time 0
      real_t theta, r, y;

      // Current structure of the asteroid, between 0 and max_structure.
      double structure;
    public:

      // Make a fully-healed copy of the given asteroid, with a different location.
      Asteroid(real_t theta,real_t r,real_t y,const Asteroid &reference);

      // Generates an asteroid from the specified data.
      Asteroid(Dictionary d,int mesh_index);

      // Make an effectively invincible asteroid with mesh 0 at location 0:
      Asteroid();
      
      ~Asteroid();

      // Reset state to an asteroid at the same location, but with a
      // different salvage, mesh, and max structure.
      void reset_stats(const Asteroid &reference);
      
      // Reset state to an effectively-invincible asteroid at the same
      // location with the default mesh and no salvage
      void reset_stats();

      // Updates the location of the asteroid. If the state is
      // invalid, this will also initialize the hash and random
      // colors.
      void update_state(AsteroidState &state,real_t orbit_period,real_t inner_radius,real_t thickness);

      // Calculate the full transform for a multimesh instance based
      // on cached information in the asteroid state.
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

      // Asteroid heals some amount of damage.
      inline void heal_asteroid(double amount) {
        structure = min(static_cast<double>(max_structure),structure+amount);
      }

      // Fully heal asteroid
      inline void heal_asteroid() {
        structure = max_structure;
      }

      // How much structure is left?
      inline double get_structure() const {
        return structure;
      }
      
      // Does the asteroid have any structure left?
      inline bool is_alive() const {
        return structure;
      }

      // When it explodes, should this asteroid generate flotsam?
      inline bool has_cargo() const {
        return !salvage.empty();
      }

      // Is this asteroid effectively invincible?
      inline bool is_invincible() const {
        max_structure>=effectively_infinite_hitpoints;
      }

      // Full 3D location
      inline Vector3 get_xyz(const AsteroidState &state) const {
        return Vector3(state.x,y,state.z);
      }

      // 3D location with y=0
      inline Vector3 get_x0z(const AsteroidState &state) const {
        return Vector3(state.x,0,state.z);
      }

      // Get/set current y location
      inline real_t get_y() const {
        return y;
      }
      inline void set_y(real_t y) {
        this->y=y;
      }

      // Get/set angle in cylindrical coordinate system.
      inline real_t get_theta() const {
        return theta;
      }
      inline void set_theta(real_t theta) {
        this->theta = theta;
      }

      // Get/set radius in cylindrical coordinate system.
      inline real_t get_r() const {
        return r;
      }
      inline void set_r(real_t r) {
        this->r=r;
      }

      // Get/set mesh index within palette
      inline int get_mesh_index() const {
        return mesh_index;
      }
      inline void set_mesh_index(int mesh) {
        this->mesh_index=mesh_index;
      }
      
      // Get/set salvage name
      inline const wstring &get_salvage() const {
        return salvage;
      }
      inline void set_salvage(const wstring &salvage) const {
        this->salvage=salvage;
      }

      // Get maximum structure.
      inline real_t get_max_structure() const {
        return max_structure;
      }

      // Set maximum structure, and reduce structure if it is higher than that.
      inline void set_max_structure(real_t max_structure) {
        this->max_structure = max_structure;
        structure = min(structure,static_cast<double>(this->max_structure));
      }
    };

                    
    ////////////////////////////////////////////////////////////////////////

    class AsteroidPalette {
      // A set of possible asteroids that can be generated in an asteroid field.
      // All vectors have the same length.
      
      // All possible asteroids.
      std::vector<Asteroid> asteroids;

      // Mesh paths for each asteroid.
      std::vector<String> mesh_path;

      // Weights for randomly selecting asteroids. These are
      // accumulated weights, so weight n > weight n-1
      std::vector<real_t> accumulated_weights;

      // The asteroid used if asteroids.size()==0
      static const Asteroid default_asteroid;
    public:
      AsteroidPalette(Array selection,std::shared_ptr<SalvagePalette> salvage);

      // Randomly choose an asteroid, or return default_asteroid if there
      // are no asteroids. Uses the provided random number generator.
      const Asteroid &random_choice(CheapRand32 &rand) const;

      // Return all mesh paths. Each asteroid provides the integer
      // (object_id) index within this list.
      inline const std::vector<String> get_meshes() const {
        return mesh_paths;
      }

      // What asteroid will be provided if this->empty()
      static inline const Asteroid &get_default_asteroid() {
        return default_asteroid;
      }
      
      // How many asteroids are in the palette?
      size_t size() const {
        return asteroids.size();
      }

      // Is the palette empty?
      bool empty() const {
        return asteroids.empty();
      }
    };

  }
}

#endif
