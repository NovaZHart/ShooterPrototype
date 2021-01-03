extends Spatial

const border_all: Mesh = preload('res://ui/OutfitBorders/1x1.mesh')
const border_tube_bottom: Mesh = preload('res://ui/OutfitBorders/1x1-U.mesh')
const border_tube_middle: Mesh = preload('res://ui/OutfitBorders/1x1-UD.mesh')
const border_middle: Mesh = preload('res://ui/OutfitBorders/1x1-UDLR.mesh')
const border_left: Mesh = preload('res://ui/OutfitBorders/1x1-UDR.mesh')
const border_lower_left: Mesh = preload('res://ui/OutfitBorders/1x1-UR.mesh')

const RIGHT: int = 1
const LEFT: int = 2
const DOWN: int = 4
const UP: int = 8

var ship_scene
var scroll_width: float = 20

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

const outfit_borders = [	       # U D L R
	[   0.0, border_all ],         # 0 0 0 0
	[ 270.0, border_tube_bottom ], # 0 0 0 1
	[  90.0, border_tube_bottom ], # 0 0 1 0
	[  90.0, border_tube_middle ], # 0 0 1 1
	[ 180.0, border_tube_bottom ], # 0 1 0 0
	[ 270.0, border_lower_left  ], # 0 1 0 1
	[ 180.0, border_lower_left  ], # 0 1 1 0
	[ 270.0, border_left        ], # 0 1 1 1
	[   0.0, border_tube_bottom ], # 1 0 0 0
	[   0.0, border_lower_left  ], # 1 0 0 1
	[  90.0, border_lower_left  ], # 1 0 1 0
	[  90.0, border_left        ], # 1 0 1 1
	[   0.0, border_tube_middle ], # 1 1 0 0
	[   0.0, border_left        ], # 1 1 0 1
	[ 180.0, border_left        ], # 1 1 1 0
	[ 180.0, border_middle      ], # 1 1 1 1
]

var ship_aabb: AABB = AABB()
var mounts: Dictionary = {}
var used_width: float = 0
var selected: bool = false
var selected_scene = null
var scene_for_item: Dictionary = {}

func make_area_for_item(item: Spatial,mask: int) -> Area:
	var area: Area = Area.new()
	var shape: BoxShape = BoxShape.new()
	shape.extents = Vector3(item.mount_size_y/8.0,1,item.mount_size_x/8.0)
	var cshape: CollisionShape = CollisionShape.new()
	cshape.shape = shape
	cshape.name = 'collision'
	area.add_child(cshape)
	area.collision_layer = mask
	area.collision_mask = 0
	item.name='item'
	item.transform = Transform()
	if item.mount_type=='gun':
		item.translation.x = (item.mount_size_y-1.0)/8.0
	area.add_child(item)
	return area

func make_box(width: int,height: int,box_scale: float,parent_area: bool=true) -> Spatial:
	var box: Spatial
	if parent_area:
		box = Area.new()
		box.collision_layer=16
		var shape: CollisionShape = CollisionShape.new()
		shape.shape = BoxShape.new()
		shape.shape.extents = Vector3(height*box_scale,10,width*box_scale)
		shape.name='shape'
		box.add_child(shape)
	else:
		box=Spatial.new()
	
	for j in range(height):
		for i in range(width):
			var border: int = 0
			if i>0: border += LEFT
			if i<width-1: border += RIGHT
			if j>0: border += UP
			if j<height-1: border += DOWN
			var instance: MeshInstance = MeshInstance.new()
			instance.rotation = Vector3(0,PI/180*outfit_borders[border][0],0)
			instance.mesh = outfit_borders[border][1]
			instance.translation = Vector3(
				- 2*(j-float(height)/2+0.5)*box_scale, 0, 2*(i-float(width)/2+0.5)*box_scale)
			instance.name = 'cell_'+str(i)+'_'+str(j)
			instance.scale = Vector3(box_scale,box_scale,box_scale)
			instance.layers = 2
			box.add_child(instance)
	return box

func place_box(box: Area, mount: Vector3) -> Area:
	var space: PhysicsDirectSpaceState = get_viewport().world.direct_space_state
	var badness: float = INF
	var loc: Vector3 = mount
	var angles: Array
	if mount.z>0:
		angles = [ 0,2.5,-2.5,5,-5,10,-10,15,-15,25,-25,40,-40,60,-60,80,-80 ]
	else:
		angles = [ 0,-2.5,2.5,-5,5,-10,10,-15,15,-25,25,-40,40,-60,60,-80,80 ]
	var radii: Array = [ .1, .2, .3, .5, .8, 1.3, 2.1, 3.4, 5.5, 8.9 ]
	var shape: Shape = box.get_node('shape').shape
	var query: PhysicsShapeQueryParameters = PhysicsShapeQueryParameters.new()
	query.margin=0.25
	query.collide_with_areas=true
	query.shape_rid=shape.get_rid()
	query.exclude = [box.get_rid()]
	var unit: Vector3 = Vector3(mount.x,0,mount.z).normalized()
	if unit.length()<0.99: # mount was precisely at the origin
		unit=x_axis
	for angle in angles:
		for radius in radii:
			var trans: Vector3 = mount + unit.rotated(y_axis,angle*PI/180)*radius
			query.transform.origin=trans
			var result: Dictionary = space.get_rest_info(query)
			if result.empty():
				trans[1]=0
				var bad: float = Vector3(trans.x,0,trans.z).length()*(1+abs(sin(angle*PI/180)))
				if bad<badness:
					badness=bad
					loc=trans
	box.translation=Vector3(loc.x,0,loc.z)
	return box

func mount_point(width: int,height: int,loc: Vector3,box_scale: float,box_name: String) -> Area:
	var box: Area = place_box(make_box(width,height,box_scale,true),loc)
	box.name=box_name
	box.collision_layer = 4
	box.collision_mask = 0
	$MountPoints.add_child(box)
	return box

func copy_to_installed(installed_name: String,child: Node,display_location: Vector3) -> NodePath:
	if child.has_method('add_stats'):
		var item = child.duplicate()
		var area = make_area_for_item(item,2)
		area.translation = Vector3(display_location.x,13,display_location.z)
		area.name = installed_name
		$Installed.add_child(area)
		return area.get_path()
	return NodePath()

func make_ship(scene: PackedScene):
	var ship = scene.instance()
	ship.name='Ship'
	add_child(ship)
	for child in $Ship.get_children():
		if child.get('mount_type')!=null:
			var loc: Vector3 = child.translation
			var nx: int = child.mount_size_x
			var ny: int = child.mount_size_y
			loc.y=10
			var mp: Area = mount_point(nx,ny,loc,0.135,child.name)
			mounts[child.name]={'name':child.name, 'transform':child.transform, 
				'mount_type':child.mount_type,'scene':'',
				'content':copy_to_installed(child.name,child,mp.translation),
				'box':mp.get_path(),'nx':nx,'ny':ny,'box_translation':mp.translation
			}
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
	var item: Node = scene.instance()
	var area: Area = make_area_for_item(item,8)
	var width: float = max(2,item.mount_size_x+1)*0.25
	var box: Spatial = make_box(item.mount_size_x,item.mount_size_y,0.135,false)
	area.translation.z = width/2.0+used_width
	area.translation.x = (3.0-item.mount_size_y)/8.0
	box.translation.z = width/2.0+used_width
	box.translation.x = (3.0-item.mount_size_y)/8.0
	used_width += width
	area.name = item_name
	box.name = 'box_for_'+item_name
	$Available.add_child(area)
	$Available.add_child(box)
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
		return false
	var mount: Dictionary = mounts[mount_name]
	var item = area.get_node_or_null('item')
	if item==null:
		return false
	if item.mount_type!=mount['mount_type'] or item.mount_size_x>mount['nx'] \
			or item.mount_size_y>mount['ny']:
		return false
	var content = get_node_or_null(mount['content'])
	if content!=null:
		content.queue_free()
	mounts[mount_name]['content'] = copy_to_installed(mount['name'],item,mount['box_translation'])
	mounts[mount_name]['scene'] = selected_scene
	var child = $Ship.get_node_or_null(mount['name'])
	if child!=null:
		$Ship.remove_child(child)
		child.queue_free()
	var install = selected_scene.instance()
	install.transform = mount['transform']
	install.name = mount['name']
	install.mount_size_x = mount['nx']
	install.mount_size_y = mount['ny']
	$Ship.add_child(install)
	install.owner=$Ship

func deselect(there: Dictionary):
	var area: Area = get_node_or_null('Selected')
	if area!=null:
		if there.has('collider'):
			var target: CollisionObject = there['collider']
			try_to_mount(area,target.name)
		area.queue_free()
	selected=false
	selected_scene=''
	update_coloring(0,0,'')

func update_coloring(nx: int,ny: int,type: String):
	for mount_info in mounts.values():
		var box_area = get_node_or_null(mount_info['box'])
		if box_area==null:
			continue
		if type and (type != mount_info['mount_type'] or nx>mount_info['nx'] or ny>mount_info['ny']):
			for child in box_area.get_children():
				if child is VisualInstance:
					child.layers = child.layers | 8
		else:
			for child in box_area.get_children():
				if child is VisualInstance:
					child.layers = child.layers & ~8

func select_available(pos: Vector2, there: Dictionary):
	var collider = there['collider']
	if collider!=null:
		var dup: CollisionObject = collider.duplicate()
		var pos3: Vector3 = $Camera.project_position(pos,-10)
		dup.translation = Vector3(pos3.x,16,pos3.z)
		dup.name = 'Selected'
		add_child(dup)
		selected=true
		selected_scene = scene_for_item[collider.name]
		$ConsolePanel.process_command('help weapons/'+collider.name)
		var item = collider.get_node_or_null('item')
		update_coloring(item.mount_size_x,item.mount_size_y,
			'' if item==null else item.mount_type)

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
			var there = at_position(pos,8)
			if there!=null and not there.empty():
				select_available(pos,there)
	elif event.is_action_released('ui_cancel'):
		var packed: PackedScene = PackedScene.new()
		if OK==packed.pack($Ship):
			game_state.player_ship_scene=packed
		else:
			printerr('Failed to pack player ship!!')
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
	ship_scene = game_state.player_ship_scene
	$SpaceBackground.center_view(130,90,0,100,0)
	ship_aabb = combined_aabb(make_ship(ship_scene))
	ship_aabb = ship_aabb.merge(combined_aabb($MountPoints))
	move_Camera_for_scene()
	var _discard
	for gun_name in guns.keys():
		_discard=add_available_item(guns[gun_name],gun_name)
	for turret_name in turrets.keys():
		_discard=add_available_item(turrets[turret_name],turret_name)
	move_Available_for_scene()
	
	var n = $ConsolePanel/Console/Output.get_child(0)
	if n!=null:
		scroll_width = 12
		$ConsolePanel/Console/Output.remove_child(n)
		var view_size: Vector2 = get_viewport().get_size()
		n.name='ConsoleScrollbar'
		$ScrollPanel.add_child(n)
		force_child_size($ScrollPanel,Vector2(scroll_width,view_size.y),Vector2(0,0))
		child_fills_parent(n)

func _process(_delta):
	var view_size: Vector2 = get_viewport().get_size()
	var pos3_ul: Vector3 = $Camera.project_position(Vector2(0,0),-10)
	var pos3_lr: Vector3 = $Camera.project_position(view_size,-10)
	$Camera.translation.z = -abs(pos3_ul.z-pos3_lr.z)/6
	force_child_size($ScrollPanel,Vector2(scroll_width,view_size.y),Vector2(0,0))
	$ConsolePanel.rect_global_position=Vector2(scroll_width,0)
	$ConsolePanel.rect_size=Vector2(view_size.x/3.0-scroll_width,view_size.y)
