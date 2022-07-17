#ifndef DAMAGEARRAY_HPP
#define DAMAGEARRAY_HPP

#include <array>
#include <initializer_list>

#include <Godot.hpp>
#include <Variant.hpp>

#include "CE/Constants.hpp"

namespace godot {
  namespace CE {
    class DamageArray: public std::array<real_t,NUM_DAMAGE_TYPES> {
    public:
      DamageArray(Variant var,real_t clamp_min,real_t clamp_max);
      DamageArray(real_t value);
      DamageArray();

      DamageArray(std::initializer_list<real_t> values) {
        int i=0;
        for(auto &value : values) {
          if(i==NUM_DAMAGE_TYPES)
            return;
          (*this)[i++] = value;
        }
        for(;i<NUM_DAMAGE_TYPES;i++)
          (*this)[i++] = 0;
        (*this)[DAMAGE_TYPELESS]=0; // typeless ignores resistances and passthrus
      }
      
      inline ~DamageArray() {}
      inline real_t for_type(size_t type) const {
        if(type>=NUM_DAMAGE_TYPES)
          type=0;
        return this->operator [] (type);
      }
    };
    
    real_t apply_damage(real_t &damage,double &life,int type,
                        const DamageArray &resists,
                        const DamageArray &passthrus);
    real_t apply_damage(real_t &damage,double &life,int type,
                        const DamageArray &resists);
  }
}
      
#endif
