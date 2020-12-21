extends Node2D

export var structure_have: Color = Color(1,0.2,0.2,1.0)
export var structure_lack: Color = Color(0.4,0.2,0.2,1.0)
export var hull_have: Color = Color(0.9,0.7,0.1,1.0)
export var hull_lack: Color = Color(0.5,0.3,0.0,1.0)
export var shields_have: Color = Color(0.4,0.4,1.0,1.0)
export var shields_lack: Color = Color(0.1,0.1,0.5,1.0)
export var planet_circle_color: Color = Color(1,1,1,0.4)
export var planet_circle_thickness: float = 8.0
export var planet_target_border: float = 5.0
export var ship_circle_color: Color = Color(1,0,0,0.7)
export var ship_circle_thickness: float = 1.5
export var ship_target_border: float = 6.5

var stats: Dictionary = {}
var first: bool = true

func player_target_changed(var system):
	system.disconnect('player_target_changed',self,'player_target_changed')
	queue_free()

func player_target_stats_updated(var new_stats: Dictionary):
	stats=new_stats.duplicate(true)
	update()

func draw_hp_arc(center: Vector2,have: Color,all: Color,radius: float,start: float,end: float,hp: float,hp_max: float):
	draw_arc(center,radius,start,end,40,all,3,true)
	draw_arc(center,radius,start,start + (end-start)*hp/hp_max,40,have,2,true)

func _draw():
	if first:
		first=false
		return
	var stats_local=stats
	var target=get_parent()
	var camera=get_viewport().get_camera()
	if camera==null:
		return
	var camera_angle = camera.rotation.x+PI/2
	var pos = target.translation
	var pos2d: Vector2 = camera.unproject_position(target.translation)
	
	# Crosshairs
	var out: Vector3
	var circle_width: float = 2
	var circle_color: Color
	
	if stats_local.has('radius'):
		# Tight circle around planets
		out = pos+Vector3(stats_local['radius']+0.25,0,0).rotated(Vector3(0,0,1),camera_angle)
		circle_color = planet_circle_color
		circle_width = planet_circle_thickness
	elif stats_local.has('aabb'):
		# Circle whole bounding box for jagged things like ships
		circle_width = ship_circle_thickness
		circle_color = ship_circle_color
		var aabb: AABB = stats_local['aabb']
		out = pos+(aabb.size/2.0).rotated(Vector3(0,0,1),camera_angle)
	else:
		return
	
	var out2d: Vector2 = camera.unproject_position(out)
	var radius: float = pos2d.distance_to(out2d)
	if stats_local.has('structure'):
		draw_hp_arc(pos2d,shields_have,shields_lack,radius+ship_target_border,
			0,2*PI/3,stats_local['shields'],stats_local['max_shields'])
		draw_hp_arc(pos2d,hull_have,hull_lack,radius+ship_target_border,
			2*PI/3,4*PI/3,stats_local['armor'],stats_local['max_armor'])
		draw_hp_arc(pos2d,structure_have,structure_lack,radius+ship_target_border,
			4*PI/3,2*PI,stats_local['structure'],stats_local['max_structure'])
	else:
		draw_arc(pos2d,radius+planet_target_border,0.0,2*PI,240,circle_color,circle_width,true)
