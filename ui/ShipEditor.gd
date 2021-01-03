extends Spatial

const InventorySlot: Script = preload('res://ui/InventorySlot.gd')

const ships = {
	'condor': preload('res://ships/PurpleShips/HeavyWarshipHull.tscn'),
	'raven': preload('res://ships/PurpleShips/WarshipHull.tscn'),
	'peregrine': preload('res://ships/PurpleShips/InterceptorHull.tscn'),
}

const guns = {
	'df_laser': preload('res://weapons/BlueLaserGun.tscn'),
	'gamma_ray_laser': preload('res://weapons/GreenLaserGun.tscn'),
	'cyclotron_cannon': preload('res://weapons/OrangeSpikeGun.tscn'),
	'shockwave_torpedo': preload('res://weapons/PurpleHomingGun.tscn'),
}

const turrets = {
	'linear_accelerator_turret': preload('res://weapons/OrangeSpikeTurret.tscn'),
	'df_laser_turret': preload('res://weapons/BlueLaserTurret.tscn'),
}

const x_axis: Vector3 = Vector3(1,0,0)
const y_axis: Vector3 = Vector3(0,1,0)

var ship_aabb: AABB = AABB()
var mounts: Dictionary = {}
var used_width: float = 0
var selected: bool = false
#var selected_scene = null
var scene_for_item: Dictionary = {}

const SHIP_LAYER_MASK: int = 1
const INSTALLED_LAYER_MASK: int = 2
const MOUNT_POINT_LAYER_MASK: int = 4
const AVAILABLE_LAYER_MASK: int = 8
const RED_LIGHT_CULL_LAYER: int = 8

func mount_point(width: int,height: int,loc: Vector3,box_name: String) -> Area:
	var box: Area = Area.new()
	box.set_script(InventorySlot)
	box.create_only_box(box_name,width,height)
	box.place_near(loc,get_viewport().world.direct_space_state)
	box.name=box_name
	box.collision_layer = MOUNT_POINT_LAYER_MASK
	$MountPoints.add_child(box)
	return box

func copy_to_installed(installed_name: String,child: Node,display_location: Vector3) -> NodePath:
	var area = child.copy_only_item()
	area.collision_layer = INSTALLED_LAYER_MASK
	area.translation = Vector3(display_location.x,13,display_location.z)
	area.name = installed_name
	$Installed.add_child(area)
	area.name = installed_name
	return area.get_path()

func make_ship(design: Dictionary):
	var scene: PackedScene = design['hull']
	var ship = scene.instance()
	ship.name='Ship'
	ship.collision_layer = SHIP_LAYER_MASK
	ship.collision_mask = 0
	add_child(ship)
	for child in $Ship.get_children():
		if child.get('mount_type')!=null:
			var loc: Vector3 = child.translation
			var nx: int = child.mount_size_x
			var ny: int = child.mount_size_y
			loc.y=10
			var mp: Area = mount_point(nx,ny,loc,child.name)
			mounts[child.name]={'name':child.name, 'transform':child.transform, 
				'mount_type':child.mount_type,'scene':'','content':NodePath(),
				'box':mp.get_path(),'nx':nx,'ny':ny,'box_translation':mp.translation
			}
	for mount_name in design:
		if mounts.has(mount_name):
			var area: Area = Area.new()
			area.set_script(InventorySlot)
			var instanced_mount: Node = design[mount_name].instance()
			area.create_item(mount_name,design[mount_name],instanced_mount.help_page,false)
			instanced_mount.queue_free()
			if not try_to_mount(area,mount_name):
				area.queue_free()
		elif mount_name!='hull':
			printerr('ShipEditor: mount "',mount_name,'" does not exist.')
	return ship

func combined_aabb(node: Node):
	var result: AABB = AABB()
	if node is VisualInstance:
		result = node.get_aabb()
	for child in node.get_children():
		result=result.merge(combined_aabb(child))
	if node is Spatial:
		result = node.transform.xform(result)
	return result

func add_available_item(scene: PackedScene,item_name: String):
	var area: Area = Area.new()
	area.set_script(InventorySlot)
	area.create_item(item_name,scene,'weapons/'+item_name,true)
	area.collision_layer = AVAILABLE_LAYER_MASK
	var width: float = max(2,area.nx+1)*0.25
	area.translation.z = width/2.0+used_width
	area.translation.x = (3.0-area.ny)/8.0
	used_width += width
	area.name = item_name
	$Available.add_child(area)
	scene_for_item[item_name]=scene

func move_Camera_for_scene():
	$Camera.size = max(8,max(abs(ship_aabb.size.x),abs(ship_aabb.size.z))+2)
	var pos = ship_aabb.position + ship_aabb.size*0.5
	$Camera.translation.x = pos.x-0.8
	$Camera.translation.z = pos.z

func move_Available_for_scene():
	var scene_size = $Camera.size
	$Available.translation.x = -scene_size/2.0 + 0.5
	$Available.translation.z = -used_width/2.0

func try_to_mount(area: Area, mount_name: String):
	if not mounts.has(mount_name):
		printerr('mount failed: no mount ',mount_name)
		return false
	var mount: Dictionary = mounts[mount_name]
	if not area.scene:
		printerr('mount failed: no scene in mount ',mount_name)
		return false
	if area.nx>mount['nx']:
		printerr('mount failed: x size too small (',area.nx,'>',mount['nx'],' in ',mount_name)
		return false
	if area.ny>mount['ny']:
		printerr('mount failed: y size too small (',area.ny,'>',mount['ny'],' in ',mount_name)
		return false
	var content = get_node_or_null(mount['content'])
	if content!=null:
		content.queue_free()
	mounts[mount_name]['content'] = copy_to_installed(mount['name'],area,mount['box_translation'])
	mounts[mount_name]['scene'] = area.scene
	var install = area.scene.instance()
	install.transform = mount['transform']
	install.name = mount['name']
	install.mount_size_x = mount['nx']
	install.mount_size_y = mount['ny']

	var child = $Ship.get_node_or_null(mount['name'])
	if child!=null:
		child.replace_by(install)
	else:
		$Ship.add_child(install)
	install.owner=$Ship
	install.name = mount['name']
	return true

func deselect(there: Dictionary):
	var area: Area = get_node_or_null('Selected')
	if area!=null:
		if there.has('collider'):
			var target: CollisionObject = there['collider']
			try_to_mount(area,target.name)
		area.queue_free()
	selected=false
	update_coloring(0,0,'')

func update_coloring(nx: int,ny: int,type: String):
	for mount_info in mounts.values():
		var box_area = get_node_or_null(mount_info['box'])
		if box_area==null:
			continue
		if type and (type != mount_info['mount_type'] or nx>mount_info['nx'] or ny>mount_info['ny']):
			for child in box_area.get_children():
				if child is VisualInstance:
					child.layers = child.layers | RED_LIGHT_CULL_LAYER
		else:
			for child in box_area.get_children():
				if child is VisualInstance:
					child.layers = child.layers & ~RED_LIGHT_CULL_LAYER

func select_collider(pos: Vector2, collider: Area):
	var dup: CollisionObject = collider.copy_only_item()
	var pos3: Vector3 = $Camera.project_position(pos,-10)
	dup.translation = Vector3(pos3.x,16,pos3.z)
	dup.name = 'Selected'
	add_child(dup)
	selected=true
	$ConsolePanel.process_command('help '+dup.page)
	var item = collider.get_node_or_null('item')
	update_coloring(item.mount_size_x,item.mount_size_y,
		'' if item==null else item.mount_type)

func select_installed(pos: Vector2, there: Dictionary):
	var collider = there['collider']
	if there!=null:
		select_collider(pos,collider)
		
		# Unmount the item from the ship
		var path = collider.get_path()
		for mount_name in mounts:
			var mount: Dictionary = mounts[mount_name]
			if mount['content'] == path:
				var child = $Ship.get_node_or_null(mount_name)
				if child!=null:
					$Ship.remove_child(child)
					child.queue_free()
				mount['scene'] = ''
				mount['content'] = NodePath()

		# Unmount the item from $Installed
		$Installed.remove_child(collider)
		collider.queue_free()

func select_available(pos: Vector2, there: Dictionary):
	var collider = there['collider']
	if collider!=null:
		select_collider(pos,collider)

func event_position(event: InputEvent):
	if event is InputEventMouseButton:
		return event.position
	return get_viewport().get_mouse_position()

func at_position(pos,mask: int):
	if pos==null:
		return {}
	var space: PhysicsDirectSpaceState = get_viewport().world.direct_space_state
	var from = $Camera.project_ray_origin(pos)
	from.y = $Camera.translation.y+500
	var to = from + $Camera.project_ray_normal(pos)
	to.y = $Camera.translation.y-500
	return space.intersect_ray(from,to,[],mask,true,true)

func _input(event: InputEvent):
	if event.is_action_released('ui_location_select'):
		if selected:
			var there = at_position(event_position(event),4)
			deselect(there)
	elif event.is_action_pressed('ui_location_select'):
		var pos = event_position(event)
		if pos!=null:
			var there = at_position(pos,AVAILABLE_LAYER_MASK)
			if there!=null and not there.empty():
				select_available(pos,there)
			there = at_position(pos,INSTALLED_LAYER_MASK)
			if there!=null and not there.empty():
				select_installed(pos,there)
	elif event.is_action_released('ui_cancel'):
		var design: Dictionary = {'hull':game_state.player_ship_design['hull']}
		for mount_name in mounts:
			if mounts[mount_name]['scene']:
				design[mount_name] = mounts[mount_name]['scene']
		game_state.player_ship_design = design
		var _discard = get_tree().change_scene('res://ui/OrbitalScreen.tscn')
	elif selected:
		var n = get_node_or_null('Selected')
		if n!=null:
			var pos2 = event_position(event)
			if pos2!=null:
				var pos3 = $Camera.project_position(pos2,-10)
				n.translation = Vector3(pos3.x,16,pos3.z)

func force_child_size(c: Control,size: Vector2,pos: Vector2):
	c.anchor_left=0
	c.anchor_right=0
	c.anchor_top=0
	c.anchor_bottom=0
	
	c.margin_left=0
	c.margin_right=0
	c.margin_top=0
	c.margin_bottom=0
	
	c.size_flags_horizontal=0
	c.size_flags_vertical=0
	
	c.rect_global_position=pos
	c.rect_size=size

func child_fills_parent(c: Control):
	c.anchor_left=0
	c.anchor_right=1
	c.anchor_top=0
	c.anchor_bottom=1
	
	c.margin_left=0
	c.margin_right=0
	c.margin_top=0
	c.margin_bottom=0
	
	c.size_flags_horizontal=Control.SIZE_FILL|Control.SIZE_EXPAND
	c.size_flags_vertical=Control.SIZE_FILL|Control.SIZE_EXPAND

func _ready():
	$Red.layers = RED_LIGHT_CULL_LAYER
	$Red.light_cull_mask = RED_LIGHT_CULL_LAYER
	$SpaceBackground.center_view(130,90,0,120,0)
	ship_aabb = combined_aabb(make_ship(game_state.player_ship_design))
	ship_aabb = ship_aabb.merge(combined_aabb($MountPoints))
	move_Camera_for_scene()
	var _discard
	for gun_name in guns.keys():
		_discard=add_available_item(guns[gun_name],gun_name)
	for turret_name in turrets.keys():
		_discard=add_available_item(turrets[turret_name],turret_name)
	move_Available_for_scene()

func _process(_delta):
	var view_size: Vector2 = get_viewport().get_size()
	var pos3_ul: Vector3 = $Camera.project_position(Vector2(0,0),-10)
	var pos3_lr: Vector3 = $Camera.project_position(view_size,-10)
	$Camera.translation.z = abs(pos3_ul.z-pos3_lr.z)/6
	$ConsolePanel.rect_global_position=Vector2(view_size.x*2.0/3.0,0)
	$ConsolePanel.rect_size=Vector2(view_size.x/3.0,view_size.y*0.6)
	$ShipInfo.rect_global_position=Vector2(view_size.x*2.0/3.0,view_size.y*0.6)
	$ShipInfo.rect_size=Vector2(view_size.x/3.0,view_size.y*0.4)
