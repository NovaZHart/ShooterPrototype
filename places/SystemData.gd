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

var faction_goals: Array
var active_factions: Dictionary

const default_active_factions: Dictionary = {
	'police': { 'starting_money':2e5, 'income_per_second':2e5, 'fleet_type_weights':{
		'large_police':1.0, 'small_police':1.0 }
	},
	'raiders': { 'starting_money':2e5, 'income_per_second':2e5, 'fleet_type_weights':{
		'large_raid':1.0, 'small_raid':1.0 },
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
	return []
