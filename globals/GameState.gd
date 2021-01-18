extends Node

var SystemInfo = preload('res://places/SystemInfo.gd')
var PlanetInfo = preload('res://places/PlanetInfo.gd')
var Universe = preload('res://places/Universe.gd')
var PlanetServices = preload('res://ui/PlanetServices.gd')

var known_systems: Dictionary = {}
var system  setget set_system,get_system
var player_location: NodePath = NodePath() setget set_player_location,get_player_location
var services: Dictionary = {}
var stored_console: String = '\n'.repeat(16) setget set_stored_console,get_stored_console
var name_counter: int = 0
var ship_designs: Dictionary = {}
var universe = Universe.new()
var tree = simple_tree.SimpleTree.new(universe)

var player_ship_design: Dictionary

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

func get_info_or_null():
	var n: Node = get_node_or_null(player_location)
	if n!=null and n.is_a_planet() or n.is_a_system():
		return n
	return null

func add_system(var node_name,var new_system):
	known_systems[node_name]=new_system
	new_system.name=node_name
	add_child(new_system)

func assemble_player_ship():
	return assemble_ship(player_ship_design)

func assemble_ship(design: Dictionary):
	if not 'hull' in design or not design['hull'] is PackedScene:
		printerr('assemble_ship: no hull provided')
		return null
	var body_scene = design['hull']
	var body = body_scene.instance()
	if body == null:
		printerr('assemble_ship: cannot instance scene: ',body_scene)
		return Node.new()
	body.save_transforms()
	for child in body.get_children():
		if child is CollisionShape and child.scale.y<10:
			child.scale.y=10
		if child.name!='hull' and design.has(child.name) and design[child.name] is PackedScene:
			var new_child: Node = design[child.name].instance()
			if new_child!=null:
				new_child.transform = child.transform
				new_child.name = child.name
				body.remove_child(child)
				child.queue_free()
				body.add_child(new_child)
				continue
		
		if child.has_method('is_not_mounted'):
			# Unused slots are removed to save space in the scene tree
			body.remove_child(child)
			child.queue_free()
	return body

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
	add_system('alef_93',SystemInfo.new('א-93') \
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

func make_test_designs():
	ship_designs = {
		'warship_lasers':{
			"hull": preload("res://ships/PurpleShips/WarshipHull.tscn"),
			"PortMiddleGun": preload("res://weapons/GreenLaserGun.tscn"),
			"PortOuterGun": preload("res://weapons/BlueLaserGun.tscn"),
			"StarboardMiddleGun": preload("res://weapons/GreenLaserGun.tscn"),
			"StarboardOuterGun": preload("res://weapons/BlueLaserGun.tscn"),
			"Engine": preload("res://equipment/engines/Engine2x4.tscn"),
			'Equipment': [
				[ 0, 0, preload("res://equipment/repair/Shield2x2.tscn") ]
			],
		},
		'warship_cyclotrons':{
			"hull": preload("res://ships/PurpleShips/WarshipHull.tscn"),
			"PortMiddleGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"PortOuterGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"StarboardMiddleGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"StarboardOuterGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"Engine": preload("res://equipment/engines/Engine2x4.tscn"),
			'Equipment': [
				[ 0, 0, preload("res://equipment/repair/Shield2x2.tscn") ]
			],
		},

		'banner_default':{
			"hull": preload("res://ships/BannerShip/BannerShipHull.tscn"),
			"ForwardTurret": preload("res://weapons/BlueLaserTurret.tscn"),
			"PortGun": preload("res://weapons/GreenLaserGun.tscn"),
			"StarboardGun": preload("res://weapons/GreenLaserGun.tscn"),
			"AftPortTurret": preload("res://weapons/OrangeSpikeTurret.tscn"),
			"AftStarboardTurret": preload("res://weapons/OrangeSpikeTurret.tscn"),
			"Engine": preload("res://equipment/engines/Engine2x4.tscn"),
			"Equipment": [
				[ 0, 0, preload("res://equipment/repair/Shield3x3.tscn") ],
				[ 3, 0, preload("res://equipment/repair/Shield3x3.tscn") ],
			]
		},

		'curvy_cyclotrons':{
			"hull": preload("res://ships/PurpleShips/CurvyWarshipHull.tscn"),
			"PortGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"StarboardGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"Turret": preload("res://weapons/OrangeSpikeTurret.tscn"),
			"Engine": preload("res://equipment/engines/Engine2x4.tscn"),
			"PortEquipment": [
				[ 0, 0, preload("res://equipment/repair/Shield2x2.tscn") ],
				[ 0, 2, preload("res://equipment/repair/Shield2x1.tscn") ],
			]
		},

		'interceptor_cyclotrons':{
			"hull": preload("res://ships/PurpleShips/InterceptorHull.tscn"),
			"PortGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"Engine": preload("res://equipment/engines/Engine2x2.tscn"),
			"StarboardGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			'Equipment': [
				[ 0, 0, preload("res://equipment/repair/Shield2x1.tscn") ]
			],
		},
		'interceptor_lasers':{
			"hull": preload("res://ships/PurpleShips/InterceptorHull.tscn"),
			"PortGun": preload("res://weapons/BlueLaserGun.tscn"),
			"Engine": preload("res://equipment/engines/Engine2x2.tscn"),
			"StarboardGun": preload("res://weapons/BlueLaserGun.tscn"),
			'Equipment': [
				[ 0, 0, preload("res://equipment/repair/Shield2x1.tscn") ]
			],
		},

		'heavy_cyclotrons':{
			"hull": preload("res://ships/PurpleShips/HeavyWarshipHull.tscn"),
			"MidPortTurret": preload("res://weapons/OrangeSpikeTurret.tscn"),
			"ForwardTurret": preload("res://weapons/BlueLaserTurret.tscn"),
			"PortSmallGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"StarboardSmallGun": preload("res://weapons/OrangeSpikeGun.tscn"),
			"PortLargeGun": preload('res://weapons/PurpleHomingGun.tscn'),
			"AftPortTurret": preload("res://weapons/BlueLaserTurret.tscn"),
			"StarboardLargeGun": preload('res://weapons/PurpleHomingGun.tscn'),
			"MidStarboardTurret": preload("res://weapons/OrangeSpikeTurret.tscn"),
			"AftStarboardTurret": preload("res://weapons/BlueLaserTurret.tscn"),
			"Engine": preload("res://equipment/engines/Engine4x4.tscn"),
			'AftEquipment': [
				[ 0, 0, preload("res://equipment/repair/Shield3x3.tscn") ]
			],
		},
		'heavy_lasers':{
			'hull':preload('res://ships/PurpleShips/HeavyWarshipHull.tscn'),
			'PortLargeGun':preload('res://weapons/PurpleHomingGun.tscn'),
			'StarboardLargeGun':preload('res://weapons/PurpleHomingGun.tscn'),
			'PortSmallGun':preload('res://weapons/GreenLaserGun.tscn'),
			'StarboardSmallGun':preload('res://weapons/GreenLaserGun.tscn'),
			'ForwardTurret':preload('res://weapons/BlueLaserTurret.tscn'),
			'AftPortTurret':preload('res://weapons/BlueLaserTurret.tscn'),
			'AftStarboardTurret':preload('res://weapons/BlueLaserTurret.tscn'),
			'MidPortTurret':preload('res://weapons/OrangeSpikeTurret.tscn'),
			'MidStarboardTurret':preload('res://weapons/OrangeSpikeTurret.tscn'),
			"Engine": preload("res://equipment/engines/Engine4x4.tscn"),
			'AftEquipment': [
				[ 0, 0, preload("res://equipment/repair/Shield3x3.tscn") ]
			],
		},
	}
	player_ship_design = ship_designs['warship_lasers']


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
	make_test_designs()
