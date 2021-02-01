extends game_state.FleetEditorStub

export var remove_item_texture: Texture

var last_tree_selection: TreeSelection

class TreeSelection extends Object:
	var path: NodePath = NodePath()
	var ship_index: int = -1
	var column: int = 0
	func _init(tree,editor):
		if not tree or not editor:
			return # null,null => deselected settings
		var item = tree.get_selected()
		column = tree.get_selected_column()
		if not item:
			return
		var fleet_path = item.get_metadata(0)
		path = item.get_metadata(1)
		if not fleet_path:
			return
		var fleet = editor.tree_find_meta(tree.get_root(),1,fleet_path)
		if not fleet:
			path=NodePath()
			return
		ship_index = editor.tree_find_meta_index(fleet,1,path)

func _ready():
	var _discard = $H/Tree.create_item()
	$H/Tree.set_column_expand(0,false)
	fill_all_fleet_info()
	last_tree_selection = TreeSelection.new($H/Tree,self)
	$H/V/Designs.set_designs(game_state.ship_designs.get_child_names())

func _process(_delta):
	if visible:
		var spawned_size = $H/Tree.rect_size
		$H/Tree.set_column_min_width(0,clamp(spawned_size.x*0.15,40,100))

func tree_find_meta(parent: TreeItem,column: int,meta): # -> TreeItem or null
	var scan = parent.get_children()
	while scan:
		if scan==null or not scan is TreeItem:
			push_error('Got invalid type from Tree: '+str(scan))
			continue
		var scan_meta = scan.get_metadata(column)
		if scan_meta == meta:
			return scan
		scan = scan.get_next()
	print('no meta item for '+str(column)+' '+str(meta))
	return null

func tree_find_meta_index(parent: TreeItem,column: int,meta) -> int:
	var scan = parent.get_children()
	var index = -1
	while scan:
		index+=1
		if scan==null or not scan is TreeItem:
			push_error('Got invalid type from Tree: '+str(scan))
			continue
		var scan_meta = scan.get_metadata(column)
		if scan_meta == meta:
			return index
		scan = scan.get_next()
	print('no meta index for '+str(column)+' '+str(meta))
	return -1

func get_nth_child(parent: TreeItem,n: int): # -> TreeItem or null
	var scan = parent.get_children()
	var i = -1
	while scan:
		i+=1
		if scan==null or not scan is TreeItem:
			push_error('Got invalid type from Tree: '+str(scan))
			continue
		if i==n:
			return scan
		scan = scan.get_next()
	print('no nth child '+str(n))
	return null

func find_item(fleet_path: NodePath,ship_index: int=-1): # -> TreeItem or null
	var fleet_item = tree_find_meta($H/Tree.get_root(),1,fleet_path)
	if not fleet_item:
		print('no fleet item')
		return null
	return fleet_item if ship_index<0 else get_nth_child(fleet_item,ship_index)

func select_fleet(fleet_path: NodePath,ship_index: int,column: int) -> bool:
	print('select fleet')
	if not fleet_path:
		return tree_deselect()
	var item = find_item(fleet_path,ship_index)
	if item:
		print('select column')
		item.select(column)
		var _discard = show_stats(item.get_metadata(1))
		last_tree_selection = TreeSelection.new($H/Tree,self)
		return true
	print('selection failed')
	return false

func tree_deselect() -> bool:
	print('tree deselect')
	var item = $H/Tree.get_selected()
	var column = $H/Tree.get_selected_column()
	if item and column>=0:
		item.deselect(column)
		$H/V/Info.clear()
	last_tree_selection = TreeSelection.new(null,null)
	return true

func popup_has_focus() -> bool:
	return false # FIXME

func _unhandled_input(event):
	var focused = get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return # do not steal input from editors
	if popup_has_focus():
		return
	
	if event.is_action_released('ui_undo'):
		universe_edits.state.undo()
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_redo'):
		universe_edits.state.redo()
		get_tree().set_input_as_handled()
#	elif event.is_action_released('ui_editor_save'):
#		save_load(true)
#		get_tree().set_input_as_handled()
#	elif event.is_action_released('ui_editor_load'):
#		save_load(false)
#		get_tree().set_input_as_handled()

	if focused is Tree:
		return # Do not exit when deselecting in a tree
	
	if event.is_action_released('ui_cancel'):
		universe_edits.state.push(universe_edits.ExitToSector.new())
		get_tree().set_input_as_handled()

func fill_ship_info(fleet,design,design_item,design_name):
	design_item.set_text_align(0,TreeItem.ALIGN_CENTER)
	design_item.set_cell_mode(0,TreeItem.CELL_MODE_RANGE)
	design_item.set_range_config(0,1,10,1)
	design_item.set_range(0,fleet.spawn_count_for(design_name))
	design_item.set_metadata(0,fleet.get_path())
	design_item.set_editable(0,true)
	if design:
		design_item.set_metadata(1,design.get_path())
		design_item.set_text(1,design.display_name)
	else:
		design_item.set_metadata(1,NodePath())
		design_item.set_text(1,'!! Missing '+design_name+' !!')
	design_item.add_button(1,remove_item_texture,-1,false,'Remove this ship from the fleet.')

func fill_fleet_info(fleet,fleet_item):
	fleet_item.set_text(0,' ')
	fleet_item.set_text_align(0,TreeItem.ALIGN_CENTER)
	fleet_item.set_selectable(0,false)
	fleet_item.set_metadata(0,NodePath())
	fleet_item.set_text(1,fleet.display_name)
	fleet_item.set_editable(1,true)
	fleet_item.set_metadata(1,fleet.get_path())
	fleet_item.add_button(1,remove_item_texture,-1,false,'Remove this fleet.')
	for design_name in fleet.get_designs():
		var design = game_state.ship_designs.get_node_or_null(design_name)
		var design_item = $H/Tree.create_item(fleet_item)
		fill_ship_info(fleet,design,design_item,design_name)

func fill_all_fleet_info():
	var tree = $H/Tree
	var root = tree.get_root()
	for fleet_name in game_state.fleets.get_child_names():
		var fleet = game_state.fleets.get_child_with_name(fleet_name)
		if not fleet:
			continue
		var fleet_item = tree.create_item(root)
		fill_fleet_info(fleet,fleet_item)

func show_stats_from_tree() -> bool:
	var item = $H/Tree.get_selected()
	var column = $H/Tree.get_selected_column()
	if item and column>=0:
		var _discard = show_stats(item.get_metadata(1))
	else:
		$H/V/Info.clear()
	return true

func show_stats(path) -> bool:
	var node = game_state.universe.get_node_or_null(path)
	if not node:
		push_warning('Cannot show stats for missing node at path '+str(path))
	elif node.has_method('is_ShipDesign'):
		var stats = node.get_stats()
		if stats:
			$H/V/Info.clear()
			$H/V/Info.insert_bbcode(text_gen.make_ship_bbcode(stats),true)
			$H/V/Info.scroll_to_line(0)
			return true
		push_warning('ShipDesign '+str(node.get_path())+' has no stats.')
	elif node.has_method('is_Fleet'):
		$H/V/Info.clear()
		$H/V/Info.insert_bbcode(text_gen.make_fleet_bbcode(
			node.name,node.display_name,node.spawn_info),true)
		$H/V/Info.scroll_to_line(0)
		return true
	else:
		push_warning("Don't know how to show stats for "+str(node))
	return false

func _on_Designs_add():
	pass # Replace with function body.

func _on_Designs_select(design_path):
	var _discard = show_stats(design_path)

func _on_Designs_select_nothing():
	var _discard = show_stats_from_tree()

func _on_Designs_deselect(_design_path):
	_on_Designs_select_nothing()

func _on_Designs_open():
	pass # Replace with function body.

func _on_Tree_item_selected():
	print('tree item selected')
	var old = last_tree_selection
	var new: TreeSelection = TreeSelection.new($H/Tree,self)
	var _discard = show_stats_from_tree()
	universe_edits.state.push(ship_edits.ChangeFleetSelection.new(
		old.path,old.ship_index,old.column, new.path,new.ship_index,new.column))

func _on_Tree_nothing_selected():
	var old = last_tree_selection
	var _discard = show_stats_from_tree()
	universe_edits.state.push(ship_edits.ChangeFleetSelection.new(
		old.path,old.ship_index,old.column, NodePath(),-1,0))

func _on_Tree_item_edited():
	pass # Replace with function body.
