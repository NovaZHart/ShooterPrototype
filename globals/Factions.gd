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
	var fleets: Array = []
	func is_Faction(): pass # never called; just used for type checking
	func _init(display_name_: String = '', fleets_: Array = [], default_resources_: float = 1000.0,
			string_affinities_: Dictionary = {}):
		default_resources=default_resources_
		affinities=string_affinities_.duplicate(true)
	func _ready():
		if not display_name:
			display_name = name.capitalize()
	func make_faction_state(combat_state: CombatState):
		var system_info = combat_state.system_info
		var faction_info = system_info.active_factions.get(name,{})
		var resources = faction_info.get('starting_money',default_resources)
		# Default gain rate is full resources every 5 minutes
		var gain_rate = faction_info.get('income_per_second',resources/300.)
		var fleet_type_weights = faction_info.get('fleet_type_weights',{})
		var state = FactionState.new(resources,gain_rate,min_fleet_cost,
			affinities.duplicate(true),fleet_type_weights.duplicate(true))
		_impl_calculate_min_fleet_costs(state)
		_impl_store_goals(combat_state,state)
		return state
	func _impl_calculate_min_fleet_cost(faction_state: FactionState):
		var min_cost = INF
		for fleet in fleets:
			var fleet = fleets[ifleet]
			var fleet_type = fleets.get('type','')
			var type_weight = faction_state.fleet_type_weights.get(fleet_type,0.0)
			if type_weight<=0.0:
				continue # this fleet does not appear in the system
			var name = fleet['fleet']
			var data = game_state.fleets.get_node_or_null(name)
			if data:
				var local_fleet = fleet.duplicate(true)
				var cost = data.get_cost()
				min_cost = min(min_cost,cost)
				local_fleet['cost'] = cost
				local_fleet['threat'] = data.get_threat()
				local_fleet['frequency'] *= type_weight
				local_fleet['ships'] = data.spawn_count()
				faction_state.fleets.append(local_fleet)
		faction_state.min_fleet_cost = min_cost
	func _impl_store_goals(combat_state: CombatState,faction_state: FactionState):
		var my_name = get_name()
		for goal in combat_state.system_info.faction_goals:
			var faction_name = goal.get('faction_name','')
			if faction_name!=my_name:
				continue
			var target_faction = goal.get('target_faction','')
			if not game_state.factions.get_child_with_name(target_faction):
				push_warning('Ignoring goal with invalid faction "'+str(target_faction)+'": '+str(goal))
				continue
			var target_path: NodePath = goal.get('target_location',NodePath())
			var spawn_point: Vector3 = Vector3(0,0,0)
			var target_rid: RID = RID()
			if target_path:
				var target_node = combat_state.system_info.get_node_or_null(target_node)
				if not target_node:
					push_warning('Ignoring goal with invalid target path "'+str(target_path)+'": '+str(goal))
					continue
				var unique_name = target_node.make_unique_name()
				var spawned_planet = combat_state.system.get_node_or_null(NodePath("Planets/"+target_location)
				if not spawned_planet:
					push_warning('Location "'+str(unique_name)+'" was not spawned in the system!')
				else:
					target_rid = spawned_planet.get_rid()
			state.goals.append({
				'action':goal.get('action','patrol'),
				'target_faction':target_faction,
				'target_rid':target_rid,
				'radius':max(0.0,float(goal.get('radius',100.0))),
				'weight':max(0.0,float(goal.get('weight',1.0))),
				'goal_status':0.0,
				'suggested_spawn_point':spawn_point,
			})
	func get_affinity(other_faction_index: int) -> float:
		return float(affinities.get(other_faction_index,0.0))
	func encode():
		return [ 'Faction',
			game_state.Universe.encode_helper(fleets), default_resources,
			game_state.Universe.encode_helper(string_affinities),
			game_state.Universe.encode_children(self) ]

#
# NOT INCORPORATED:
#
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
					'target_faction':int(goal.get('target_faction',ALL_FACTIONS)),
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

func decode_Faction(v):
	var result = Faction.new(
		game_state.Universe.decode_helper(v[1]), float(v[2]),
		game_state.Universe.decode_helper(v[3]))
	game_state.Universe.decode_children(result)
	return result


class FactionState extends Reference:
	# Resources for a faction in space, while the player is in the system.
	# Deleted upon player exit.
	var resources_available: float
	var resource_gain_rate: float
	var min_resources_to_act: float
	var goals: Array = []
	var fleets = []
	var fleet_type_weights: Dictionary = {}
	var min_fleet_cost: float = 0.0
	func _init(resources_available_: float,resource_gain_rate_: float,
			min_resources_to_act_: float, fleet_type_weights_:Dictionary):
		resources_available = resources_available_
		resource_gain_rate = resource_gain_rate_
		min_resources_to_act = min_resources_to_act_
		fleet_type_weights = fleet_type_weights_

	func data_for_native(combat_state: CombatState,faction_index: int):
		var result = { 'faction': faction_index, 'goals': [] }
		for goal in goals:
			var target_faction: String = goal['target_faction']
			var target_int = -1
			if target_faction:
				target_int = combat_state.faction_name2int.get(target_faction,ALL_FACTIONS)
			var rgoal = goal.duplicate(true)
			rgoal['target_faction'] = target_int
			result['goals'].append(rgoal)
	func update_from_native(combat_state: CombatState,faction_index: int,data: Dictionary)
		var igoal = -1
		var goal_status: PoolRealArray = data['goal_status']
		var suggested_spawn_points = data['suggested_spawn_points']
		for goal in goals:
			igoal += 1
			goal['goal_status'] = goal_status[igoal]
			goal['suggested_spawn_point'] = suggested_spawn_point[igoal]

class CombatState extends Reference:
	# Information about factions and ship locations in the system which the
	# player is currently flying. Deleted upon player exit.
	var system_info = null
	var system = null
	var immediate_entry: bool = false
        var player_faction_name: String

	var planet_tactical_data: Dictionary = {}
	var system_tactical_data: TacticalData
	var faction_states: Dictionary = {}
	var faction_int2name: Dictionary = {}
	var faction_name2int: Dictionary = {}
	var faction_int_affinity: Dictionary = {}

	func _init(system_info_, system_, immediate_entry_: bool):
		system_info = system_info_
		system = system_
		immediate_entry = immediate_entry_
		system_tactical_data = TacticalData.new(system_info.get_path(),system_info.name)
		_impl_add_planets(system_info)
		_impl_add_faction(player_faction_name)
		player_faction_index = faction_name2int[player_faction_name]
                assert(player_faction_index==0)
		for goal in system.faction_goals:
			_impl_add_faction(goal.get('faction_name',''))
		player_faction_name = Player.player_faction
		for faction_name in faction_states:
			_impl_add_faction_affinities(faction_name)
	func get_faction_affinity(from_faction: int, to_faction: int):
		var key = (from_faction<<Factions.FACTION_BIT_SHIFT) | to_faction
		return faction_int_affinity.get(key,0)
	func get_faction_affinities(from_faction: int):
		for to_faction in faction_int2name:
			if to_faction==from_faction:
				continue
			var key = (from_faction<<Factions.FACTION_BIT_SHIFT) | to_faction
			var affinity = faction_int_affinity.get(key,0)
			if affinity!=0:
				result[to_faction] = affinity
	func get_faction_state(faction_name):
		return faction_states.get(faction_name,null)
	func get_planet_tactical_data(system_relative_path:NodePath):
		return planet_tactical_data.get(system_relative_path,null)
	func get_system_tactical_data():
		return system_tactical_data
	func add_factions(faction_names):
		var added: bool = false
		for name in faction_names:
			if not faction_name2int.has(name):
				_impl_add_faction(faction_name)
				added = true
		if added:
			for name in faction_name2int:
				_impl_add_faction_affinities(name)

	func data_for_native():
		var result = { "affinities": faction_int_affinity, "active_factions": [],
			"player_faction":player_faction_index }
		for faction_name in faction_states:
			var faction_int = faction_name2int[faction_name]
			var faction = game_state.get(faction_name,null)
			if faction:
				active_factions[faction_int] = faction.data_for_native(self)

	func update_from_native(native_data):
		var system_data = native_data.get('system_data',null)
		if system_data:
			system_data.update_from_native(system_data)
		for native_planet_data in native_data.get('planet_data',null)
			var unique_name = native_planet_data.get('name','')
			var planet_data = planet_tactical_data.get(unique_name,null)
			if planet_data:
				planet_data.update_from_native(native_planet_data)

	func _impl_add_faction_affinities(faction_name):
		var faction = game_state.factions.get_child_with_name(faction_name)
		if not faction:
			return
		var from_index: int = faction_name2int.find(faction_name,-1)
		if from_index<0:
			_impl_add_faction(name)
			from_index = faction_name2int.find(faction_name,-1)
			if from_index<0:
				push_error('Cannot add faction "'+str(faction_name)+'"')
				return
		for affinity_to_name in faction.affinities:
			var to_index: int = faction_name2int.get(affinity_to_name,-1)
			if to_index>=0:
				faction_int_affinity[(from_faction << FACTION_BIT_SHIFT)|to_faction] = \
					faction.affinities[affinity_to_name]
	func _impl_add_faction(name):
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
	func _impl_add_planets(node):
		if node.has_method('is_SpaceObjectData'):
			var unique_name = node.make_unique_name()
			planet_tactical_data[unique_name] = TacticalData.new(node.get_path(),node.make_unique_name())
		for child_name in node.get_child_names():
			var child = node.get_child_with_name(child_name)
			if child:
				_impl_add_planets(child)


class TacticalData extends Reference:
	var path: NodePath = NodePath()
	var combat_data_ref: WeakRef
	var unique_name: String = ''
	var distances: PoolRealArray
	var threats: PoolRealArray
	var costs: PoolRealArray
	var factions: PoolIntArray
	func _init(path_,unique_name_,combat_data,
			distances_:PoolRealArray = PoolRealArray(),
			threats_:PoolRealArray = PoolRealArray(),
			costs_:PoolRealArray = PoolRealArray(),
			factions_:PoolIntArray = PoolIntArray)
		path=path_
		unique_name=unique_name_
		distances=distances_
		threats=threats_
		costs=costs_
		factions=factions_
		set_combat_data(combat_data)
	func update_from_native(data):
		distances = data['ship_distances']
		threats = data['ship_threats']
		costs = data['ship_costs']
		factions = data['ship_factions']
	func set_combat_data(combat_data):
		combat_data_ref = WeakRef(combat_data)
	func get_combat_data():
		return combat_data_ref.get_ref()
	func _impl_strength(from_faction: int, stat: PoolRealArray, max_distance: float,
			weighted: int) -> Dictionary:
		var result: Dictionary = {'self':0.0, 'ally':0.0, 'enemy':0.0, 'neutral':0.0]
		var affinities = null
		var denom = max(1.0,max_distance)
		var weight: float = 1.0
		for i in range(len(distances)):
			if distances[i]>max_distance:
				break
			if weighted==1 or weighted==2:
				weight = 1.0 - distances[i]/denom
				if weighted==2:
					weight *= weight
			var to_faction = factions[i]
			if from_faction == to_faction:
				result['self'] += stat[i]*weight
			if affinities==null:
				affinities = get_combat_data().get_faction_affinities(from_faction)
			var affinity = affinities.get(factions[i],0)
			if affinity>AFFINITY_EPSILON:
				result['ally'] += stat[i]*weight
			elif affinity<-AFFINITY_EPSILON:
				result['enemy'] += stat[i]*weight
			else:
				result['neutral'] += stat[i]*weight
		return result
