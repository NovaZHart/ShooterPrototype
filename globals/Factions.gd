extends Node

const AFFINITY_EPSILON: float = 1e-9
const FACTION_BIT_SHIFT: int = 24
const FACTION_TO_MASK: int = 16777215
const MAX_ACTIVE_FACTIONS: int = 64
const ALL_FACTIONS: int = FACTION_TO_MASK

const DEFAULT_GOAL_RADIUS: float = 100.0
const DEFAULT_GOAL_WEIGHT: float = 5.0

const FLOTSAM_FACTION_NAME: String = "flotsam"

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
	var faction_color: Color = Color(1,0.8,0.3)

	func is_Faction(): pass # never called; just used for type checking

	func _init(display_name_: String, fleets_: Array = [],
			default_resources_: float = 1000.0,
			string_affinities_: Dictionary = {}, faction_color_: Color = Color(1,0.8,0.3)):
		default_resources=default_resources_
		affinities=string_affinities_.duplicate(true)
		display_name=display_name_
		fleets=fleets_
		faction_color=faction_color_

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
			fleet_type_weights.duplicate(true),faction_color,
			faction_name+"_")
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
				assert(frequency>0)
				var probability: float = clamp(frequency/3600,0,1)
				threat_per_cost += threat/max(1.0,cost)*probability
				threat_per_second += threat*probability
				faction_state.fleet_weights.append(weight_sum)
				weight_sum += probability
				spawn_chance += (1.0-spawn_chance)*probability
				local_fleet['cost'] = cost
				local_fleet['threat'] = threat
				local_fleet['frequency'] = frequency
				local_fleet['spawn_count'] = data.spawn_count()
				faction_state.fleets.append(local_fleet)
		faction_state.fleet_weights.append(weight_sum)
		faction_state.min_fleet_cost = min_cost
		faction_state.threat_per_second = min(threat_per_second,threat_per_cost*gain_rate)
		if weight_sum>0 and spawn_chance>0:
			threat_per_cost /= weight_sum
			for i in range(len(faction_state.fleet_weights)):
				faction_state.fleet_weights[i] *= spawn_chance/weight_sum

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
			var scene_tree_path: NodePath = NodePath()
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
					scene_tree_path = spawned_planet.get_path()
			faction_state.goals.append({
				'action':goal.get('action','patrol'),
				'target_faction':target_faction,
				'target_rid':target_rid,
				'radius':max(0.0,float(goal.get('radius',DEFAULT_GOAL_RADIUS))),
				'weight':max(0.0,float(goal.get('weight',DEFAULT_GOAL_WEIGHT))),
				'goal_status':0.0,
				'suggested_spawn_point':spawn_point,
				'scene_tree_path':scene_tree_path,
			})

	func get_affinity(other_faction):
		return affinities.get(other_faction,0.0)

	func encode():
		return [ 'Faction', display_name,
			game_state.Universe.encode_helper(fleets), default_resources,
			game_state.Universe.encode_children(self),
			game_state.Universe.encode_color(faction_color) ]

func decode_Faction(v):
	var result = Faction.new(String(v[1]),
		game_state.Universe.decode_helper(v[2]), float(v[3]),
		game_state.Universe.decode_helper(v[4]),
		game_state.Universe.decode_helper(v[6]))
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
	var faction_color: Color = Color(1,1,1,1)
	var available_fleets: Array = [] # fleets that have arrived and can be spawned now
	var ship_name_prefix: String

	func _init(resources_available_: float,resource_gain_rate_: float,
			min_resources_to_act_: float, fleet_type_weights_:Dictionary,
			faction_color_: Color, ship_name_prefix_: String):
		assert(ship_name_prefix!='_')
		ship_name_prefix = ship_name_prefix_
		resources_available = resources_available_
		resource_gain_rate = resource_gain_rate_
		min_resources_to_act = min_resources_to_act_
		fleet_type_weights = fleet_type_weights_
		faction_color = faction_color_

	# Prepare data for the native Faction class
	func data_for_native(combat_state: CombatState) -> Dictionary:
		var result = { 'faction': faction_index, 'goals': [], 'threat_per_second':threat_per_second,
			'faction_color': faction_color }
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
		var goal_status: Array = data['goal_status']
		var spawn_desire: Array = data['spawn_desire']
		var suggested_spawn_points: Array = data['suggested_spawn_point']
		var scene_tree_paths: Array = data['suggested_spawn_path']
		var igoal = -1
		for goal in goals:
			igoal += 1
			goal['goal_status'] = goal_status[igoal]
			goal['spawn_desire'] = spawn_desire[igoal]
			goal['suggested_spawn_point'] = suggested_spawn_points[igoal]
			goal['scene_tree_path'] = scene_tree_paths[igoal]
			assert(goal['scene_tree_path'])

	# Given an amount of time that has passed (<=1 hour), update money and available fleets.
	func process_space(delta):
		# Gain money if we have any income:
		resources_available += delta*resource_gain_rate
		
		# See if new fleets have arrived for recruitment.
		make_fleets_available(delta)

	func spawn_one_fleet(combat_state,only_if_available: bool,max_tries=max_available_fleets) -> Array:
		if resources_available<min_fleet_cost:
			return [] # There are no fleets we can purchase now.
		
		var fac = 3
		var sfac=str(fac)
		
		var fleet_index: int = 0 # index in available_fleets to try spawning
		
		if only_if_available:
			if not available_fleets:
				return []
			max_tries = min(max_tries,available_fleets.size())
		
		if available_fleets.size()>1:
			fleet_index = randi()%len(available_fleets)
		
		# Get combat statistics for this team
		var stat = combat_state.system.team_stats.get(faction_index,{})
		var ship_count = stat.get('count',0)
		
		# Don't spawn ships if we already have a decisive advantage (unless we have few ships).
		if ship_count>3:
			var threats = combat_state.faction_threats(faction_index)
			if threats['my_threat'] > 1.5*threats['enemy_threat']:
				if faction_index==fac:
					print('Faction '+sfac+' is too strong to spawn fleets.')
				return []
		
		# Keep trying to spawn a fleet until we succeed, or hit max_tries
		fleet_index -= 1
		for _tries in range(max_tries):
			var fleet = null
			if only_if_available:
				fleet_index = (fleet_index+1)%len(available_fleets)
			else:
				fleet_index += 1
				if fleet_index>=max_available_fleets:
					fleet_index=0
				elif fleet_index>=len(available_fleets):
					# Should only get here for only_if_available.
					# This forces loading a fleet if one isn't available.
					fleet = next_fleet(null)
					if fleet:
						available_fleets.append(fleet)
						fleet_index=len(available_fleets)-1
					else:
						# Can get here if the faction cannot produce fleets
						push_error('next_fleet(null) did not produce a fleet')
						return []
			
			if not fleet:
				fleet = available_fleets[fleet_index]
			
			if faction_index==fac:
				print('Faction '+sfac+' is considering fleet '+str(fleet['fleet']))
			
			# Can we spawn this fleet?
			if not fleet['cost']:
				push_warning('ignoring fleet '+str(fleet['fleet'])+' which has no cost')
				available_fleets.remove(fleet_index)
				continue
			
			var fleet_name = fleet['fleet']
			var fleet_node = game_state.fleets.get_child_with_name(fleet_name)
			if not fleet_node:
				push_warning('ignoring fleet '+str(fleet['fleet'])+' which has no node')
				available_fleets.remove(fleet_index)
				continue
			
			# Can we pay for this fleet?
			if fleet['cost'] > resources_available:
				if faction_index==fac:
					print('faction '+sfac+' cannot spawn fleet '+str(fleet['fleet'])+' because cost '+
						str(fleet['cost'])+'>'+str(resources_available))
				continue # Can't afford the fleet.
			
			# Are there any game limits preventing this fleet from spawning?
			if not combat_state.can_spawn_fleet(faction_index,fleet):
				if faction_index==fac:
					print('faction '+sfac+' cannot spawn fleet '+str(fleet['fleet'])
						+' because can_spawn_fleet returned false.')
				fleet_index = (fleet_index+1)%len(available_fleets)
				continue # Can't spawn; we hit some system or game ship limit.
			
			# Pay for the fleet:
			resources_available -= fleet['cost']
			
			# What should the ships in the fleet do?
			var goal = choose_random_goal()
			var entry_method = combat_engine.ENTRY_FROM_RIFT
			var ai_type = combat_engine.PATROL_SHIP_AI
			var center = goal.get('scene_tree_path',null)
			var cargo_hold_fill_fraction: float = 0.0
			
			if goal['action'] == 'patrol' and randf()>0.7:
				entry_method = combat_engine.ENTRY_FROM_ORBIT
			elif goal['action'] == 'raid':
				ai_type = combat_engine.RAIDER_AI
			elif goal['action'] == 'arriving_merchant':
				ai_type = combat_engine.ARRIVING_MERCHANT_AI
				cargo_hold_fill_fraction = 0.3 + randf()*0.7
			elif goal['action'] == 'departing_merchant':
				ai_type = combat_engine.DEPARTING_MERCHANT_AI
				entry_method = combat_engine.ENTRY_FROM_ORBIT
				cargo_hold_fill_fraction = 0.3 + randf()*0.7
			
			# Success! Remove this fleet from those available:
			if fleet_index>=0:
				available_fleets.remove(fleet_index)
			
			# Forward the request for this fleet to spawn.
			if faction_index==fac:
				print('faction '+sfac+' is spawning a fleet')
			if entry_method==combat_engine.ENTRY_FROM_ORBIT:
				center = goal.get('scene_tree_path',null)
				assert(center)
			if not center:
				if entry_method==combat_engine.ENTRY_FROM_ORBIT:
					push_warning('Trying to spawn a fleet from orbit but the goal has no scene tree path')
				center = goal['suggested_spawn_point']
			return combat_state.spawn_fleet(fleet_node,faction_index,
				center,entry_method,ai_type,ship_name_prefix,cargo_hold_fill_fraction)
		
		# Could not spawn fleets this turn.
		if faction_index==fac:
			print('faction '+sfac+' failed to spawn fleets this turn')
		return []

	func decide_merchant_planet():
		return Vector3(0,0,0) # FIXME

	func make_fleets_available(delta):
		var fleet = next_fleet(delta)
		if fleet:
			print('Faction '+str(faction_index)+" fleet "+str(fleet['fleet'])+" is available")
			available_fleets.push_back(fleet)
			if len(available_fleets)>max_available_fleets:
				# We hit the limit for maximum fleets available, so
				# the fleet waiting the longest leaves.
				var removed = available_fleets.pop_front()
				print('Faction '+str(faction_index)+" fleet "+str(removed['fleet'])+" is no longer available")

	# Given an amount of time that has passed, decide what fleet may be spawned.
	# If delta is null, then a fleet is always returned (if there is one)
	func next_fleet(delta):
		if not fleets:
			return null # This faction has no fleets
		
		if delta!=null and delta<=0:
			return null # no time has passed, so nothing can spawn
		
		# How likely is it that a fleet should spawn?
		var rand_max: float = fleet_weights[len(fleet_weights)-1]
		
		if delta!=null and randf()>rand_max*delta:
			return null # No fleet has spawned.
		
		# Find the fleet to spawn, if any
# warning-ignore:narrowing_conversion
		var fleet_index: int = clamp(fleet_weights.bsearch(randf()*rand_max),0,len(fleets)-1)
		
		# Return the fleet to spawn
		if fleet_index<len(fleets):
			return fleets[fleet_index] # Index within array means a fleet was chosen
		elif delta==null:
			push_warning('Returning end of fleets list. This should not happen.')
			return fleets.back() # null delta means we spawn a fleet regardless
		
		# No fleet was chosen. Try again next timestep.
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
	var flotsam_faction_index: int

	func _init(system_info_, system_, immediate_entry_: bool):
		system_info = system_info_
		system = system_
		immediate_entry = immediate_entry_
		_impl_add_faction(Player.player_faction)
		_impl_add_faction(FLOTSAM_FACTION_NAME)
		player_faction_index = faction_name2int[Player.player_faction]
		assert(player_faction_index==0)
		flotsam_faction_index = faction_name2int[FLOTSAM_FACTION_NAME]
		assert(flotsam_faction_index==1)
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
			faction_states[faction_name].ship_name_prefix = faction_name+'_'
			if not faction_name2int.has(faction_name):
				faction_int2name[ifaction] = faction_name
				faction_name2int[faction_name] = ifaction
				faction_states[faction_name].faction_index = ifaction
		else:
			push_error('Tried to add a faction with name "'+faction_name+'" but the faction has no game data')

	func spawn_one_fleet_each(max_tries=FactionState.max_available_fleets) -> Array:
		var result: Array = []
		for faction in faction_states.values():
			if faction.faction_index != player_faction_index:
				result += faction.spawn_one_fleet(self,not immediate_entry,max_tries)
		return result

	func process_space(delta: float) -> Array:
		for faction in faction_states.values():
			if faction.faction_index != player_faction_index:
				faction.process_space(delta)
		var result = []
		# Fixme: sort factions somehow? Perhaps weakest first?
		if immediate_entry:
			var old_len = 0
			var diff = -1
			while diff != 0:
				result += spawn_one_fleet_each()
				diff = len(result) - old_len
				old_len = len(result)
		else:
			result += spawn_one_fleet_each(1)
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
			combat_engine.ATTACKER_AI,"initial_player_faction_",0.0,null)

	# Spawn an individual ship. Intended to be called from
	# spawn_fleet or spawn_player_ship
	func spawn_ship(var _system,var ship_design: simple_tree.SimpleNode,
			faction_index: int,angle: float,add_radius: float,safe_zone: float,
			random_x: float, random_z: float, center: Vector3, is_player: bool,
			entry_method: int, initial_ai: int, ship_name_prefix: String,
			cargo_hold_fill_fraction: float,commodities):
		var x = (safe_zone+add_radius)*sin(angle) + center.x + random_x
		var z = (safe_zone+add_radius)*cos(angle) + center.z + random_z
		# IMPORTANT: Return value must match what spawn_ship, init_system, and
		#   _physics_process want in System.gd:
		return ['spawn_ship',ship_design, Vector3(0,2*PI-angle,0), Vector3(x,game_state.SHIP_HEIGHT,z),
			faction_index, is_player, entry_method, initial_ai,ship_name_prefix,cargo_hold_fill_fraction,
			commodities]

	func get_system_planets(): # -> Node or null
		var Planets = system.get_node_or_null('Planets')
		if Planets: return Planets
		return system.get_node_or_null('Systems')

	# Spawn all ships from a Fleet node. Intended to be called from FleetInfo
	func spawn_fleet(fleet_node, faction_index: int, where=null,
			entry_method = null, initial_ai=combat_engine.ATTACKER_AI,
			ship_name_prefix: String = "MISSING",cargo_hold_fill_fraction: float = 0.0) -> Array:
		print('Faction '+str(faction_index)+' is spawning fleet '+str(fleet_node.get_name())+' at '+str(where))
		assert(fleet_node)
		assert(ship_name_prefix!="MISSING")
		if faction_index<0:
			return []
		var center = null
		var add_radius = null
		var safe_zone = 25
		var rand_halfwidth = 10
		var fleet_angle = null
		var commodities = null
		if immediate_entry:
			entry_method = combat_engine.ENTRY_COMPLETE
		elif entry_method == null:
			if system_info:
				entry_method = combat_engine.ENTRY_FROM_RIFT
			else:
				entry_method = combat_engine.ENTRY_FROM_RIFT_STATIONARY
		if where is NodePath:
			var planet = system.get_node_or_null(where)
			if planet:
				center = planet.translation
				commodities = planet.commodities
				if entry_method==combat_engine.ENTRY_FROM_ORBIT:
					add_radius = randf()
					add_radius = 1.0 - add_radius*add_radius*0.9
					safe_zone = 0
					rand_halfwidth = 1
			else:
				push_warning('no planet at path "'+str(where)+'"')
		elif where is Vector3:
			center = where
		if center==null:
			center = Vector3(0,0,0)
			add_radius = 250*randf()
			fleet_angle = randf()*2*PI
		if add_radius == null:
			add_radius = randf()
			add_radius = 100*add_radius*add_radius
			fleet_angle = randf()*2*PI
		var result: Array = Array()
		for design_name in fleet_node.get_designs():
			var num_ships = int(fleet_node.spawn_count_for(design_name))
			for _n in range(num_ships):
				var design = game_state.ship_designs.get_node_or_null(design_name)
				if design:
					var angle = fleet_angle
					if angle==null:
						angle=randf()*2*PI
					var rand_x = rand_halfwidth*(randf()*2-1)
					var rand_z = rand_halfwidth*(randf()*2-1)
					result.push_back(spawn_ship(
						system,design,faction_index,
						angle,add_radius,rand_x,rand_z,
						safe_zone,center,false,entry_method,initial_ai,
						ship_name_prefix,cargo_hold_fill_fraction,
						commodities))
				else:
					push_warning('Fleet '+str(fleet_node.get_path())+
						' wants to spawn missing design '+str(design_name))
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

	func fill_system(_planet_time: float, ship_time: float, _detail: int):
		if ship_time>0:
			for _i in range(5):
				for faction in faction_states.values():
					if faction.faction_index != player_faction_index:
						faction.make_fleets_available(ship_time/5)
		return [spawn_player_ship()]
