#include "CombatEngineUtils.hpp"

#include <cstdint>

using namespace godot;
using namespace godot::CE;
using namespace std;

// from https://burtleburtle.net/bob/hash/integer.html
uint32_t godot::CE::bob_full_avalanche(uint32_t a) {
    a = (a+0x7ed55d16) + (a<<12);
    a = (a^0xc761c23c) ^ (a>>19);
    a = (a+0x165667b1) + (a<<5);
    a = (a+0xd3a2646c) ^ (a<<9);
    a = (a+0xfd7046c5) + (a<<3);
    a = (a^0xb55a4f09) ^ (a>>16);
    return a;
}

object_id godot::CE::rid2id_default(const rid2id_t &rid2id,const RID &rid,object_id default_id) {
  auto it = rid2id.find(rid.get_id());
  return (it==rid2id.end()) ? default_id : it->second;
}

object_id godot::CE::rid2id_default(const rid2id_t &rid2id,int32_t rid_id,object_id default_id) {
  auto it = rid2id.find(rid_id);
  return (it==rid2id.end()) ? default_id : it->second;
}
