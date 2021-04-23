extends Node

class FactionList extends simple_tree.SimpleNode:
	var last_index = -1
	var faction_indices: Dictionary = {}
	var faction_mutex: Mutex = Mutex.new()
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
			var affinity = faction.affinity(faction_index)
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

class Faction extends simple_tree.SimpleNode:
	var affinities: Dictionary = {}
	var string_affinities: Dictionary = {}
	var default_affinity: float = 0.0
	var default_resources: float = 1000.0
	var min_fleet_cost: float = 0.0
	var faction_index: int = -1
	var fleets: Array = []
	func _init(faction_list: FactionList,fleets_: Array = [],
			default_resources_: float = 1000.0, string_affinities_: Dictionary = {},
			default_affinity_: float=0.0):
		default_resources=default_resources_
		string_affinities=string_affinities_.duplicate(true)
		default_affinity=float(default_affinity_)
		faction_index = faction_list.add_faction(self)
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
	func postload():
		var faction_list = get_parent()
		for faction_name in string_affinities:
			var faction = faction_list.get_faction_or_null(faction_name)
			affinities[faction.faction_index] = string_affinities[faction_name]
		postload_children()
	func get_or_add_faction_state(combat_state: CombatState):
		var state = combat_state.get_faction_state(faction_index)
		if not state:
			var system_info = combat_state.system_info
			var resources = system_info.faction_starting_money.get(name,default_resources)
			var gain_rate = system_info.faction_income_per_second.get(name,resources)
			state = combat_state.add_faction_state(faction_index,FactionState.new(
				resources,gain_rate,min_fleet_cost))
		return state
	func process_space(combat_state: CombatState,delta: float):
		var state = get_or_add_faction_state(combat_state)
		state.resources_available += delta*state.resource_gain_rate
		if state.resources_available < state.min_resources_to_act:
			return
		var weights: Dictionary = {}
		var goals = combat_state.system_info.faction_goals.get(name,[])
		for igoal in range(len(goals)):
			var goal = goals[igoal]
			if goal[0]>0 and has_method(goal[1]):
				weights[igoal] = call(goal[1],goal[2])
	func affinity(other_faction_index: int) -> float:
		return float(affinities.get(other_faction_index,default_affinity))
