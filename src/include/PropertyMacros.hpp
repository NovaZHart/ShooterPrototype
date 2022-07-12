#ifndef PROPERTYMACROS_HPP
#define PROPERTYMACROS_HPP

#define PROP_GET_VAL(proptype,propname) \
  proptype get_##propname() const { return propname; }

#define PROP_SET_REF(proptype,propname) \
  void set_##propname(const proptype &__getset_val__) { propname=__getset_val__; }

#define PROP_SET_VAL(proptype,propname) \
  void set_##propname(proptype __getset_val__) { propname=__getset_val__; }

#define PROP_IS_VAL(propname) \
  bool is_##propname() const { return !!propname; }

#define PROP_HAVE_VAL(propname) \
  bool have_##propname() const { return !!propname; }

#define PROP_GET_CONST_REF(proptype,propname) \
  const proptype & get_##propname() const { return propname; }

#define PROP_GET_NONCONST_REF(proptype,propname) \
  proptype & get_##propname() { return propname; }

#define PROP_GET_REF(proptype,propname) \
  PROP_GET_NONCONST_REF(proptype,propname) \
  PROP_GET_CONST_REF(proptype,propname)

#define PROP_GETSET_VAL(proptype,propname) \
  PROP_GET_VAL(proptype,propname) \
  PROP_SET_VAL(proptype,propname)

#define PROP_GETSET_REFVAL(proptype,propname) \
  PROP_GET_VAL(proptype,propname) \
  PROP_SET_REF(proptype,propname)

#define PROP_GETSET_REF(proptype,propname) \
  PROP_GET_REF(proptype,propname) \
  PROP_SET_REF(proptype,propname)

#define PROP_GETSET_CONST_REF(proptype,propname) \
  PROP_GET_CONST_REF(proptype,propname) \
  PROP_SET_REF(proptype,propname)

#endif
