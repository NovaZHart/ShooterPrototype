extends Panel

signal page_selected

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)

func _on_Tree_select_node(path):
	var node = game_state.systems.get_node_or_null(path)
	if node:
		var relpath = game_state.systems.get_path_to(node)
		if relpath:
			$All/Info/Bottom/Console.process_command('location '+str(relpath))

func _on_Tree_deselect_node():
	pass # Replace with function body.

func _on_StarmapPanel_deselect():
	$All/Info/Bottom/Tree.clear()

func _on_StarmapPanel_select(node):
	if node is simple_tree.SimpleNode and node.has_method('is_SystemData'):
		$All/Info/Bottom/Tree.set_system(node)
	else:
		push_warning('Invalid type received in on_StarmapPanel_select; expected SystemData')