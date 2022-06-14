#include "HUDStatDisplay.hpp"

#include <algorithm>
#include <assert.h>

using namespace godot;
using namespace std;

const int HUDStatDisplay::default_x_justify =-1;
const int HUDStatDisplay::default_y_justify = 1;
const int HUDStatDisplay::default_x_orientation = -1;
const Color HUDStatDisplay::default_background_color = Color(0.0, 0.0, 0.0, 0.5);
const Color HUDStatDisplay::default_outline_color = Color(0.6, 0.6, 0.6, 0.6);
const Color HUDStatDisplay::default_structure_color = Color(0.8, 0.4, 0.2);
const Color HUDStatDisplay::default_armor_color = Color(0.9, 0.7, 0.1);
const Color HUDStatDisplay::default_shields_color = Color(0.4, 0.4, 1.0);
const Color HUDStatDisplay::default_shields_down_color = Color(0.15, 0.15, 0.2);
const Color HUDStatDisplay::default_fuel_color = Color(0.7, 0.4, 1.0);
const Color HUDStatDisplay::default_heat_color = Color(0.9, 0.4, 0.4);
const Color HUDStatDisplay::default_energy_color = Color(0.9, 0.9, 0.7);
const Color HUDStatDisplay::default_efficiency_color = Color(0.2, 0.8, 0.2);
const real_t HUDStatDisplay::default_target_ratio = 1.3;
const real_t HUDStatDisplay::default_text_padded_height = 0.2;
const real_t HUDStatDisplay::default_text_padding = 0.03;
const real_t HUDStatDisplay::default_bar_padded_height = 0.75;
const real_t HUDStatDisplay::default_bar_padding = 0.05;


HUDStatDisplay::HUDStatDisplay():
  icon_font(),
  x_justify(default_x_justify),
  y_justify(default_y_justify),
  x_orientation(default_x_orientation),
  background_color(default_background_color),
  outline_color(default_outline_color),
  structure_color(default_structure_color),
  armor_color(default_armor_color),
  shields_color(default_shields_color),
  shields_down_color(default_shields_down_color),
  fuel_color(default_fuel_color),
  heat_color(default_heat_color),
  energy_color(default_energy_color),
  efficiency_color(default_efficiency_color),
  original_font_size(0),
  original_font_ascent(0),
  original_height(0),
  text_ratio(0),
  initialized(false),
  target_ratio(default_target_ratio),
  text_padded_height(default_text_padded_height),
  text_padding(default_text_padding),
  bar_padded_height(default_bar_padded_height),
  bar_padding(default_bar_padding),
  bars()
{}

HUDStatDisplay::~HUDStatDisplay() {}

void HUDStatDisplay::_init() {}
void HUDStatDisplay::_ready() {
  connect("resized",this,"_on_Control_resized");
  initialize();
}
void HUDStatDisplay::player_target_changed(Variant system,Variant new_target) {
  set_visible(new_target.has_method("is_ShipStats"));
}
void HUDStatDisplay::player_target_nothing(Variant system) {
  set_visible(false);
}
bool HUDStatDisplay::initialize() {
  if(initialized)
    return true;

  bars[0]={ 'A', "shields", "max_shields", shields_color, 0, 1 };
  bars[1]={ 'B', "armor", "max_armor", armor_color, 0, 1 };
  bars[2]={ 'C', "structure", "max_structure", structure_color, 0, 1 };
  bars[3]={ 'F', "heat", "max_heat", heat_color, 0, 1 };
  bars[4]={ 'D', "energy", "max_energy", energy_color, 0, 1 };
  bars[5]={ 'E', "fuel", "max_fuel", fuel_color, 0, 1 };
  bars[6]={ 'G', "efficiency", "max_efficiency", efficiency_color, 0, 1 };

  if(!is_visible_in_tree())
    return initialized;
  
  Vector2 rect_size = get_rect().size;
  real_t len = rect_size.length();
  
  if(!len)
    return initialized;
  
  original_font_size=icon_font->get_size();
  original_font_ascent=icon_font->get_ascent();
  original_height=fabsf(rect_size.y);
  Vector2 a_size = icon_font->get_char_size('A');
  text_ratio = a_size.y/max(1e-5f,a_size.x);

  initialized=true;
  return initialized;
}

void HUDStatDisplay::update_ship_stats(Variant updated_variant) {
  initialize();
  
  Dictionary updated = updated_variant;
  for(int ibar=0;ibar<bar_count;ibar++) {
    if(updated.has(bars[ibar].nowname))
      bars[ibar].nowval = updated[bars[ibar].nowname];
    if(updated.has(bars[ibar].maxname))
      bars[ibar].maxval = updated[bars[ibar].maxname];
  }

  bool active = updated["cargo_web_active"];
  if(active)
    bars[0].color = shields_down_color;
  else
    bars[0].color = shields_color;
  
  update();
}

Color HUDStatDisplay::dimmed(Color bright) {
  return bright.from_hsv(bright.get_h(),bright.get_s(),bright.get_v()*0.5,0.7);
}

void HUDStatDisplay::_on_Control_resized() {
  initialize();
  update();
}

void HUDStatDisplay::_draw() {
  if(!initialized) {
    //Godot::print_warning("Not initialized in HUDStatDisplay._draw!",__FUNCTION__,__FILE__,__LINE__);
    return;
  }
  if(!icon_font.is_valid()) {
    //Godot::print_error("No icon font in HUDStatDisplay._draw",__FUNCTION__,__FILE__,__LINE__);
    return;
  }
  
  Rect2 me = get_global_rect();
  if(me.size.x<0) {
    me.position.x=me.position.x+me.size.x+1;
    me.size.x=-me.size.x;
  }
  if(me.size.y<0) {
    me.position.y=me.position.y+me.size.y+1;
    me.size.y=-me.size.y;
  }
  
  Rect2 draw_region = Rect2(Vector2(0,0),Vector2(me.size.y/target_ratio,me.size.y));
  if(draw_region.size.y>me.size.y)
    // Container is too wide to fit, so fit height instead:
    draw_region.size = Vector2(me.size.x,me.size.x*target_ratio);
	
  if(x_justify>0)
    draw_region.position.x = me.size.x-draw_region.size.x;
  else if(x_justify==0)
    draw_region.position.x = 0.5*(me.size.x-draw_region.size.x);
	
  if(y_justify>0)
    draw_region.position.y = me.size.y-draw_region.size.y;
  else if(y_justify==0)
    draw_region.position.y = 0.5*(me.size.y-draw_region.size.y);
	
  assert(draw_region.position.y>=0);
  assert(draw_region.position.x>=0);
	
  draw_rect(draw_region,background_color,true);
  //draw_rect(draw_region,outline_color,false,2,true)
	
  real_t ascent = draw_region.size.y*(text_padded_height-2*text_padding);
  icon_font->set_size(original_font_size*ascent/original_font_ascent);
  Vector2 char_size = Vector2(1,1);
  ascent = icon_font->get_ascent();
  for(int ibar=0;ibar<bar_count;ibar++) {
    Vector2 a_size = icon_font->get_char_size(bars[ibar].letter);
    char_size.x = max(char_size.x,a_size.x);
    char_size.y = max(char_size.y,a_size.y);
  }
	

  real_t fbars = bar_count;
  real_t bar_xpad = draw_region.size.x*bar_padding;
  real_t bar_ypad = draw_region.size.y*bar_padding;
  real_t bar_xsize = draw_region.size.x-bar_xpad*2;
  real_t bar_ysize = draw_region.size.y/fbars-bar_ypad*2;
  real_t bar_ystep = draw_region.size.y/fbars;
  Rect2 bar_rect = Rect2(
		draw_region.position + Vector2(bar_xpad,bar_ypad),
		Vector2(bar_xsize,bar_ysize));
  
  for(int ibar=0;ibar<bar_count;ibar++) {
    if(ibar)
      bar_rect.position.y+=bar_ystep;
    BarInfo &bar = bars[ibar];
    Color color = bar.color;
    Color dim_color = dimmed(color);
    Vector2 i_size = icon_font->get_char_size(bar.letter);
    
    real_t text_width = char_size.x*1.1;
    real_t text_xshift = (text_width-i_size.x)/2+2*bar_ysize*text_padded_height;
    real_t remain = bar_xsize-text_width;
    
    if(x_orientation<0)
      draw_string(icon_font,
                  Vector2(bar_rect.position.x-text_xshift,
                          bar_rect.position.y+ascent/2+2*bar_ysize*text_padded_height),bar.letter,color);
    else
      draw_string(icon_font,
                  Vector2(bar_rect.position.x+bar_rect.size.x-text_width+text_xshift,
                          bar_rect.position.y+ascent/2+2*bar_ysize*text_padded_height),bar.letter,color);
		
    real_t value = max(0.0f,bar.nowval);
    real_t bound = max(1e-5f,max(value,bar.maxval));
    float have = value/bound;
    float lack = 1.0-have;
		
    if(x_orientation<0) {
      if(have>1e-5)
        draw_rect(Rect2(bar_rect.position+Vector2(text_width,0),
                        Vector2(remain*have,bar_ysize)),color,true);
      if(lack>1e-5)
        draw_rect(Rect2(bar_rect.position+Vector2(remain*have+text_width,0),
                        Vector2(remain*lack,bar_ysize)),dim_color,true);
      draw_rect(Rect2(bar_rect.position+Vector2(text_width,0),
                      Vector2(remain,bar_ysize)),color,false,0.5,true);
    } else {
      if(lack>1e-5)
        draw_rect(Rect2(bar_rect.position,
                        Vector2(remain*lack,bar_ysize)),dim_color,true);
      if(have>1e-5)
        draw_rect(Rect2(bar_rect.position+Vector2(remain*lack,0),
                        Vector2(remain*have,bar_ysize)),color,true);
      draw_rect(Rect2(bar_rect.position,
                      Vector2(remain,bar_ysize)),color,false,0.5,true);
    }
  }
}

void HUDStatDisplay::_register_methods() {
  register_method("_init", &HUDStatDisplay::_init);
  register_method("_ready", &HUDStatDisplay::_ready);
  register_method("player_target_changed", &HUDStatDisplay::player_target_changed);
  register_method("player_target_nothing", &HUDStatDisplay::player_target_nothing);
  register_method("initialize", &HUDStatDisplay::initialize);
  register_method("update_ship_stats", &HUDStatDisplay::update_ship_stats);
  register_method("_on_Control_resized", &HUDStatDisplay::_on_Control_resized);
  register_method("_draw", &HUDStatDisplay::_draw);

  register_property<HUDStatDisplay, Ref<DynamicFont>>("icon_font", &HUDStatDisplay::icon_font, Ref<DynamicFont>());
  register_property<HUDStatDisplay, int>("x_justify", &HUDStatDisplay::x_justify, default_x_justify);
  register_property<HUDStatDisplay, int>("y_justify", &HUDStatDisplay::y_justify, default_y_justify);
  register_property<HUDStatDisplay, int>("x_orientation", &HUDStatDisplay::x_orientation, default_x_orientation);

  register_property<HUDStatDisplay, Color>("background_color", &HUDStatDisplay::background_color, default_background_color);
  register_property<HUDStatDisplay, Color>("outline_color", &HUDStatDisplay::outline_color, default_outline_color);
  register_property<HUDStatDisplay, Color>("structure_color", &HUDStatDisplay::structure_color, default_structure_color);
  register_property<HUDStatDisplay, Color>("armor_color", &HUDStatDisplay::armor_color, default_armor_color);
  register_property<HUDStatDisplay, Color>("shields_color", &HUDStatDisplay::shields_color, default_shields_color);
  register_property<HUDStatDisplay, Color>("shields_down_color", &HUDStatDisplay::shields_down_color, default_shields_down_color);
  register_property<HUDStatDisplay, Color>("fuel_color", &HUDStatDisplay::fuel_color, default_fuel_color);
  register_property<HUDStatDisplay, Color>("heat_color", &HUDStatDisplay::heat_color, default_heat_color);
  register_property<HUDStatDisplay, Color>("energy_color", &HUDStatDisplay::energy_color, default_energy_color);
  register_property<HUDStatDisplay, Color>("efficiency_color", &HUDStatDisplay::efficiency_color, default_efficiency_color);

  register_property<HUDStatDisplay, real_t>("target_ratio", &HUDStatDisplay::target_ratio, default_target_ratio);
  register_property<HUDStatDisplay, real_t>("text_padded_height", &HUDStatDisplay::text_padded_height, default_text_padded_height);
  register_property<HUDStatDisplay, real_t>("text_padding", &HUDStatDisplay::text_padding, default_text_padding);
  register_property<HUDStatDisplay, real_t>("bar_padded_height", &HUDStatDisplay::bar_padded_height, default_bar_padded_height);
  register_property<HUDStatDisplay, real_t>("bar_padding", &HUDStatDisplay::bar_padding, default_bar_padding);
}
