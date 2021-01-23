extends Node

const standalone_team_maximums: Array = [ 200,200 ]
const standalone_max_ships: int = 300
const debug_team_maximums: Array = [35, 35]
const debug_max_ships: int = 60

var team_maximums: Array = standalone_team_maximums
var max_ships: int = standalone_max_ships

var Universe = preload('res://places/Universe.gd')
var PlanetServices = preload('res://ui/PlanetServices.gd')

var system setget set_system,get_system
var player_location: NodePath = NodePath() setget set_player_location,get_player_location
var services: Dictionary = {}
var stored_console: String = '\n'.repeat(16) setget set_stored_console,get_stored_console
var name_counter: int = 0
var ship_designs: Dictionary = {}
var universe
var tree

var player_ship_design: Dictionary

signal console_append

class SectorEditorStub extends Spatial:
	var selection = null
	func process_if(_condition: bool) -> bool:
		return true
	func change_selection_to(_what, _center: bool) -> bool:
		return true
	func deselect(_what) -> bool:
		return true
	func cancel_drag() -> bool:
		return true

class SystemEditorStub extends Panel:
	func update_system_data(_path: NodePath,_background_update: bool,
			_metadata_update: bool):
		return true
	func update_space_object_data(_path: NodePath, _basic: bool, _visual: bool,
			_help: bool, _location: bool):
		return true
	func add_space_object(_parent: NodePath, _child) -> bool:
		return true
	func remove_space_object(_parent: NodePath, _child) -> bool:
		return true
	func change_selection_to(_what, _center: bool) -> bool:
		return true
	func cancel_drag() -> bool:
		return true
var sector_editor = SectorEditorStub.new()
var system_editor = SystemEditorStub.new()

func switch_editors(what: Node):
	if what is SectorEditorStub:
		system_editor=SystemEditorStub.new()
		sector_editor=what
	elif what is SystemEditorStub:
		system_editor=what
		sector_editor=SectorEditorStub.new()
	else:
		push_error('Unrecognized type in switch_editors for node '+str(what))
		system_editor=SystemEditorStub.new()
		sector_editor=SectorEditorStub.new()

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

func get_system(): return system
func set_system(var s: String):
	var system_for_name = universe.get_child_with_name(s)
	if system_for_name:
		system = system_for_name
		player_location = universe.get_path_to(system)
	return system

func save_universe_as_json(filename: String) -> bool:
	return universe.save_as_json(filename)

func load_universe_from_json(file_path: String):
	var system_path = system.get_path() if system else NodePath()
	var player_path = player_location
	system=null
	player_location=NodePath()
	if not universe.load_from_json(file_path):
		push_error('Failed to load from json at path "'+file_path+'"')
		return false
	if player_path:
		set_player_location(player_path)
		return true
	elif system_path:
		set_system(system_path)
		return true
	else:
		var system_names = universe.get_child_names()
		if system_names:
			set_system(system_names[0])
			if system:
				push_warning('After load, system '+str(system_path)
					+' no longer exists. Will go to system '+system.get_path())
				return true
		push_error('After load, no systems exist. Universe is empty. Player is at an invalid location.')
		return false
	
func get_player_location() -> NodePath: return player_location
func set_player_location(s: NodePath):
	var n = universe.get_node_or_null(s)
	if n!=null:
		var loc = universe.get_path_to(n)
		assert(loc)
		var system_name = loc.get_name(0)
		assert(universe.has_child(system_name))
		if universe.has_child(system_name):
			system = universe.get_child_with_name(system_name)
			player_location = n.get_path()
	else:
		push_error('no SimpleNode at path '+str(s))
	return player_location

func get_player_translation(planet_time: float) -> Vector3:
	var node = universe.get_node_or_null(player_location)
	if node==null or not node.has_method('planet_translation'):
		return Vector3()
	return node.planet_translation(planet_time)

func get_space_object_unique_name() -> String:
	var n = universe.get_node_or_null(player_location)
	if n!=null and n.has_method('is_SpaceObjectData'):
		return n.make_unique_name()
	return ""

func get_space_object_or_null():
	var n = universe.get_node_or_null(player_location)
	if n!=null and n.has_method('is_SpaceObjectData'):
		return n
	push_error('SimpleNode '+str(n)+' is not a SpaceObjectData')
	return null

func get_info_or_null():
	var n: simple_tree.SimpleNode = universe.get_node_or_null(player_location)
	if n!=null and n is simple_tree.SimpleNode:
		return n
	return null

func assemble_player_ship():
	return assemble_ship(player_ship_design)

func assemble_ship(design: Dictionary):
	if not 'hull' in design or not design['hull'] is PackedScene:
		push_error('assemble_ship: no hull provided')
		return null
	var body_scene = design['hull']
	var body = body_scene.instance()
	if body == null:
		push_error('assemble_ship: cannot instance scene: '+body_scene)
		return Node.new()
	body.save_transforms()
	for child in body.get_children():
		if child is CollisionShape and child.scale.y<10:
			child.scale.y=10
		if child.name!='hull' and design.has(child.name):
			if design[child.name] is PackedScene:
				var new_child: Node = design[child.name].instance()
				if new_child!=null:
					new_child.transform = child.transform
					new_child.name = child.name
					body.remove_child(child)
					child.queue_free()
					body.add_child(new_child)
					continue
			elif design[child.name] is Array:
				for content in design[child.name]:
					if len(content)<3:
						continue
					var scene = content[2]
					if scene is PackedScene:
						var new_child: Node = scene.instance()
						if new_child!=null:
							new_child.transform = child.transform
							new_child.name = child.name+'_at_'+str(content[0])+'_'+str(content[1])
							body.add_child(new_child)
				continue
	body.pack_stats(true)
	for child in body.get_children():
		if child.has_method('is_not_mounted'):
			# Unused slots are removed to save space in the scene tree
			body.remove_child(child)
			child.queue_free()
	return body

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
	universe = Universe.new()
	tree = simple_tree.SimpleTree.new(universe)
	assert(tree.root_==universe)
	assert(universe.is_root())
	assert(universe.get_path_str()=='/root')
	universe.load_from_json('res://places/universe.json')

	set_player_location(NodePath('/root/alef_93/astra/pearl'))
	assert(player_location)
	assert(system)

	if not OS.has_feature('standalone'):
#		print('Reducing ship count for debug build')
		max_ships = debug_max_ships
		team_maximums = debug_team_maximums
	services['test'] = PlanetServices.ChildInstanceService.new(
		'Service Text',preload('res://ui/TestService.tscn'))
	services['alttest'] = PlanetServices.ChildInstanceService.new(
		'Service Button',preload('res://ui/AltTestService.tscn'))
	services['info'] = PlanetServices.PlanetDescription.new(
		'Planet Description',preload('res://ui/PlanetDescription.tscn'))
	services['shipeditor'] = PlanetServices.SceneChangeService.new(
		'Shipyard',preload('res://ui/ShipEditor.tscn'))
	make_test_designs()
