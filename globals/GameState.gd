extends Node

const standalone_max_ships_per_faction: int = 180
const standalone_max_ships: int = 300
const debug_max_ships_per_faction: int = 40
const debug_max_ships: int = 60

const EPOCH_ONE_SECOND: int = 10080 # Number of epoch ticks in one second.
# Why 10080? It is divisible by 32, 60, 90, 144, 240, and all numbers 2-10

# Game start time relative to unix epoch start, used for date strings
# Must be a multiple of 400 to ensure correct leap year calculations
const EPOCH_YEAR_SHIFT: int = 800

const EPOCH_ONE_MINUTE: int = EPOCH_ONE_SECOND*60
const EPOCH_ONE_HOUR: int = EPOCH_ONE_MINUTE*60
const EPOCH_ONE_DAY: int = EPOCH_ONE_HOUR*24

const EPOCH_GAME_START: int = 100*EPOCH_ONE_DAY+5*EPOCH_ONE_HOUR+31*EPOCH_ONE_MINUTE+30*EPOCH_ONE_SECOND

const MOUNT_FLAG_INTERNAL: int = 1
const MOUNT_FLAG_EXTERNAL: int = 2
const MOUNT_FLAG_GUN: int = 4
const MOUNT_FLAG_TURRET: int = 8
const MOUNT_FLAG_EQUIPMENT: int = 16
const MOUNT_FLAG_ENGINE: int = 32

var epoch_time: int = EPOCH_GAME_START
var max_ships: int = standalone_max_ships
var max_ships_per_faction: int = standalone_max_ships_per_faction

var Universe = preload('res://places/Universe.gd')
var PlanetServices = load('res://ui/PlanetServices.gd')

var services: Dictionary = {}
var stored_console: String = '\n'.repeat(16) setget set_stored_console,get_stored_console
var name_counter: int = 0
var sphere_xyz
var restore_from_load_page: bool = false
var input_edit_state = undo_tool.UndoStack.new(false)

var current_time_dict: Dictionary setget ,get_current_time_dict
var current_time_dict_when: int = -1

var tree
var universe
var systems
var ship_designs
var fleets
var ui
var factions
var flotsam
var asteroids

const SHIP_HEIGHT: float = 5.0 # FIXME: move this somewhere sensible

signal universe_preload
signal universe_postload
signal console_append

func get_epoch_time_at(time_dict: Dictionary):
	var in_dict = time_dict.duplicate(true)
	in_dict['year'] -= EPOCH_YEAR_SHIFT
	var unix_epoch: int = OS.get_unix_time_from_datetime(in_dict)
	var time_zone_error = OS.get_time_zone_info()
	unix_epoch += time_zone_error['bias']*3600
	return unix_epoch*EPOCH_ONE_SECOND

func get_current_time_dict():
	if not current_time_dict or current_time_dict_when!=epoch_time:
		var time_zone_error = OS.get_time_zone_info()
# warning-ignore:integer_division
		var result = OS.get_datetime_from_unix_time(epoch_time/EPOCH_ONE_SECOND-int(time_zone_error['bias']*3600))
		result['year'] += EPOCH_YEAR_SHIFT
		current_time_dict=result
	return current_time_dict

func change_scene(to):
	if get_tree().current_scene.has_method('change_scene'):
		get_tree().current_scene.change_scene(to)
		return OK
	elif to is PackedScene:
		return get_tree().change_scene_to(to)
	else:
		return get_tree().change_scene(to)

var background_cache = null setget set_background_cache, get_background_cache
var background_mutex = Mutex.new()
var starfield_cache = null setget set_starfield_cache, get_starfield_cache
var starfield_mutex = Mutex.new()

func get_background_cache():
	return background_cache
func set_background_cache(c):
	if c.bg_texture:
		background_mutex.lock()
		background_cache=c
		background_mutex.unlock()

func get_starfield_cache():
	return starfield_cache
func set_starfield_cache(c):
	if c.bg_texture:
		starfield_mutex.lock()
		starfield_cache=c
		starfield_mutex.unlock()

class CachedImage extends Reference:
	var bg_seed
	var bg_color
	var bg_texture
	var hyperspace
	func _init(bg_seed_, bg_color_, bg_texture_, hyperspace_):
		assert(bg_texture_)
		bg_seed=bg_seed_
		bg_color=bg_color_
		bg_texture=bg_texture_
		hyperspace=hyperspace_
		assert(bg_texture)

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
	func make_edited_ship_design():
		return simple_tree.SimpleNode.new()
	func cancel_drag() -> bool:
		return true

class HyperspaceStub extends Node:
	func change_selection_to(_what, _center: bool = false) -> bool:
		return true
	func deselect(_what) -> bool:
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
	func update_key_system_data(
			_path: NodePath,_property: String,_key,_value) -> bool:
		return true
	func reorder_key_space_object_data(
			_path: NodePath,_property: String,_from_key,_to_key,_shift,_undo) -> bool:
		return true
	func insert_system_data(
			_path: NodePath,_property: String,_key,_value) -> bool:
		return true
	func remove_system_data(
			_path: NodePath,_property: String,_key) -> bool:
		return true

	func update_space_object_data(_path: NodePath, _basic: bool, _visual: bool,
			_help: bool, _location: bool):
		return true
	func update_key_space_object_data(
			_path: NodePath,_property: String,_key,_value) -> bool:
		return true
	func insert_space_object_data(
			_path: NodePath,_property: String,_key,_value) -> bool:
		return true
	func remove_space_object_data(
			_path: NodePath,_property: String,_key) -> bool:
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
var hyperspace = HyperspaceStub.new()
var key_editor = KeyEditorStub.new()
var fleet_tree_selection = null
var game_editor_mode = false

var editor_stack: Array = []

func set_key_editor(what):
	key_editor = what if(what is KeyEditorStub) else KeyEditorStub.new()

func pop_editors():
	var popped = editor_stack.pop_back() if editor_stack else {}
	if popped:
		sector_editor = popped['sector_editor']
		system_editor = popped['system_editor']
		ship_editor = popped['ship_editor']
		fleet_editor = popped['fleet_editor']
		hyperspace = popped['hyperspace']
	else:
		sector_editor = SectorEditorStub.new()
		system_editor = SystemEditorStub.new()
		ship_editor = ShipEditorStub.new()
		fleet_editor = ShipEditorStub.new()
		hyperspace = HyperspaceStub.new()

func push_editors(what):
	editor_stack.push_back({
		'sector_editor': sector_editor,
		'system_editor': system_editor,
		'ship_editor': ship_editor,
		'fleet_editor': fleet_editor,
		'hyperspace': hyperspace
	})
	switch_editors(what)

func switch_editors(what):
	# FIXME: Is this needed?
	#for design in ship_designs.get_children():
	#	design.clear_cached_stats()
	sector_editor = what if(what is SectorEditorStub) else SectorEditorStub.new()
	system_editor = what if(what is SystemEditorStub) else SystemEditorStub.new()
	ship_editor = what if(what is ShipEditorStub) else ShipEditorStub.new()
	fleet_editor = what if(what is FleetEditorStub) else FleetEditorStub.new()
	hyperspace = what if(what is HyperspaceStub) else HyperspaceStub.new()

func make_unique_ship_node_name(prefix: String):
	var i: int = name_counter
	name_counter = name_counter+1
	return str(prefix)+str(i)

func print_to_console(s: String):
	if s.ends_with('\n'):
		emit_signal('console_append',s)
	else:
		emit_signal('console_append',s+'\n')
func set_stored_console(s: String): stored_console=s
func get_stored_console() -> String: return stored_console


func get_sphere_xyz():
	if not sphere_xyz:
		var xyz_data: Image = utils.native.make_lookup_tiles_c192()
		assert(xyz_data)
		var xyz: ImageTexture = ImageTexture.new()
		assert(xyz)
		xyz.create_from_image(xyz_data,Texture.FLAG_FILTER)
		sphere_xyz = xyz;
	return sphere_xyz

func save_universe_as_json(filename: String) -> bool:
	var success = universe.save_places_as_json(filename)
	if success:
		universe_edits.state.activity=false
	return success

func load_universe_from_json(file_path: String):
	emit_signal('universe_preload')
	if not universe.load_places_from_json(file_path):
		push_error('Failed to load places from json at path "'+file_path+'"')
		return false
	universe.get_tree().call_ready()
	emit_signal('universe_postload')

func assemble_ship(design_path: NodePath): # -> RigidBody or null
	var design = ship_designs.get_node_or_null(design_path)
	if not design:
		push_error('assemble_ship: path "'+str(design_path)+'" has no ship design')
		return null
	return design.assemble_ship()

func load_universe():
	# Destroy the universe:
	universe = Universe.new()
	if tree:
		tree.set_root(universe)
	else:
		tree = simple_tree.SimpleTree.new(universe)
	
	# Basic checks:
	assert(universe)
	assert(tree.root==universe)
	assert(tree.root.children_.has('ship_designs'))
	assert(tree.root.children_.has('systems'))
	assert(tree.root.children_.has('fleets'))
	assert(universe.is_root())
	assert(universe.get_path_str()=='/root')
	
	# Actually load the universe here:
	universe.load_places_from_json('res://data/')
	assert(tree.root.children_.has('ship_designs'))
	assert(tree.root.children_.has('systems'))
	
	# Make aliases for parts of the universe:
	ship_designs = universe.ship_designs
	systems = universe.systems
	fleets = universe.fleets
	flotsam = universe.flotsam
	ui = universe.ui
	factions = universe.factions
	asteroids = universe.asteroids
	
	# More basic checks:
	assert(ship_designs)
	assert(ship_designs is simple_tree.SimpleNode)
	assert(not ship_designs.has_method('is_SpaceObjectData'))
	assert(not ship_designs.has_method('is_SystemData'))

func make_services():
	services['info'] = PlanetServices.PlanetDescription.new(
		'Planet Description',preload('res://ui/PlanetDescription.tscn'))
	services['shipeditor'] = PlanetServices.SceneChangeService.new(
		'Shipyard',load('res://ui/ships/ShipDesignScreen.tscn'))
	services['market'] = PlanetServices.SceneChangeService.new(
		'Market',load('res://ui/commodities/TradingScreen.tscn'))
	
	# For debugging services code:
	services['test'] = PlanetServices.ChildInstanceService.new(
		'Service Text',preload('res://ui/TestService.tscn'))
	services['alttest'] = PlanetServices.ChildInstanceService.new(
		'Service Button',preload('res://ui/AltTestService.tscn'))

func _enter_tree():
	load_universe()
	make_services()
	if not OS.has_feature('standalone'):
		max_ships = debug_max_ships
		max_ships_per_faction = debug_max_ships_per_faction
		print('Reducing ship count for debug build: ',max_ships,' ',max_ships_per_faction)

func set_paused(v: bool):
	get_tree().paused = v
