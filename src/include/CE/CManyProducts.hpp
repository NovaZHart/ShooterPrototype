#ifndef PRODUCTLIST_HPP
#define PRODUCTLIST_HPP

#include <unordered_map>

#include "Godot.hpp"
#include "String.hpp"

#include "CE/ObjectIdGenerator.hpp"
#include "hash_functions.hpp"

namespace godot {
  namespace CE {

    class ManyProducts {
    public:
      typedef std::unordered_map<object_id,Product> products_t;
      typedef std::unordered_map<String,object_id> string2id_t;
      typedef std::unordered_multimap<String,object_id> tag2id_t;
    private:
      ObjectIdGenerator idgen;
      products_t products;
      string2id_t string2id;
      tag2id_t tag2id;
    public:
      ManyProducts();
      ~ManyProducts();
      std::pair<products_t::iterator,bool> insert(const Product &product);

      bool has_quantity() const override;
      Array encode() const override;
      Array products_for_tags(const PoolStringArray &included,
                              const PoolStringArray &excluded) const override;
      real_t get_value(const Array *names) const override;
      real_t get_mass(const Array *names) const override;
      shared_ptr<ProductList> make_subset(Array names) const override;
      void remove_named_products(Array names,bool negate) override;
      void add_product_list(shared_ptr<const ProductList> pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier) override;
      void add_quantity_from(shared_ptr<const ProductList> pl,const String &product_name,int count,const ProductsList *fallback) override;
      void merge_products(shared_ptr<const ProductList> pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier,Variant keys_to_add,bool zero_quantity_if_missing) override;
      void reduce_quantity_by(shared_ptr<const ProductList> pl) override;
      void remove_named_products(Variant names,bool negate) override;
      
      inline products_t::iterator begin() { return products.begin(); }
      inline products_t::const_iterator begin() const { return products.begin(); }
      inline products_t::iterator end() { return products.end(); }
      inline products_t::const_iterator end() const { return products.end(); }

      products_t::iterator find(object_id id) {
        return products.find(id);
      }
      products_t::const_iterator find(object_id id) const {
        return products.find(id);
      }

      products_t::iterator find(const String &name) {
        string2id_t::const_iterator to_id = string2id.find(name);
        return to_id==string2id.end() ? end() : find(to_id.second);
      }
      products_t::const_iterator find(const String &name) const {
        string2id_t::const_iterator to_id = string2id.find(name);
        return to_id==string2id.end() ? end() : find(to_id.second);
      }
    };
    
  }
}
#endif
