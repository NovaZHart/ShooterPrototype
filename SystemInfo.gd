extends Node

const Ship = preload('res://Ship.tscn')
const BigShip = preload('res://BigShip.tscn')
const PillShip = preload('res://PillShip.tscn')
const Planet = preload('res://Planet.tscn')
const ShipAI = preload('res://ShipAI.gd')

var display_name: String = "Unnamed" setget ,get_display_name
var counter: int = 0

const default_fleets: Array = [
	{ 'frequency':100, 'ships':[ [3, PillShip] ], 'team':1 },
	{ 'frequency':30, 'ships':[ [1, PillShip], [1, BigShip] ], 'team':1 },
	{ 'frequency':30, 'ships':[ [5, Ship] ], 'team':0 },
	{ 'frequency':200, 'ships':[ [1, Ship] ], 'team':0 },
]

const team_maximums: Array = [ 12,10 ]

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

func spawn_ship(var system,var ship_scene,team: int,a: float,r: float,s: float):
	var ship=ship_scene.instance()
	ship.name=name+'-ship-'+String(increment_counter())
	var x = r*sin(a) + 2*(rng.randf()-0.5)*s
	var z = r*cos(a) + 2*(rng.randf()-0.5)*s
	ship.set_identity()
	ship.rotation=Vector3(0,-a,0)
	ship.translation=Vector3(x,5,z)
	ship.set_team(team)
	ship.ai=ShipAI.new()
	system.spawn_ship(ship)

func spawn_fleet(var system, var fleet: Array,team: int):
	var radius = 100*rng.randf()
	var angle = rng.randf()*2*PI
	for num_ship in fleet:
		for _n in range(num_ship[0]):
			spawn_ship(system,num_ship[1],team,angle,radius,10)

func process_space(var system,var delta):
	for fleet in fleets:
		if rng.randf_range(0.0,1.0) < delta*fleet['frequency']/1800:
			var team: int = fleet['team']
			if system.ship_count_by_team(team)<team_maximums[team]:
				spawn_fleet(system,fleet['ships'],team)

func fill_system(var system,planet_time: float,ship_time: float,detail: float):
	for child in get_children():
		if child.is_a_planet():
			child.fill_system(system,planet_time,ship_time,detail)
	process_space(system,ship_time)
