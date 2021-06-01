extends Node

const AFFINITY_EPSILON: float = 1e-9
const FACTION_BIT_SHIFT: int = 24
const FACTION_TO_MASK: int = 16777215
const MAX_ACTIVE_FACTIONS: int = 64
const ALL_FACTIONS: int = FACTION_TO_MASK

class FactionList extends simple_tree.SimpleNode:
	func is_FactionList(): pass # never called; just used for type checking
	func encode():
		return [ 'FactionList', game_state.Universe.encode_children(self) ]

func decode_FactionList(v):
	var result = FactionList.new()
	game_state.Universe.decode_children(result,v[1])
	return result

class Faction extends simple_tree.SimpleNode:
	var affinities: Dictionary = {}
	var default_resources: float = 1000.0
	var display_name: String = ''
	var faction_name: String = ''
	var fleets: Array = []

	func is_Faction(): pass # never called; just used for type checking

	func _init(display_name_: String = '', fleets_: Array = [], default_resources_: float = 1000.0,
			string_affinities_: Dictionary = {}):
		default_resources=default_resources_
		affinities=string_affinities_.duplicate(true)
		display_name=display_name_
		fleets=fleets_

	func _ready():
		if not display_name:
			display_name = name.capitalize()

	func make_faction_state(combat_state: CombatState):
		var system_info = combat_state.system_info
		var faction_info
		if system_info:
			faction_info = system_info.active_factions.get(get_name(),{})
		else:
			faction_info = {}
		var resources = faction_info.get('starting_money',default_resources)
		# Default gain rate is full resources every 5 minutes
		var gain_rate = faction_info.get('income_per_second',resources/300.0)
		var fleet_type_weights = faction_info.get('fleet_type_weights',{})
		var state = FactionState.new(resources,gain_rate,0.0,
			fleet_type_weights.duplicate(true))
		_impl_calculate_fleet_stats(state,gain_rate)
		_impl_store_goals(combat_state,state)
		return state

	func _impl_calculate_fleet_stats(faction_state: FactionState,gain_rate: float):
		var min_cost: float = INF
		var threat_per_cost: float = 0.0
		var threat_per_second: float = 0.0
		var weight_sum: float = 0.0
# warning-ignore:unused_variable
		var count: int = 0
		var spawn_chance: float = 0
		for ifleet in range(len(fleets)):
			var fleet = fleets[ifleet]
			var fleet_type = fleet.get('type','')
			var type_weight = faction_state.fleet_type_weights.get(fleet_type,0.0)
			if type_weight<=0.0:
				continue # this fleet does not appear in the system
			var name = fleet['fleet']
			var data = game_state.fleets.get_node_or_null(name)
			if data:
				var frequency = clamp(fleet['frequency'],0.0,3600.0) # spawns per hour
				if frequency<1e-5:
					continue
				var local_fleet = fleet.duplicate(true)
				count += 1
				var cost = data.get_cost()
				min_cost = min(min_cost,cost)
				var threat = data.get_threat()
				var weight = frequency/3600.0 # spawns per second
				assert(weight>0)
				threat_per_cost += threat/max(1.0,cost)*weight
				threat_per_second += threat*weight
				faction_state.fleet_weights.append(weight_sum)
				weight_sum += weight
				spawn_chance += (1.0-spawn_chance)*clamp(weight,0,1)
				local_fleet['cost'] = cost
				local_fleet['threat'] = threat
				local_fleet['frequency'] = frequency
				local_fleet['spawn_count'] = data.spawn_count()
				faction_state.fleets.append(local_fleet)
		faction_state.fleet_weights.append(weight_sum)
		threat_per_cost /= max(1.0,weight_sum)
		faction_state.min_fleet_cost = min_cost
		faction_state.threat_per_second = min(threat_per_second,threat_per_cost*gain_rate)
		if weight_sum>0:
			for i in range(len(faction_state.fleet_weights)):
				faction_state.fleet_weights[i] /= weight_sum

	func _impl_store_goals(combat_state: CombatState,faction_state: FactionState):
		if not combat_state.system_info:
			return
		var my_name = get_name()
		for goal in combat_state.system_info.faction_goals:
			var goal_faction_name = goal.get('faction_name','')
			if goal_faction_name!=my_name:
				continue
			var target_faction = goal.get('target_faction','')
			if not game_state.factions.get_child_with_name(target_faction):
				push_warning('Ignoring goal with invalid faction "'+str(target_faction)+'": '+str(goal))
				continue
			var target_path: NodePath = goal.get('target_location',NodePath())
			var spawn_point: Vector3 = Vector3(0,0,0)
			var target_rid: RID = RID()
			if target_path:
				var target_node = combat_state.system_info.get_node_or_null(target_path)
				if not target_node:
					push_warning('Ignoring goal with invalid target path "'+str(target_path)+'": '+str(goal))
					continue
				var unique_name = target_node.make_unique_name()
				var spawned_planet = combat_state.system.get_node_or_null(
					NodePath("Planets/"+unique_name))
				if not spawned_planet:
					push_warning('Location "'+str(unique_name)+'" was not spawned in the system!')
				else:
					target_rid = spawned_planet.get_rid()
					spawn_point = spawned_planet.position()
			faction_state.goals.append({
				'action':goal.get('action','patrol'),
				'target_faction':target_faction,
				'target_rid':target_rid,
				'radius':max(0.0,float(goal.get('radius',100.0))),
				'weight':max(0.0,float(goal.get('weight',1.0))),
				'goal_status':0.0,
				'suggested_spawn_point':spawn_point,
			})

	func get_affinity(other_faction):
		return affinities.get(other_faction,0.0)

	func encode():
		return [ 'Faction', display_name,
			game_state.Universe.encode_helper(fleets), default_resources,
			game_state.Universe.encode_children(self) ]

func decode_Faction(v):
	var result = Faction.new(String(v[1]),
		game_state.Universe.decode_helper(v[2]), float(v[3]),
		game_state.Universe.decode_helper(v[4]))
	game_state.Universe.decode_children(result,v[5])
	return result


class FactionState extends Reference:
	# Resources for a faction in space, while the player is in the system.
	# Created anew on each system entry.
	var resources_available: float
	var resource_gain_rate: float
	var min_resources_to_act: float
	const max_available_fleets: int = 5
	var goals: Array = []
	var fleets = []
	var threat_per_second: float
	var fleet_type_weights: Dictionary = {}
	var min_fleet_cost: float = 0.0
	var fleet_weights: Array = []
	var faction_index: int = -1
	var available_fleets: Array = [] # fleets that have arrived and can be spawned now

	func _init(resources_available_: float,resource_gain_rate_: float,
			min_resources_to_act_: float, fleet_type_weights_:Dictionary):
		resources_available = resources_available_
		resource_gain_rate = resource_gain_rate_
		min_resources_to_act = min_resources_to_act_
		fleet_type_weights = fleet_type_weights_

	# Prepare data for the native Faction class
	func data_for_native(combat_state: CombatState) -> Dictionary:
		var result = { 'faction': faction_index, 'goals': [], 'threat_per_second':threat_per_second }
		for goal in goals:
			var target_faction: String = goal['target_faction']
			var target_int = -1
			if target_faction:
				target_int = combat_state.faction_name2int.get(target_faction,ALL_FACTIONS)
			var rgoal = goal.duplicate(true)
			rgoal['target_faction'] = target_int
			result['goals'].append(rgoal)
		return result

	# Update spawn info and goal status from the native Faction class.
	func update_from_native(_combat_state: CombatState,data: Dictionary):
		var recouped = data.get("recouped_resources",0.0)
		resources_available += recouped
		var goal_status: PoolRealArray = data['goal_status']
		var spawn_desire: PoolRealArray = data['spawn_desire']
		var suggested_spawn_points: PoolVector3Array = data['suggested_spawn_point']
		var igoal = -1
		for goal in goals:
			igoal += 1
			goal['goal_status'] = goal_status[igoal]
			goal['spawn_desire'] = spawn_desire[igoal]
			goal['suggested_spawn_point'] = suggested_spawn_points[igoal]

	# Given an amount of time that has passed (<=1 second), update money and available fleets.
	func process_space(delta):
		resources_available += delta*resource_gain_rate
		var fleet = next_fleet(delta)
		if fleet:
			available_fleets.push_back(fleet)
			if len(available_fleets)>max_available_fleets:
				var _discard = available_fleets.pop_front()

	func spawn_one_fleet(combat_state) -> Array:
		if resources_available<min_fleet_cost:
			return []
		var failed_fleets = 0
		var stat = combat_state.system.team_stats.get(faction_index,{})
		var ship_count = stat.get('count',0)
		if ship_count>5:
			var threats = combat_state.faction_threats(faction_index)
			if threats['my_threat'] > 1.5*threats['enemy_threat']:
				return []
		while failed_fleets<5 and resources_available>min_fleet_cost:
			var fleet = next_fleet(null)
			if not fleet['cost']:
				failed_fleets += 1
				continue
			var fleet_name = fleet['fleet']
			var fleet_node = game_state.fleets.get_child_with_name(fleet_name)
			if not fleet_node:
				failed_fleets += 1
				continue
			if fleet['cost'] > resources_available:
				failed_fleets += 1
				continue
			if not combat_state.can_spawn_fleet(faction_index,fleet):
				failed_fleets += 1
				continue
			var goal = choose_random_goal()
			resources_available -= fleet['cost']
			var entry_method = combat_engine.ENTRY_FROM_RIFT
			var ai_type = combat_engine.PATROL_SHIP_AI
			if goal['action'] == 'patrol' and randf()>0.2:
				entry_method = combat_engine.ENTRY_FROM_ORBIT
			elif goal['action'] == 'raid':
				ai_type = combat_engine.RAIDER_AI
			return combat_state.spawn_fleet(fleet_node,faction_index,
				goal['suggested_spawn_point'],entry_method,ai_type)
		return []

	# Given an amount of time that has passed (<= 1 second), decide what fleet may be spawned.
	# If delta is null, then a fleet is always returned (if there is one)
	func next_fleet(delta):
		if not fleets:
			return null
		var rand_max: float = fleet_weights[len(fleet_weights)-1]
		if delta!=null and delta<1.0:
			rand_max *= delta
		var fleet_index: int = fleet_weights.bsearch(randf()*rand_max)
		if fleet_index<len(fleets):
			return fleets[fleet_index]
		elif delta==null:
			return fleets.back()
		return null

	# Choose a random goal with priorities weighted by goal weight and goal spawn desire.
	func choose_random_goal() -> Dictionary:
		var spawn_weights: Array = []
		var accum: float = 0
		for goal in goals:
			var spawn_desire = max(0.0,goal.get("spawn_desire",1.0))
			var weight = max(0.0,goal.get("weight",1.0))
			spawn_weights.append(accum)
			accum += weight*spawn_desire
		spawn_weights.append(accum)
		var goal_index = min(len(goals)-1,spawn_weights.bsearch(randf()*accum))
		return goals[goal_index]

class CombatState extends Reference:
	# Information about factions and ship locations in the system which the
	# player is currently flying. Created anew on each system entry.
	var system_info = null # SystemData for current system, or null in Hyperspace
	var system = null # The System or Hyperspace
	var immediate_entry: bool = false # Should ships appear without entry animations?

	var faction_states: Dictionary = {}
	var faction_int2name: Dictionary = {}
	var faction_name2int: Dictionary = {}
	var faction_int_affinity: Dictionary = {}
	
	var player_faction_index: int

	func _init(system_info_, system_, immediate_entry_: bool):
		system_info = system_info_
		system = system_
		immediate_entry = immediate_entry_
		_impl_add_faction(Player.player_faction)
		player_faction_index = faction_name2int[Player.player_faction]
		assert(player_faction_index==0)
		if system_info:
			for goal in system_info.faction_goals:
				_impl_add_faction(goal.get('faction_name',''))
		for faction_name in faction_states:
			_impl_add_faction_affinities(faction_name)
	func get_faction_affinity(from_faction: int, to_faction: int):
		var key = (from_faction<<Factions.FACTION_BIT_SHIFT) | to_faction
		return faction_int_affinity.get(key,0)
	func get_faction_affinities(from_faction: int) -> Dictionary:
		var result: Dictionary = {}
		for to_faction in faction_int2name:
			if to_faction==from_faction:
				continue
			var key = (from_faction<<Factions.FACTION_BIT_SHIFT) | to_faction
			var affinity = faction_int_affinity.get(key,0)
			if affinity!=0:
				result[to_faction] = affinity
		return result
	func get_faction_state(faction_name):
		return faction_states.get(faction_name,null)
	func add_factions(faction_names):
		var added: bool = false
		for name in faction_names:
			if not faction_name2int.has(name):
				_impl_add_faction(name)
				added = true
		if added:
			for name in faction_name2int:
				_impl_add_faction_affinities(name)

	func data_for_native() -> Dictionary:
		var result = {
			"affinities": faction_int_affinity,
			"active_factions": [],
			"player_faction":player_faction_index,
		}
		result['active_factions'].resize(faction_states.size())
		for faction_name in faction_states:
			var faction_int = faction_name2int[faction_name]
			var faction_state = faction_states[faction_name]
			if faction_state:
				var data: Dictionary = faction_state.data_for_native(self)
				assert(data)
				result['active_factions'][faction_int] = data
			else:
				push_warning('Cannot find faction named "'+faction_name+'" in universe')
		return result

	func update_from_native(native_data: Dictionary):
		for faction_index in native_data:
			var faction_state = faction_states[faction_int2name[faction_index]]
			faction_state.update_from_native(self,native_data[faction_index])

	func _impl_add_faction_affinities(faction_name):
		var faction = game_state.factions.get_child_with_name(faction_name)
		if not faction:
			push_error('no faction with name "'+faction_name+'"')
			return
		var from_index: int = faction_name2int.get(faction_name,-1)
		if from_index<0:
			_impl_add_faction(faction_name)
			from_index = faction_name2int.get(faction_name,-1)
			if from_index<0:
				push_error('Cannot add faction "'+str(faction_name)+'"')
				return
		for affinity_to_name in faction.affinities:
			var to_index: int = faction_name2int.get(affinity_to_name,-1)
			if to_index>=0:
				faction_int_affinity[(from_index << FACTION_BIT_SHIFT)|to_index] = \
					faction.affinities[affinity_to_name]
	func _impl_add_faction(faction_name: String):
		if not faction_name or faction_states.has(faction_name):
			return
		var ifaction = faction_states.size()
		if ifaction >= MAX_ACTIVE_FACTIONS:
			push_error('Can only have '+str(MAX_ACTIVE_FACTIONS)+' active at once.')
			return
		var faction = game_state.factions.get_child_with_name(faction_name)
		if faction:
			faction_states[faction_name] = faction.make_faction_state(self)
			if not faction_name2int.has(faction_name):
				faction_int2name[ifaction] = faction_name
				faction_name2int[faction_name] = ifaction
				faction_states[faction_name].faction_index = ifaction
		else:
			push_error('Tried to add a faction with name "'+faction_name+'" but the faction has no game data')

	func process_space(delta: float) -> Array:
		for faction in faction_states.values():
			if faction.faction_index != player_faction_index:
				faction.process_space(delta)
		var result = []
		# Fixme: sort factions somehow? Perhaps weakest first?
		for faction in faction_states.values():
			if faction.faction_index != player_faction_index:
				result += faction.spawn_one_fleet(self)
		return result

	func spawn_player_ship():
		var planet_data = game_state.systems.get_node_or_null(Player.player_location);
		var entry_method: int = combat_engine.ENTRY_FROM_RIFT
		var center: Vector3 = Vector3(0,0,0)
		var angle = randf()*2*PI
		var add_radius = randf()
		add_radius *= add_radius*100
		var safe_zone = 25
		if planet_data and planet_data.has_method("is_SpaceObjectData"):
			var planet_unique_name: String = planet_data.make_unique_name()
			var planet = get_system_planets().get_node_or_null(planet_unique_name)
			if planet and planet is Spatial:
				center = planet.translation
				entry_method = combat_engine.ENTRY_FROM_ORBIT
				add_radius *= planet.get_radius()/100
				safe_zone = 0
		if entry_method == combat_engine.ENTRY_FROM_RIFT:
			var planets: Array = get_system_planets().get_children()
			var planet: Spatial = planets[randi()%len(planets)]
			center = planet.translation
		return spawn_ship(system,Player.player_ship_design,
			0,angle,add_radius,safe_zone,0,0,center,true,entry_method,
			combat_engine.ATTACKER_AI)

	# Spawn an individual ship. Intended to be called from
	# spawn_fleet or spawn_player_ship
	func spawn_ship(var _system,var ship_design: simple_tree.SimpleNode,
			faction_index: int,angle: float,add_radius: float,safe_zone: float,
			random_x: float, random_z: float, center: Vector3, is_player: bool,
			entry_method: int, initial_ai: int):
		var x = (safe_zone+add_radius)*sin(angle) + center.x + random_x
		var z = (safe_zone+add_radius)*cos(angle) + center.z + random_z
		# IMPORTANT: Return value must match what spawn_ship, init_system, and
		#   _physics_process want in System.gd:
		return ['spawn_ship',ship_design, Vector3(0,2*PI-angle,0), Vector3(x,game_state.SHIP_HEIGHT,z),
			faction_index, is_player, entry_method, initial_ai]

	func get_system_planets(): # -> Node or null
		var Planets = system.get_node_or_null('Planets')
		if Planets: return Planets
		return system.get_node_or_null('Systems')

	# Spawn all ships from a Fleet node. Intended to be called from FleetInfo
	func spawn_fleet(fleet_node, faction_index: int, where=null,
			entry_method = null, initial_ai=combat_engine.ATTACKER_AI) -> Array:
		assert(fleet_node)
		if faction_index<0:
			return []
		var center: Vector3 = where
		var planets: Array = get_system_planets().get_children()
		var add_radius = 100*randf()*randf()
		var safe_zone = 25
		if immediate_entry:
			entry_method = combat_engine.ENTRY_COMPLETE
		elif entry_method == null:
			if system_info:
				entry_method = combat_engine.ENTRY_FROM_RIFT
			else:
				entry_method = combat_engine.ENTRY_FROM_RIFT_STATIONARY
		if system_info and combat_engine.ENTRY_FROM_ORBIT==entry_method and planets:
			if not center:
				var planet: Spatial = planets[randi()%len(planets)]
				center = planet.translation
				add_radius *= planet.get_radius()/100
			safe_zone = 0
		elif combat_engine.ENTRY_FROM_RIFT!=entry_method and planets and not center:
			var planet: Spatial = planets[randi()%len(planets)]
			center = planet.translation
		if not center:
			center = Vector3(0,0,0)
		var result: Array = Array()
		var angle = randf()*2*PI
		for design_name in fleet_node.get_designs():
			var num_ships = int(fleet_node.spawn_count_for(design_name))
			for _n in range(num_ships):
				var design = game_state.ship_designs.get_node_or_null(design_name)
				if design:
					result.push_back(spawn_ship(
						system,design,faction_index,
						angle,add_radius,randf()*10-5,randf()*10-5,
						safe_zone,center,false,entry_method,initial_ai))
				else:
					push_warning('Fleet '+str(fleet_node.get_path())+
						' wants to spawn missing design '+str(design.get_path()))
		return result

	func faction_threats(faction_index: int):
		var stat = system.team_stats.get(faction_index,{})
		var result = { 'my_count': stat.get('count',0),
			'my_threat': stat.get('threat',0.0),
			'enemy_count': 0, 'enemy_threat':0,
			'neutral_count': 0, 'neutral_threat':0,
			'ally_count': 0, 'ally_threat':0 }
		for other_faction_index in faction_int2name:
			if other_faction_index!=faction_index:
				var affinity = faction_int_affinity.get(other_faction_index | 
					(faction_index << FACTION_BIT_SHIFT),0.0)
				if affinity<-1e-5:
					var ostat = system.team_stats.get(other_faction_index,{})
					result['enemy_threat'] += ostat.get('threat',0.0)
					result['enemy_count'] += ostat.get('count',0)
				elif affinity>1e-5:
					var ostat = system.team_stats.get(other_faction_index,{})
					result['ally_threat'] += ostat.get('threat',0.0)
					result['ally_count'] += ostat.get('count',0)
				else:
					var ostat = system.team_stats.get(other_faction_index,{})
					result['neutral_threat'] += ostat.get('threat',0.0)
					result['neutral_count'] += ostat.get('count',0)
		return result

	func can_spawn_fleet(faction_index: int,fleet: Dictionary):
		if not system_info:
			return false # do not spawn ships in hyperspace
		if fleet['spawn_count']+system.ship_count > game_state.max_ships:
			return false
		var stat = system.team_stats.get(faction_index,null)
		if stat and stat['count']+fleet['spawn_count'] > game_state.max_ships_per_faction:
			return false
		return true

	func fill_system(_planet_time: float, _ship_time: float, _detail: int):
		return [spawn_player_ship()]
