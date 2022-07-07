#ifndef SALVAGE_HPP
#define SALVAGE_HPP

#include <memory>
#include <unordered_map>
#include <string>

#include <Ref.hpp>
#include <Mesh.hpp>
#include <Godot.hpp>
#include <Dictionary.hpp>

#include "CE/CheapRand32.hpp"

namespace godot {
  namespace CE {
    
    struct Salvage {
      const Ref<Mesh> flotsam_mesh;
      const real_t flotsam_scale;
      const String cargo_name;
      const int cargo_count;
      const real_t cargo_unit_mass;
      const real_t cargo_unit_value;
      const real_t armor_repair;
      const real_t structure_repair;
      const real_t fuel;
      const real_t spawn_duration;
      const real_t grab_radius;

      Salvage(Dictionary dict);
      Salvage(const Salvage &,int new_count);
      ~Salvage();
    };

    ////////////////////////////////////////////////////////////////////

    class SalvagePalette {
      std::unordered_map<wstring,std::shared_ptr<const Salvage>> salvage;
    public:
      static constexpr real_t max_product_fraction = 1.0f;
      static constexpr real_t min_product_fraction = 0.3f;
      static constexpr real_t product_fraction_range = max_product_fraction-min_product_fraction;
      
      SalvagePalette(Dictionary from);
      std::shared_ptr<Salvage> instance_salvage(const wstring &whut,CheapRand32 &rand) const;

      inline ~SalvagePalette() {};
      inline std::shared_ptr<const Salvage> get_salvage(const wstring &whut) const {
        auto found=salvage.find(whut);
        return (found==salvage.end()) ? nullptr : found->second;
      }
      inline void add_salvage(const wstring &whut,std::shared_ptr<const Salvage> salvage) {
        salvage.emplace(whut,salvage);
      }
    };

  }
}

#endif
