extends Node

var target_path: NodePath setget set_target_path,get_target_path
var ui_forward: float
var ui_reverse: float
var ui_rotate: float
var ui_shoot: bool

var alive: bool = true setget set_alive, is_alive
var tick: int

var ship_ai = null

var ShipAI = load('res://ShipAI.gd')

var request_next_planet: bool = false
var request_next_enemy: bool = false

enum { AUTO_NOTHING=0, AUTO_INTERCEPT_TARGET=1, AUTO_EVADE=2, AUTO_LAND=4 }

var autopilot_orders = AUTO_NOTHING

signal console
signal land

func ensure_ship_ai():
	if ship_ai==null:
		ship_ai = ShipAI.new()
		add_child(ship_ai)

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

func _process(var _delta: float) -> void:
	if not alive:
		return
	tick += 1
	var left: bool = Input.is_action_pressed("ui_left")
	var right: bool = Input.is_action_pressed("ui_right")
	var up: bool = Input.is_action_pressed("ui_up")
	var down: bool = Input.is_action_pressed("ui_down")
	ui_forward = float(up)
	ui_reverse = float(down)
	ui_rotate = float(left)-float(right)
	ui_shoot = Input.is_key_pressed(KEY_SPACE)
	
	var cancel_autopilot: bool = up or down or left or right
	
	if Input.is_action_just_released('ui_land'):
		autopilot_orders = AUTO_LAND|AUTO_INTERCEPT_TARGET
	if Input.is_action_just_released('ui_evade'):
		autopilot_orders = AUTO_EVADE
		ensure_ship_ai()
	if Input.is_action_just_released('ui_intercept'):
		autopilot_orders = AUTO_INTERCEPT_TARGET
	
	if cancel_autopilot:
		autopilot_orders = AUTO_NOTHING
	
	if Input.is_action_just_released('ui_next_enemy'):
		request_next_enemy=true
	elif Input.is_action_just_released('ui_next_planet'):
		request_next_planet=true

func ai_step(var state: PhysicsDirectBodyState, var ship, var system: Spatial) -> void:
	if not alive:
		return
	if request_next_enemy:
		target_path = system.next_enemy(target_path,ship.enemy)
		request_next_enemy=false
	if request_next_planet:
		target_path = system.next_planet(target_path)
		request_next_planet=false
	var target = null
	if not target_path.is_empty():
		target = get_node_or_null(target_path)
		if target == null:
			target_path=NodePath() # can't intercept a dead target
	
	if autopilot_orders&AUTO_LAND:
		if target==null or not target.is_a_planet():
			target_path = system.nearest_planet(target_path,ship.translation)
			target = get_node_or_null(target_path)
		if target!=null and target.is_a_planet():
			if target.ship_can_land(ship):
				game_state.player_location=target.game_state_path
				emit_signal('land')
				return # Scene should end after this.

	var should_auto_target: bool = target!=null
	
	if autopilot_orders&AUTO_EVADE:
		ensure_ship_ai()
		ship_ai.coward_ai(state,ship,system)
		should_auto_target = false
	elif target!=null and autopilot_orders&AUTO_INTERCEPT_TARGET:
		should_auto_target = false
		if target.is_immobile():
			var tgt_pos: Vector3 = target.position_at_time(0)
			ship.request_stop(tgt_pos,state,system)
		else:
			ship.request_move_to_attack(state,target)
	else:
		ship.request_rotation(state,ui_rotate)
		ship.request_thrust(state,ui_forward,ui_reverse)
	if ui_shoot:
		if should_auto_target and abs(ui_reverse)<1e-5:
			ship.auto_fire(state,target)
		else:
			ship.request_primary_fire(state)
