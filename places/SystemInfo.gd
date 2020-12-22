extends Node

const SimpleInterceptor = preload('res://ships/SimpleInterceptor.tscn')
const SuperSimpleInterceptor = preload('res://ships/SuperSimpleInterceptor.tscn')

var display_name: String = "Unnamed" setget ,get_display_name
var counter: int = 0

const default_fleets: Array = [
	{ 'frequency':900, 'ships':[ [8, SimpleInterceptor] ], 'team':1 },
	{ 'frequency':900, 'ships':[ [8, SimpleInterceptor] ], 'team':0 },
	{ 'frequency':2400, 'ships':[ [3, SimpleInterceptor] ], 'team':1 },
	{ 'frequency':2400, 'ships':[ [3, SimpleInterceptor] ], 'team':0 },
]

const team_maximums: Array = [ 75,75 ]
const max_ships: int = 120

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

func spawn_ship(var _system,var ship_scene,team: int,a: float,r: float,s: float,
		is_player: bool):
	var x = r*sin(a) + 2*(rng.randf()-0.5)*s
	var z = r*cos(a) + 2*(rng.randf()-0.5)*s
	return ['spawn_ship',[ship_scene, Vector3(0,-1,0), Vector3(x,5,z),
		team, is_player]]

func fleet_size(var fleet: Array) -> int:
	var result: int = 0
	for num_ship in fleet:
		var size: int = num_ship[0]
		result += size
	return result

func spawn_fleet(system, fleet: Array,team: int) -> Array:
	var result: Array = Array()
	var radius = 100*rng.randf()
	var angle = rng.randf()*2*PI
	for num_ship in fleet:
		for _n in range(num_ship[0]):
			result.push_back(spawn_ship(system,num_ship[1],team,angle,radius,10,false))
	return result

func process_space(system,delta) -> Array:
	var result: Array = Array()
	for fleet in fleets:
		if rng.randf_range(0.0,1.0) > delta*fleet['frequency']/3600:
			continue
		var size: int = fleet_size(fleet['ships'])
		var team: int = fleet['team']
		var my_count: int = system.ship_count_by_team(team)
		if my_count+size>team_maximums[team]:
			continue
		var their_count: int = system.ship_count_by_team(1-team)
		if my_count > their_count*1.5 and my_count>1:
			continue
		if my_count+their_count+size > max_ships:
			continue
		result += spawn_fleet(system,fleet['ships'],team)
	return result

func fill_system(var system,planet_time: float,ship_time: float,detail: float) -> Array:
	var result = [spawn_ship(system,SuperSimpleInterceptor,0,0,0,0,true)]
	for child in get_children():
		if child.is_a_planet():
			child.fill_system(system,planet_time,ship_time,detail)
	result += process_space(system,ship_time)
	return result
