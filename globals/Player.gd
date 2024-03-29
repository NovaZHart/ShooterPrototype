extends Node

const PLAYER_START_SHIP_DESIGN: String = 'thoroughbred_haruspex'
const PLAYER_START_LOCATION: String = '/root/systems/seti-gamma/kindra'

var player_ship_design
var system setget set_system,get_system
var player_location: NodePath = NodePath() setget set_player_location,get_player_location
var departed_location: NodePath = NodePath()
var departed_hyperspace_position: Vector3
var player_name = 'FIXME'
var hyperspace_position: Vector3 setget set_hyperspace_position
var destination_system: NodePath = NodePath() setget set_destination_system
var ship_combat_stats: Dictionary = {}
var money: int = 3800000
var markets: simple_tree.SimpleNode
var ship_parts: simple_tree.SimpleNode
var root: simple_tree.SimpleNode = simple_tree.SimpleNode.new()
var tree: simple_tree.SimpleTree = simple_tree.SimpleTree.new(root)
var stored_system_path
var stored_player_path
var player_faction = 'initial_player_faction'
signal destination_system_changed

func is_entering_from_rift() -> bool:
	var node = game_state.systems.get_node_or_null(player_location)
	return not node or not node.has_method('is_SpaceObjectData')

func set_ship_combat_stats(stats: Dictionary):
	var subset = {}
	for varname in [ 'fuel', 'armor', 'structure', 'shields', 'energy', 'heat' ]:
		if stats.has(varname):
			subset[varname] = stats[varname]
		if stats.has('max_'+varname):
			subset['max_'+varname] = stats['max_'+varname]
	ship_combat_stats = subset

func set_hyperspace_position(new_position: Vector3):
	hyperspace_position = Vector3(new_position.x,0,new_position.z)

func set_destination_system(new_system: NodePath):
	var node = game_state.systems.get_node_or_null(new_system)
	if not node or not node.has_method('is_SystemData'):
		if node:
			push_warning('Tried to set destination system to something that is not a SystemData')
		destination_system=NodePath()
		return
	destination_system = node.get_path()
	emit_signal('destination_system_changed',destination_system)

func read_save_file(filename):
	var file: File = File.new()
	if OK!=file.open(filename,File.READ):
		push_error(filename+': cannot open file for reading')
		return null
	var json_string = file.get_as_text()
	file.close()
	var parsed: JSONParseResult = JSON.parse(json_string)
	if parsed.error:
		push_error(filename+':'+str(parsed.error_line)+': '+parsed.error_string)
		return null
	return game_state.universe.decode_helper(parsed.result)

func write_save_file(state,filename) -> bool:
	var file: File = File.new()
	print('write to '+filename)
	if file.open(filename,File.WRITE)!=OK:
		push_error(filename+': cannot open file for writing')
		return false
	var encoded = game_state.universe.encode_helper(state)
	if not encoded:
		push_error(filename+': cannot encode data for writing to file')
		return false
	var json_string = JSON.print(encoded,'  ')
	if not json_string or not json_string is String:
		push_error(filename+': JSON.print could not generate JSON for file')
		return false
	file.store_string(json_string)
	file.close()
	return true

func store_state():
	var design = game_state.universe.decode_ShipDesign(
		game_state.universe.encode_ShipDesign(player_ship_design))
	return {
		'player_name': player_name,
		'player_location': player_location,
		'player_ship_design': design,
		'hyperspace_position': hyperspace_position,
		'epoch_time': str(game_state.epoch_time),
		'money': money,
		'player_tree_root': root,
		'departed_location': departed_location,
		'departed_hyperspace_position': departed_hyperspace_position,
	}

func add_cargo_to_hold(product_name: String,count: int) -> int:
	# Get the player's cargo:
	var cargo
	if player_ship_design.cargo:
		cargo = player_ship_design.cargo
	else:
		cargo = Commodities.ManyProducts.new()
	
	var player_product = cargo.by_name.get(product_name,null)
	
	if not player_product:
		var product = Commodities.commodities.by_name.get(product_name,null)
		if not product:
			push_warning('Product "'+str(product_name)+'" does not exist.')
			return 0
		cargo.add_product_list([Commodities.commodities.by_name.get(product_name,null)],
			0,null,0,false)
		player_product = cargo.by_name.get(product_name,null)
	
	if not player_product:
		push_error('Failed to add product "'+str(product_name)+'" to player ship cargo')
		return 0
	
	var cargo_mass_before = cargo.get_mass()
	var max_cargo_mass: float = player_ship_design.cached_stats["max_cargo"]
	var available_mass: float = max(0,max_cargo_mass-cargo_mass_before)
	available_mass *= 1000 # convert tons -> kg
	var unit_mass: int = player_product.mass/1000.0
	var allowed_items: int = count
	if unit_mass>0:
		allowed_items = int(floor(available_mass/unit_mass))
# warning-ignore:narrowing_conversion
	var added_items: int = min(count,allowed_items)
	
	if added_items:
		print('Loading '+str(added_items)+' "'+str(product_name)+'" into player cargo hold')
		player_product.quantity += added_items
		player_ship_design.set_cargo(cargo)
		player_ship_design.get_stats()['cargo_mass'] = cargo.get_mass()
	
	return added_items

func products_for_sale_at(planet_path: NodePath,include_all_commodities=false,
		include_all_ship_parts=false) -> Dictionary:
	var result = {}
	
	# If this space object does not exist, nothing can be sold:
	var planet_info = game_state.systems.get_node_or_null(planet_path)
	if not planet_info:
		push_warning('No space object at path '+str(planet_path))
		
		# If there is anything in the cargo, then list it as "unknown"
		if player_ship_design.cargo:
			var unknown_cargo = player_ship_design.cargo.duplicate(true)
			unknown_cargo.remove_absent_products()
			if unknown_cargo.by_name:
				result['unknown'] = unknown_cargo
		
		return result
	
	# Get the player's cargo:
	var cargo
	if player_ship_design.cargo:
		cargo = player_ship_design.cargo
	else:
		cargo = Commodities.ManyProducts.new()
	
	# Find all commodities for sale at the planet, or cargo commodities that
	# can be sold at the planet.
	var commodities_for_sale = update_markets_at(planet_path)
	var commodities_here
	var has_commodities_for_sale = not not commodities_for_sale
	if has_commodities_for_sale:
		commodities_here = Commodities.products_for_market(Commodities.commodities,
			commodities_for_sale,cargo,planet_info,'price_products',
			include_all_commodities)
		result['commodities'] = commodities_here
	else:
		push_warning('no commodities for sale')
		commodities_here = Commodities.ManyProducts.new()
	
	# Find all ship parts for sale at the planet, or ship parts in the cargo
	# that can be sold at the planet.
	var ship_parts_for_sale = Player.update_ship_parts_at(Player.player_location)
	var ship_parts_here
	if ship_parts_for_sale:
		ship_parts_here = Commodities.products_for_market(Commodities.ship_parts,
			ship_parts_for_sale,cargo,planet_info,'price_ship_parts',
			include_all_ship_parts)
		result['ship_parts'] = ship_parts_here
	else:
		ship_parts_here = Commodities.ManyProducts.new()
	
	# If there is nothing in cargo, we're done:
	if not cargo.by_name:
		return result
	
	# Find all cargo that cannot be sold as commodities or ship parts:
	var unknown_player_cargo = Player.player_ship_design.cargo.duplicate(true)
	unknown_player_cargo.remove_named_products(commodities_here)
	unknown_player_cargo.remove_named_products(ship_parts_here)
	unknown_player_cargo.remove_absent_products()
	if unknown_player_cargo.by_name:
		result['unknown'] = unknown_player_cargo
	
	return result


func restore_state(state: Dictionary,restore_from_load_page = true):
	player_name = state['player_name']
	money = state.get('money',98000)
	set_player_location(state['player_location'])
	if state.has('hyperspace_position'):
		set_hyperspace_position(state['hyperspace_position'])
	player_ship_design = state['player_ship_design']
	var timestr: String = str(state.get('epoch_time','0'))
	departed_location = state.get('departed_location',player_location)
	departed_hyperspace_position = state.get('departed_hyperspace_position',hyperspace_position)
	if timestr.is_valid_integer():
		game_state.epoch_time = int(timestr)
	player_ship_design.name = 'player_ship_design'
	var old_design = game_state.ship_designs.get_node_or_null('player_ship_design')
	if old_design:
		var _discard = game_state.ship_designs.remove_child(old_design)
	var _discard = game_state.ship_designs.add_child(player_ship_design)
	game_state.restore_from_load_page = not not restore_from_load_page
	game_state.change_scene('res://ui/OrbitalScreen.tscn')
	var player_tree_root = state.get('player_tree_root',null)
	if markets:
		var _ignore = markets.remove_all_children()
	if player_tree_root:
		tree.root = state['player_tree_root']
		root = tree.root
		markets = ensure_markets_node()
		ship_parts = ensure_ship_parts_node()

func _on_universe_preload():
	stored_system_path = system.get_path() if system else NodePath()
	stored_player_path = player_location
	system=null
	player_location=NodePath()

func _on_universe_postload():
	if stored_player_path:
		set_player_location(stored_player_path)
	elif stored_system_path:
		set_system(stored_system_path)
	else:
		var system_names = game_state.systems.get_child_names()
		if system_names:
			set_system(system_names[0])
			if system:
				push_warning('After load, system '+str(stored_system_path)
					+' no longer exists. Will go to system '+system.get_path())
				get_tree().get_root().change_scene('res://ui/OrbitalScreen.gd')
				return true
		push_error('After load, no systems exist. Universe is empty. Player is at an invalid location.')
	stored_player_path = null
	stored_system_path = null
	get_tree().get_root().change_scene('res://ui/OrbitalScreen.gd')

func get_system(): return system
func set_system(var s):
	if s is NodePath:
		var system_at_path = game_state.systems.get_node_or_null(s)
		if not system_at_path.has_method('is_SystemData'):
			push_error('Tried to go to a non-system at path '+str(s))
			return system
		system = system_at_path
	elif s is simple_tree.SimpleNode:
		var s_path = s.get_path()
		var system_at_path = game_state.systems.get_node_or_null(s_path)
		if not system_at_path.has_method('is_SystemData'):
			push_error('Specified system is not in tree at path '+str(s_path))
			return system
		system = system_at_path
	elif s is String:
		var system_for_name = game_state.systems.get_child_with_name(s)
		if system_for_name:
			system = system_for_name
			player_location = game_state.systems.get_path_to(system)
		return system

func apply_departure():
	departed_location = player_location
	departed_hyperspace_position = hyperspace_position

func go_back_to_departure():
	set_player_location(departed_location)
	set_hyperspace_position(departed_hyperspace_position)

func get_player_location() -> NodePath:
	return player_location
func set_player_location(s: NodePath):
	var n = game_state.systems.get_node_or_null(s)
	if n!=null:
		var loc = game_state.systems.get_path_to(n)
		var system_name = loc.get_name(0)
		if game_state.systems.has_child(system_name):
			system = game_state.systems.get_child_with_name(system_name)
			player_location = n.get_path()
			if not hyperspace_position or system.show_on_map:
				set_hyperspace_position(system.position)
		else:
			push_error('No system parent at path '+str(s))
	else:
		push_error('no SimpleNode at path '+str(s))
	return player_location

func get_player_translation(planet_time: float) -> Vector3:
	var node = game_state.systems.get_node_or_null(player_location)
	if node==null or not node.has_method('planet_translation'):
		return Vector3()
	return node.planet_translation(planet_time)

func get_space_object_unique_name() -> String:
	var n = game_state.systems.get_node_or_null(player_location)
	if n!=null and n.has_method('is_SpaceObjectData'):
		return n.make_unique_name()
	return ""

func get_space_object_or_null():
	var n = game_state.systems.get_node_or_null(player_location)
	if n!=null and n.has_method('is_SpaceObjectData'):
		return n
	push_error('SimpleNode '+str(n)+' is not a SpaceObjectData')
	return null

func get_info_or_null():
	var n: simple_tree.SimpleNode = game_state.systems.get_node_or_null(player_location)
	if n!=null and n is simple_tree.SimpleNode:
		return n
	return null

func assemble_player_ship(): # -> RigidBody or null
	if not player_ship_design:
		return null
	return player_ship_design.assemble_ship()

func age_off_markets(age: int = game_state.EPOCH_ONE_DAY*14):
	Commodities.delete_old_products(markets,game_state.epoch_time-age)

func age_off_ship_parts(age: int = game_state.EPOCH_ONE_DAY*14):
	Commodities.delete_old_products(ship_parts,game_state.epoch_time-age)

func update_ship_parts_at(path_in_universe: NodePath, dropoff: float = 0.7, scale: float = 1.0/game_state.EPOCH_ONE_DAY):
	var place: simple_tree.SimpleNode = game_state.systems.get_node_or_null(path_in_universe)
	if place and place.has_method('is_SpaceObjectData') and place.has_market():
		var relpath: NodePath = game_state.systems.get_path_to(place)
		var ship_parts_node = null
		if relpath:
			var universe_node = game_state.systems
			ship_parts_node = ship_parts
			for iname in relpath.get_name_count():
				var child_name = relpath.get_name(iname)
				universe_node = universe_node.get_child_with_name(child_name)
				var next = ship_parts_node.get_child_with_name(child_name)
				if not universe_node.has_method('is_SpaceObjectData'):
					if not next:
						next = simple_tree.SimpleNode.new()
						next.name = child_name
						if not ship_parts_node.add_child(next):
							push_error('Cannot add "'+child_name+'" child of '+str(ship_parts_node.get_path()))
					ship_parts_node = next
					continue
				if not next or next.update_time<game_state.epoch_time:
					var local_ship_parts = Commodities.ManyProducts.new()
					universe_node.list_ship_parts(Commodities.ship_parts, local_ship_parts)
					if next:
						next.update(local_ship_parts,game_state.epoch_time,dropoff,scale)
					else:
						next = Commodities.ProductsNode.new(local_ship_parts,game_state.epoch_time)
						next.name = child_name
						if not ship_parts_node.add_child(next):
							push_error('Cannot add "'+child_name+'" child of '+str(ship_parts_node.get_path()))
				ship_parts_node = next
			if ship_parts_node and ship_parts_node.has_method('is_ProductsNode'):
				return ship_parts_node.products
	return null

func update_markets_at(path_in_universe: NodePath, dropoff: float = 0.7, scale: float = 1.0/game_state.EPOCH_ONE_DAY):
	var place: simple_tree.SimpleNode = game_state.systems.get_node_or_null(path_in_universe)
	if place and place.has_method('is_SpaceObjectData') and place.has_market():
		var relpath: NodePath = game_state.systems.get_path_to(place)
		if relpath:
			var universe_node = game_state.systems
			var market_node = markets
			for iname in relpath.get_name_count():
				var child_name = relpath.get_name(iname)
				universe_node = universe_node.get_child_with_name(child_name)
				var next = market_node.get_child_with_name(child_name)
				if not universe_node.has_method('is_SpaceObjectData'):
					if not next:
						next = simple_tree.SimpleNode.new()
						next.name = child_name
						if not market_node.add_child(next):
							push_error('Cannot add "'+child_name+'" child of '+str(market_node.get_path()))
					market_node = next
					continue
				if not next or next.update_time<game_state.epoch_time:
					var local_products = Commodities.ManyProducts.new()
					universe_node.list_products(Commodities.commodities, local_products)
					var v = local_products.by_name.get('vitamins')
					if v:
						assert(v.value>0)
					if next:
						next.update(local_products,game_state.epoch_time,dropoff,scale)
					else:
						next = Commodities.ProductsNode.new(local_products,game_state.epoch_time)
						next.name = child_name
						if not market_node.add_child(next):
							push_error('Cannot add "'+child_name+'" child of '+str(market_node.get_path()))
				market_node = next
		var market_node = markets.get_node(relpath)
		if market_node and market_node.has_method('is_ProductsNode'):
			return market_node.products
	return null

func ensure_markets_node():
	var markets_node = root.get_child_with_name('markets')
	if not markets_node:
		markets_node = simple_tree.SimpleNode.new()
		markets_node.name = 'markets'
		if not root.add_child(markets_node):
			push_error('Cannot add the "markets" node to Player\'s tree.')
	markets = markets_node
	return markets

func ensure_ship_parts_node():
	var ship_parts_node = root.get_child_with_name('ship_parts')
	if not ship_parts_node:
		ship_parts_node = simple_tree.SimpleNode.new()
		ship_parts_node.name = 'ship_parts'
		if not root.add_child(ship_parts_node):
			push_error('Cannot add the "ship_parts" node to Player\'s tree.')
	ship_parts = ship_parts_node
	return ship_parts

func _enter_tree():
	var start_node: NodePath = NodePath(PLAYER_START_LOCATION)
	assert(game_state.tree.get_node_or_null(start_node))
	var planet = game_state.systems.get_node_or_null(start_node)
	assert(planet)
	
	set_player_location(planet.get_path())
	assert(player_location)
	assert(system)
	
	#var start_ship = game_state.ship_designs.get_node_or_null('godship')
	var start_ship = game_state.ship_designs.get_node_or_null(PLAYER_START_SHIP_DESIGN)
	assert(start_ship)
	player_ship_design = start_ship
	
	var _discard = game_state.connect('universe_preload',self,'_on_universe_preload')
	_discard = game_state.connect('universe_postload',self,'_on_universe_postload')
	
	ensure_markets_node()
	ensure_ship_parts_node()
