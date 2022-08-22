extends Control

onready var SystemSelector = preload('res://ui/SystemSelector.tscn')
onready var ServiceSelector = preload('res://ui/ServiceSelector.tscn')

const ButtonPanel = preload('res://ui/ButtonPanel.tscn')

var tick: int = 0
var planet: KinematicBody
var planet_info = null
var current_service: NodePath
var axial_tilt: float = 0.0
var planet_rotation: float = 0.0
var planet_translation: Vector3 = Vector3(50,0,-86.6)
export var camera_distance_ratio: float = 7
export var space_background_scale: float = 0.333
export var angular_velocity: float = 0.5
#var old_msaa

signal jump_complete

var system_name
var planet_name

func _enter_tree():
	combat_engine.clear_visuals()
	system_name = Player.system.display_name
	planet_info = Player.get_space_object_or_null()
	if planet_info==null:
		# Cannot land here
		push_error('ERROR: NULL PLANET INFO')
		game_state.change_scene('res://ui/SpaceScreen.tscn')
		return
	planet=planet_info.make_planet(600,0)
	planet_name = planet.display_name
	axial_tilt = planet_info.axial_tilt
	var d: float = planet_info.planet_translation(game_state.epoch_time*game_state.EPOCH_ONE_DAY).length()
	planet_translation = Vector3(d/sqrt(2),0,-d/sqrt(2))
	planet.translation = planet_translation
	planet.update_ring_shading()
	$View/Port.add_child(planet)

func _ready():
	camera_and_label(system_name,planet_name)
	game_state.print_to_console("Reached destination "+planet_name+" in the "+system_name+" system\n")
	#$View/Port/SpaceBackground.rotate_x(PI/2-0.575959)
	$View/Port/SpaceBackground.center_view(130,90,0,100,0)
	#$View/Port/SpaceBackground.update_from(Player.system)
	update_astral_gate()
	$ServiceSelector.update_service_list()
	var _discard = get_viewport().connect('size_changed',self,'force_viewport_size')
	force_viewport_size()
	_discard = Player.ship_combat_stats.erase('shields')
	_discard = Player.ship_combat_stats.erase('structure')
	if planet_info.services:
		_discard = Player.ship_combat_stats.erase('armor')
		_discard = Player.ship_combat_stats.erase('fuel')

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

# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
func camera_and_label(system_name: String,planet_name: String):
	if system_name == planet_name:
		$Labels/LocationLabel.text=system_name
	else:
		$Labels/LocationLabel.text=system_name+' '+planet_name
	var s: float = 4.5*max(min(2,log(planet.get_sphere().scale.x)*0.666),1)
	planet.get_sphere().scale=Vector3(s,s,s)
	var shift: float = camera_distance_ratio*sqrt(2)
	$View/Port/Camera.transform.basis = Basis().rotated(Vector3(1,0,0),-PI/4)
	$View/Port/Camera.transform.origin = Vector3(planet_translation.x,shift,planet_translation.z+shift)
	#$View/Port/Camera.size = 15
#	$View/Port/SpaceBackground.transform = Transform()
	$View/Port/SpaceBackground.transform = Transform(Basis(Vector3(PI/4,0,0)),Vector3(planet_translation.x-shift,-shift,planet_translation.z-4*shift))
	$View/Port/SpaceBackground.rotation.x = PI/4
	$View/Port/SpaceBackground.scale=Vector3(space_background_scale,space_background_scale,space_background_scale)
#	$View/Port/SpaceBackground.transform.basis = Basis().rotated(Vector3(1,0,0),PI/4)

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
	planet.translation = planet_translation
	if system_info.display_name == planet_info.display_name:
		$Labels/LocationLabel.text=system_info.display_name
	else:
		$Labels/LocationLabel.text=planet_info.full_display_name()
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
	game_state.print_to_console('Departing '+$Labels/LocationLabel.text)
	game_state.call_deferred('change_scene','res://ui/SpaceScreen.tscn')

func _input(event):
	if event.is_action_released('ui_depart'):
		get_tree().set_input_as_handled()
		deorbit()

func _process(delta):
	planet_rotation += angular_velocity*delta
	var t: Basis = Basis()
	t=t.rotated(Vector3(0,1,0),planet_rotation)
	t=t.rotated(Vector3(0,0,1),axial_tilt)
	planet.transform.basis = t
#	var rotation_axis: Vector3 = Vector3(0,1,0).rotated(Vector3(0,0,1),axial_tilt)
#	planet.transform = planet.transform.rotated(rotation_axis,planet_rotation)
#	planet.rotation = Vector3(0,1,0).rotated(rotation_axis,planet_rotation)
#	print(planet.rotation)

func _on_MainDialogTrigger_dialog_hidden():
	get_tree().paused = false

func _on_MainDialogTrigger_dialog_shown():
	get_tree().paused = true
