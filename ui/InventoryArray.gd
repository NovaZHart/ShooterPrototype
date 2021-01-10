extends Spatial

export var nx: int = 2
export var ny: int = 2
export var mount_type: String = 'equipment'

const fail_cull_layer_mask: int = 8
const okay_cull_layer_mask: int = 16
const both_cull_layer_mask: int = fail_cull_layer_mask|okay_cull_layer_mask
const my_collision_mask: int = 32
const grid_cell_size: float = 0.135

var first: Vector3
var slots: Array = []
var used: Array = []
var scenes: Array = []

func create(nx_: int,ny_: int,mount_type_: String):
	nx=nx_
	ny=ny_
	mount_type=mount_type_

func content_for_design() -> Array:
	var nodes = Dictionary()
	for j in range(ny):
		for i in range(nx):
			var path = used[j*nx+i]
			if not path or nodes.has(path):
				continue
			var node = get_node_or_null(path)
			if node==null:
				continue
			nodes[path]=node
	var content = []
	for node in nodes:
		content.append([ node.my_x, node.my_y, node.scene ])
	return content

func remove_child_or_null(pos3: Vector3): # -> PackedScene or null
	var xy: Vector2 = Vector2(pos3.z-first.z,-(pos3.x-first.x))/grid_cell_size
	var x: int = int(round(xy.x))
	var y: int = int(round(xy.y))
	if x<0 or y<0 or x>=nx or y>=ny:
		return null
	var child_path = used[y*nx+x]
	if child_path.is_empty():
		return null
	var child_scene = scenes[y*nx+x]
	if not child_scene is PackedScene:
		printerr('Missing scene in InventoryArray')
		return null
	var child = get_node_or_null(child_path)
	if child==null:
		return null
	for j in range(ny):
		for i in range(nx):
			if used[j*nx+i]==child_path:
				used[j*nx+i] = NodePath()
				scenes[j*nx+i] = null
	remove_child(child)
	child.queue_free()
	return child_scene

func insert_at_grid_range(drag: CollisionObject,scene: PackedScene) -> bool:
	if drag.mount_type!=mount_type or drag.nx>nx or drag.ny>ny:
		return false
	# dragged item's location, upper-left (-x, -y) corner:
	var xy1 = Vector2(round(drag.translation.z/grid_cell_size-drag.nx),
		round(-drag.translation.x/grid_cell_size-drag.ny))
	for y in range(int(xy1.y),int(xy1.y)+drag.ny):
		for x in range(int(xy1.x),int(xy1.x)+drag.ny):
			var path: NodePath = used[y*nx+x]
			if not path.is_empty():
				return false
	var item: Spatial = scene.instance()
	if not item is Spatial:
		printerr('insert_at_grid_range: scene "'+scene.resource_path+'" is not a Spatial.')
		return false
	item.translation = Vector3(-xy1.y+0.5,0,xy1.x+0.5)*grid_cell_size+first
	if item is CollisionObject:
		item.collision_layer = 0
		item.collision_mask = 0
	add_child(item)
	var path = item.get_path()
	for y in range(int(xy1.y),int(xy1.y)+drag.ny):
		for x in range(int(xy1.x),int(xy1.x)+drag.ny):
			used[y*nx+x] = path
			scenes[y*nx+x] = scene
	return true

func all_slots() -> Dictionary:
	var d = {}
	for path in used:
		if not path.empty():
			d[path]=1
	return d

func color_slots(set: Dictionary,mask: int):
	for path in set:
		var child = get_node_or_null(path)
		if child:
			child.layers = child.layers & ~both_cull_layer_mask | mask

func update_coloring(size_x: int,size_y: int,pos,type: String):
	if type!=mount_type:
		return color_slots(all_slots(),fail_cull_layer_mask)
	elif pos==null or size_x<=0 or size_y<=0:
		return color_slots(all_slots(),0)
	# item location, upper-left (-x, -y) corner:
	var xy1 = Vector2(round(pos.z/grid_cell_size-size_x),round(-pos.x/grid_cell_size-size_y))
	var not_free: int = size_x*size_y
	var red: Dictionary = {}
	var not_red: Dictionary = {}
	for y in range(int(xy1.y),int(xy1.y)+size_y):
		for x in range(int(xy1.x),int(xy1.x)+size_x):
			var path: NodePath = used[y*nx+x]
			if path.is_empty():
				not_red[path]=1
			else:
				red[path]=1
				not_free-=1
	
	color_slots(red,fail_cull_layer_mask)
	color_slots(not_red, (0 if not_free else okay_cull_layer_mask) )

func _ready():
	var gs: float = grid_cell_size
	first = translation+Vector3(-(ny*gs)/2.0,0,(nx*gs)/2.0)
	for y in range(ny):
		for x in range(nx):
			var slot = Area.new()
			slot.set_script(preload('res://ui/InventorySlot.gd'))
			slot.name = 'slot_x'+str(x)+'_y'+str(y)
			slot.mount_name = name
			slot.translation = first + Vector3(-gs*y,0,gs*x)
			slot.collision_layer = 0
			slot.collision_mask = my_collision_mask
			slot.my_x = x
			slot.my_y = y
			add_child(slot)
			slots.append(slot.get_path())
			used.append(NodePath())
