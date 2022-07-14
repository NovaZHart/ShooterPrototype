#ifndef OBJECTIDGENERATOR_HPP
#define OBJECTIDGENERATOR_HPP

#include <unordered_map>

namespace godot {
  class ObjectIdGenerator {
  public:
    typedef int64_t object_id;
    object_id last_id;
  public:
    inline ObjectIdGenerator():
      last_id(0)
    {}
    inline explicit ObjectIdGenerator(const ObjectIdGenerator &m):
      last_id(m.last_id)
    {}
    inline object_id next() { return last_id++; }
    inline object_id count() const { return last_id; }
    inline ObjectIdGenerator &operator = (const ObjectIdGenerator &m) {
      last_id=m.last_id;
      return *this;
    }
    inline bool operator == (const ObjectIdGenerator &m) const {
      return last_id==m.last_id;
    }
    inline bool operator != (const ObjectIdGenerator &m) const {
      return last_id!=m.last_id;
    }
  };

  // To simplify code, copy the object_id typedef to the godot scope.
  typedef ObjectIdGenerator::object_id object_id;

  typedef std::unordered_map<int32_t,object_id> rid2id_t;
  typedef std::unordered_map<int32_t,object_id>::iterator rid2id_iter;
  typedef std::unordered_map<int32_t,object_id>::iterator rid2id_const_iter;
}

#endif