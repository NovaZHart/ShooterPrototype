#ifndef COMBATENGINEUTILS_HPP
#define COMBATENGINEUTILS_HPP

#include <assert.h>
#include <time.h>

#include <cstdint>
#include <cmath>
#include <algorithm>
#include <limits>
#include <memory>
#include <string>

#include <Dictionary.hpp>
#include <RID.hpp>
#include <PoolArrays.hpp>

#include "FastProfilier.hpp"
#include "DVector3.hpp"

#include "CE/Data.hpp"
#include "CE/Math.hpp"
#include "CE/Targetting.hpp"
#include "CE/ObjectIdGenerator.hpp"

namespace godot {

  template<class T>
  struct pool_type {};

  template<>
  struct pool_type<PoolByteArray> {
    typedef uint8_t type;
  };

  template<>
  struct pool_type<PoolIntArray> {
    typedef int type;
  };

  template<>
  struct pool_type<PoolRealArray> {
    typedef real_t type;
  };

  template<>
  struct pool_type<PoolStringArray> {
    typedef String type;
  };

  template<>
  struct pool_type<PoolVector2Array> {
    typedef Vector2 type;
  };

  template<>
  struct pool_type<PoolVector3Array> {
    typedef Vector3 type;
  };

  template<>
  struct pool_type<PoolColorArray> {
    typedef Color type;
  };
  
  template<class Function,class Pool>
  inline void pool_foreach_write(Pool &&pool, Function f) {
    Pool::Write write = pool.write();
    typename pool_type<Pool>::type *ptr = write.ptr();
    for(int i=0,e=pool.size();i<e;i++)
      if(f(*ptr[i]))
        return;
  }
  
  template<class Function,class Pool>
  inline void pool_foreach_read(const Pool &&pool, Function f) {
    Pool::Read read = pool.write();
    const typename pool_type<Pool>::type *ptr = read.ptr();
    for(int i=0,e=pool.size();i<e;i++)
      if(f(*ptr[i]))
        return;
  }
  
  template<class T>
  inline String str(const T &t) {
    return String(Variant(t));
  }
  
  template<>
  inline String str(const std::wstring &s) {
    const wchar_t *c = s.c_str();
    if(c&&*c)
      return String(c);
    return String();
  }
  
  inline std::wstring to_wstring(const String &s) {
    const wchar_t *c = s.unicode_str();
    return c ? std::wstring(c) : std::wstring();
  }

  namespace CE {

    inline Vector2 to_xz(const Vector3 &v) {
      return Vector2(v.x,v.z);
    }
    inline Vector3 to_xyz(const Vector2 &xz,real_t y) {
      return Vector3(xz.x,y,xz.y);
    }

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
  }
}

#endif
