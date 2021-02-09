extends game_state.HyperspaceStub

export var max_ticks_for_double_press: int = 30
export var min_sun_height: float = 50.0
export var max_sun_height: float = 1e5
export var min_camera_size: float = 25
export var max_camera_size: float = 150

# These must match src/CombatEngineData.hpp:
const PLAYER_GOAL_LANDING_AI: int = 2
const PLAYER_ORDERS_MAX_GOALS: int = 3
const PLAYER_ORDER_STOP_SHIP: int = 2
const PLAYER_ORDER_MAINTAIN_SPEED: int = 4
const PLAYER_TARGET_CONDITION: int = 3840
const PLAYER_TARGET_NEXT: int = 256
const PLAYER_TARGET_NEAREST: int = 512
const PLAYER_TARGET_SELECTION: int = 240
const PLAYER_TARGET_PLANET: int = 48
const PLAYER_TARGET_OVERRIDE: int = 64
const PLAYER_TARGET_NOTHING: int = 240

const SystemEntrance = preload('res://places/SystemEntrance.tscn')
const player_ship_name: String = 'player_ship' # name of player's ship node

var ui_scroll: float = 0.0
var visual_tick: int = 0
var mouse_selection_mutex: Mutex = Mutex.new()
var mouse_selection: RID = RID()
var mouse_deselect: bool = false
var last_back_command: int = -9999
var double_down_active: bool = false
var goal: int = 0
var pause_mutex: Mutex = Mutex.new()
var dialog_paused: bool = false
var was_paused: bool = false

var player_orders: Array = Array()
var player_orders_mutex: Mutex = Mutex.new()
var old_target_fps
var physics_tick: int = 0
var sent_systems_and_player: bool = false
var combat_engine_mutex: Mutex = Mutex.new()
var latest_target_info: Dictionary = Dictionary()
var ship_stats: Dictionary = {}
var first_visual_tick = true

signal view_center_changed

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
	var space: PhysicsDirectSpaceState = get_world().direct_space_state
	var camera = $TopCamera
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
		mouse_deselect = false
		mouse_selection_mutex.unlock()

func _on_destination_system_changed(path: NodePath):
	var data_node = game_state.systems.get_node_or_null(path)
	if data_node and data_node.has_method('is_SystemData'):
		var scene_node = $Systems.get_node_or_null(data_node.name)
		if scene_node and scene_node is Area:
			mouse_selection_mutex.lock()
			mouse_selection = scene_node.get_rid()
			mouse_deselect = false
			mouse_selection_mutex.unlock()
			return
	
	mouse_selection_mutex.lock()
	mouse_selection = RID()
	mouse_deselect = true
	mouse_selection_mutex.unlock()

func clear():
	combat_engine_mutex.lock()
	combat_engine.clear_ai()
	
	for ship in $Ships.get_children():
		ship.queue_free()
	for planet in $Systems.get_children():
		planet.queue_free()
	combat_engine_mutex.unlock()

func make_player_orders(_delta: float) -> Dictionary:
	if Input.is_action_just_released('ui_down'):
		if double_down_active:
			double_down_active=false
		else:
			last_back_command=visual_tick
	
	var thrust: int = int(Input.is_action_pressed('ui_up'))-int(Input.is_action_pressed('ui_down'))
	var rotate: int = int(Input.is_action_pressed('ui_left'))-int(Input.is_action_pressed('ui_right'))
	var land: bool = Input.is_action_just_pressed('ui_land')
	var next_planet: bool = Input.is_action_just_pressed('ui_next_planet')
	var deselect: bool = Input.is_action_just_pressed('ui_deselect_target')
	
	var nearest: int = PLAYER_TARGET_NEAREST
	if Input.is_key_pressed(KEY_SHIFT):
		nearest = PLAYER_TARGET_NEXT
	
	if Input.is_action_just_pressed('ui_down') and visual_tick-last_back_command<15:
		double_down_active=true

	mouse_selection_mutex.lock()
	var target_rid = mouse_selection
	deselect = deselect or mouse_deselect
	mouse_selection = RID()
	mouse_deselect = false
	mouse_selection_mutex.unlock()

	var target_info: int = 0
	if deselect:                target_info = PLAYER_TARGET_NOTHING
	elif next_planet:           target_info = PLAYER_TARGET_PLANET|nearest

	var orders: int = 0
	if double_down_active:
		orders = PLAYER_ORDER_STOP_SHIP
		thrust = 0
	elif not thrust:            orders = PLAYER_ORDER_MAINTAIN_SPEED

	if thrust:              goal=0
	elif land:              goal=PLAYER_GOAL_LANDING_AI
	
	if first_visual_tick:
		var node = $Systems.get_node_or_null(Player.system.name)
		if node==null or not node is Area:
			push_warning('Cannot find system '+Player.system.name)
		else:
			target_info = PLAYER_TARGET_OVERRIDE
			target_rid = node.get_rid()
	elif target_rid.get_id() and target_rid!=get_player_rid():
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
	game_state.switch_editors(self)
	combat_engine.change_worlds(get_viewport().world)
	old_target_fps = Engine.target_fps
	Engine.target_fps = Engine.iterations_per_second

func _exit_tree():
	game_state.switch_editors(null)
	if old_target_fps != null:
		Engine.target_fps = old_target_fps
	Player.disconnect('destination_system_changed',self,'_on_destination_system_changed')

func change_selection_to(new_selection,_center: bool = false) -> bool:
	game_state.universe.lock()
	Player.destination_system = new_selection.get_path()
	game_state.universe.unlock()
	return true

func _process(delta: float) -> void:
	#warning-ignore:narrowing_conversion
	visual_tick += max(1,round(delta*60.0))
	if dialog_paused:
		return
	first_visual_tick = false
	combat_engine.draw_space($TopCamera,get_tree().root)
	update_pause(delta)
	handle_zoom(delta)
	if get_tree().paused:
		return
	receive_player_orders(make_player_orders(delta))
	center_view()

func _ready():
	var player_ship = Player.assemble_player_ship()
	player_ship.name = player_ship_name
	player_ship.translation = Player.system.position*20
	player_ship.translation.y = 10
	if OK!=Player.connect('destination_system_changed',self,'_on_destination_system_changed'):
		push_error("Cannot connect to Player destination_system_changed signal.")
	$Ships.add_child(player_ship)
	for system_name in game_state.systems.get_child_names():
		var system_entrance = SystemEntrance.instance()
		if system_entrance.init_system(system_name):
			$Systems.add_child(system_entrance)
			print('Add system entrance at ',system_entrance.translation)
		else:
			push_warning(system_name+': could not add system')
	_on_destination_system_changed(Player.destination_system)

func pack_ship_stats_if_not_sent():
	if not sent_systems_and_player:
		var player_ship = $Ships.get_node_or_null(player_ship_name)
		return [ player_ship.pack_stats() ]
	return []

func pack_system_stats_if_not_sent() -> Array:
	var new_planets_packed: Array = []
	if not sent_systems_and_player:
		for planet in $Systems.get_children():
			new_planets_packed.append(planet.pack_stats())
	return new_planets_packed

func get_world():
	return get_viewport().get_world()
func get_player_rid() -> RID:
	var player_ship = $Ships.get_node_or_null(player_ship_name)
	return RID() if player_ship==null else player_ship.get_rid()

func get_player_target_rid() -> RID:
	var new_target = latest_target_info.get('new','')
	var target_ship = $Ships.get_node_or_null(new_target)
	if target_ship!=null:
		return target_ship.get_rid()
	var target_planet = $Systems.get_node_or_null(new_target)
	if target_planet!=null:
		return target_planet.get_rid()
	return RID() 

func _physics_process(delta):
	combat_engine_mutex.lock()
	physics_tick += 1
	
	var new_ships_packed: Array = pack_ship_stats_if_not_sent().duplicate(true)
	var new_systems_packed: Array = pack_system_stats_if_not_sent().duplicate(true)
	if not sent_systems_and_player:
		print('new systems paced: ',new_systems_packed)
	sent_systems_and_player = true
	
	var player_ship = $Ships.get_node_or_null(player_ship_name)
	var player_ship_rid = RID() if player_ship==null else player_ship.get_rid()
	var old_player_target_name = ''
	if ship_stats.has(player_ship_name):
		old_player_target_name = ship_stats[player_ship_name].get('target_name','')
	
	player_orders_mutex.lock()
	var orders_copy: Array = player_orders.duplicate(true)
	player_orders_mutex.unlock()
	
	var space: PhysicsDirectSpaceState = get_world().direct_space_state

	var update_request_rids = [ player_ship_rid ]

	var result: Dictionary = combat_engine.ai_step(
		delta,new_ships_packed,new_systems_packed,
		orders_copy,player_ship_rid,space,update_request_rids)
	
	var player_died: bool = $Ships.get_node_or_null(player_ship_name) == null
	for ship_name in result.keys():
		var ship: Dictionary = result[ship_name]
		var fate: int = ship.get('fate',combat_engine.FATED_TO_FLY)
		if fate<=0:
			continue # ship is still flying
		player_died = player_died or ship_name == player_ship_name
		var ship_node = $Ships.get_node_or_null(ship_name)
		if ship_node==null:
			continue
		if ship_name==player_ship_name:
			#emit_signal('player_target_changed',self) # remove target display (if any)
			if fate==combat_engine.FATED_TO_LAND:
				var planet_name = ship.get('target_name','no-name')
				var node = $Systems.get_node_or_null(planet_name)
				if node==null:
					push_warning('SYSTEM '+planet_name+' HAS NO NODE!')
				else:
					Player.player_location=node.game_state_path
				clear()
				game_state.call_deferred('change_scene','res://ui/SpaceScreen.tscn')
				return
		ship_node.call_deferred("queue_free")
	if not player_died:
		# Update target information.
		var new_player_target_name = result.get(player_ship_name,{}).get('target_name','')
		latest_target_info = {'old':old_player_target_name, 'new':new_player_target_name}
		if new_player_target_name!=old_player_target_name:
			var old_target = game_state.systems.get_node_or_null(Player.destination_system)
			var new_target = game_state.systems.get_child_with_name(new_player_target_name)
			if new_target and physics_tick>5:
				print('new target')
				universe_edits.state.push(universe_edits.ChangeSelection.new(
					old_target,new_target))

	
	var _discard = result.erase('weapon_rotations')
	ship_stats = result
	
	combat_engine_mutex.unlock()

func set_zoom(zoom: float,original: float=-1) -> void:
	var from: float = original if original>1 else $TopCamera.size
	$TopCamera.size = clamp(zoom*from,min_camera_size,max_camera_size)

func center_view(center=null) -> void:
	if center==null:
		var player_ship = $Ships.get_node_or_null(player_ship_name)
		var center_object = $TopCamera 
		if player_ship!=null:
			center_object=player_ship
		center = center_object.translation
	var size=$TopCamera.size
	$TopCamera.translation = Vector3(center.x, 50, center.z)
	$SpaceBackground.center_view(center.x,center.z,0,size,30)
	$Minimap.view_center_changed(Vector3(center.x,50,center.z),Vector3(size,0,size))
	emit_signal('view_center_changed',Vector3(center.x,50,center.z),Vector3(size,0,size))

func receive_player_orders(new_orders: Dictionary) -> void:
	var player_ship = $Ships.get_node_or_null(player_ship_name)
	if player_ship!=null:
		var rid: RID = player_ship.get_rid()
		var id: int = rid.get_id()
		new_orders['rid_id'] = id
	else:
		new_orders['rid_id'] = 0
	player_orders_mutex.lock()
	player_orders = [new_orders]
	player_orders_mutex.unlock()

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
	set_zoom(zoom)

func update_pause(_delta: float) -> void:
	if Input.is_action_just_released('ui_pause'):
		pause_mutex.lock()
		if not dialog_paused:
			get_tree().paused = not get_tree().paused
			if get_tree().paused:
				game_state.print_to_console('Pause.')
			else:
				game_state.print_to_console('Unpause.')
		pause_mutex.unlock()

func _on_MainDialogTrigger_dialog_hidden():
	game_state.switch_editors(self)
	pause_mutex.lock()
	get_tree().paused = was_paused
	dialog_paused = false
	pause_mutex.unlock()

func _on_MainDialogTrigger_dialog_shown():
	pause_mutex.lock()
	was_paused = get_tree().paused
	dialog_paused = true
	get_tree().paused = true
	pause_mutex.unlock()
