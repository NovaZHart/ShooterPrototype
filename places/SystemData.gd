extends simple_tree.SimpleNode

var display_name: String = "Unnamed" setget ,get_display_name
var counter: int = 0

var links: Dictionary
var position: Vector3 setget set_position
var plasma_seed: int
var plasma_color: Color
var starfield_seed: int
var show_on_map: bool
var system_fuel_recharge: float
var center_fuel_recharge: float
var locality_adjustments: Dictionary = {}

var asteroid_fields: Array = []
var oort_clouds: Array = [
	{ 'thickness':4000, 'inner_radius':2000, 'asteroids':[ 'comets' ] }
]

var SphereTool = preload('res://bin/spheretool.gdns')
var SimpleAsteroidShader = preload('res://shaders/SimpleAsteroidShader.shader')
var SimpleCometShader = preload('res://shaders/SimpleCometShader.shader')

var AsteroidTexture1 = preload('res://textures/small-asteroid-continents-bronze.jpg')
var AsteroidTexture2 = preload('res://textures/small-asteroid-rocky-orange.jpg')
var AsteroidTexture3 = preload('res://textures/small-asteroid-red-veins.jpg')
var AsteroidTexture4 = preload('res://textures/small-asteroid-noisy-bronze.jpg')
var AsteroidTexture5 = preload('res://textures/small-asteroid-wobbly-patterns.jpg')

var CometTexture1 = preload('res://textures/comet-smudged-blue-pearl.jpg')
var CometTexture2 = preload('res://textures/comet-dark-blue-smooth.jpg')
var CometTexture3 = preload('res://textures/comet-light-blue-shades.jpg')
var CometTexture4 = preload('res://textures/comet-lavender-grey.jpg')
var CometTexture5 = preload('res://textures/comet-dark-spotty.jpg')
#var CometTexture5 = preload('res://textures/comet-rock-lavender.jpg')

var faction_goals: Array
var active_factions: Dictionary

const default_active_factions: Dictionary = {
	'police': { 'starting_money':2e5, 'income_per_second':2e5, 'fleet_type_weights':{
		'large_police':1.0, 'small_police':1.0 }
	},
	'raiders': { 'starting_money':2e5, 'income_per_second':2e5, 'fleet_type_weights':{
		'large_raid':1.3, 'small_raid':1.0 },
	},
	'civilians': { 'starting_money':1e6, 'income_per_second':2e6, 'fleet_type_weights':{
		'small_merchant':30.0, 'large_merchant':30.0 }
	},
}

const default_faction_goals: Array = [
	{ 'faction_name':'police','target_faction':'raiders','action':'patrol' },
	{ 'faction_name':'civilians','target_faction':'raiders','action':'arriving_merchant','weight':15 },
	{ 'faction_name':'civilians','target_faction':'raiders','action':'departing_merchant','weight':5 },
	{ 'faction_name':'raiders','target_faction':'civilians','action':'raid' },
]

var rng

func set_position(v: Vector3):
	position=Vector3(v.x,0.0,v.z)

func is_a_system() -> bool: return true
func is_a_planet() -> bool: return false

func is_SystemData(): pass # never called; must only exist

func get_system(): # -> SystemData or null
	return self

func full_display_name():
	return display_name

func get_SystemData_anscestor(): # -> SimpleNode or null
	return self

func encode() -> Dictionary:
	var result = {
		'display_name':display_name,
		'position':position,
		'links':links,
		'plasma_seed':plasma_seed,
		'starfield_seed':starfield_seed,
		'plasma_color':plasma_color,
		'show_on_map':show_on_map,
		'system_fuel_recharge':system_fuel_recharge,
		'center_fuel_recharge':center_fuel_recharge,
		'locality_adjustments':locality_adjustments.duplicate(true),
		'faction_goals':faction_goals.duplicate(true),
		'active_factions':active_factions.duplicate(true),
		'asteroid_fields':asteroid_fields.duplicate(true),
	}
	return result

func getdict(content: Dictionary, key, default):
	var result = content.get(key,null)
	return default if result==null else result

func decode(content: Dictionary):
	display_name = content.get('display_name','(unnamned)')
	links = getdict(content,'links',{})
	plasma_seed = getdict(content,'plasma_seed',320918)
	starfield_seed = getdict(content,'starfield_seed',987686)
	plasma_color = getdict(content,'plasma_color',Color(0.07,0.07,.18,1.0))
	show_on_map = getdict(content,'show_on_map',true)
	system_fuel_recharge = getdict(content,'system_fuel_recharge',0.5)
	center_fuel_recharge = getdict(content,'center_fuel_recharge',1.5)
	locality_adjustments = getdict(content,'locality_adjustments',{})
	faction_goals = getdict(content,'faction_goals',default_faction_goals)
	active_factions = getdict(content,'active_factions',default_active_factions)
	asteroid_fields = getdict(content,'asteroid_fields',[])
	set_position(getdict(content,'position',Vector3()))

func _init(the_name,content: Dictionary):
	decode(content)
	if the_name:
		set_name(the_name)
	rng = RandomNumberGenerator.new()
	rng.randomize()
	var objects = content.get('objects',{})
	if objects and objects is Dictionary:
		for key in objects:
			var object = objects[key]
			if object and object is simple_tree.SimpleNode:
				var _discard = add_child(object,key)

func increment_counter() -> int:
	counter+=1
	return counter

func get_display_name() -> String:
	return display_name

func num_planets():
	return get_child_count()

func price_ship_parts(_result):
	pass # FIXME: Maybe implement locality adjustments for parts?

func price_products(result: Commodities.Products):
	result.randomize_costs(hash(get_path()),game_state.epoch_time/365.25)
	if locality_adjustments:
		result.apply_multiplier_list(locality_adjustments)

func astral_gate_path() -> NodePath:
	for child in get_children():
		if child.has_method('astral_gate_path'):
			var p: NodePath = child.astral_gate_path()
			if not p.is_empty():
				return p
	return NodePath()

func process_space(_system,_delta,_immediate_entry: bool = false) -> Array:
	return []

func fill_system(var system,planet_time: float,ship_time: float,detail: float,ships=true):
	system.raise_sun = not show_on_map
	for child in get_children():
		if child.is_a_planet():
			child.fill_system(system,planet_time,ship_time,detail,ships)
	for field in asteroid_fields:
		system.spawn_asteroid_field(generate_asteroid_field(
			field.get("inner_radius",500), field.get("thickness",100),
			field.get('asteroids',['simple_metals']),
			field.get('spacing_multiplier',1),
			field.get('scale_multiplier',1),
			field.get('iterations',7)))
	for field in oort_clouds:
		system.spawn_asteroid_field(generate_asteroid_field(
			field.get("inner_radius",500), field.get("thickness",100),
			field.get('asteroids',['simple_metals']),
			field.get('spacing_multiplier',20),
			field.get('scale_multiplier',3),
			field.get('iterations',10)))
	return []

func generate_asteroid_field(inner_radius: float,thickness: float,asteroids: Array,spacing_multiplier: float,scale_multiplier: float,iterations: int) -> Dictionary:
#	var spacing_multiplier = 1
#	var scale_multiplier = 1
#	var iterations = 7
#	if oort_cloud:
#		spacing_multiplier = 20
#		scale_multiplier = 3
#		iterations = 10
	var result = {
		"asteroids": [],
		"layers": generate_asteroid_layers(inner_radius,thickness,spacing_multiplier,scale_multiplier,iterations),
		"salvage": {}
	}

	for ast in asteroids:
		var astnode = game_state.asteroids.get_child_with_name(ast)
		assert(astnode)
		if not astnode:
			push_warning('Ignoring invalid asteroid palette name "'+str(ast)+'"')
			continue
		var a_s = astnode.get_palettes(game_state.flotsam)
		assert(a_s is Array)
		assert(a_s[0] is Array)
		assert(a_s[1] is Dictionary)
		result['asteroids'].append_array(a_s[0])
		result['salvage'] = utils.update_dict(result['salvage'],a_s[1])
	
	if not result['asteroids'] or not result['salvage']:
		push_warning('Incomplete asteroid field palette data; adding defaults.')
		result['asteroids'].append_array(generate_asteroid_palette())
		result['salvage'] = utils.update_dict(result['salvage'],generate_salvage_palette())
	
	var default_asteroid_meshes: Dictionary = {}
	
	for ast in result['asteroids']:
		if not ast[1].get('mesh',null):
			var mesh_generator = ast[1].get('mesh_generator','asteroid')
			var mesh = default_asteroid_meshes.get(mesh_generator,null)
			if mesh==null:
				mesh=generate_default_asteroid_mesh(scale_multiplier,mesh_generator)
				default_asteroid_meshes[mesh_generator]=mesh
			ast[1]['mesh'] = mesh
		assert(ast[1]['mesh'])
	
	var default_salvage_mesh: Mesh
	
	for salname in result['salvage']:
		if not result['salvage'][salname].get('flotsam_mesh',null):
			if not default_salvage_mesh:
				default_salvage_mesh = preload('res://equipment/engines/IonEngine4x4.mesh')
			result['salvage'][salname]['flotsam_mesh'] = default_salvage_mesh
	
	return result

func generate_salvage_palette() -> Dictionary:
	var scrap_metal = game_state.universe.flotsam.get_child_with_name("scrap_metal")
	var salvage_palette: Dictionary = {}
	if scrap_metal:
		salvage_palette["scrap_metal"] = scrap_metal.encode_for_native(
			preload('res://equipment/engines/IonEngine4x4.mesh'),0,0,null,false)
	return salvage_palette

func generate_default_asteroid_mesh(scale_multiplier: float = 1, generator: String = 'asteroid') -> Mesh:
	var mesh: ArrayMesh = utils.native.make_cube_sphere_v2(1,max(5,ceil(3+2*scale_multiplier)))
	var shade=ShaderMaterial.new()
	if generator=='comet':
		shade.set_shader(SimpleCometShader)
		shade.set_shader_param('tex1',CometTexture1)
		shade.set_shader_param('tex2',CometTexture2)
		shade.set_shader_param('tex3',CometTexture3)
		shade.set_shader_param('tex4',CometTexture4)
		shade.set_shader_param('tex5',CometTexture5)
	else: # asteroid
		shade.set_shader(SimpleAsteroidShader)
		shade.set_shader_param('tex1',AsteroidTexture1)
		shade.set_shader_param('tex2',AsteroidTexture2)
		shade.set_shader_param('tex3',AsteroidTexture3)
		shade.set_shader_param('tex4',AsteroidTexture4)
		shade.set_shader_param('tex5',AsteroidTexture5)

	for i in range(mesh.get_surface_count()):
		mesh.surface_set_material(i,shade)
	return mesh

func generate_asteroid_palette() -> Array:
	var mesh: Mesh = generate_default_asteroid_mesh()
	return [ [ 1.0, {
		"mesh": mesh,
		"color_data": Color(0.1,0.3,0.5,0.7),
		"salvage": "scrap_metal",
		"max_structure": 2000,
		} ] ]

func generate_asteroid_layers(inner_radius: float,thickness: float,
		spacing_multiplier: float,scale_multiplier: float,iterations: int) -> Array:
	assert(iterations>2)
	var result: Array = []
	var tfac = (inner_radius+0.75*thickness)/(inner_radius+0.25*thickness)
	for i in range(iterations):
		var f = i/(iterations+1.0)
		var fac = max(0.5,1-0.42*f)
		var spd = max(6,10-f*4.2)
		var scl = 2.1*f + 1
		result.append({
			"mean_velocity": spd,
			"inner_radius": inner_radius+thickness*0.5*(1-fac),
			"thickness": thickness*0.51*fac,
			"spacing": 7*(1+f*scl)*spacing_multiplier,
			"min_scale": 0.8*scl*scale_multiplier,
			"max_scale": 1.2*scl*scale_multiplier
		})
		result.append({
			"mean_velocity": spd*tfac,
			"inner_radius": inner_radius+thickness*0.5,
			"thickness": thickness*0.5*fac,
			"spacing": 7*(1+f*scl)*spacing_multiplier,
			"min_scale": 0.8*scl*scale_multiplier,
			"max_scale": 1.2*scl*scale_multiplier
		})
	return result
