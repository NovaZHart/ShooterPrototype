#ifndef COMBATENGINEUTILS_HPP
#define COMBATENGINEUTILS_HPP

#include <assert.h>
#include <time.h>

#include <cstdint>
#include <cmath>
#include <algorithm>
#include <limits>
#include <memory>

#include <Dictionary.hpp>
#include <RID.hpp>

#include "FastProfilier.hpp"
#include "DVector3.hpp"

#include "CE/Data.hpp"
#include "CE/Math.hpp"
#include "CE/Targetting.hpp"
#include "CE/ObjectIdGenerator.hpp"

namespace godot {

  template<class T>
  String str(const T &t) {
    return String(Variant(t));
  }
  
  namespace CE {

    inline object_id rid2id_default(const rid2id_t &rid2id,const RID &rid,object_id default_id=-1) {
      auto it = rid2id.find(rid.get_id());
      return (it==rid2id.end()) ? default_id : it->second;
    }
    
    inline object_id rid2id_default(const rid2id_t &rid2id,int32_t rid_id,object_id default_id=-1) {
      auto it = rid2id.find(rid_id);
      return (it==rid2id.end()) ? default_id : it->second;
    }
    

    template<class T>
    inline T get(const Dictionary &dict,const char *key) {
      return static_cast<T>(dict[key]);
    }

    template<class T>
    inline T get(const Dictionary &dict,const char *key,const T &default_value) {
      if(dict.has(key))
        return static_cast<T>(dict[key]);
      else
        return default_value;
    }
    
    inline uint32_t state_for_name(const String &name) {
      return name.hash();
    }

    inline bool compare_distance(const std::pair<real_t,std::pair<RID,object_id>> &a,const std::pair<real_t,std::pair<RID,object_id>> &b) {
      return a.first<b.first;
    }
  }
}

#endif
