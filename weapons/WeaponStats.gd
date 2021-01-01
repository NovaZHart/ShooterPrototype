extends MeshInstance

export var damage: float = 30
export var impulse: float = 0
export var weapon_mass: float = 15
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
export var mount_size_x: int = 0
export var mount_size_y: int =0
export var mount_type: String

func mount_size() -> Vector2:
	if mount_size_x>0 and mount_size_y>0:
		return Vector2(mount_size_x,mount_size_y)
	return Vector2(2,2)

func add_stats(stats: Dictionary) -> void:
	var th = threat
	if th<0:
		th = 1.0/max(firing_delay,1.0/60) * damage
	stats['mass'] += weapon_mass
	stats['max_structure'] += weapon_structure
	stats['threat'] += th
	stats['weapons'].append({
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
		'instance_id':get_instance(),
		'node_path':get_path(),
	})
