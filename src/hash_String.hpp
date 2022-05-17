#ifndef HASH_STRING_HPP
#define HASH_STRING_HPP

#include <String.hpp>

namespace godot {
  struct hash_String {
    inline int operator() (const String &s) const {
      return s.hash();
    }
  };
}

#endif
