#ifndef HUDSTATDISPLAY_HPP
#define HUDSTATDISPLAY_HPP

#include <Godot.hpp>
#include <Control.hpp>
#include <Ref.hpp>
#include <DynamicFont.hpp>
#include <Variant.hpp>

namespace godot {
  class HUDStatDisplay: public Control {
    GODOT_CLASS(HUDStatDisplay, Control)
  private:
    Ref<DynamicFont> icon_font;
    int x_justify, y_justify, x_orientation;
    static const int default_x_justify, default_y_justify, default_x_orientation;

    Color background_color,
      outline_color,
      structure_color,
      armor_color,
      shields_color,
      fuel_color,
      heat_color,
      energy_color,
      efficiency_color;

    static const Color default_background_color,
      default_outline_color,
      default_structure_color,
      default_armor_color,
      default_shields_color,
      default_fuel_color,
      default_heat_color,
      default_energy_color,
      default_efficiency_color;

    // FIXME: Array bars
    float original_font_size, original_font_ascent, original_height, text_ratio;
    bool initialized;
    // FIXME: Dictionary stats
    
    real_t target_ratio;
    real_t text_padded_height;
    real_t text_padding;
    real_t bar_padded_height;
    real_t bar_padding;

    static const real_t default_target_ratio, default_text_padded_height,
      default_text_padding, default_bar_padded_height, default_bar_padding;

    struct BarInfo {
      char letter;
      String nowname,maxname;
      Color color;
      real_t nowval,maxval;
    };

    static const int bar_count=7;
    BarInfo bars[bar_count];
  public:
    HUDStatDisplay();
    ~HUDStatDisplay();
    void _init();
    void _ready();
    void player_target_changed(Variant system,Variant new_target);
    void player_target_nothing(Variant system);
    bool initialize();
    void update_ship_stats(Variant updated);
    void _on_Control_resized();
    void _draw();
    static void _register_methods();
  private:
    static Color dimmed(Color bright);
  };
}

#endif
