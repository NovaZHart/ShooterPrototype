extends Node2D

var map_center: Vector2 setget set_map_center, get_map_center
export var map_radius: float = 300
export var minimap_size: float = 0.1
export var background_color: Color = Color(0,0,0,0.3)
export var border_color: Color = Color(0.5,0.5,0.5,1)

func set_map_center(f: Vector2): map_center = f
func get_map_center() -> Vector2: return map_center

func view_center_changed(center: Vector3,_size: Vector3):
	map_center=Vector2(center.z,-center.x)

func _process(_delta):
	update()

func _draw():
	var viewport_size: Vector2 = get_viewport_rect().size
	var goal = viewport_size*Vector2(.1,.17)
	var minimap_radius = min(goal[0],goal[1])
	var minimap_center: Vector2 = Vector2(minimap_radius,minimap_radius)
	var bounds_radius = minimap_radius*0.95
	
	draw_circle(minimap_center,bounds_radius,background_color)
	draw_arc(minimap_center,bounds_radius,0,2*PI,80,border_color,1.5,true)
	combat_engine.draw_minimap(self,minimap_size,map_center,map_radius)

