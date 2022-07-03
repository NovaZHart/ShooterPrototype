#ifndef FACTION_HPP
#define FACTION_HPP

#include <unordered_map>

#include <Color.hpp>
#include <NodePath.hpp>
#include <Vector3.hpp>
#include <RID.hpp>
#include <Dictionary.hpp>

#include "CE/Types.hpp"
#include "CE/Planet.hpp"
#include "CE/Constants.hpp"

namespace godot {
  namespace CE {
    struct FactionGoal {
      const goal_action_t action;
      const faction_index_t target_faction;
      const RID target_rid; // Of planet, or RID() for system
      const object_id target_object_id; // Of planet, or -1 for system
      const float weight;
      const float radius;
      float goal_success, spawn_desire;
      Vector3 suggested_spawn_point;
      NodePath suggested_spawn_path;
      static goal_action_t action_enum_for_string(String string_goal);
      static object_id id_for_rid(const RID &rid,const rid2id_t &rid2id);
      inline void clear() {
        goal_success = 0.0f;
        spawn_desire = -std::numeric_limits<float>::infinity();
        suggested_spawn_point = Vector3(0.0f,0.0f,0.0f);
        suggested_spawn_path = NodePath();
      }
      FactionGoal(Dictionary dict,const std::unordered_map<object_id,Planet> &planets,
                  const rid2id_t &rid2id);
      ~FactionGoal();
    };

    struct ShipGoalData {
      float threat; // Ship.threat
      float distsq; // square of distance to target location
      faction_mask_t faction_mask; // Ship.faction_mask
      Vector3 position; // Ship.position
    };

    struct PlanetGoalData {
      float goal_status;
      float spawn_desire;
      object_id planet;
    };

    struct TargetAdvice {
      goal_action_t action;
      float target_weight, radius;
      object_id planet;
      Vector3 position;
    };

    struct Faction {
      const faction_index_t faction_index;
      const float threat_per_second;
      const Color faction_color;
      static inline int affinity_key(const faction_index_t from_faction,
                                     const faction_index_t to_faction) {
        return to_faction | (from_faction<<FACTION_BIT_SHIFT);
      }

      Faction(Dictionary dict,const std::unordered_map<object_id,Planet> &planets,
              const rid2id_t &rid2id);
      ~Faction();

      void update_masks(const std::unordered_map<int,float> &affinities);
      void make_state_for_gdscript(Dictionary &factions);

      inline const std::vector<FactionGoal> &get_goals() const {
        return goals;
      }
      inline std::vector<FactionGoal> &get_goals() {
        return goals;
      }
      inline const std::vector<TargetAdvice> &get_target_advice() const {
        return target_advice;
      }
      inline std::vector<TargetAdvice> &get_target_advice() {
        return target_advice;
      }
      inline void clear_target_advice(int nplanets) {
        target_advice.reserve(nplanets*goals.size());
        target_advice.clear();
      }
      inline faction_mask_t get_enemy_mask() const {
        return enemy_mask;
      }
      inline faction_mask_t get_friend_mask() const {
        return friend_mask;
      }
      inline void recoup_resources(float resources) {
        recouped_resources+=std::max(resources,0.0f);
      }
    private:
      float recouped_resources;
      std::vector<FactionGoal> goals;
      std::vector<TargetAdvice> target_advice;
      faction_mask_t enemy_mask, friend_mask;
    };


    typedef std::unordered_map<faction_index_t,Faction> factions_t;
    typedef std::unordered_map<faction_index_t,Faction>::iterator factions_iter;
    typedef std::unordered_map<faction_index_t,Faction>::const_iterator factions_const_iter;
  }
}

#endif
