#include "CManyProducts.hpp"

using namespace std;
using namespace godot;
using namespace godot::CE;

CManyProducts::CManyProducts() {}
CManyProducts::~CManyProducts() {}

pair<by_name_t::iterator,bool>
CManyProducts::insert(shared_ptr<Product> product) {
  typedef pair<by_name_t::iterator,bool> result;

  if(!product)
    return result(nullptr,false);
  
  // Do we already have the product?
  const String &name=product->get_name();
  auto named=by_name.find(name);
  if(named!=by_name.end()) {
    if(named.second==product)
      return result(named,false);
    else
      remove_product(named);
  }

  result inserted = by_name.insert(product);
  for(auto tag_ptr=product->begin_tag();tag_ptr!=product->end_tag();tag_ptr++)
      by_tag.emplace(*tag_ptr,product);

  return inserted;
}

void CManyProducts::erase(shared_ptr<Product> product) {
  if(!product)
    return;
  const String &name=product->get_name();
  auto named = by_name.find(name);
  if(named==by_name.end())
    return;

  Product &removeme = *named->second;
  for(auto tag_ptr=removeme.begin_tag();tag_ptr!=removeme.end_tag();tag_ptr++) {
    
}

bool CManyProducts::has_quantity() const {
  for(auto &id_product : products)
    if(products.second.quantity>0)
      return true;
  return false;
}

Array CManyProducts::encode() const {
  Array result;
  result.resize(1+products.size());
  result[0] = "ManyProducts";
  int i=1;
  for(auto &id_product : products)
    result[i++] = id_product.second;
  return result;
}

real_t CManyProducts::get_value(const Array *names) const {
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

real_t CManyProducts::get_mass(const Array *names) const {
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

CManyProducts CManyProducts::make_subset(Array names) const {
  CManyProducts result;
  for(int i=0,e=names.size();i<e;i++) {
    auto it = find(names[i]);
    if(it!=products.end())
      result.insert(it->second);
  }
}

void CManyProducts::remove_named_products(Array names,bool negate) {
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

void add_product_list(const CManyProducts &pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier) {
  bool apply_multipliers = quantity_multiplier>=0 or value_multiplier>=0 or fine_multiplier>=0;
  for(auto &product : pl) {
    products_t::iterator it = insert(product);
    if(apply_multipliers and it!=products.end())
      it->apply_multipliers(quantity_multiplier,value_multiplier,fine_multiplier);
  }
}

void add_quantity_from(const CManyProducts &all_products,const String &product_name,int count,const ProductsList *fallback) {
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

void CManyProducts::merge_product(const Product &product,bool have_multipliers,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier,Variant keys_to_add,bool zero_quantity_if_missing) {
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

void CManyProducts::merge_products(const CManyProducts &pl,real_t quantity_multiplier,real_t value_multiplier,real_t fine_multiplier,Variant keys_to_add,bool zero_quantity_if_missing) {
  bool have_multipliers = quantity_multiplier>=0 or value_multiplier>=0 or fine_multiplier>=0;

		if keys_to_add==null:
			keys_to_add = all_products.by_name.keys()
		for key in keys_to_add:

		return false
}
      void reduce_quantity_by(const CManyProducts &pl);
      void remove_named_products(Variant names,bool negate);
