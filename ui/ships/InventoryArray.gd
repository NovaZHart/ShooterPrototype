extends Spatial

export var nx: int = 2
export var ny: int = 2
const multimount: bool = false

const fail_cull_layer_mask: int = 8
const okay_cull_layer_mask: int = 16
const both_cull_layer_mask: int = fail_cull_layer_mask|okay_cull_layer_mask
const my_collision_mask: int = 32
const grid_cell_size: float = 0.135*2

var InventorySlot = preload('res://ui/ships/InventorySlot.gd')
var cached_shape = null
var first: Vector3
var slots: Array = []
var used: Array = []
var scenes: Array = []
var all_slots: Dictionary = {}
var mount_flags: int = 0

const x_axis: Vector3 = Vector3(1,0,0)
const y_axis: Vector3 = Vector3(0,1,0)

func is_InventoryArray(): pass # used for type checking; never called

func item_at(x: int, y: int): # -> Node or null
	if y<0 or y>=ny or x<0 or x>=nx or not used[y*nx+x]:
		return null
	return get_node_or_null(used[y*nx+x])

func scene_at(x: int,y: int): # -> PackedScene or null
	if y<0 or y>=ny or x<0 or x>=nx:
		return null
	return scenes[y*nx+x]

func create(nx_: int,ny_: int,mount_flags_: int):
	nx=nx_
	ny=ny_
	mount_flags=mount_flags_
	for y in range(ny):
		for x in range(nx):
			all_slots['slot_x'+str(x)+'_y'+str(y)]=1
			used.append(NodePath())
			scenes.append(null)

func list_ship_parts(products,from):
	var paths_processed = {}
	for j in range(ny):
		for i in range(nx):
			var node_path = used[j*nx+i]
			if not node_path or paths_processed.has(node_path):
				continue
			paths_processed[node_path]=1
			var node = get_node_or_null(node_path)
			if node==null:
				push_error('cannot find mount at path '+str(node_path))
				continue
			#print('multi add quantity from '+str(scenes[j*nx+i].resource_path))
			products.add_quantity_from(
				from,scenes[j*nx+i].resource_path,1,Commodities.ship_parts)
	return products

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

func make_shape() -> Shape:
	if cached_shape==null:
		var shape = BoxShape.new()
		shape.extents = Vector3(ny*InventorySlot.box_scale,10,nx*InventorySlot.box_scale)
		cached_shape = shape
	return cached_shape

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
	var shape: Shape = make_shape()
	var query: PhysicsShapeQueryParameters = PhysicsShapeQueryParameters.new()

	query.margin=0.25
	query.collide_with_areas=true
	#query.collision_mask = mask
	query.shape_rid=shape.get_rid()
	var exclude: Array = []
	for child in get_children():
		if child.has_method('is_InventorySlot'):
			exclude.append(child.get_rid());
		else:
			push_warning('InventoryArray child is not inventory slot: '+child.get_class())
	query.exclude = exclude
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

func check_at_grid_range(item_nx: int,item_ny: int,slot_x: int, slot_y: int) -> Array:
	# Checks if an item can be inserted at slot_x,slot_y (from slot_xy_for)
	# with width item_nx and height item_ny
	
	# Returns [null] if the item does not fit
	# Returns [] if the item fits and nothing is in the way
	
	# If something is in the way, returns [path1,scene1,path2,scene2,...]
	# with one path and scene for each item that is in the way
	if not item_nx or not item_ny or item_nx>nx or item_ny>ny:
		return [null]
	var y1 = clamp(int(slot_y),0,ny-1)
	var y2 = clamp(int(slot_y)+item_ny,0,ny)
	var x1 = clamp(int(slot_x),0,nx-1)
	var x2 = clamp(int(slot_x)+item_nx,0,nx)
	if x2-x1 < item_nx or y2-y1 < item_ny:
		return [null]
	var in_the_way: Dictionary = {}
	for y in range(y1,y2):
		for x in range(x1,x2):
			var path: NodePath = used[y*nx+x]
			if not path.is_empty():
				in_the_way[path] = scenes[y*nx+x]
	if in_the_way:
		var retval = []
		for key in in_the_way.keys():
			retval += [ key,in_the_way[key] ]
		return retval
	return []

func insert_at_grid_range(content,use_item_offset: bool) -> Array:
	if not utils.can_mount(mount_flags,content):
		push_warning('multimount: cannot mount item with wrong type; expected '+ \
			utils.mountable_string_for(content)+'.')
		return []
	elif content.nx>nx or content.ny>ny:
		push_warning('multimount: cannot mount item ('+str(content.nx)+'x'+ \
			str(content.ny)+') larger than mount space ('+str(nx)+'x'+str(ny)+')')
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
		item.queue_free()
		return []
	item.translation = Vector3(-(xy1.y+(content.ny-1)/2.0),0.1,(xy1.x+(content.nx-1)/2.0))*grid_cell_size+first
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

func update_coloring(pos,item):
	if item and not utils.can_mount(mount_flags,item):
		return color_slots(all_slots,fail_cull_layer_mask)
	elif not item or pos==null:
		return color_slots(all_slots,0)
	var dtr = (pos-first-translation)/grid_cell_size
	var size_x = item.item_size_x
	var size_y = item.item_size_y
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
			slot.set_script(InventorySlot)
			slot.name = 'slot_x'+str(x)+'_y'+str(y)
			slot.create_only_box(1,1,mount_flags)
			slot.mount_name = name
			slot.translation = first + Vector3(-y,0,x)*gs
			slot.collision_layer = my_collision_mask
			slot.collision_mask = my_collision_mask
			slot.my_x = x
			slot.my_y = y
			add_child(slot)
			slots.append(slot.get_path())
			used.append(NodePath())
