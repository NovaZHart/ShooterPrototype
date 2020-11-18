extends Node2D

var structure_have: Color = Color(1,0.2,0.2,1.0)
var structure_lack: Color = Color(0.4,0.2,0.2,1.0)
var hull_have: Color = Color(0.9,0.7,0.1,1.0)
var hull_lack: Color = Color(0.5,0.3,0.0,1.0)
var shields_have: Color = Color(0.4,0.4,1.0,1.0)
var shields_lack: Color = Color(0.1,0.1,0.5,1.0)

func player_target_deselect(var system):
	system.disconnect('player_target_deselect',self,'player_target_deselect')
	queue_free()

func _process(_delta: float):
	update()

func draw_hp_arc(center: Vector2,have: Color,all: Color,radius: float,start: float,end: float,hp: float,hp_max: float):
	draw_arc(center,radius,start,end,40,all,3,true)
	draw_arc(center,radius,start,start + (end-start)*hp/hp_max,40,have,2,true)

func _draw():
	var target=get_parent()
	var camera=get_viewport().get_camera()
	if camera==null:
		return
	var pos = Vector3(target.translation.x,-30,target.translation.z)
	var pos2d: Vector2 = camera.unproject_position(pos)
	var aabb: AABB = target.get_combined_aabb()
	
	# Crosshairs
	var out: Vector3
	var circle_width = 2
	var cross_width = 1.5
	var circle_color
	var cross_color
	var show_cross = true
	
	if target.has_method('is_a_planet') and target.is_a_planet():
		# Tight circle around planets
		var max_size = max(aabb.size.x,aabb.size.z)
		out = pos+Vector3(max_size/2+0.25,0,0)
		circle_color = Color(1,1,1,0.4)
		cross_color = Color(1,1,1,1)
		circle_width = 8.0
		show_cross = false
	else:
		# Circle whole bounding box for jagged things like ships
		circle_width = 1.5
		cross_width = 1.0
		circle_color = Color(1,0,0,0.7)
		cross_color = Color(1,0,0,1.0)
		out = pos+Vector3(aabb.size.x/2,0,aabb.size.z/2)
		show_cross = false
	var out2d: Vector2 = camera.unproject_position(out)
	var radius: float = pos2d.distance_to(out2d)
	if show_cross:
		draw_line(Vector2(pos2d.x+radius/2,pos2d.y),Vector2(pos2d.x+radius*1.1+5.0,pos2d.y),cross_color,cross_width,true)
		draw_line(Vector2(pos2d.x-radius/2,pos2d.y),Vector2(pos2d.x-radius*1.1-5.0,pos2d.y),cross_color,cross_width,true)
		draw_line(Vector2(pos2d.x,pos2d.y+radius/2),Vector2(pos2d.x,pos2d.y+radius*1.1+5.0),cross_color,cross_width,true)
		draw_line(Vector2(pos2d.x,pos2d.y-radius/2),Vector2(pos2d.x,pos2d.y-radius*1.1-5.0),cross_color,cross_width,true)

	if target.has_method('get_structure'):
		draw_hp_arc(pos2d,shields_have,shields_lack,radius+6.5,0,2*PI/3,target.shields,target.max_shields)
		draw_hp_arc(pos2d,hull_have,hull_lack,radius+6.5,2*PI/3,4*PI/3,target.hull,target.max_hull)
		draw_hp_arc(pos2d,structure_have,structure_lack,radius+6.5,4*PI/3,2*PI,target.structure,target.max_structure)
	else:
		draw_arc(pos2d,radius+5.0,0.0,2*PI,240,circle_color,circle_width,true)
