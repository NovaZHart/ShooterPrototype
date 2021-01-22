extends Tree

signal select_node
signal deselect_node
signal center_on_node

func scan_array(x) -> Array:
	if x is Array:
		return x
	var a: Array = []
	a.append(x)
	return a

func all_children_of(item) -> Array:
	var children: Array = []
	var scan = item.get_children()
	while scan:
		if scan==null or not scan is TreeItem:
			push_error('Got invalid type from Tree: '+str(scan))
			continue
		children.append(scan)
		scan = scan.get_next()
	return children

func select_recurse(item,path) -> bool:
	if not item:
		return false
	var success: bool = false
	var scan = item
	while scan:
		if scan.get_metadata(0)==path:
			scan.select(0)
			success=true
		else:
			scan.deselect(0)
		success = select_recurse(scan.get_children(),path) or success
		scan = scan.get_next()
	return success

func select_node_with_path(path) -> bool:
	var node = null
	var full_path = NodePath()
	if path:
		node = game_state.universe.get_node_or_null(path)
		if node != null:
			full_path = node.get_path()
	return select_recurse(get_root(),full_path)

func sync_names_recursively(item):
	var scan = item
	while scan:
		var path = scan.get_metadata(0)
		if path and path is NodePath:
			var node = game_state.universe.get_node_or_null(path)
			if node:
				scan.set_text(0,node.display_name)
		sync_names_recursively(scan.get_children())
		scan = scan.get_next()

func sync_metadata():
	sync_names_recursively(get_root())
	return true

func update_system():
	print('tree update system')
	var root: TreeItem = get_root()
	if root:
		assert(root!=null)
		assert(root is TreeItem)
		if recurse_update_tree(root):
			clear()

func recurse_update_tree(item) -> bool: # true = delete me
	assert(item)
	assert(item is TreeItem)
	var path: NodePath = item.get_metadata(0)
	var node = game_state.universe.get_node_or_null(path)
	if not node:
		print('update fail; no node at '+str(path))
		return true
	var remove = []
	var paths = {}
	for scan in all_children_of(item):
		if scan==null or not scan is TreeItem:
			push_error('item.get_children() returned a bad value '+str(scan))
			continue
		var abspath = game_state.tree.make_absolute(scan.get_metadata(0))
		print('scan '+str(scan)+' abspath '+str(abspath))
		if recurse_update_tree(scan):
			remove.append(scan)
		elif abspath:
			paths[abspath] = scan
	for remove_me in remove:
		item.remove_child(remove_me)
	for child in node.get_children():
		var child_path = game_state.tree.make_absolute(child.get_path())
		if not paths.has(child_path):
			print(child_path,' is not in ',str(paths))
			recurse_fill_tree(child,item)
	return false

func recurse_fill_tree(node: simple_tree.SimpleNode, parent):
	var item: TreeItem = create_item(parent)
	var path: NodePath = node.get_path()
	item.set_text(0,node.display_name)
	item.set_metadata(0,path)
	for child in node.get_children():
		recurse_fill_tree(child,item)

func set_system(system: simple_tree.SimpleNode):
	clear()
	recurse_fill_tree(system, null)

func _on_Tree_item_activated():
	var path: NodePath = get_selected().get_metadata(0)
	emit_signal('center_on_node',path)

func _on_Tree_item_selected():
	var path: NodePath = get_selected().get_metadata(0)
	emit_signal('select_node',path)

func _on_Tree_nothing_selected():
	emit_signal('deselect_node')
