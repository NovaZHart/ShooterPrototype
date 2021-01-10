extends MeshInstance

export var add_mass: float = 1
export var add_thrust: float = 0
export var add_reverse_thrust: float = 0
export var add_shields: float = 0
export var add_armor: float = 0
export var add_structure: float = 0
export var add_heal_shields: float = 0
export var add_heal_armor: float = 0
export var add_heal_structure: float = 0
export var add_drag: float = 0
export var add_turn_rate: float = 0
export var add_threat: float = 0
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

func is_mount_point(): # Never called; must only exist
	pass

func is_mounted(): # Never called; must only exist
	pass

func get_mount_size_x() -> int:
	return mount_size_x if mount_size_x>0 else item_size_x

func get_mount_size_y() -> int:
	return mount_size_y if mount_size_y>0 else item_size_y

func add_stats(stats: Dictionary) -> void:
	if add_mass > 0:
		stats['mass'] = max(1e-5,stats['mass']+add_mass)
	if add_thrust > 0:
		stats['thrust'] = max(0,stats['thrust']+add_thrust)
	if add_reverse_thrust>0:
		stats['reverse_thrust'] = max(0,stats['reverse_thrust']+add_reverse_thrust)
	if add_shields>0:
		stats['max_shields'] = max(0,stats['max_shields']+add_shields)
	if add_armor>0:
		stats['max_armor'] = max(0,stats['max_armor']+add_armor)
	if add_structure>0:
		stats['max_structure'] = max(0,stats['max_structure']+add_structure)
	if add_heal_shields>0:
		stats['heal_shields'] = max(0,stats['heal_shields']+add_heal_shields)
	if add_heal_armor>0:
		stats['heal_armor'] = max(0,stats['heal_armor']+add_heal_armor)
	if add_heal_structure>0:
		stats['heal_structure'] = max(0,stats['heal_structure']+add_heal_structure)
	if add_drag>0:
		stats['drag'] = max(1e-5,stats['drag']+add_drag)
	if add_turn_rate>0:
		stats['turn_rate'] = max(0,stats['turn_rate']+add_turn_rate)
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
