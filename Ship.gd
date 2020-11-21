extends RigidBody

var ai setget set_ai,get_ai
var team: int = 1 setget set_team, get_team
var enemy: int = 0 setget , get_enemy

export var rotation_torque: float = 70
export var max_angular_velocity: float = 2

var combined_aabb=null setget ,get_combined_aabb
export var thrust: float = 20
export var reverse_thrust: float = 7
var velocity: Vector3 = Vector3()
export var max_speed: float = 30 setget ,get_max_speed
var tick: int = 0
var ai_shoot: bool = false
var minimap_heading: Object = null setget ,get_minimap_heading
var minimap_velocity: Object = null setget ,get_minimap_velocity
var minimap_location: Object = null setget ,get_minimap_location

export var max_shields: float = 100 setget set_max_shields,get_max_shields
export var max_hull: float = 200 setget set_max_hull,get_max_hull
export var max_structure: float = 400 setget set_max_structure,get_max_structure

var shields: float = max_shields setget set_shields,get_shields
var hull: float = max_hull setget set_hull,get_hull
var structure: float = max_structure setget set_structure,get_structure

export var shield_heal: float = 20 setget set_shield_heal,get_shield_heal
export var hull_heal: float = 10 setget set_hull_heal,get_hull_heal

var enemy_mask: int setget ,get_enemy_mask
var enemy_ship_mask: int setget ,get_enemy_mask

signal shoot
signal ai_step
signal die
signal hp_changed
signal land
signal target_changed

func is_alive():
	return structure > 0

func get_shield_heal() -> float: return shield_heal
func set_shield_heal(f: float): shield_heal=f
func get_hull_heal() -> float: return hull_heal
func set_hull_heal(f: float): hull_heal=f

func get_shields() -> float: return shields
func set_shields(f: float):  shields = f
func get_hull() -> float: return hull
func set_hull(f: float): hull = f
func get_structure() -> float: return structure
func set_structure(f: float): structure=f
func get_max_shields() -> float: return max_shields
func set_max_shields(f: float): max_shields=f
func get_max_hull() -> float: return max_hull
func set_max_hull(f: float): max_hull = f
func get_max_structure() -> float: return max_structure
func set_max_structure(f: float): max_structure = f

func get_hp() -> Dictionary:
	return {
		'shields': shields,
		'max_shields': max_shields,
		'hull': hull,
		'max_hull': max_hull,
		'structure': structure,
		'max_structure': max_structure
	}

func emit_landing_signal():
	emit_signal('land')

func emit_target_changed_signal(target: NodePath):
	emit_signal('target_changed',target)

func fully_heal():
	shields = max_shields
	hull = max_hull
	structure = max_structure

func set_max_hp(var shields_: int, var hull_: int, var structure_: int):
	max_shields = shields_
	max_hull = hull_
	max_structure = structure_
	shields = min(shields,max_shields)
	hull = min(hull,max_hull)
	structure = min(structure,max_structure)

func set_hp(var shields_: int, var hull_: int, var structure_: int):
	max_shields=max(max_shields,shields_)
	max_hull=max(max_hull,hull_)
	max_structure=max(max_structure,structure_)
	shields=shields_
	hull=hull_
	structure=structure_

func receive_damage(var amount: float):
	if amount<=0:
		return
	if shields>amount:
		shields -= amount
		emit_signal('hp_changed',self)
		return
	amount -= shields
	shields = 0
	if hull>amount:
		hull -= amount
		emit_signal('hp_changed',self)
		return
	amount -= hull
	hull = 0
	if structure>amount:
		structure -= amount
		emit_signal('hp_changed',self)
		return
	structure = 0
	emit_signal('hp_changed',self)
	emit_signal('die',amount)

func is_a_ship() -> bool: return true
func is_a_planet() -> bool: return false
func is_a_projectile() -> bool: return false
func is_immobile() -> bool: return false
func get_velocity() -> Vector3: return linear_velocity

func get_ai(): return ai
func get_max_speed() -> float: return max_speed
func get_enemy_mask() -> int: return enemy_ship_mask|collision_mask
func get_enemy_ship_mask() -> int: return enemy_ship_mask
func threat_at_time(t: float) -> float:
	var result=0
	for child in get_children():
		if child.has_method('threat_at_time'):
			result = max(result,child.threat_at_time(t)*5 + 10)
	return result
func get_team(): return team
func get_enemy(): return enemy

func get_minimap_heading():
	var h = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation[1])
	return Vector2(h[2],-h[0])
	
func get_minimap_location():
	var loc = translation
	return Vector2(loc[2],-loc[0])

func get_minimap_velocity():
	var vel = linear_velocity
	return Vector2(vel[2],-vel[0])

func set_ai(var new_ai):
	if ai!=null and ai.is_class('Node'):
		ai.queue_free()
	ai = new_ai
	if new_ai!=null and new_ai.is_class('Node'):
		add_child(ai)

func position_at_time(t: float) -> Vector3:
	return translation + linear_velocity*t

func get_position() -> Vector3:
	return Vector3(translation[0],0,translation[2])

func set_team(var new_team: int):
	team=new_team
	if team:
		enemy=0
	else:
		enemy=1
	collision_layer = 1 << (2*team)
	collision_mask = 1 << (2*enemy+1)
	enemy_ship_mask = (1<<(2*enemy))

func _init():
	gravity_scale=0
	axis_lock_linear_y=true
	axis_lock_angular_x=true
	axis_lock_angular_z=true
	set_team(0)

func get_weapon_range() -> float:
	var max_range = 0
	for child in get_children():
		if child.has_method('get_weapon_range'):
			max_range = max(max_range,child.get_weapon_range())
	return max_range

func init_children(node: Node):
	for child in node.get_children():
		if child.has_signal('shoot'):
			child.connect('shoot',self,'pass_shoot_signal')
		if child is VisualInstance:
			child.layers=4
		if child.get_child_count()>0:
			init_children(child)

func _enter_tree():
	init_children(self)
#	make_transforms(Vector3(100,50,100),Vector3(20,50,20))

func pass_shoot_signal(var shot: Node):
	emit_signal('shoot',shot)

func clear_ai():
	ai_shoot = false

#func set_action(var rotate: float,var forward: float,var reverse: float,var shoot: bool):
#	ai_action = true
#	ai_thrust = thrust*min(1.0,abs(forward)) - reverse_thrust*min(1.0,abs(reverse))
#	ai_rotate = rotate * rotation_torque
#	ai_shoot = shoot

func slow_heal(var delta):
	var healed=false
	if shield_heal>0 and shields<max_shields:
		shields = min(shields+shield_heal*delta,max_shields)
		healed=true
	if hull_heal>0 and hull<max_hull:
		hull = min(hull+hull_heal*delta,max_hull)
		healed=true
	if healed:
		emit_signal('hp_changed',self)

func _physics_process(var delta):
	slow_heal(delta)
	if ai_shoot:
		for child in get_children():
			if child.has_method('shoot'):
				child.shoot(translation+delta*linear_velocity, \
					rotation[1]+delta*angular_velocity[1],linear_velocity, \
					angular_velocity[1],team)

func get_first_weapon_or_null(allow_non_turret: bool,allow_turret: bool):
	for child in get_children():
		if child.has_method('shoot'):
			var turret=child.is_a_turret()
			if (turret and allow_turret) or (allow_non_turret and not turret):
				return child
	return null

func recurse_combine_aabb(node: Node):
	var result: AABB = AABB()
	if node is VisualInstance:
		result = node.get_aabb()
	for child in node.get_children():
		result=result.merge(recurse_combine_aabb(child))
	return result

func get_combined_aabb():
	if combined_aabb==null:
		var result: AABB = AABB()
		for child in get_children():
			result=result.merge(recurse_combine_aabb(child))
		combined_aabb=result
	return combined_aabb

func _integrate_forces(var state: PhysicsDirectBodyState):
	if ! is_alive():
		return
	tick += 1
	clear_ai()
	var speed: float = state.linear_velocity.length()
	if speed > max_speed:
		# Use quadratic drag beyond max_speed. Slows the ship rapidly
		# at extreme speeds. Smaller effect near max_speed.
		state.add_central_force(-0.1*speed*state.linear_velocity)
	emit_signal('ai_step',state)
	if abs(state.angular_velocity[1]) > max_angular_velocity:
		state.angular_velocity[1] = max_angular_velocity*sign(state.angular_velocity[1])
