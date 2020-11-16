extends Node2D

func player_target_deselect(var system):
	system.disconnect('player_target_deselect',self,'player_target_deselect')
	queue_free()

func _process(_delta: float):
	update()

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
		show_cross = true
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
	draw_arc(pos2d,radius+5.0,0.0,2*PI,240,circle_color,circle_width,true)
	if show_cross:
		draw_line(Vector2(pos2d.x+radius/2,pos2d.y),Vector2(pos2d.x+radius*1.1+5.0,pos2d.y),cross_color,cross_width,true)
		draw_line(Vector2(pos2d.x-radius/2,pos2d.y),Vector2(pos2d.x-radius*1.1-5.0,pos2d.y),cross_color,cross_width,true)
		draw_line(Vector2(pos2d.x,pos2d.y+radius/2),Vector2(pos2d.x,pos2d.y+radius*1.1+5.0),cross_color,cross_width,true)
		draw_line(Vector2(pos2d.x,pos2d.y-radius/2),Vector2(pos2d.x,pos2d.y-radius*1.1-5.0),cross_color,cross_width,true)

	# 
