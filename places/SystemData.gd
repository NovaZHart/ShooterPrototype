extends simple_tree.SimpleNode

var display_name: String = "Unnamed" setget ,get_display_name
var counter: int = 0

const default_fleets: Array = [
	{ 'frequency':900, 'ships':[ [2, 'warship_cyclotrons'] ], 'team':0 },
	{ 'frequency':900, 'ships':[ [2, 'curvy_cyclotrons'] ], 'team':0 },
	{ 'frequency':900, 'ships':[ [1, 'warship_lasers'], [1, 'interceptor_lasers' ] ], 'team':0 },
	{ 'frequency':900, 'ships':[ [1, 'curvy_cyclotrons'], [1, 'interceptor_cyclotrons' ] ], 'team':0 },
	{ 'frequency':1200, 'ships':[ [3, 'interceptor_lasers'] ], 'team':0 },
	{ 'frequency':600, 'ships':[ [3, 'interceptor_lasers'] ], 'team':0 },
	{ 'frequency':450, 'ships':[ [1, 'heavy_lasers'], ], 'team':0 },
	{ 'frequency':450, 'ships':[ [1, 'heavy_cyclotrons'], ], 'team':0 },
	{ 'frequency':100, 'ships':[ [1, 'banner_default'], ], 'team':0 },
	
#	{ 'frequency':60, 'ships':[ [1, 'bannership_default'], [1, 'interceptor_default'] ], 'team':0 },

	{ 'frequency':900, 'ships':[ [2, 'warship_cyclotrons'] ], 'team':1 },
	{ 'frequency':900, 'ships':[ [2, 'curvy_cyclotrons'] ], 'team':1 },
	{ 'frequency':900, 'ships':[ [1, 'warship_lasers'], [1, 'interceptor_lasers' ] ], 'team':1 },
	{ 'frequency':900, 'ships':[ [1, 'curvy_cyclotrons'], [1, 'interceptor_cyclotrons' ] ], 'team':1 },
	{ 'frequency':1200, 'ships':[ [3, 'interceptor_lasers'] ], 'team':1 },
	{ 'frequency':600, 'ships':[ [3, 'interceptor_lasers'] ], 'team':1 },
	{ 'frequency':450, 'ships':[ [1, 'heavy_lasers'], ], 'team':1 },
	{ 'frequency':450, 'ships':[ [1, 'heavy_cyclotrons'], ], 'team':1 },
]

const standalone_team_maximums: Array = [ 200,200 ]
const standalone_max_ships: int = 300
const debug_team_maximums: Array = [35, 35]
const debug_max_ships: int = 60

var team_maximums: Array = standalone_team_maximums
var max_ships: int = standalone_max_ships
var fleets: Array = default_fleets
var rng

func is_a_system() -> bool: return true
func is_a_planet() -> bool: return false

func is_SystemData(): pass # never called; must only exist

#func add_planet(planet_name: String,planet: Reference):
#	add_child(planet_name,planet)
#	return self
#
func full_display_name():
	return display_name

func encode() -> Dictionary:
	return {
		'display_name':display_name,
		'fleets':fleets.duplicate(true),
	}

func _init(the_name,content: Dictionary):
	display_name = content.get('display_name','(unnamned)')
	fleets = content.get('fleets',default_fleets)
	if the_name:
		set_name(the_name)
	rng = RandomNumberGenerator.new()
	rng.randomize()
	if not OS.has_feature('standalone'):
		print('Reducing ship count for debug build')
		max_ships = debug_max_ships
		team_maximums = debug_team_maximums
	var objects = content.get('objects',{})
	if objects and objects is Dictionary:
		for key in objects:
			var object = objects[key]
			if object and object is simple_tree.SimpleNode:
				add_child(object,key)

func increment_counter() -> int:
	counter+=1
	return counter

func get_display_name() -> String:
	return display_name

func num_planets():
	var n=0
	for child in get_children():
		if child.is_a_planet():
			n += 1+child.num_planets()
	return n

func astral_gate_path() -> NodePath:
	for child in get_children():
		if not child.is_a_planet():
			continue
		var p: NodePath = child.astral_gate_path()
		if not p.is_empty():
			return p
	return NodePath()

func spawn_ship(var _system,var ship_design: Dictionary,team: int,angle: float,
		add_radius: float,safe_zone: float,
		random_x: float, random_z: float, center: Vector3, is_player: bool):
	var x = (safe_zone+add_radius)*sin(angle) + center.x + random_x
	var z = (safe_zone+add_radius)*cos(angle) + center.z + random_z
	
	# IMPORTANT: Return value must match what spawn_ship, init_system, and
	#   _physics_process want in System.gd:
	return ['spawn_ship',ship_design, Vector3(0,-1,0), Vector3(x,5,z),
		team, is_player]

func fleet_size(var fleet: Array) -> int:
	var result: int = 0
	for num_ship in fleet:
		var size: int = num_ship[0]
		result += size
	return result

func spawn_fleet(system, fleet: Array,team: int) -> Array:
	var planets: Array = system.get_node("Planets").get_children()
	var planet: Spatial = planets[randi()%len(planets)]
	var result: Array = Array()
	var add_radius = 100*sqrt(rng.randf())
	var safe_zone = 25
	var angle = rng.randf()*2*PI
	for num_ship in fleet:
		for _n in range(num_ship[0]):
			var design_name: String = num_ship[1]
			if design_name in game_state.ship_designs:
				result.push_back(spawn_ship(
					system,game_state.ship_designs[design_name],team,
					angle,add_radius,randf()*10-5,randf()*10-5,
					safe_zone,planet.translation,false))
			else:
				printerr('No such design: ',design_name)
	return result

func spawn_player(system: Spatial,t: float):
	var add_radius = 50*sqrt(rng.randf())
	var angle = rng.randf()*2*PI
	var center = game_state.get_player_translation(t)
	return spawn_ship(system,game_state.player_ship_design,
		0,angle,add_radius,0,0,10,center,true)

func process_space(system,delta) -> Array:
	var result: Array = Array()
	var stats: Array = system.ship_stats_by_team().duplicate(true)
	for fleet in fleets:
		if rng.randf_range(0.0,1.0) > delta*fleet['frequency']/3600:
			continue
		var size: int = fleet_size(fleet['ships'])
		var team: int = fleet['team']
		var enemy: int = 1-team
		if stats[team]['count']+size>team_maximums[team]:
			continue
		if stats[team]['threat'] > stats[enemy]['threat']*1.5 and stats[team]['count']>1:
			continue
		if stats[team]['count']+stats[enemy]['count']+size > max_ships:
			continue
		result += spawn_fleet(system,fleet['ships'],team)
		stats[team]['count'] += size
	return result

func fill_system(var system,planet_time: float,ship_time: float,detail: float) -> Array:
	for child in get_children():
		if child.is_a_planet():
			child.fill_system(system,planet_time,ship_time,detail)
	var result = [spawn_player(system,planet_time)]
	result += process_space(system,ship_time)
	return result
