extends Spatial

export var label_font: Font
export var min_sun_height: float = 50.0
export var max_sun_height: float = 1e5
export var min_camera_size: float = 25
export var max_camera_size: float = 500
export var detail_level: float = 150

var play_speed: float = 0.0
var planet_time: float = 0.0

var is_paging_up: bool = false
var is_paging_down: bool = false
var ui_scroll: float = 0.0
var is_location_select_down: bool = false
var was_location_select_down: bool = false

var system
var planet_mutex: Mutex = Mutex.new()
var has_focus: bool = false
var arrow_move: Vector3 = Vector3()
var selection: NodePath = NodePath()
var last_clicked: NodePath = NodePath()
var is_moving = false
var last_position = null
var start_position = null
var last_screen_position = null
var camera_start = null

signal select_space_object
signal select_nothing
signal view_center_changed

func full_game_state_path(var path: NodePath):
	var node = game_state.universe.get_node_or_null(path)
	if node:
		return node.get_path()
	else:
		push_error('No game state node exists at path '+str(path))
	return path

func gain_focus():
	has_focus = true
	$Annotations.update()

func lose_focus():
	has_focus = false
	is_paging_up=false
	is_paging_down=false
	is_location_select_down=false
	was_location_select_down=false
	ui_scroll=0
	is_moving = false
	last_position=null
	last_screen_position=null
	start_position=null
	camera_start=null
	$Annotations.update()

func update_space_background(from=null) -> bool:
	if from==null:
		from=system
	var result = $SpaceBackground.update_from(from)
	while result is GDScriptFunctionState and result.is_valid():
		result = yield(result,'completed')
	if not result:
		push_error('space background regeneration failed')
		return false
	return true

func handle_input():
	if not has_focus:
		return
	if Input.is_action_just_released("wheel_up"):
		ui_scroll=1.5
	if Input.is_action_just_released("wheel_down"):
		ui_scroll=-1.5
	is_paging_up = Input.is_action_pressed("ui_page_up")
	is_paging_down = Input.is_action_pressed("ui_page_down")
	was_location_select_down = is_location_select_down
	is_location_select_down = Input.is_action_pressed("ui_location_select")
	arrow_move = Vector3(
		float(Input.is_action_pressed('ui_up'))-float(Input.is_action_pressed('ui_down')),
		0.0,
		float(Input.is_action_pressed('ui_right'))-float(Input.is_action_pressed('ui_left')))
	if Input.is_action_just_released('ui_select'):
		if abs(play_speed)>1e-5:
			play_speed=0
		else:
			play_speed=1.0

func handle_selection():
	if Input.is_action_just_pressed('ui_location_select'):
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var space_pos: Vector3 = $TopCamera.project_position(mouse_pos,-10)
		var y500: Vector3 = Vector3(0.0,500.0,0.0)
		var space: PhysicsDirectSpaceState = get_world().direct_space_state
		var result: Dictionary = space.intersect_ray(space_pos-y500,space_pos+y500)
		last_position = space_pos
		start_position = space_pos
		last_screen_position = mouse_pos
		camera_start = $TopCamera.translation
		if result:
			var path = result['collider'].game_state_path
			last_clicked = full_game_state_path(path)
#			selection = full_game_state_path(path)
			if path:
				emit_signal('select_space_object',path)
		elif selection:
#			selection = NodePath()
			last_clicked = NodePath()
			emit_signal('select_nothing')
	elif last_position and Input.is_action_pressed('ui_location_select'):
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var space_pos: Vector3 = $TopCamera.project_position(mouse_pos,-10)
		if not last_clicked:
			var start_pos: Vector3 = $TopCamera.project_position(last_screen_position,-10)
			var pos_diff = start_pos-space_pos
			pos_diff.y=0
			if pos_diff.length()>1e-3:
				center_view(camera_start + pos_diff)
		elif is_moving or space_pos.distance_to(start_position)>0.25:
			is_moving = true
			play_speed = 0
	if last_clicked and is_moving and last_position:
		$Annotations.update()
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var space_pos: Vector3 = $TopCamera.project_position(mouse_pos,-10)
		if not Input.is_action_pressed('ui_location_select'):
			var data = game_state.universe.get_node_or_null(last_clicked)
			var adjust: Dictionary = data.orbital_adjustments_to(planet_time,space_pos)
			universe_editor.state.push(universe_editor.SpaceObjectDataChange.new(
				data.get_path(),adjust,false,false,false,true))
			is_moving = false
			last_position=null
			last_screen_position=null
			start_position=null
			last_clicked = NodePath()
		else:
			last_position=space_pos
		
func update_planet_locations():
	var success: bool = true
	for planet in $Planets.get_children():
		var data = game_state.universe.get_node_or_null(planet.game_state_path)
		if data:
			planet.translation = data.planet_translation(planet_time)
			planet.rotation = data.planet_rotation(planet_time)
		else:
			push_error('Planet data location ('+str(planet.game_state_path)+') does not exist.')
			success=false
	$Annotations.update()
	return success

func _process(delta):
	if has_focus:
		handle_input()
		handle_selection()
		
		if arrow_move.length()>1e-5:
			center_view($TopCamera.translation+arrow_move*delta*$TopCamera.size)
		
		var ui_zoom: int = 0
		ui_zoom = int(is_paging_up)-int(is_paging_down)
		var zoom: float = pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll)
		ui_scroll*=0.7
		if abs(ui_scroll)<.05:
			ui_scroll=0
		set_zoom(zoom)
	if abs(play_speed)>1e-5:
		planet_time += delta*0.5
		update_planet_locations()

func set_zoom(zoom: float,original: float=-1) -> void:
	$Annotations.update()
	var from: float = original if original>1 else $TopCamera.size
	var new_size: float = clamp(zoom*from,min_camera_size,max_camera_size)
	if abs($TopCamera.size-new_size)>1e-5:
		$TopCamera.size = new_size
		center_view()

func get_main_camera() -> Node:
	return $TopCamera

func spawn_planet(planet: Spatial) -> bool:
	$Annotations.update()
	planet_mutex.lock()
	$Planets.add_child(planet)
	planet_mutex.unlock()
	return true

func remake_planet(game_state_path) -> bool:
	$Annotations.update()
	var data = game_state.universe.get_node_or_null(game_state_path)
	if data:
		var planet: PhysicsBody = data.make_planet(detail_level,0.0)
		if planet:
			var success = erase_planet(game_state_path)
			success = spawn_planet(planet) and success
			success = update_planet_locations() and success
			return success
	return false

func erase_planet(game_state_path: NodePath) -> bool:
	$Annotations.update()
	var full_path = full_game_state_path(game_state_path)
	planet_mutex.lock()
	for planet in $Planets.get_children():
		if full_game_state_path(planet.game_state_path)==full_path:
			planet.queue_free()
			planet_mutex.unlock()
			return true
	planet_mutex.unlock()
	push_error('Could not find a planet to erase at path '+str(game_state_path))
	return false

func deselect():
	selection = NodePath()
	$Annotations.update()

func select_and_center_view(path: NodePath) -> bool:
	if last_position and last_clicked:
		return true
	var data = game_state.universe.get_node_or_null(path)
	var full_path = data.get_path() if data else NodePath()
	selection = full_path
	if not full_path:
		push_error('no object exists at path '+str(path))
		return false
	for child in $Planets.get_children():
		var child_path = full_game_state_path(child.game_state_path)
		if full_path==child_path:
			center_view(child.translation)
			return true
	push_error('cannot find object with path '+str(path))
	return true

func center_view(center=null) -> void:
	if center==null:
		center=$TopCamera.translation
	var size=$TopCamera.size
	$TopCamera.translation = Vector3(center.x, 50, center.z)
	$SpaceBackground.center_view(center.x,center.z,0,size,30)
	# Maintain 30 degree sun angle unless were're very close to the sun.
	$ShipLight.translation.y = min(max_sun_height,max(min_sun_height,
		sqrt(center.x*center.x+center.z*center.z)/sqrt(3)))
	emit_signal('view_center_changed',Vector3(center.x,50,center.z),Vector3(size,0,size))
	$Annotations.update()

func clear():
	planet_mutex.lock()
	for planet in $Planets.get_children():
		planet.queue_free()
	planet_mutex.unlock()

# warning-ignore:shadowed_variable
func set_system(system: simple_tree.SimpleNode) -> bool:
	self.system=system
	clear()
	system.fill_system(self,0.0,0.0,detail_level,false)
	update_space_background()
	return true

func _on_Annotations_draw():
	var draw_color: Color = Color(system.plasma_color)
	draw_color.v = 0.7
	var box_color: Color = Color(draw_color)
	box_color.a = 0.3

	if has_focus:
		var points: PoolVector2Array = PoolVector2Array()
		points.resize(5)
		points[0]=Vector2(1,1)
		points[2]=get_viewport().get_size()-Vector2(1,1)
		points[1]=Vector2(points[0].x,points[2].y)
		points[3]=Vector2(points[2].x,points[0].y)
		points[4]=points[0]
		$Annotations.draw_polyline(points,box_color,1.5,true)
	
	var ascent: float = label_font.get_ascent()
	for planet in $Planets.get_children():
		var data = game_state.universe.get_node_or_null(planet.game_state_path)
		if data:
			var center2d: Vector2 = $TopCamera.unproject_position(planet.translation)
			var full_path = full_game_state_path(planet.game_state_path)
			var pos2d: Vector2 = $TopCamera.unproject_position(
				planet.translation+Vector3(-1.0,0,1.0)*data.size/sqrt(2))
			if full_path==selection:
				$Annotations.draw_arc(center2d,pos2d.distance_to(center2d)+5,
					PI/4,2.25*PI,80,box_color,6.0,true)
			if is_moving and full_path==last_clicked and last_position:
				var last_pos_2d = $TopCamera.unproject_position(last_position)
				$Annotations.draw_circle(last_pos_2d,pos2d.distance_to(center2d),box_color)
				pos2d = $TopCamera.unproject_position(
					last_position+Vector3(-1.0,0,1.0)*data.size/sqrt(2))
			$Annotations.draw_string(label_font,pos2d+Vector2(0,ascent), \
				data.display_name,draw_color)

func view_resized():
	$Annotations.update()
