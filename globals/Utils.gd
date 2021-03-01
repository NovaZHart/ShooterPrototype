extends Node

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

func TreeItem_find_index(parent: TreeItem,object: Object,method: String):
	var scan = parent.get_children()
	var index = 0
	while scan:
		if object.call(method,parent,scan):
			return index
		index += 1
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
