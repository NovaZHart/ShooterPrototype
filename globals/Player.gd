extends Node

var player_ship_design
var system setget set_system,get_system
var player_location: NodePath = NodePath() setget set_player_location,get_player_location
var player_name = 'FIXME'

var stored_system_path
var stored_player_path

func read_save_file(filename):
	var file: File = File.new()
	if OK!=file.open(filename,File.READ):
		push_error(filename+': cannot open file for reading')
		return null
	var json_string = file.get_as_text()
	file.close()
	var parsed: JSONParseResult = JSON.parse(json_string)
	if parsed.error:
		push_error(filename+':'+str(parsed.error_line)+': '+parsed.error_string)
		return null
	return game_state.universe.decode_helper(parsed.result)

func write_save_file(state,filename) -> bool:
	var file: File = File.new()
	print('write to '+filename)
	if file.open(filename,File.WRITE)!=OK:
		push_error(filename+': cannot open file for writing')
		return false
	var encoded = game_state.universe.encode_helper(state)
	if not encoded:
		push_error(filename+': cannot encode data for writing to file')
		return false
	var json_string = JSON.print(encoded,'  ')
	if not json_string or not json_string is String:
		push_error(filename+': JSON.print could not generate JSON for file')
		return false
	file.store_string(json_string)
	file.close()
	return true

func store_state():
	var design = game_state.universe.decode_ShipDesign(
		game_state.universe.encode_ShipDesign(player_ship_design))
	return {
		'player_name': player_name,
		'player_location': player_location,
		'player_ship_design': design,
		'current_day': game_state.current_day,
	}

func restore_state(state: Dictionary):
	player_name = state['player_name']
	set_player_location(state['player_location'])
	player_ship_design = state['player_ship_design']
	game_state.current_day = state['current_day']
	player_ship_design.name = 'player_ship_design'
	var old_design = game_state.ship_designs.get_node_or_null('player_ship_design')
	if old_design:
		var _discard = game_state.ship_designs.remove_child(old_design)
	var _discard = game_state.ship_designs.add_child(player_ship_design)
	game_state.restore_from_load_page = true
	game_state.change_scene('res://ui/OrbitalScreen.tscn')

func _on_universe_preload():
	stored_system_path = system.get_path() if system else NodePath()
	stored_player_path = player_location
	system=null
	player_location=NodePath()

func _on_universe_postload():
	if stored_player_path:
		set_player_location(stored_player_path)
	elif stored_system_path:
		set_system(stored_system_path)
	else:
		var system_names = game_state.systems.get_child_names()
		if system_names:
			set_system(system_names[0])
			if system:
				push_warning('After load, system '+str(stored_system_path)
					+' no longer exists. Will go to system '+system.get_path())
				get_tree().get_root().change_scene('res://ui/OrbitalScreen.gd')
				return true
		push_error('After load, no systems exist. Universe is empty. Player is at an invalid location.')
	stored_player_path = null
	stored_system_path = null
	get_tree().get_root().change_scene('res://ui/OrbitalScreen.gd')

func get_system(): return system
func set_system(var s):
	if s is NodePath:
		var system_at_path = game_state.systems.get_node_or_null(s)
		if not system_at_path.has_method('is_SystemData'):
			push_error('Tried to go to a non-system at path '+str(s))
			return system
		system = system_at_path
	elif s is simple_tree.SimpleNode:
		var s_path = s.get_path()
		var system_at_path = game_state.systems.get_node_or_null(s_path)
		if not system_at_path.has_method('is_SystemData'):
			push_error('Specified system is not in tree at path '+str(s_path))
			return system
		system = system_at_path
	elif s is String:
		var system_for_name = game_state.systems.get_child_with_name(s)
		if system_for_name:
			system = system_for_name
			player_location = game_state.systems.get_path_to(system)
		return system


func get_player_location() -> NodePath:
	return player_location
func set_player_location(s: NodePath):
	var n = game_state.systems.get_node_or_null(s)
	if n!=null:
		var loc = game_state.systems.get_path_to(n)
		assert(loc)
		var system_name = loc.get_name(0)
		assert(game_state.systems.has_child(system_name))
		if game_state.systems.has_child(system_name):
			system = game_state.systems.get_child_with_name(system_name)
			player_location = n.get_path()
	else:
		push_error('no SimpleNode at path '+str(s))
	return player_location

func get_player_translation(planet_time: float) -> Vector3:
	var node = game_state.systems.get_node_or_null(player_location)
	if node==null or not node.has_method('planet_translation'):
		return Vector3()
	return node.planet_translation(planet_time)

func get_space_object_unique_name() -> String:
	var n = game_state.systems.get_node_or_null(player_location)
	if n!=null and n.has_method('is_SpaceObjectData'):
		return n.make_unique_name()
	return ""

func get_space_object_or_null():
	var n = game_state.systems.get_node_or_null(player_location)
	if n!=null and n.has_method('is_SpaceObjectData'):
		return n
	push_error('SimpleNode '+str(n)+' is not a SpaceObjectData')
	return null

func get_info_or_null():
	var n: simple_tree.SimpleNode = game_state.systems.get_node_or_null(player_location)
	if n!=null and n is simple_tree.SimpleNode:
		return n
	return null

func assemble_player_ship(): # -> RigidBody or null
	if not player_ship_design:
		return null
	return player_ship_design.assemble_ship()
	
	
func _init():
	assert(game_state.tree.get_node_or_null(NodePath('/root/systems/alef_93/astra/pearl')))
	var pearl = game_state.systems.get_node_or_null(NodePath('/root/systems/alef_93/astra/pearl'))
	assert(pearl)
	
	set_player_location(pearl.get_path())
	assert(player_location)
	assert(system)
	
	var banner_godship = game_state.ship_designs.get_node_or_null('godship')
	assert(banner_godship)
	player_ship_design = banner_godship
	
	var _discard = game_state.connect('universe_preload',self,'_on_universe_preload')
	_discard = game_state.connect('universe_postload',self,'_on_universe_postload')
