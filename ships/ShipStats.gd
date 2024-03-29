extends RigidBody

# In this list, -1 means, "use calculated defaults in add_stats"

export var help_page: String = 'hulls'
export var base_mass: float = 0
export var base_thrust: float = -1
export var base_reverse_thrust: float = -1
export var base_turning_thrust: float = -1
export var base_hyperthrust: float = 0
export var base_shields: float = 1600
export var base_armor: float = 1000
export var base_structure: float = 600
export var base_fuel: float = 30
export var heal_shields: float = -1
export var heal_armor: float = 0
export var heal_structure: float = -1
export var heal_fuel: float = 30
export var fuel_efficiency: float = 0.9
export var base_drag: float = 1.5
export var base_turn_drag: float = 1.5
#export var base_turn_rate: float = 2
export var base_threat: float = -1
export var base_explosion_damage: float = -1
export var base_explosion_radius: float = -1
export var base_explosion_impulse: float = -1
export var base_explosion_delay: int = 10
export var explosion_type: int = 8 # combat_engine.DAMAGE_EXPLOSIVE
export var base_max_cargo: int = 20
export var armor_inverse_density: float = 200.0
export var fuel_inverse_density: float = 10.0
export var override_size: Vector3 = Vector3(0,0,0)

export var rifting_damage_multiplier: float = 0.5

export var base_heat_capacity: float = 0.2
export var base_cooling: float = -1.0
export var base_shield_repair_heat: float = 0.013
export var base_armor_repair_heat: float = 0.0165
export var base_structure_repair_heat: float = .02
export var base_shield_repair_energy: float = 0.13
export var base_armor_repair_energy: float = 0.165
export var base_structure_repair_energy: float = .2
export var base_forward_thrust_heat: float = 0.3
export var base_reverse_thrust_heat: float = 0.3
export var base_turning_thrust_heat: float = 0.9
export var base_forward_thrust_energy: float = 0.05
export var base_reverse_thrust_energy: float = 0.05
export var base_turning_thrust_energy: float = 0.15
export var base_battery: float = -1
export var base_power: float = -1

export var ai_type: int = 0 setget set_ai_type

export var flotsam: Dictionary = {
	'diamonds':2,
	'transport_barge':5,
	'medical_supplies':12,
	'invalid_product':10,
	'intoxicants':8,
	'scrap_metal':30,
	'cargo':25,
	'cargo2':25,
	'cargo3':25,
	'cargo4':25
}
export var flotsam_meshes: Array = []
export var cargo_puff: Mesh = preload('res://effects/meshes/cargo-puff.mesh');
export var cargo_web_add_radius: float = 3
export var cargo_web_strength: float = -1

################################################################  0    1    2    3    4    5    6    7    8    9    10   11   12   13   14   15    16
################################################################ TYP  LGT  HEP  PRC  IMP  EMF  GRV  ATM  EPL  PSI  PLS  CRG  SPR  TMP  BIO  LIF   UNR
export var base_shield_resist: PoolRealArray =    PoolRealArray([0.0, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.0, 0.0,-0.3, 0.0, 0.0, 0.3,  0.0])
export var base_shield_passthru: PoolRealArray =  PoolRealArray([0.0, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3,  1.0])
export var base_armor_resist: PoolRealArray =     PoolRealArray([0.0, 0.1, 0.2, 0.2, 0.2, 0.1, 0.1,-0.7, 0.2, 0.0, 0.2, 0.1, 0.0, 0.0, 0.2, 0.1,  0.0])
export var base_armor_passthru: PoolRealArray =   PoolRealArray([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,  1.0])
export var base_structure_resist: PoolRealArray = PoolRealArray([0.0, 0.0, 0.0, 0.1, 0.0,-0.2, 0.2,-1.0,-0.1, 0.0, 0.0,-0.1,-0.1, 0.0, 0.1, 0.75, 0.0])

var ship_display_name: String = 'Unnamed'
var item_slots: int = -1 setget set_item_slots,get_item_slots
var combined_stats: Dictionary = {'weapons':[],'equipment':[],'salvage':[]}
var stats_overridden: Dictionary = {}
var non_weapon_stats: Array = []
#var team: int = 0
#var enemy_team: int = 1
#var enemy_mask: int = 2
var faction_index: int = -1
var height: float = 5 setget set_height
var random_height: bool = true
var transforms: Dictionary = {}
var retain_hidden_mounts: bool = false
var cargo setget set_cargo

var skipped_runtime_stats: bool = true

func is_ShipStats(): pass # for type detection; never called

func set_height(new_height: float):
	height=new_height
	combined_stats['visual_height'] = new_height+game_state.SHIP_HEIGHT

func save_transforms():
	for child in get_children():
		if child is Spatial:
			transforms[child.name] = child.transform

class SortByPriority:
	static func by_priority(a,b):
		return a.get("spawn_priority",50)>b.get("spawn_priority",50)

func make_random_cargo(cargo_hold_spawn_fraction,from,_quiet: bool = false, skip_runtime_stats: bool = false):
	if not combined_stats.has('empty_mass'):
#		if not quiet:
#			push_warning('No stats in set_cargo! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[],'salvage':[]},skip_runtime_stats)
	var max_mass = combined_stats.get('max_cargo',0)
	if max_mass<=0:
		return
	var max_cash = 1e4*max_mass + combined_stats.get('cost',1e5)
	max_mass *= 1000*clamp(cargo_hold_spawn_fraction,0.0,1.0)
	var names_remaining = from.by_name.keys()
	var mass_remaining = max_mass
	var cash_remaining = max_cash
	var results = Array()
	
	var infinite_loop_guard = 0
	
	while names_remaining and cash_remaining and mass_remaining and infinite_loop_guard<100:
		infinite_loop_guard += 1
		var index = randi()%names_remaining.size()
		var product_name = names_remaining[index]
		var product = from.by_name.get(product_name,null)
		if product==null:
			names_remaining.pop_at(index)
			continue
		var unit_cost = product.value
		var unit_mass = product.mass
		var available = product.quantity*100
		if unit_cost<=0 or unit_mass<=0 or available<=0:
			names_remaining.pop_at(index)
			continue
		var max_items = int(min(available,min(floor(mass_remaining/unit_mass),floor(cash_remaining/unit_cost))))
		if max_items<=0:
			names_remaining.pop_at(index)
			continue
		mass_remaining -= max_items*unit_mass
		cash_remaining -= max_items*unit_cost
		product = product.duplicate()
		product.quantity = max_items
		results.append(product)
#		print('   '+str(product.name)+
#			' '+str(max_items)+' @ '+str(unit_cost)+' & '+str(unit_mass)+'kg')
		names_remaining.pop_at(index)
	
	if results:
		var _ignore = set_cargo(Commodities.ManyProducts.new(results))
	else:
		clear_cargo()

# warning-ignore:shadowed_variable
# warning-ignore:shadowed_variable
func add_salvage(result: Array,flotsam_meshes: Array,flotsam: Dictionary):
	if not flotsam_meshes or not flotsam:
		return result
	var keys_left: Array
	var max_armor = combined_stats.get('max_armor',2000.0)
	var max_fuel = combined_stats.get('max_fuel',20.0)
	for mesh in flotsam_meshes:
		if not keys_left:
			keys_left = flotsam.keys()
		while keys_left:
			var selected_key = utils.dict_random_element_by_weight(flotsam,keys_left)
			if flotsam[selected_key]<=0:
				keys_left.remove(selected_key)
			var flotsam_node = game_state.universe.flotsam.get_child_with_name(selected_key)
			if not flotsam_node:
				push_warning('No flotsam exists with name '+str(selected_key))
				continue
			if flotsam_node.uses_ship_cargo() and not cargo:
				continue
			result.append(flotsam_node.encode_for_native(mesh,max_armor,max_fuel,cargo,true))
			break

func select_salvage():
	var results: Array = []
	for d in combined_stats.get('flotsam_data',[]):
		add_salvage(results,d[0],d[1])
	combined_stats['salvage'] = results

func restore_transforms():
	for key in transforms:
		var child = get_node_or_null(key)
		if child!=null:
			child.transform=transforms[key]

func set_entry_method(method: int, _quiet: bool = false, skip_runtime_stats: bool = false):
	if not combined_stats.has('empty_mass'):
#		if not quiet:
#			push_error('No stats in set_entry_method! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[],'salvage':[]},skip_runtime_stats)
	combined_stats['entry_method'] = method

func set_faction_index(new_faction_index: int):
	faction_index = new_faction_index

func get_combined_aabb(node: Node = self) -> AABB:
	if override_size.length()>1e-5:
		var size: Vector3 = Vector3(override_size.x,1,override_size.z)
		return AABB(-size*0.5,size)
	else:
		var result: AABB = AABB()
		if node is VisualInstance:
			result = node.get_aabb()
		for child in node.get_children():
			result=result.merge(get_combined_aabb(child))
		return result

func make_stats(node: Node, stats: Dictionary,skip_runtime_stats=false) -> Dictionary:
	if node.has_method("add_stats"):
		node.add_stats(stats,skip_runtime_stats,self)
	if node.has_method('pack_cargo_stats'):
		node.pack_cargo_stats(stats)
	var children: Array = node.get_children()
	for child in children:
		var _discard = make_stats(child,stats,skip_runtime_stats)
	if node.get_instance_id()==self.get_instance_id():
		combined_stats["salvage"].sort_custom(SortByPriority,"by_priority")
	return stats

func repack_stats(skip_runtime_stats=false) -> Dictionary:
	var new_stats = make_stats(self,{'weapons':[],'equipment':[],'salvage':[]},
		skip_runtime_stats and skipped_runtime_stats)
	if not new_stats['equipment'] and combined_stats and combined_stats['equipment']:
		new_stats['equipment'] = combined_stats['equipment']
	combined_stats = new_stats
	return combined_stats
	
func pack_stats(_quiet: bool = false, skip_runtime_stats=false) -> Dictionary:
	if not combined_stats.has('empty_mass'):
		#if not quiet:
		#	push_error('No stats in pack_stats! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[],'salvage':[]},skip_runtime_stats)
	elif not skip_runtime_stats and skipped_runtime_stats:
		update_stats()
	return combined_stats

func set_ai_type(type: int):
	ai_type = type
	if combined_stats.has('empty_mass'):
		combined_stats['ai_type'] = ai_type

func update_cargo_stats():
	pack_cargo_stats(combined_stats)

func pack_cargo_stats(stats):
	# Update cargo stats. This MUST match ShipDesign.set_cargo.
	stats['cargo_mass'] = float(cargo.get_mass()/1000) if cargo else 0.0

func set_cost(cost: float, _quiet: bool = false, skip_runtime_stats=false) -> Dictionary:
	if not combined_stats.has('empty_mass'):
#		if not quiet:
#			push_warning('No stats in set_cost! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[],'salvage':[]},skip_runtime_stats)
	combined_stats['cost']=cost
	return combined_stats

func clear_cargo(_quiet: bool = false,skip_runtime_stats: bool = false):
	cargo = null
	if not combined_stats.has('empty_mass'):
#		if not quiet:
#			push_warning('No stats in set_cargo! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[],'salvage':[]},skip_runtime_stats)
	pack_cargo_stats(combined_stats)
	return combined_stats

func set_cargo(products: Commodities.Products, _quiet: bool = false,
		skip_runtime_stats=false) -> Dictionary:
	if not combined_stats.has('empty_mass'):
#		if not quiet:
#			push_warning('No stats in set_cargo! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[],'salvage':[]},skip_runtime_stats)
	cargo = Commodities.ManyProducts.new()
	cargo.copy_from(products)
	pack_cargo_stats(combined_stats)
	if products.by_name:
		assert(cargo.by_name)
	return combined_stats


func restore_combat_stats(stats: Dictionary, skip_runtime_stats: bool = false, _quiet: bool = false) -> void:
	#if not stats:
	#	push_error('no combat stats to restore in restore_combat_stats')
	if not combined_stats.has('empty_mass'):
#		if not quiet:
#			push_error('No stats in restore_combat_stats! Making stats now.')
		combined_stats = make_stats(self,{'weapons':[],'equipment':[],'salvage':[]},skip_runtime_stats)
	for varname in [ 'fuel', 'shields', 'armor', 'structure', 'energy', 'heat' ]:
		if stats.has(varname) and stats.has('max_'+varname):
			combined_stats[varname] = clamp(stats[varname],0.0,stats['max_'+varname])
#			print('restored '+str(varname)+' to '+str(combined_stats[varname]))

func set_stats(stats: Dictionary) -> void:
	combined_stats = stats.duplicate(true)

func set_item_slots(_ignored):
	var _discard = get_item_slots()

func get_item_slots() -> int:
	if item_slots<0:
		item_slots = count_item_slots_impl()
	return item_slots

func count_item_slots_impl() -> int:
	var result: int = 0
	for child in get_children():
		if child.has_method('get_mount_size'):
			result += child.get_mount_size()
	return result

func set_power_and_cooling(stats: Dictionary):
	var need = 2
	if base_power>=0:
		stats['power'] = base_power
		need -= 1
	if base_cooling>=0:
		stats['cooling'] = base_cooling
		need -= 1
	if need<=0:
		return

	var slots: int = stats['item_slots']
	if not (base_power>=0):
		var power: float = slots/4.0
		power += max(stats['thrust']*stats['forward_thrust_energy'], \
			stats['reverse_thrust']*stats['reverse_thrust_energy'])/1000.0 + \
			stats['turning_thrust']*stats['turning_thrust_energy']/1000.0 + \
			stats['heal_shields']*stats['shield_repair_energy'] + \
			stats['heal_armor']*stats['armor_repair_energy'] + \
			stats['heal_structure']*stats['structure_repair_energy']
		stats['power'] = power
	if not (base_cooling>=0):
		var heat: float = slots/30.0
		heat += max(stats['thrust']*stats['forward_thrust_heat'], \
			stats['reverse_thrust']*stats['reverse_thrust_heat'])/1000.0 + \
			stats['turning_thrust']*stats['turning_thrust_heat']/1000.0 + \
			stats['heal_shields']*stats['shield_repair_heat'] + \
			stats['heal_armor']*stats['armor_repair_heat'] + \
			stats['heal_structure']*stats['structure_repair_heat']
		stats['cooling'] = heat

func add_stats(stats: Dictionary,skip_runtime_stats=false,ship_node=null) -> void:
	if ship_node==null:
		ship_node=self
	stats['item_slots'] = get_item_slots()
	if base_explosion_damage>=0:
		stats['explosion_damage']=base_explosion_damage
	else:
		stats['explosion_damage']=(base_armor+base_shields+base_structure+10*base_mass)/20
	if base_explosion_radius>=0:
		stats['explosion_radius']=base_explosion_radius
	else:
		stats['explosion_radius']=stats['explosion_damage']/100.0
	if base_explosion_impulse>=0:
		stats['explosion_impulse']=base_explosion_impulse
	else:
		stats['explosion_impulse']=stats['explosion_damage']*3
	stats['explosion_delay']=base_explosion_delay
	stats['name']=name
	if not skip_runtime_stats and is_inside_tree():
		stats['rid']=get_rid()
	if base_mass<=0:
		push_warning('invalid base mass '+str(base_mass))
		base_mass = 1.0
		stats['invalid']=true
	if base_thrust>=0:
		stats['thrust']=base_thrust
	else:
		stats['thrust']=base_mass*16*-base_reverse_thrust
	assert(stats['thrust']>0)
	if base_reverse_thrust>=0:
		stats['reverse_thrust']=base_reverse_thrust
	else:
		stats['reverse_thrust']=base_mass*12*-base_reverse_thrust
	assert(stats['reverse_thrust']>0)
	if base_turning_thrust>=0:
		stats['turning_thrust']=base_turning_thrust
	else:
		stats['turning_thrust']=base_mass*15*-base_turning_thrust
	assert(stats['turning_thrust']>0)
	stats['hyperthrust']=max(base_hyperthrust,0)
	stats['max_shields']=base_shields
	stats['max_armor']=base_armor
	stats['max_structure']=base_structure
	stats['max_fuel']=base_fuel
	stats['max_cargo']=base_max_cargo
	stats['cargo_web_add_radius']=cargo_web_add_radius
	if cargo_web_strength>=0:
		stats['cargo_web_strength']=cargo_web_strength
	else:
		stats['cargo_web_strength']=500*(cargo_web_add_radius+1)*-cargo_web_strength
	if heal_shields>=0:
		stats['heal_shields']=heal_shields
	else:
		stats['heal_shields']=base_shields/180.0*-heal_shields
	stats['heal_armor']=heal_armor
	if heal_structure>=0:
		stats['heal_structure']=heal_structure
	else:
		stats['heal_structure']=base_structure/120.0*-heal_structure
	if base_threat<0:
		stats['threat'] = ((stats['max_shields']+stats['max_armor']+stats['max_structure'])/60 + \
			stats['heal_shields']+stats['heal_armor']+stats['heal_structure'])*-base_threat
	else:
		stats['threat'] = base_threat
	stats['heal_fuel']=heal_fuel
	stats['fuel_efficiency']=fuel_efficiency
	stats['aabb']=get_combined_aabb()
	stats['turn_drag']=base_turn_drag
	stats['collision_layer']=collision_layer
	stats['faction_index']=faction_index
	stats['rotation']=rotation
	stats['position']=Vector3(translation.x,0,translation.z)
	stats['transform']=transform
	stats['empty_mass']=base_mass
	stats['armor_inverse_density']=armor_inverse_density
	stats['fuel_inverse_density']=fuel_inverse_density
	stats['drag']=base_drag
	stats['weapons']=Array()
	stats['equipment']=Array()
	stats['ai_type']=ai_type

	stats['explosion_type']=explosion_type
	stats['shield_resist']=base_shield_resist
	stats['shield_passthru']=base_shield_passthru
	stats['armor_resist']=base_armor_resist
	stats['armor_passthru']=base_armor_passthru
	stats['structure_resist']=base_structure_resist
	stats['rifting_damage_multiplier']=rifting_damage_multiplier

	stats['heat_capacity']=base_heat_capacity
	stats['shield_repair_heat']=base_shield_repair_heat
	stats['armor_repair_heat']=base_armor_repair_heat
	stats['structure_repair_heat']=base_structure_repair_heat
	stats['shield_repair_energy']=base_shield_repair_energy
	stats['armor_repair_energy']=base_armor_repair_energy
	stats['structure_repair_energy']=base_structure_repair_energy
	stats['forward_thrust_heat']=base_forward_thrust_heat
	stats['reverse_thrust_heat']=base_reverse_thrust_heat
	stats['turning_thrust_heat']=base_turning_thrust_heat
	stats['forward_thrust_energy']=base_forward_thrust_energy
	stats['reverse_thrust_energy']=base_reverse_thrust_energy
	stats['turning_thrust_energy']=base_turning_thrust_energy
	
	set_power_and_cooling(stats)

	if base_battery>=0:
		stats['battery']=base_battery
	else:
		stats['battery']=stats['power']*15*-base_battery

	# Used for text generation, not CombatEngine:
	stats['display_name']=ship_display_name
	stats['help_page']=help_page
	
	stats['flotsam_data'] = [ [flotsam_meshes,flotsam] ]
	
	skipped_runtime_stats = skip_runtime_stats

func update_stats():
	combined_stats['faction_index']=faction_index
#	combined_stats['enemy_team']=enemy_team
	combined_stats['name']=name
#	combined_stats['enemy_mask']=enemy_mask
	combined_stats['rid'] = get_rid()
#	combined_stats['team']=team
	combined_stats['rotation']=rotation
	combined_stats['position']=Vector3(translation.x,0,translation.z)
	combined_stats['transform']=transform
	combined_stats['ai_type']=ai_type
	for wep in combined_stats['weapons']:
		var child = get_node_or_null(wep['name'])
		if child==null:
			printerr('ShipStats._ready: weapon "',wep['name'],'" vanished.')
		else:
			wep['node_path'] = child.get_path()
			assert(not wep['node_path'].is_empty())
	combined_stats['aabb']=get_combined_aabb()
	combined_stats['cargo_puff_mesh']=cargo_puff
	skipped_runtime_stats=false
	assert(combined_stats['turning_thrust']>0)

func make_cell(key,value) -> String:
	return '[cell]'+key+'[/cell][cell]'+str(value)+'[/cell]'

func max_and_repair(key,maxval,repairval) -> String:
	if repairval>0:
		return make_cell(key,str(maxval)+' (+'+str(repairval)+'/s)')
	return make_cell(key,maxval)

func get_bbcode(annotation: String = '') -> String:
	return text_gen.make_ship_bbcode(pack_stats(true,true),true,annotation)

func _ready():
	var must_update: bool = true
	if not combined_stats.has('empty_mass'):
		var _discard = pack_stats(false)
#	else:
#		must_update = not combined_stats.has('rid')

	if not retain_hidden_mounts:
		for child in get_children():
			if child.has_method('is_mountable') and not child.has_method('is_shown_in_space'):
				remove_child(child)
				child.queue_free()
				must_update=true
	if must_update:
		update_stats()
	
	if random_height:
		height = (randi()%11)*1.99 - 8.445
	combined_stats['visual_height'] = height+game_state.SHIP_HEIGHT
	collision_mask=0
	mass=utils.ship_mass(combined_stats)
	linear_damp=combined_stats['drag']
	gravity_scale=0
	axis_lock_linear_y=true
	axis_lock_angular_x=true
	axis_lock_angular_z=true
	can_sleep=false
	
	# Sometimes Godot trashes the CollisionShape transforms:
	restore_transforms()
	
	for child in get_children():
		if child is VisualInstance or child is Position3D:
			child.translation.y+=height
