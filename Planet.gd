extends KinematicBody

var have_sent_texture: bool = false
var SphereTool = preload('res://bin/spheretool.gdns')
var CubePlanetTiles = preload("res://CubePlanetTiles.shader")
var simple_planet_shader = load('SimplePlanet.shader')
var simple_sun_shader = load('SimpleSun.shader')

var combined_aabb setget ,get_combined_aabb
var sphere_material: ShaderMaterial setget ,get_sphere_material
var tile_material: ShaderMaterial setget ,get_tile_material
var sphere: MeshInstance setget ,get_sphere
var view: Viewport setget ,get_viewport
var display_name: String setget set_display_name,get_display_name
var full_display_name: String setget set_full_display_name,get_full_display_name
var has_astral_gate: bool = false
var game_state_path: NodePath = NodePath() setget set_game_state_path,get_game_state_path

func get_display_name() -> String: return display_name
func set_display_name(s: String): display_name=s
func get_full_display_name() -> String: return full_display_name
func set_full_display_name(s: String): full_display_name=s
func get_game_state_path() -> NodePath: return game_state_path
func set_game_state_path(s: NodePath): game_state_path=s

func is_a_system() -> bool: return false
func is_a_ship() -> bool: return false
func is_a_planet() -> bool: return true
func get_has_astral_gate() -> bool: return has_astral_gate
func set_has_astral_gate(b: bool): has_astral_gate = b
func is_a_projectile() -> bool: return false
func is_immobile() -> bool: return true
func get_velocity() -> Vector3: return Vector3(0,0,0)
func threat_at_time(var _t: float) -> float: return 0.0
func position_at_time(var _t: float) -> Vector3: return get_position()
func get_position() -> Vector3: return Vector3(translation[0],0,translation[2])
func get_viewport(): return view
func get_sphere(): return sphere
func get_sphere_material(): return sphere_material
func get_tile_material(): return tile_material
func receive_damage(_f: float): pass

func make_viewport(var nx: float, var ny: float, var shader: ShaderMaterial) -> Viewport:
	var viewport=Viewport.new()
	var rect=ColorRect.new()
	viewport.size=Vector2(nx,ny)
	viewport.render_target_clear_mode=Viewport.CLEAR_MODE_NEVER
	viewport.render_target_update_mode=Viewport.UPDATE_ONCE
	viewport.usage=Viewport.USAGE_2D
	rect.rect_size=Vector2(nx,ny)
	rect.set_material(shader)
	rect.name='Content'
	viewport.add_child(rect)
	return viewport

func ship_can_land(ship: RigidBody) -> bool:
	if ship.linear_velocity.length()>.2:
		return false
	var my_pos = Vector2(translation.z,-translation.x)
	var ship_pos = Vector2(ship.translation.z,-ship.translation.x)
	var my_size = sphere.scale[0]
	return my_size >= (my_pos-ship_pos).length()

func make_sphere(sphere_shader: Shader, subdivisions: int,random_seed: int,
		noise_type=1, texture_size=1024):
	sphere = SphereTool.new()
	sphere.make_cube_sphere('Sphere',Vector3(0,0,0),1,subdivisions)
	var shade=ShaderMaterial.new()
	shade.set_shader(sphere_shader)
	sphere.material_override=shade
	sphere_material = sphere.material_override
	sphere.set_layer_mask_bit(1,true)
	sphere.name='Sphere'
	
	var view_shade=ShaderMaterial.new()
	view_shade.set_shader(CubePlanetTiles)
	view=make_viewport(texture_size,texture_size,view_shade)
	view_shade.set_shader_param('perlin_seed',int(random_seed))
	view_shade.set_shader_param('perlin_type',int(noise_type))
	view.name='View'
	tile_material = view_shade
	
	add_child(view)
	add_child(sphere)

func color_sphere(scaling: Color,addition: Color,scheme: int = 2):
	sphere_material.set_shader_param('color_scaling',Vector3(scaling[0],scaling[1],scaling[2]))
	sphere_material.set_shader_param('color_addition',Vector3(addition[0],addition[1],addition[2]))
	sphere_material.set_shader_param('color_scheme',scheme)

func make_planet(subdivisions: int,random_seed: int,texture_size: int = 2048,
		noise_type: int = 0):
	make_sphere(simple_planet_shader,subdivisions,random_seed,noise_type,texture_size)

func make_sun(subdivisions: int,random_seed: int,texture_size: int = 2048,
		noise_type: int = 1):
	make_sphere(simple_sun_shader,subdivisions,random_seed,noise_type,texture_size)

func place_sphere(sphere_scale: float, sphere_translation: Vector3):
	sphere.scale = Vector3(sphere_scale,sphere_scale,sphere_scale)
	$CollisionShape.shape.radius = sphere_scale*2
	translation = sphere_translation

func get_combined_aabb():
	if combined_aabb==null:
		combined_aabb=sphere.get_transformed_aabb()
		assert(combined_aabb!=null)
	return combined_aabb

func _init():
	collision_mask = 0
	collision_layer = 1<<28

func _process(var _delta) -> void:
	if have_sent_texture: return
	if sphere==null or view==null:
		print('child no longer exists?')
		return # child no longer exists?
	var tex = view.get_texture()
	if tex == null:
		print('tex is null!?')
		return # should never get here in _process()
	sphere.material_override.set_shader_param('precalculated',tex)
	have_sent_texture = true
