extends Spatial

export var min_sun_height: float = 30.0
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

var ships_to_spawn: Array = Array()

var ship_stats: Dictionary = {}
const player_ship_name: String = 'player_ship' # name of player's ship node

var sent_planets: bool = false
var latest_target_info: Dictionary = Dictionary()

var Landing = preload('res://ui/OrbitalScreen.tscn')
var TargetDisplay = preload('res://ui/TargetDisplay.tscn')

signal view_center_changed          #<-- visual thread
signal player_ship_stats_updated    #<-- visual thread
signal player_target_stats_updated  #<-- visual thread
signal player_target_changed        #<-- visual thread and clear()

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
	player_orders_mutex.lock()
	var player_ship = $Ships.get_node_or_null(player_ship_name)
	new_orders['rid_id'] = player_ship.get_rid().get_id() if player_ship!=null else 0
	player_orders = [new_orders]
	player_orders_mutex.unlock()

func ship_count_by_team(team: int):
	var count=0
	for ship in $Ships.get_children():
		if team==ship.team:
			count+=1
	return count

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
	ship_stats_requests_mutex.lock()
	var new_requests: Dictionary = Dictionary()
	for ship_name in ship_stats_requests.keys():
		if $Ships.get_node_or_null(ship_name)!=null or \
				$Planets.get_node_or_null(ship_name)!=null:
			new_requests[ship_name]=1
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
	var new_ships_packed: Array = []
	for ship in new_ships:
		if ship!=null and ship is RigidBody:
			new_ships_packed.append(ship.pack_stats())
	new_ships.clear()
	new_ships_mutex.unlock()
	return new_ships_packed

func pack_planet_stats_if_not_sent() -> Array:
	var new_planets_packed: Array = []
	if not sent_planets:
		for planet in $Planets.get_children():
			new_planets_packed.append(planet.pack_stats())
		sent_planets = true
	return new_planets_packed

func _physics_process(delta):
	physics_tick += 1
	ships_to_spawn = ships_to_spawn + game_state.system.process_space(self,delta)
	for _i in range(max_new_ships_per_tick):
		var spawn_me = ships_to_spawn.pop_front()
		if spawn_me==null:
			break
		callv(spawn_me[0],spawn_me[1])
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
				var _discard = get_tree().change_scene('res://ui/OrbitalScreen.tscn')
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

func spawn_ship(ship_scene: PackedScene, rotation: Vector3, translation: Vector3,
		team: int, is_player: bool) -> void:
	var ship = ship_scene.instance()
	ship.set_identity()
	ship.rotation=rotation
	ship.translation=translation
	ship.set_team(team)
	if is_player:
		ship.name = player_ship_name
		add_ship_stat_request(player_ship_name)
	else:
		ship.name = game_state.make_unique_ship_node_name()
	$Ships.add_child(ship)
	new_ships_mutex.lock()
	new_ships.append(ship)
	new_ships_mutex.unlock()
	if is_player:
		receive_player_orders({})

func spawn_planet(planet: Spatial) -> void:
	$Planets.add_child(planet)
	sent_planets=false

func clear() -> void: # must be called in visual thread
	combat_engine_mutex.lock() # Ensure _physics_process() does not run during clear()
	
	emit_signal('player_target_changed',self) # remove old target display
	
	new_ships_mutex.lock()
	player_orders_mutex.lock()
	ship_stats_requests_mutex.lock()
	
	combat_engine.clear_ai()
	
	for ship in $Ships.get_children():
		ship.queue_free()
	for planet in $Planets.get_children():
		planet.queue_free()
		
	new_ships=Array()
	player_orders=Array()
	ship_stats_requests=Dictionary()
	latest_target_info=Dictionary()
	
	ship_stats_requests_mutex.unlock()
	player_orders_mutex.unlock()
	new_ships_mutex.unlock()
	
	combat_engine_mutex.unlock()

func init_system(planet_time: float,ship_time: float,detail: float) -> void:
	var make_me: Array = game_state.system.fill_system(self,planet_time,ship_time,detail)
	for call_arg in make_me:
		callv(call_arg[0],call_arg[1])
	center_view()

func _ready() -> void:
	init_system(999,50,150)

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
	$TopCamera.translation = Vector3(center.x, 10, center.z)
	$SpaceBackground.center_view(center.x,center.z,0,size,10)
	# Maintain 30 degree sun angle unless were're very close to the sun.
	$ShipLight.translation.y = min(max_sun_height,max(min_sun_height,
		sqrt(center.x*center.x+center.z*center.z)/sqrt(3)))
	emit_signal('view_center_changed',Vector3(center.x,10,center.z),Vector3(size,0,size))