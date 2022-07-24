#ifndef PRODUCTVIEW_HPP
#define PRODUCTVIEW_HPP

#include <memory>

#include "Godot.hpp"
#include "Reference.hpp"
#include "String.hpp"
#include "PoolArrays.hpp"

#include "CE/ProductList.hpp"
#include "CE/ObjectIdGenerator.hpp"

namespace godot {
    class ProductView: public Reference {
      GODOT_CLASS(Product,Reference)

    public:
      ProductView(const ProductView &p);
      ProductView(const std::shared_ptr<CE::Product> &product);

      // Constructors intended for Godot:
      ProductView(Variant from);p
      ProductView();

      virtual ~ProductView();
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
      std::shared_ptr<CE::Product> product;
    };
    class ProductListView: public ProductView {
    public:
      ProductListView(std::weak_ptr<CE::ProductList> list,CE::object_id id);
      ProductListView(const ProductListView &p);
      virtual ~ProductListView();
      CE::Product *get_product() override;
      const CE::Product *get_product() override;
    private:
      std::weak_ptr<CE::ProductList> list;
      CE::object_id id;
    };
}

#endif
