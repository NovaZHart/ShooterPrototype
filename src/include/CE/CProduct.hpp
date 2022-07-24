#ifndef PRODUCT_HPP
#define PRODUCT_HPP

#include <PoolArrays.hpp>
#include <String.hpp>
#include <Variant.hpp>

#include "PropertyMacros.hpp"

namespace godot {
  namespace CE {
    class CProduct {
      String name;
      real_t quantity, value, fine, mass;
      std::unordered_set<String> tags;
    public:
      PROP_GET_CONST_REF(String,name);
      PROP_GETSET_VAL(real_t,quantity);
      PROP_GETSET_VAL(real_t,value);
      PROP_GETSET_VAL(real_t,fine);
      PROP_GETSET_VAL(real_t,mass);
      PROP_GET_REF(std::unordered_set<String>,tags);

      // Set everything except the name to constructor defaults.
      inline void clear() {
        quantity=value=fine=mass=0;
        tags.clear();
      }

      // Iterate over tags.
      inline std::unordered_set<String>::iterator begin_tag() {
        return tags.begin();
      }
      inline std::unordered_set<String>::iterator end_tag() {
        return tags.end();
      }
      inline std::unordered_set<String>::const_iterator begin_tag() const {
        return tags.begin();
      }
      inline std::unordered_set<String>::const_iterator end_tag() const {
        return tags.end();
      }

      // Search for a tag
      inline std::unordered_set<String>::iterator find_tag(const String &s) {
        return tags.find(s);
      }
      inline std::unordered_set<String>::const_iterator find_tag(const String &s) const {
        return tags.find(s);
      }
      
      // Construct with specified values.
      template<class Iter>
      CProduct(const String &name,real_t quantity,real_t value,real_t fine,real_t mass,
               Iter first_tag, Iter last_tag):
        name(name), quantity(quantity), value(value), fine(fine),
        mass(mass), tags(first_tag,last_tag)
      {}

      // Construct with specified values, and no tags.
      CProduct(const String &name,real_t quantity,real_t value,real_t fine,real_t mass):
        name(name), quantity(quantity), value(value), fine(fine),
        mass(mass), tags()
      {}

      // Construct with given name, and constructor defaults for everything else.
      CProduct(const String &name):
        name(name), quantity(0), value(0), fine(0),
        mass(0), tags()
      {}

      // Decode from a variant. Ignore the first "shift" elements of
      // an Array. This is to allow the constructor to be used when
      // decode()ing, where the first element is String("Product").
      // The shift must be >=0.
      CProduct(const Variant &v,int shift);

      // Construct with default values
      CProduct() {}
      ~CProduct() {}
      
      // Turn "a/b/c" tags into "a", "a/b", and "a/b/c"
      void expand_tags();

      // Encode into an array that decode() will understand
      Array encode() const;
      
      // Given an array from encode(), fill this object with values from that array.
      bool decode(Array from);

      // Apply multipliers to the quantity, value, and fine. Maps from
      // tag name to an array of up to three values: multiplier for
      // quantity, for value, and for fine. A multipllier that is
      // non-numeric or negative is ignored.
      void apply_multiplier_list(Dictionary multiplier_list);

      // Set costs and quantity to random values.  The "time" is the
      // amount of time that has elapsed, and the "randseed" is the
      // seed to CheapRand32.
      void randomize_costs(uint32_t randseed,float time);

      // Apply a triad of multipliers to the quantity, value, and fine
      // of either the other product, or this product (if "other" is
      // null). If a multiplier is negative, it will be ignored.
      void apply_multipliers(const CProduct *other,real_t quantity_multiplier,
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
