extends simple_tree.SimpleNode

const Planet = preload('res://places/Planet.tscn')

# IMPORTANT: These must match SpaceObjectSettings._ready():
enum { PLANET=0, STAR=1 }

const base_types = {
	'yellow_sun': {
		'object_type':STAR, 'size':6.0, 'color_scaling':Color(-0.7,-0.7,-0.5),
		'color_addition':Color(1,0.7,0.3)
	},
	'blue_sun': {
		'object_type':STAR, 'size':6.0, 'color_scaling':Color(-0.4,-0.5,-0.5),
		'color_addition':Color(0.4,0.5,1.0)
	},
	'ocean_planet': {
		'object_type':PLANET, 'size':2.5,'color_scaling':Color(0.7,0.7,0.2),
		'color_addition':Color(0,0,0.3)
	},
	'ice_planet': {
		'object_type':PLANET, 'size':2.5, 'color_scaling':Color(0.2,0.2,0.7),
		'color_addition':Color(.3,.3,.3)
	},
	'fiery_rock': {
		'object_type':PLANET, 'size':2.5, 'color_scaling':Color(0.7,0.2,0.2),
		'color_addition':Color(0.3,0,0)
	}
}

const default_axial_tilt: float = 200*PI/180
const default_height_map_scale: float = 0.35
const default_planet_trading: Array = [ 'suvar', 'human' ]
const default_planet_population: Dictionary = { 'suvar':1e6, 'human':9e6 }
const default_planet_industry: float = 100000.0

var shader_type: String = 'old'
var shader_colors: Texture
var object_type = PLANET setget set_object_type
var size: float = 3.0 setget set_size
var color_scaling: Color = Color(1,1,1,1)
var color_addition: Color = Color(0,0,0,1)
var display_name: String = 'Unnamed'
var shader_seed: int = 0
var rotation_period: float = 0.0 setget set_rotation_period
var orbit_radius: float = 0.0 setget set_orbit_radius
var orbit_period: float = 0.0
var orbit_start: float = 0.0
var axial_tilt: float = default_axial_tilt
var height_map_scale: float = default_height_map_scale
var has_astral_gate: bool = false
var services: Array = []
var description: String = ''
var base_name: String = ''
var trading: Array = []
var shipyard: Array = []
var population: Dictionary = {}
var industry: float = 0
var locality_adjustments: Dictionary = {}
var shipyard_locality_adjustments: Dictionary = {}
var cached_unique_name: String

func set_object_type(p: int):
	assert(object_type==PLANET or object_type==STAR)
	object_type=p

func set_size(p: float):
	assert(p>.1)
	size=p

func set_orbit_radius(p: float):
	assert(p>=0)
	orbit_radius = p

func set_rotation_period(p: float):
	rotation_period = p

func is_a_system() -> bool: return false
func is_a_planet() -> bool: return true

func is_SpaceObjectData(): pass # never called; must only exist

func has_market():
	return trading or shipyard or services.has('market')

func has_shipyard():
	return not not shipyard

func total_population() -> float:
	var result: float = 0.0
	for p in population.values():
		result += p
	return result

func total_industry() -> float:
	return industry

func get_system(): # -> SystemData or null
	var parent = get_parent()
	if parent and parent.has_method('get_system'):
		return parent.get_system()
	return null

func maybe_add(result,key,value,base):
	if base and base.has(key) and value==base[key]:
		return
	result[key]=value

func encode() -> Dictionary:
	var base = base_types.get(base_name)
	var result = {
		'services': services.duplicate(true),
		'shipyard': shipyard.duplicate(true),
		'display_name': display_name,
		'description': description,
		'base': base_name,
		'population': population.duplicate(true),
		'trading': trading.duplicate(true),
		'locality_adjustments': locality_adjustments.duplicate(true),
		'shipyard_locality_adjustments': shipyard_locality_adjustments.duplicate(true),
	}
	maybe_add(result,'object_type',object_type,base)
	maybe_add(result,'size',size,base)
	maybe_add(result,'color_scaling',color_scaling,base)
	maybe_add(result,'color_addition',color_addition,base)
	maybe_add(result,'shader_seed',shader_seed,base)
	maybe_add(result,'rotation_period',rotation_period,base)
	maybe_add(result,'axial_tilt',axial_tilt,base)
	maybe_add(result,'default_height_map_scale',height_map_scale,base)
	maybe_add(result,'orbit_radius',orbit_radius,base)
	maybe_add(result,'orbit_period',orbit_period,base)
	maybe_add(result,'orbit_start',orbit_start,base)
	maybe_add(result,'has_astral_gate',has_astral_gate,base)
	return result

func get_or_dup(me: Dictionary,key,default,deep: bool = true):
	if key in me:
		return me[key]
	return default.duplicate(deep)

func _init(node_name,me: Dictionary ={}):
	base_name = me.get('base','')
	var base = base_types.get(base_name,{})
	if node_name:
		set_name(node_name)
	shader_type = get_it(me,base,'shader_type','old')
	if me.has('shader_colors'):
		var sc = me['shader_colors']
		if sc is String and ResourceLoader.exists(sc):
			shader_colors=load(sc)
		else:
			push_warning('shader_colors has invalid resource path '+str(sc))
	if not shader_colors:
		shader_colors = preload('res://textures/continents-terran.jpg')
	object_type = get_it(me,base,'object_type',PLANET)
	size = get_it(me,base,'size',5)
	color_scaling = get_it(me,base,'color_scaling',Color(1,1,1,1))
	color_addition = get_it(me,base,'color_addition',Color(0,0,0,1))
	display_name = get_it(me,base,'display_name','Unnamed')
	shader_seed = get_it(me,base,'shader_seed',0)
	orbit_radius = get_it(me,base,'orbit_radius',20.0)
	orbit_period = get_it(me,base,'orbit_period',20.0)
	orbit_start = get_it(me,base,'orbit_start',0.0)
	rotation_period = get_it(me,base,'rotation_period',0.0)
	axial_tilt = get_it(me,base,'axial_tilt',default_axial_tilt)
	height_map_scale = get_it(me,base,'height_map_scale',default_height_map_scale)
	has_astral_gate = get_it(me,base,'has_astral_gate',object_type==STAR)
	description = get_it(me,base,'description','')
	services = me.get('services',[])
	locality_adjustments = me.get('locality_adjustments',{})
	shipyard_locality_adjustments = me.get('shipyard_locality_adjustments',{})
	if object_type==PLANET:
		var trad = get_or_dup(me,'trading',default_planet_trading)
		if trad is Dictionary:
			trad = trad.keys()
		trading = trad
		shipyard = get_or_dup(me,'shipyard',[])
		population = get_or_dup(me,'population',default_planet_population)
		industry = me.get('industry',default_planet_industry)
		if 'locality_adjustments' in me:
			locality_adjustments = me['locality_adjustments']
		if 'shipyard_locality_adjustments' in me:
			shipyard_locality_adjustments = me['shipyard_locality_adjustments']
	var objects = me.get('objects',{})
	if objects and objects is Dictionary:
		for key in objects:
			var object = objects[key]
			if object and object is simple_tree.SimpleNode:
				var _discard = add_child(object,key)

func price_products(result: Commodities.Products):
	if locality_adjustments:
		result.apply_multiplier_list(locality_adjustments)
	var system = get_system()
	if system:
		system.price_products(result)

func list_products(commodities: Reference, result: Commodities.Products):
	for trade in trading:
		var proc = Commodities.trading.get(trade,null)
		if proc:
			proc.population(commodities,result,population)
			proc.industry(commodities,result,industry)
		else:
			push_warning('Trade type "'+str(trade)+'" not in known types '+
				str(Commodities.trading.keys()))
	price_products(result)

func price_ship_parts(_result: Commodities.Products):
	pass # FIXME: Maybe implement locality adjustments for parts?

func list_ship_parts(all: Commodities.Products, here: Commodities.Products):
	for whut in shipyard:
		var proc = Commodities.shipyard.get(whut,null)
		if whut:
			proc.population(all,here,population)
			proc.industry(all,here,industry)
		else:
			push_warning('Ship part type "'+str(whut)+'" not in known types '+
				str(Commodities.shipyard.keys()))
	price_ship_parts(here)

func astral_gate_path() -> NodePath:
	if has_astral_gate:
		return get_path()
	for child in get_children():
		if child.has_method('astral_gate_path'):
			var p: NodePath = child.astral_gate_path()
			if not p.is_empty():
				return p
	return NodePath()

func get_it(info: Dictionary,type: Dictionary,key: String, var default):
	var result=info.get(key,null)
	return result if result!=null else type.get(key,default)

func make_unique_name() -> String:
	if not cached_unique_name:
		cached_unique_name = _impl_make_unique_name()
	return cached_unique_name

func _impl_make_unique_name() -> String:
	var uname = get_name()
	var parent = get_parent()
	if parent==null:
		return uname
	elif parent.has_method('make_unique_name'):
		return parent.make_unique_name() + '_' + uname
	return parent.get_name() + '_' + uname

func full_display_name() -> String:
	var fp = display_name
	var parent = get_parent()
	if parent==null:
		return fp
	elif parent.is_a_planet() or parent.is_a_system():
		return parent.full_display_name() + ' ' + fp
	return fp

func planet_basis(time: float) -> Basis:
	var rotation_y = 2*PI*time/rotation_period if abs(rotation_period)>1e-6 else 0.0
	var b: Basis = Basis()
	b=b.rotated(Vector3(0,1,0),rotation_y)
	b=b.rotated(Vector3(0,0,1),axial_tilt)
	return b

func planet_translation(time: float) -> Vector3:
	var angle = 2*PI*time/orbit_period if abs(orbit_period)>1e-6 else 0.0
	var loc = Vector3(orbit_radius*sin(angle+orbit_start),0,orbit_radius*cos(angle+orbit_start))
	
	var parent = get_parent()
	if parent!=null and parent.has_method('is_SpaceObjectData'):
		loc += parent.planet_translation(time)
	return loc

func orbital_adjustments_to(time: float,new_location: Vector3,parent=null) -> Dictionary:
	var angle = 2*PI*time/orbit_period if abs(orbit_period)>1e-6 else 0.0
	if parent==null:
		parent = get_parent()
	var parent_translation: Vector3 = Vector3()
	if parent and parent.has_method('is_SpaceObjectData'):
		parent_translation = parent.planet_translation(time)
	var new_rad_loc = new_location-parent_translation
	new_rad_loc.y=0
	var new_radius = new_rad_loc.length()

	var new_start = 0.0
	if abs(orbit_period)>1e-6:
		var new_rel_loc = new_rad_loc
		var new_angle = atan2(new_rel_loc.x,new_rel_loc.z)
		new_start = fmod(new_angle - angle, 2*PI)
	return { 'orbit_radius':new_radius, 'orbit_start':new_start }

func make_planet(detail: float=150, time: float=0, planet = null):
	var texture_size: int = int(round(pow(2,max(7,min(11,int(log(detail*size)/log(2)))))))
	var place_sphere: bool = false
	if not planet:
		planet=Planet.instance()
		place_sphere=true
	if object_type==STAR:
		planet.make_sun(1+detail*size/30.0,shader_seed,texture_size,shader_type,shader_colors,height_map_scale)
		planet.has_astral_gate = true
	else:
		planet.make_planet(1+detail*(10+size)/30.0,shader_seed,texture_size,shader_type,shader_colors,height_map_scale)
	
	planet.color_sphere(color_scaling,color_addition)
	if place_sphere:
		var x0z = planet_translation(time)
		planet.place_sphere(size,Vector3(x0z[0],-20,x0z[2]),planet_basis(time))
	
	planet.name = make_unique_name()
	planet.display_name = display_name
	planet.full_display_name = full_display_name()
	planet.has_astral_gate = has_astral_gate
	planet.game_state_path = game_state.systems.get_path_to(self)
	list_products(Commodities.commodities,planet.commodities)
	return planet

func fill_system(var system,planet_time: float,ship_time: float,detail: float,ships=true):
	system.spawn_planet(make_planet(detail,planet_time))
	for child in get_children():
		if child.is_a_planet():
			child.fill_system(system,planet_time,ship_time,detail,ships)
