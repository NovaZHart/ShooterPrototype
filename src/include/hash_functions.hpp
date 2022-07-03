#ifndef HASH_FUNCTIONS_HPP
#define HASH_FUNCTIONS_HPP

#include <Ref.hpp>
#include <String.hpp>

#include <cstdint>
#include <functional>

namespace std {
  template<class T>
  struct hash<godot::Ref<T>> {
    const hash<const void *> h;
    std::size_t operator () (const godot::Ref<T> &ref) const noexcept {
      return h(reinterpret_cast<const void*>(ref.ptr()));
    }
  };

  template<>
  struct hash<godot::String> {
    inline int operator() (const godot::String &s) const {
      return s.hash();
    }
  };
};

#endif
