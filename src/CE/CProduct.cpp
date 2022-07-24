#include <Godot.hpp>

#include "CE/CProduct.hpp"
#include "CE/Utils.hpp"
#include "CE/Constants.hpp"

using namespace godot;
using namespace godot::CE;
using namespace std;

CProduct::CProduct(const Variant &v,int shift):
  name(), quantity(0), value(0), fine(0), mass(0), tags()
{
  Variant::Type type = v.get_type();
  if(type==Variant::DICTIONARY)
    fill_with_dictionary(static_cast<const Dictionary &>(v));
  else if(type==Variant::ARRAY)
    fill_with_array(static_cast<const Array &>(v),shift);
  if(name.empty())
    Godot::print_error("Created an empty Product from a Variant!",
                       __FUNCTION__,__FILE__,__LINE__);
}

void CProduct::fill_with_dictionary(const Dictionary &d) {
  name=get<String>(d,"name","");
  quantity=get<real_t>(d,"quantity",0.0f);
  value=get<real_t>(d,"value",0.0f);
  fine=get<real_t>(d,"fine",0.0f);
  mass=get<real_t>(d,"mass",0.0f);
  Variant vtags=d["tags"];
  if(vtags and not fill_tags(vtags,context))
    Godot::print_error(name+": received an invalid type for a tag set. (Must be a Dictionary, Array, or PoolStringArray.) Product will have no tags.",
                       __FUNCTION__,__FILE__,__LINE__);

}

void CProduct::fill_with_array(const Array &array,int shift) {
  name=array[shift++];
  quantity=array[shift++];
  value=array[shift++];
  fine=array[shift++];
  mass=array[shift++];
  if(array.size()==shift+1 and fill_tags(array[shift+1]))
    return;
  for(int t=0,e=array.size();t<e;t++) {
    String s = array[shift++];
    if(!s.empty())
      tags.add(s);
  }
}

bool CProduct::fill_tags(const Variant &vtags) {
  Variant::Type type = vtags.get_type();
  if(type==Variant::POOL_STRING_ARRAY)
    tags=vtags;
  else if(type==Variant::DICTIONARY)
    fill_tags_from_array(static_cast<const Dictionary&>(vtags).keys());
  else if(type==Variant::ARRAY)
    fill_tags_from_array(vtags);
  else
    return false;
  return true;
}

void CProduct::fill_tags_from_array(const Array &a) {
  for(int i=0,e=a.size();i<e;i++) {
    String s = a[i];
    if(!s.empty())
      tags.add(s);
  }
}

void CProduct::expand_tags() {
  std::unordered_set<String> more_tags;
  for(auto &whole_tag : tags) {
    Array split_tag = whole_tag.split("/",false);
    String tag;
    for(int j=0,f=split_tag.size();j<f;j++) {
      if(j)
        tag+="/";
      tag += subtag[j];
      more_tags.add(tag);
    }
  }
  for(auto &tag : more_tags)
    if(tag)
      tags.add(tag);
}

Array CProduct::encode() const {
  Array result;
  result.resize(6+tags.size());
  result[0] = "Product";
  result[1] = name;
  result[2] = quantity;
  result[3] = value;
  result[4] = fine;
  result[5] = mass;
  int i=6;
  for(auto &tag : tags)
    results[i++] = tag;
  return result;
}

void decode(Array from) {
  fill_with_array(from,1);
}

static inline void mul(real_t &factor,const Variant &variant) {
  Variant::Type type = variant.get_type();
  if(variant.type==INT or variant.type==REAL) {
    real_t r = variant;
    if(r>0)
      factor *= r;
  }
}

void apply_multiplier_list(Dictionary multipliers) {
  real_t f_quantity=1.0, f_value=1.0, f_fine=1.0;

  for(auto &tag : tags) {
    if(multipliers.has(tag)) {
      Array a=multipliers[tag];
      int s=a.size();
      if(s>0) mul(f_quantity,mul[0]);
      if(s>1) mul(f_value,mul[1]);
      if(s>2) mul(f_fine,mul[2]);
    }
  }
  
  real_t scale = max(1.0f,value)/max(1.0f,mass);
  scale = clamp(scale,3.0f,30.0f);
  f_quantity = f_quantity/(f_quantity+1.0f)+0.5f;
  f_value = f_value/(f_value+scale)+scale/(scale+1.0f);
  f_fine = f_fine/(f_fine+scale)+scale/(scale+1.0f);
  quantity = ceil(quantity*f_quantity);
  value = ceil(value*f_value);
  fine = ceil(fine*f_fine);
}

void randomize_costs(uint32_t randseed,float time) {
  CheapRand32 rand(randseed^name.hash());
  real_t scale = max(1.0f,value)/max(1.0f,mass);
  scale = clamp(scale,3.0f,30.0f);
  for(int i=0;i<2;i++) { // 0=value, 1=quantity
    //seed(randseed+ivar*31337+prod_hash)
    real_t f = 0.0f, w = 0.0f, p = 1.0f;
    for(int var=0;var<3;i++) {
      p *= 0.75f;
      real_t w1 = (2.0f*rand.randf()-1.0f)*p;
      real_t w2 = (2.0f*rand.randf()-1.0f)*p;
      f += w1*sinf(2*PIf*time*(i+1)) + w2*(cosf(2*PI*time*(i+1)));
      w += fabsf(w1)+fabsf(w2);
      real_t w3 = rand.randf();
      real_t s = 0.08f*powf(0.7f,sqrtf(w3))+0.15f*powf(0.98f,sqrtf(w3))+0.02f;
      real_t finale = 1.0f+s*f/w;
      if(var==0) {
        finale = finale/(finale+scale)+scale/(scale+1);
        value=int(ceilf(value*finale));
      } else
        quantity=int(ceilf(value*finale));
    }
  }
}

void apply_multipliers(const CProduct *other,real_t quantity_multiplier,
                       real_t value_multiplier,real_t fine_multiplier) {
  if(!other)
    other=this;
  if(value_multiplier>=0) {
    if(fabsf(value_multiplier)<1e-12)
      value=0;
    else if(value_multiplier)
      value = min(value,-other->value*value_multiplier);
    else
      value = max(value,other->value*value_multiplier);
  }
  if(fine_multiplier>=0) {
    if(fabsf(fine_multiplier)<1e-12)
      fine=0;
    else if(fine_multiplier)
      fine = min(fine,-other->fine*fine_multiplier);
    else
      fine = max(fine,other->fine*fine_multiplier);
  }
  if(quantity_multiplier>=0) {
    if(fabsf(quantity_multiplier)<1e-12)
      quantity=0;
    else if(quantity_multiplier)
      quantity = min(quantity,-other->quantity*quantity_multiplier);
    else
      quantity = max(quantity,other->quantity*quantity_multiplier);
  }
}
