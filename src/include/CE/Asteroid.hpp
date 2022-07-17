#ifndef ASTEROIDS_HPP
#define ASTEROIDS_HPP

#include <vector>
#include <cstdint>
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

#include "PropertyMacros.hpp"
#include "CE/CheapRand32.hpp"
#include "CE/CelestialObject.hpp"
#include "CE/DamageArray.hpp"

namespace godot {
  namespace CE {
    class MultiMeshManager;
    class SalvagePalette;
    class Asteroid;
    class AsteroidLayer;
    
    class AsteroidState {
      friend class Asteroid;
      
      // Stores the time-varying state and expensive calculations for one asteroid.
      // Updated as needed by Asteroid::update_state

      // Special constant for valid_time that indicates the state is uninitialized.
      // Should be positive so time<invalid_time is true.
      static constexpr real_t invalid_time = -1e20;

      // Location of the asteroid.
      real_t x,z;

      // Other derived quantities
      real_t rotation_speed, scale, max_structure;
      double structure;

      // Four random numbers generated from a relatively-expensive hash calculation:
      Color random_numbers;

    private:
      // Last time at which Asteroid::update_state was called:
      real_t valid_time;

    public:
      PROP_GET_VAL(real_t,rotation_speed);
      PROP_GET_VAL(real_t,scale);
      PROP_GET_VAL(real_t,x);
      PROP_GET_VAL(real_t,z);
      PROP_GET_VAL(real_t,max_structure);
      PROP_GET_VAL(double,structure);
      PROP_GETSET_REF(Color,random_numbers);
      PROP_GETSET_VAL(real_t,valid_time);
      
      inline const Color &get_instance_data() const {
        return random_numbers;
      }
      
      // Does this state match that time?
      inline bool needs_update_to(real_t time) const {
        return time!=valid_time;
      }

      inline Vector2 get_xz() const {
        return Vector2(x,z);
      }
      
      // Does the state have valid data?
      inline bool is_valid() const {
        return valid_time!=invalid_time;
      }
      
      // Pretend the state has invalid data so the next call to update_state will calculate it.
      inline void invalidate() {
        valid_time=invalid_time;
      }

      // Create a new AsteroidState with an invalid state.
      AsteroidState():
        x(0),z(0),rotation_speed(0),scale(1),
        max_structure(EFFECTIVELY_INFINITE_HITPOINTS),structure(max_structure),
        random_numbers(0,0,0,0),valid_time(invalid_time)
      {}
      inline ~AsteroidState() {}
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
      String salvage;

      // Structure of asteroid of unit radius when totally undamaged.
      real_t max_structure;

      // Resistance of asteroid to various damage types;
      DamageArray resistances;

    public:

      static const DamageArray default_resistances;

      AsteroidTemplate(const Dictionary &dict,object_id mesh_id=-1);
      AsteroidTemplate();
      ~AsteroidTemplate();

      // Does this template have what is needed for an asteroid to be visible on the screen?
      inline bool is_visible() const {
        return mesh_id>=0;
      }

      // When an asteroid made from template is destroyed, should it leave behind flotsam?
      inline bool has_cargo() const {
        return !salvage.empty();
      }
      inline const String &get_cargo() const {
        return salvage;
      }
      
      PROP_GETSET_VAL(object_id,mesh_id);
      PROP_GETSET_REF(Ref<Mesh>,mesh);
      PROP_GETSET_REF(Color,color_data);
      PROP_GETSET_REF(String,salvage);
      PROP_GETSET_VAL(real_t,max_structure);
      PROP_GET_REF(DamageArray,resistances);
      
      inline bool is_invincible() const {
        return max_structure == EFFECTIVELY_INFINITE_HITPOINTS;
      }
    };

    ////////////////////////////////////////////////////////////////////
    
    class Asteroid: public CelestialObject {
      friend class AsteroidLayer;
      friend class AsteroidField;
      
      object_id id;

      std::shared_ptr<const AsteroidTemplate> templ;
      
      // Location of the asteroid in a cylindrical coordinate system at time 0
      real_t theta, r, y;

      // Cached values of time-varying state of asteroid, updated as needed.
      mutable AsteroidState state;
      
    public:

      // Make a fully-healed copy of the given asteroid, with a different location.
      Asteroid(object_id id,real_t theta,real_t r,real_t y,std::shared_ptr<const AsteroidTemplate> templ):
        CelestialObject(ASTEROID),
        id(id), templ(templ), theta(theta), r(r), y(y),
        state()
      {}

      // Make an effectively invincible asteroid at location 0 with no mesh
      Asteroid():
        CelestialObject(ASTEROID),
        id(-1), templ(), theta(0), r(0), y(0), state()
      {}
      
      ~Asteroid() {}

      PROP_GET_VAL(object_id,id);

      void get_object_info(CelestialInfo &info) const override;
      object_id get_object_id() const override;
      real_t get_object_radius() const override;
      Vector3 get_object_xyz() const override;
      Vector2 get_object_xz() const override;

      inline const Color &get_instance_data() const {
        return state.get_instance_data();
      }

      inline real_t get_rotation_speed() const {
        return state.rotation_speed;
      }

      // Marks the cached state information as extremely old, so it
      // will be updated next time an automatic update check happens.
      inline void invalidate_state() {
        state.invalidate();
      }

      inline real_t get_scale() const {
        return state.scale;
      }
      inline real_t get_radius() const {
        return get_scale();
      }
      
      inline bool is_state_valid() const {
        return state.is_valid();
      }

      inline const DamageArray &get_resistances() const {
        return templ ? templ->get_resistances() : AsteroidTemplate::default_resistances;
      }
      
      // inline real_t calculate_rotation_speed(const AsteroidState &state) const {
      //   return state.random_numbers.r * max_rotation_speed;
      // }

      inline real_t calculate_rotation_phase() const {
        return state.random_numbers.g * TAUf;
      }

      // inline real_t calculate_scale() const {
      //   return state.random_numbers.b*scale_range + min_scale;
      // }

      // Updates the location of the asteroid. If the state is
      // invalid, this will also initialize the hash and random
      // colors.
      void update_state(real_t when,real_t orbit_period,real_t inner_radius,
                        real_t max_rotation_speed,real_t min_scale,real_t scale_range) const;

      // Calculate the full transform for a multimesh instance based
      // on cached information in the asteroid state.
      Transform calculate_transform() const;
      
      inline std::shared_ptr<const AsteroidTemplate> get_template() const {
        return templ;
      }
      
      // Reset state to an asteroid at the same location, fully
      // healed, and with different stats
      void set_template(std::shared_ptr<const AsteroidTemplate> reference);

      inline real_t get_max_structure() const {
        return templ ? templ->get_max_structure()*get_radius() : EFFECTIVELY_INFINITE_HITPOINTS;
      }

      // How much structure is left?
      inline double get_structure() const {
        return state.structure;
      }

      // What is the name in the SalvagePalette of the flotsam that
      // should be created when this asteroid is destroyed?
      inline String get_cargo() const {
        return templ ? templ->get_cargo() : String();
      }
      
      // Should this asteroid be shown if it is on camera?
      inline bool is_visible() const {
        return is_alive() and templ and templ->is_visible();
      }
      
      // Does the asteroid have any structure left?
      inline bool is_alive() const {
        return state.structure>0;
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
      inline Vector2 get_xz() const {
        return Vector2(state.x,state.z);
      }
      
      // Full 3D location
      inline Vector3 get_xyz() const {
        return Vector3(state.x,y,state.z);
      }

      // 3D location with y=0
      inline Vector3 get_x0z() const {
        return Vector3(state.x,0,state.z);
      }

      // Get/set current y location
      PROP_GETSET_VAL(real_t,y);

      // Get/set angle in cylindrical coordinate system.
      PROP_GETSET_VAL(real_t,theta);

      // Get/set radius in cylindrical coordinate system.
      PROP_GETSET_VAL(real_t,r);

      // Get/set mesh index within palette
      inline Ref<Mesh> get_mesh() const {
        return templ ? templ->get_mesh() : Ref<Mesh>();
      }
      
      // Get/set salvage name
      inline const String &get_salvage() const {
        static const String empty_string="";
        return templ ? templ->get_salvage() : empty_string;
      }

    private:
      // Damage must be private so only AsteroidField can apply it.
      
      // Asteroid heals some amount of damage.
      inline void heal_asteroid(real_t amount) {
        state.structure = std::min(double(get_max_structure()),state.structure+amount);
      }

      // Fully heal asteroid
      inline void heal_asteroid() {
        state.structure = get_max_structure();
      }

      // Receive a specified amount of damage:
      real_t take_damage(real_t damage,int type);
    };
    
    ////////////////////////////////////////////////////////////////////////

    class AsteroidPalette {
      // A set of possible asteroid templates that can be used in an
      // asteroid field.  Both vectors have the same length.
      
      // All possible asteroids.
      std::vector<std::shared_ptr<AsteroidTemplate>> asteroids;

      // Weights for randomly selecting asteroids. These are
      // accumulated weights, so weight n > weight n-1
      std::vector<real_t> accumulated_weights;

      // The asteroid template used if asteroids.size()==0
      static std::shared_ptr<const AsteroidTemplate> default_asteroid;
    public:
      AsteroidPalette();
      AsteroidPalette(Array selection);
      AsteroidPalette(const AsteroidPalette &a,bool deep_copy);

      // Iterators are over asteroids.
      std::vector<std::shared_ptr<AsteroidTemplate>>::iterator begin() {
        return asteroids.begin();
      }

      std::vector<std::shared_ptr<AsteroidTemplate>>::iterator end() {
        return asteroids.end();
      }

      std::vector<std::shared_ptr<AsteroidTemplate>>::const_iterator begin() const {
        return asteroids.begin();
      }

      std::vector<std::shared_ptr<AsteroidTemplate>>::const_iterator end() const {
        return asteroids.end();
      }
      
      // Randomly choose an asteroid, or return default_asteroid if there
      // are no asteroids. Uses the provided random number generator.
      std::shared_ptr<const AsteroidTemplate> random_choice(CheapRand32 &rand) const;

      // What asteroid will be provided if this->empty()
      static inline std::shared_ptr<const AsteroidTemplate> get_default_asteroid() {
        if(!default_asteroid)
          default_asteroid=std::make_shared<AsteroidTemplate>();
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
