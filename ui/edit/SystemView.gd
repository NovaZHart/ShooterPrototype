extends Spatial

export var min_sun_height: float = 50.0
export var max_sun_height: float = 1e5
export var min_camera_size: float = 25
export var max_camera_size: float = 150
export var detail_level: float = 150

var system
var planet_mutex: Mutex = Mutex.new()
var planet2data: Dictionary = {}
var data2planet: Dictionary = {}

signal view_center_changed

func update_space_background(from=null):
	if from==null:
		from=system
	var result = $SpaceBackground.update_from(from)
	while result is GDScriptFunctionState and result.is_valid():
		result = yield(result,'completed')
	if not result:
		push_error('space background regeneration failed')

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

func center_view(center=Vector3()) -> void:
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
