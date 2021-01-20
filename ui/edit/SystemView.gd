extends Spatial

export var min_sun_height: float = 50.0
export var max_sun_height: float = 1e5
export var min_camera_size: float = 15
export var max_camera_size: float = 250
export var detail_level: float = 150

var is_paging_up: bool = false
var is_paging_down: bool = false
var ui_scroll: float = 0.0
var is_location_select_down: bool = false
var was_location_select_down: bool = false

var system
var planet_mutex: Mutex = Mutex.new()
var planet2data: Dictionary = {}
var data2planet: Dictionary = {}
var has_focus: bool = false

var selection: NodePath = NodePath()
var last_position = null
var last_screen_position = null
var camera_start = null

signal select_space_object
signal select_nothing
signal view_center_changed

func gain_focus():
	has_focus = true

func lose_focus():
	has_focus = false
	is_paging_up=false
	is_paging_down=false
	is_location_select_down=false
	was_location_select_down=false
	ui_scroll=0
	
	last_position=null
	last_screen_position=null
	camera_start=null

func update_space_background(from=null):
	if from==null:
		from=system
	var result = $SpaceBackground.update_from(from)
	while result is GDScriptFunctionState and result.is_valid():
		result = yield(result,'completed')
	if not result:
		push_error('space background regeneration failed')

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

func handle_selection():
	if Input.is_action_just_pressed('ui_location_select'):
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var space_pos: Vector3 = $TopCamera.project_position(mouse_pos,-10)
		var y500: Vector3 = Vector3(0.0,500.0,0.0)
		var space: PhysicsDirectSpaceState = get_world().direct_space_state
		var result: Dictionary = space.intersect_ray(space_pos-y500,space_pos+y500)
		last_position = space_pos
		last_screen_position = mouse_pos
		camera_start = $TopCamera.translation
		if result:
			var path = result['collider'].game_state_path
			selection = path
			if path:
				emit_signal('select_space_object',path)
		elif selection:
			selection = NodePath()
			emit_signal('select_nothing')
	elif last_position and not selection and Input.is_action_pressed('ui_location_select'):
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var space_pos: Vector3 = $TopCamera.project_position(mouse_pos,-10)
		var start_pos: Vector3 = $TopCamera.project_position(last_screen_position,-10)
		var pos_diff = start_pos-space_pos
		pos_diff.y=0
		if pos_diff.length()>1e-3:
			center_view(camera_start + pos_diff)

func _process(_delta):
	if not has_focus:
		return
	handle_input()
	handle_selection()
	var ui_zoom: int = 0
	ui_zoom = int(is_paging_up)-int(is_paging_down)
	var zoom: float = pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll)
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0
	set_zoom(zoom)

func set_zoom(zoom: float,original: float=-1) -> void:
	var from: float = original if original>1 else $TopCamera.size
	var new_size: float = clamp(zoom*from,min_camera_size,max_camera_size)
	if abs($TopCamera.size-new_size)>1e-5:
		$TopCamera.size = new_size
		center_view()

func get_main_camera() -> Node:
	return $TopCamera

func spawn_planet(planet: Spatial) -> bool:
	planet_mutex.lock()
	$Planets.add_child(planet)
	planet2data[planet.get_path()] = planet.game_state_path
	data2planet[planet.game_state_path] = planet.get_path()
	planet_mutex.unlock()
	return true

func remake_planet(data) -> bool:
	var game_state_path: NodePath = data.get_path()
	if not game_state_path:
		return false
# warning-ignore:return_value_discarded
	erase_planet(game_state_path)
	var planet: PhysicsBody = data.make_planet(detail_level,0.0)
	if not planet:
		return false
	return spawn_planet(planet)

func erase_planet(game_state_path: NodePath) -> bool:
	planet_mutex.lock()
	var node_path = data2planet.get(game_state_path)
# warning-ignore:return_value_discarded
	data2planet.erase(game_state_path)
	if node_path:
# warning-ignore:return_value_discarded
		planet2data.erase(node_path)
		var node = get_node_or_null(node_path)
		if node:
			node.queue_free()
			planet_mutex.unlock()
			return true
	planet_mutex.unlock()
	return false

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

func clear():
	planet_mutex.lock()
	for planet in $Planets.get_children():
		planet.queue_free()
	data2planet.clear()
	planet2data.clear()
	planet_mutex.unlock()

# warning-ignore:shadowed_variable
func set_system(system: simple_tree.SimpleNode):
	self.system=system
	clear()
	system.fill_system(self,0.0,0.0,detail_level,false)
	update_space_background()
