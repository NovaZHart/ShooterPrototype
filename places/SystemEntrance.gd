extends Area

export var exit_shader: Shader = preload('res://shaders/HyperspaceExit.shader')
export var thickness_texture: Texture = preload('res://textures/cell-noise.jpg')
export var detail_texture: Texture = preload('res://textures/blue-squiggles.jpeg')
export var exit_color_multiplier: Vector3 = Vector3(1.0,1.7,1.0)

var display_name: String
var has_astral_gate: bool = false
var game_state_path: NodePath = NodePath()
var radius = null

func is_SystemEntrance(): pass # used for type detection; never called
func is_a_system() -> bool: return true
func is_a_ship() -> bool: return false
func is_a_planet() -> bool: return false

func _ready():
	var r: float = get_radius()
	var mesh: ArrayMesh = utils.native.make_circle(r*1.4,120,true);
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader=exit_shader
	mat.set_shader_param('thickness_texture',thickness_texture)
	mat.set_shader_param('detail_texture',detail_texture)
	mat.set_shader_param('exit_color_multiplier',exit_color_multiplier)
	mat.set_shader_param('perturbation',r*0.3)
	if game_state_path:
# warning-ignore:integer_division
		mat.set_shader_param('ship_id',(hash(game_state_path)&65535)/65536*PI)
	else:
# warning-ignore:integer_division
		mat.set_shader_param('ship_id',(hash(display_name)&65535)/65536*PI)
	mesh.surface_set_material(0,mat)
	$MeshInstance.mesh = mesh

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
