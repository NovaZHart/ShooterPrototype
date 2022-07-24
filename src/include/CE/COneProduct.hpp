#ifndef CONEPRODUCT_HPP
#define CONEPRODUCT_HPP

#include <memory>

#include <Array.hpp>
#include <Ref.hpp>
#include <PoolArrays.hpp>

#include "CE/CProduct.hpp"
#include "CE/ProductList.hpp"
#include "PropertyMacros.hpp"

namespace godot {
  namespace CE {
    class COneProduct {
      CProduct product;
    public:
      COneProduct(const CProduct &product):
        product(product)
      {}
      COneProduct():
        product()
      {}
      ~COneProduct() {}
      PROP_GETSET_REF(CProduct,product);
      
      virtual Array products_for_tags(const PoolStringArray &included,
                                      const PoolStringArray &excluded) const override;
      virtual real_t get_value(const Array *names) const override;
      virtual real_t get_mass(const Array *names) const override;
      virtual std::shared_ptr<ProductList> make_subset(Array names) const override;
      virtual void add_product_list(std::shared_ptr<const ProductList> pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier) override;
      virtual void add_quantity_from(std::shared_ptr<const ProductList> pl,const String &product_name,int count,std::shared_ptr<const ProductList> fallback) override;
      virtual void merge_products(std::shared_ptr<const ProductList> pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier,Variant keys_to_add,bool zero_quantity_if_missing) override;
      virtual void reduce_quantity_by(std::shared_ptr<const ProductList> pl) override;

      virtual bool empty() override;
      virtual size_t size() override;
      virtual bool has_quantity() const override;
      virtual Array encode() const override;
      virtual object_id id_with_name(String name) override;
      virtual CProduct *product_ptr_with_id(object_id id) override;
      virtual CProduct *product_ptr_with_name(const String &name) override;
      virtual const CProduct *product_ptr_with_id(object_id id) const override;
      virtual const CProduct *product_ptr_with_name(const String &name) const override;
      virtual Ref<Product> product_ref_with_id(object_id id) override;
      virtual Ref<Product> product_ref_with_name(String name) override;
      virtual Array for_tag(String tag) override;
      virtual void remove_named_products(Variant names,bool negate) override;
    };
  }
}


#endif
