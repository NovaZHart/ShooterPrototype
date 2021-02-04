extends Node

const standalone_team_maximums: Array = [ 200,200 ]
const standalone_max_ships: int = 300
const debug_team_maximums: Array = [35, 35]
const debug_max_ships: int = 60

var team_maximums: Array = standalone_team_maximums
var max_ships: int = standalone_max_ships

var Universe = preload('res://places/Universe.gd')
var PlanetServices = load('res://ui/PlanetServices.gd')

var system setget set_system,get_system
var player_location: NodePath = NodePath() setget set_player_location,get_player_location
var services: Dictionary = {}
var stored_console: String = '\n'.repeat(16) setget set_stored_console,get_stored_console
var name_counter: int = 0
var sphere_xyz

var input_edit_state = undo_tool.UndoStack.new(false)

var tree
var universe
var systems
var ship_designs
var fleets
var ui
var player_ship_design

signal console_append

func change_scene(to):
	if get_tree().current_scene.has_method('change_scene'):
		get_tree().current_scene.change_scene(to)
		return OK
	elif to is PackedScene:
		return get_tree().change_scene_to(to)
	else:
		return get_tree().change_scene(to)

class KeyEditorStub extends Control:
	func add_ui_for_action_event(_action: String, _event: InputEvent, _index: int) -> bool:
		return true
	func remove_ui_for_action_event(_action: String, _event: InputEvent, _index: int) -> bool:
		return true
	func change_ui_for_action_event(_action: String, _old_event: InputEvent,
			_new_event: InputEvent) -> bool:
		return true

class FleetEditorStub extends Panel:
	func select_fleet(_selection) -> bool:
		return true
	func add_fleet(_fleet) -> bool:
		return true
	func remove_fleet(_fleet_path:NodePath) -> bool:
		return true
	func set_fleet_display_name(_fleet_path:NodePath,_value:int) -> bool:
		return true
	func set_spawn_count(_fleet_path: NodePath,_design_path: NodePath,_value:int) -> bool:
		return true

class ShipEditorStub extends Panel:
	func add_item(_scene: PackedScene, _mount_name:String, _x:int, _y:int) -> bool:
		return true
	func remove_item(_scene: PackedScene, _mount_name: String, _x: int, _y: int) -> bool:
		return true
	func add_design(_design: simple_tree.SimpleNode) -> bool:
		return true
	func remove_design(_design: simple_tree.SimpleNode) -> bool:
		return true
	func set_edited_ship_display_name(_new_name: String) -> bool:
		return true
	func set_edited_ship_name(_new_name: String) -> bool:
		return true
	func set_edited_ship_design(_design: simple_tree.SimpleNode) -> bool:
		return true
	func make_edited_ship_design() -> simple_tree.SimpleNode:
		return simple_tree.SimpleNode.new()
	func cancel_drag() -> bool:
		return true

class SectorEditorStub extends Panel:
	var selection = null
	func process_if(_condition: bool) -> bool:
		return true
	func change_selection_to(_what, _center: bool = false) -> bool:
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
	func remove_spawned_fleet(_index: int) -> bool:
		return true
	func add_spawned_fleet(_index: int, _data:Dictionary) -> bool:
		return true
	func change_fleet_data(_index:int, _key:String, _value) -> bool:
		return true
var sector_editor = SectorEditorStub.new()
var system_editor = SystemEditorStub.new()
var ship_editor = ShipEditorStub.new()
var fleet_editor = ShipEditorStub.new()
var key_editor = KeyEditorStub.new()
var fleet_tree_selection = null
var game_editor_mode = false

func set_key_editor(what):
	key_editor = what if(what is KeyEditorStub) else KeyEditorStub.new()

func switch_editors(what):
	for design in ship_designs.get_children():
		design.clear_cached_stats()
	sector_editor = what if(what is SectorEditorStub) else SectorEditorStub.new()
	system_editor = what if(what is SystemEditorStub) else SystemEditorStub.new()
	ship_editor = what if(what is ShipEditorStub) else ShipEditorStub.new()
	fleet_editor = what if(what is FleetEditorStub) else FleetEditorStub.new()

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
func set_system(var s):
	if s is NodePath:
		var system_at_path = systems.get_node_or_null(s)
		if not system_at_path.has_method('is_SystemData'):
			push_error('Tried to go to a non-system at path '+str(s))
			return system
		system = system_at_path
	elif s is simple_tree.SimpleNode:
		var s_path = s.get_path()
		var system_at_path = systems.get_node_or_null(s_path)
		if not system_at_path.has_method('is_SystemData'):
			push_error('Specified system is not in tree at path '+str(s_path))
			return system
		system = system_at_path
	elif s is String:
		var system_for_name = systems.get_child_with_name(s)
		if system_for_name:
			system = system_for_name
			player_location = systems.get_path_to(system)
		return system

func get_sphere_xyz(sphere):
	if not sphere_xyz:
		var xyz_data: Image = sphere.make_lookup_tiles_c112()
		assert(xyz_data)
		var xyz: ImageTexture = ImageTexture.new()
		assert(xyz)
		xyz.create_from_image(xyz_data)
		sphere_xyz = xyz;
	return sphere_xyz

func save_universe_as_json(filename: String) -> bool:
	var success = universe.save_places_as_json(filename)
	if success:
		universe_edits.state.activity=false
	return success

func load_universe_from_json(file_path: String):
	var system_path = system.get_path() if system else NodePath()
	var player_path = player_location
	system=null
	player_location=NodePath()
	if not universe.load_places_from_json(file_path):
		push_error('Failed to load places from json at path "'+file_path+'"')
		return false
	if player_path:
		set_player_location(player_path)
		return true
	elif system_path:
		set_system(system_path)
		return true
	else:
		var system_names = systems.get_child_names()
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
	var n = systems.get_node_or_null(s)
	if n!=null:
		var loc = systems.get_path_to(n)
		assert(loc)
		var system_name = loc.get_name(0)
		assert(systems.has_child(system_name))
		if systems.has_child(system_name):
			system = systems.get_child_with_name(system_name)
			player_location = n.get_path()
	else:
		push_error('no SimpleNode at path '+str(s))
	return player_location

func get_player_translation(planet_time: float) -> Vector3:
	var node = systems.get_node_or_null(player_location)
	if node==null or not node.has_method('planet_translation'):
		return Vector3()
	return node.planet_translation(planet_time)

func get_space_object_unique_name() -> String:
	var n = systems.get_node_or_null(player_location)
	if n!=null and n.has_method('is_SpaceObjectData'):
		return n.make_unique_name()
	return ""

func get_space_object_or_null():
	var n = systems.get_node_or_null(player_location)
	if n!=null and n.has_method('is_SpaceObjectData'):
		return n
	push_error('SimpleNode '+str(n)+' is not a SpaceObjectData')
	return null

func get_info_or_null():
	var n: simple_tree.SimpleNode = systems.get_node_or_null(player_location)
	if n!=null and n is simple_tree.SimpleNode:
		return n
	return null

func assemble_player_ship(): # -> RigidBody or null
	if not player_ship_design:
		return null
	return player_ship_design.assemble_ship()

func assemble_ship(design_path: NodePath): # -> RigidBody or null
	var design = ship_designs.get_node_or_null(design_path)
	if not design:
		push_error('assemble_ship: path "'+str(design_path)+'" has no ship design')
		return null
	return design.assemble_ship()

func _init():
	universe = Universe.new()
	tree = simple_tree.SimpleTree.new(universe)
	assert(tree.root_==universe)
	assert(tree.root_.children_.has('ship_designs'))
	assert(tree.root_.children_.has('systems'))
	assert(tree.root_.children_.has('fleets'))
	assert(universe.is_root())
	assert(universe.get_path_str()=='/root')
	universe.load_places_from_json('res://places/universe.json')
	assert(tree.root_.children_.has('ship_designs'))
	assert(tree.root_.children_.has('systems'))
	ship_designs = universe.ship_designs
	systems = universe.systems
	fleets = universe.fleets
	ui = universe.ui
	assert(ship_designs)
	assert(ship_designs is simple_tree.SimpleNode)
	assert(not ship_designs.has_method('is_SpaceObjectData'))
	assert(not ship_designs.has_method('is_SystemData'))

#	assert(systems.get_child_with_name('alef_93'))
#	assert(systems.get_node_or_null(NodePath('alef_93')))
#	assert(systems.get_node_or_null(NodePath('alef_93/astra')))
	assert(tree.root_.children_.has('ship_designs'))
	assert(tree.root_.children_.has('systems'))
	assert(tree.get_node_or_null(NodePath('/root/systems/alef_93/astra/pearl')))
	var pearl = systems.get_node_or_null(NodePath('/root/systems/alef_93/astra/pearl'))
	assert(pearl)
	set_player_location(pearl.get_path())
	assert(player_location)
	assert(system)

	var banner_godship = ship_designs.get_node_or_null('godship')
	assert(banner_godship)
	player_ship_design = banner_godship

	if not OS.has_feature('standalone'):
		max_ships = debug_max_ships
		team_maximums = debug_team_maximums
		print('Reducing ship count for debug build: ',max_ships,' ',team_maximums)
	services['test'] = PlanetServices.ChildInstanceService.new(
		'Service Text',preload('res://ui/TestService.tscn'))
	services['alttest'] = PlanetServices.ChildInstanceService.new(
		'Service Button',preload('res://ui/AltTestService.tscn'))
	services['info'] = PlanetServices.PlanetDescription.new(
		'Planet Description',preload('res://ui/PlanetDescription.tscn'))
	services['shipeditor'] = PlanetServices.SceneChangeService.new(
		'Shipyard',load('res://ui/ships/ShipDesignScreen.tscn'))
	
