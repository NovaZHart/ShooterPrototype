extends Node2D

var tick: int = 0
var death_start: int = -1
var last_back_command: int = -9999
var double_down_active: bool = false
var auto_target_flag: bool = false
var ui_scroll: float = 0
var goal: int = 0
var mouse_selection: RID = RID()
var mouse_selection_mutex: Mutex = Mutex.new()

export var max_ticks_for_double_press: int = 30

# These must match src/CombatEngineData.hpp:
const PLAYER_GOAL_ATTACKER_AI: int = 1
const PLAYER_GOAL_LANDING_AI: int = 2
const PLAYER_GOAL_COWARD_AI: int = 3
const PLAYER_GOAL_INTERCEPT: int = 4
const PLAYER_ORDERS_MAX_GOALS: int = 3
const PLAYER_ORDER_FIRE_PRIMARIES: int = 1
const PLAYER_ORDER_STOP_SHIP: int = 2
const PLAYER_ORDER_MAINTAIN_SPEED: int = 4
const PLAYER_ORDER_AUTO_TARGET: int = 8
const PLAYER_TARGET_CONDITION: int = 3840
const PLAYER_TARGET_NEXT: int = 256
const PLAYER_TARGET_NEAREST: int = 512
const PLAYER_TARGET_SELECTION: int = 240
const PLAYER_TARGET_ENEMY: int = 16
const PLAYER_TARGET_FRIEND: int = 32
const PLAYER_TARGET_PLANET: int = 48
const PLAYER_TARGET_OVERRIDE: int = 64
const PLAYER_TARGET_NOTHING: int = 240

func update_pause(_delta: float) -> void:
	if Input.is_action_just_released('ui_pause'):
		get_tree().paused = not get_tree().paused
		if get_tree().paused:
			game_state.print_to_console('Pause.')
		else:
			game_state.print_to_console('Unpause.')

func _input(event: InputEvent):
	if not event.is_action_pressed('ui_location_select'):
		return
	var selected_position = null
	if event is InputEventMouseButton:
		selected_position = event.position
	else:
		selected_position = get_viewport().get_mouse_position()
	if selected_position==null:
		return
	var space: PhysicsDirectSpaceState = $System.get_world().direct_space_state
	var camera = $System.get_main_camera()
	var from = camera.project_ray_origin(selected_position)
	from.y = camera.translation.y+500
	var to = from + camera.project_ray_normal(selected_position)
	to.y = camera.translation.y-500
	var there = space.intersect_ray(from,to,[])
	if there==null or there.empty():
		return
	var that = there.collider
	if that.has_method('pack_stats'):
		mouse_selection_mutex.lock()
		mouse_selection = that.get_rid()
		mouse_selection_mutex.unlock()

func handle_zoom(_delta: float):
	var ui_zoom: int = int(Input.is_action_pressed("ui_page_up"))-int(Input.is_action_pressed("ui_page_down"))
	if Input.is_action_just_released("wheel_up"):
		ui_scroll=1.5
	if Input.is_action_just_released("wheel_down"):
		ui_scroll=-1.5
	var zoom: float = pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll)
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0
	var _zoom_level = $System.set_zoom(zoom)

func make_player_orders(_delta: float) -> Dictionary:
	if Input.is_action_just_released('ui_down'):
		if double_down_active:
			double_down_active=false
		else:
			last_back_command=tick
	
	var thrust: int = int(Input.is_action_pressed('ui_up'))-int(Input.is_action_pressed('ui_down'))
	var rotate: int = int(Input.is_action_pressed('ui_left'))-int(Input.is_action_pressed('ui_right'))
	var deselect: bool = Input.is_action_just_pressed('ui_deselect_target')
	var auto_target: bool = Input.is_action_just_pressed('ui_toggle_auto_targeting')
	var shoot: bool = Input.is_action_pressed('ui_select')
	var land: bool = Input.is_action_just_pressed('ui_land')
	var evade: bool = Input.is_action_just_pressed('ui_evade')
	var intercept: bool = Input.is_action_just_pressed('ui_intercept')
	var next_enemy: bool = Input.is_action_just_pressed('ui_next_enemy')
	var next_planet: bool = Input.is_action_just_pressed('ui_next_planet')

	
	var nearest: int = PLAYER_TARGET_NEAREST
	if Input.is_key_pressed(KEY_SHIFT):
		nearest = PLAYER_TARGET_NEXT
	
	if Input.is_action_just_pressed('ui_down') and tick-last_back_command<15:
		double_down_active=true
	
	var target_info: int = 0
	if deselect:                target_info = PLAYER_TARGET_NOTHING
	elif next_enemy:            target_info = PLAYER_TARGET_ENEMY|nearest
	elif next_planet:           target_info = PLAYER_TARGET_PLANET|nearest
	# FIXME: elif next_friend
	
	var orders: int = 0
	if shoot:                   orders = PLAYER_ORDER_FIRE_PRIMARIES
	elif double_down_active:
		orders = PLAYER_ORDER_STOP_SHIP
		thrust = 0
	elif not thrust:            orders = PLAYER_ORDER_MAINTAIN_SPEED
	
	if auto_target:
		auto_target_flag = not auto_target_flag
		if auto_target_flag:
			orders |= PLAYER_ORDER_AUTO_TARGET
	
	if thrust:              goal=0
	elif intercept:         goal=PLAYER_GOAL_INTERCEPT
	elif evade:             goal=PLAYER_GOAL_COWARD_AI
	elif land:              goal=PLAYER_GOAL_LANDING_AI
		# FIXME: elif attacker ai
	
	if not orders and land and not thrust and not goal:
		target_info = PLAYER_TARGET_PLANET|nearest
		goal=PLAYER_GOAL_INTERCEPT
	
	mouse_selection_mutex.lock()
	var target_rid = mouse_selection
	mouse_selection=RID()
	mouse_selection_mutex.unlock()
	if not target_rid.get_id() or target_rid==$System.get_player_rid():
		target_rid = $System.get_player_target_rid()
	else:
		target_info = PLAYER_TARGET_OVERRIDE
	
	var result: Dictionary = Dictionary()
	if thrust:                result['manual_thrust'] = float(thrust)
	if rotate:                result['manual_rotation'] = float(rotate)
	if orders:                result['orders'] = orders
	if target_info:           result['change_target'] = target_info
	if goal:                  result['goals'] = [goal]
	if target_rid.get_id():
		result['target_rid'] = target_rid
	return result

func _enter_tree() -> void:
#	if mesh_loader.load_meshes() != OK:
#		printerr('Could not start the mesh loader.')
	combat_engine.change_worlds(get_viewport().world)

#func _exit_tree() -> void:
#	mesh_loader.wait_for_thread()

func _process(delta: float) -> void:
	#warning-ignore:narrowing_conversion
	tick += max(1,round(delta*60.0))
	update_pause(delta)
	handle_zoom(delta)
	if get_tree().paused:
		return
	if $System.player_has_a_ship():
		$System.receive_player_orders(make_player_orders(delta))
	else:
		if death_start<0:
			death_start = tick
		if tick-death_start>300 or Input.is_action_just_released('ui_cancel'):
			var _discard = get_tree().change_scene('res://ui/OrbitalScreen.tscn')
			yield(get_tree(),'idle_frame')


# Called when the node enters the scene tree for the first time.
func _ready():
	var system_name = game_state.system.display_name
	$LocationLabel.text=system_name
	game_state.print_to_console('Entered system '+system_name)
	var _discard = $System.connect("view_center_changed",$System/Minimap,"view_center_changed")

func get_player_system() -> Node:
	return $Player
