extends MeshInstance

export var damage: float = 30
export var impulse: float = 0
export var weapon_mass: float = 0
export var weapon_structure: float = 30
export var initial_velocity: float = 30
export var projectile_mass: float = 0.3
export var projectile_drag: float = 5
export var projectile_thrust: float = 0
export var projectile_lifetime: float = 0.7
export var projectile_turn_rate: float = 8
export var firing_delay: float = 0.1
export var turn_rate: float = 0
export var detonation_range: float = 0
export var blast_radius: float = 0
export var threat: float = -1
export var guided: bool = false
export var guidance_uses_velocity: bool = false
export var projectile_mesh_path: String
export var item_size_x: int = 1
export var item_size_y: int = 3
export var mount_size_x: int = 0 setget ,get_mount_size_x
export var mount_size_y: int = 0 setget ,get_mount_size_y
export var mount_type: String = 'gun'
export var help_page: String = 'weapons'

var cached_bbcode = null
var cached_stats = null
var skipped_runtime_stats: bool = true

func is_WeaponStats(): pass # Never called; must only exist

func is_mount_point(): # Never called; must only exist
	pass

func is_mounted(): # Never called; must only exist
	pass

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
		var th = threat
		if th<0:
			th = 1.0/max(firing_delay,1.0/60) * damage
		cached_stats = {
			'damage':damage,
			'impulse':impulse,
			'initial_velocity':initial_velocity,
			'projectile_mass':projectile_mass,
			'projectile_drag':projectile_drag,
			'projectile_thrust':projectile_thrust,
			'projectile_lifetime':projectile_lifetime,
			'projectile_turn_rate':projectile_turn_rate,
			'firing_delay':firing_delay,
			'turn_rate':turn_rate,
			'blast_radius':blast_radius,
			'detonation_range':detonation_range,
			'threat':th,
			'guided':guided,
			'guidance_uses_velocity':guidance_uses_velocity,
			'projectile_mesh_path':projectile_mesh_path,
			'position':Vector3(translation.x,0,translation.z),
			'rotation':rotation,
			'node_path':(get_path() if (not skip_runtime_stats and is_inside_tree()) else NodePath()),
			'name':name,
			
			# Used for text generation, not CombatEngine:
			'help_page':help_page,
			'item_size_x':item_size_x,
			'item_size_y':item_size_y,
			'weapon_mass':weapon_mass,
			'weapon_structure':weapon_structure,
			'mount_type':mount_type,
		}
		skipped_runtime_stats=skip_runtime_stats
	elif not skip_runtime_stats and skipped_runtime_stats:
		cached_stats['node_path'] = get_path()
		skipped_runtime_stats=false
	return cached_stats

func add_stats(stats: Dictionary,skip_runtime_stats=false) -> void:
	stats['empty_mass'] += weapon_mass
	stats['max_structure'] += weapon_structure
	stats['weapons'].append(pack_stats(skip_runtime_stats))
	stats['threat'] += cached_stats['threat']
