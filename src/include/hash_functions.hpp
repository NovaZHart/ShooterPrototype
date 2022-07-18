#ifndef HASH_FUNCTIONS_HPP
#define HASH_FUNCTIONS_HPP

#include <Ref.hpp>
#include <String.hpp>
#include <Godot.hpp>

#include <cstdint>
#include <functional>

#include <CE/ObjectIdGenerator.hpp>

namespace std {

  template<>
  struct hash<pair<godot::object_id,real_t>> {
    static const hash<godot::object_id> object_id_hash;
    static const hash<real_t> real_t_hash;
    size_t operator () (const pair<godot::object_id,real_t> &a) const noexcept {
      return object_id_hash(a.first)^object_id_hash(a.second);
    }
  };
  
  template<class T>
  struct hash<godot::Ref<T>> {
    const hash<const void *> h;
    size_t operator () (const godot::Ref<T> &ref) const noexcept {
      return h(reinterpret_cast<const void*>(ref.ptr()));
    }
  };

  template<>
  struct hash<godot::String> {
    inline int operator() (const godot::String &s) const noexcept {
      return s.hash();
    }
  };
};

#endif
