#include "CE/VisualEffects.hpp"
#include "CE/VisibleContent.hpp"
#include "CE/MultiMeshManager.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

VisibleObject::VisibleObject(const godot::CE::Ship &ship,bool hostile):
  x(ship.position.x),
  z(ship.position.z),
  radius((ship.aabb.size.x+ship.aabb.size.z)/2.0),
  rotation_y(ship.rotation.y),
  vx(ship.linear_velocity.x),
  vz(ship.linear_velocity.z),
  max_speed(ship.max_speed),
  flags(VISIBLE_OBJECT_SHIP | ( hostile ? VISIBLE_OBJECT_HOSTILE : 0 ))
{}

VisibleObject::VisibleObject(const Planet &planet):
  x(planet.position.x),
  z(planet.position.z),
  radius(planet.radius),
  rotation_y(0),
  vx(0),
  vz(0),
  max_speed(0),
  flags(VISIBLE_OBJECT_PLANET)
{}

VisibleEffect::VisibleEffect(const Projectile &projectile):
  rotation_y(projectile.rotation.y),
  scale_x(projectile.direct_fire ? projectile.scale : 0),
  scale_z(0),
  y(projectile.visual_height),
  center(projectile.position.x,projectile.position.z),
  half_size(projectile.direct_fire ? Vector2(projectile.scale,projectile.scale) : Vector2(0.1f,0.1f)),
  data(),
  mesh_id(projectile.mesh_id)
{}

VisibleEffect::VisibleEffect(const MultiMeshInstanceEffect &effect):
  rotation_y(effect.rotation),
  scale_x(1),
  scale_z(1),
  y(effect.position.y),
  center(effect.position.x,effect.position.z),
  half_size(effect.half_size),
  data(effect.data),
  mesh_id(effect.mesh_id)
{}

VisibleContentManager::VisibleContentManager():
  new_content(nullptr), visible_content(nullptr)
{}
VisibleContentManager::~VisibleContentManager() {
  clear();
}
void VisibleContentManager::clear() {
  VisibleContent *content=new_content;
  new_content=nullptr;
  visible_content=nullptr;
  while(content) {
    VisibleContent *next=content->next;
    delete content;
    content=next;
  }
}
VisibleContent *VisibleContentManager::push_content(VisibleContent *next) {
  next->next=new_content;
  new_content=next;
  return next;
}

std::pair<bool,VisibleContent*> VisibleContentManager::update_visible_content() {
  FAST_PROFILING_FUNCTION;
  if(!new_content)
    // Nothing to display yet.
    return std::pair<bool,VisibleContent*>(false,nullptr);
  if(new_content==visible_content)
    // Nothing new to display.
    return std::pair<bool,VisibleContent*>(false,visible_content);
  visible_content = new_content;
  
  // Delete content from prior frames, and any content we skipped:
  VisibleContent *delete_list = visible_content->next;
  visible_content->next=nullptr;
  while(delete_list) {
    VisibleContent *delete_me=delete_list;
    delete_list=delete_list->next;
    delete delete_me;
  }

  return std::pair<bool,VisibleContent*>(true,visible_content);
}
