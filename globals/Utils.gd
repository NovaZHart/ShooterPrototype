extends Node

var ScriptUtilsNative = preload("res://bin/ScriptUtils.gdns")
var native

func noop():
	native.noop()

func string_join(string_list: Array,separator: String) -> String:
	return native.string_join(string_list,separator)

func update_dict(dest: Dictionary, src: Dictionary) -> Dictionary:
	for key in src:
		dest[key] = src[key]
	return dest

func _init():
	var the_seed = OS.get_system_time_msecs()
	print('Setting random seed to '+str(the_seed))
	seed(the_seed)
	native = ScriptUtilsNative.new()

func get_viewport_scale() -> Vector2:
	var window_size: Vector2 = get_tree().root.size
	var project_height: int = ProjectSettings.get_setting("display/window/size/height")
	var project_width: int = ProjectSettings.get_setting("display/window/size/width")
	var scale: Vector2 = window_size / Vector2(project_width,project_height)
	return scale

func make_icosphere(subs: int) -> ArrayMesh:
	return native.make_icosphere(subs)

func make_cube_sphere_v2(radius: float,subs: int) -> ArrayMesh:
	return native.make_cube_sphere_v2(radius,subs)

func make_lookup_tiles_c224() -> Image:
	return native.make_lookup_tiles_c224()

func make_lookup_tiles_c112() -> Image:
	return native.make_lookup_tiles_c112()

class WeightArraySorter extends Object:
	var weights: Array
	func _init(weights_: Array):
		weights=weights_
	func cmp(index1,index2):
		return weights[index1] < weights[index2]

func sorted_array_by_weight(array: Array, weights: Array) -> Array:
	# Return a sorted copy of array, sorted by weight.
	assert(len(weights) == len(array))
	var indices: Array = range(len(array))
	var sorter = WeightArraySorter.new(weights)
	indices.sort_custom(sorter,'cmp')
	sorter.free()
	var result: Array = []
	result.resize(len(array))
	for i in range(len(indices)):
		result[i] = array[indices[i]]
	return result

func can_mount_flags(mount_type: int, item_type_all: int, item_type_any: int) -> bool:
	return  ( not item_type_all or item_type_all&mount_type == item_type_all ) \
		and \
		( not item_type_any or item_type_any&mount_type != 0 )

func can_mount(mount_flags: int, item) -> bool:
	return  ( not item.mount_flags_all or item.mount_flags_all&mount_flags == item.mount_flags_all ) \
		and \
		( not item.mount_flags_any or item.mount_flags_any&mount_flags != 0 )

func mount_type_to_int(mount_type: String) -> int:
	var mount_flags: int = 0
	for s in mount_type.split(' ',false,false):
		if   s=='internal':  mount_flags = game_state.MOUNT_FLAG_INTERNAL  + mount_flags
		elif s=='external':  mount_flags = game_state.MOUNT_FLAG_EXTERNAL  + mount_flags
		elif s=='gun':       mount_flags = game_state.MOUNT_FLAG_GUN       + mount_flags
		elif s=='turret':    mount_flags = game_state.MOUNT_FLAG_TURRET    + mount_flags
		elif s=='equipment': mount_flags = game_state.MOUNT_FLAG_EQUIPMENT + mount_flags
		elif s=='engine':    mount_flags = game_state.MOUNT_FLAG_ENGINE    + mount_flags
		else:
			push_warning('Invalid mount type "'+str(s)+'"')
	return mount_flags

func mount_string(mount_flags: int,sep: String = ' ',before_last: String = ''):
	var result: Array = []
	if mount_flags&game_state.MOUNT_FLAG_INTERNAL:  result+=[ 'internal' ]
	if mount_flags&game_state.MOUNT_FLAG_EXTERNAL:  result+=[ 'external' ]
	if mount_flags&game_state.MOUNT_FLAG_GUN:       result+=[ 'gun' ]
	if mount_flags&game_state.MOUNT_FLAG_TURRET:    result+=[ 'turret' ]
	if mount_flags&game_state.MOUNT_FLAG_EQUIPMENT: result+=[ 'equipment' ]
	if mount_flags&game_state.MOUNT_FLAG_ENGINE:    result+=[ 'engine' ]
	var string: String = ''
	for i in range(len(result)):
		if i:
			string += sep
			if i==len(result)-1:
				string += before_last
		string += result[i]
	return string

func mount_string_for(mount) -> String:
	return mount_string(mount.mount_flags,' ','')

func mountable_string_for(mountable) -> String:
	return mountable_string(mountable.mount_flags_all,mountable.mount_flags_any)

func mountable_string(mount_flags_all: int, mount_flags_any: int) -> String:
	if mount_flags_all:
		if mount_flags_any:
			return 'all of ['+mount_string(mount_flags_all,' ','and ')+' = '+str(mount_flags_all)+']'+ \
				' and any of ['+mount_string(mount_flags_any,' ','or ')+' = '+str(mount_flags_any)+']'
		else:
			return 'all of ['+mount_string(mount_flags_all,' ','and ')+' = '+str(mount_flags_all)+']'
	elif mount_flags_any:
		return 'any of ['+mount_string(mount_flags_any,' ','or ')+' = '+str(mount_flags_any)+']'
	return 'anything (fits in any slot)'

class YieldActionQueue extends Reference:
	var mutex: Mutex = Mutex.new()
	var queue: Array = []
	var last_id: int = -1
	
	func check_top(id: int):
		mutex.lock()
		var result = len(queue) and queue[0]==id
		mutex.unlock()
		return result
	
	func run(object,method,args):
		# Queue this request:
		mutex.lock()
		last_id += 1
		var id = last_id
		queue.append(id)
		mutex.unlock()
		
		# Wait for our turn to run:
		while not check_top(id):
			yield()
		
		# Call the method and yield until we have a result:
		var result = object.callv(method,args)
		while result is GDScriptFunctionState and result.is_valid():
			yield(result,'completed')
		
		# Remove this request from the queue:
		mutex.lock()
		queue.erase(id)
		mutex.unlock()
		
		# Report the result back to the caller.
		return result

class TreeFinder extends Reference:
	var key
	var column
	func _init(key_,column_=0):
		key=key_
		column=column_
	func find(_parent: TreeItem,child: TreeItem):
		if child.get_metadata(column)==key:
			return child
		return null
	func eq(_parent: TreeItem,child: TreeItem):
		return child.get_metadata(column)==key
	func ge(_parent: TreeItem,child: TreeItem):
		return child.get_metadata(column)>=key

func TreeItem_at_index(parent: TreeItem,index: int): # -> TreeItem or null
	var scan = parent.get_children()
	var i = 0
	while scan:
		if i==index:
			return scan
		if scan:
			scan = scan.get_next()
			i += 1
	return null

func TreeItem_find_index(parent: TreeItem,object: Object,method: String):
	var scan = parent.get_children()
	var index = 0
	while scan:
		if object.call(method,parent,scan):
			return index
		index += 1
		if scan:
			scan = scan.get_next()
	return -1

func Tree_set_titles_and_width(tree: Tree,titles,font: Font,min_width: int,expand=true):
	for i in range(len(titles)):
		var title = titles[i]
		if title and title is String:
			Tree_set_title_and_width(tree,i,title,font,min_width,expand)

func Tree_set_title_and_width(tree: Tree,column: int,title: String,font: Font,min_width: int,expand=true):
	var text = title
	var width = 0
	for i in range(30):
		text = ' '.repeat(i) + title + ' '.repeat(i)
		width = font.get_string_size(text).x
		if width>=min_width:
			break
	tree.set_column_title(column,text)
	tree.set_column_expand(column,expand)
	tree.set_column_min_width(column,width+6)

func Tree_remove_where(item: TreeItem,object: Object,method: String) -> bool:
	var result = false
	var scan = item.get_children()
	while scan:
		if object.call(method,item,scan):
			var next = scan.get_next()
			item.remove_child(scan)
			scan.free()
			scan = next
			result = true
		else:
			result = Tree_depth_first(scan,object,method) or result
			if not scan:
				return result
			scan = scan.get_next()
	return result

func Tree_depth_first(item: TreeItem,object: Object,method: String):
	var scan = item.get_children()
	while scan and scan.has_method('get_next'):
		var result = Tree_depth_first(scan,object,method)
		var scan_next = null
		if scan:
			scan_next = scan.get_next()
		if not result:
			result = object.call(method,item,scan)
		if result:
			return result
		scan = scan_next
	return false

func Tree_remove_subtree(parent: TreeItem,child: TreeItem):
	var _discard = Tree_depth_first(child,self,'_TreeItem_remove_child')
	_TreeItem_remove_child(parent,child)

func Tree_clear(tree: Tree):
	var root = tree.get_root()
	if not root:
		return
	var _discard = Tree_depth_first(root,self,'_TreeItem_remove_child')
	tree.clear()

func _TreeItem_remove_child(parent: TreeItem,child: TreeItem) -> void:
	parent.remove_child(child)
	child.free()

func TreeItem_child_count_at_least(item: TreeItem,min_children: int):
	var count = 0
	var scan = item.get_children()
	while scan:
		count += 1
		if count >= min_children:
			return true
		if scan:
			scan = scan.get_next()
	return false

func mesh_radius(mesh: Mesh) -> float:
	if not mesh:
		return 0.0
	var aabb: AABB = mesh.get_aabb()
	var x = abs(aabb.position.x)+abs(aabb.size.x)
	var z = abs(aabb.position.z)+abs(aabb.size.z)
	return sqrt(x*x+z*z)

func dict_random_element_by_weight(dict: Dictionary,keys=null):
	if not keys:
		keys = dict.keys()
	var n = len(keys)
	if not n:
		return null
	var accum: Array = Array()
	accum.resize(n+1)
	accum[0] = 0.0
	for i in range(n):
		accum[i+1] = accum[i] + abs(dict.get(keys[i],0.0)+0.0)
	var there = min(n-1,accum.bsearch(randf()*accum[n]))
	return keys[there]

func ship_max_speed(ship_stats,mass=null) -> float:
	if mass==null:
		mass = ship_stats.get('mass',null)
	if mass==null:
		mass = ship_mass(ship_stats)
	var max_thrust = max(max(ship_stats['reverse_thrust'],ship_stats['thrust']),0)
	return max_thrust/max(1e-9,ship_stats['drag']*mass)

func ship_mass(ship_stats,when_full = false):
	var cargo_mass
	if when_full:
		cargo_mass = ship_stats.get('max_cargo',0)
	else:
		cargo_mass = ship_stats.get('cargo_mass',0)
	return ship_stats['empty_mass']+cargo_mass+ \
		ship_stats['max_fuel']/ship_stats['fuel_inverse_density']+ \
		ship_stats['max_armor']/ship_stats['armor_inverse_density']

func event_position(event: InputEvent) -> Vector2:
	# Get the best guess of the mouse position for the event.
	if event and event is InputEventMouse:
		return event.position
	return get_viewport().get_mouse_position()

func sum_of_squares_scalar(accum: float, add: float) -> float:
	if not add:
		return accum
	var result: float
	result = add*abs(add) + accum*abs(accum)
	result = sign(result)*sqrt(abs(result))
	return result

func sum_of_squares(accum: PoolRealArray,add: PoolRealArray) -> PoolRealArray:
	if not add:
		return accum
	for i in range(len(add)):
		if i>=len(accum):
			accum.append(add[i])
		elif add[i]!=0:
			var a = sign(accum[i])*accum[i]*accum[i] + sign(add[i])*add[i]*add[i]
			accum[i] = sign(a)*sqrt(abs(a))
	return accum

func isfinite(f: float) -> bool:
	return not is_inf(f) and not is_nan(f)

func weighted_add(add_value,add_weight: float,stats: Dictionary,value_key: String,weight_key: String):
	if not add_weight:
		return

	var abs_weight: float = abs(stats.get(weight_key,add_weight))
	var abs_add_weight: float = abs(add_weight)
	var value: float = stats.get(value_key,0.0)
	var denom: float = abs_weight+abs_add_weight

	stats[value_key] = (add_value*abs_add_weight + value*abs_weight)/denom
	assert(isfinite(stats[value_key]))
