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
    class MultiMeshManager;
    
    struct AsteroidState {
      // Stores the time-varying state and expensive calculations for one asteroid.
      // Updated as needed by Asteroid::update_state

      // Special constant for valid_time that indicates the state is uninitialized.
      // Should be positive so time<invalid_time is true.
      static constexpr real_t invalid_time = -1e20;

      // Location of the asteroid.
      real_t x,z;

      // Four random numbers generated from a relatively-expensive hash calculation:
      Color random_numbers;

    private:
      // Last time at which Asteroid::update_state was called:
      real_t valid_time;

    public:
      inline const Color &get_instance_data() const {
        return random_numbers;
      }
      
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
        x(0),y(0),valid_time(invalid_time),random_numbers(0,0,0,0)
      {}
      ~AsteroidState() {}
    };

    ////////////////////////////////////////////////////////////////////
    
    class AsteroidTemplate {
      // Stores data that is common among many asteroids.
      
      // Mesh for this asteroid
      Ref<Mesh> mesh;

      // Mesh ID from a MultimeshManager
      object_id mesh_id;

      // Color sent to asteroid mesh's shader
      Color color_data;
      
      // Name of the flotsam from the SalvagePalette for when this asteroid is destroyed
      wstring salvage;

      // Structure of asteroid when totally undamaged.
      real_t max_structure;

    public:
      AsteroidTemplate(const Dictionary &dict,object_id mesh_id=-1);
      AsteroidTemplate();
      ~AsteroidTemplate();

      // Does this template have what is needed for an asteroid to be visible on the screen?
      inline bool is_visible() const {
        return mesh_id>=0;
      }

      // When an asteroid made from template is destroyed, should it leave behind flotsam?
      inline bool has_cargo() const {
        return salvage;
      }

      inline object_id get_mesh_id() const {
        return mesh_id;
      }
      inline void set_mesh_id(object_id id) {
        mesh_id=id;
      }
      
      inline const Ref<Mesh> &get_mesh() const {
        return mesh;
      }
      inline void set_mesh(const Ref<Mesh> &mesh) {
        this->mesh = mesh;
      }
      
      inline const Color &get_color_data() const {
        return color_data;
      }
      inline void set_color_data(const Color &color_data) {
        this->color_data = color_data;
      }
      
      inline const wstring &get_salvage() const {
        return salvage;
      }
      inline void set_salvage(const wstring &salvage) {
        this->salvage = salvage;
      }

      inline real_t get_max_structure() const {
        return max_structure;
      }
      inline void set_max_structure(real_t max_structure) const {
        this->max_structure = max_structure;
      }

      inline bool is_invincible() const {
        return max_structure == effectively_infinite_hitpoints;
      }
    };

    ////////////////////////////////////////////////////////////////////
    
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

      shared_ptr<const AsteroidTemplate> templ;
      
      // Location of the asteroid in a cylindrical coordinate system at time 0
      real_t theta, r, y;

      // Current structure of the asteroid, between 0 and max_structure.
      double structure;
    public:

      // Make a fully-healed copy of the given asteroid, with a different location.
      Asteroid(real_t theta,real_t r,real_t y,shared_ptr<const AsteroidTemplate> templ):
        templ(templ), theta(theta), r(r), y(y),
        structure(templ ? templ->max_structure : effectively_infinite_structure)
      {}

      // Make an effectively invincible asteroid at location 0 with no mesh
      Asteroid():
        templ(), theta(0), r(0), y(0), structure(effectively_infinite_structure)
      {}
      
      ~Asteroid() {}

      inline real_t calculate_rotation_speed(const AsteroidState &state) const {
        return state.random_numbers.r * max_rotation_speed;
      }

      inline real_t calculate_rotation_phase(const AsteroidState &state) const {
        return state.random_numbers.g * TAUf;
      }

      inline real_t calculate_scale(const AsteroidState &state) const {
        return random_numbers.b*scale_range + min_scale;
      }

      // Updates the location of the asteroid. If the state is
      // invalid, this will also initialize the hash and random
      // colors.
      void update_state(AsteroidState &state,real_t when,real_t orbit_period,real_t inner_radius,real_t thickness,bool initialize);

      // Calculate the full transform for a multimesh instance based
      // on cached information in the asteroid state.
      Transform calculate_transform(const AsteroidState &state) const;

      // Receive a specified amount of damage:
      double take_damage(double damage);
      
      inline shared_ptr<const AsteroidTemplate> get_template() const {
        return templ;
      }
      
      // Reset state to an asteroid at the same location, fully
      // healed, and with different stats
      void set_template(shared_ptr<const AsteroidTemplate> reference);

      inline real_t get_max_structure() const {
        return templ ? templ->get_max_structure() : effectively_infinite_hitpoints;
      }
      
      // Asteroid heals some amount of damage.
      inline void heal_asteroid(double amount) {
        structure = min(double(get_max_structure),structure+amount);
      }

      // Fully heal asteroid
      inline void heal_asteroid() {
        structure = max_structure;
      }

      // How much structure is left?
      inline double get_structure() const {
        return structure;
      }

      // Should this asteroid be shown if it is on camera?
      inline bool is_visible() const {
        return is_alive() and templ and templ->is_visible();
      }
      
      // Does the asteroid have any structure left?
      inline bool is_alive() const {
        return structure;
      }

      // When it explodes, should this asteroid generate flotsam?
      inline bool has_cargo() const {
        return templ && templ->has_cargo();
      }

      // Is this asteroid effectively invincible?
      inline bool is_invincible() const {
        return !templ or templ->is_invincible();
      }

      // 2D location x-z
      inline Vector2 get_xz(const AsteroidState &state) const {
        return Vector2(state.x,state.z);
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
      inline Ref<Mesh> get_mesh() const {
        return templ ? templ->get_mesh() : Ref<Mesh>();
      }
      
      // Get/set salvage name
      inline const wstring &get_salvage() const {
        static const wstring empty_string="";
        return templ ? templ->get_salvage() : empty_string;
      }
    };
    
    ////////////////////////////////////////////////////////////////////////

    class AsteroidPalette {
      // A set of possible asteroid templates that can be used in an
      // asteroid field.  Both vectors have the same length.
      
      // All possible asteroids.
      std::vector<shared_ptr<AsteroidTemplate>> asteroids;

      // Weights for randomly selecting asteroids. These are
      // accumulated weights, so weight n > weight n-1
      std::vector<real_t> accumulated_weights;

      // The asteroid template used if asteroids.size()==0
      static const shared_ptr<const AsteroidTemplate> default_asteroid;
    public:
      AsteroidPalette(Array selection,std::shared_ptr<SalvagePalette> salvage);

      // Randomly choose an asteroid, or return default_asteroid if there
      // are no asteroids. Uses the provided random number generator.
      shared_ptr<const AsteroidTemplate> random_choice(CheapRand32 &rand) const;

      // What asteroid will be provided if this->empty()
      static inline shared_ptr<const AsteroidTemplate> get_default_asteroid() {
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
