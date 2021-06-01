extends MeshInstance

export var add_mass: float = 1
export var add_threat: float = 0
export var add_max_cargo: float = 0

export var add_thrust: float = 0
export var add_reverse_thrust: float = 0
export var add_turn_thrust: float = 0
export var add_fuel: float = 0
export var add_heal_fuel: float = 0
export var add_drag: float = 0
export var mult_drag: float = 1
export var add_turn_drag: float = 0
export var mult_turn_drag: float = 1

export var add_shields: float = 0
export var add_armor: float = 0
export var add_structure: float = 0
export var add_heal_shields: float = 0
export var add_heal_armor: float = 0
export var add_heal_structure: float = 0

export var add_explosion_damage: float = 0
export var add_explosion_radius: float = 0
export var add_explosion_impulse: float = 0
export var add_explosion_delay: int = 0

export var item_size_x: int = 1
export var item_size_y: int = 3
export var item_offset_x: int = -1
export var item_offset_y: int = -1
export var mount_size_x: int = 0 setget ,get_mount_size_x
export var mount_size_y: int = 0 setget ,get_mount_size_y
export var mount_type: String = 'equipment'
export var help_page: String = 'equipment'

var cached_stats
var cached_bbcode

func is_EquipmentStats(): pass # Never called; must only exist

func is_mount_point(): # Never called; must only exist
	pass

func is_not_mounted(): # Never called; must only exist
	pass

func get_mount_size_x() -> int:
	return mount_size_x if mount_size_x>0 else item_size_x

func get_mount_size_y() -> int:
	return mount_size_y if mount_size_y>0 else item_size_y

func pack_stats() -> Dictionary:
	if not cached_stats:
		cached_stats = {
			'name':name,
			'mount_type':mount_type,
			'help_page':help_page,
			'item_size_x':item_size_x,
			'item_size_y':item_size_y,
			'add_mass':add_mass,
			'add_thrust':add_thrust,
			'add_reverse_thrust':add_reverse_thrust,
			'add_turn_thrust':add_turn_thrust,
			'add_shields':add_shields,
			'add_armor':add_armor,
			'add_structure':add_structure,
			'add_fuel':add_fuel,
			'add_heal_shields':add_heal_shields,
			'add_heal_armor':add_heal_armor,
			'add_heal_structure':add_heal_structure,
			'add_heal_fuel':add_heal_fuel,
			'add_drag':add_drag,
			'add_max_cargo':add_max_cargo,
			'mult_drag':mult_drag,
			'add_turn_drag':add_turn_drag,
			'mult_turn_drag':mult_turn_drag,
			'add_threat':add_threat,
			'add_explosion_damage':add_explosion_damage,
			'add_explosion_radius':add_explosion_radius,
			'add_explosion_impulse':add_explosion_impulse,
			'add_explosion_delay':add_explosion_delay,
		}
	return cached_stats

func get_bbcode_for_ship_table() -> String:
	return '[b]'+name.capitalize() + ':[/b] {ref '+help_page+'}\n' + get_bbcode()

func get_bbcode() -> String:
	if cached_bbcode == null:
		cached_bbcode = text_gen.make_equipment_bbcode(pack_stats())
	return cached_bbcode

func add_stats(stats: Dictionary,_skip_runtime_stats=false) -> void:
	stats['equipment'].append(pack_stats())
	if add_mass > 0:
		stats['empty_mass'] = max(1,stats['empty_mass']+add_mass)
	if add_thrust > 0:
		stats['thrust'] = max(0,stats['thrust']+add_thrust)
	if add_reverse_thrust>0:
		stats['reverse_thrust'] = max(0,stats['reverse_thrust']+add_reverse_thrust)
	if add_turn_thrust>0:
		stats['turn_thrust'] = max(0,stats['turn_thrust']+add_turn_thrust)
	if add_shields>0:
		stats['max_shields'] = max(0,stats['max_shields']+add_shields)
	if add_armor>0:
		stats['max_armor'] = max(0,stats['max_armor']+add_armor)
	if add_structure>0:
		stats['max_structure'] = max(0,stats['max_structure']+add_structure)
	if add_fuel>0:
		stats['max_fuel'] = max(0,stats['max_fuel']+add_fuel)
	if add_heal_shields>0:
		stats['heal_shields'] = max(0,stats['heal_shields']+add_heal_shields)
	if add_heal_armor>0:
		stats['heal_armor'] = max(0,stats['heal_armor']+add_heal_armor)
	if add_heal_structure>0:
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
