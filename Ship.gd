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

export var shields: float = max_shields setget set_shields,get_shields
export var hull: float = max_hull setget set_hull,get_hull
export var structure: float = max_structure setget set_structure,get_structure

export var shield_heal: float = 20 setget set_shield_heal,get_shield_heal
export var hull_heal: float = 10 setget set_hull_heal,get_hull_heal

var enemy_mask: int setget ,get_enemy_mask
var enemy_ship_mask: int setget ,get_enemy_mask

signal shoot
signal ai_step
signal die
signal hp_changed

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
				child.shoot(translation+delta*linear_velocity,rotation[1]+delta*angular_velocity[1],linear_velocity,team)

func get_first_weapon_or_null():
	for child in get_children():
		if child.has_method('shoot'):
			return child
	return null

func aim_forward(var state: PhysicsDirectBodyState,var target) -> Vector3:
	var weapon = get_first_weapon_or_null()
	if weapon==null:
		return Vector3()
	var my_pos: Vector3 = get_position()
	var tgt_pos: Vector3 = target.get_position()
	var dp: Vector3 = tgt_pos - my_pos
	var dv: Vector3 = target.get_velocity() - state.linear_velocity
	var t: float = rendezvous_time(dp,dv,weapon.initial_projectile_speed())
	if is_nan(t):
		return tgt_pos - my_pos
	t = min(t,weapon.get_projectile_lifetime())
	return dp + t*dv

func stopping_point(var state: PhysicsDirectBodyState,var tgt_vel: Vector3):
	var pos: Vector3 = Vector3(translation[0],0,translation[2])
	var rel_vel: Vector3 = state.linear_velocity - tgt_vel
	var heading: Vector3 = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation[1])
	var should_reverse: bool = false
	var speed = rel_vel.length()
	var accel = thrust*state.inverse_mass
	var reverse_accel = reverse_thrust*state.inverse_mass
	
	if(speed<=0):
		return [should_reverse, pos]
	var turn: float = acos(clamp(-rel_vel.normalized().dot(heading),-1.0,1.0))
	var dist: float = speed*turn/max_angular_velocity + 0.5*speed*speed/accel
	if reverse_accel>0:
		var rev_dist: float = speed*(PI-turn)/max_angular_velocity \
			+ 0.5*speed*speed/reverse_accel
		if rev_dist < dist:
			should_reverse = true
			dist = rev_dist
	return [ should_reverse, pos+dist*rel_vel ]

static func rendezvous_time(var target_location: Vector3,
		var target_velocity: Vector3, var interceptor_speed: float) -> float:
#	var target_location3: Vector3 = target.get_position()
#	var target_location: Vector3 = Vector3(target_location3[0],0,target_location3[2])
#	var target_velocity: Vector3 = target.get_velocity()
	
	var a: float = target_velocity.dot(target_velocity) - interceptor_speed*interceptor_speed
	var b: float = 2.0 * target_location.dot(target_velocity)
	var c: float = target_location.dot(target_location)
	var descriminant = b*b - 4*a*c
	
	if descriminant<0:
		return NAN
	
	var d1 = (-b + descriminant)/(2.0*a)
	var d2 = (-b - descriminant)/(2.0*a)
	var mn = min(d1,d2)
	var mx = max(d1,d2)
	if mn>0:
		return mn
	elif mx>0:
		return mx
	return NAN

func request_move_to_attack(var state: PhysicsDirectBodyState, var target):
	move_to_attack(state,target)
	auto_target(state,target,false)

func auto_fire(state: PhysicsDirectBodyState, target):
	if not target.is_a_ship():
		request_primary_fire(state)
		return
	var aim: Vector3 = aim_forward(state,target)
	request_heading(state,aim.normalized())
	auto_target(state,target,true)

func auto_target(state: PhysicsDirectBodyState, target, always_fire: bool):
	var weapon = get_first_weapon_or_null()
	if weapon==null:
		return
	if not target.is_a_ship():
		if always_fire:
			request_primary_fire(state)
		return
	var heading: Vector3 = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation[1])
	var p: Vector3 = target.get_position()
	var dp: Vector3 = target.get_position() - get_position()
	var dv: Vector3 = target.get_velocity() - state.linear_velocity
	dp += dv*state.step
	dv = heading*weapon.initial_projectile_speed() - dv
	dv *= weapon.get_projectile_lifetime()
	target.collision_mask |= 1<<30
	var space: PhysicsDirectSpaceState = state.get_space_state()
	var point1 = dp-dv+p
	var point2 = dp+p
	point1[1]=5
	point2[1]=5
	var result: Dictionary = space.intersect_ray(point1, point2, [self])
	if always_fire or not result.empty():
		request_primary_fire(state)
	target.collision_mask ^= 1<<30

func move_to_attack(var state: PhysicsDirectBodyState, var target):
	var heading: Vector3 = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation[1])
	var dp: Vector3 = target.get_position() - get_position()
	var aim: Vector3 = aim_forward(state,target)
	request_heading(state,aim.normalized())
	
	# Get the circle the ship would make while turning at maximum speed:
	var full_turn_time = 2*PI / max_angular_velocity
	var turn_circumference = full_turn_time * max_speed
	var turn_diameter = max(turn_circumference/PI,5)
	
	# Heuristic; needs improvement
	if heading.dot(dp)>=0 and dp.length()>turn_diameter \
		or state.linear_velocity.dot(dp)<0 and heading.dot(dp.normalized())>0.9:
			request_thrust(state,1.0,0.0)

func move_to_intercept(var state: PhysicsDirectBodyState,
		var close: float, var slow: float,
		var tgt_pos: Vector3, var tgt_vel: Vector3):
	var small_dot_product = 0.8
	var position = Vector3(translation[0],0,translation[2])
	var heading = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation[1])
	var tgt_pos1 = Vector3(tgt_pos[0],0,tgt_pos[2])
	var dp = tgt_pos1 - position
	var dv = tgt_vel - state.linear_velocity
	var speed = dv.length()
	var is_close: bool = dp.length()<close
	if is_close and speed<slow:
		return true
	var sp = stopping_point(state, tgt_vel)
	var should_reverse: bool = sp[0]
	dp = tgt_pos1 - sp[1]
	var dot = dp.normalized().dot(heading)
	var is_facing = dot > small_dot_product
	if is_close or (!is_facing and !should_reverse):
		pass
	else:
		state.angular_velocity = Vector3(0,0,0)
	request_thrust(state,float(is_facing),float(should_reverse and not is_facing))

func request_intercept_try2(var target, var state: PhysicsDirectBodyState):
	var slow = thrust*state.inverse_mass*state.step
	var small = slow*state.step
	move_to_intercept(state,small,slow,target.get_position(),target.get_velocity())

func request_heading(var state: PhysicsDirectBodyState, var new_heading: Vector3):
	var heading = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation[1])
	var cross = -new_heading.cross(heading)[1]
	
	if new_heading.dot(heading)>0:
		var angle = asin(min(1.0,max(-1.0,cross/new_heading.length())))
		var actual_av = sign(angle)*min(abs(angle)/state.step,max_angular_velocity)
		state.angular_velocity = Vector3(0,actual_av,0)
	else:
		var left: float = float(cross >= 0.0)
		var right: float = float(cross < 0.0)
		state.angular_velocity = Vector3(0,(left-right)*max_angular_velocity,0)

func request_rotation(var state: PhysicsDirectBodyState, var rotate: float):
	if abs(rotate)>1e-3:
		state.add_torque(Vector3(0,rotate*rotation_torque,0))
	else:
		state.angular_velocity = Vector3(0,0,0)

func request_thrust(var state: PhysicsDirectBodyState,var forward: float,var reverse: float):
	var ai_thrust = thrust*min(1.0,abs(forward)) - reverse_thrust*min(1.0,abs(reverse))
	velocity=state.linear_velocity
	var v_thrust = Vector3(ai_thrust,0,0).rotated(Vector3(0,1,0),rotation.y)
	state.add_central_force(v_thrust)

func request_primary_fire(var _state: PhysicsDirectBodyState):
	ai_shoot = true

func request_stop(var destination: Vector3,
		var state: PhysicsDirectBodyState, var _system: Spatial):
	var towards_destination: Vector3 = destination-translation
	towards_destination[1] = 0
	var distance: float = towards_destination.length()
	var speed: float = state.linear_velocity.length()
	if distance < 0.03 and speed < 0.1:
		state.linear_velocity = Vector3(0,0,0)
		state.angular_velocity = Vector3(0,0,0)
		#game_state.print_to_console('reached destination')
		return
#	var s: String = ''
	
	var heading: Vector3 = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation[1])
	var course: Vector3 = state.linear_velocity.normalized()
	var turn_direction: float = max(-0.99999,min(0.99999,heading.dot(course)))
	var _turn: float = acos(turn_direction)
	
	var fwd_turnaround_distance: float = (PI/max_angular_velocity)*max_speed
	var fwd_decelleration_distance = max_speed*max_speed/(2*thrust*state.inverse_mass)
	var fwd_stop_distance: float = fwd_decelleration_distance+fwd_turnaround_distance
	
	var rev_turnaround_distance: float
	var rev_stop_distance: float
	var rev_decelleration_distance: float
	
	var stop_distance = fwd_stop_distance
	var _turnaround_distance = fwd_turnaround_distance
	var _decelleration_distance = fwd_decelleration_distance
	#var prefer_reverse: bool = false
	var _thrust_to_use: float = thrust
	
	if false: #reverse_thrust > 1e-3:
		rev_turnaround_distance = 0 # ((PI-turn)/max_angular_velocity)*speed
		rev_decelleration_distance = max_speed*max_speed/(2*reverse_thrust*state.inverse_mass)
		rev_stop_distance = rev_turnaround_distance + rev_decelleration_distance
		if rev_stop_distance < stop_distance:
			stop_distance = rev_stop_distance
			#prefer_reverse = true
			_thrust_to_use = reverse_thrust
			_decelleration_distance = rev_decelleration_distance
	
#	s = 'speed %08.4f dist %08.4f\n'%[speed,distance]
#	s += 'decel dist: fwd %08.4f rev %08.4f\n'%[fwd_decelleration_distance,rev_decelleration_distance]
#	s += 'turn dist: fwd %08.4f rev %08.4f\n'%[fwd_turnaround_distance,rev_turnaround_distance]
#	s += 'stop dist: fwd %08.4f rev %08.4f\n'%[fwd_stop_distance,rev_stop_distance]
#	s += 'use reverse engines\n' if prefer_reverse else 'use forward engines\n'
	
	if distance<stop_distance:
		var velocity_goal: Vector3
		velocity_goal = towards_destination.normalized()* \
			max(max_speed*distance/stop_distance,.097)
		request_velocity(state,velocity_goal,false,false) # prefer_reverse)
	else:
#		s += 'head to destination\n'
		request_velocity(state,towards_destination.normalized()*max_speed,false,false) # prefer_reverse)
	#game_state.print_to_console('console',s)

func request_velocity(var state: PhysicsDirectBodyState, \
		var velocity_goal: Vector3,var prioritize_speed: bool, \
		var _prefer_reverse: bool, var include_weapon: bool = false):
	# FIXME: include gravity in this equation
	var my_velocity = state.linear_velocity
	var heading: Vector3 = Vector3(1,0,0).rotated(Vector3(0,1,0),rotation[1])
	var weapon
	if include_weapon:
		weapon = get_first_weapon_or_null()
		if weapon!=null:
			my_velocity += weapon.initial_projectile_speed()*heading
	var velocity_error: Vector3 = velocity_goal-my_velocity
	var needed_thrust: Vector3 = (velocity_error)/(state.step*state.inverse_mass)
	var goal_norm: Vector3 = velocity_goal.normalized()
	var thrust_norm: Vector3 = needed_thrust.normalized()
	var head_vs_thrust: float = heading.dot(thrust_norm)
	
	#var s: String = 'vel_dot = %08.4f turn = %08.4f\n'%[vel_dot,turn]
#	var s: String = 'goal: [%08.4f, %08.4f, %08.4f]\n'%[
#		velocity_goal[0], velocity_goal[1], velocity_goal[2] ]
#	s += 'err: [%08.4f, %08.4f, %08.4f]\n'%[
#		velocity_error[0], velocity_error[1], velocity_error[2] ]
	
	var new_velocity: Vector3 = state.linear_velocity
	if include_weapon and weapon!=null:
		new_velocity += weapon.initial_projectile_speed()*heading
	
	if velocity_error.length()<0.001:
		state.linear_velocity = velocity_goal
		state.angular_velocity = Vector3(0,0,0)
#		s += 'near velocity goal\n'
		return
	elif prioritize_speed or abs(head_vs_thrust) > 0.999:
		var desired_thrust = needed_thrust.dot(heading)
		if desired_thrust > 0:
			var actual_thrust = min(desired_thrust,thrust)
#			s += 'fwd thrust %08.4f\n'%[actual_thrust]
			state.add_central_force(actual_thrust*heading)
			new_velocity += actual_thrust*heading*state.step*state.inverse_mass
		else:
			var actual_thrust = min(-desired_thrust,reverse_thrust)
#			s += 'rev thrust %08.4f\n'%[actual_thrust]
			state.add_central_force(-actual_thrust*heading)
			new_velocity += -actual_thrust*heading*state.step*state.inverse_mass
#	else:
#		s += 'no thrust\n'
	
	var new_error: Vector3 = velocity_goal - new_velocity
	var new_err_norm: Vector3 = new_error.normalized()
	var heading_neg_goal: Vector3 = goal_norm if prioritize_speed else new_err_norm
	var turn_direction: float = heading.cross(heading_neg_goal)[1]
	
	var old_err_norm: Vector3 = velocity_error.normalized()
	var old_heading_neg_goal: Vector3 = goal_norm if prioritize_speed else old_err_norm
	var _old_turn_direction: float = heading.cross(old_heading_neg_goal)[1]
	
	var turn_amount: float = max(-0.99999,min(0.99999,heading.dot(heading_neg_goal)))
	var desired_angular_velocity: float = acos(turn_amount)/state.step
	var actual_angular_velocity: float = min(max_angular_velocity,desired_angular_velocity)
	
	if turn_direction>0:
		state.angular_velocity = Vector3(0,actual_angular_velocity,0)
#		s += 'turn positive: %08.4f\n'%[actual_angular_velocity]
	elif turn_direction<0:
		state.angular_velocity = Vector3(0,-actual_angular_velocity,0)
#		s += 'turn negative: %08.4f\n'%[-actual_angular_velocity]
	elif turn_amount<0:
		# We're pointing backwards.
		state.angular_velocity = Vector3(0,actual_angular_velocity,0)
#		s += 'turn backwards %08.4f\n'%[actual_angular_velocity]
	else:
#		s += 'turn (-none-)\n'
		state.angular_velocity = Vector3(0,0,0)
#	return s

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
