#ifndef CHEAPRAND32_HPP
#define CHEAPRAND32_HPP

#include <cstdint>
#include <algorithm>

#include "OS.hpp"

#include "CE/Constants.hpp"

namespace godot {
  namespace CE {
    class CheapRand32 {
      // Low-memory-footprint, fast, 32-bit, random number, generator
      // that produces high-quality random numbers.  Note: not
      // thread-safe; multiple threads may get the same random number
      // state sometimes. Numbers and state will always be valid though.
      uint32_t state;
    public:
      CheapRand32():
        state(make_seed())
      {};
      CheapRand32(uint32_t seed):
        state(hash(hash(hash(seed))))
      {}
      inline uint32_t randi() {
        // Random 32-bit integer, uniformly distributed.
        return state=hash(state);
      }
      inline float randf() {
        // Random float in [0..1), uniformly distributed.
        return int2float(state=hash(state));
      }
      inline float rand_angle() {
        return randf()*2*PI;
      }
      inline void seed(uint32_t s) {
        state = hash(hash(hash(s)));
      }
      inline void seed() {
        state = make_seed();
      }
      
      static inline uint32_t make_seed() {
        uint32_t s=OS::get_singleton()->get_ticks_usec();
        return hash(hash(hash(s)));
      }
      static inline uint32_t hash(uint32_t a) {
        // Generator magic from https://burtleburtle.net/bob/hash/integer.html
        // There is no protection against updating the state twice at the same time.
        // That means the state will be valid, but two threads may see the same
        // state if they update it at the same time.
        // Hence, calls to this routine are why the class is not thread-safe.
        a = (a+0x7ed55d16) + (a<<12);
        a = (a^0xc761c23c) ^ (a>>19);
        a = (a+0x165667b1) + (a<<5);
        a = (a+0xd3a2646c) ^ (a<<9);
        a = (a+0xfd7046c5) + (a<<3);
        a = (a^0xb55a4f09) ^ (a>>16);
        return a;
      }
      
      static inline float int2float(uint32_t i) {
        // Not the fastest int->float conversion method, but is
        // simpler and more portable than bit manipulation.
        return std::min(float(i%8388608)/8388608.0f,1.0f);
      }
    };
  }
}

#endif
