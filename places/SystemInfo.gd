extends Node

const PurpleWarship = preload('res://ships/PurpleShips/Warship.tscn')
const PurpleHeavyWarship = preload('res://ships/PurpleShips/HeavyWarship.tscn')
const PurpleInterceptor = preload('res://ships/PurpleShips/Interceptor.tscn')
const BannerShip = preload('res://ships/BannerShip/BannerShip.tscn')

var display_name: String = "Unnamed" setget ,get_display_name
var counter: int = 0

const default_fleets: Array = [
	{ 'frequency':1800, 'ships':[ [2, PurpleWarship] ], 'team':0 },
	{ 'frequency':1800, 'ships':[ [1, PurpleWarship], [1, PurpleInterceptor] ], 'team':0 },
	{ 'frequency':1800, 'ships':[ [3, PurpleInterceptor] ], 'team':0 },
	{ 'frequency':900, 'ships':[ [1, PurpleHeavyWarship], ], 'team':0 },
	
#	{ 'frequency':60, 'ships':[ [1, BannerShip], [1, PurpleInterceptor] ], 'team':0 },

	{ 'frequency':1800, 'ships':[ [2, PurpleWarship] ], 'team':1 },
	{ 'frequency':1800, 'ships':[ [1, PurpleWarship], [1, PurpleInterceptor] ], 'team':1 },
	{ 'frequency':1800, 'ships':[ [3, PurpleInterceptor] ], 'team':1 },
	{ 'frequency':900, 'ships':[ [1, PurpleHeavyWarship], ], 'team':1 },
]

const standalone_team_maximums: Array = [ 200,200 ]
const standalone_max_ships: int = 300
const debug_team_maximums: Array = [75, 75]
const debug_max_ships: int = 120

var team_maximums: Array = standalone_team_maximums
var max_ships: int = standalone_max_ships

var fleets: Array = default_fleets

var rng

func is_a_system() -> bool: return true
func is_a_planet() -> bool: return false

func add_planet(var p):
	add_child(p)
	return self

func full_display_name():
	return display_name

func _init(the_name: String,the_fleets: Array=default_fleets):
	display_name = the_name
	fleets = the_fleets
	rng = RandomNumberGenerator.new()
	rng.randomize()
	if not OS.has_feature('standalone'):
		print('Reducing ship count for debug build')
		max_ships = debug_max_ships
		team_maximums = debug_team_maximums

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

func spawn_ship(var _system,var ship_scene,team: int,angle: float,
		add_radius: float,safe_zone: float,
		random_x: float, random_z: float, center: Vector3, is_player: bool):
	var x = (safe_zone+add_radius)*sin(angle) + center.x + random_x
	var z = (safe_zone+add_radius)*cos(angle) + center.z + random_z
	return ['spawn_ship',ship_scene, Vector3(0,-1,0), Vector3(x,5,z),
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
			result.push_back(spawn_ship(system,num_ship[1],team,
				angle,add_radius,randf()*10-5,randf()*10-5,
				safe_zone,planet.translation,false))
	return result

func spawn_player(system: Spatial,scene: PackedScene,t: float):
	var add_radius = 50*sqrt(rng.randf())
	var angle = rng.randf()*2*PI
	var center = game_state.get_player_translation(t)
	return spawn_ship(system,scene,0,angle,add_radius,0,0,10,center,true)

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
	var result = [spawn_player(system,game_state.player_ship_scene,planet_time)]
	result += process_space(system,ship_time)
	return result
