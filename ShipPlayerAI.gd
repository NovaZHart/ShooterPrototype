extends Node

var target_path: NodePath setget set_target_path,get_target_path
var ui_forward: float
var ui_reverse: float
var ui_rotate: float
var ui_shoot: bool

var alive: bool = true setget set_alive, is_alive
var tick: int
var print_console_target: bool = false

const mask_all_ships_and_planets: int = 1<<29

var ship_ai = null

var ShipAI = load('res://ShipAI.gd')

var selected_position = null
var request_next_planet: bool = false
var request_next_enemy: bool = false

enum { AUTO_NOTHING=0, AUTO_INTERCEPT_TARGET=1, AUTO_EVADE=2, AUTO_LAND=4 }

var autopilot_orders = AUTO_NOTHING

func ensure_ship_ai():
	if ship_ai==null:
		ship_ai = ShipAI.new()

func update_ship_ai():
	if ship_ai==null:
		return
	if not target_path.is_empty():
		ship_ai.target_path = target_path

func set_alive(alive_: bool):
	alive=alive_

func is_alive() -> bool:
	return alive

func set_target_path(var target):
	target_path = target
	update_ship_ai()

func get_target_path() -> NodePath:
	return target_path

func _input(event: InputEvent):
	if event.is_action_pressed('ui_location_select'):
		if event is InputEventMouseButton:
			selected_position = event.position
		else:
			selected_position = get_viewport().get_mouse_position()

func _process(var _delta: float) -> void:
	if not alive:
		return
	update_ui()

func select_position(var state: PhysicsDirectBodyState,var ship,var system: Spatial):
	var pos = selected_position
	selected_position = null
	if pos==null:
		return null
	var space: PhysicsDirectSpaceState = state.get_space_state()
	var camera = system.get_main_camera()
	var from = camera.project_ray_origin(pos)
	from.y = camera.translation.y
	var to = from + camera.project_ray_normal(pos)
	to.y = camera.translation.y-30
	var there = space.intersect_ray(from,to,[ship])
	if there==null or there.empty():
		return null
	var that = there.collider
	if that.has_method('is_a_planet') and (that.is_a_planet() or that.is_a_ship()):
		return that
	return null

func update_ui() -> void:
	var left: bool = Input.is_action_pressed("ui_left")
	var right: bool = Input.is_action_pressed("ui_right")
	var up: bool = Input.is_action_pressed("ui_up")
	var down: bool = Input.is_action_pressed("ui_down")
	var deselect: bool = Input.is_action_just_released('ui_deselect_target')
	ui_forward = float(up)
	ui_reverse = float(down)
	ui_rotate = float(left)-float(right)
	ui_shoot = Input.is_key_pressed(KEY_SPACE)
	
	var cancel_autopilot: bool = up or down or left or right or deselect
	
	if not cancel_autopilot:
		if Input.is_action_just_released('ui_land'):
			if autopilot_orders & AUTO_LAND:
				request_next_planet=true
			autopilot_orders = AUTO_LAND|AUTO_INTERCEPT_TARGET
			print_console_target=true
		if Input.is_action_just_released('ui_evade'):
			autopilot_orders = AUTO_EVADE
			ensure_ship_ai()
			print_console_target=true
		if Input.is_action_just_released('ui_intercept'):
			if autopilot_orders & AUTO_INTERCEPT_TARGET:
				request_next_enemy=true
			autopilot_orders = AUTO_INTERCEPT_TARGET
			print_console_target=true
	
	if Input.is_action_just_released('ui_next_enemy'):
		request_next_enemy=true
		print_console_target=true
		if autopilot_orders & AUTO_LAND:
			cancel_autopilot = true
	elif Input.is_action_just_released('ui_next_planet'):
		request_next_planet=true
		if autopilot_orders & AUTO_LAND:
			print_console_target=true
		else:
			cancel_autopilot=true
	
	if cancel_autopilot:
		if autopilot_orders != AUTO_NOTHING:
			game_state.print_to_console('Autopilot canceled.')
		autopilot_orders = AUTO_NOTHING

func ai_step(var state: PhysicsDirectBodyState, var ship, var system: Spatial) -> void:
	tick += 1
	if not alive:
		return
	var target = select_position(state,ship,system)
	
	if target!=null:
		# Position was selected by mouse location.
		target_path=target.get_path()
		ship.emit_target_changed_signal(target_path)
		print_console_target=true
	elif request_next_planet:
		target_path = system.next_planet(target_path)
		ship.emit_target_changed_signal(target_path)
		request_next_planet=false
		print_console_target=true
	elif request_next_enemy:
		target_path = system.next_enemy(target_path,ship.enemy)
		ship.emit_target_changed_signal(target_path)
		request_next_enemy=false
		print_console_target=true
	
	if target==null and not target_path.is_empty():
		target = get_node_or_null(target_path)
		if target == null:
			target_path=NodePath() # can't intercept a dead target
			ship.emit_target_changed_signal(target_path)
	
	if autopilot_orders&AUTO_LAND:
		if target==null or not target.is_a_planet():
			target_path = system.nearest_planet(target_path,ship.translation)
			target = get_node_or_null(target_path)
			if target!=null and target.is_a_planet():
				ship.emit_target_changed_signal(target_path)
				print_console_target=true
		if target!=null and target.is_a_planet():
			if target.ship_can_land(ship):
				game_state.player_location=target.game_state_path
				ship.emit_landing_signal()
				return # Scene should end after this.
		if print_console_target:
			game_state.print_to_console('Landing on '+target.display_name)
			print_console_target=false

	var should_auto_target: bool = target!=null
	
	if autopilot_orders&AUTO_EVADE:
		ensure_ship_ai()
		ship_ai.coward_ai(state,ship,system)
		if print_console_target:
			game_state.print_to_console('Evade enemies.')
			print_console_target=false
		should_auto_target = false
	elif target!=null and autopilot_orders&AUTO_INTERCEPT_TARGET:
		should_auto_target = false
		if target.is_a_planet():
			ship_tool.move_to_intercept(ship, state, target.get_radius(),
				3, target.get_position(), Vector3(0,0,0), true)
			if print_console_target:
				game_state.print_to_console('Fly to '+target.display_name)
		else:
			ship_tool.request_move_to_attack(ship,state,target)
			if print_console_target:
				game_state.print_to_console('Intercept target.')
		print_console_target=false
	else:
		ship_tool.request_rotation(ship,state,ui_rotate)
		ship_tool.request_thrust(ship,state,ui_forward,ui_reverse)
	if ui_shoot:
		if should_auto_target and abs(ui_rotate)<1e-5:
			ship_tool.auto_fire(ship,state,target)
		else:
			ship_tool.request_primary_fire(ship,state)
