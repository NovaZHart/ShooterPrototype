extends Tree

signal select_node
signal deselect_node
signal center_on_node

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
