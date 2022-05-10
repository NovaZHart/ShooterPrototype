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
    inline IntVector2(int x,int y): x(x), y(y) {}
    explicit inline IntVector2(const Vector2 &v,real_t position_box_size):
      x(int(floorf(v.x/position_box_size))*position_box_size),
      y(int(floorf(v.y/position_box_size))*position_box_size)
    {}
    bool operator == (const IntVector2 &o) const { return o.x==x and o.y==y; }
  };

  template<>
  inline String str<IntVector2>(const IntVector2 &t) {
    return str("(x=")+str(t.x)+",y="+str(t.y)+")";
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
  };

  template<>
  inline String str<IntRect2>(const IntRect2 &t) {
    return str("(position=")+str(t.position)+",size="+str(t.size)+")";
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
  template<class T>
  class SpaceHash {
  public:
    typedef T data_type;
    typedef std::unordered_multimap<IntVector2,data_type> int_to_data_map;
    typedef std::unordered_multimap<data_type,IntVector2> data_to_int_map;
    typedef std::unordered_map<data_type,Rect2> data_to_rect_map;
    typedef typename int_to_data_map::iterator int_to_data_iter;
    typedef typename int_to_data_map::const_iterator int_to_data_const_iter;
    typedef typename data_to_int_map::iterator data_to_int_iter;
    typedef typename data_to_int_map::const_iterator data_to_int_const_iter;
    typedef typename data_to_rect_map::iterator data_to_rect_iter;
    typedef typename data_to_rect_map::const_iterator data_to_rect_const_iter;
  private:
    int_to_data_map int2data;
    data_to_int_map data2int;
    data_to_rect_map data2rect;
    const real_t position_box_size;
  public:
    SpaceHash(real_t position_box_size=10.0f);
    ~SpaceHash();
    void within_region(const Rect2 &region,std::unordered_set<data_type> &results) const;
    void set_rect(const data_type &object,const Rect2 &rect);
    void remove(const data_type &object);
    void reserve(int data,int positions);
    void dump() const;
  };

  ////////////////////////////////////////////////////////////////////////
  
  template<class T>
  SpaceHash<T>::SpaceHash(real_t position_box_size):
    int2data(),data2int(),data2rect(),position_box_size(position_box_size)
  {}
  
  template<class T>
  SpaceHash<T>::~SpaceHash() {}

  template<class T>
  void SpaceHash<T>::reserve(int data,int positions) {
    int2data.reserve(positions);
    data2int.reserve(positions);
    data2rect.reserve(positions);
  }
  
  template<class T>
  void SpaceHash<T>::within_region(const Rect2 &region,std::unordered_set<T> &result) const {
    IntRect2 rect = IntRect2(region,position_box_size).positive_size();
    for(int iy=0,y=rect.position.y;iy<rect.size.y;iy++,y++)
      for(int ix=0,x=rect.position.x;ix<rect.size.x;ix++,x++) {
        IntVector2 here(x,y);
        std::pair<int_to_data_const_iter,int_to_data_const_iter> range=int2data.equal_range(here);
        for(int_to_data_const_iter it=range.first;it!=range.second;it++) {
          const T &what = it->second;
          if(result.find(what)==result.end()) {
            data_to_rect_const_iter d2r_it = data2rect.find(what);
            if(d2r_it!=data2rect.end() and d2r_it->second.intersects(region)) {
              result.insert(what);
            }
          }
        }
      }
  }
  
  template<class T>
  void SpaceHash<T>::set_rect(const data_type &what,const Rect2 &real_rect) {
    IntRect2 new_rect = IntRect2(real_rect,position_box_size).positive_size();
    Godot::print("SET_RECT what="+str(what)+" at "+str(real_rect)+" = "+str(new_rect));
    // std::pair<data_to_int_iter,data_to_int_iter> dit=data2int.equal_range(what);
    // for(data_to_int_iter it=dit.first;it!=dit.second;it++) {
    //   IntVector2 &here=it->second;
    //   if(not new_rect.contains(it->second)) {
    //     std::pair<int_to_data_iter,int_to_data_iter> search=int2data.equal_range(here);
    //     for(int_to_data_iter f=search.first;f!=search.second;f++)
    //       if(f->second==what) {
    //         int2data.erase(f);
    //         break;
    //       }
    //   }
    // }
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
        if(!found) {
          int2data.emplace(here,what);
          data2int.emplace(what,here);
        }
      }
    data2rect.emplace(what,real_rect);
  }
  
  template<class T>
  void SpaceHash<T>::remove(const data_type &what) {
    data_to_rect_iter there=data2rect.find(what);
    if(there==data2rect.end())
      return;
    data2rect.erase(there);
    
    std::pair<data_to_int_iter,data_to_int_iter> dit=data2int.equal_range(what);
    for(data_to_int_iter it=dit.first;it!=dit.second;it++) {
      IntVector2 &here(it->second);
      std::pair<int_to_data_iter,int_to_data_iter> search=int2data.equal_range(here);
      for(int_to_data_iter f=search.first;f!=search.second;f++)
        if(f->second==what) {
          int2data.erase(f);
          break;
        }
    }
    data2int.erase(dit.first,dit.second);
  }

  template<class T>
  void SpaceHash<T>::dump() const {
    Godot::print("SpaceHash = {");
    Godot::print("  int2data = {");
    for(auto &int_data : int2data)
      Godot::print("    "+str(int_data.first)+" -> "+str(int_data.second));
    Godot::print("  },");
    Godot::print("  data2int = {");
    for(auto &data_int : data2int)
      Godot::print("    "+str(data_int.first)+" -> "+str(data_int.second));
    Godot::print("  data2rect = {");
    for(auto &data_rect : data2rect)
      Godot::print("    "+str(data_rect.first)+" -> "+str(data_rect.second));    
    Godot::print("  }");
    Godot::print("}");
  }
}

#endif
