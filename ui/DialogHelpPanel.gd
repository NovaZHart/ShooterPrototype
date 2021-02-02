extends Panel

signal page_selected

func _ready():
	var help = $Split/Help.get_command('help')
	if not help or not help.has_method('make_help_tree'):
		push_error('The InteractiveConsole cannot generate a help tree.')
		return
	var tree: Tree = $Split/Left/Tree
	var root: TreeItem = tree.create_item()
	var tree_info: Array = help.make_help_tree()
	var page2item: Dictionary = {}
	for page in tree_info[0]:
		var parts = page.split('/',false)
		var full: String = ''
		var parent = root
		for i in range(len(parts)):
			full += parts[i] if not full else '/'+parts[i]
			var child = page2item.get(full,null)
			if not child:
				child = tree.create_item(parent)
				child.set_text(0,tree_info[1][full])
				child.set_metadata(0,full)
				page2item[full]=child
				child.set_tooltip(0,'help '+full)
			parent=child

func _on_DialogPageSelector_page_selected(page):
	print('select page '+page)
	emit_signal('page_selected',page)


func _on_Tree_cell_selected():
	var selected = $Split/Left/Tree.get_selected()
	if not selected:
		return
	var page = selected.get_metadata(0)
	if page and page is String:
		$Split/Help.process_command('help '+page)
