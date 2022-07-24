#ifndef PRODUCT_HPP
#define PRODUCT_HPP

#include <PoolArrays.hpp>
#include <String.hpp>
#include <Variant.hpp>

#include "PropertyMacros.hpp"

namespace godot {
  namespace CE {
    class Product {
      String name;
      real_t quantity, value, fine, mass;
      std::unordered_set<String> tags;
    public:
      PROP_GET_REF(String,name);
      PROP_GETSET_VAL(real_t,quantity);
      PROP_GETSET_VAL(real_t,value);
      PROP_GETSET_VAL(real_t,fine);
      PROP_GETSET_VAL(real_t,mass);
      PROP_GET_REF(std::unordered_set<String>,tags);

      Product(const String &name,real_t quantity,real_t value,real_t fine,real_t mass,const PoolStringArray &tags):
        name(name), quantity(quantity), value(value), fine(fine),
        mass(mass), tags(tags)
      {}
      Product(const Variant &v,int shift);
      Product() {}
      ~Product() {}
      
      void expand_tags();
      Array encode() const;
      void decode(Array from);
      void apply_multiplier_list(Dictionary multiplier_list);
      void randomize_costs(int randseed,float time);
      void apply_multipliers(const Product *other,real_t quantity_multiplier,
                             real_t value_multiplier,real_t fine_multiplier);
    private:
      void fill_with_dictionary(const Dictionary &d);
      void fill_with_array(const Array &d,int shift);

      bool fill_tags(Variant &v);
      void fill_tags_from_array(const Array &d);
    };
  }
}

#endif
