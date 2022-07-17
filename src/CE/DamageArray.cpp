#include "CE/DamageArray.hpp"

namespace godot {
  namespace CE {
    using namespace std;

    DamageArray::DamageArray(Variant var,real_t clamp_min,real_t clamp_max) {
      PoolRealArray a = static_cast<PoolRealArray>(var);
      PoolRealArray::Read reader = a.read();
      const real_t *reals = reader.ptr();
      size_t a_size=a.size();
      for(size_t i=0;i<size();i++)
        (*this)[i] = (i<a_size) ? clamp(reals[i],clamp_min,clamp_max) : 0;
      (*this)[DAMAGE_TYPELESS]=0; // typeless ignores resistances and passthrus
    }

    DamageArray::DamageArray(real_t value) {
      for(auto &r : *this)
        r=value;
      (*this)[DAMAGE_TYPELESS]=0; // typeless ignores resistances and passthrus
    }

    DamageArray::DamageArray() {
      for(auto &r : *this)
        r=0;
    }


    real_t apply_damage(real_t &damage,double &life,int type,
                        const DamageArray &resists,
                        const DamageArray &passthrus) {
      // Apply damage of the given type to life (shields, armor, or structure) based on
      // resistance (resist) and passthrough (pasthrus) fractions
      // On return:
      //   damage = amount of damage not applied
      //   life = life remaining after damage is applied
      //   Returns the amount of damage taken.

      // Assumes 0<=type<NUM_DAMAGE_TYPES

      if(life<=0 or damage<=0)
        return 0.0f;

      real_t applied = 1.0 - resists[type];
      if(applied<1e-5)
        return 0.0f;

      real_t passed = 0.0f;
      real_t taken = damage;

      real_t passthru = passthrus[type];
      if(passthru>=1.0)
        return 0.0f; // All damage is passed, so we have no more to do.
      if(passthru>0) {
        taken = (1.0-passthru)*damage;
        passed = passthru*damage;
      }

      // Apply resistance to damage:
      taken *= applied;

      if(taken>life) {
        // Too much damage for life.
        // Pass remaining damage, after reversing resistances:
        passed += (taken-life)/applied;
        life = 0;
      } else
        life -= taken;

      damage = passed;
      return taken;
    }


    real_t apply_damage(real_t &damage,double &life,int type,
                        const DamageArray &resists) {
      // Apply damage of the given type to life (shields, armor, or structure) based on
      // resistances (resist)
      // On return:
      //   damage = amount of damage not applied
      //   life = life remaining after damage is applied
      //   Returns the amount of damage taken.

      // Assumes 0<=type<NUM_DAMAGE_TYPES

      if(life<=0 or damage<=0)
        return 0.0f;

      real_t applied = 1.0 - resists[type];
      if(applied<1e-5)
        return 0.0f;

      real_t passed = 0.0f;

      // Apply resistance to damage:
      real_t taken = damage*applied;

      if(taken>life) {
        // Too much damage for life.
        // Pass remaining damage, after reversing resistances:
        passed += (taken-life)/applied;
        life = 0;
      } else
        life -= taken;

      damage = passed;
      return taken;
    }
  }
}
