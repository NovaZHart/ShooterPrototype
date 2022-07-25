#ifndef COMBATENGINECONSTANTS_HPP
#define COMBATENGINECONSTANTS_HPP
#include <cstdint>

#include <Godot.hpp>

#include "CE/Types.hpp"

namespace godot {
 
  namespace CE {
    constexpr double PI = 3.141592653589793, TAU = 2*PI;
    constexpr real_t PIf = PI, TAUf = TAU;

    // All constants MUST match CombatEngine.gd

    const ticks_t FOREVER = 189000000000; /* more ticks than a game should reach (about 100 years) */
    const ticks_t TICKS_LONG_AGO = -9999; /* for ticks before object began (just needs to be negative) */
    const ticks_t FAST = 9999999; /* faster than any object should move */
    const ticks_t FAR = 9999999; /* farther than any distance that should be considered */
    const ticks_t BIG = 9999999; /* bigger than any object should be */
    const ticks_t SALVAGE_TIME_LIMIT = 60; // How long flotsam remains before vanishing

    const int EFFECTS_LIGHT_LAYER_MASK = 2;

    const faction_mask_t PLAYER_COLLISION_LAYER_BITS = 1;

    constexpr real_t THREAT_EPSILON = 1.0f; /* Threat difference that is considered 0 */
    constexpr real_t AFFINITY_EPSILON = 1e-9f; /* Affinity difference that is considered 0 */
    constexpr real_t DEFAULT_AFFINITY = 0.0f; /* For factions pairs with no affinity */
    
    const int FACTION_BIT_SHIFT = 24;
    const int FACTION_TO_MASK = 16777215; /* 2**FACTION_BIT_SHIFT-1 */
    const faction_mask_t ALL_FACTIONS = FACTION_TO_MASK;
    const int FACTION_ARRAY_SIZE = 64;
    const int MAX_ALLOWED_FACTION = 29;
    const int MIN_ALLOWED_FACTION = 0;
    const int PLAYER_FACTION = 0;
    const int FLOTSAM_FACTION = 1;

    const int NUM_DAMAGE_TYPES = 17;
    enum damage_type {
      DAMAGE_TYPELESS = 0,    /* Damage that ignores resist and passthru (only for story scripts) */
      DAMAGE_LIGHT = 1,       /* Non-standing electromagnetic fields (ie. lasers) */
      DAMAGE_HE_PARTICLE = 2, /* Particles of matter with high kinetic energy (particle beam) */
      DAMAGE_PIERCING = 3,    /* Small macroscopic things moving quickly (ie. bullets) */
      DAMAGE_IMPACT = 4,      /* Larger non-pointy things with high momentum (ie. asteroids) */
      DAMAGE_EM_FIELD = 5,    /* Standing or low-frequency EM fields (ie. EMP or big magnet) */
      DAMAGE_GRAVITY = 6,     /* Strong gravity or gravity waves */
      DAMAGE_ANTIMATTER = 7,  /* Antimatter particles */
      DAMAGE_EXPLOSIVE = 8,   /* Ka-boom! */
      DAMAGE_PSIONIC = 9,     /* Mind over matter */
      DAMAGE_PLASMA = 10,     /* Super-heated matter */
      DAMAGE_CHARGE = 11,     /* Electric charge */
      DAMAGE_RIFT = 12,       /* Tear open rifts in the fabric of spacetime (like a hyperspace rift) */
      DAMAGE_TEMPORAL = 13,   /* Suddenly, half of your ship is running an hour before the other half */
      DAMAGE_BIO = 14,        /* Damage that specifically attacks living things (infections, parasites, etc.) */
      DAMAGE_LIFEFORCE = 15,  /* Directly harms the lifeforce, or soul, of the ship, if it has one */
      DAMAGE_UNREALITY = 16   /* The ultimate damage type: rewriting reality to suit your whims. */
    };
    constexpr real_t MAX_RESIST = 0.75; // Lowest allowed resistance (fraction)
    constexpr real_t MIN_RESIST = -2.0; // Highest allowed resistance (fraction)
    constexpr real_t MIN_PASSTHRU = 0.0;
    constexpr real_t MAX_PASSTHRU = 1.0;

    const real_t MIN_ASTEROID_RESISTANCE = -9.0;
    const real_t MAX_ASTEROID_RESISTANCE = 1.0;

    const real_t ASTEROID_RESPAWN_DELAY = 30.0f;
    
    constexpr real_t PROJECTILE_POINT_WIDTH = 0.001; // Width of bounding square for point projectiles
    const int MAX_PROJECTILES_IN_MINIMAP = 300;
    
    const real_t FLOTSAM_MASS = 10.0;
    const real_t EXPLOSION_FLOTSAM_INITIAL_SPEED = 50.0;
    
    enum visual_layers {
      below_planets=-30,
      asteroid_height=-15,
      flotsam_height=-7,
      below_ships=-5,
      ship_height=5,
      below_projectiles=25,
      projectile_height=27,
      above_projectiles=29
    };
    
    const int max_meshes=50; // For pre-allocating data, expected max meshes (not actual limit)
    const int max_ships=700; // For pre-allocating data, expected max ships (not actual_limit)
    const int max_planets=300; // For pre-allocating data, expected max planets or system entrances (not actual limit)

    const ticks_t ticks_per_second = 10800;
    const ticks_t ticks_per_minute = static_cast<ticks_t>(60)*ticks_per_second;
    const ticks_t zero_ticks = 0;
    const ticks_t inactive_ticks = -1;
    const double thrust_loss_heal = 0.5;

    const double EFFECTIVELY_INFINITE_HITPOINTS = 1e20;
    
    constexpr real_t hyperspace_display_ratio = 20.0f;
  
    enum goal_action_t {
      goal_patrol = 0,  // equal or surpass enemy threat; kill enemies
      goal_raid = 1,    // control airspace or retreat; kill high-value, low-threat, ships
      goal_planet = 2,  // travel from planet to jump, or from jump to planet
      goal_avoid_and_land = 3, // pick a planet with few enemies and land there
      goal_avoid_and_rift = 4 // pick a planet with few enemies, leave from there, exit
    };

    // These enums MUST match globals/CombatEngine.gd.
    enum fate_t { FATED_TO_EXPLODE=-1, FATED_TO_FLY=0, FATED_TO_DIE=1, FATED_TO_LAND=2, FATED_TO_RIFT=3 };
    enum entry_t { ENTRY_COMPLETE=0, ENTRY_FROM_ORBIT=1, ENTRY_FROM_RIFT=2, ENTRY_FROM_RIFT_STATIONARY=3 };
    enum ship_ai_t { ATTACKER_AI=0, PATROL_SHIP_AI=1, RAIDER_AI=2, ARRIVING_MERCHANT_AI=3, DEPARTING_MERCHANT_AI=4 };
    enum ai_flags { DECIDED_NOTHING=0, DECIDED_TO_LAND=1, DECIDED_TO_RIFT=2, DECIDED_TO_FLEE=4,
                    DECIDED_TO_SALVAGE=8, DECIDED_TO_WANDER=16, DECIDED_MISSION_SUCCESS=32,
                    DECIDED_TO_FIGHT=64 };


    // These constants MUST match globals/CombatEngine.gd.

    const float SPATIAL_RIFT_LIFETIME_SECS = 3.0f;
    const ticks_t SPATIAL_RIFT_LIFETIME_TICKS = roundf(SPATIAL_RIFT_LIFETIME_SECS*ticks_per_second);

    const int PLAYER_GOAL_ATTACKER_AI = 1;
    const int PLAYER_GOAL_LANDING_AI = 2;
    const int PLAYER_GOAL_ARRIVING_MERCHANT_AI = 3;
    const int PLAYER_GOAL_INTERCEPT = 4;
    const int PLAYER_GOAL_RIFT = 5;
    
    const int PLAYER_ORDERS_MAX_GOALS = 3;

    const int PLAYER_ORDER_FIRE_PRIMARIES   = 0x0001;
    const int PLAYER_ORDER_STOP_SHIP        = 0x0002;
    const int PLAYER_ORDER_MAINTAIN_SPEED   = 0x0004;
    const int PLAYER_ORDER_AUTO_TARGET      = 0x0008;
    const int PLAYER_ORDER_TOGGLE_CARGO_WEB = 0x0010;
    
    const int PLAYER_TARGET_CONDITION       = 0xF000;
    const int PLAYER_TARGET_NEXT            = 0x1000;
    const int PLAYER_TARGET_NEAREST         = 0x2000;

    const int PLAYER_TARGET_SELECTION       = 0x0F00;
    const int PLAYER_TARGET_ENEMY           = 0x0100;
    const int PLAYER_TARGET_FRIEND          = 0x0200;
    const int PLAYER_TARGET_PLANET          = 0x0400;
    const int PLAYER_TARGET_OVERRIDE        = 0x0800;
    const int PLAYER_TARGET_NOTHING         = 0x0F00;

    const size_t HASH_SQUARE_LENGTH=32;
    const size_t HASH_SQUARE_COUNT_SQRT=4;
  
    const int VISIBLE_OBJECT_PROJECTILE = 0;
    const int VISIBLE_OBJECT_PLANET = 1;
    const int VISIBLE_OBJECT_SHIP = 2;
    const int VISIBLE_OBJECT_HOSTILE = 4;
    const int VISIBLE_OBJECT_PLAYER_TARGET = 8;
    const int VISIBLE_OBJECT_PLAYER = 16;

    const faction_mask_t MASK_ALL_FACTIONS = 0x7ffffff;
    const faction_mask_t PLANET_COLLISION_MASK = 1<<28;
    const size_t NEAR_OBJECTS_MAX_HITS = 100;
    const size_t NEARBY_ENEMIES_MAX_HITS = 100;
    constexpr real_t NEAR_OBJECTS_RANGE = 100.0f;
    const size_t BLAST_RADIUS_MAX_HITS = 100;
    const size_t DETONATION_RANGE_MAX_HITS = 32;
    const size_t ANTIMISSILE_SEARCH_MAX_HITS = 100;
    const size_t SHIP_EXPLOSION_MAX_HITS = 100;
    
    constexpr real_t BLAST_DAMAGE_AT_FULL_RADIUS = 0.25;
    
    // FIXME: Implement this:
    const int VISIBLE_OBJECT_GOAL = 32;

    enum mesheffect_behavior {
      STATIONARY=0,
      CONSTANT_VELOCITY=1,
      CENTER_ON_TARGET1=2,
      VELOCITY_RELATIVE_TO_TARGET=3,
      CENTER_AND_ROTATE_ON_TARGET1=4
    };
  }
}
#endif
