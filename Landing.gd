extends Node

onready var SystemSelector = preload('res://SystemSelector.tscn')

var tick: int = 0
var planet = null

signal jump_complete

func _ready():
	$Console.add_text("\n".repeat(16))
	var system_name = game_state.system.display_name
	if game_state.planet_name=="":
		game_state.planet_name = game_state.system.innermost_planet(0)
	planet=game_state.system.planet_with_name(game_state.planet_name,600,0)
	var planet_name = planet.display_name
	planet.translation = Vector3(0,0,0)
	planet.name=system_name+'_'+planet.name
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

func astral_jump(system_name: String,planet_name: String):
	game_state.system=system_name
	game_state.planet_name=planet_name
	planet.queue_free()
	planet=game_state.system.planet_with_name(game_state.planet_name,600,0)
	planet.name=system_name+'_'+planet_name
	planet.translation = Vector3(0,0,0)
	add_child(planet)
	if system_name == planet_name:
		$LocationLabel.text=system_name
	else:
		$LocationLabel.text=system_name+' '+planet_name
	camera_and_label(game_state.system.display_name,planet.display_name)
	$Console.add_text("Jumped to "+planet.display_name+" in the " \
		+game_state.system.display_name+" system.\n")
	emit_signal('jump_complete')

func _process(delta):
	if Input.is_action_just_released('ui_depart'):
		var _discard=get_tree().change_scene('res://Main.tscn')
	else:
		planet.rotate_y(0.4*delta)
