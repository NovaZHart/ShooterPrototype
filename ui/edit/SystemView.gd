extends Spatial

const SpaceObjectData = preload('res://places/SpaceObjectData.gd')
const MapAnnotation: PackedScene = preload('res://ui/edit/MapAnnotation.tscn')

export var label_font: Font
export var min_sun_height: float = 50.0
export var max_sun_height: float = 1e5
export var min_camera_size: float = 25
export var max_camera_size: float = 500
export var in_game_max_camera_size: float = 150
export var detail_level: float = 150

const y500: Vector3 = Vector3(0.0,500.0,0.0)
const ANNOTATION_FOR_MAKING_OBJECTS: String = '-is_making-'

var first_process: bool = true
var play_speed: float = 0.0
var planet_time: float = 0.0

var ui_scroll: float = 0.0
var is_location_select_down: bool = false
var was_location_select_down: bool = false

var object_namer: PopupPanel

var system
var planet_mutex: Mutex = Mutex.new()
var has_focus: bool = false
var arrow_move: Vector3 = Vector3()
var selection: NodePath = NodePath() setget set_selection
var last_clicked: NodePath = NodePath()
var is_moving = false
var is_making = null
var is_sliding = false
var last_position = null
var start_position = null
var last_screen_position = null
var camera_start = null

signal select_space_object
signal select_nothing
signal view_center_changed
signal make_new_space_object
signal request_focus

func _ready():
	var annotate_making = MapAnnotation.instance()
	annotate_making.name = ANNOTATION_FOR_MAKING_OBJECTS
	$Annotation3D.add_child(annotate_making)

func full_game_state_path(var path: NodePath):
	var node = game_state.systems.get_node_or_null(path)
	if node:
		return node.get_path()
	else:
		push_error('No game state node exists at path '+str(path))
	return path

func set_selection(what) -> bool:
	if (what==null or not what) and selection:
		selection=NodePath()
		$Annotation2D.update()
		return stop_moving()
	else:
		var full_path = game_state.tree.make_absolute(what)
		if full_path != game_state.tree.make_absolute(selection):
			selection = what
			$Annotation2D.update()
			return stop_moving()
	return true # selection hasn't changed

func gain_focus():
	has_focus = true
	$Annotation2D.update()
	return true

func lose_focus() -> bool:
	has_focus = false
	is_location_select_down=false
	was_location_select_down=false
	ui_scroll=0
	camera_start=null
	$Annotation2D.update()
	return stop_moving()

func stop_moving() -> bool:
	is_moving = false
	is_making = null
	last_position=null
	last_screen_position=null
	is_sliding = false
	start_position=null
	$Annotation2D.update()
	return true

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

func handle_scroll(mouse_in_rect):
	if mouse_in_rect:
		if Input.is_action_just_released("wheel_up"):
			ui_scroll=1.5
		if Input.is_action_just_released("wheel_down"):
			ui_scroll=-1.5
	arrow_move = Vector3(
		float(Input.is_action_pressed('ui_up'))-float(Input.is_action_pressed('ui_down')),
		0.0,
		float(Input.is_action_pressed('ui_right'))-float(Input.is_action_pressed('ui_left')))
	if Input.is_action_just_released('ui_select'):
		play_speed = float(abs(play_speed)<=1e-5)
	var ui_zoom = int(Input.is_action_pressed("ui_page_up")) \
		- int(Input.is_action_pressed("ui_page_down"))
	set_zoom(pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll))
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0

func make_node_to_add():
	if selection:
		var selected_node = game_state.systems.get_node_or_null(selection)
		if selected_node:
			var result = SpaceObjectData.new('unnamed',selected_node.encode())
			result.display_name = result.display_name+' DUP'
			return result
		else:
			push_error('Selected node does not exist. Will make a child of system.')
	return SpaceObjectData.new(system.make_child_name('unnamed'))

func any_actions_present():
	return Input.is_action_just_released('ui_location_select') or \
		Input.is_action_pressed('ui_location_select') or \
		Input.is_action_just_released('ui_location_modify') or \
		Input.is_action_pressed('ui_location_modify') or \
		Input.is_action_just_released('ui_location_slide') or \
		Input.is_action_pressed('ui_location_slide') or \
		Input.is_action_just_released('wheel_down') or \
		Input.is_action_just_released('wheel_up')

func start_moving(space_pos: Vector3,mouse_pos: Vector2):
	last_position = space_pos
	start_position = space_pos
	last_screen_position = mouse_pos
	camera_start = $TopCamera.translation

func handle_mouse_action_start(mouse_pos: Vector2, space_pos: Vector3):
	var view_rect: Rect2 = Rect2(Vector2(),get_viewport().get_size())
	if not view_rect.has_point(mouse_pos):
		return
	if Input.is_action_just_pressed('ui_location_modify'):
		var _discard = stop_moving()
		is_making = make_node_to_add()
		start_moving(space_pos,mouse_pos)
	elif Input.is_action_just_pressed('ui_location_select'):
		var _discard = stop_moving()
		var space: PhysicsDirectSpaceState = get_world().direct_space_state
		var result: Dictionary = space.intersect_ray(space_pos-y500,space_pos+y500)
		last_clicked = NodePath()
		if result:
			last_clicked = full_game_state_path(result['collider'].game_state_path)
		if last_clicked:
			emit_signal('select_space_object',last_clicked)
			start_moving(space_pos,mouse_pos)
		else:
			emit_signal('select_nothing')
	elif Input.is_action_just_pressed('ui_location_slide'):
		is_sliding = true
		start_moving(space_pos,mouse_pos)

func handle_mouse_action_end(_mouse_pos: Vector2, space_pos: Vector3):
	if is_making and not Input.is_action_pressed('ui_location_modify'):
		var parent_path = selection
		var adjust: Dictionary = is_making.orbital_adjustments_to(planet_time,space_pos,
			game_state.systems.get_node_or_null(parent_path))
		is_making.orbit_start=adjust.orbit_start
		is_making.orbit_radius=adjust.orbit_radius
		if not parent_path:
			parent_path = Player.system.get_path()
		emit_signal('make_new_space_object',parent_path,is_making)
		var _discard = stop_moving()
	if is_moving and not Input.is_action_pressed('ui_location_select'):
		var data = game_state.systems.get_node_or_null(last_clicked)
		var adjust: Dictionary = data.orbital_adjustments_to(planet_time,space_pos)
		universe_edits.state.push(universe_edits.SpaceObjectDataChange.new(
			data.get_path(),adjust,false,false,false,true))
		var _discard = stop_moving()
		last_clicked = NodePath()
	if is_sliding and not Input.is_action_pressed('ui_location_slide'):
		is_sliding = false
		if not is_moving and not is_making:
			var _discard = stop_moving()

func handle_mouse_action_active(_mouse_pos: Vector2, space_pos: Vector3):
	if last_position and Input.is_action_pressed('ui_location_slide'):
		var start_pos: Vector3 = $TopCamera.project_position(last_screen_position,-10)
		var pos_diff = start_pos-space_pos
		pos_diff.y=0
		if pos_diff.length()>1e-3:
			center_view(camera_start + pos_diff)
	if last_position and Input.is_action_pressed('ui_location_select'):
		if last_clicked and not is_moving and space_pos.distance_to(start_position)>0.25:
			is_moving = true
			play_speed = 0
	if ( (last_clicked and is_moving) or is_making ) and last_position:
		last_position=space_pos
		$Annotation2D.update()
		update_Annotation3D()

func update_planet_locations():
	var success: bool = true
	for planet in $Planets.get_children():
		var data = game_state.systems.get_node_or_null(planet.game_state_path)
		if data:
			planet.translation = data.planet_translation(planet_time)
			planet.rotation = data.planet_rotation(planet_time)
		else:
			push_error('Planet data location ('+str(planet.game_state_path)+') does not exist.')
			success=false
	$Annotation2D.update()
	update_Annotation3D()
	return success

func _process(delta):
	if first_process:
		first_process=false
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var space_pos: Vector3 = $TopCamera.project_position(mouse_pos,-10)
	var view_rect: Rect2 = Rect2(Vector2(),get_viewport().get_size())
	if any_actions_present():
		if view_rect.has_point(mouse_pos):
			emit_signal('request_focus')
	if has_focus:
		handle_mouse_action_start(mouse_pos,space_pos)
		handle_mouse_action_end(mouse_pos,space_pos)
		handle_mouse_action_active(mouse_pos,space_pos)
		if selection and Input.is_action_just_released('ui_delete'):
			var node = game_state.systems.get_node_or_null(selection)
			universe_edits.state.push(universe_edits.RemoveSpaceObject.new(node,true))
			selection = NodePath()
		if arrow_move.length()>1e-5:
			center_view($TopCamera.translation+arrow_move*delta*$TopCamera.size)
		handle_scroll(view_rect.has_point(mouse_pos))
	if abs(play_speed)>1e-5:
		planet_time += delta*0.5
		update_planet_locations()

func set_zoom(zoom: float,original: float=-1) -> void:
	var from: float = original if original>1 else $TopCamera.size
	var new_size: float = clamp(zoom*from,min_camera_size,max_camera_size)
	if abs($TopCamera.size-new_size)>1e-5:
		$TopCamera.size = new_size
		center_view()
	$Annotation2D.update()
	update_Annotation3D()

func spawn_planet(planet: Spatial) -> bool:
	planet_mutex.lock()
	$Planets.add_child(planet)
	var planet_data = game_state.systems.get_node(planet.game_state_path)
	var parent_data = planet_data.get_parent() if planet_data else null
	if parent_data:
		var ann3 = MapAnnotation.instance()
		ann3.object_path = planet_data.get_path()
		ann3.name = planet.name
		var old = $Annotation3D.get_node_or_null(ann3.name)
		if old:
			$Annotation3D.remove_child(old)
			old.queue_free()
		$Annotation3D.add_child(ann3)
		call_deferred('update_Annotation3D')
	planet_mutex.unlock()
	$Annotation2D.update()
	return true

func remake_planet(game_state_path) -> bool:
	$Annotation2D.update()
	var data = game_state.systems.get_node_or_null(game_state_path)
	if data:
		var planet: PhysicsBody = data.make_planet(detail_level,0.0)
		if planet:
			var success = erase_planet(game_state_path)
			success = spawn_planet(planet) and success
			success = update_planet_locations() and success
			return success
	return false

func erase_planet(game_state_path: NodePath) -> bool:
	$Annotation2D.update()
	var full_path = full_game_state_path(game_state_path)
	planet_mutex.lock()
	for planet in $Planets.get_children():
		if full_game_state_path(planet.game_state_path)==full_path:
			planet.queue_free()
			planet_mutex.unlock()
			return true
	planet_mutex.unlock()
	call_deferred('update_Annotation3D')
	push_error('Could not find a planet to erase at path '+str(game_state_path))
	return false

func deselect():
	var _discard = stop_moving()
	selection = NodePath()
	$Annotation2D.update()

func change_selection_to(path: NodePath,center_view: bool) -> bool:
	var data = game_state.systems.get_node_or_null(path)
	var full_path = data.get_path() if data else NodePath()
	selection = full_path
	if not full_path:
		push_error('no object exists at path '+str(path))
		return false
	if not center_view or is_moving or is_sliding or is_making:
		return true
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
	$Annotation2D.update()

func clear():
	planet_mutex.lock()
	for planet in $Planets.get_children():
		planet.queue_free()
		$Planets.remove_child(planet)
	for annotation in $Annotation3D.get_children():
		if annotation.name != ANNOTATION_FOR_MAKING_OBJECTS:
			annotation.queue_free()
	planet_mutex.unlock()

# warning-ignore:shadowed_variable
func set_system(system: simple_tree.SimpleNode) -> bool:
	self.system=system
	clear()
	var _discard = stop_moving()
	system.fill_system(self,0.0,0.0,detail_level,false)
	update_space_background()
	return true

func _on_Annotation2D_draw():
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
		$Annotation2D.draw_polyline(points,box_color,1.5,true)
	
	var ascent: float = label_font.get_ascent()
	
	if is_making and last_position:
		var center2d: Vector2 = $TopCamera.unproject_position(last_position)
		var pos2d: Vector2 = $TopCamera.unproject_position(
			last_position+Vector3(-1.0,0,1.0)*is_making.size/sqrt(2))
		$Annotation2D.draw_circle(center2d,pos2d.distance_to(center2d),box_color)
		pos2d = $TopCamera.unproject_position(
			last_position+Vector3(-1.0,0,1.0)*is_making.size/sqrt(2))
		$Annotation2D.draw_string(label_font,pos2d+Vector2(0,ascent), \
			is_making.display_name,draw_color)
	
	for planet in $Planets.get_children():
		var data = game_state.systems.get_node_or_null(planet.game_state_path)
		if data:
			var center2d: Vector2 = $TopCamera.unproject_position(planet.translation)
			var full_path = full_game_state_path(planet.game_state_path)
			var pos2d: Vector2 = $TopCamera.unproject_position(
				planet.translation+Vector3(-1.0,0,1.0)*data.size/sqrt(2))
			if full_path==selection:
				$Annotation2D.draw_arc(center2d,pos2d.distance_to(center2d)+5,
					PI/4,2.25*PI,80,box_color,6.0,true)
			if is_moving and full_path==last_clicked and last_position:
				var last_pos_2d = $TopCamera.unproject_position(last_position)
				$Annotation2D.draw_circle(last_pos_2d,pos2d.distance_to(center2d),box_color)
				pos2d = $TopCamera.unproject_position(
					last_position+Vector3(-1.0,0,1.0)*data.size/sqrt(2))
			$Annotation2D.draw_string(label_font,pos2d+Vector2(0,ascent), \
				data.display_name,draw_color)

func update_Annotation3D():
	var new_u_scale = clamp($TopCamera.size/max_camera_size,0.1,1.0)
	var draw_color: Color = Color(system.plasma_color)
	
	planet_mutex.lock()
	
	var deleteme = []
	for ann3 in $Annotation3D.get_children():
		if ann3.object_path:
			var new_position = null
			if is_moving and last_clicked==ann3.object_path:
				new_position=last_position
			if not ann3.update_from_path(new_u_scale,draw_color,planet_time,new_position):
				deleteme.append(ann3)
		elif is_making and last_position:
			var center = Vector3(0,0,0)
			if selection:
				var selected_node = game_state.systems.get_node_or_null(selection)
				if selected_node and selected_node.has_method('is_SpaceObjectData'):
					center = selected_node.planet_translation(planet_time)
			ann3.update_from_spec(new_u_scale,draw_color,last_position,center)
		else:
			ann3.visible=false
	for ann3 in deleteme:
		$Annotation3D.remove_child(ann3)
		ann3.queue_free()
	
	planet_mutex.unlock()

func view_resized():
	$Annotation2D.update()
	call_deferred('update_Annotation3D')
