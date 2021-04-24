extends Node

class FactionList extends simple_tree.SimpleNode:
	var last_index = -1
	var faction_indices: Dictionary = {}
	var faction_mutex: Mutex = Mutex.new()
	func is_FactionList(): pass # never called; just used for type checking
	func get_faction_or_null(name: String): # -> Faction or null
		var node = get_node_or_null(name)
		return node.faction_index if node else -1
	func remove_faction(data) -> bool:
		faction_mutex.lock()
		var success = faction_indices.erase(data.name)
		success = remove_child(data) or success
		faction_mutex.unlock()
		return success
	func add_faction(data) -> int:
		faction_mutex.lock()
		var _ignore = add_child(data)
		last_index += 1
		data.faction_index = last_index
		faction_indices[data.name] = last_index
		faction_mutex.unlock()
		return data.faction_index
	func data_for_native():
		var faction_count = last_index+1
		var faction_ints = PoolIntArray()
		var other_faction_ints = PoolIntArray()
		var affinity_reals = PoolRealArray()
		for child_name in get_child_names():
			var child = get_child_with_name(child_name)
			if child and child.has_method('is_Faction'):
				var faction_index: int = child.faction_index
				faction_ints.append(faction_index)
				other_faction_ints.append(-1)
				affinity_reals.append(child.default_affinity)
				for other_faction_index in child.affinities:
					faction_ints.append(faction_index)
					other_faction_ints.append(other_faction_index)
					affinity_reals.append(child.affinities[other_faction_index])
		return {'faction_count':faction_count,'affinity_from':faction_ints,
			'affinity_to':other_faction_ints,'affinity_value':affinity_reals}
	func encode():
		return [ 'FactionList', game_state.Universe.encode_children(self) ]

func decode_FactionList(v):
	var result = FactionList.new()
	game_state.Universe.decode_children(result,v[1])
	# Note: child _ready() will call add_faction on the child.
	return result

class Faction extends simple_tree.SimpleNode:
	var affinities: Dictionary = {}
	var string_affinities: Dictionary = {}
	var default_affinity: float = 0.0
	var default_resources: float = 1000.0
	var min_fleet_cost: float = 0.0
	var faction_index: int = -1
	var fleets: Array = []
	func is_Faction(): pass # never called; just used for type checking
	func _init(fleets_: Array = [], default_resources_: float = 1000.0,
			string_affinities_: Dictionary = {}, default_affinity_: float=0.0):
		default_resources=default_resources_
		string_affinities=string_affinities_.duplicate(true)
		default_affinity=float(default_affinity_)
		fleets = fleets_.duplicate(true)
		var delete_me: Array = []
		var min_cost = INF
		for ifleet in range(len(fleets)):
			var fleet = fleets[ifleet]
			var name = fleet['fleet']
			var data = game_state.fleets.get_node_or_null(name)
			if not data:
				delete_me.append(ifleet)
			else:
				var cost = data.get_cost()
				fleet['cost'] = cost
				min_cost = min(min_cost,cost)
				fleet['threat'] = data.get_threat()
			min_fleet_cost = min_cost
	func _impl_find_faction_list(node):
		# Walk up the tree looking for a FactionList anscestor.
		# The node must be a simple_tree.SimpleNode
		if node is Object:
			return null
		elif node.has_method('is_FactionList'):
			return node
		else:
			return _impl_find_faction_list(node.get_parent())
	func _ready():
		var faction_list = _impl_find_faction_list(get_parent())
		if faction_list:
			faction_list.add_faction(self)
			for faction_name in string_affinities:
				var faction = faction_list.get_faction_or_null(faction_name)
				affinities[faction.faction_index] = string_affinities[faction_name]
	func get_or_add_faction_state(combat_state: CombatState):
		var state = combat_state.get_faction_state(faction_index)
		if not state:
			var system_info = combat_state.system_info
			var resources = system_info.faction_starting_money.get(name,default_resources)
			var gain_rate = system_info.faction_income_per_second.get(name,resources)
			state = combat_state.add_faction_state(faction_index,FactionState.new(
				resources,gain_rate,min_fleet_cost))
		return state
	func data_for_native(combat_state: CombatState):
		var goal_target_faction = PoolIntArray()
		var goal_target_location = PoolStringArray()
		var goal_radius = PoolRealArray()
		var goal_weight = PoolRealArray()
		var goals = combat_state.system_info.faction_goals.get(name,[])
		for goal in goals:
			var goal_name = goal.get('name','')
			if goal_name:
				goal_target_faction.append(int(goal.get('target_faction',-1)))
				goal_target_location.append(goal.get('target_location',''))
				goal_radius.append(float(goal.get('radius',100.0)))
				goal_weight.append(max(0.0,float(goal.get('weight',1.0))))
	func _impl_process_goal_weights(combat_state: CombatState,state: FactionState):
		var weights: Array = []
		var goals = combat_state.system_info.faction_goals.get(name,[])
		var igoal = -1
		for goal in goals:
			igoal += 1
			if igoal>=state.goal_status.size():
				push_error('Not enough goal statuses for goal list')
				break
			var goal_status = state.goal_status[igoal]
			var goal_name = goal.get('goal_action','')
			if goal_name:
				var args = {
					'target_faction':int(goal.get('target_faction',-1)),
					'target_location':goal.get('target_location',''),
					'radius':float(goal.get('radius',100.0)),
					'weight':max(0.0,float(goal.get('weight',1.0))),
					'goal_status':goal_status,
					'suggested_spawn_point':state.suggested_spawn_point[igoal],
				}
				weights.append([igoal,goal_name,clamp(call('weight_'+goal_name,args),0.0,1e12),args])
		return weights
	func _impl_choose_goal_from_weights(weights):
		var total_weight = 0
		for goal_data in weights:
			total_weight += goal_data[2]
		var decision_weight = randf()*total_weight
		var remainder = decision_weight
		var decision_index = 0
		while decision_weight<len(weights)-1:
			var goal_weight = weights[decision_index][2]
			if decision_weight<=remainder:
				break
			remainder -= goal_weight
		return decision_index
	func process_space(combat_state: CombatState,delta: float):
		var faction_state = get_or_add_faction_state(combat_state)
		faction_state.resources_available += delta*faction_state.resource_gain_rate
		if faction_state.resources_available < faction_state.min_resources_to_act:
			return
		if not fleets:
			return
		var weights = _impl_process_goal_weights(combat_state,faction_state)
		if not weights:
			return
		var decision_index = _impl_choose_goal_from_weights(weights)
		if decision_index<len(weights) and decision_index>=0:
			var action = weights[decision_index]
			call('spawn_'+action[1],action[3])
	func get_affinity(other_faction_index: int) -> float:
		return float(affinities.get(other_faction_index,default_affinity))
	func encode():
		return [ 'Faction',
			game_state.Universe.encode_helper(fleets), default_resources,
			game_state.Universe.encode_helper(string_affinities),
			default_affinity, game_state.Universe.encode_children(self) ]

func decode_Faction(v):
	var result = Faction.new(
		game_state.Universe.decode_helper(v[1]), float(v[2]),
		game_state.Universe.decode_helper(v[3]), float(v[4]))
	game_state.Universe.decode_children(result)
	return result


class TacticalInfo extends Reference:
	var space_object: NodePath = NodePath()
	var distances: PoolRealArray
	var threat_levels: PoolRealArray
	var faction_indices: PoolIntArray
	func _init(distances_:PoolRealArray,threat_levels_:PoolRealArray,
			faction_indices_:PoolIntArray,space_object_=NodePath()):
		distances=distances_
		threat_levels=threat_levels_
		faction_indices=faction_indices_
		space_object=space_object_
	func faction_strength(faction, max_distance: float, weighted=0) -> Dictionary:
		var result: Array = [0.0, 0.0, 0.0, 0.0]
		var weight: float = 1.0
		for i in range(len(faction)):
			if distances[i]>max_distance:
				break
			if weighted:
				weight = 1.0-(distances[i]/max_distance)
				if weighted==2:
					weight *= weight
			var faction_index = faction_indices[i]
			if faction_index == faction.faction_index:
				result[0] += threat_levels[i]*weight
				continue
			var affinity = faction.get_affinity(faction_index)
			if affinity>1e-9:
				result[1] += threat_levels[i]*weight
			elif affinity<-1e-9:
				result[2] += threat_levels[i]*weight
			else:
				result[3] += threat_levels[i]*weight
		return { 'self':result[0], 'ally':result[1], 'enemy':result[2],
			'neutral':result[3] }

class FactionState extends Reference:
	var resources_available: float
	var resource_gain_rate: float
	var min_resources_to_act: float
	var goal_status: PoolRealArray = PoolRealArray()
	var suggested_spawn_point: PoolVector3Array = PoolVector3Array()
	func _init(resources_available_: float,resource_gain_rate_: float,
			min_resources_to_act_: float):
		resources_available = resources_available_
		resource_gain_rate = resource_gain_rate_
		min_resources_to_act = min_resources_to_act_

class CombatState extends Reference:
	var system_info = null # FIXME
	var system = null # FIXME
	var immediate_entry: bool = false
	var active_factions: Dictionary = {}
	var planet_tactical_data: Dictionary = {}
	var system_tactical_data: TacticalInfo
	var faction_state: Dictionary = {}
	func add_faction_state(faction_index: int,state: Reference):
		faction_state[faction_index]=state
	func get_faction_state(faction_index: int):
		return faction_state.get(faction_index,null)
	func _init(system_info_,system_,system_tactical_data_):
		system_info = system_info_
		system = system_
		system_tactical_data = system_tactical_data_
	func get_planet_data(path:NodePath): # -> TacticalInfo or null
		var absolute_path: NodePath = path
		if not path.is_absolute():
			var node = game_state.system_data.get_node_or_null(path)
			absolute_path = node.get_path()
		return planet_tactical_data.get(absolute_path,null)
	func add_planet_data(path:NodePath,data:Reference):
		var absolute_path: NodePath = path
		if not path.is_absolute():
			var node = game_state.system_data.get_node_or_null(path)
			absolute_path = node.get_path()
		planet_tactical_data[absolute_path]=data
	func add_faction(name: String,faction_index: int):
		active_factions[faction_index]=name
