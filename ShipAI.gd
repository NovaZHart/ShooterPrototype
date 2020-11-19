extends Node

var tick: int = 0
var tick_at_last_shot: int = 0

var target_path: NodePath setget set_target_path,get_target_path

# For stopping:
var am_stopping: bool = false
var use_forward_engines: bool = false

# For threat detection:
var near_shape: CylinderShape
var threat_vector: Vector3 = Vector3(0,0,0)
var nearby_enemy_ships: Array
var threat_threshold = 0.01
var shape_radius: float = 70.0
var target_search_radius: float = 1000.0
var near_objects: Array
var got_near_objects: bool = false

signal land

func set_target_path(var target):
	target_path = target

func get_target_path() -> NodePath:
	return target_path

func clear_data():
	got_near_objects=false
	near_objects=[]
	nearby_enemy_ships=[]

func apply_ship_transform(var scale: Vector3, var origin: Vector3, var ship) -> Transform:
	var u = Transform()
	var st = ship.translation
	u = u.scaled(scale).translated(origin/scale).rotated(Vector3(0,1,0),ship.rotation[1])
	u.origin += Vector3(st.x,0,st.y)
	return u

func make_threat_vector(var ship,var t: float):
	var my_position: Vector3 = ship.position_at_time(t)
	var my_threat_vector: Vector3 = Vector3(0,0,0)
	var my_nearby_enemy_ships: Array = []
	var dw_div = 0
	for dict in near_objects:
		var object = dict.collider
		var obj_pos: Vector3 = object.position_at_time(t)
		var position: Vector3 = obj_pos - my_position
		var threat: float = object.threat_at_time(t)
		if object.is_a_ship() and object.team!=ship.team:
			my_nearby_enemy_ships.append(object)
		var distance: float = Vector2(position[0],position[1]).length()
		var distance_weight = max(0.0,(shape_radius-distance)/shape_radius)
		var weight: float = distance_weight*threat
		dw_div += distance_weight
		my_threat_vector += weight * position.normalized()
	threat_vector = Vector3(my_threat_vector[0],0,my_threat_vector[2])/max(1.0,dw_div)
	nearby_enemy_ships = my_nearby_enemy_ships

func _ready():
	near_shape = CylinderShape.new()
	near_shape.radius = shape_radius
	near_shape.height = 10

func get_collisions(var space: PhysicsDirectSpaceState, var _state: PhysicsDirectBodyState, var ship):
	if not got_near_objects!=null:
		var query = PhysicsShapeQueryParameters.new()
		query.collision_mask = ship.enemy_mask
		query.transform = ship.transform
		query.set_shape(near_shape)
		near_objects = space.intersect_shape(query) # (query,state.linear_velocity)
		got_near_objects=true
	return near_objects

func pick_nearest_target(_space: PhysicsDirectSpaceState,
		_state: PhysicsDirectBodyState, ship, system: Spatial):
	var ship_position: Vector3 = ship.get_position()
	
	var target_object = null
	var target_distance: float = 9e9
	
	for obj in nearby_enemy_ships:
		if not obj.is_a_ship() or not obj.is_alive():
			continue
		var dist = (obj.get_position()-ship_position).length()
		if dist<target_distance:
			target_object = obj
	
	if target_object!=null:
		target_path=target_object.get_path()
		return target_object
	
	# No nearby targets, so expand to the full search radius
	var near_path = system.nearest_enemy(target_path,ship.translation,ship.enemy)
	target_object = get_node_or_null(near_path)
	
	if target_object!=null:
		target_path=near_path
	
	return target_object

func fight(var state: PhysicsDirectBodyState, var ship, var system: Spatial) -> bool:
	var space: PhysicsDirectSpaceState = state.get_space_state()
	var target = pick_nearest_target(space,state,ship,system)
	if target == null:
		return false
	ship.request_move_to_attack(state,target)
	return true

func evade(var state: PhysicsDirectBodyState, var ship, var _system: Spatial) -> void:
	var threat_level: float = threat_vector.length()
	#var norm_vector: Vector3 = threat_vector.normalized()
	var react_vector: Vector3 = -threat_vector.normalized()
#
#	var s: String = "threat@[%8.4f x %8.4f] level %8.4f\n"% \
#		[norm_vector[0],norm_vector[2],threat_level]
	
	if threat_level < threat_threshold:
		var tock: float = tick%240-120
		react_vector = react_vector.rotated(Vector3(0,1,0),PI/4.0 * exp(-tock*tock/40))
#		s += "Pulsating react vector.\n"
	
	#game_state.print_to_console(s)
	
	ship.request_velocity(state,react_vector*ship.max_speed,true,false)

func approach_destination(var destination: Vector3,
		var state: PhysicsDirectBodyState, var ship, var _system: Spatial):
	var towards_destination: Vector3 = destination-ship.translation
	towards_destination[1] = 0
	ship.request_velocity(state,towards_destination.normalized()*ship.max_speed,false,true)

func coward_ai(state: PhysicsDirectBodyState, var ship, system: Spatial):
	var _discard = get_collisions(state.get_space_state(),state,system)
	make_threat_vector(ship,0.5)
	if threat_vector.length() > threat_threshold:
		evade(state,ship,system)
	else:
		# When there are no threats, fly away from system center
		var pos_norm = ship.get_position().normalized()
		if pos_norm.length()<0.99:
			pos_norm = Vector3(1,0,0)
		ship.request_velocity(state,pos_norm*ship.max_speed,true,false)

func attacker_ai(var state: PhysicsDirectBodyState, var ship, var system: Spatial):
	var target = null

	if not target_path.is_empty():
		target = get_node_or_null(target_path)
	if tick-tick_at_last_shot>600:
		# After 10 seconds without firing, reevaluate target
		target=null
	if target != null and tick%1200==0:
		# After 20 seconds, if ship is out of range, reevaluate target
		var weapon_range = ship.get_weapon_range()
		var target_distance = Vector2(ship.translation.x,ship.translation.z). \
			distance_to(Vector2(target.translation.x,target.translation.z))
		if target_distance > 1.5*weapon_range:
			target = null
	if target != null and not target.is_alive():
		target = null
	if target != null and not target.is_a_ship():
		target = null

	if target != null:
		ship.request_move_to_attack(state,target)
	else:
		target_path = NodePath()
		if not fight(state,ship,system):
			ship.request_stop(Vector3(0,0,0),state,system)
	if ship.ai_shoot:
		tick_at_last_shot=tick

func landing_ai(var state: PhysicsDirectBodyState, var ship,
		var system: Spatial, var destination: Vector3):
	make_threat_vector(ship,0.5)
	if threat_vector.length()>0:
		evade(state,ship,system)
	else:
		ship.request_stop(destination,state,system)

func ai_step(var state: PhysicsDirectBodyState, var ship, var system: Spatial) -> void:
	if ship.shields<=0 and ship.hull<=0 and ship.structure<0.5*ship.max_structure:
		coward_ai(state,ship,system)
	else:
		attacker_ai(state,ship,system)
	clear_data()
	tick += 1
