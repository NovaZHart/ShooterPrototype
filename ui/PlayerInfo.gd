extends Node2D

var structure: float = 1.0
var hull: float = 1.0
var shields: float = 1.0
var max_structure: float = 1.0
var max_hull: float = 1.0
var max_shields: float = 1.0

export var background_color: Color = Color(0,0,0,0.3)
export var structure_have: Color = Color(1,0.2,0.2,1.0)
export var structure_lack: Color = Color(0.4,0,0,1.0)
export var hull_have: Color = Color(0.9,0.7,0.1,1.0)
export var hull_lack: Color = Color(0.5,0.3,0.0,1.0)
export var shields_have: Color = Color(0.4,0.4,1.0,1.0)
export var shields_lack: Color = Color(0,0,0.5,1.0)

func update_stat(new: float,old: float,update_flag: Array) -> float:
	if new!=old:
		update_flag[0]=true
	return new

func update_ship_stats(stats: Dictionary):
	var updated: Array = [false] # will be [true] if any stat changed
	structure = update_stat(stats.get('structure',0),structure,updated)
	max_structure = update_stat(stats.get('max_structure',structure),max_structure,updated)
	hull = update_stat(stats.get('hull',0),hull,updated)
	max_hull = update_stat(stats.get('max_hull',hull),max_hull,updated)
	shields = update_stat(stats.get('shields',0),shields,updated)
	max_shields = update_stat(stats.get('max_shields',shields),max_shields,updated)
	if updated[0]:
		update()

func draw_hp_arc(viewport_size: Vector2,now: float,cap: float,radius: float,width: float,have: Color,lack: Color):
	var size = 2.0 - now/max(1.0,cap)
	draw_arc(viewport_size,radius,-PI/2.0,-PI,40,lack,width*0.4)
	draw_arc(viewport_size,radius,-PI*size/2.0,-PI,40,have,width*0.4)

func _draw():
	var viewport_size: Vector2 = get_viewport_rect().size
	var goal = viewport_size*Vector2(.1,.17)
	var radius = min(goal[0],goal[1])
	draw_arc(viewport_size,radius*0.5,-PI/2.0,-PI,40,background_color,radius*0.25)
	draw_hp_arc(viewport_size,shields,max_shields,radius*0.57,radius/10,shields_have,shields_lack)
	draw_hp_arc(viewport_size,hull,max_hull,radius*0.5,radius/10,hull_have,hull_lack)
	draw_hp_arc(viewport_size,structure,max_structure,radius*0.43,radius/10,structure_have,structure_lack)
