extends Node

static func aim_forward(var ship,var weapon,var state: PhysicsDirectBodyState,var target) -> Vector3:
	if weapon==null:
		return Vector3()
	var my_pos: Vector3 = ship.get_position()
	var tgt_pos: Vector3 = target.get_position()
	var dp: Vector3 = tgt_pos - my_pos
	var dv: Vector3 = target.get_velocity() - state.linear_velocity
	var t: float = rendezvous_time(dp,dv,weapon.projectile_speed)
	if is_nan(t):
		return tgt_pos - my_pos
	t = min(t,weapon.get_projectile_lifetime())
	return dp + t*dv

static func stopping_point(var ship,var state: PhysicsDirectBodyState,var tgt_vel: Vector3):
	var pos: Vector3 = ship.get_position()
	var rel_vel: Vector3 = state.linear_velocity - tgt_vel
	var heading: Vector3 = ship.get_heading()
	var should_reverse: bool = false
	var speed = rel_vel.length()
	var accel = ship.thrust*state.inverse_mass
	var reverse_accel = ship.reverse_thrust*state.inverse_mass
	
	if(speed<=0):
		return [false, pos]
	var turn: float = acos(clamp(-rel_vel.normalized().dot(heading),-1.0,1.0))
	var dist: float = speed*turn/ship.max_angular_velocity + 0.5*speed*speed/accel
	if false: #reverse_accel>0:
		var rev_dist: float = speed*(PI-turn)/ship.max_angular_velocity \
			+ 0.5*speed*speed/reverse_accel
		if rev_dist < dist:
			should_reverse = true
			dist = rev_dist
	return [ should_reverse, pos+dist*rel_vel.normalized() ]

static func rendezvous_time(var target_location: Vector3,
		var target_velocity: Vector3, var interceptor_speed: float) -> float:
#	var target_location3: Vector3 = target.get_position()
#	var target_location: Vector3 = Vector3(target_location3[0],0,target_location3[2])
#	var target_velocity: Vector3 = target.get_velocity()
	
	var a: float = target_velocity.dot(target_velocity) - interceptor_speed*interceptor_speed
	var b: float = 2.0 * target_location.dot(target_velocity)
	var c: float = target_location.dot(target_location)
	var descriminant = b*b - 4*a*c
	
	if descriminant<0 or abs(a)<1e-4:
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

static func request_move_to_attack(ship, var state: PhysicsDirectBodyState, target):
	move_to_attack(ship,state,target)
	auto_target(ship,state,target)

static func auto_fire(ship,state: PhysicsDirectBodyState, target):
	if not target.is_a_ship():
		request_primary_fire(ship,state)
		return
	var weapon = ship.get_first_weapon_or_null(true,false)
	if weapon==null:
		return
	var aim: Vector3 = aim_forward(ship,weapon,state,target).normalized()
	request_heading(ship,state,aim)
	request_primary_fire(ship,state)

static func check_target_lock(_ship, state: PhysicsDirectBodyState, point1: Vector3,
		point2: Vector3, target) -> Dictionary:
	target.collision_mask |= 1<<30
	var space: PhysicsDirectSpaceState = state.get_space_state()
	var result: Dictionary = space.intersect_ray(point1, point2, [])
	target.collision_mask ^= 1<<30
	return result

static func auto_target(ship, state: PhysicsDirectBodyState, target):
	var weapon = ship.get_first_weapon_or_null(true,false)
	if weapon==null:
		return
	if not target.is_a_ship():
		return
	var heading: Vector3 = ship.get_heading()
	var p: Vector3 = target.get_position()
	var dp: Vector3 = p - ship.get_position()
	var dv: Vector3 = target.get_velocity() - state.linear_velocity
	dp += dv*state.step
	dv = heading*weapon.projectile_speed - dv
	dv *= weapon.get_projectile_lifetime()
	var point1 = dp-dv+p
	var point2 = dp+p
	point1[1]=5
	point2[1]=5
	var result: Dictionary = check_target_lock(ship,state,point1,point2,target)
	if not result.empty():
		request_primary_fire(ship,state)

static func move_to_attack(ship, var state: PhysicsDirectBodyState, target):
	var heading: Vector3 = ship.get_heading()
	var dp: Vector3 = target.get_position() - ship.get_position()
	var weapon = ship.get_first_weapon_or_null(true,true)
	if weapon==null:
		return
	var aim: Vector3 = aim_forward(ship,weapon,state,target)
	request_heading(ship,state,aim.normalized())
	
	# Get the circle the ship would make while turning at maximum speed:
	var full_turn_time = 2*PI / ship.max_angular_velocity
	var turn_circumference = full_turn_time * ship.max_speed
	var turn_diameter = max(turn_circumference/PI,5)
	
	# Heuristic; needs improvement
	if heading.dot(dp)>=0 and dp.length()>turn_diameter \
		or state.linear_velocity.dot(dp)<0 and heading.dot(dp.normalized())>0.9:
			request_thrust(ship,state,1.0,0.0)

static func move_to_intercept(ship, state: PhysicsDirectBodyState,
		close: float, slow: float, tgt_pos: Vector3, tgt_vel: Vector3,
		force_final_state: bool = false):
	var small_dot_product = 0.8
	var position = ship.get_position()
	var heading = ship.get_heading()
	var tgt_pos1 = Vector3(tgt_pos[0],0,tgt_pos[2])
	var dp = tgt_pos1 - position
	var dv = tgt_vel - state.linear_velocity
	var speed = dv.length()
	var is_close: bool = dp.length()<close
	if is_close and speed<slow:
		if force_final_state:
			ship.translation = Vector3(position[0],ship.translation[1],position[2])
			state.linear_velocity = tgt_vel
		return true
	var sp = stopping_point(ship, state, tgt_vel)
	var should_reverse: bool = sp[0]
	dp = tgt_pos1 - sp[1]
	var dp_dir = dp.normalized()
	var dot = dp_dir.dot(heading)
	var is_facing = dot > small_dot_product
	if !is_close or (!is_facing and !should_reverse):
		request_heading(ship,state,dp_dir)
	else:
		state.angular_velocity = Vector3(0,0,0)
	request_thrust(ship,state,float(is_facing),float(should_reverse and not is_facing))

static func request_heading(ship, state: PhysicsDirectBodyState, new_heading: Vector3):
	var heading = ship.get_heading()
	var cross = -new_heading.cross(heading)[1]
	
	if new_heading.dot(heading)>0:
		var angle = asin(min(1.0,max(-1.0,cross/new_heading.length())))
		var actual_av = sign(angle)*min(abs(angle)/state.step,ship.max_angular_velocity)
		state.angular_velocity = Vector3(0,actual_av,0)
	else:
		var left: float = float(cross >= 0.0)
		var right: float = float(cross < 0.0)
		state.angular_velocity = Vector3(0,(left-right)*ship.max_angular_velocity,0)

static func request_rotation(ship, state: PhysicsDirectBodyState, rotate: float):
	if abs(rotate)>1e-3:
		state.add_torque(Vector3(0,rotate*ship.rotation_torque,0))
	else:
		state.angular_velocity = Vector3(0,0,0)

static func request_thrust(ship, state: PhysicsDirectBodyState,forward: float,reverse: float):
	var ai_thrust = ship.thrust*min(1.0,abs(forward)) - ship.reverse_thrust*min(1.0,abs(reverse))
	ship.velocity=state.linear_velocity
	var v_thrust = Vector3(ai_thrust,0,0).rotated(Vector3(0,1,0),ship.rotation.y)
	state.add_central_force(v_thrust)

static func request_primary_fire(ship, _state: PhysicsDirectBodyState):
	ship.ai_shoot = true

static func request_velocity(ship, state: PhysicsDirectBodyState, \
		velocity_goal: Vector3,prioritize_speed: bool, \
		_prefer_reverse: bool, include_weapon: bool = false):
	# FIXME: include gravity in this equation
	var my_velocity = state.linear_velocity
	var heading: Vector3 = ship.get_heading()
	var weapon
	if include_weapon:
		weapon = ship.get_first_weapon_or_null(true,true)
		if weapon!=null:
			my_velocity += weapon.projectile_speed*heading
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
		new_velocity += weapon.projectile_speed*heading
	
	if velocity_error.length()<0.001:
		state.linear_velocity = velocity_goal
		state.angular_velocity = Vector3(0,0,0)
#		s += 'near velocity goal\n'
		return
	elif prioritize_speed or abs(head_vs_thrust) > 0.999:
		var desired_thrust = needed_thrust.dot(heading)
		if desired_thrust > 0:
			var actual_thrust = min(desired_thrust,ship.thrust)
#			s += 'fwd thrust %08.4f\n'%[actual_thrust]
			state.add_central_force(actual_thrust*heading)
			new_velocity += actual_thrust*heading*state.step*state.inverse_mass
		else:
			var actual_thrust = min(-desired_thrust,ship.reverse_thrust)
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
	var actual_angular_velocity: float = min(ship.max_angular_velocity,desired_angular_velocity)
	
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
