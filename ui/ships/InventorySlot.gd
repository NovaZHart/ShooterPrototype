extends Area

var scene: PackedScene

# From item_size_x, item_size_y, page, mount_flags of *Stats.gd:
var nx: int = 2
var ny: int = 2
var page: String = 'weapons'
var mount_flags: int = 0
var mount_flags_all: int = 0
var mount_flags_any: int = 0
var mount_name: String = '' setget ,get_mount_name

# x,y location within an InventoryArray
var my_x: int = -1
var my_y: int = -1

const border_all: Mesh = preload('res://ui/OutfitBorders/1x1.mesh')
const border_tube_bottom: Mesh = preload('res://ui/OutfitBorders/1x1-U.mesh')
const border_tube_middle: Mesh = preload('res://ui/OutfitBorders/1x1-UD.mesh')
const border_middle: Mesh = preload('res://ui/OutfitBorders/1x1-UDLR.mesh')
const border_left: Mesh = preload('res://ui/OutfitBorders/1x1-UDR.mesh')
const border_lower_left: Mesh = preload('res://ui/OutfitBorders/1x1-UR.mesh')

const RED_LIGHT_LAYER_MASK = 8
const WHITE_LIGHT_LAYER_MASK = 16
const LIGHT_LAYER_MASK = RED_LIGHT_LAYER_MASK|WHITE_LIGHT_LAYER_MASK

const RIGHT: int = 1
const LEFT: int = 2
const DOWN: int = 4
const UP: int = 8

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

# Inventory grid boxes are slightly larger than items:
const box_scale: float = 0.135
const item_scale: float = 0.125

func get_mount_name() -> String:
	return mount_name if mount_name else name

func is_InventorySlot(): pass # used for type checking; never called

func is_inventory_slot(): # never called; must only exist. FIXME: DELETE THIS
	pass

func has_item() -> bool:
	return get_node_or_null('InventorySlotItem')!=null

func color(mask: int):
	for j in range(ny):
		for i in range(nx):
			var child = get_node_or_null("InventorySlotBox_x"+str(i)+"_y"+str(j))
			assert(child)
			if child!=null:
				child.layers = child.layers&~LIGHT_LAYER_MASK | mask

func update_coloring(pos,item):
	if my_x>0:
		var parent=get_parent()
		if parent:
			parent.update_coloring(pos,item)
	else:
		var mask: int = 0
		# special case: no type means deselect
		if item and (item.item_size_x>nx or item.item_size_y>ny or \
				not utils.can_mount(mount_flags,item)):
			mask |= RED_LIGHT_LAYER_MASK
		elif pos!=null:
			var pos3_half_x: float = ny*box_scale
			var pos3_half_z: float = nx*box_scale
			var rel: Vector3 = pos-translation
			if rel.x>=-pos3_half_x and rel.x<=pos3_half_x and \
					rel.z>=-pos3_half_z and rel.z<=pos3_half_z:
				mask |= WHITE_LIGHT_LAYER_MASK
		for child in get_children():
			if child is VisualInstance:
				child.layers = child.layers & ~LIGHT_LAYER_MASK | mask

func copy_only_item() -> Area:
	var new: Area = Area.new()
	new.set_script(get_script())
	new.create_item(scene,false)
	return new

func create_only_box(nx_: int,ny_: int,mount_flags_: int):
	nx=nx_
	ny=ny_
	mount_flags=mount_flags_
	mount_flags_any=0
	mount_flags_all=0
	collision_layer=16
	var shape: CollisionShape = CollisionShape.new()
	shape.shape = BoxShape.new()
	shape.shape.extents = Vector3(ny*box_scale,10,nx*box_scale)
	shape.name='InventorySlotShape'
	var old = get_node_or_null(shape.name)
	if old:
		remove_child(old)
		old.queue_free()
	add_child(shape)
	make_box()
	assert(mount_flags)

func create_item(scene_: PackedScene,with_box: bool,position = null,item = null):
	scene=scene_
	
	if item == null:
		item = scene.instance()
	nx=item.mount_size_x
	ny=item.mount_size_y
	page=item.help_page
	mount_flags_any=item.mount_flags_any
	mount_flags_all=item.mount_flags_all
	mount_flags=0
	
	assert(nx>0 and ny>0)
	
	if position!=null:
		assert(position is Vector2)
		my_x = int(round(position.x))
		my_y = int(round(position.y))

	
	var shape: BoxShape = BoxShape.new()
	shape.extents = Vector3(ny*item_scale,100,nx*item_scale)
	var cshape: CollisionShape = CollisionShape.new()
	cshape.shape = shape
	cshape.name = 'InventorySlotCollision'
	var old_collision=get_node_or_null(cshape.name)
	if old_collision:
		remove_child(old_collision)
		old_collision.queue_free()
	add_child(cshape)
	#collision_layer = mask
	collision_mask = 0
	item.name='InventorySlotItem'
	item.transform = Transform()
	if item.is_gun():
		item.translation.x = (item.mount_size_y-1.0)*item_scale
	item.translation.y += 0.1
	var old_item=get_node_or_null(item.name)
	if old_collision:
		remove_child(old_item)
		old_item.queue_free()
	add_child(item)
	
	if with_box:
		make_box()
	assert(mount_flags_all or mount_flags_any)

func is_shown_in_space() -> bool:
	var m=mount_flags_all|mount_flags_any|mount_flags
	return m&(game_state.MOUNT_FLAG_TURRET|game_state.MOUNT_FLAG_GUN)

func place_near(mount: Vector3,space: PhysicsDirectSpaceState,_mask: int):
	var badness: float = INF
	var loc: Vector3 = mount
	var angles: Array = []
	for i in range(0,10,1):
		angles.append(i/10.0)
		if i>0:
			angles.append(-i/10.0)
	for i in range(10,100,10):
		angles.append(i/10.0)
		angles.append(-i/10.0)
	for i in range(100,200,20):
		angles.append(i/10.0)
		angles.append(-i/10.0)
	for i in range(200,350,30):
		angles.append(i/10.0)
		angles.append(-i/10.0)
	for i in range(350,750,50):
		angles.append(i/10.0)
		angles.append(-i/10.0)
	var radii: Array = [ .1, .2, .3, .5, .8, 1.3, 2.1, 3.4, 5.5, 8.9 ]
	var shape: Shape = get_node('InventorySlotShape').shape
	var query: PhysicsShapeQueryParameters = PhysicsShapeQueryParameters.new()

	query.margin=0.25
	query.collide_with_areas=true
	#query.collision_mask = mask
	query.shape_rid=shape.get_rid()
	query.exclude = [get_rid()]
	var unit: Vector3 = Vector3(mount.x,0,mount.z).normalized()
	if unit.length()<0.99: # mount was precisely at the origin
		unit=x_axis
	for angle in angles:
		if mount.z<0:
			angle=-angle
		angle *= PI/180
		for radius in radii:
			var trans: Vector3 = mount + unit.rotated(y_axis,angle)*radius
			query.transform.origin=trans
			var result: Dictionary = space.get_rest_info(query)
			if result.empty():
				trans[1]=0
				var bad: float = Vector3(trans.x,0,trans.z).length()*(1+pow(1-cos(angle),.8))
				if bad<badness:
					badness=bad
					loc=trans
	translation=Vector3(loc.x,0,loc.z)

func make_box():
	for j in range(ny):
		for i in range(nx):
			var border: int = 0
			if i>0: border += LEFT
			if i<nx-1: border += RIGHT
			if j>0: border += UP
			if j<ny-1: border += DOWN
			var instance: MeshInstance = MeshInstance.new()
			instance.rotation = Vector3(0,PI/180*outfit_borders[border][0],0)
			instance.mesh = outfit_borders[border][1]
			instance.translation = Vector3(
				- 2*(j-float(ny)/2+0.5)*box_scale, 0, 2*(i-float(nx)/2+0.5)*box_scale)
			instance.name = "InventorySlotBox_x"+str(i)+"_y"+str(j)
			instance.scale = Vector3(box_scale,box_scale,box_scale)
			instance.layers = 2
			var old=get_node_or_null(instance.name)
			if old:
				remove_child(old)
				old.queue_free()
			add_child(instance)

