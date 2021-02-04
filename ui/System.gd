extends Node

export var min_sun_height: float = 50.0
export var max_sun_height: float = 1e5
export var min_camera_size: float = 25
export var max_camera_size: float = 150
export var max_new_ships_per_tick: int = 1

var combat_engine_mutex: Mutex = Mutex.new()
var visual_tick: int = 0
var physics_tick: int = 0
var new_ships: Array = Array()
var new_ships_mutex: Mutex = Mutex.new()
var player_orders: Array = Array()
var player_orders_mutex: Mutex = Mutex.new()
var ship_stats_requests: Dictionary = Dictionary()
var ship_stats_requests_mutex: Mutex = Mutex.new()

#var terminate_ship_maker: bool = false
#var ship_maker_thread: Thread = Thread.new()
var ships_to_spawn: Array = Array()
var ship_maker_mutex: Mutex = Mutex.new()

var team_stats: Array = [{'count':0,'threat':0},{'count':0,'threat':0}]
var team_stats_mutex: Mutex = Mutex.new()

var ship_stats: Dictionary = {}
const player_ship_name: String = 'player_ship' # name of player's ship node

var sent_planets: bool = false
var latest_target_info: Dictionary = Dictionary()

var Landing = preload('res://ui/OrbitalScreen.tscn')
var TargetDisplay = preload('res://ui/TargetDisplay.tscn')

var old_target_fps = null

signal view_center_changed          #<-- visual thread
signal player_ship_stats_updated    #<-- visual thread
signal player_target_stats_updated  #<-- visual thread
signal player_target_changed        #<-- visual thread and clear()

func get_world():
	return get_viewport().get_world()

func _enter_tree():
	old_target_fps = Engine.target_fps
	Engine.target_fps = Engine.iterations_per_second

func _exit_tree():
	if old_target_fps != null:
		Engine.target_fps = old_target_fps

func player_has_a_ship() -> bool:
	return $Ships.get_node_or_null(player_ship_name)!=null

func update_space_background(from=null):
	if from==null:
		from=game_state.system
	var result = $SpaceBackground.update_from(from)
	while result is GDScriptFunctionState and result.is_valid():
		result = yield(result,'completed')
	if not result:
		push_error('space background regeneration failed')

func get_player_rid() -> RID:
	var player_ship = $Ships.get_node_or_null(player_ship_name)
	return RID() if player_ship==null else player_ship.get_rid()

func get_player_target_rid() -> RID:
	var new_target = latest_target_info.get('new','')
	var target_ship = $Ships.get_node_or_null(new_target)
	if target_ship!=null:
		return target_ship.get_rid()
	var target_planet = $Planets.get_node_or_null(new_target)
	if target_planet!=null:
		return target_planet.get_rid()
	return RID() 

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

func ship_stats_by_team():
	team_stats_mutex.lock()
	var result = team_stats.duplicate(true)
	team_stats_mutex.unlock()
	return result
#	var results: Dictionary = {}
#	for i in range(2): # range(max_teams)
#		results[i] = {'count':0,'threat':0}
#	for ship in $Ships.get_children():
#		results[ship.team]['count'] += 1
#		results[ship.team]['threat'] += max(0,ship.combined_stats.get('threat',0))
#	return results

func add_ship_stat_request(ship_name: String) -> void:
	ship_stats_requests_mutex.lock()
	ship_stats_requests[ship_name]=1
	ship_stats_requests_mutex.unlock()
	
func remove_ship_stat_request(ship_name: String) -> void:
	ship_stats_requests_mutex.lock()
	var _discard = ship_stats_requests.erase(ship_name)
	ship_stats_requests_mutex.unlock()

func sync_Ships_with_stat_requests() -> void:
	# Remove non-existent ships from the ship stats requests:
	var new_requests: Dictionary = Dictionary()
	ship_stats_requests_mutex.lock()
	var keys=ship_stats_requests.keys()
	ship_stats_requests_mutex.unlock()
	for ship_name in keys:
		if $Ships.get_node_or_null(ship_name)!=null or \
				$Planets.get_node_or_null(ship_name)!=null:
			new_requests[ship_name]=1
	ship_stats_requests_mutex.lock()
	ship_stats_requests=new_requests
	ship_stats_requests_mutex.unlock()

func _process(_delta) -> void:
	visual_tick += 1
	assert($TopCamera!=null)
	combat_engine.draw_space($TopCamera,get_tree().root)
	
	if ship_stats==null:
		return
	
	var player_ship_stats = ship_stats.get(player_ship_name,null)
	if player_ship_stats==null:
		return

	emit_signal('player_ship_stats_updated',player_ship_stats)
	center_view()

	var target_ship_stats = ship_stats.get(player_ship_stats.get('target_name',''),null)
	if target_ship_stats != null:
		emit_signal('player_target_stats_updated',target_ship_stats)

	sync_Ships_with_stat_requests()

	var target_info: Dictionary = latest_target_info.duplicate(true)
	if target_info.get('old','') != target_info.get('new',''):
		# The target has changed, so we need a new TargetDisplay.
		update_target_display(target_info['old'],target_info['new'])

func update_target_display(old_target_name: String,new_target_name: String) -> void:
	assert(old_target_name!=new_target_name)
	remove_ship_stat_request(old_target_name)
	emit_signal('player_target_changed',self) # remove old display
	var new_target = $Ships.get_node_or_null(new_target_name)
	if new_target==null:
		new_target = $Planets.get_node_or_null(new_target_name)
	if new_target==null:
		return # target does not exist, so don't make a new target display.
	add_ship_stat_request(new_target_name)
	var display = TargetDisplay.instance()
	var _discard=connect('player_target_changed',display,'player_target_changed')
	_discard = connect('player_target_stats_updated',display,'player_target_stats_updated')
	new_target.call_deferred('add_child',display)

func pack_ship_stats() -> Array:
	new_ships_mutex.lock()
	var my_new_ships = new_ships.duplicate(true)
	new_ships.clear()
	new_ships_mutex.unlock()

	var threats: Array = [0, 0]
	var new_ships_packed: Array = []
	for ship in my_new_ships:
		if ship!=null and ship is RigidBody:
			new_ships_packed.append(ship.pack_stats())
			threats[ship.team] += max(0,ship.combined_stats.get('threat',0))

	team_stats_mutex.lock()
	# Count was incremented in _physics_process
	for team in range(len(threats)):
		team_stats[team]['threat'] += threats[team]
	team_stats_mutex.unlock()

	return new_ships_packed

func pack_planet_stats_if_not_sent() -> Array:
	var new_planets_packed: Array = []
	if not sent_planets:
		for planet in $Planets.get_children():
			new_planets_packed.append(planet.pack_stats())
		sent_planets = true
	return new_planets_packed

#func make_ships(_ignored):
#	while not terminate_ship_maker:
#		ship_maker_mutex.lock()
#		var spawn_me = ships_to_spawn.pop_front()
#		ship_maker_mutex.unlock()
#		if spawn_me==null:
#			OS.delay_usec(100)
#		else:
#			callv(spawn_me[0],spawn_me.slice(1,len(spawn_me)))

func _physics_process(delta):
	physics_tick += 1
	
	var make_me: Array = game_state.system.process_space(self,delta)
	
	team_stats_mutex.lock()
	for ship in make_me:
		var team: int = ship[4] # "team" argument to spawn_ship
		team_stats[team]['count']+=1
	team_stats_mutex.unlock()
	
	ship_maker_mutex.lock()
	ships_to_spawn = ships_to_spawn + make_me
	var front = ships_to_spawn.pop_front()
	if front:
		callv('call_deferred',front)
	ship_maker_mutex.unlock()
	
	combat_engine_mutex.lock() # ensure clear() does not run during _physics_process()
	
	var new_ships_packed: Array = pack_ship_stats().duplicate(true)
	var new_planets_packed: Array = pack_planet_stats_if_not_sent().duplicate(true)
	
	var player_ship = $Ships.get_node_or_null(player_ship_name)
	var player_ship_rid = RID() if player_ship==null else player_ship.get_rid()
	var old_player_target_name = ''
	if ship_stats.has(player_ship_name):
		old_player_target_name = ship_stats[player_ship_name].get('target_name','')
	
	player_orders_mutex.lock()
	var orders_copy: Array = player_orders.duplicate(true)
	player_orders_mutex.unlock()
	
	var space: PhysicsDirectSpaceState = get_world().direct_space_state

	var update_request_keys = ship_stats_requests.keys()
	var update_request_rids = Array();
	for ship_name in update_request_keys:
		var ship = $Ships.get_node_or_null(ship_name)
		if ship!=null:
			update_request_rids.append(ship.get_rid())

	var result: Dictionary = combat_engine.ai_step(
		delta,new_ships_packed,new_planets_packed,
		orders_copy,player_ship_rid,space,update_request_rids)
	
	var player_died: bool = $Ships.get_node_or_null(player_ship_name) == null
	for ship_name in result.keys():
		var ship: Dictionary = result[ship_name]
		if ship_name=='weapon_rotations':
			# This is actually a list of weapons to rotate, not a ship.
			for weapon_path in ship:
				var weapon=get_node_or_null(weapon_path)
				if weapon!=null:
					weapon.rotation.y = ship[weapon_path]
			continue
		var fate: int = ship.get('fate',combat_engine.FATED_TO_FLY)
		if fate<=0:
			continue # ship is still flying
		player_died = player_died or ship_name == player_ship_name
		var ship_node = $Ships.get_node_or_null(ship_name)
		if ship_node==null:
			continue
		if ship_name==player_ship_name:
			emit_signal('player_target_changed',self) # remove target display (if any)
			if fate==combat_engine.FATED_TO_LAND:
				var planet_name = ship.get('target_name','no-name')
				var node = $Planets.get_node_or_null(planet_name)
				if node==null:
					push_warning('PLANET '+planet_name+' HAS NO NODE!')
				else:
					game_state.player_location=node.game_state_path
				clear()
				get_tree().current_scene.change_scene(load('res://ui/OrbitalScreen.tscn'))
				return
#				var _discard = get_tree().change_scene('res://ui/OrbitalScreen.tscn')
		team_stats_mutex.lock()
		team_stats[ship_node.team]['count'] -= 1
		team_stats[ship_node.team]['threat'] -= max(0,ship_node.combined_stats.get('threat',0))
		team_stats_mutex.unlock()
		ship_node.call_deferred("queue_free")
	if not player_died:
		# Update target information.
		var new_player_target_name = result.get(player_ship_name,{}).get('target_name','')
		latest_target_info = {'old':old_player_target_name, 'new':new_player_target_name}
	var _discard = result.erase('weapon_rotations')
	ship_stats = result
	
	combat_engine_mutex.unlock()

func get_main_camera() -> Node:
	return $TopCamera

func land_player() -> int:
	return get_tree().change_scene('res://ui/OrbitalScreen.tscn')

func add_spawned_ship(ship: RigidBody,is_player: bool):
	$Ships.add_child(ship)
	new_ships_mutex.lock()
	new_ships.append(ship)
	new_ships_mutex.unlock()
	if is_player:
		receive_player_orders({})

func spawn_ship(ship_design, rotation: Vector3, translation: Vector3,
		team: int, is_player: bool) -> void:
	var ship = ship_design.assemble_ship()
	ship.set_identity()
	ship.rotation=rotation
	ship.translation=translation
	ship.set_team(team)
	if is_player:
		ship.name = player_ship_name
		add_ship_stat_request(player_ship_name)
		pass
	else:
		ship.name = game_state.make_unique_ship_node_name()
	call_deferred('add_spawned_ship',ship,is_player)

func spawn_planet(planet: Spatial) -> void:
	$Planets.add_child(planet)
	sent_planets=false

func clear() -> void: # must be called in visual thread
	combat_engine_mutex.lock() # Ensure _physics_process() does not run during clear()
	
	emit_signal('player_target_changed',self) # remove old target display
	
	new_ships_mutex.lock()
	player_orders_mutex.lock()
	ship_stats_requests_mutex.lock()
	team_stats_mutex.lock()
	
	combat_engine.clear_ai()
	
	for ship in $Ships.get_children():
		ship.queue_free()
	for planet in $Planets.get_children():
		planet.queue_free()
	
	team_stats = [{'count':0,'threat':0},{'count':0,'threat':0}]
	
	new_ships=Array()
	player_orders=Array()
	ship_stats_requests=Dictionary()
	latest_target_info=Dictionary()
	
	team_stats_mutex.unlock()
	ship_stats_requests_mutex.unlock()
	player_orders_mutex.unlock()
	new_ships_mutex.unlock()
	
	combat_engine_mutex.unlock()

func init_system(planet_time: float,ship_time: float,detail: float) -> void:
	get_tree().paused=true
	#game_state.system.fill_system(self,planet_time,ship_time,detail)
	
	var make_me: Array = game_state.system.fill_system(self,planet_time,ship_time,detail)
	team_stats_mutex.lock()
	for ship in make_me:
		var team: int = ship[4] # "team" argument to spawn_ship
		team_stats[team]['count']+=1
	team_stats_mutex.unlock()
	
	ship_maker_mutex.lock()
	var front = make_me.pop_front()
	if front:
		# Player ship (if any) is always the first.
		callv(front[0],front.slice(1,len(front)))
	# Other ships can wait until later frames
	ships_to_spawn = ships_to_spawn + make_me
	ship_maker_mutex.unlock()

#	team_stats_mutex.lock()
#	for ship in make_me:
#		var team: int = ship[4] # "team" argument to spawn_ship
#		team_stats[team]['count']+=1
#	team_stats_mutex.unlock()
#	for call_arg in make_me:
#		callv(call_arg[0],call_arg.slice(1,len(call_arg)))
	center_view()
	VisualServer.force_sync()
	yield(get_tree(),'idle_frame')
	get_tree().paused=false

func _ready() -> void:
	init_system(randf()*500,50,150)
#	if ship_maker_thread.start(self,'make_ships',null)!=OK:
#		printerr("Cannot start the ship maker thread! Will be unable to make ships!")

#func _exit_tree() -> void:
#	terminate_ship_maker=true
#	if ship_maker_thread.is_active():
#		ship_maker_thread.wait_to_finish()

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
	# Maintain 30 degree sun angle unless were're very close to the sun.
	$ShipLight.translation.y = min(max_sun_height,max(min_sun_height,
		sqrt(center.x*center.x+center.z*center.z)/sqrt(3)))
	emit_signal('view_center_changed',Vector3(center.x,50,center.z),Vector3(size,0,size))
