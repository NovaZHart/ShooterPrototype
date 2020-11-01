extends Node2D

var structure: float = 1.0 setget set_structure,get_structure
var hull: float = 1.0 setget set_hull,get_hull
var shields: float = 1.0 setget set_shields,get_shields
var max_structure: float = 1.0 setget set_max_structure,get_max_structure
var max_hull: float = 1.0 setget set_max_hull,get_max_hull
var max_shields: float = 1.0 setget set_max_shields,get_max_shields

func set_structure(f: float): structure = f
func get_structure() -> float: return structure 
func set_hull(f: float): hull = f
func get_hull() -> float: return hull 
func set_shields(f: float): shields = f
func get_shields() -> float: return shields 
func set_max_structure(f: float): max_structure = f
func get_max_structure() -> float: return max_structure 
func set_max_hull(f: float): max_hull = f
func get_max_hull() -> float: return max_hull 
func set_max_shields(f: float): max_shields = f
func get_max_shields() -> float: return max_shields 

var background_color: Color = Color(0,0,0,0.3)
var structure_have: Color = Color(1,0.2,0.2,1.0)
var structure_lack: Color = Color(0.4,0,0,1.0)
var hull_have: Color = Color(0.9,0.7,0.1,1.0)
var hull_lack: Color = Color(0.5,0.3,0.0,1.0)
var shields_have: Color = Color(0.4,0.4,1.0,1.0)
var shields_lack: Color = Color(0,0,0.5,1.0)

func update_hp_from(var somewhere):
	structure = somewhere.structure
	max_structure = somewhere.max_structure
	hull = somewhere.hull
	max_hull = somewhere.max_hull
	shields = somewhere.shields
	max_shields = somewhere.max_shields
	update()

func draw_hp_arc(viewport_size: Vector2,now: float,cap: float,radius: float,width: float,have: Color,lack: Color):
	var size = 2.0 - now/max(1.0,cap)
	draw_arc(viewport_size,radius,-PI/2.0,-PI,40,lack,width*0.4)
	draw_arc(viewport_size,radius,-PI*size/2.0,-PI,40,have,width*0.4)

# Called when the node enters the scene tree for the first time.
func _draw():
	var viewport_size: Vector2 = get_viewport_rect().size
	var goal = viewport_size*Vector2(.1,.17)
	var radius = min(goal[0],goal[1])
	draw_arc(viewport_size,radius*0.5,-PI/2.0,-PI,40,background_color,radius*0.25)
	draw_hp_arc(viewport_size,shields,max_shields,radius*0.57,radius/10,shields_have,shields_lack)
	draw_hp_arc(viewport_size,hull,max_hull,radius*0.5,radius/10,hull_have,hull_lack)
	draw_hp_arc(viewport_size,structure,max_structure,radius*0.43,radius/10,structure_have,structure_lack)
