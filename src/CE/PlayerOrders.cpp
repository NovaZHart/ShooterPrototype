#include "CE/Data.hpp"
#include "CE/Utils.hpp"
#include "CE/MultiMeshManager.hpp"

#include <cstdint>
#include <cmath>
#include <limits>

#include <GodotGlobal.hpp>
#include <PhysicsDirectBodyState.hpp>
#include <PhysicsShapeQueryParameters.hpp>
#include <NodePath.hpp>

using namespace godot;
using namespace godot::CE;
using namespace std;

GoalsArray::GoalsArray() {
  for(int i=0;i<PLAYER_ORDERS_MAX_GOALS;i++)
    goal[i] = 0;
}

GoalsArray::GoalsArray(const Array &a) {
  int i=0, s=a.size();
  for(;i<PLAYER_ORDERS_MAX_GOALS && i<s;i++)
    goal[i] = static_cast<int>(a[i]);
  for(;i<PLAYER_ORDERS_MAX_GOALS;i++)
    goal[i] = 0;
}

PlayerOverrides::PlayerOverrides():
  manual_thrust(0),
  manual_rotation(0),
  orders(0),
  change_target(0),
  target_id(-1),
  goals()
{}

PlayerOverrides::PlayerOverrides(Dictionary from,const rid2id_t &rid2id):
  manual_thrust(get<real_t>(from,"manual_thrust")),
  manual_rotation(get<real_t>(from,"manual_rotation")),
  orders(get<int>(from,"orders")),
  change_target(get<int>(from,"change_target")),
  target_id(rid2id_default(rid2id,get<RID>(from,"target_rid").get_id(),-1)),
  goals(get<Array>(from,"goals"))
{}

PlayerOverrides::~PlayerOverrides() {}
