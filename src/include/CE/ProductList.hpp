#ifndef PRODUCTLIST_HPP
#define PRODUCTLIST_HPP

#include <memory>

#include <Array.hpp>
#include <Ref.hpp>
#include <PoolArrays.hpp>

#include "CE/ObjectIdGenerator.hpp"
#include "CE/CProduct.hpp"

namespace godot {
  namespace CE {

    //FIXME: NEED TO BE ABLE TO RETURN WEAK POINTIER TO THIS
    
    class ProductList: public std::enable_shared_from_this<ProductList> {
    public:
      virtual Array products_for_tags(const PoolStringArray &included,
                                      const PoolStringArray &excluded) const  = 0;
      virtual real_t get_value(const Array *names) const  = 0;
      virtual real_t get_mass(const Array *names) const  = 0;
      virtual std::shared_ptr<ProductList> make_subset(Array names) const  = 0;
      virtual void add_product_list(std::shared_ptr<const ProductList> pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier)  = 0;
      virtual void add_quantity_from(std::shared_ptr<const ProductList> pl,const String &product_name,int count,std::shared_ptr<const ProductList> fallback)  = 0;
      virtual void merge_products(std::shared_ptr<const ProductList> pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier,Variant keys_to_add,bool zero_quantity_if_missing)  = 0;
      virtual void reduce_quantity_by(std::shared_ptr<const ProductList> pl)  = 0;

      virtual void remove_named_products(Array names,bool negate)  = 0;
      virtual bool empty() = 0;
      virtual size_t size() = 0;
      virtual bool has_quantity() const  = 0;
      virtual Array encode() const  = 0;

      virtual object_id id_with_name(String name) = 0;
      virtual Ref<Product> product_with_id(object_id id) = 0;
      virtual Ref<Product> product_with_name(String name) = 0;
      virtual Array for_tag(String tag) = 0;
      virtual void remove_named_products(Variant names,bool negate)  = 0;
    };
  }
}

#endif
