extends Node

var SystemInfo = preload('res://places/SystemInfo.gd')
var PlanetInfo = preload('res://places/PlanetInfo.gd')
var PlanetServices = preload('res://ui/PlanetServices.gd')

var known_systems: Dictionary = {}
var system  setget set_system,get_system
var player_location: NodePath = NodePath() setget set_player_location,get_player_location
var services: Dictionary = {}
var stored_console: String = '\n'.repeat(16) setget set_stored_console,get_stored_console
var name_counter: int = 0

var player_ship_scene: PackedScene = preload('res://ships/PurpleShips/Warship.tscn')

signal console_append

func make_unique_ship_node_name():
	var i: int = name_counter
	name_counter = name_counter+1
	return 'ship_'+str(i)

func print_to_console(s: String):
	if s.ends_with('\n'):
		emit_signal('console_append',s)
	else:
		emit_signal('console_append',s+'\n')
func set_stored_console(s: String): stored_console=s
func get_stored_console() -> String: return stored_console

func is_a_system() -> bool: return false
func is_a_planet() -> bool: return false

func get_system(): return system
func set_system(var s: String):
	if known_systems.has(s):
		system = known_systems[s]
		player_location = get_path_to(system)
	return system

func get_player_location() -> NodePath: return player_location
func set_player_location(s: NodePath):
	var n = get_node_or_null(s)
	if n!=null:
		var loc = get_path_to(n)
		var system_name = loc.get_name(0)
		if known_systems.has(system_name):
			system = known_systems[system_name]
			player_location = loc
	return player_location

func get_player_translation(planet_time: float) -> Vector3:
	var node = get_node_or_null(player_location)
	if node==null or not node.has_method('planet_translation'):
		return Vector3()
	return node.planet_translation(planet_time)

func get_planet_unique_name() -> String:
	var n: Node = get_node_or_null(player_location)
	if n!=null and n.is_a_planet():
		return n.make_unique_name()
	return ""

func get_planet_info_or_null():
	var n: Node = get_node_or_null(player_location)
	if n!=null and n.is_a_planet():
		return n
	return null

func add_system(var node_name,var new_system):
	known_systems[node_name]=new_system
	new_system.name=node_name
	add_child(new_system)

func make_test_systems():
	add_system('seti_alpha',SystemInfo.new('Seti-α') \
		.add_planet(
			PlanetInfo.new('sun', {
				'display_name':'Seti-α', 'shader_seed':1231333334,
			},PlanetInfo.yellow_sun) \
			.add_planet(
				PlanetInfo.new('storm', {
					'display_name':'Storm', 'shader_seed':321321321,
					'orbit_radius':200, 'orbit_period':300, 'size':3,
					'description':'Description of Storm planet.',
				},PlanetInfo.ocean_planet,['info','missing','shipeditor'])
			)
		)
	)
	add_system('alef_93',SystemInfo.new('א:93') \
		.add_planet(
			PlanetInfo.new('astra', {
				'display_name':'Astra', 'shader_seed':91,
			},PlanetInfo.blue_sun) \
			.add_planet(
				PlanetInfo.new('hellscape',{
					'display_name':'Hellscape', 'shader_seed':391,
					'orbit_radius':200, 'orbit_period':91, 'size':2,
				},PlanetInfo.fiery_rock,['info','shipeditor'])
			) \
			.add_planet(
				PlanetInfo.new('pearl',{
					'display_name':'Pearl', 'shader_seed':913,
					'orbit_radius':450, 'orbit_period':1092, 'size':4,
					'description':'Description of Pearl planet.',
				},PlanetInfo.ice_planet,['info','test','alttest','shipeditor'])
			) \
		)
	)
	system = known_systems['alef_93']
	player_location = get_path_to(system)

func _init():
	services['test'] = PlanetServices.ChildInstanceService.new(
		'Service Text',preload('res://ui/TestService.tscn'))
	services['alttest'] = PlanetServices.ChildInstanceService.new(
		'Service Button',preload('res://ui/AltTestService.tscn'))
	services['info'] = PlanetServices.PlanetDescription.new(
		'Planet Description',preload('res://ui/PlanetDescription.tscn'))
	services['shipeditor'] = PlanetServices.SceneChangeService.new(
		'Shipyard',preload('res://ui/ShipEditor.tscn'))
	make_test_systems()
