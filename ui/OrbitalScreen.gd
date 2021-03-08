extends Control

onready var SystemSelector = preload('res://ui/SystemSelector.tscn')
onready var ServiceSelector = preload('res://ui/ServiceSelector.tscn')

const ButtonPanel = preload('res://ui/ButtonPanel.tscn')

var tick: int = 0
var planet = null
var planet_info = null
var current_service: NodePath
#var old_msaa

signal jump_complete

func _ready():
	combat_engine.clear_visuals()
	var system_name = Player.system.display_name
	planet_info = Player.get_space_object_or_null()
	if planet_info==null:
		# Cannot land here
		push_error('ERROR: NULL PLANET INFO')
		game_state.change_scene('res://ui/SpaceScreen.tscn')
		return
	planet=planet_info.make_planet(600,0)
	var planet_name = planet.display_name
	planet.translation = Vector3(0,0,0)
	add_child(planet)
	camera_and_label(system_name,planet_name)
	game_state.print_to_console("Reached destination "+planet_name+" in the "+system_name+" system\n")
	$View/Port/SpaceBackground.rotate_x(PI/2-0.575959)
	$View/Port/SpaceBackground.center_view(130,90,0,100,0)
	$View/Port/SpaceBackground.update_from(Player.system)
	update_astral_gate()
	$ServiceSelector.update_service_list()
	var _discard = get_viewport().connect('size_changed',self,'force_viewport_size')
	force_viewport_size()
	_discard = Player.ship_combat_stats.erase('shields')
	_discard = Player.ship_combat_stats.erase('structure')
	if planet_info.services:
		_discard = Player.ship_combat_stats.erase('armor')
		_discard = Player.ship_combat_stats.erase('fuel')
#	old_msaa = get_viewport().msaa
#	get_viewport().msaa = Viewport.MSAA_4X

#func _exit_tree():
#	get_viewport().msaa = old_msaa

func force_viewport_size():
	$View.rect_size=get_viewport().size
	$View/Port.size = $View.rect_size

func update_astral_gate():
	if planet.has_astral_gate:
		$SystemSelector.update_system_list()
		$SystemSelector.visible=true
	else:
		$SystemSelector.visible=false

func activate_service(service_name: String,var service):
	if not service.is_available():
		return
	var service_node = get_node_or_null(current_service)
	if service_node!=null:
		service_node.queue_free()
	if service.will_change_scene():
		if OK!=service.create(get_tree()):
			printerr('Unable to start service ',service_name)
		return
	else:
		service_node = service.create(get_tree())
	if service_node!=null:
		add_child(service_node)
		current_service = get_path_to(service_node)
	else:
		current_service = NodePath()

func camera_and_label(system_name: String,planet_name: String):
	if system_name == planet_name:
		$LocationLabel.text=system_name
	else:
		$LocationLabel.text=system_name+' '+planet_name
	planet.get_sphere().scale=Vector3(6.5,6.5,6.5)
	$View/Port/Camera.set_identity()
	$View/Port/Camera.rotate_x(-0.575959)
	$View/Port/Camera.rotate_y(-0.14399)
	$View/Port/Camera.size = 15
	$View/Port/Camera.translate_object_local(Vector3(0.0,0.0,10.0))

func check_cargo_mass() -> bool:
	var design = Player.player_ship_design
	if design.cargo:
		var max_cargo = design.get_stats()['max_cargo']*1000
		if max_cargo and design.cargo.get_mass()>max_cargo:
			var panel = ButtonPanel.instance()
			panel.set_label_text("Your ship cannot fit all of it's cargo.")
			var service_names = $ServiceSelector/ServiceList.service_names
			var can_go_somewhere
			if service_names.has('shipeditor'):
				can_go_somewhere = true
				panel.add_button('Go to Shipyard','res://ui/ships/ShipDesignScreen.tscn')
			if service_names.has('market'):
				can_go_somewhere = true
				panel.add_button('Buy/Sell in Market','res://ui/commodities/TradingScreen.tscn')
			if can_go_somewhere:
				var parent = get_tree().get_root()
				parent.add_child(panel)
				panel.popup()
				while panel.visible:
					yield(get_tree(),'idle_frame')
				var result = panel.result
				parent.remove_child(panel)
				panel.queue_free()
				if result:
					game_state.call_deferred('change_scene',result)
				return false
	return true

func astral_jump(system_node_name: String,planet_location: NodePath):
	var check = check_cargo_mass()
	while check is GDScriptFunctionState and check.is_valid():
		check = yield(check,'completed')
	if not check:
		return
	Player.system=game_state.systems.get_node(system_node_name)
	Player.player_location=planet_location
#	planet.queue_free()
	planet_info = Player.get_space_object_or_null()
	var system_info = Player.system
	if planet_info==null:
		# Cannot land here
		game_state.change_scene('res://ui/SpaceScreen.tscn')
		return
	
	$View/Port/SpaceBackground.update_from(Player.system)
	yield(get_tree(),'idle_frame')
	yield(get_tree(),'idle_frame')
	
	planet=planet_info.make_planet(600,0,planet)
	planet.translation = Vector3(0,0,0)
	if system_info.display_name == planet_info.display_name:
		$LocationLabel.text=system_info.display_name
	else:
		$LocationLabel.text=planet_info.full_display_name()
	yield(get_tree(),'idle_frame')
	camera_and_label(system_info.display_name,planet.display_name)
	$ServiceSelector.update_service_list()
	update_astral_gate()
	game_state.print_to_console("Jumped to "+planet_info.display_name+" in the " \
		+system_info.display_name+" system.\n")
	emit_signal('jump_complete')

func deorbit():
	var check = check_cargo_mass()
	while check is GDScriptFunctionState and check.is_valid():
		check = yield(check,'completed')
	if not check:
		return
	Player.apply_departure()
	game_state.print_to_console('Departing '+$LocationLabel.text)
	game_state.call_deferred('change_scene','res://ui/SpaceScreen.tscn')

func _input(event):
	if event.is_action_released('ui_depart'):
		get_tree().set_input_as_handled()
		deorbit()

func _physics_process(delta):
	planet.rotate_y(0.4*delta)

func _on_MainDialogTrigger_dialog_hidden():
	get_tree().paused = false

func _on_MainDialogTrigger_dialog_shown():
	get_tree().paused = true
