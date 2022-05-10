#include "SpaceHash.hpp"

using namespace godot;

godot::IntRect2::IntRect2(const Rect2 &real_rect,real_t position_box_size) {
  Vector2 real_start=real_rect.position, real_end=real_start+real_rect.size;
    
  if(real_rect.size.x<0)
    std::swap(real_start.x,real_end.x);
  if(real_rect.size.y<0)
    std::swap(real_start.y,real_end.y);
    
  IntVector2 start(real_start,position_box_size);
  IntVector2 end(real_end,position_box_size);
    
  position = IntVector2(real_start,position_box_size);
  size.x = end.x-start.x+1;
  size.y = end.y-start.y+1;
}

godot::IntRect2 godot::IntRect2::positive_size() {
  IntRect2 r(*this);
  if(size.x<0) {
    position.x=position.x+size.x+1;
    size.x=-size.x;
  }
  if(size.y<0) {
    position.y=position.y+size.y+1;
    size.y=-size.y;
  }
  return r;
}
