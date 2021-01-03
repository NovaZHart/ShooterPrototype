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
export var item_size_x: int = 1
export var item_size_y: int = 3
export var mount_size_x: int = 0 setget ,get_mount_size_x
export var mount_size_y: int = 0 setget ,get_mount_size_y
export var mount_type: String = 'gun'
export var help_page: String = 'weapons'

var cached_bbcode = null

func is_mount_point(): # Never called; must only exist
	pass

func is_mounted(): # Never called; must only exist
	pass

func approximate_range() -> float:
	if projectile_drag>0 and projectile_thrust>0:
		return max(initial_velocity,projectile_thrust/projectile_drag)*max(1.0/60,projectile_lifetime)
	return initial_velocity*max(1.0/60,projectile_lifetime)

func make_cell(var a,var b):
	return '[cell]'+str(a)+'[/cell][cell]'+str(b)+'[/cell]'

func get_bbcode() -> String:
	if cached_bbcode == null:
		var bbcode: String = '[table=2]'
		
		# Weapon stats:
		bbcode += make_cell('type',mount_type)
		bbcode += make_cell('size',str(item_size_x)+'x'+str(item_size_y))
		bbcode += make_cell('weapon mass',weapon_mass)
		bbcode += make_cell('structure bonus',weapon_structure)
		if turn_rate: bbcode += make_cell('turret turn rate',turn_rate)
		
		# Projectile stats:
		if damage:
			if firing_delay<=1.0/60:
				bbcode += make_cell('shots per second','60 (continuous fire)')
			else:
				bbcode += make_cell('shots per second',ceil(1.0/max(1.0/60,firing_delay)))
			bbcode += make_cell('damage per shot',damage)
			bbcode += make_cell('damage per second',round(damage/max(1.0/60,firing_delay)*10)/10)
		if impulse:
			bbcode += make_cell('hit force per second',round(impulse/max(1.0/60,firing_delay)*10)/10)
		if detonation_range: bbcode += make_cell('detonation range',detonation_range)
		if blast_radius: bbcode += make_cell('blast radius',blast_radius)
		bbcode += make_cell('range',round(approximate_range()*100)/100)
		if guided:
			bbcode += make_cell('guidance','interception' if guidance_uses_velocity else 'homing')
			bbcode += make_cell('turn rate',projectile_turn_rate)
		else:
			bbcode += make_cell('guidance','unguided')

		cached_bbcode = bbcode+'[/table]\n'
	return cached_bbcode

func get_mount_size_x() -> int:
	return mount_size_x if mount_size_x>0 else item_size_x

func get_mount_size_y() -> int:
	return mount_size_y if mount_size_y>0 else item_size_y

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
