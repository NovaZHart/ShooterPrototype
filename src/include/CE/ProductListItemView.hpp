#ifndef PRODUCTLISTVIEW_HPP
#define PRODUCTLISTVIEW_HPP

#include <memory>

#include "CE/ProductList.hpp"
#include "CE/ObjectIdGenerator.hpp"

namespace godot {
  class ProductListItemView: public Product {
  public:
    ProductListItemView(std::weak_ptr<CE::ProductList> list,CE::object_id id);
    ProductListItemView(const ProductListItemView &p);
    virtual ~ProductListItemView();
    CE::Product *get_product() override;
    const CE::Product *get_product() override;
  private:
    std::weak_ptr<CE::ProductList> list;
    CE::object_id id;
  };
}

#endif
