extends Spatial

export var help_page: String = 'equipment'
export var item_size_x: int = 1
export var item_size_y: int = 3
export var hidden: bool = false
export var mount_type_display: String = 'equipment'
export var mount_type_all: String = ''
export var mount_type_any: String = ''

export var add_mass: float = 0
export var add_threat: float = 0
export var add_max_cargo: float = 0

export var add_thrust: float = 0
export var add_reverse_thrust: float = 0
export var add_turning_thrust: float = 0
export var add_hyperthrust: float = 0
export var add_fuel: float = 0
export var add_heal_fuel: float = 0
export var add_drag: float = 0
export var mult_drag: float = 1
export var add_turn_drag: float = 0
export var mult_turn_drag: float = 1

export var add_shields: float = 0
export var add_armor: float = 0
export var add_structure: float = -1
export var add_heal_shields: float = 0
export var add_heal_armor: float = 0
export var add_heal_structure: float = 0

export var add_explosion_damage: float = 0
export var add_explosion_radius: float = 0
export var add_explosion_impulse: float = 0
export var add_explosion_delay: int = 0

export var mount_size_x: int = 0 setget ,get_mount_size_x
export var mount_size_y: int = 0 setget ,get_mount_size_y

export var add_shield_resist: PoolRealArray = PoolRealArray()
export var add_shield_passthru: PoolRealArray = PoolRealArray()
export var add_armor_resist: PoolRealArray = PoolRealArray()
export var add_armor_passthru: PoolRealArray = PoolRealArray()
export var add_structure_resist: PoolRealArray = PoolRealArray()

export var add_heat_capacity: float = 0.0
export var add_cooling: float = 0.0
export var shield_repair_heat: float = 0.013
export var armor_repair_heat: float = 0.0165
export var structure_repair_heat: float = .02
export var shield_repair_energy: float = 0.13
export var armor_repair_energy: float = 0.165
export var structure_repair_energy: float = .2
export var forward_thrust_heat: float = .12
export var reverse_thrust_heat: float = .12
export var turning_thrust_heat: float = .36
export var forward_thrust_energy: float = 1.2
export var reverse_thrust_energy: float = 1.2
export var turning_thrust_energy: float = 3.6
export var add_battery: float = 0.0
export var add_power: float = 0.0

var cached_structure

var cached_stats
var cached_bbcode

var item_offset_x: int = -1
var item_offset_y: int = -1

var mount_flags_any: int = 0 setget set_mount_flags_any,get_mount_flags_any
var mount_flags_all: int = 0 setget set_mount_flags_all,get_mount_flags_all
var initialized_mount_flags: bool = false

func is_EquipmentStats(): pass # Never called; must only exist

func is_mountable(): # Never called; must only exist
	# Defining this ensures the equipment can be placed in a mount
	pass

func is_not_mounted(): # Never called; must only exist
	# Defining this ensures the equipment mesh is not spawned in space
	pass

func is_gun():
	return false

func set_mount_flags_any(m: int):
	if not initialized_mount_flags:
		initialize_mount_flags()
	mount_flags_any = m

func set_mount_flags_all(m: int):
	if not initialized_mount_flags:
		initialize_mount_flags()
	mount_flags_all = m

func get_mount_flags_any() -> int:
	if not initialized_mount_flags:
		initialize_mount_flags()
	return mount_flags_any

func get_mount_flags_all() -> int:
	if not initialized_mount_flags:
		initialize_mount_flags()
	return mount_flags_all

func initialize_mount_flags():
	mount_flags_any = utils.mount_type_to_int(mount_type_any)
	mount_flags_all = utils.mount_type_to_int(mount_type_all)
	if not mount_flags_any and not mount_flags_all:
		#push_warning('No mount flags in EquipmentStats; assuming equipment')
		mount_type_all = 'equipment'
		mount_flags_all = utils.mount_type_to_int(mount_type_all)
	initialized_mount_flags = true

func get_mount_size_x() -> int:
	return mount_size_x if mount_size_x>0 else item_size_x

func get_mount_size_y() -> int:
	return mount_size_y if mount_size_y>0 else item_size_y

func get_mount_size() -> int:
	 return get_mount_size_x()*get_mount_size_y()

func pack_stats() -> Dictionary:
	if not cached_stats:
		cached_structure = add_structure if add_structure>=0 else add_mass*25
		cached_stats = {
			'name':name,
			'hidden': hidden,
			'add_mass':add_mass,
			'add_threat':add_threat,
			'add_max_cargo':add_max_cargo,

			'add_thrust':add_thrust,
			'add_reverse_thrust':add_reverse_thrust,
			'add_turning_thrust':add_turning_thrust,
			'add_hyperthrust':add_hyperthrust,
			'add_fuel':add_fuel,
			'add_heal_fuel':add_heal_fuel,
			'add_drag':add_drag,
			'mult_drag':mult_drag,
			'add_turn_drag':add_turn_drag,
			'mult_turn_drag':mult_turn_drag,

			'add_shields':add_shields,
			'add_armor':add_armor,
			'add_structure':cached_structure,
			'add_heal_shields':add_heal_shields,
			'add_heal_armor':add_heal_armor,
			'add_heal_structure':add_heal_structure,

			'add_explosion_damage':add_explosion_damage,
			'add_explosion_radius':add_explosion_radius,
			'add_explosion_impulse':add_explosion_impulse,
			'add_explosion_delay':add_explosion_delay,

			'item_size_x':item_size_x,
			'item_size_y':item_size_y,
			'mount_type_all':mount_type_all,
			'mount_type_any':mount_type_any,
			'mount_type_display':mount_type_display,
			'help_page':help_page,

			'add_shield_resist':add_shield_resist,
			'add_shield_passthru':add_shield_passthru,
			'add_armor_resist':add_armor_resist,
			'add_armor_passthru':add_armor_passthru,
			'add_structure_resist':add_structure_resist,

			'add_heat_capacity':add_heat_capacity,
			'add_cooling':add_cooling,
			'shield_repair_heat':shield_repair_heat,
			'armor_repair_heat':armor_repair_heat,
			'structure_repair_heat':structure_repair_heat,
			'shield_repair_energy':shield_repair_energy,
			'armor_repair_energy':armor_repair_energy,
			'structure_repair_energy':structure_repair_energy,
			'forward_thrust_heat':forward_thrust_heat,
			'reverse_thrust_heat':reverse_thrust_heat,
			'turning_thrust_heat':turning_thrust_heat,
			'forward_thrust_energy':forward_thrust_energy,
			'reverse_thrust_energy':reverse_thrust_energy,
			'turning_thrust_energy':turning_thrust_energy,
			'add_battery':add_battery,
			'add_power':add_power,
		}
	return cached_stats

func get_bbcode_for_ship_table() -> String:
	return '[b]'+name.capitalize() + ':[/b] {ref '+help_page+'}\n' + get_bbcode()

func get_bbcode() -> String:
	if cached_bbcode == null:
		cached_bbcode = text_gen.make_equipment_bbcode(pack_stats())
	return cached_bbcode

func add_stats(stats: Dictionary,_skip_runtime_stats=false,_ship_node=null) -> void:
	stats['equipment'].append(pack_stats())
	if add_heat_capacity>0.0:
		stats['heat_capacity'] += add_heat_capacity
	if add_cooling:
		stats['cooling'] += add_cooling
	if add_battery>0.0:
		stats['battery'] += add_battery
	if add_power:
		stats['power'] += add_power
	if add_shield_resist:
		stats['shield_resist'] = utils.sum_of_squares(stats['shield_resist'],add_shield_resist)
	if add_shield_passthru:
		stats['shield_passthru'] = utils.sum_of_squares(stats['shield_passthru'],add_shield_passthru)
	if add_armor_resist:
		stats['armor_resist'] = utils.sum_of_squares(stats['armor_resist'],add_armor_resist)
	if add_armor_passthru:
		stats['armor_passthru'] = utils.sum_of_squares(stats['armor_passthru'],add_armor_passthru)
	if add_structure_resist:
		stats['structure_resist'] = utils.sum_of_squares(stats['structure_resist'],add_structure_resist)
	stats['empty_mass'] = max(1,stats['empty_mass']+add_mass)
	if add_thrust > 0:
		utils.weighted_add(forward_thrust_heat,add_thrust,stats,'forward_thrust_heat','thrust')
		utils.weighted_add(forward_thrust_energy,add_thrust,stats,'forward_thrust_energy','thrust')
		stats['thrust'] = max(0,stats['thrust']+add_thrust)
	if add_reverse_thrust>0:
		utils.weighted_add(reverse_thrust_heat,add_reverse_thrust,stats,'reverse_thrust_heat','reverse_thrust')
		utils.weighted_add(reverse_thrust_energy,add_reverse_thrust,stats,'reverse_thrust_energy','reverse_thrust')
		stats['reverse_thrust'] = max(0,stats['reverse_thrust']+add_reverse_thrust)
	if add_turning_thrust>0:
		utils.weighted_add(turning_thrust_heat,add_turning_thrust,stats,'turning_thrust_heat','turning_thrust')
		utils.weighted_add(turning_thrust_energy,add_turning_thrust,stats,'turning_thrust_energy','turning_thrust')
		stats['turning_thrust'] = max(0,stats['turning_thrust']+add_turning_thrust)
	if add_hyperthrust > 0:
		stats['hyperthrust'] = utils.sum_of_squares_scalar(stats['hyperthrust'],add_hyperthrust)
	if add_shields>0:
		stats['max_shields'] = max(0,stats['max_shields']+add_shields)
	if add_armor>0:
		stats['max_armor'] = max(0,stats['max_armor']+add_armor)
	if add_structure>0:
		stats['max_structure'] = max(0,stats['max_structure']+add_structure)
	else:
		stats['max_structure'] = max(0,stats['max_structure']+(mount_size_x*mount_size_y)*40*-add_structure)
	if add_fuel>0:
		stats['max_fuel'] = max(0,stats['max_fuel']+add_fuel)
	if add_heal_shields>0:
		utils.weighted_add(shield_repair_heat,add_heal_shields,stats,'shield_repair_heat','heal_shields')
		utils.weighted_add(shield_repair_energy,add_heal_shields,stats,'shield_repair_energy','heal_shields')
		stats['heal_shields'] = max(0,stats['heal_shields']+add_heal_shields)
	if add_heal_armor>0:
		utils.weighted_add(armor_repair_heat,add_heal_armor,stats,'armor_repair_heat','heal_armor')
		utils.weighted_add(armor_repair_energy,add_heal_armor,stats,'armor_repair_energy','heal_armor')
		stats['heal_armor'] = max(0,stats['heal_armor']+add_heal_armor)
	if add_heal_structure>0:
		utils.weighted_add(structure_repair_heat,add_heal_structure,stats,'structure_repair_heat','heal_structure')
		utils.weighted_add(structure_repair_energy,add_heal_structure,stats,'structure_repair_energy','heal_structure')
		stats['heal_structure'] = max(0,stats['heal_structure']+add_heal_structure)
	if add_fuel>0:
		stats['heal_fuel'] = max(0,stats['heal_fuel']+add_heal_fuel)
	if add_max_cargo > 0:
		stats['max_cargo'] = max(0.0,stats['max_cargo']+add_max_cargo)
	if add_drag>0 or abs(mult_drag-1.0)>1e-6:
		stats['drag'] = max(0.05,stats['drag']*mult_drag+add_drag)
	if add_turn_drag>0 or abs(mult_turn_drag-1.0)>1e-6:
		stats['turn_drag'] = max(0.005,stats['turn_drag']*mult_turn_drag+add_turn_drag)
#	if add_turn_rate>0 or mult_turn_rate>0:
#		stats['turn_rate'] = max(0,stats['turn_rate']*mult_turn_rate+add_turn_rate)
	if add_threat>0:
		stats['threat'] = max(0,stats['threat']+add_threat)
	if add_explosion_damage>0:
		stats['explosion_damage'] = max(0,stats['explosion_damage']+add_explosion_damage)
	if add_explosion_radius>0:
		stats['explosion_radius'] = max(0,stats['explosion_radius']+add_explosion_radius)
	if add_explosion_impulse>0:
		stats['explosion_impulse'] = max(0,stats['explosion_impulse']+add_explosion_impulse)
	if add_explosion_delay>0:
		stats['explosion_delay'] = max(0,stats['explosion_delay']+add_explosion_delay)
