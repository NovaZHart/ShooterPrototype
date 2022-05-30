#ifndef SPACEHASH_H
#define SPACEHASH_H

#include <algorithm>
#include <unordered_set>
#include <unordered_map>

#include <Vector2.hpp>
#include <Rect2.hpp>

#include <CombatEngineUtils.hpp>

namespace godot {
  struct IntVector2 {
    int x,y;
    IntVector2(): x(0),y(0) {}
    explicit inline IntVector2(int x,int y): x(x), y(y) {}
    explicit inline IntVector2(Vector2 v,real_t position_box_size):
      x(floorf(v.x/position_box_size)),
      y(floorf(v.y/position_box_size))
    {}
    bool operator == (const IntVector2 &o) const { return o.x==x and o.y==y; }
    bool operator != (const IntVector2 &o) const { return o.x!=x or o.y!=y; }
  };

  template<>
  inline String str<IntVector2>(const IntVector2 &t) {
    return str("(x=")+str(t.x)+",y="+str(t.y)+")";
  }

  inline Rect2 rect_for_circle(Vector2 c,real_t r) {
    return Rect2(c.x-r,c.y-r,2*r,2*r);
  }
  inline Rect2 rect_for_circle(Vector3 c,real_t r) {
    return Rect2(c.z-r,-c.x-r,2*r,2*r);
  }
  
  struct IntRect2 {
    IntVector2 position,size;
    inline bool contains(const IntVector2 &i) {
      return i.x>position.x and i.y>position.y and i.x-position.x<size.x and i.y-position.y<size.y;
    }
    IntRect2(): position(), size() {}
    explicit IntRect2(const Rect2 &rect,real_t position_box_size);
    explicit inline IntRect2(const IntVector2 &position,const IntVector2 &size):
      position(position),
      size(size)
    {}
    IntRect2 positive_size();
    bool operator == (const IntRect2 &o) const { return o.position==position and o.size==size; }
    bool operator != (const IntRect2 &o) const { return o.position!=position or o.size!=size; }
  };

  template<>
  inline String str<IntRect2>(const IntRect2 &t) {
    return "("+str(t.size.x)+", "+str(t.size.y)+", "+str(t.position.x)+", "+str(t.position.y)+")";
  }
}

namespace std {
  template<> struct hash<godot::IntVector2> {
    const hash<int> h;
    size_t operator()(const godot::IntVector2 &i) const {
      size_t xhash=h(i.x),yhash=h(i.y);
      return xhash ^ (yhash + 0x9e3779b9 + (xhash << 6) + (xhash >> 2));
    }
  };
}
  
namespace godot {
  struct SpaceHashInfo {
    Rect2 rect;
    IntRect2 irect;
    SpaceHashInfo(Rect2 r,IntRect2 i): rect(r),irect(i) {}
    SpaceHashInfo(): rect(), irect() {}
    SpaceHashInfo(const SpaceHashInfo &s): rect(s.rect), irect(s.irect) {}
  };
  template<class T>
  class SpaceHash {
  public:
    typedef T data_type;
    typedef std::unordered_multimap<IntVector2,data_type> int_to_data_map;
    typedef std::unordered_map<data_type,SpaceHashInfo> data_to_info_map;
    typedef typename int_to_data_map::iterator int_to_data_iter;
    typedef typename int_to_data_map::const_iterator int_to_data_const_iter;
    typedef typename data_to_info_map::iterator data_to_info_iter;
    typedef typename data_to_info_map::const_iterator data_to_info_const_iter;
  private:
    int_to_data_map int2data;
    data_to_info_map data2info;
    const real_t position_box_size;
  public:
    SpaceHash(real_t position_box_size=10.0f);
    ~SpaceHash();

    inline bool contains(const data_type &d) const {
      return data2info.find(d)!=data2info.end();
    }
    
    // Give me data for all rects that overlap this one.
    bool overlapping_rect(const Rect2 &region,std::unordered_set<data_type> &results) const;
    bool overlapping_circle(Vector2 center,real_t radius,std::unordered_set<data_type> &results) const;
    bool overlapping_point(Vector2 point,std::unordered_set<data_type> &results) const;

    // Do any rects overlap this region?
    data_type first_at_point(Vector2 point) const;
    bool rect_is_nonempty(const Rect2 &region) const;
    bool circle_is_nonempty(Vector2 center,real_t radius) const;
    bool point_is_nonempty(Vector2 point) const;
    bool ray_is_nonempty(Vector2 p1,Vector2 p2) const;

    // Modifiers
    void set_rect(const data_type &object,const Rect2 &rect);
    void remove(const data_type &object);

    // Reserve space
    void reserve(int data,int positions);

    // Send contents to Godot::print
    void dump() const;

  private:
    static Rect2 rect_positive_size(Rect2 in);
    static bool circle_overlaps_rect(Vector2 center,real_t radius,Rect2 rect);
  };

  ////////////////////////////////////////////////////////////////////////
  
  template<class T>
  SpaceHash<T>::SpaceHash(real_t position_box_size):
    int2data(),data2info(),position_box_size(position_box_size)
  {}
  
  template<class T>
  SpaceHash<T>::~SpaceHash() {}

  template<class T>
  void SpaceHash<T>::reserve(int data,int positions) {
    int2data.reserve(positions);
    data2info.reserve(data);
  }
  
  template<class T>
  bool SpaceHash<T>::overlapping_rect(const Rect2 &region,std::unordered_set<T> &result) const {
    bool matches_found = false;
    IntRect2 rect = IntRect2(region,position_box_size).positive_size();
    for(int iy=0,y=rect.position.y;iy<rect.size.y;iy++,y++)
      for(int ix=0,x=rect.position.x;ix<rect.size.x;ix++,x++) {
        IntVector2 here(x,y);
        std::pair<int_to_data_const_iter,int_to_data_const_iter> range=int2data.equal_range(here);
        for(int_to_data_const_iter it=range.first;it!=range.second;it++) {
          const T &what = it->second;
          if(result.find(what)==result.end()) {
            data_to_info_const_iter d2r_it = data2info.find(what);
            if(d2r_it!=data2info.end() and d2r_it->second.rect.intersects(region)) {
              result.insert(what);
              matches_found = true;
            }
          }
        }
      }
    return matches_found;
  }
  
  template<class T>
  bool SpaceHash<T>::rect_is_nonempty(const Rect2 &region) const {
    IntRect2 rect = IntRect2(region,position_box_size).positive_size();
    for(int iy=0,y=rect.position.y;iy<rect.size.y;iy++,y++)
      for(int ix=0,x=rect.position.x;ix<rect.size.x;ix++,x++) {
        IntVector2 here(x,y);
        std::pair<int_to_data_const_iter,int_to_data_const_iter> range=int2data.equal_range(here);
        for(int_to_data_const_iter it=range.first;it!=range.second;it++) {
          const T &what = it->second;
          data_to_info_const_iter d2r_it = data2info.find(what);
          if(d2r_it!=data2info.end() and d2r_it->second.rect.intersects(region))
            return true;
        }
      }
    return false;
  }

  template<class T>
  bool SpaceHash<T>::overlapping_circle(Vector2 center,real_t radius,std::unordered_set<T> &result) const {
    bool matches_found = false;
    IntRect2 rect = IntRect2(rect_for_circle(center,radius),position_box_size);
    for(int iy=0,y=rect.position.y;iy<rect.size.y;iy++,y++)
      for(int ix=0,x=rect.position.x;ix<rect.size.x;ix++,x++) {
        IntVector2 here(x,y);
        std::pair<int_to_data_const_iter,int_to_data_const_iter> range=int2data.equal_range(here);
        for(int_to_data_const_iter it=range.first;it!=range.second;it++) {
          const T &what = it->second;
          if(result.find(what)==result.end()) {
            data_to_info_const_iter d2r_it = data2info.find(what);
            if(d2r_it!=data2info.end() and circle_overlaps_rect(center,radius,d2r_it->second)) {
              result.insert(what);
              matches_found = true;
            }
          }
        }
      }
    return matches_found;
  }

  template<class T>
  bool SpaceHash<T>::circle_is_nonempty(Vector2 center,real_t radius) const {
    IntRect2 rect = IntRect2(rect_for_circle(center,radius),position_box_size);
    for(int iy=0,y=rect.position.y;iy<rect.size.y;iy++,y++)
      for(int ix=0,x=rect.position.x;ix<rect.size.x;ix++,x++) {
        IntVector2 here(x,y);
        std::pair<int_to_data_const_iter,int_to_data_const_iter> range=int2data.equal_range(here);
        for(int_to_data_const_iter it=range.first;it!=range.second;it++) {
          const T &what = it->second;
          data_to_info_const_iter d2r_it = data2info.find(what);
          if(d2r_it!=data2info.end() and circle_overlaps_rect(center,radius,d2r_it->second.rect))
            return true;
        }
      }
    return false;
  }

  template<class T>
  bool SpaceHash<T>::ray_is_nonempty(Vector2 p1,Vector2 p2) const {
    // FIXME: This should use a line drawing algorithm instead of searching the rect with p1..p2 as the diagonal.
    Rect2 real_rect = rect_positive_size(Rect2(p1,Vector2(p2.x-p1.x,p2.y-p1.y)));
    IntRect2 rect = IntRect2(real_rect,position_box_size);
    for(int iy=0,y=rect.position.y;iy<rect.size.y;iy++,y++)
      for(int ix=0,x=rect.position.x;ix<rect.size.x;ix++,x++) {
        IntVector2 here(x,y);
        std::pair<int_to_data_const_iter,int_to_data_const_iter> range=int2data.equal_range(here);
        for(int_to_data_const_iter it=range.first;it!=range.second;it++) {
          const T &what = it->second;
          data_to_info_const_iter d2r_it = data2info.find(what);
          if(d2r_it!=data2info.end() and real_rect.intersects_segment(p1,p2))
            return true;
        }
      }
    return false;
  }
  

  template<class T>
  bool SpaceHash<T>::overlapping_point(Vector2 point,std::unordered_set<T> &result) const {
    bool matches_found = false;
    IntVector2 here = IntVector2(point,position_box_size);
    std::pair<int_to_data_const_iter,int_to_data_const_iter> range=int2data.equal_range(here);
    for(int_to_data_const_iter it=range.first;it!=range.second;it++) {
      const T &what = it->second;
      if(result.find(what)==result.end()) {
        data_to_info_const_iter d2r_it = data2info.find(what);
        if(d2r_it!=data2info.end() and d2r_it->second.rect.has_point(point)) {
          result.insert(what);
          matches_found = true;
        }
      }
    }
    return matches_found;
  }
  
  template<class T>
  bool SpaceHash<T>::point_is_nonempty(Vector2 point) const {
    IntVector2 here = IntVector2(point,position_box_size);
    std::pair<int_to_data_const_iter,int_to_data_const_iter> range=int2data.equal_range(here);
    for(int_to_data_const_iter it=range.first;it!=range.second;it++) {
      const T &what = it->second;
      data_to_info_const_iter d2r_it = data2info.find(what);
      if(d2r_it!=data2info.end() and d2r_it->second.rect.has_point(point))
        return true;
    }
    return false;
  }
  
  template<class T>
  void SpaceHash<T>::set_rect(const data_type &what,const Rect2 &real_rect) {
    Rect2 positive_rect = rect_positive_size(real_rect);
    IntRect2 new_rect = IntRect2(positive_rect,position_box_size);
    
    if(false) {
      data_to_info_iter old=data2info.find(what);
      if(old!=data2info.end() and new_rect==old->second.irect) {
        old->second.rect=positive_rect;
        return; // do not need to move things yet
      }
    }

    remove(what);
    
    for(int iy=0,y=new_rect.position.y;iy<new_rect.size.y;iy++,y++)
      for(int ix=0,x=new_rect.position.x;ix<new_rect.size.x;ix++,x++) {
        IntVector2 here(x,y);
        std::pair<int_to_data_iter,int_to_data_iter> search=int2data.equal_range(here);
        bool found=false;
        for(int_to_data_iter f=search.first;f!=search.second;f++)
          if(f->second==what) {
            found=true;
            break;
          }
        if(!found)
          int2data.emplace(here,what);
      }
    data2info.emplace(what,SpaceHashInfo(positive_rect,new_rect));
  }
  
  template<class T>
  void SpaceHash<T>::remove(const data_type &what) {
    data_to_info_iter there=data2info.find(what);
    if(there==data2info.end())
      return;

    const IntRect2 &irect = there->second.irect;
    
    for(int iy=0,y=irect.position.y;iy<irect.size.y;iy++,y++)
      for(int ix=0,x=irect.position.x;ix<irect.size.x;ix++,x++) {
        IntVector2 here(x,y);
        std::pair<int_to_data_iter,int_to_data_iter> search=int2data.equal_range(here);
        for(int_to_data_iter f=search.first;f!=search.second;f++)
          if(f->second==what) {
            int2data.erase(f);
            break;
        }
      }

    data2info.erase(there);
  }

  template<class T>
  void SpaceHash<T>::dump() const {
    Godot::print("SpaceHash = {");
    Godot::print("  int2data = {");
    for(auto &int_data : int2data)
      Godot::print("    "+str(int_data.first)+" -> "+str(int_data.second));
    Godot::print("  },");
    Godot::print("  data2info = {");
    for(auto &data_rect : data2info)
      Godot::print("    "+str(data_rect.first)+" -> "+str(data_rect.second.rect)+" "+str(data_rect.second.irect));    
    Godot::print("  }");
    Godot::print("}");
  }

  template<class T>
  Rect2 SpaceHash<T>::rect_positive_size(Rect2 in) {
    Rect2 r = in;
    if(r.size.x<0) {
      r.position.x=r.position.x+r.size.x+1;
      r.size.x=-r.size.x;
    }
    if(r.size.y<0) {
      r.position.y=r.position.y+r.size.y+1;
      r.size.y=-r.size.y;
    }
    return r;
  }

  template<class T>
  bool SpaceHash<T>::circle_overlaps_rect(Vector2 center,real_t radius,Rect2 rect) {
    // Assumes rect.size is positive.
    Vector2 p1=rect.position, p2=rect.position+rect.size;
    Vector2 near = Vector2(std::max<real_t>(p1.x,std::min<real_t>(center.x,p2.x)),
                           std::max<real_t>(p1.y,std::min<real_t>(center.y,p2.y)));
    Vector2 dist = near-center;
    return dist.length_squared()<=radius*radius;
  }
}

#endif
