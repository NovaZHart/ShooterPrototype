extends Spatial

export var nx = 2
export var ny = 2
export var fail_cull_layer_mask = 8
export var okay_cull_layer_mask = 16
export var my_collision_mask = 32
export var grid_cell_size = 0.135

var first: Vector3
var slots: Array = []
var used: Array = []
var scene: Array = []

func clear_grid_range():
	var both: int = fail_cull_layer_mask|okay_cull_layer_mask
	for child in get_children():
		child.layers = child.layers & ~both

func color_slot(x,y,red,white):
	var spot = get_node_or_null(slots[y*nx+x])
	if not spot:
		return
	var both: int = fail_cull_layer_mask|okay_cull_layer_mask
	var set: int = (fail_cull_layer_mask if red else 0) \
		| (okay_cull_layer_mask if white else 0)
	spot.layers = (spot.layers&~both) | set

func remove_child_or_null(viewport_point: Vector2):
	var xy: Vector2 = slot_at_pixel(viewport_point)
	var x = round(xy.x)
	var y = round(xy.y)
	if x<0 or y<0 or x>=nx or y>=ny:
		return null
	var child_path = used[y*nx+x]
	if child_path.is_empty():
		return null
	var child = get_node_or_null(child_path)
	if child==null:
		return null
	for j in range(ny):
		for i in range(nx):
			if used[j*nx+i]==child_path:
				used[j*nx+i] = NodePath()
	remove_child(child)
	return child

func slot_at_pixel(viewport_point: Vector2) -> Vector2:
	var pos3 = get_viewport().get_camera().project_position(viewport_point,-10)
	return Vector2(pos3.z-first.z,-(pos3.x-first.x))

func insert_at_grid_range(inventory_slot: CollisionObject,item: PackedScene) -> bool:
	var test = update_grid_range(inventory_slot,false)
	if not test[0]:
		return false
	

func update_grid_range(inventory_slot: CollisionObject,recolor: bool = true) -> Array:
	if not inventory_slot.has_method('is_inventory_slot'):
		printerr('update_grid_range: argument is not an inventory slot')
		clear_grid_range()
		return [0,0,0,0]
	
	var item_nx: int = inventory_slot.nx
	var item_ny: int = inventory_slot.ny
	var item_x_float: float = inventory_slot.translation.z-first.z
	var item_y_float: float = -(inventory_slot.translation.x-first.x)
	var item_x1: int = int(round(item_x_float))
	var item_y1: int = int(round(item_y_float))
	var item_x2: int = item_x1 + item_nx-1
	var item_y2: int = item_y1 + item_ny-1
	var okay_points: int = 0
	
	item_x1 = clamp(item_x1,0,nx-1)
	item_x2 = clamp(item_x2,0,nx-1)
	item_y1 = clamp(item_y1,0,ny-1)
	item_y2 = clamp(item_y2,0,ny-1)
	
	for y in range(item_y1,item_y2+1):
		for x in range(item_x1,item_x2+1):
			if used[y*nx+x].is_empty():
				if recolor:
					color_slot(x,y,false,true)
				okay_points+=1
			elif recolor:
				color_slot(x,y,true,false)
	
	return [okay_points==item_nx*item_ny, item_x1, item_y1, item_x2, item_y2]

func _ready():
	var gs: float = grid_cell_size
	first = translation+Vector3(-(ny*gs)/2.0,0,(nx*gs)/2.0)
	for y in range(ny):
		for x in range(nx):
			var slot = Area.new()
			slot.set_script(preload('res://ui/InventorySlot.gd'))
			slot.name = 'slot_x'+str(x)+'_y'+str(y)
			slot.translation = first + Vector3(-gs*y,0,gs*x)
			slot.my_x = x
			slot.my_y = y
			add_child(slot)
			slots.append(slot.get_path())
			used.append(NodePath())
