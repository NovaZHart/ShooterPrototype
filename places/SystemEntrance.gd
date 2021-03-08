extends Area

var display_name: String
var has_astral_gate: bool = false
var game_state_path: NodePath = NodePath()
var radius = null

func is_SystemEntrance(): pass # used for type detection; never called
func is_a_system() -> bool: return true
func is_a_ship() -> bool: return false
func is_a_planet() -> bool: return false

func _init():
	collision_mask = 0
	collision_layer = 1<<28

func get_radius():
	if radius==null:
		radius = $CollisionShape.shape.radius
	return radius

func init_system(system_name: String) -> bool:
	var system_node = game_state.systems.get_child_with_name(system_name)
	if system_node:
		display_name = system_node.display_name
		has_astral_gate = not system_node.astral_gate_path().is_empty()
		game_state_path = system_node.get_path()
		translation = system_node.position*20
		translation.y = -20.0
		name = system_name
		return true
	return false

func pack_stats() -> Dictionary:
	return {
		'rotation': Vector3(0,0,0),
		'position': Vector3(translation.x,0,translation.z),
		'transform': transform,
		'name': name,
		'rid': get_rid(),
		'radius': get_radius(),
	}
