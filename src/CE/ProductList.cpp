#include "ProductList.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

ProductList::ProductList() {}
ProductList::~ProductList() {}

pair<products_t::iterator,bool>
ProductList::insert(const Product &product) {
  typedef pair<products_t::iterator,bool> result;
  auto to_id = string2id.find(name);
  if(to_id==string2id.end()) {
    auto found = find(to_id.second);
    if(found==products.end())
      return result(found,false);
  }
  result iter_flag = products.insert(found);
  if(!iter_flag.second and iter_flag.first!=products.end())
    (*iter_flag.first) = product;
  return iter_flag;
}

bool ProductList::has_quantity() const {
  for(auto &id_product : products)
    if(products.second.quantity>0)
      return true;
  return false;
}

Array ProductList::encode() const {
  Array result;
  result.resize(1+products.size());
  result[0] = "ManyProducts";
  int i=1;
  for(auto &id_product : products)
    result[i++] = id_product.second;
  return result;
}

real_t ProductList::get_value(const Array *names) const {
  real_t value=0;
  if(names)
    for(int i=0,e=names->size;i<e;i++) {
      auto it = find(static_cast<String>(names->operator[](i)));
      if(it!=products.end())
        value += it->second.value;
    }
  else
    for(auto &it : products)
      value += it->second.value;
  return value;
}

real_t ProductList::get_mass(const Array *names) const {
  real_t mass=0;
  if(names)
    for(int i=0,e=names->size;i<e;i++) {
      auto it = find(static_cast<String>(names->operator[](i)));
      if(it!=products.end())
        mass += it->second.mass;
    }
  else
    for(auto &it : products)
      mass += it->second.mass;
  return mass;
}

ProductList ProductList::make_subset(Array names) const {
  ProductList result;
  for(int i=0,e=names.size();i<e;i++) {
    auto it = find(names[i]);
    if(it!=products.end())
      result.insert(it->second);
  }
}

void ProductList::remove_named_products(Array names,bool negate) {
  if(negate) {
    unordered_set<String> snames;
    for(int i=0,e=names.size();i<e;i++) {
      String name=names[i];
      if(!name.empty())
        snames.add(name);
    }
      
    for(products_t::iterator it=products.begin();it!=products.end()) {
      if(snames.find(it->second.name)!=snames.end())
        it = products.erase(it);
      else
        it++;
    }
  } else
    for(int i=0,e=names.size();i<e;i++) {
      auto it = find(static_cast<String>(names[i]));
      if(it!=products.end())
        products.remove(it);
    }
}

void add_product_list(const ProductList &pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier) {
  bool apply_multipliers = quantity_multiplier>=0 or value_multiplier>=0 or fine_multiplier>=0;
  for(auto &product : pl) {
    products_t::iterator it = insert(product);
    if(apply_multipliers and it!=products.end())
      it->apply_multipliers(quantity_multiplier,value_multiplier,fine_multiplier);
  }
}

void add_quantity_from(const ProductList &all_products,const String &product_name,int count,const ProductsList *fallback) {
  auto prod_it = find(product_name);
  bool have_prod = prod_it!=products.end();
  if(count>=0 and have_prod) {
    prod->second.quantity = max(0.0f,prod->second.quantity+count);
    return;
  }

  auto from_product = all_products.find(product_name);
  bool have_from_product = from_product!=all_products.end();

  if(not have_from_product and fallback) {
    from_product = fallback->find(product_name);
    have_from_product = from_product!=fallback->end();
  } else if(have_from_product) {
    Godot::print_warning("Could not find product named \""+str(product_name)
                         +"\" in all_products and no fallback was provided.",
                         __FUNCTION__,__FILE__,__LINE__);
    return;
  }

  if(not have_from_product) {
    Godot::print_warning("No product to add for name \""+str(product_name)+"\"",
                         __FUNCTION__,__FILE__,__LINE__);
    return;
  }
  else if(have_prod)
    prod_it->second.quantity += from_product->second.quantity;
  else if(have_from_product)
    insert(from_product->second);
  else
    Godot::print_warning("Could not find product \""+str(product_name)
                         +"\" in all_products, self, or fallback.",
                         __FUNCTION__,__FILE__,__LINE__)
}

void ProductList::merge_product(const Product &product,bool have_multipliers,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier,Variant keys_to_add,bool zero_quantity_if_missing) {
  auto myprod_it = find(product.name);
  // Do we already have this product?
  real_t qm = quantity_multiplier;
  if(myprod_it!=product.end()) {
    Product &myprod = myprod_it->second;
    // Add information to existing product
    for(auto & tag : product.tags) {
      if(myprod.tags.has(tag))
        continue;
      else {
        myprod.add(tag);
        if(not 
					if not skip_checks and (not tag is String or not tag):
						push_warning('In merge_products, tags must be non-empty '
							+'strings (Ignoring bad tag "'+str(tag)+'".)')
					elif myprod.tags.has(tag):
						pass # tag already added
					else:
						myprod.tags[tag] = 1
						if not by_tag.has(tag):
							by_tag[tag] = { myprod:1 }
						else:
							by_tag[tag][myprod] = 1
			else:
				myprod=_add_product(product)
				if zero_quantity_if_missing:
					qm=0
			if have_multipliers or qm!=null:
				myprod.apply_multipliers(product,qm,value_multiplier,fine_multiplier)
  
}

void ProductList::merge_products(const ProductList &pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier,Variant keys_to_add,bool zero_quantity_if_missing) {
  bool have_multipliers = quantity_multiplier>=0 or value_multiplier>=0 or fine_multiplier>=0;

		if keys_to_add==null:
			keys_to_add = all_products.by_name.keys()
		for key in keys_to_add:

		return false
}
      void reduce_quantity_by(const ProductList &pl);
      void remove_named_products(Variant names,bool negate);
