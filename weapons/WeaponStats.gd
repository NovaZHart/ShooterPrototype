extends MeshInstance

export var help_page: String = 'weapons'
export var mount_type_all: String = 'gun'
export var mount_type_any: String = ''
export var mount_type_display: String = 'gun'
export var item_size_x: int = 1
export var item_size_y: int = 3

export var damage: float = 0
export var damage_type: int = 0 # Make sure you override this!
export var impulse: float = 0
export var weapon_mass: float = -2
export var weapon_structure: float = -1
export var initial_velocity: float = 30
export var projectile_mass: float = 0.3
export var projectile_drag: float = 1
export var projectile_thrust: float = 0
export var projectile_lifetime: float = 0.7
export var projectile_turn_rate: float = 8
export var projectile_structure: float = 0
export var firing_delay: float = 0.1
export var turn_rate: float = 0
export var detonation_range: float = 0
export var blast_radius: float = 0
export var threat: float = -1
export var guided: bool = false
export var guidance_uses_velocity: bool = false
export var auto_retarget: bool = false
export var antimissile: bool = false
export var projectile_mesh_path: String
export var mount_size_x: int = 0 setget ,get_mount_size_x
export var mount_size_y: int = 0 setget ,get_mount_size_y

export var ammo_capacity: int = 0
export var reload_delay: float = 0.0
export var reload_heat: float = 0.0
export var reload_energy: float = 0.0

export var add_heat_capacity: float = 0.0
export var add_cooling: float = 0.0
export var add_battery: float = 0.0
export var add_power: float = 0.0

export var firing_heat: float = 0.03
export var firing_energy: float = 0.03

export var heat_fraction: float = 0
export var energy_fraction: float = 0
export var thrust_fraction: float = 0

export var add_shield_resist: PoolRealArray = PoolRealArray()
export var add_shield_passthru: PoolRealArray = PoolRealArray()
export var add_armor_resist: PoolRealArray = PoolRealArray()
export var add_armor_passthru: PoolRealArray = PoolRealArray()
export var add_structure_resist: PoolRealArray = PoolRealArray()

var mount_flags_any: int = 0 setget set_mount_flags_any,get_mount_flags_any
var mount_flags_all: int = 0 setget set_mount_flags_all,get_mount_flags_all
var initialized_mount_flags: bool = false
var cached_bbcode = null
var cached_stats = null
var cached_structure = null
var cached_mass = null
var skipped_runtime_stats: bool = true
var item_offset_x: int = -1
var item_offset_y: int = -1

func is_WeaponStats(): pass # Never called; must only exist

func keep_mount_in_space():
	return true

func is_mountable(): # Never called; must only exist
	# Defining this ensures the weapon can be placed in a mount
	pass

func is_shown_in_space(): # Never called; must only exist
	# Defining this ensures the equipment mesh is spawned in space
	pass

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

func is_gun() -> bool:
	return mount_flags_any&game_state.MOUNT_FLAG_GUN or mount_flags_all&game_state.MOUNT_FLAG_GUN

func is_turret() -> bool:
	return mount_flags_any&game_state.MOUNT_FLAG_TURRET or mount_flags_all&game_state.MOUNT_FLAG_TURRET

func initialize_mount_flags():
	mount_flags_any = utils.mount_type_to_int(mount_type_any)
	mount_flags_all = utils.mount_type_to_int(mount_type_all)
	assert(mount_flags_any or mount_flags_all)
	initialized_mount_flags = true

func approximate_range() -> float:
	if projectile_drag>0 and projectile_thrust>0:
		return max(initial_velocity,projectile_thrust/projectile_drag)*max(1.0/60,projectile_lifetime)
	return initial_velocity*max(1.0/60,projectile_lifetime)

func get_bbcode_for_ship_table() -> String:
	return '[b]'+name.capitalize() + ':[/b] {ref '+help_page+'}\n' + get_bbcode()
#		+ '[cell] DPS ' + str(round(damage/max(1.0/60,firing_delay)*10)/10) + '[/cell]' \
#		+ '[cell] Range ' + str(round(approximate_range()*100)/100) + ' [/cell]'

func get_bbcode() -> String:
	if cached_bbcode == null:
		cached_bbcode = text_gen.make_weapon_bbcode(pack_stats(true))
	return cached_bbcode

func get_mount_size_x() -> int:
	return mount_size_x if mount_size_x>0 else item_size_x

func get_mount_size_y() -> int:
	return mount_size_y if mount_size_y>0 else item_size_y

func pack_stats(skip_runtime_stats=false) -> Dictionary:
	if not cached_stats:
		if weapon_structure>=0:
			cached_structure = weapon_structure
		else:
			cached_structure = mount_size_x*mount_size_y*45*-weapon_structure
		if weapon_mass>=0:
			cached_mass = weapon_mass
		else:
			cached_mass = mount_size_x*mount_size_y*-weapon_mass
		var th = threat
		if th<0:
			th = 1.0/max(firing_delay,1.0/60) * damage
		cached_stats = {
			'damage':damage,
			'damage_type':damage_type,
			'impulse':impulse,
			'weapon_mass':cached_mass,
			'weapon_structure':cached_structure,
			'initial_velocity':initial_velocity,
			'projectile_mass':projectile_mass,
			'projectile_drag':projectile_drag,
			'projectile_thrust':projectile_thrust,
			'projectile_lifetime':projectile_lifetime,
			'projectile_turn_rate':projectile_turn_rate,
			'projectile_structure':projectile_structure,
			'firing_delay':firing_delay,
			'turn_rate':turn_rate,
			'detonation_range':detonation_range,
			'blast_radius':blast_radius,
			'threat':th,
			'guided':guided,
			'guidance_uses_velocity':guidance_uses_velocity,
			'auto_retarget':auto_retarget,
			'antimissile':antimissile,
			'projectile_mesh_path':projectile_mesh_path,
			'item_size_x':item_size_x,
			'item_size_y':item_size_y,

			'ammo_capacity':ammo_capacity,
			'reload_delay':reload_delay,
			'reload_energy':reload_energy,
			'reload_heat':reload_heat,

			'position':Vector3(translation.x,0,translation.z),
			'rotation':rotation,
			'node_path':(get_path() if (not skip_runtime_stats and is_inside_tree()) else NodePath()),
			'name':name,

			'add_heat_capacity':add_heat_capacity,
			'add_cooling':add_cooling,
			'add_battery':add_battery,
			'add_power':add_power,

			'firing_heat':firing_heat,
			'firing_energy':firing_energy,

			'heat_fraction':heat_fraction,
			'energy_fraction':energy_fraction,
			'thrust_fraction':thrust_fraction,

			'add_shield_resist':add_shield_resist,
			'add_shield_passthru':add_shield_passthru,
			'add_armor_resist':add_armor_resist,
			'add_armor_passthru':add_armor_passthru,
			'add_structure_resist':add_structure_resist,
			
			# Used for text generation, not CombatEngine:
			'help_page':help_page,
			'is_gun':is_gun(),
			'is_turret':is_turret(),
			'mount_type_display':mount_type_display,
		}
		skipped_runtime_stats=skip_runtime_stats
	elif not skip_runtime_stats and skipped_runtime_stats:
		cached_stats['node_path'] = get_path()
		skipped_runtime_stats=false
	return cached_stats

func add_stats(stats: Dictionary,skip_runtime_stats=false,_ship_node=null) -> void:
	stats['weapons'].append(pack_stats(skip_runtime_stats))
	if add_heat_capacity:
		stats['heat_capacity'] += add_heat_capacity
	if add_cooling:
		stats['cooling'] += add_cooling
	if add_battery:
		stats['battery'] += add_battery
	if add_power:
		stats['power'] += add_power
	stats['empty_mass'] += cached_mass
	stats['max_structure'] += cached_structure
	stats['threat'] += cached_stats['threat']
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
