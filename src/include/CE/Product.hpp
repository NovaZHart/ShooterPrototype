#ifndef PRODUCTVIEW_HPP
#define PRODUCTVIEW_HPP

#include <memory>

#include "Godot.hpp"
#include "Reference.hpp"
#include "String.hpp"
#include "PoolArrays.hpp"
#include "CProduct.hpp"
namespace godot {
    class Product: public Reference {
      GODOT_CLASS(Product,Reference)

    public:
      Product(const Product &p);
      Product(const std::shared_ptr<CE::Product> &product);

      // Constructors intended for Godot:
      Product(Variant from);
      Product();

      virtual ~Product();
      virtual CE::Product *get_product();
      virtual const CE::Product *get_product();

      // Interface for godot:
      void _init();
      static void _register_methods();

      void set_quantity(real_t q);
      real_t get_quantity() const;

      void set_value(real_t q);
      real_t get_value() const;

      void set_fine(real_t q);
      real_t get_fine() const;

      void set_mass(real_t q);
      real_t get_mass() const;

      void set_tags(Variant q);
      PoolStringArray get_mass() const;

    private:
      std::shared_ptr<CE::CProduct> product;
    };
}

#endif
