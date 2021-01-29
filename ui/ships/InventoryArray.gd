extends Spatial

export var nx: int = 2
export var ny: int = 2
export var mount_type: String = 'equipment'
const multimount: bool = false

const fail_cull_layer_mask: int = 8
const okay_cull_layer_mask: int = 16
const both_cull_layer_mask: int = fail_cull_layer_mask|okay_cull_layer_mask
const my_collision_mask: int = 32
const grid_cell_size: float = 0.135*2

var first: Vector3
var slots: Array = []
var used: Array = []
var scenes: Array = []
var all_slots: Dictionary = {}

func is_InventoryArray(): pass # used for type checking; never called

func item_at(x: int, y: int): # -> Node or null
	if y<0 or y>=ny or x<0 or x>=nx or not used[y*nx+x]:
		return null
	return get_node_or_null(used[y*nx+x])

func scene_at(x: int,y: int): # -> PackedScene or null
	if y<0 or y>=ny or x<0 or x>=nx:
		return null
	return scenes[y*nx+x]

func create(nx_: int,ny_: int,mount_type_: String):
	nx=nx_
	ny=ny_
	mount_type=mount_type_
	for y in range(ny):
		for x in range(nx):
			all_slots['slot_x'+str(x)+'_y'+str(y)]=1
			used.append(NodePath())
			scenes.append(null)

func content_for_design(mount_name: String): # -> MultiMount
	var multimount = game_state.universe.MultiMount.new()
	multimount.set_name(mount_name)
	var paths_processed = {}
	for j in range(ny):
		for i in range(nx):
			var path = used[j*nx+i]
			if not path or paths_processed.has(path):
				continue
			var node = get_node_or_null(path)
			if node==null:
				push_error('cannot find mount at path '+str(path))
				continue
			var mounted = game_state.universe.MultiMounted.new(scenes[j*nx+i],
				node.item_offset_x, node.item_offset_y)
			mounted.set_name_with_prefix(mount_name)
			multimount.add_child(mounted)
			paths_processed[path]=node
	return multimount

func all_children_xy() -> Array:
	var results: Dictionary = {}
	for j in range(ny):
		for i in range(nx):
			var path = used[j*nx+i]
			if not path:
				continue
			if not results.has(path):
				results[path] = [scenes[j*nx+i],i,j]
	return results.values()

func remove_child_or_null(x: int,y: int): # -> PackedScene or null
	if x<0 or y<0 or x>=nx or y>=ny:
		return [null,-1,-1]
	var child_path = used[y*nx+x]
	if child_path.is_empty():
		return [null,-1,-1]
	var child_scene = scenes[y*nx+x]
	if not child_scene is PackedScene:
		printerr('Missing scene in InventoryArray')
		return [null,-1,-1]
	var child = get_node_or_null(child_path)
	if child==null:
		return [null,-1,-1]
	var min_i = 999
	var min_j = 999
	for j in range(ny):
		for i in range(nx):
			if used[j*nx+i]==child_path:
				min_i=min(min_i,i)
				min_j=min(min_j,j)
				used[j*nx+i] = NodePath()
				scenes[j*nx+i] = null
	remove_child(child)
	child.queue_free()
	return [child_scene,min_i,min_j]

func slot_xy_for(loc: Vector3,slotx: int,sloty: int) -> Array:
	var dtr = (loc-first-translation)/grid_cell_size
	var xy1 = Vector2(round(dtr.z-(slotx-1)/2.0),round(-dtr.x-(sloty-1)/2.0))
	return [ clamp(int(xy1.x),0,nx-1), clamp(int(xy1.y),0,ny-1) ]

func insert_at_grid_range(content,use_item_offset: bool,_console=null) -> Array:
	if content.mount_type!=mount_type:
		push_warning('multimount: cannot mount item with wrong type "'+content.mount_type+'"')
		return []
	elif content.nx>nx or content.ny>ny:
		push_warning('multimount: cannot mount item ('+str(content.nx)+'x'+str(content.ny)+') larger than mount space ('+str(nx)+'x'+str(ny)+')')
		return []
	# item location, upper-left (-x, -y) corner:
	var xy1
	if use_item_offset:
		assert(content.my_x>=0 and content.my_y>=0)
		xy1 = Vector2(content.my_x,content.my_y)
	else:
		var dtr = (content.translation-first-translation)/grid_cell_size
		xy1 = Vector2(round(dtr.z-(content.nx-1)/2.0),round(-dtr.x-(content.ny-1)/2.0))
	var y1 = clamp(int(xy1.y),0,ny-1)
	var y2 = clamp(int(xy1.y)+content.ny,0,ny)
	var x1 = clamp(int(xy1.x),0,nx-1)
	var x2 = clamp(int(xy1.x)+content.nx,0,nx)
	if x2-x1 < content.nx or y2-y1 < content.ny:
		push_warning('multimount: not enough space free to mount: '+str(content.nx)+'x'+str(content.ny)+' item does not fit in '+str(x2-x1)+'x'+str(y2-y1)+' space at location '+str(x1)+'x'+str(y1)+'.')
		return []
	for y in range(y1,y2):
		for x in range(x1,x2):
			var path: NodePath = used[y*nx+x]
			if not path.is_empty():
				push_warning('multimount: something is already installed at '+str(x)+'x'+str(y))
				return []
	var scene: PackedScene = content.scene
	var item: Spatial = scene.instance()
	if not item is Spatial:
		push_warning('multimount: scene "'+scene.resource_path+'" is not a Spatial.')
		return []
	item.translation = Vector3(-(xy1.y+(content.ny-1)/2.0),0,(xy1.x+(content.nx-1)/2.0))*grid_cell_size+first
	item.item_offset_x = x1
	item.item_offset_y = y1
	if item is CollisionObject:
		item.collision_layer = 0
		item.collision_mask = 0
	add_child(item)
	var path = item.get_path()
	for y in range(y1,y2):
		for x in range(x1,x2):
			used[y*nx+x] = path
			scenes[y*nx+x] = scene
	return [x1,y1]

func color_slots(set: Dictionary,mask: int):
	for path in set:
		var child = get_node_or_null(path)
		if child:
			child.color(mask)

func update_coloring(size_x: int,size_y: int,pos,type: String):
	if type and type!=mount_type:
		return color_slots(all_slots,fail_cull_layer_mask)
	elif not type or pos==null or size_x<=0 or size_y<=0:
		return color_slots(all_slots,0)
	var dtr = (pos-first-translation)/grid_cell_size
	# item location, upper-left (-x, -y) corner:
	var xy1 = Vector2(round(dtr.z-(size_x-1)/2.0),round(-dtr.x-(size_y-1)/2.0))
	var not_free: int = size_x*size_y
	var not_red: Dictionary = {}
	var y1 = clamp(int(xy1.y),0,ny-1)
	var y2 = clamp(int(xy1.y)+size_y,0,ny)
	var x1 = clamp(int(xy1.x),0,nx-1)
	var x2 = clamp(int(xy1.x)+size_x,0,nx)
	for y in range(ny):
		for x in range(nx):
			if not (y>=y1 and y<y2 and x>=x1 and x<x2):
				var child = get_node_or_null('slot_x'+str(x)+'_y'+str(y))
				if child:
					child.color(0)
				continue
			var path: NodePath = used[y*nx+x]
			if path.is_empty():
				not_red['slot_x'+str(x)+'_y'+str(y)]=1
				not_free-=1
			else:
				var child = get_node_or_null('slot_x'+str(x)+'_y'+str(y))
				if child:
					child.color(fail_cull_layer_mask)
	color_slots(not_red, (0 if not_free>0 else okay_cull_layer_mask) )

func _ready():
	var gs: float = grid_cell_size
	first = Vector3((ny-1)/2.0,0,-(nx-1)/2.0)*gs
	for y in range(ny):
		for x in range(nx):
			var slot = Area.new()
			slot.set_script(preload('res://ui/ships/InventorySlot.gd'))
			slot.name = 'slot_x'+str(x)+'_y'+str(y)
			slot.create_only_box(1,1,mount_type)
			slot.mount_name = name
			slot.translation = first + Vector3(-y,0,x)*gs
			slot.collision_layer = my_collision_mask
			slot.collision_mask = my_collision_mask
			slot.my_x = x
			slot.my_y = y
			add_child(slot)
			slots.append(slot.get_path())
			used.append(NodePath())
