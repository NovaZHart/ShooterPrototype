extends KinematicBody

const allowed_subdivisions = [ 6, 12, 24, 48 ]# , 96, 192 ]
const allowed_texture_sizes = [ 128, 256, 512, 1024, 2048 ]

var have_sent_texture: bool = false
var SphereTool = preload('res://bin/spheretool.gdns')
#var CubePlanetTilesV2 = preload("res://shaders/CubePlanetTilesV2.shader")
var CubePlanetTiles = preload("res://shaders/CubePlanetTilesV3.shader")
var ContinentTiles = preload("res://shaders/ContinentGenerator.shader")
var InfernoTiles = preload("res://shaders/InfernoGenerator.shader")
var IceballTiles = preload("res://shaders/IceballGenerator.shader")
var RockyTiles = preload("res://shaders/RockyGenerator.shader")
var CraterTiles = preload("res://shaders/CraterGenerator.shader")
var StripeGasTiles = preload("res://shaders/StripeGasGenerator.shader")
var simple_planet_shader = preload('res://shaders/SimplePlanetV2.shader')
var rocky_planet_shader = preload('res://shaders/RockyPlanet.shader')
var inferno_planet_shader = preload('res://shaders/InfernoPlanet.shader')
var simple_sun_shader = preload('res://shaders/SimpleSunV2.shader')

var default_colors = preload('res://textures/continents-terran.jpg')
const GasGiantRingShader: Shader = preload('res://shaders/GasGiantRing.shader')

const crater_count: int = 20
const crater_min_size: float = 15*PI/180
const crater_max_size: float = 25*PI/180
var crater_list_image: ImageTexture
var hash_cube_8: ImageTexture
var hash_cube_16: ImageTexture
var hash_cube_16b: ImageTexture

var commodities: Commodities.ManyProducts = Commodities.ManyProducts.new()
var u_size: int
var v_size: int
var tick: int =0
var combined_aabb setget ,get_combined_aabb
var sphere_material: ShaderMaterial setget ,get_sphere_material
var tile_material: ShaderMaterial setget ,get_tile_material
var sphere: MeshInstance setget ,get_sphere
var view: Viewport setget ,get_viewport
var display_name: String setget set_display_name,get_display_name
var full_display_name: String setget set_full_display_name,get_full_display_name
var has_astral_gate: bool = false
var game_state_path: NodePath = NodePath() setget set_game_state_path,get_game_state_path
var view_shade: ShaderMaterial
var have_valid_texture: bool = false

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
func get_radius() -> float: return sphere.scale[0]

func save_tile_image(to: String):
	var v: Viewport = get_node_or_null("View")
	assert(v)
	v.render_target_update_mode = Viewport.UPDATE_ALWAYS
	var vtex: ViewportTexture = v.get_texture()
	yield(get_tree(),'idle_frame')
	yield(get_tree(),'idle_frame')
	var img: Image = vtex.get_data()
	img.save_png(to)

func update_ring_shading():
	var rings: MeshInstance = sphere.get_node_or_null('rings')
	if rings:
		var material: ShaderMaterial = rings.mesh.surface_get_material(0)
		if material:
			var dp_vec: Vector3 = Vector3(translation.x,0,translation.z)
			var dp2: float = dp_vec.length_squared()
			var dp: float = sqrt(dp2)
			var rp: float = sphere.scale.x
			if dp>rp:
				var rp_inner: float = max(rp-0.5,0.8*rp)
				material.set_shader_param('planet_world_norm',dp_vec/dp)
				material.set_shader_param('shadow_start',dp-rp/2)
				material.set_shader_param('shadow_cos_inner',sqrt(1-rp_inner*rp_inner/dp2))
				material.set_shader_param('shadow_cos_outer',sqrt(1-rp*rp/dp2))

func make_rings(planet_radius: float,inner_radius: float,thickness: float,random_seed: int):
	inner_radius /= planet_radius
	thickness /= planet_radius
	var middle_radius: float = inner_radius+thickness/2
	var outer_radius: float = inner_radius+thickness
	var steps: float = clamp(2*PI*outer_radius/0.1,60,1440)
	var mesh: ArrayMesh = utils.native.make_annulus_mesh(middle_radius,thickness,steps)
	var material = ShaderMaterial.new()
	material.shader = GasGiantRingShader
	material.set_shader_param('color',Color(0.75,0.75,0.7,0.6))
	material.set_shader_param('r_mid',float(middle_radius))
	material.set_shader_param('thickness',float(thickness))
	material.set_shader_param('scale',1.0)
	var ring_noise: Image = utils.native.generate_planet_ring_noise(9,random_seed,0.7)
	assert(ring_noise)
	var texture = ImageTexture.new()
	texture.create_from_image(ring_noise)
	material.set_shader_param('ring_noise',texture)
	mesh.surface_set_material(0,material)
	var instance: MeshInstance = MeshInstance.new()
	instance.mesh = mesh
	instance.name = 'rings'
	sphere.add_child(instance)

func make_viewport(var nx: float, var ny: float, var shader: ShaderMaterial) -> Viewport:
# warning-ignore:shadowed_variable
	var view=Viewport.new()
	var rect=ColorRect.new()
	view.size=Vector2(nx,ny)
	#view.render_target_clear_mode=Viewport.CLEAR_MODE_NEVER
	view.render_target_update_mode=Viewport.UPDATE_ONCE
	view.keep_3d_linear=true
	#view.disable_3d=true
	view.usage=Viewport.USAGE_3D_NO_EFFECTS
	rect.rect_size=Vector2(nx,ny)
	rect.color=Color(0,0,0,0)
	rect.set_material(shader)
	rect.name='Content'
	view.own_world=true
	view.hdr=true
	view.add_child(rect)
	return view

func ship_can_land(ship: RigidBody) -> bool:
	if ship.linear_velocity.length()>.2:
		return false
	var my_pos = Vector2(translation.z,-translation.x)
	var ship_pos = Vector2(ship.translation.z,-ship.translation.x)
	var my_size = sphere.scale[0]
	return my_size >= (my_pos-ship_pos).length()

func choose_subdivisions(wanted) -> int:
	for allowed in allowed_subdivisions:
		if wanted<=allowed:
			return allowed
	return allowed_subdivisions[len(allowed_subdivisions)-1]

func choose_texture_size(x,y) -> int:
	for allowed in allowed_texture_sizes:
		if x<=allowed and y<=allowed:
			return allowed
	return allowed_texture_sizes[len(allowed_texture_sizes)-1]

func get_crater_list_image(var random_seed: int) -> ImageTexture:
	if not crater_list_image:
		var c: Image = utils.native.generate_impact_craters(crater_max_size,crater_min_size,crater_count,random_seed)
		var texture = ImageTexture.new()
		texture.create_from_image(c)
		crater_list_image=texture
	return crater_list_image

func get_hash_cube_8(var random_seed: int) -> ImageTexture:
	if not hash_cube_8:
		var hash_cube_image: Image = utils.native.make_hash_cube8(int(random_seed))
		var texture = ImageTexture.new()
		texture.create_from_image(hash_cube_image)
		hash_cube_8 = texture
	return hash_cube_8

func get_hash_cube_16(var random_seed: int) -> ImageTexture:
	if not hash_cube_16:
		var hash_cube_image: Image = utils.native.make_hash_cube16(int(random_seed))
		var texture = ImageTexture.new()
		texture.create_from_image(hash_cube_image)
		hash_cube_16 = texture
	return hash_cube_16

func get_hash_cube_16b(var random_seed: int) -> ImageTexture:
	if not hash_cube_16b:
		var hash_cube_image: Image = utils.native.make_hash_cube16(int(random_seed+1))
		var texture = ImageTexture.new()
		texture.create_from_image(hash_cube_image)
		hash_cube_16b = texture
	return hash_cube_16b
	
func make_sphere(object_type: String, subdivisions: int,random_seed: int,
		texture_size=1024, shader_type: String = "old",
		colors = null, noise_type=1, height_map_scale: float = 0.35):

	var xyz: ImageTexture
	if not sphere:
# warning-ignore:narrowing_conversion
		var subs: int = clamp(subdivisions/4.0,6,28) # choose_subdivisions(subdivisions)
		u_size = choose_texture_size(texture_size,texture_size)
# warning-ignore:integer_division
		v_size = u_size/2
	
		sphere = SphereTool.new()
		xyz = game_state.get_sphere_xyz()
		sphere.make_cube_sphere_v2('Sphere',Vector3(0,0,0),1,subs)
		var shade=ShaderMaterial.new()
		if shader_type=='inferno':
			shade.set_shader(inferno_planet_shader)
		elif shader_type=='rocky' or shader_type=='craters' or shader_type=='iceball':
			shade.set_shader(rocky_planet_shader)
		elif object_type=='sun':
			shade.set_shader(simple_sun_shader)
		else:
			shade.set_shader(simple_planet_shader)
		sphere.material_override=shade
		sphere.cast_shadow=false
		sphere_material = sphere.material_override
		if shader_type=='rocky' or shader_type=='craters' or shader_type=='iceball':
			if not colors or not colors is Texture:
				push_warning('Using default continent color texture')
				colors = default_colors
			colors.flags=0
			sphere_material.set_shader_param('colors',colors)
			sphere_material.set_shader_param('xyz',xyz)
			sphere_material.set_shader_param('height_map_scale',height_map_scale)
	#	sphere_material.set_shader_param('hash_cube',hash_cube)
		sphere.set_layer_mask(4)
		sphere.name='Sphere'
		add_child(sphere)
	else:
		xyz = game_state.get_sphere_xyz()
	
	view_shade=ShaderMaterial.new()
	if shader_type=='continents':
		print("CONTINENTS")
		view_shade.set_shader(ContinentTiles)
		view_shade.set_shader_param('temperature_cube8',get_hash_cube_8(random_seed+2))
		view_shade.set_shader_param('altitude_cube16',get_hash_cube_16(random_seed))
		view_shade.set_shader_param('cloud_cube16',get_hash_cube_16b(random_seed+1))
		if not colors or not colors is Texture:
			push_warning('Using default continent color texture')
			colors = default_colors
		colors.flags=0
		view_shade.set_shader_param('colors',colors)
	elif shader_type=='inferno':
		print('INFERNO')
		view_shade.set_shader(InfernoTiles)
		view_shade.set_shader_param('texture_cube16',get_hash_cube_16(random_seed))
		if not colors or not colors is Texture:
			push_warning('Using default continent color texture')
			colors = default_colors
		colors.flags=0
		view_shade.set_shader_param('colors',colors)
	elif shader_type=='rocky':
		print('ROCKY')
		view_shade.set_shader(RockyTiles)
		view_shade.set_shader_param('texture_cube16',get_hash_cube_16(random_seed))
		view_shade.set_shader_param('coloring_cube16',get_hash_cube_16b(random_seed+1))
	elif shader_type=='iceball':
		print('ICEBALL')
		view_shade.set_shader(IceballTiles)
		view_shade.set_shader_param('crack_cube8',get_hash_cube_8(random_seed))
		view_shade.set_shader_param('color_cube16',get_hash_cube_16(random_seed+2))
		view_shade.set_shader_param('rough_cube16',get_hash_cube_16b(random_seed+1))
	elif shader_type=='craters':
		print('CRATERS')
		view_shade.set_shader(CraterTiles)
		view_shade.set_shader_param('texture_cube16',get_hash_cube_16(random_seed))
		view_shade.set_shader_param('coloring_cube16',get_hash_cube_16b(random_seed+1))
		view_shade.set_shader_param('crater_data',get_crater_list_image(random_seed+2))
		view_shade.set_shader_param('crater_count',crater_count)
	elif shader_type=='stripe_gas':
		print('STRIPE GAS')
		view_shade.set_shader(StripeGasTiles)
		view_shade.set_shader_param('stripe_cube8',get_hash_cube_8(random_seed))
		view_shade.set_shader_param('texture_cube16',get_hash_cube_16(random_seed))
		if not colors or not colors is Texture:
			push_warning('Using default continent color texture')
			colors = default_colors
		colors.flags=0
		view_shade.set_shader_param('colors',colors)
	else: # shader_type=='old'
		print('old shader')
		view_shade.set_shader(CubePlanetTiles)
		view_shade.set_shader_param('perlin_type',int(noise_type))
		view_shade.set_shader_param('hash_cube',get_hash_cube_16(random_seed))

	self.view=make_viewport(u_size,v_size,view_shade)
	view_shade.set_shader_param('xyz',xyz)
	self.view.name='View'
	tile_material = view_shade
	
	add_child(self.view)
	assert(self.view)
	tick=0
	set_process(true)

func color_sphere(scaling: Color,addition: Color,scheme: int = 2):
	view_shade.set_shader_param('color_scaling',Vector3(scaling[0],scaling[1],scaling[2]))
	view_shade.set_shader_param('color_addition',Vector3(addition[0],addition[1],addition[2]))
	view_shade.set_shader_param('color_scheme',scheme)

func make_planet(subdivisions: int,random_seed: int,texture_size: int = 2048,
		shader_type='old', colors=null, height_map_scale: float = 0.35, noise_type: int = 0):
	make_sphere('planet',subdivisions,random_seed,texture_size,shader_type,colors,noise_type,height_map_scale)

func make_sun(subdivisions: int,random_seed: int,texture_size: int = 2048,
		shader_type='old', colors=null, height_map_scale: float = 0.35, noise_type: int = 1):
	make_sphere('sun',subdivisions,random_seed,texture_size,shader_type,colors,noise_type,height_map_scale)

func place_sphere(sphere_scale: float, sphere_translation: Vector3,
		sphere_basis: Basis = Basis()):
	transform = Transform(sphere_basis,sphere_translation)
	sphere.scale = Vector3(sphere_scale,sphere_scale,sphere_scale)
	$CollisionShape.scale = sphere.scale

func get_combined_aabb():
	if combined_aabb==null:
		combined_aabb=sphere.get_transformed_aabb()
	return combined_aabb

func _init():
	collision_mask = 0
	collision_layer = combat_engine.PLANET_COLLISION_MASK
	pause_mode = PAUSE_MODE_PROCESS

func copy_data_to_image(data) -> ImageTexture:
	var copy = Image.new()
	copy.copy_from(data)
	var newtex = ImageTexture.new()
	newtex.create_from_image(copy)
	return newtex

func get_tex_data(tex):
	return tex.get_data()

func get_planet_texture():
	var tex = view.get_texture()
	tex.flags = Texture.FLAGS_DEFAULT
	return tex

func remove_view():
	remove_child(view)
	view.queue_free()

func _process(var _delta) -> void:
	tick += 1
	
	if sphere==null or view==null:
		push_error("Planet's child no longer exists!?")
		return # child no longer exists?

	var tex = get_planet_texture()
	sphere.material_override.set_shader_param('precalculated',tex)
	have_valid_texture = true
	
	#view=null
	#view_shade=null
	
	set_process(false)

func pack_stats() -> Dictionary:
	var game_data = game_state.systems.get_node_or_null(game_state_path)
	var scene_tree_path = get_path()
	assert(scene_tree_path)
	return {
		'rotation': Vector3(0,0,0),
		'position': Vector3(translation.x,0,translation.z),
		'transform': transform,
		'name': name,
		'rid': get_rid(),
		'radius': sphere.scale[0],
		'population': (game_data.total_population() if game_data else 0.0),
		'industry': (game_data.total_industry() if game_data else 0.0),
		'scene_tree_path': scene_tree_path,
	}
