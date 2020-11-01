extends Node

onready var SystemSelector = preload('res://SystemSelector.tscn')

var tick: int = 0
var planet = null

signal jump_complete

func _ready():
	$Console.add_text("\n".repeat(16))
	var system_name = game_state.system.display_name
	var planet_info = game_state.get_planet_info_or_null()
	if planet_info==null:
		# Cannot land here
		print('ERROR: NULL PLANET INFO')
		var _discard=get_tree().change_scene('res://Main.tscn')
		return
	planet=planet_info.make_planet(600,0)
	var planet_name = planet.display_name
	planet.translation = Vector3(0,0,0)
	add_child(planet)
	camera_and_label(system_name,planet_name)
	$Console.add_text("Reached destination "+planet_name+" in the "+system_name+" system\n")
	$SpaceBackground.rotate_x(PI/2-0.575959)
	$SpaceBackground.center_view(130,90,100)
	if planet.has_astral_gate:
		var selector = SystemSelector.instance()
		var system_list = selector.get_node('SystemList')
		var _discard = system_list.connect('astral_jump',self,'astral_jump')
		_discard = connect('jump_complete',system_list,'update_selectability')
		add_child(selector)

func camera_and_label(system_name: String,planet_name: String):
	if system_name == planet_name:
		$LocationLabel.text=system_name
	else:
		$LocationLabel.text=system_name+' '+planet_name
	planet.get_sphere().scale=Vector3(7,7,7)
	$Camera.set_identity()
	$Camera.rotate_x(-0.575959)
	$Camera.rotate_y(-0.14399)
	$Camera.size = 15
	$Camera.translate_object_local(Vector3(0.0,0.0,10.0))

func astral_jump(system_node_name: String,planet_location: NodePath):
	game_state.system=game_state.get_node(system_node_name)
	game_state.player_location=planet_location
	planet.queue_free()
	var planet_info = game_state.get_planet_info_or_null()
	var system_info = game_state.system
	if planet_info==null:
		# Cannot land here
		var _discard=get_tree().change_scene('res://Main.tscn')
	planet=planet_info.make_planet(600,0)
	planet.translation = Vector3(0,0,0)
	add_child(planet)
	if system_info.display_name == planet_info.display_name:
		$LocationLabel.text=system_info.display_name
	else:
		$LocationLabel.text=planet_info.full_display_name()
	camera_and_label(system_info.display_name,planet.display_name)
	$Console.add_text("Jumped to "+planet_info.display_name+" in the " \
		+system_info.display_name+" system.\n")
	emit_signal('jump_complete')

func _process(delta):
	if Input.is_action_just_released('ui_depart'):
		var _discard=get_tree().change_scene('res://Main.tscn')
	else:
		planet.rotate_y(0.4*delta)
