#include "CE/COneProduct.hpp"
#include "CE/Utils.hpp"
#include "CE/Product.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

Array COneProduct::products_for_tags(const PoolStringArray &included,
                                     const PoolStringArray &excluded) const {
  Array result;
  bool found = true;
  pool_foreach_read(excluded,[&](const String &tag) {
                               if(product.find_tag(tag)==product.end_tag())
                                 found=false;
                               return not found;
                             });
  if(!found)
    return result;
  found=false;
  pool_foreach_read(included,[&](const String &tag) {
                               if(product.find_tag(tag)!=product.end_tag())
                                 found=true;
                               return found;
                             });
  if(found)
    result.append(this,0);
}

real_t get_value(const Array *names) const {
  if(product.name.empty())
    return 0;
  
  if(names) {
    for(int i=0,e=names->size();i!=e;i++)
      if(names->operator[](i) == product.name)
        return product.value;
  } else
    return product.value;
}

real_t get_mass(const Array *names) const {
  if(product.name.empty())
    return 0;
  
  if(names) {
    for(int i=0,e=names->size();i!=e;i++)
      if(names->operator[](i) == product.name)
        return product.mass;
  } else
    return product.mass;
}

std::shared_ptr<ProductList> make_subset(Array names) const {
  if(not product.name.empty())
    for(int i=0,e=names->size();i!=e;i++)
      if(names->operator[](i) == product.name)
        return make_shared<COneProduct>(product);
  return make_shared<COneProduct>();
}

void add_product_list(std::shared_ptr<const ProductList> pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier) {
  
}

void add_quantity_from(std::shared_ptr<const ProductList> pl,const String &product_name,int count,std::shared_ptr<const ProductList> fallback) {

}
void merge_products(std::shared_ptr<const ProductList> pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier,Variant keys_to_add,bool zero_quantity_if_missing) {

}
void reduce_quantity_by(std::shared_ptr<const ProductList> pl) {
  if(!pl or product.name.empty() or product.quantity<=0)
    return;
  
}

bool empty() {
  return product.name.empty();
}

size_t size() {
  return product.name.empty() ? 0 : 1;
}

bool has_quantity() const {
  return not product.name.empty() and product.name.quantity>0;
}

Array encode() const {
  Array a;
  a.append("OneProduct");
  if(not product.name.empty())
    a.append(product.encode());
  return a;
}

object_id id_with_name(String name) {
  if(not product.name.empty() and product.name==name)
    return 0;
  return -1;
}

CProduct *product_ptr_with_id(object_id id) {
  if(id!=0 or product.name.empty())
    return nullptr;
  return product;
}

CProduct *product_ptr_with_name(const String &name) {
  if(id!=0 or product.name.empty())
    return nullptr;
  return product;
}

const CProduct *product_ptr_with_id(object_id id) const {
  if(id!=0 or product.name.empty())
    return nullptr;
  return product;
}

const CProduct *product_ptr_with_name(const String &name) const {
  if(id!=0 or product.name.empty())
    return nullptr;
  return product;
}

Ref<Product> product_ref_with_id(object_id id) {
  if(id!=0 or product.name.empty())
    return Ref<Product>();
  return Ref<Product>(new ProductListItemView(this,0));
}

Ref<Product> product_ref_with_name(String name) {
  if(not product.name.empty() and product.name==name)
    return Ref<Product>(new ProductListItemView(this,0));
  return Ref<Product>();
}

Array for_tag(String tag) {
  Array result;
  if(product.name.empty() or tag.empty())
    return result;
  for(auto &product_tag : product.tags)
    if(tag==product_tag) {
      result.append(Ref<Product>(new ProductListItemView(this,0)));
      break;
    }
  return result;
}

void remove_named_products(Variant names,bool negate) {
  if(!product.name)
    return;

  Variant::Type type = names.get_type();
  if(type==Variant::POOL_STRING_ARRAY)
    pool_foreach_read(static_cast<PoolStringArray>(names),[&](const String &name) {
      if(name==product.name) {
        product.clear();
        return true;
      }
      return false;
    });
  else if(type==Variant::ARRAY) {
    Array a=names;
    for(int i=0,e=a.size();i!=e;i++)
      if(static_cast<String>(a[i]) == product.name) {
        product.clear();
        break;
      }
  } else if(type==Variant::DICTIONARY) {
    Array a=static_cast<Dictionary>(names).keys();
    for(int i=0,e=a.size();i!=e;i++)
      if(static_cast<String>(a[i]) == product.name) {
        product.clear();
        break;
      }
  } else
    print_error("Invalid type sent to remove_named_products: "+str(names));
}
