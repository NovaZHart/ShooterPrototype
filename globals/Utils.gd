extends Node

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
	while scan:
		var result = Tree_depth_first(scan,object,method)
		if not result:
			result = object.call(method,item,scan)
		if result:
			return result
		if scan:
			scan = scan.get_next()
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
	if root:
		root.free()

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

func ship_max_speed(ship_stats,mass=null) -> float:
	if mass==null:
		mass = ship_stats.get('mass',null)
	if mass==null:
		mass = ship_mass(ship_stats)
	var max_thrust = max(max(ship_stats['reverse_thrust'],ship_stats['thrust']),0)
	return max_thrust/max(1e-9,ship_stats['drag']*mass)

func ship_mass(ship_stats):
	return ship_stats['empty_mass']+ship_stats.get('cargo_mass',0)+ \
		ship_stats['max_fuel']*ship_stats['fuel_density']/1000.0+ \
		ship_stats['max_armor']*ship_stats['armor_density']/1000.0

func event_position(event: InputEvent) -> Vector2:
	# Get the best guess of the mouse position for the event.
	if event and event is InputEventMouse:
		return event.position
	return get_viewport().get_mouse_position()
