extends Spatial

var border_all=preload('res://ui/OutfitBorders/1x1.mesh')
var border_tube_bottom=preload('res://ui/OutfitBorders/1x1-U.mesh')
var border_tube_middle=preload('res://ui/OutfitBorders/1x1-UD.mesh')
var border_middle=preload('res://ui/OutfitBorders/1x1-UDLR.mesh')
var border_left=preload('res://ui/OutfitBorders/1x1-UDR.mesh')
var border_lower_left=preload('res://ui/OutfitBorders/1x1-UR.mesh')

const x_axis: Vector3 = Vector3(1,0,0)
const y_axis: Vector3 = Vector3(0,1,0)

var outfit_borders = [             # U D L R
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

var mounts: Array = []

const RIGHT: int = 1
const LEFT: int = 2
const DOWN: int = 4
const UP: int = 8

func make_box(width: int,height: int,box_scale: float) -> Area:
	var box: Area = Area.new()
	box.collision_layer=16
	
	var shape: CollisionShape = CollisionShape.new()
	shape.shape = BoxShape.new()
	shape.shape.extents = Vector3(height*box_scale,10,width*box_scale)
	shape.name='shape'
	box.add_child(shape)
	
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
	box.translation=Vector3(loc.x,9,loc.z)
	return box

func gen_box(width: int,height: int,loc: Vector3,box_scale: float,box_name: String) -> Area:
	var box: Area = place_box(make_box(width,height,box_scale),loc)
	box.name=box_name
	add_child(box)
	return box

# Called when the node enters the scene tree for the first time.
func _ready():
	$SpaceBackground.center_view(130,90,0,100,0)
	for child in $Ship.get_children():
		if child.has_method('mount_size'):
			var size: Vector2 = child.mount_size()
			var loc: Vector3 = child.translation
			loc.y=10
			var mount_name: String = 'mount_'+child.name
			mounts.append(mount_name)
			gen_box(int(ceil(size.x)),int(ceil(size.y)),loc,0.125,mount_name)
