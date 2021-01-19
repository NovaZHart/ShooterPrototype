extends Tree

signal select_node
signal deselect_node

func select_recursively_with_path(item: TreeItem,path: NodePath) -> bool:
	if item.get_metadata(0)==path:
		pass # FIXME
	else:
		pass # FIXME
	return false # FIXME

func select_node_with_path(path: NodePath) -> bool:
	return select_recursively_with_path(get_root(),path)

func sync_names_recursively(item: TreeItem):
	var path = item.get_metadata(0)
	if path and path is NodePath:
		var node = game_state.universe.get_node_or_null(path)
		if node:
			item.set_text(0,node.display_name)

func sync_metadata():
	sync_names_recursively(get_root())

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
	emit_signal('select_node',path)

func _on_Tree_item_selected():
	var path: NodePath = get_selected().get_metadata(0)
	emit_signal('select_node',path)

func _on_Tree_nothing_selected():
	emit_signal('deselect_node')
