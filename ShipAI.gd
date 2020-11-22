extends Reference

var tick: int = 0
var tick_at_last_shot: int = 0

var cached_sorted_enemy_list: Array
var tick_at_last_list: int = -9999
const default_max_age: int = 10

var destination: Vector3 setget set_destination, get_destination
var target_path: NodePath setget set_target_path,get_target_path

# For stopping:
var am_stopping: bool = false
var use_forward_engines: bool = false

# For threat detection:
var near_shape: CylinderShape
var threat_vector: Vector3 = Vector3(0,0,0)
var threat_threshold = 0.01
var shape_radius: float = 70.0
var target_search_radius: float = 1000.0
var near_objects: Array
var got_near_objects: bool = false

func set_destination(f: Vector3): destination=Vector3(f.x,5,f.z)
func get_destination() -> Vector3: return destination
func set_target_path(f: NodePath): target_path = f
func get_target_path() -> NodePath: return target_path

func randomize_destination():
	var radius = 20 + pow(randf(),2)*60
	var angle = randf()*2*PI
	destination = Vector3(radius*sin(angle),5,radius*cos(angle))

func sorted_enemy_list(ship, system: Spatial,max_age: int = default_max_age) -> Array:
	if tick-tick_at_last_list > max_age:
		cached_sorted_enemy_list=system.sorted_enemy_list(ship.translation,ship.enemy)
		tick_at_last_list=tick
	return cached_sorted_enemy_list

func clear_data():
	got_near_objects=false
	near_objects=[]

func apply_ship_transform(scale: Vector3, origin: Vector3, ship) -> Transform:
	var u = Transform()
	var st = ship.translation
	u = u.scaled(scale).translated(origin/scale).rotated(Vector3(0,1,0),ship.rotation[1])
	u.origin += Vector3(st.x,0,st.y)
	return u

func make_threat_vector(ship,t: float):
	threat_vector = ship_tool.make_threat_vector(ship,near_objects,shape_radius,t)

func _init():
	near_shape = CylinderShape.new()
	near_shape.radius = shape_radius
	near_shape.height = 10

func _ready():
	randomize_destination()

func get_collisions(space: PhysicsDirectSpaceState, _state: PhysicsDirectBodyState, ship):
	if not got_near_objects:
		var query = PhysicsShapeQueryParameters.new()
		query.collision_mask = ship.enemy_mask
		query.transform = ship.transform
		query.set_shape(near_shape)
		near_objects = space.intersect_shape(query) # (query,state.linear_velocity)
		got_near_objects=true
	return near_objects

func pick_nearest_target(_space: PhysicsDirectSpaceState,
		_state: PhysicsDirectBodyState, ship, system: Spatial):
	var target_object = null
	for dist_path in sorted_enemy_list(ship,system):
		target_object=ship.get_node_or_null(dist_path[1])
		if target_object!=null:
			target_path=dist_path[1]
	
	return target_object

func fight(state: PhysicsDirectBodyState, ship, system: Spatial) -> bool:
	var space: PhysicsDirectSpaceState = state.get_space_state()
	var target = pick_nearest_target(space,state,ship,system)
	if target == null:
		return false
	ship_tool.request_move_to_attack(ship,state,target)
	return true

func evade(state: PhysicsDirectBodyState, ship, _system: Spatial) -> void:
	var threat_level: float = threat_vector.length()
	#var norm_vector: Vector3 = threat_vector.normalized()
	var react_vector: Vector3 = -threat_vector.normalized()
	
	if threat_level < threat_threshold:
		var tock: float = tick%240-120
		react_vector = react_vector.rotated(Vector3(0,1,0),PI/4.0 * exp(-tock*tock/40))
	
	ship_tool.request_heading(ship,state,react_vector.normalized())
	var forward: bool = react_vector.dot(ship.get_heading()) > 0
	ship_tool.request_thrust(ship,state,forward,!forward)

func coward_ai(state: PhysicsDirectBodyState, ship, system: Spatial):
	var _discard = get_collisions(state.get_space_state(),state,ship)
	make_threat_vector(ship,0.5)
	if threat_vector.length() > threat_threshold:
		evade(state,ship,system)
	else:
		# When there are no threats, fly away from system center
		var pos = ship.get_position()
		var pos_norm = pos.normalized()
		if pos_norm.length()<0.99:
			pos_norm = Vector3(1,0,0)
		ship_tool.move_to_intercept(ship, state, 1,
			999, pos_norm * max(100,pos.length()*2+10),
			ship.max_speed * pos_norm, false, false)

func patrol_ai(state: PhysicsDirectBodyState, ship, _system: Spatial):
	if ship.translation.distance_to(destination)<10:
		randomize_destination()
	else:
		ship_tool.move_to_intercept(ship, state, 5,
			1, destination, Vector3(0,0,0), false, false)

func attacker_ai(state: PhysicsDirectBodyState, ship, system: Spatial):
	var target = null

	if not target_path.is_empty():
		target = ship.get_node_or_null(target_path)
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
		ship_tool.request_move_to_attack(ship,state,target)
	else:
		target_path = NodePath()
		if not fight(state,ship,system):
			patrol_ai(state,ship,system)
	if ship.ai_shoot:
		tick_at_last_shot=tick

func landing_ai(state: PhysicsDirectBodyState, ship, system: Spatial):
	make_threat_vector(ship,0.5)
	if threat_vector.length()>0:
		evade(state,ship,system)
	else:
		var target = null
		if not target_path.is_empty():
			target = ship.get_node_or_null(target_path)
		if target == null:
			target_path = system.next_planet(target_path)
			target = ship.get_node_or_null(target_path)
		if target == null:
			# Nowhere to land!
			patrol_ai(state,ship,system)
		else:
			ship_tool.move_to_intercept(ship, state, target.get_radius(),
				0.1, target.translation, Vector3(0,0,0), false, false)

func ai_step(state: PhysicsDirectBodyState, ship, system: Spatial) -> void:
	if ship.shields<=0 and ship.hull<=0 and ship.structure<0.5*ship.max_structure:
		coward_ai(state,ship,system)
	else:
		attacker_ai(state,ship,system)
	clear_data()
	tick += 1
