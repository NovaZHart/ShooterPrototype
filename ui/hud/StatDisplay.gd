extends Control

export var icon_font: DynamicFont
export var x_justify: int = -1
export var y_justify: int = 1
export var x_orientation: int = -1

export var background_color: Color = Color(0.0, 0.0, 0.0, 0.5)
export var outline_color: Color =    Color(0.6, 0.6, 0.6, 0.6)
export var structure_color: Color =  Color(0.8, 0.4, 0.2)
export var armor_color: Color =      Color(0.9, 0.7, 0.1)
export var shields_color: Color =    Color(0.4, 0.4, 1.0)
export var fuel_color: Color =       Color(0.7, 0.4, 1.0)
export var heat_color: Color =       Color(0.9, 0.4, 0.4)
export var energy_color: Color =     Color(0.9, 0.9, 0.7)
export var efficiency_color: Color = Color(0.2, 0.8, 0.2)

var bars: Array

var original_font_size: float
var original_font_ascent: float
var original_height: float
var initialized: bool = false
var text_ratio: float
var stats: Dictionary = {}

const target_ratio: float = 1.3
const text_padded_height: float = 0.2
const text_padding: float = 0.03
const bar_padded_height: float = 0.75
const bar_padding: float = 0.05
#const bar_inner_ypart: float = bar_padded_height-2.0*bar_padding
#const bar_inner_xpart: float = 0.95-2.0*bar_padding

func _ready():
	#rect_clip_content = true
	initialize()

func player_target_changed(_system,new_target):
	visible = new_target.has_method('is_ShipStats')

func player_target_nothing(_system):
	print('target nothing')
	visible=false

func update_ship_stats(updated: Dictionary):
	initialize()
	var new_stats: Dictionary = {}
	for ibar in range(len(bars)):
		for key in [ bars[ibar][1], bars[ibar][2] ]:
			if updated.has(key):
				new_stats[key] = updated[key]
	stats = new_stats
	update()

func initialize():
	if not initialized and is_visible_in_tree() and rect_size.length()>0:
		initialized = true

		bars = [
			[ 'A', 'shields', 'max_shields', shields_color],
			[ 'B', 'armor', 'max_armor', armor_color],
			[ 'C', 'structure', 'max_structure', structure_color],
			[ 'F', 'heat', 'max_heat', heat_color],
			[ 'D', 'energy', 'max_energy', energy_color],
			[ 'E', 'fuel', 'max_fuel', fuel_color],
			[ 'G', 'efficiency', 'max_efficiency', efficiency_color],
		]
		
		original_font_size = icon_font.size
		original_font_ascent = icon_font.get_ascent()
		original_height = rect_size.y
		var a_size: Vector2 = icon_font.get_char_size(ord('A'))
		text_ratio = a_size.y/a_size.x

func dimmed(bright: Color) -> Color:
	return Color.from_hsv(bright.h,bright.s,bright.v*0.5,0.7)
	
func _on_Control_resized():
	initialize()
	update()

func _draw():
	if not initialized:
		return
	
	var me: Rect2 = get_global_rect().abs()
	var draw_rect: Rect2 = Rect2(Vector2(0,0),Vector2(me.size.y/target_ratio,me.size.y))
	if draw_rect.size.y>me.size.y:
		# Container is too wide to fit, so fit height instead:
		draw_rect.size = Vector2(me.size.x,me.size.x*target_ratio)
	
	if x_justify>0:
		draw_rect.position.x = me.size.x-draw_rect.size.x
	elif x_justify==0:
		draw_rect.position.x = 0.5*(me.size.x-draw_rect.size.x)
	
	if y_justify>0:
		draw_rect.position.y = me.size.y-draw_rect.size.y
	elif y_justify==0:
		draw_rect.position.y = 0.5*(me.size.y-draw_rect.size.y)
	
	assert(draw_rect.position.y>=0)
	assert(draw_rect.position.x>=0)
	
	draw_rect(draw_rect,background_color,true)
	#draw_rect(draw_rect,outline_color,false,2,true)
	
	var ascent = draw_rect.size.y*(text_padded_height-2*text_padding)
	icon_font.size = original_font_size*ascent/original_font_ascent
	var char_size: Vector2 = Vector2(1,1)
	ascent = icon_font.get_ascent()
	for ibar in range(len(bars)):
		var a_size: Vector2 = icon_font.get_char_size(ord(bars[ibar][0]))
		char_size.x = max(char_size.x,a_size.x)
		char_size.y = max(char_size.y,a_size.y)
	
	var nbars: float = len(bars)
	var fbars: float = float(nbars)
	var bar_xpad: float = draw_rect.size.x*bar_padding
	var bar_ypad: float = draw_rect.size.y*bar_padding
	var bar_xsize: float = draw_rect.size.x-bar_xpad*2
	var bar_ysize: float = draw_rect.size.y/fbars-bar_ypad*2
	var bar_ystep: float = draw_rect.size.y/fbars
	var bar_rect: Rect2 = Rect2(
		draw_rect.position + Vector2(bar_xpad,bar_ypad),
		Vector2(bar_xsize,bar_ysize))
	for ibar in range(len(bars)):
		if ibar:
			bar_rect.position.y+=bar_ystep
		var color: Color = bars[ibar][3]
		var dim_color: Color = dimmed(color)
		var i_size: Vector2 = icon_font.get_char_size(ord(bars[ibar][0]))
		
		var text_width: float = char_size.x*1.1
		var text_xshift: float = (text_width-i_size.x)/2+2*bar_ysize*text_padded_height
		var remain: float = bar_xsize-text_width
		
		if x_orientation<0:
			draw_string(icon_font,
				Vector2(bar_rect.position.x-text_xshift,
				bar_rect.position.y+ascent/2+2*bar_ysize*text_padded_height),bars[ibar][0],color)
		else:
			draw_string(icon_font,
				Vector2(bar_rect.position.x+bar_rect.size.x-text_width+text_xshift,
				bar_rect.position.y+ascent/2+2*bar_ysize*text_padded_height),bars[ibar][0],color)
		
		var value: float = max(0.0,stats.get(bars[ibar][1],0.0))
		var bound: float = max(1e-5,max(value,stats.get(bars[ibar][2],1.0)))
		var have: float = value/bound
		var lack: float = 1.0-have
		
		if x_orientation<0:
			if have>1e-5:
				draw_rect(Rect2(bar_rect.position+Vector2(text_width,0),
					Vector2(remain*have,bar_ysize)),color,true)
			if lack>1e-5:
				draw_rect(Rect2(bar_rect.position+Vector2(remain*have+text_width,0),
					Vector2(remain*lack,bar_ysize)),dim_color,true)
			draw_rect(Rect2(bar_rect.position+Vector2(text_width,0),
				Vector2(remain,bar_ysize)),color,false,0.5,true)
		else:
			if lack>1e-5:
				draw_rect(Rect2(bar_rect.position,
					Vector2(remain*lack,bar_ysize)),dim_color,true)
			if have>1e-5:
				draw_rect(Rect2(bar_rect.position+Vector2(remain*lack,0),
					Vector2(remain*have,bar_ysize)),color,true)
			draw_rect(Rect2(bar_rect.position,
				Vector2(remain,bar_ysize)),color,false,0.5,true)

