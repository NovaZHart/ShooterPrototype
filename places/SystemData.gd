extends simple_tree.SimpleNode

var display_name: String = "Unnamed" setget ,get_display_name
var counter: int = 0

const default_fleets: Array = [
	{ 'frequency':900, 'fleet':'raven_duo_cyclotrons', 'team':0 },
	{ 'frequency':900, 'fleet':'eagle_duo_cyclotrons', 'team':0 },
	{ 'frequency':900, 'fleet':'eagle_peregrine_lasers', 'team':0 },
	{ 'frequency':900, 'fleet':'raven_peregrine_cyclotrons', 'team':0 },
	{ 'frequency':1200, 'fleet':'peregrine_trio_lasers', 'team':0 },
	{ 'frequency':600, 'fleet':'peregrine_trio_cyclotrons', 'team':0 },
	{ 'frequency':450, 'fleet':'condor_lasers', 'team':0 },
	{ 'frequency':450, 'fleet':'condor_cyclotrons', 'team':0 },
	{ 'frequency':100, 'fleet':'banner_ship', 'team':0 },
	
#	{ 'frequency':60, 'ships':[ [1, 'bannership_default'], [1, 'interceptor_default'] ], 'team':0 },

	{ 'frequency':900, 'fleet':'raven_duo_cyclotrons', 'team':1 },
	{ 'frequency':900, 'fleet':'eagle_duo_cyclotrons', 'team':1 },
	{ 'frequency':900, 'fleet':'eagle_peregrine_lasers', 'team':1 },
	{ 'frequency':900, 'fleet':'raven_peregrine_cyclotrons', 'team':1 },
	{ 'frequency':1200, 'fleet':'peregrine_trio_lasers', 'team':1 },
	{ 'frequency':600, 'fleet':'peregrine_trio_cyclotrons', 'team':1 },
	{ 'frequency':450, 'fleet':'condor_lasers', 'team':1 },
	{ 'frequency':450, 'fleet':'condor_cyclotrons', 'team':1 },
]
var fleets: Array
var links: Dictionary
var position: Vector3 setget set_position
var plasma_seed: int
var plasma_color: Color
var starfield_seed: int

var rng

func set_position(v: Vector3):
	position=Vector3(v.x,0.0,v.z)

func is_a_system() -> bool: return true
func is_a_planet() -> bool: return false

func is_SystemData(): pass # never called; must only exist

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
	}
	if fleets!=default_fleets:
		result['fleets']=fleets.duplicate(true)
	return result

func getdict(content: Dictionary, key, default):
	var result = content.get(key,null)
	return default if result==null else result

func decode(content: Dictionary):
	display_name = content.get('display_name','(unnamned)')
	fleets = getdict(content,'fleets',['abc'])
	if len(fleets)==1 and fleets[0] is String and fleets[0]=='abc':
		fleets=default_fleets.duplicate(true)
	links = getdict(content,'links',{})
	plasma_seed = getdict(content,'plasma_seed',320918)
	starfield_seed = getdict(content,'starfield_seed',987686)
	plasma_color = getdict(content,'plasma_color',Color(0.07,0.07,.18,1.0))
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
#	var n=0
#	for child in get_children():
#		if child.is_a_planet():
#			n += 1+child.get_child_count()
#	return n

func astral_gate_path() -> NodePath:
	for child in get_children():
		if child.has_method('astral_gate_path'):
			var p: NodePath = child.astral_gate_path()
			if not p.is_empty():
				return p
	return NodePath()

func spawn_ship(var _system,var ship_design: simple_tree.SimpleNode,
		team: int,angle: float,add_radius: float,safe_zone: float,
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

func spawn_fleet(system, fleet_node: simple_tree.SimpleNode, design_names: Array,team: int) -> Array:
	var planets: Array = system.get_node("Planets").get_children()
	var center: Vector3 = Vector3()
	if planets:
		var planet: Spatial = planets[randi()%len(planets)]
		center = planet.translation
	var result: Array = Array()
	var add_radius = 100*sqrt(rng.randf())
	var safe_zone = 25
	var angle = rng.randf()*2*PI
	for design_name in design_names:
		var num_ships = int(fleet_node.spawn_count_for(design_name))
		for _n in range(num_ships):
			var design = game_state.ship_designs.get_node_or_null(design_name)
			if design:
				result.push_back(spawn_ship(
					system,design,team,
					angle,add_radius,randf()*10-5,randf()*10-5,
					safe_zone,center,false))
			else:
				push_warning('Fleet '+str(fleet_node.get_path())+
					' wants to spawn missing design '+str(design.get_path()))
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
		var fleet_name = fleet['fleet']
		var fleet_node: simple_tree.SimpleNode = game_state.fleets.get_child_with_name(fleet_name)
		if not fleet_node:
			push_warning('System '+str(get_path())+' wants to spawn missing fleet "'+fleet_name+'"')
		var designs = fleet_node.get_designs()
		var size: int = len(designs)
		var team: int = fleet['team']
		var enemy: int = 1-team
		if stats[team]['count']+size>game_state.team_maximums[team]:
			continue
		if stats[team]['threat'] > stats[enemy]['threat']*1.5 and stats[team]['count']>1:
			continue
		if stats[team]['count']+stats[enemy]['count']+size > game_state.max_ships:
			continue
		result += spawn_fleet(system,fleet_node,designs,team)
		stats[team]['count'] += size
	return result

func fill_system(var system,planet_time: float,ship_time: float,detail: float,ships=true) -> Array:
	system.update_space_background(self)
	for child in get_children():
		if child.is_a_planet():
			child.fill_system(system,planet_time,ship_time,detail,ships)
	if not ships:
		return []
	var result = [spawn_player(system,planet_time)]
	result += process_space(system,ship_time)
	return result
