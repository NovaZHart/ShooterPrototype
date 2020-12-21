extends Node2D

var tick: int = 0
var tex: MeshTexture = MeshTexture.new()
var polygons: Array = []
var collision_polygon_data: PoolVector2Array = PoolVector2Array()

func sync_2d3d():
	for child in get_children():
		if child is Node2D:
			for grand in child.get_children():
				if not grand is Spatial:
					continue
				grand.translation = Vector3(-child.position.y/100,grand.translation.y,-child.position.x/100)
				if not grand is Camera:
					grand.rotation = Vector3(0,child.rotation,0)

func sync_camera():
	$Camera.translation = Vector3(-$RigidBody2D.position.y/100,10,-$RigidBody2D.position.x/100)
	$SpaceBackground.center_view($Camera.translation.x,$Camera.translation.z,0,
		$Camera.size,$Camera.translation.y)

func _ready():
	$RigidBody2D.linear_damp=5.0
	
	var new: RigidBody2D = $RigidBody2D.duplicate(true)
	new.name='george'
	new.position=Vector2(100,-100)
	add_child(new)
	
	var vert3d: PoolVector3Array = $RigidBody2D/MeshInstance.mesh.get_faces()
	var vert2d: PoolVector2Array = PoolVector2Array()
	var aabb3d: AABB = $RigidBody2D/MeshInstance.mesh.get_aabb()
	vert2d.resize(vert3d.size())
	var center3d: Vector3 = (aabb3d.position+aabb3d.end)/2
	var size3d: Vector3 = (aabb3d.position-aabb3d.end).abs()*1.1
	for i in range(vert2d.size()):
		var x: float = (vert3d[i].x-center3d.x)/size3d.x
		var z: float = (vert3d[i].z-center3d.z)/size3d.z
		vert2d[i] = Vector2(1024*(0.5-z),600*(0.5-x))
	var arr: Array = Array()
	arr.resize(ArrayMesh.ARRAY_MAX)
	arr[ArrayMesh.ARRAY_VERTEX] = vert2d
	var base_image: Image = Image.new()
	base_image.create(1024,600,false,Image.FORMAT_RGB8)
	base_image.fill(Color(0,0,0,0))
	tex.base_texture = ImageTexture.new()
	tex.base_texture.create_from_image(base_image)
	tex.image_size = Vector2(1024,600)
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arr)
	tex.mesh = mesh
	$Viewport/TextureRect.texture=tex

func make_polygons():
	var image: Image = $Viewport.get_texture().get_data()
	assert(image!=null)
	var bm: BitMap = BitMap.new()
	bm.create_from_image_alpha(image)
	print(bm.get_size())
	print(bm.get_true_bit_count())
	var rect: Rect2 = Rect2(0,0,bm.get_size().x,bm.get_size().y)
	polygons = bm.opaque_to_polygons(rect)
	update()

func _draw():
	if not polygons:
		print('nothing to draw')
		return
	print('draw')
	var big_size: int = -1
	var big_index: int = -1
	for i in range(polygons.size()):
		if polygons[i].size()>big_size:
			big_size=polygons[i].size()
			big_index=i
	if big_index>=0:
		collision_polygon_data=PoolVector2Array(polygons[big_index])
		draw_colored_polygon(collision_polygon_data,Color(1,1,1,0.5))

func _process(_delta):
	tick += 1
	if tick==1:
		$Viewport.render_target_update_mode=Viewport.UPDATE_ONCE
	if tick==2:
		make_polygons()
	sync_camera()

func move_ship(delta):
	var move: int = int(Input.is_action_pressed("ui_up"))-int(Input.is_action_pressed("ui_down"))
	if move:
		#$RigidBody2D.translate(Vector2(0,-move*delta*120).rotated(-$RigidBody2D.rotation))
		$RigidBody2D.add_central_force(Vector2(0,-move*delta*1200).rotated($RigidBody2D.rotation))
	var rotate: int = int(Input.is_action_pressed("ui_left"))-int(Input.is_action_pressed("ui_right"))
	$RigidBody2D.angular_velocity=rotate

func _physics_process(delta):
	sync_2d3d()
	move_ship(delta)
