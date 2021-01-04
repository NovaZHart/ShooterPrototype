extends Area

var scene: PackedScene
var nx: int = 2
var ny: int = 2
var page: String = 'weapons'
var mount_type: String = ''

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

const box_scale: float = 0.135
const item_scale: float = 0.125

func copy_only_item() -> Area:
	var new: Area = Area.new()
	new.set_script(get_script())
	new.create_item(scene,false)
	return new

func create_only_box(nx_: int,ny_: int):
	nx=nx_
	ny=ny_
	collision_layer=16
	var shape: CollisionShape = CollisionShape.new()
	shape.shape = BoxShape.new()
	shape.shape.extents = Vector3(ny*box_scale,10,nx*box_scale)
	shape.name='shape'
	add_child(shape)
	make_box()

func create_item(scene_: PackedScene,with_box: bool):
	scene=scene_
	
	var item: Node = scene.instance()
	nx=item.mount_size_x
	ny=item.mount_size_y
	page=item.help_page
	mount_type=item.mount_type
	
	var shape: BoxShape = BoxShape.new()
	shape.extents = Vector3(ny*item_scale,1,nx*item_scale)
	var cshape: CollisionShape = CollisionShape.new()
	cshape.shape = shape
	cshape.name = 'collision'
	add_child(cshape)
	#collision_layer = mask
	collision_mask = 0
	item.name='item'
	item.transform = Transform()
	if item.mount_type=='gun':
		item.translation.x = (item.mount_size_y-1.0)*item_scale
	add_child(item)
	
	if with_box:
		make_box()

func place_near(mount: Vector3,space: PhysicsDirectSpaceState,mask: int):
#	var space: PhysicsDirectSpaceState = get_viewport().world.direct_space_state
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
	var shape: Shape = get_node('shape').shape
	var query: PhysicsShapeQueryParameters = PhysicsShapeQueryParameters.new()

	query.margin=0.25
	query.collide_with_areas=true
	query.collision_mask = mask
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
			instance.name = 'cell_'+str(i)+'_'+str(j)
			instance.scale = Vector3(box_scale,box_scale,box_scale)
			instance.layers = 2
			add_child(instance)

