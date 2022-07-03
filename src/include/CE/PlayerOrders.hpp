#ifndef PLAYERORDERS_HPP
#define PLAYERORDERS_HPP

namespace godot {
  namespace CE {
    struct GoalsArray {
      int goal[PLAYER_ORDERS_MAX_GOALS];
      GoalsArray();
      GoalsArray(const Array &);
    };
    
    struct PlayerOverrides {
      const real_t manual_thrust, manual_rotation;
      const int orders, change_target;
      object_id target_id;
      const GoalsArray goals;
      PlayerOverrides();
      PlayerOverrides(Dictionary from,const rid2id_t &rid2id);
      ~PlayerOverrides();
    };

    typedef std::unordered_map<object_id,PlayerOverrides>::iterator player_orders_iter;
  }
}

#endif
