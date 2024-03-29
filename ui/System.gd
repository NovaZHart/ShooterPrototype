extends Viewport

export var label_font_data: DynamicFontData
export var min_sun_height: float = 50.0
export var max_sun_height: float = 1e5
export var min_camera_size: float = 25
export var max_camera_size: float = 180
export var max_new_ships_per_tick: int = 1
export var max_new_ships_per_early_tick: int = 5
export var number_of_early_ticks: int = 20
export var game_time_ratio: float = 60
export var make_labels: bool = false
export var target_label_height: float = 32

export var TargetDisplay: PackedScene = preload('res://ui/TargetDisplay.tscn')

const ImageLabelMaker = preload('res://ui/ImageLabelMaker.gd')

var timing: Dictionary = Dictionary()
var time_start: Array = Array()

var label_maker
var label_being_made: String
var finished_making_labels: bool = true

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
var ship_count: int = 0
var team_stats: Dictionary = {}
var team_stats_mutex: Mutex = Mutex.new()

var ship_stats: Dictionary = {}
const player_ship_name: String = 'player_ship' # name of player's ship node

var sent_planets: bool = false
var latest_target_info: Dictionary = Dictionary()

var raise_sun: bool = false setget set_raise_sun

var old_target_fps = null

signal view_center_changed          #<-- visual thread
signal player_ship_stats_updated    #<-- visual thread
signal player_target_nothing        #<-- visual thread
signal player_target_stats_updated  #<-- visual thread
signal player_target_changed        #<-- visual thread and clear()

func set_raise_sun(flag: bool):
	if raise_sun==flag:
		return
	if flag:
		$PlanetLight.translation.y += 10000
	else:
		$PlanetLight.translation.y += 10000

func get_label_scale() -> float:
	var view_size = max(1,size.y)
	var camera_size = $TopCamera.size
	return target_label_height/view_size * camera_size

func make_more_labels():
	# Delete any labels for removed planets:
	for label in $Labels.get_children():
		var planet = $Planets.get_node_or_null(label.name)
		if not planet:
			$Labels.remove_child(label)
			label.queue_free()
	
	# If we're in the middle of making a label, finish
	if label_being_made and label_maker:
		if not label_maker.step():
			return # not done making this label
		var planet = $Planets.get_node_or_null(label_being_made)
		if planet:
			var shift = planet.get_radius()/sqrt(2)
			var xyz: Vector3 = Vector3(shift,0,shift)
			label_maker.instance.translation = planet.translation + xyz
			var scale = get_label_scale()
			label_maker.instance.scale = Vector3(scale,scale,scale)
		label_maker.instance.name = label_being_made
		$Labels.add_child(label_maker.instance)
		label_being_made=''
	
	# Start making a label for the next planet that doesn't have one:
	for planet in $Planets.get_children():
		if $Labels.get_node_or_null(planet.name)==null:
			label_being_made = planet.name
			var display_name = planet.display_name
			var color = Color($SpaceBackground.plasma_color)
			color.v = 0.7
			if label_maker:
				label_maker.reset(display_name,color)
			else:
				label_maker = ImageLabelMaker.new(display_name,label_font_data,color)
			label_maker.step()
			return
	label_maker = null
	finished_making_labels=true

func get_world():
	return find_world()

func _enter_tree():
	old_target_fps = Engine.target_fps
	Engine.target_fps = Engine.iterations_per_second

func _exit_tree():
	print('TIMINGS:')
	for tm in timing:
		print(str(tm)+" = "+str(timing[tm]))
	
	if old_target_fps != null:
		Engine.target_fps = old_target_fps

func player_has_a_ship() -> bool:
	return $Ships.get_node_or_null(player_ship_name)!=null

func store_player_ship_stats():
	var player_ship_stats = ship_stats.get(player_ship_name,null)
	if player_ship_stats:
		Player.set_ship_combat_stats(player_ship_stats)

func update_space_background(from=null):
	if from==null:
		from=Player.system
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
	var start: float = OS.get_ticks_msec()
	player_orders_mutex.lock()
	var duration: float = OS.get_ticks_msec()-start
	if duration>1:
		print("Waited "+str(duration)+" ms for player orders mutex lock in receive_player_orders")
	player_orders = [new_orders]
	player_orders_mutex.unlock()

func ship_stats_by_team():
	var start: float = OS.get_ticks_msec()
	team_stats_mutex.lock()
	var duration: float = OS.get_ticks_msec()-start
	if duration>1:
		print("Waited "+str(duration)+" ms for team stats mutex lock in ship_stats_by_team")
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
	var start: float = OS.get_ticks_msec()
	ship_stats_requests_mutex.lock()
	var duration: float = OS.get_ticks_msec()-start
	if duration>1:
		print("Waited "+str(duration)+" ms for ship stats requests mutex lock in add_ship_stat_request")
	ship_stats_requests[ship_name]=1
	ship_stats_requests_mutex.unlock()
	
func remove_ship_stat_request(ship_name: String) -> void:
	var start: float = OS.get_ticks_msec()
	ship_stats_requests_mutex.lock()
	var duration: float = OS.get_ticks_msec()-start
	if duration>1:
		print("Waited "+str(duration)+" ms for ship stats requests mutex lock in remove_ship_stat_request")
	var _discard = ship_stats_requests.erase(ship_name)
	ship_stats_requests_mutex.unlock()

func sync_Ships_with_stat_requests() -> void:
	# Remove non-existent ships from the ship stats requests:
	var new_requests: Dictionary = Dictionary()
#	var start: float = OS.get_ticks_msec()
	ship_stats_requests_mutex.lock()
#	var duration: float = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for ship stats request mutex lock in sync_Ships_with_stat_requests (1)")
	var keys=ship_stats_requests.keys()
	ship_stats_requests_mutex.unlock()
	for ship_name in keys:
		if $Ships.get_node_or_null(ship_name)!=null or \
				$Planets.get_node_or_null(ship_name)!=null:
			new_requests[ship_name]=1
#	start = OS.get_ticks_msec()
	ship_stats_requests_mutex.lock()
#	duration = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for ship stats requests mutex lock in sync_Ships_with_stat_requests (2)")
	ship_stats_requests=new_requests
	ship_stats_requests_mutex.unlock()

func visible_region() -> AABB:
	var ul: Vector3 = $TopCamera.project_position(Vector2(0,0),0)
	var lr: Vector3 = $TopCamera.project_position(size,0)
	var y0: float = $SpaceBackground.translation.y
	var y1: float = $TopCamera.translation.y
	return AABB(Vector3(min(ul.x,lr.x),min(y0,y1),min(ul.z,lr.z)),
		Vector3(abs(ul.x-lr.x),abs(y1-y0),abs(ul.z-lr.z)))

func visible_region_expansion_rate() -> Vector3:
	var player_ship_stats = ship_stats.get(player_ship_name,null)
	if not player_ship_stats:
		return Vector3(0,0,0)
	var player_ship = $Ships.get_node_or_null(player_ship_name)
	if not player_ship:
		return Vector3(0,0,0)
	var rate: float = utils.ship_max_speed(player_ship.combined_stats)
	return Vector3(rate,0,rate)

func start_timing():
	time_start.push_back(OS.get_ticks_usec())
	
func end_timing(what):
	var before = timing.get(what,0)
	timing[what] = before + OS.get_ticks_usec()-time_start.pop_back()

func _process(delta) -> void:
	visual_tick += 1
	assert($TopCamera!=null)
	
	start_timing()
	
	start_timing()
	combat_engine.draw_space($TopCamera,get_tree().root)
	end_timing('combat_engine.draw_space')
	
	if ship_stats==null:
		end_timing('_process')
		return
	
	#var player_ship_stats = ship_stats.get(player_ship_name,null)
	
	start_timing()
	combat_engine.set_visible_region(visible_region(),
		visible_region_expansion_rate())
	end_timing('set_visible_region')

	start_timing()
	combat_engine.step_visual_effects(delta,$TopCamera,get_tree().root)
	end_timing('step_visual_effects')
	
#	if player_ship_stats==null:
#		end_timing('_process')
#		return

	if make_labels and not finished_making_labels:
		start_timing()
		make_more_labels()
		end_timing('make_more_labels')
		
	end_timing('_process')

func update_target_display(old_target_name: String,new_target_name: String) -> void:
	assert(old_target_name!=new_target_name)
	remove_ship_stat_request(old_target_name)
	var new_target = $Ships.get_node_or_null(new_target_name)
	if new_target==null:
		new_target = $Planets.get_node_or_null(new_target_name)
	if new_target==null:
		emit_signal('player_target_nothing',self)
		return # target does not exist, so don't make a new target display.
	emit_signal('player_target_changed',self,new_target)
	add_ship_stat_request(new_target_name)
	var display = TargetDisplay.instance()
	var _discard=connect('player_target_nothing',display,'player_target_nothing')
	_discard=connect('player_target_changed',display,'player_target_changed')
	_discard = connect('player_target_stats_updated',display,'player_target_stats_updated')
	new_target.call_deferred('add_child',display)

func pack_ship_stats() -> Array:
#	var start: float = OS.get_ticks_msec()
	new_ships_mutex.lock()
#	var duration: float = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for new ships mutex lock in pack_ship_stats")
	var my_new_ships = new_ships.duplicate(true)
	new_ships.clear()
	new_ships_mutex.unlock()

	var new_ships_packed: Array = []
	var threats: Dictionary = {}
#	start = OS.get_ticks_msec()
	team_stats_mutex.lock()
#	duration = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for team stats mutex lock in pack_ship_stats")
	for ship in my_new_ships:
		if ship!=null and ship is RigidBody:
			new_ships_packed.append(ship.pack_stats())
			if ship.faction_index<0:
				push_error("Tried to spawn a ship with no faction index.")
			elif threats.has(ship.faction_index):
				threats[ship.faction_index] += ship.combined_stats.get('threat',0.0)
			else:
				threats[ship.faction_index] = ship.combined_stats.get('threat',0.0)

	# Count was incremented in _physics_process
	for faction_index in threats:
		var team_stat = team_stats.get(faction_index,null)
		if not team_stat:
			# Should never get here.
			push_warning('No team_stats['+str(faction_index)+'] during pack_ship_stats')
			team_stats[faction_index] = {
				'threat':threats[faction_index],
				'count':1,
			}
		else:
			team_stat['threat'] += threats[faction_index]
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

func process_space(delta):
	combat_engine.combat_state.immediate_entry = physics_tick<30
	Player.system.process_space(self,delta)
	var make_me: Array = combat_engine.combat_state.process_space(delta)

#	var start: float = OS.get_ticks_msec()
	team_stats_mutex.lock()
#	var duration: float = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for team stats mutex lock in process_space")
	for ship in make_me:
		var faction_index: int = ship[4] # "team" argument to spawn_ship
		if faction_index<0 :
			push_error('Refusing to spawn a ship with no faction index: '+str(ship))
			continue
		elif not team_stats.has(faction_index):
			team_stats[faction_index] = { 'threat':0.0, 'count':1 }
		else:
			team_stats[faction_index]['count'] += 1
	var new_ship_count: int = 0
	for faction_index in team_stats:
		var stat = team_stats[faction_index]
		new_ship_count += stat['count']
	ship_count = new_ship_count
	team_stats_mutex.unlock()
	
#	start = OS.get_ticks_msec()
	ship_maker_mutex.lock()
#	duration = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for ship maker mutex lock in process_space")
	ships_to_spawn = ships_to_spawn + make_me
	var max_ships_to_spawn = max_new_ships_per_tick
	if physics_tick<number_of_early_ticks:
		max_ships_to_spawn = max_new_ships_per_early_tick
	for _ship_spawn_count in range(max_ships_to_spawn):
		var front = ships_to_spawn.pop_front()
		if not front:
			break
		#var args = front.slice(1,front.size()-1)
		#callv(front[0],args)
		callv('call_deferred',front)
	ship_maker_mutex.unlock()

func _physics_process(delta):
	combat_engine.combat_state.immediate_entry = false
	game_state.epoch_time += int(round(delta*game_state.EPOCH_ONE_SECOND*game_time_ratio))
	physics_tick += 1
	
#	var start: float = OS.get_ticks_msec()
	combat_engine_mutex.lock() # ensure clear() does not run during _physics_process()
#	var duration: float = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for combat engine mutex lock in _physics_process")
	
	var new_ships_packed: Array = pack_ship_stats().duplicate(true)
	var new_planets_packed: Array = pack_planet_stats_if_not_sent().duplicate(true)
	
	var player_ship = $Ships.get_node_or_null(player_ship_name)
	var player_ship_rid = RID() if player_ship==null else player_ship.get_rid()
	var old_player_target_name = ''
	if ship_stats.has(player_ship_name):
		old_player_target_name = ship_stats[player_ship_name].get('target_name','')
	
#	start = OS.get_ticks_msec()
	player_orders_mutex.lock()
#	duration = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for player orders mutex lock in _physics_process")
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
	
	if result['salvaged_items']:
		var added_items: bool = false
		for item in result['salvaged_items']:
			if not item:
				push_warning('Ignoring null item in salvaged_items list')
				continue
			if item['ship_name'] == player_ship_name:
#				print('Player salvaged '+str(item['count'])+ \
#					' units of '+str(item['product_name'])+' with unit mass ' \
#					+str(item['unit_mass']))
				if item['count']>0:
					added_items = Player.add_cargo_to_hold(item['product_name'],item['count'])>0 \
						or added_items
	
	var player_died: bool = $Ships.get_node_or_null(player_ship_name) == null
	for ship_name in result.keys():
		if ship_name == 'salvaged_items':
			continue
		var ship: Dictionary = result[ship_name]
		if ship_name=='weapon_rotations':
			# This is actually a list of weapons to rotate, not a ship.
			for weapon_path in ship:
				var weapon=get_node_or_null(weapon_path)
				if weapon!=null:
					weapon.rotation.y = ship[weapon_path]
			continue
		elif ship_name=='faction_info':
			# This is actually information about faction states, not a ship.
			combat_engine.combat_state.update_from_native(ship)
			continue
		var fate: int = ship.get('fate',combat_engine.FATED_TO_FLY)
		if fate<=0:
			continue # ship is still flying
		player_died = player_died or ship_name == player_ship_name
		var ship_node = $Ships.get_node_or_null(ship_name)
		if ship_node==null:
			continue
		if ship_name==player_ship_name:
			emit_signal('player_target_nothing',self) # remove target display (if any)
			if fate==combat_engine.FATED_TO_LAND:
				var planet_name = ship.get('target_name','no-name')
				var node = $Planets.get_node_or_null(planet_name)
				if node==null:
					push_warning('PLANET '+planet_name+' HAS NO NODE!')
				else:
					Player.player_location=node.game_state_path
				clear()
				store_player_ship_stats()
				game_state.call_deferred('change_scene','res://ui/OrbitalScreen.tscn')
				return
			elif fate==combat_engine.FATED_TO_RIFT:
				store_player_ship_stats()
				game_state.call_deferred('change_scene','res://places/Hyperspace.tscn')
#		start = OS.get_ticks_msec()
		team_stats_mutex.lock()
#		duration = OS.get_ticks_msec()-start
#		if duration>1:
#			print("Waited "+str(duration)+" ms for team stats mutex lock in _physics_process")
		if team_stats.has(ship_node.faction_index):
			team_stats[ship_node.faction_index]['count'] -= 1
			team_stats[ship_node.faction_index]['threat'] -= max(0,ship_node.combined_stats.get('threat',0))
		team_stats_mutex.unlock()
		ship_node.call_deferred("queue_free")
	var _discard = result.erase('weapon_rotations')
	if not player_died:
		# Update target information.
		var new_player_target_name = result.get(player_ship_name,{}).get('target_name','')
		latest_target_info = {'old':old_player_target_name, 'new':new_player_target_name}
	ship_stats = result
	
	combat_engine_mutex.unlock()

	report_ship_stats()
	process_space(delta)

func report_ship_stats():
	if ship_stats!=null:
		var player_ship_stats = ship_stats.get(player_ship_name,null)
		
		if player_ship_stats!=null:
			start_timing()
			emit_signal('player_ship_stats_updated',player_ship_stats)
			end_timing('player_ship_stats_updated')
			start_timing()
			center_view()
			end_timing('center_view')
			
			var target_ship_stats = ship_stats.get(player_ship_stats.get('target_name',''),null)
			if target_ship_stats != null:
				start_timing()
				emit_signal('player_target_stats_updated',target_ship_stats)
				end_timing('player_target_stats_updated')

		start_timing()
		sync_Ships_with_stat_requests()
		end_timing('sync_Ships_with_stat_requests')

	var target_info: Dictionary = latest_target_info.duplicate(true)
	if target_info.get('old','') != target_info.get('new',''):
		# The target has changed, so we need a new TargetDisplay.
		start_timing()
		update_target_display(target_info['old'],target_info['new'])
		end_timing('update_target_display')

func get_main_camera() -> Node:
	return $TopCamera

func land_player() -> int:
	store_player_ship_stats()
	return get_tree().change_scene('res://ui/OrbitalScreen.tscn')

func add_spawned_ship(ship: RigidBody,is_player: bool):
	var top_start: float = OS.get_ticks_msec()
	if is_player:
#		print('restore combat stats ',Player.ship_combat_stats)
		ship.restore_combat_stats(Player.ship_combat_stats)
	$Ships.add_child(ship)
	var start: float = OS.get_ticks_msec()
	new_ships_mutex.lock()
	var duration: float = OS.get_ticks_msec()-start
	if duration>1:
		print("Waited "+str(duration)+" ms for new ships mutex lock in add_spawned_ship")
	new_ships.append(ship)
	new_ships_mutex.unlock()
	if is_player:
		receive_player_orders({})
	duration=OS.get_ticks_msec()-top_start
	if duration>1:
		print('Spawn_ship took '+str(duration)+'ms')

func assemble_ship_to_spawn(ship_design, rotation: Vector3, translation: Vector3,
		faction_index: int, is_player: bool, entry_method: int,
		initial_ai: int,ship_name_prefix,cargo_hold_spawn_fraction: float = 0.0,
		commodities=null) -> Spatial:
#	var start: float = OS.get_ticks_msec()
	var ship = ship_design.assemble_ship()
	ship.set_identity()
	ship.rotation=rotation
	ship.translation=translation
	ship.ai_type=initial_ai
	ship.set_faction_index(faction_index)
	if is_player:
		ship.name = player_ship_name
	else:
		ship.name = game_state.make_unique_ship_node_name(ship_name_prefix)
	ship.set_entry_method(entry_method)
	if not ship.cargo and cargo_hold_spawn_fraction>0:
		if not commodities:
			push_warning('Tried to spawn a ship with cargo, but no commodities to pick from')
#		print(ship.name+': making random cargo')
		ship.make_random_cargo(cargo_hold_spawn_fraction,commodities)
#		print('    ... end cargo list')
	ship.select_salvage()
#	var duration = OS.get_ticks_msec()-start
#	if duration>1:
#		print('assemble_ship_to_spawn took '+str(duration)+'ms')
	return ship

func spawn_ship(ship_design, rotation: Vector3, translation: Vector3,
		faction_index: int, is_player: bool, entry_method: int,
		initial_ai: int, ship_name_prefix, cargo_hold_spawn_fraction: float = 0.0,
		commodities=null) -> void:
#	var start: float = OS.get_ticks_msec()
	var ship = assemble_ship_to_spawn(ship_design,rotation,translation,faction_index,is_player,entry_method,initial_ai,ship_name_prefix,cargo_hold_spawn_fraction,commodities)
	if is_player:
		add_ship_stat_request(player_ship_name)
		ship.restore_combat_stats(Player.ship_combat_stats)
		add_spawned_ship(ship,true)
		if ship.faction_index!=0:
			push_warning('Player ship faction index should be 0 but is '+str(ship.faction_index))
	else:
		ship.name = game_state.make_unique_ship_node_name(ship_name_prefix)
		add_spawned_ship(ship,false)
		#call_deferred('add_spawned_ship',ship,false)
#	var duration = OS.get_ticks_msec()-start
#	if duration>1:
#		print('Spawn_ship took '+str(duration)+'ms')

func spawn_planet(planet: Spatial) -> void:
	$Planets.add_child(planet)
	sent_planets=false
	finished_making_labels=false

func clear() -> void: # must be called in visual thread
	combat_engine_mutex.lock() # Ensure _physics_process() does not run during clear()
	
	emit_signal('player_target_nothing',self) # remove old target display
	
	new_ships_mutex.lock()
	player_orders_mutex.lock()
	ship_stats_requests_mutex.lock()
	team_stats_mutex.lock()
	
	combat_engine.clear_ai()
	
	for ship in $Ships.get_children():
		ship.queue_free()
	for planet in $Planets.get_children():
		planet.queue_free()
	for label in $Labels.get_children():
		label.queue_free()
	
	label_maker = null
	label_being_made = ''
	
	team_stats = Dictionary()
	new_ships=Array()
	player_orders=Array()
	ship_stats_requests=Dictionary()
	latest_target_info=Dictionary()
	
	team_stats_mutex.unlock()
	ship_stats_requests_mutex.unlock()
	player_orders_mutex.unlock()
	new_ships_mutex.unlock()
	
	combat_engine_mutex.unlock()

func spawn_asteroid_field(field_data):
	combat_engine.add_asteroid_field(field_data)

func init_system(planet_time: float,ship_time: float,detail: float) -> void:
	get_tree().paused=true
	#Player.system.fill_system(self,planet_time,ship_time,detail)
	combat_engine.init_combat_state(Player.system,self,true)
	Player.system.fill_system(self,planet_time,ship_time,detail)
	var make_me: Array = combat_engine.combat_state.fill_system(planet_time,ship_time,detail)
#	var start: float = OS.get_ticks_msec()
	team_stats_mutex.lock()
#	var duration: float = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for team stats mutex lock in init_system")
	for ship in make_me:
		var faction_index: int = ship[4] # "faction" argument to spawn_ship
		if faction_index<0:
			push_error('Refusing to make a ship with no faction index: '+str(ship))
			continue
		elif not team_stats.has(faction_index):
			team_stats[faction_index] = { 'threat':0.0, 'count':1 }
		else:
			team_stats[faction_index]['count'] += 1
	team_stats_mutex.unlock()
	
#	start = OS.get_ticks_msec()
	ship_maker_mutex.lock()
#	duration = OS.get_ticks_msec()-start
#	if duration>1:
#		print("Waited "+str(duration)+" ms for ship maker mutex lock in init_system")
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
	call_deferred('unpause')

func unpause():
	if is_inside_tree():
		var tree = get_tree()
		if tree:
			tree.paused = false

func _ready() -> void:
	init_system(game_state.epoch_time/float(game_state.EPOCH_ONE_DAY*5),600,150)
	combat_engine.set_world(get_world())
	center_view()
	combat_engine.set_visible_region(visible_region(),
		visible_region_expansion_rate())
#	if ship_maker_thread.start(self,'make_ships',null)!=OK:
#		printerr("Cannot start the ship maker thread! Will be unable to make ships!")

#func _exit_tree() -> void:
#	terminate_ship_maker=true
#	if ship_maker_thread.is_active():
#		ship_maker_thread.wait_to_finish()

func set_zoom(zoom: float,original: float=-1) -> void:
	var from: float = original if original>1 else $TopCamera.size
	$TopCamera.size = clamp(zoom*from,min_camera_size,max_camera_size)
	if $Labels.get_child_count():
		var label_scale = get_label_scale()
		var scale = Vector3(label_scale,label_scale,label_scale)
		for label in $Labels.get_children():
			label.scale = scale

func center_view(center=null) -> void:
	if center==null:
		var player_ship = $Ships.get_node_or_null(player_ship_name)
		var center_object = $TopCamera 
		if player_ship!=null:
			center_object=player_ship
		center = center_object.translation
	var size=$TopCamera.size
	$TopCamera.translation = Vector3(center.x, 50, center.z)
	$EffectsLight.translation.y = min(max_sun_height,max(min_sun_height,
		sqrt(center.x*center.x+center.z*center.z)/sqrt(3)))
	$EffectsLight.omni_range = ($EffectsLight.translation.y+size)*3
	$SpaceBackground.center_view(center.x,center.z,0,size,30)
	# Maintain 30 degree sun angle unless were're very close to the sun.
	$ShipLight.translation.y = min(max_sun_height,max(min_sun_height,
		sqrt(center.x*center.x+center.z*center.z)/sqrt(3)))
	$ShipLight.omni_range = ($EffectsLight.translation.y+size)*3
	emit_signal('view_center_changed',Vector3(center.x,50,center.z),Vector3(size,0,size))
