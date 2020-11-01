extends Node

const Ship = preload('res://Ship.tscn')
const Planet = preload('res://Planet.tscn')
const ShipAI = preload('res://ShipAI.gd')

var display_name: String = "Unnamed" setget ,get_display_name
var counter: int = 0

var planets: Dictionary = {}

var planet_types: Dictionary = {
	'yellow_sun': {
		'type':'sun', 'size':6.0, 'color_scaling':Color(-0.7,-0.7,-0.5),
		'color_addition':Color(1,0.7,0.3)
	},
	'blue_sun': {
		'type':'sun', 'size':6.0, 'color_scaling':Color(-0.4,-0.5,-0.5),
		'color_addition':Color(0.4,0.5,1.0)
	},
	'ocean_planet': {
		'type':'planet', 'size':2.5, 'color_scaling':Color(0.7,0.7,0.2),
		'color_addition':Color(0,0,0.3)
	},
	'ice_planet': {
		'type':'planet', 'size':2.5, 'color_scaling':Color(0.2,0.2,0.7),
		'color_addition':Color(.3,.3,.3)
	},
	'fiery_rock': {
		'type':'planet', 'size':2.5, 'color_scaling':Color(0.7,0.2,0.2),
		'color_addition':Color(0.3,0,0)
	},
}

const default_fleets: Array = [
	{ 'frequency':30, 'ships':[ [2, Ship], [1, Ship] ], 'team':1 },
	{ 'frequency':30, 'ships':[ [1, Ship] ], 'team':0 },
	{ 'frequency':120, 'ships':[ [4, Ship] ], 'team':0 },
]

var fleets: Array = default_fleets

var rng

func _init(the_name: String,the_planets: Dictionary,
		the_fleets: Array=default_fleets):
	display_name = the_name
	planets = the_planets
	fleets = the_fleets
	rng = RandomNumberGenerator.new()
	rng.randomize()

func increment_counter() -> int:
	counter+=1
	return counter

func get_display_name() -> String:
	return display_name

func num_planets():
	return len(planets)

func get_it(info: Dictionary,type: Dictionary,key: String, var default):
	var result=info.get(key,null)
	return result if result!=null else type.get(key,default)

func planet_info(planet_name: String) -> Dictionary:
	var d = planets.get(planet_name,{'type':'unknown'}).duplicate()
	var type: Dictionary = planet_types.get(d['type'],{})
	for k in type:
		if not d.has(k):
			d[k] = type[k]
	d['node_name']=planet_name
	return d

func astral_gate_name() -> String:
	for planet_name in planets:
		var info: Dictionary = planets.get(planet_name,{'type':'yellow_sun'})
		var type: Dictionary = planet_types[info['type']]
		if type['type'] == 'sun':
			return planet_name
	return ''

func has_planet(planet_name: String) -> bool:
	var has = planets.get(planet_name,null)!=null
	print('has planet? ',planet_name,': ',has)
	return has

func innermost_planet(t: float):
	var inner_name = ""
	var inner_distance = 9e9
	for planet_name in planets:
		var x0z = planet_translation(planets[planet_name],t)
		var dist = Vector2(x0z[2],-x0z[0]).length()
		if dist<inner_distance:
			inner_distance=dist
			inner_name = planet_name
	return inner_name
	

func planet_translation(info: Dictionary, t: float, depth: int = 0):
	var radius = info.get('distance',0)
	var start = info.get('start',0)
	var period = info.get('period',0)
	var parent = info.get('parent',null)
	var parent_info = null if parent==null else planets.get(parent,null)
	var angle = 2*PI*t/period if (period>1e-6) else 0
	var loc = Vector3(radius*sin(angle+start),0,radius*cos(angle+start))
	
	if parent_info!=null and depth<10:
		loc += planet_translation(parent_info,t,depth+1)
	
	return loc

func planet_with_name(planet_name: String, detail: float=150, time: float=0):
	print('planet with name ',planet_name)
	var info: Dictionary = planets.get(planet_name,{'type':'yellow_sun'})
	var type: Dictionary = planet_types[info['type']]
	var shader_seed: int = get_it(info,type,'seed',0)
	var size: float = get_it(info,type,'size',0.0)
	var texture_size: int = int(round(pow(2,max(7,min(11,int(log(detail*size)/log(2)))))))
	var planet=Planet.instance()
	if type['type']=='sun':
		planet.make_sun(min(96,max(8,1+detail*size/60.0)),shader_seed,texture_size)
		planet.has_astral_gate = true
	else:
		planet.make_planet(min(96,max(8,1+detail*size/60.0)),shader_seed,texture_size)
	
	var color_scaling: Color = get_it(info,type,'color_scaling',Color(1,1,1,1))
	var color_addition: Color = get_it(info,type,'color_addition',Color(0,0,0,1))
	
	planet.color_sphere(color_scaling,color_addition)
	var x0z = planet_translation(info,time)
	planet.place_sphere(size,Vector3(x0z[0],-5,x0z[2]))
	
	planet.name = planet_name
	planet.display_name = info.get('display_name',planet_name)
	return planet

func spawn_ship(var system,var ship_scene,team: int,a: float,r: float,s: float):
	var ship=ship_scene.instance()
	ship.name=name+'-ship-'+String(increment_counter())
	var x = r*sin(a) + rng.randf()*s
	var z = r*cos(a) + rng.randf()*s
	ship.set_identity()
	ship.rotate(Vector3(0,1,0),-a)
	ship.translate_object_local(Vector3(x,5,z))
	ship.set_team(team)
	ship.ai=ShipAI.new()
	system.spawn_ship(ship)

func spawn_fleet(var system, var fleet: Array,team: int):
	var radius = 60*sqrt(rng.randf())+20
	var angle = rng.randf()*2*PI
	for num_ship in fleet:
		for _n in range(num_ship[0]):
			spawn_ship(system,num_ship[1],team,angle,radius,10)

func process_space(var system,var delta):
	for fleet in fleets:
		if rng.randf_range(0.0,1.0) < delta/fleet['frequency']:
			spawn_fleet(system,fleet['ships'],fleet['team'])

func fill_system(var system,planet_time: float,ship_time: float,detail: float):
	for planet_name in planets:
		system.spawn_planet(planet_with_name(planet_name,detail,planet_time))
	process_space(system,ship_time)
