extends Spatial

const WideShip = preload('res://WideShip.tscn')
const Planet = preload('res://Planet.tscn')
const ShipAI = preload('res://ShipAI.gd')
const ShipPlayerAI = preload('res://ShipPlayerAI.gd')
const TargetDisplay = preload('res://TargetDisplay.tscn')

# Note: cyclic dependency Landing->Main->Player->Landing
var Landing = preload('res://Landing.tscn')

var target_change_mutex: Mutex = Mutex.new()
var player_target_path: NodePath
var new_target_path: NodePath
var ui_zoom: float = 0
var ui_scroll: float = 0
var shot_counter: int = 0
var tick: int = 0
var solar_system: Array = []
var player_ship: RigidBody

signal place_minimap
signal fill_minimap
signal player_hp_changed
signal player_target_deselect

func get_main_camera():
	return $TopCamera

func clear():
	for proj in $Projectiles.get_children():
		proj.queue_free()
	for ship in $Ships.get_children():
		if ship.get_instance_id() != player_ship.get_instance_id():
			ship.queue_free()
	for planet in $Planets.get_children():
		planet.queue_free()

func update_minimap():
	var planets=[]
	var ships=[]
	var projectiles=[]
	var target_path: NodePath = player_ship.ai.get_target_path()
	var target
	var target_id
	if not target_path.is_empty():
		target = get_node_or_null(target_path)
		if target != null:
			target_id = target.get_instance_id()
	for planet in $Planets.get_children():
		var where = planet.translation
		planets.append({
			'location':Vector2(where.z,-where.x),
			'scale':planet.sphere.scale[0],
			"target":planet.get_instance_id()==target_id,
			'type':'planet'
		})
	var player_ship_id = player_ship.get_instance_id()
	for ship in $Ships.get_children():
		if not ship.is_alive():
			continue
		var ship_id = ship.get_instance_id()
		var info = {
			'location':ship.minimap_location,
			'scale':2,
			'friendly':ship.team==0,
			'hostile':ship.enemy==0,
			'target':ship_id==target_id,
			'type':'ship',
			'player':ship_id==player_ship_id,
		}
		if info['target'] or info['player']:
			info['heading'] = ship.minimap_heading
			info['velocity'] = ship.minimap_velocity
		ships.append(info)
	for proj in $Projectiles.get_children():
		var where = proj.translation
		projectiles.append({
			'location':Vector2(where.z,-where.x),
			'scale':1,
			'type':'projectile'
		})
	emit_signal('fill_minimap',planets,ships,projectiles,
		player_ship.minimap_velocity,player_ship.minimap_heading)

func land_player():
	var _discard=get_tree().change_scene('res://Landing.tscn')

func emit_player_hp_changed(var ship):
	emit_signal('player_hp_changed',ship)

func add_projectile(var proj: Node):
	$Projectiles.add_child(proj)

func next_planet(var last_target: NodePath) -> NodePath:
	return next_target(last_target,$Planets,null)

func nearest_planet(var last_target: NodePath, var rel: Vector3) -> NodePath:
	return nearest_target(last_target,$Planets,null,rel)

func nearest_enemy(var last_target: NodePath, var rel: Vector3, var target_team) -> NodePath:
	return nearest_target(last_target,$Ships,target_team,rel)

func next_enemy(var last_target: NodePath, var target_team) -> NodePath:
	return next_target(last_target,$Ships,target_team)

class CmpBy0:
	static func cmp_by_0(a,b) -> bool:
		return a[0]<b[0]

func sorted_enemy_list(where: Vector3,enemy_team: int) -> Array:
	var pos: Vector3 = Vector3(where.x,0,where.y)
	var list: Array = []
	for child in $Ships.get_children():
		if child.team == enemy_team:
			list.append([pos.distance_to(child.get_position()),child.get_path()])
	list.sort_custom(CmpBy0,'cmp_by_0')
	return list

func nearest_target(var last_target: NodePath, var list: Node,
		var target_team, var rel: Vector3) -> NodePath:
	#var enemy_team: int = ship.enemy
	var target_path = last_target
	var target_dist = 9e9
	var rel2 = Vector2(rel[2],-rel[0])
	for node in list.get_children():
		if last_target!=null and node.get_path() == last_target:
			continue
		if target_team != null and node.team != target_team:
			continue
		var loc2 = Vector2(node.translation[2],-node.translation[0])
		var dist = (loc2-rel2).length()
		if dist<target_dist:
			target_path = node.get_path()
			target_dist = dist
	return target_path

func next_target(var last_target: NodePath, var list: Node,
		var target_team) -> NodePath:
	#var enemy_team: int = ship.enemy
	var last_found: bool = false
	var first_found: bool = false
	var first_target: NodePath
	for node in list.get_children():
		var is_last: bool = false
		if node.get_path() == last_target:
			last_found = true
			is_last = true
		if target_team != null and node.team != target_team:
			continue
		if last_found and not is_last:
			return node.get_path()
		if not first_found:
			first_target = node.get_path()
			first_found = true
	# No next target. Two possibilities:
	# 1. There was only one target. If so, no target is returned (empty path)
	# 2. There were at least two targets. We hit the end of the list of targets,
	#    so we send the first target.
	return first_target

func disconnect_target_info():
	player_target_path=NodePath()

func player_target_changed(target_path: NodePath):
	new_target_path=target_path

func update_target_display():
	var target_path=new_target_path
	if target_path.is_empty():
		return
	new_target_path=NodePath()
	target_change_mutex.lock()
	emit_signal('player_target_deselect',self)
	var target=get_node_or_null(target_path)
	if target==null:
		player_target_path=NodePath()
	player_target_path=target_path
	var info = TargetDisplay.instance()
	var _discard=self.connect('player_target_deselect',info,'player_target_deselect')
	target.add_child(info)
	target_change_mutex.unlock()

func spawn_ship(var ship,var _is_player: bool = false):
	var _discard
	ship.connect('shoot',self,'add_projectile')
	_discard = ship.connect('die',self,'ship_died',[ship])
	_discard = ship.connect('ai_step',ship.ai,'ai_step',[ship,self])
	ship.can_sleep=false
	$Ships.add_child(ship)

func spawn_planet(var planet):
	$Planets.add_child(planet)

func make_player_ship():
	var _discard
	var ship=WideShip.instance()
	ship.name='player'
	ship.translation[1]=5
	ship.set_team(0)
	ship.set_max_hp(4000,8000,12000)
	ship.fully_heal()
	ship.ai=ShipPlayerAI.new()
	_discard = ship.connect('hp_changed',self,'emit_player_hp_changed')
	_discard = ship.ai.connect('land',self,'land_player')
	_discard = ship.ai.connect('target_changed',self,'player_target_changed')
	spawn_ship(ship)
	return ship

func init_system():
	clear()
	game_state.system.fill_system(self,999,60,50)
	player_ship=make_player_ship()
	var planet_info = game_state.get_planet_info_or_null()
	var node_name = '' if planet_info==null else planet_info.make_unique_name()
	var planet: Spatial = $Planets.get_node_or_null(node_name)
	if planet!=null:
		player_ship.translation.x = planet.translation.x
		player_ship.translation.z = planet.translation.z
	$TopCamera.size=30
	$TopCamera.translation=Vector3(player_ship.translation.x,10,player_ship.translation.z)

func _ready() -> void:
	init_system()

func set_zoom(zoom: float,ratio: float=-1) -> float:
	if ratio<1:
		ratio=$TopCamera.size
	ratio = max(25,min(150,ratio*zoom))
	$TopCamera.size = ratio
	return ratio

func ship_count_by_team(team: int):
	var count=0
	for ship in $Ships.get_children():
		if team==ship.team:
			count+=1
	return count

func ship_died(_damage: int, ship: Node):
	if player_ship != null and \
			ship.get_instance_id() == player_ship.get_instance_id():
		game_state.print_to_console('YOU DIED!  8-(')
		player_ship.visible = false
		player_ship.collision_layer = 0
		player_ship.collision_mask = 0
		player_ship.linear_velocity = Vector3(0,0,0)
		player_ship.ai.alive = false
	else:
		ship.queue_free()

func center_view() -> void:
	var x: float = player_ship.translation.x
	var z: float = player_ship.translation.z
	$TopCamera.translation.x = x
	$TopCamera.translation.z = z
	$SpaceBackground.center_view(x,z,$TopCamera.size)
	emit_signal('place_minimap',Vector2(z,-x),300)

func _process(delta):
	game_state.system.process_space(self,delta)
	update_target_display()
	ui_zoom = Input.get_action_strength("ui_page_up")-Input.get_action_strength("ui_page_down")
	if Input.is_action_just_released("wheel_up"):
		ui_scroll=3
	if Input.is_action_just_released("wheel_down"):
		ui_scroll=-3
	center_view()
	var zoom = pow(0.9,ui_zoom)*pow(0.9,ui_scroll)
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0
	var _zoom_level = set_zoom(zoom)
	tick = tick+1
	update_minimap()
