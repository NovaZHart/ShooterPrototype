#ifndef PRODUCTLIST_HPP
#define PRODUCTLIST_HPP

#include <unordered_map>

#include "Godot.hpp"
#include "String.hpp"

#include "hash_functions.hpp"
#include "CE/CProduct.hpp"

namespace godot {
  namespace CE {

    class ManyProducts {
    public:
      typedef std::shared_ptr<CProduct> product_ptr_t
      typedef std::unordered_map<String,product_ptr_t> by_name_t;
      typedef std::unordered_multimap<String,product_ptr_t> by_tag_t;
    private:
      by_name_t by_name;
      by_tag_t by_tag;
    public:
      ManyProducts();
      ~ManyProducts();
      std::pair<by_name_t::iterator,bool> insert(shared_ptr<Product> product);

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
      
      inline products_t::iterator begin() { return by_name.begin(); }
      inline products_t::const_iterator begin() const { return by_name.begin(); }
      inline products_t::iterator end() { return by_name.end(); }
      inline products_t::const_iterator end() const { return by_name.end(); }

      products_t::iterator find(const String & id) {
        return products.find(id);
      }
      products_t::const_iterator find(const String & id) const {
        return products.find(id);
      }

      inline tags_t::iterator tags_begin() { return by_tag.begin(); }
      inline tags_t::const_iterator tags_begin() const { return by_tag.begin(); }
      inline tags_t::iterator tags_end() { return by_tag.end(); }
      inline tags_t::const_iterator tags_end() const { return by_tag.end(); }

      std::pair<tags_t::iterator,tags_t::iterator> equal_range_tag(const String &tag) {
        return by_tag.equal_range(tag);
      }
      std::pair<tags_t::const_iterator,tags_t::const_iterator> equal_range_tag(const String &tag) const {
        return by_tag.equal_range(tag);
      }
      tags_t::iterator find_tag(const String & tag) {
        return by_tag.find(tag);
      }
      tags_t::const_iterator find_tag(const String & tag) const {
        return by_tag.find(tag);
      }
    };
    
  }
}
#endif
