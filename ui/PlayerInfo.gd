extends Node2D

var structure: float = 1.0
var armor: float = 1.0
var shields: float = 1.0
var fuel: float = 1.0
var heat: float = 1.0
var energy: float = 1.0
var max_structure: float = 1.0
var max_armor: float = 1.0
var max_shields: float = 1.0
var max_fuel: float = 1.0
var max_heat: float = 1.0
var max_energy: float = 1.0

export var background_color: Color = Color(0,0, 0.0, 0.3)
export var structure_have: Color =   Color(0.8, 0.4, 0.2)
export var structure_lack: Color =   Color(0.5, 0.2, 0.0)
export var armor_have: Color =       Color(0.9, 0.7, 0.1)
export var armor_lack: Color =       Color(0.5, 0.3, 0.0)
export var shields_have: Color =     Color(0.4, 0.4, 1.0)
export var shields_lack: Color =     Color(0,0, 0.5, 1.0)
export var fuel_have: Color =        Color(0.4, 0.2, 0.8)
export var fuel_lack: Color =        Color(0.2, 0.0, 0.7)
export var heat_have: Color =        Color(0.9, 0.4, 0.4)
export var heat_lack: Color =        Color(0.5, 0.2, 0.2)
export var energy_have: Color =      Color(0.9, 0.9, 0.7)
export var energy_lack: Color =      Color(0.6, 0.6, 0.5)

func update_stat(new: float,old: float,update_flag: Array) -> float:
	if new!=old:
		update_flag[0]=true
	return new

func update_ship_stats(stats: Dictionary):
	Player.set_ship_combat_stats(stats)
	var updated: Array = [false] # will be [true] if any stat changed
	structure = update_stat(stats.get('structure',0),structure,updated)
	max_structure = update_stat(stats.get('max_structure',structure),max_structure,updated)
	armor = update_stat(stats.get('armor',0),armor,updated)
	max_armor = update_stat(stats.get('max_armor',armor),max_armor,updated)
	shields = update_stat(stats.get('shields',0),shields,updated)
	max_shields = update_stat(stats.get('max_shields',shields),max_shields,updated)
	fuel = update_stat(stats.get('fuel',0),fuel,updated)
	max_fuel = update_stat(stats.get('max_fuel',fuel),max_fuel,updated)
	heat = update_stat(stats.get('heat',0),heat,updated)
	max_heat = update_stat(stats.get('max_heat',0),max_heat,updated)
	energy = update_stat(stats.get('energy',0),energy,updated)
	max_energy = update_stat(stats.get('max_energy',0),max_energy,updated)
	if updated[0]:
		update()

func draw_hp_arc(viewport_size: Vector2,now: float,cap: float,radius: float,width: float,have: Color,lack: Color):
	var size = 2.0 - clamp(now/max(1.0,cap),0.0,1.0)
	draw_arc(viewport_size,radius,-PI/2.0,-PI,40,lack,width*0.4)
	draw_arc(viewport_size,radius,-PI*size/2.0,-PI,40,have,width*0.4)

func _draw():
	var viewport_size: Vector2 = get_viewport_rect().size
	var goal = viewport_size*Vector2(.1,.17)
	var radius = min(goal[0],goal[1])
	draw_arc(viewport_size,radius*0.47,-PI/2.0,-PI,40,background_color,radius*0.5)
	draw_hp_arc(viewport_size,fuel,max_fuel,radius*0.65,radius/10,fuel_have,fuel_lack)
	draw_hp_arc(viewport_size,shields,max_shields,radius*0.57,radius/10,shields_have,shields_lack)
	draw_hp_arc(viewport_size,armor,max_armor,radius*0.5,radius/10,armor_have,armor_lack)
	draw_hp_arc(viewport_size,structure,max_structure,radius*0.43,radius/10,structure_have,structure_lack)
	draw_hp_arc(viewport_size,heat,max_heat,radius*0.36,radius/10,heat_have,heat_lack)
	draw_hp_arc(viewport_size,energy,max_energy,radius*0.29,radius/10,energy_have,energy_lack)
