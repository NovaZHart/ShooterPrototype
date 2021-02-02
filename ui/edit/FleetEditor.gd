extends game_state.FleetEditorStub

export var IDNamePopup: PackedScene
export var remove_item_texture: Texture

#var last_tree_selection: ship_edits.FleetTreeSelection
var selected_file=null
var id_name_popup_path: NodePath = NodePath()

func _enter_tree():
	game_state.game_editor_mode=true

func _exit_tree():
	game_state.switch_editors(null)
	universe_edits.state.disconnect('undo_stack_changed',self,'update_buttons')
	universe_edits.state.disconnect('redo_stack_changed',self,'update_buttons')

func _ready():
	game_state.switch_editors(self)
	var _discard = $Split/Left/Tree.create_item()
	$Split/Left/Tree.set_column_expand(0,false)
	_discard = fill_all_fleet_info()
	$Split/Right/Designs.set_designs(game_state.ship_designs.get_child_names())
	universe_edits.state.connect('undo_stack_changed',self,'update_buttons')
	universe_edits.state.connect('redo_stack_changed',self,'update_buttons')
	if game_state.fleet_tree_selection!=null:
		print('revert to saved selection')
		_discard = select_fleet(game_state.fleet_tree_selection,false)
	else:
		print('no saved selection, so construct one')
		game_state.fleet_tree_selection = ship_edits.FleetTreeSelection.new(
			$Split/Left/Tree,self)

	update_buttons()

func _process(_delta):
	if visible:
		var spawned_size = $Split/Left/Tree.rect_size
		$Split/Left/Tree.set_column_min_width(0,clamp(spawned_size.x*0.15,40,100))

func update_buttons():
	$Split/Left/Buttons/Redo.disabled = universe_edits.state.redo_stack.empty()
	$Split/Left/Buttons/Undo.disabled = universe_edits.state.undo_stack.empty()

func popup_has_focus() -> bool:
	return not id_name_popup_path.is_empty() or \
		get_viewport().get_modal_stack_top()

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

func index_for_new_item(parent: TreeItem, column: int, meta) -> int:
	var scan = parent.get_children()
	var i = -1
	while scan:
		i+=1
		if scan==null or not scan is TreeItem:
			push_error('Got invalid type from Tree: '+str(scan))
			continue
		if str(scan.get_metadata(column))>str(meta):
			return i
		scan = scan.get_next()
	return -1

func find_fleet_item(fleet_path: NodePath,ship_index: int=-1): # -> TreeItem or null
	var fleet_item = tree_find_meta($Split/Left/Tree.get_root(),1,fleet_path)
	if not fleet_item:
		print('no fleet item')
		return null
	return fleet_item if ship_index<0 else get_nth_child(fleet_item,ship_index)

func set_spawn_count(fleet_path: NodePath,design_path: NodePath,value: int) -> bool:
	var fleet_item = find_fleet_item(fleet_path,-1)
	if not fleet_item:
		push_error('There is no fleet '+str(fleet_path)+' in the fleet tree.')
		return false
	var design_item = tree_find_meta(fleet_item,1,design_path)
	if design_item:
		if value<1:
			fleet_item.remove_child(design_item)
			return true
		design_item.set_range(0,value)
		return true
	var design = game_state.ship_designs.get_node_or_null(design_path)
	if not design:
		push_error('There is no design '+str(design_path)+' in game_state.ship_designs.')
		return false
	var fleet = game_state.fleets.get_node_or_null(fleet_path)
	if not fleet:
		push_error('There is no fleet '+str(fleet_path)+' in game_state.fleets.')
		return false
	var new_index = index_for_new_item(fleet_item,1,design_path)
	design_item = $Split/Left/Tree.create_item(fleet_item,new_index)
	return fill_ship_info(fleet,design,design_item,
		design_path.get_name(design_path.get_name_count()-1))

func add_fleet(fleet: simple_tree.SimpleNode) -> bool:
	var fleet_path: NodePath = fleet.get_path()
	assert(fleet_path!=null)
	var index = index_for_new_item($Split/Left/Tree.get_root(),1,fleet_path)
	var fleet_item: TreeItem = $Split/Left/Tree.create_item($Split/Left/Tree.get_root(),index)
	return fill_fleet_info(fleet,fleet_item)

func set_fleet_display_name(fleet_path,value) -> bool:
	var fleet = find_fleet_item(fleet_path,-1)
	if not fleet:
		push_error('There is no fleet '+str(fleet_path)+' in the fleet tree.')
		return false
	fleet.set_text(2,value)
	return true

func remove_fleet(fleet_path: NodePath) -> bool:
	var item = find_fleet_item(fleet_path,-1)
	if not item:
		push_error('There is no fleet '+str(fleet_path)+' in the fleet tree.')
		return false
	$Split/Left/Tree.get_root().remove_child(item)
	return true

func select_fleet(sel: ship_edits.FleetTreeSelection,send_action=true) -> bool:
	if not sel.path:
		return tree_deselect()
	var item = find_fleet_item(sel.path,sel.ship_index)
	if item:
		item.select(sel.column)
		var _discard = show_stats(item.get_metadata(1))
		if send_action:
			game_state.fleet_tree_selection = \
				ship_edits.FleetTreeSelection.new($Split/Left/Tree,self)
		return true
	else:
		push_error('There is no fleet with path '+sel.path+' in tree.')
	return false

func tree_deselect() -> bool:
	print('tree deselect')
	var item = $Split/Left/Tree.get_selected()
	var column = $Split/Left/Tree.get_selected_column()
	if item and column>=0:
		item.deselect(column)
		$Split/Right/Info.clear()
	game_state.fleet_tree_selection = ship_edits.FleetTreeSelection.new(null,null)
	return true

func _unhandled_input(event):
	var focused = get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return # do not steal input from editors
	if popup_has_focus():
		return
	
	if event.is_action_released('ui_undo'):
		_on_Undo_pressed()
	elif event.is_action_released('ui_redo'):
		_on_Redo_pressed()
	elif event.is_action_released('ui_editor_save'):
		_on_Save_pressed()
	elif event.is_action_released('ui_editor_load'):
		_on_Load_pressed()
	if focused is Tree:
		return # Do not exit when deselecting in a tree
	
	if event.is_action_released('ui_cancel'):
		_on_System_pressed()
#		universe_edits.state.push(universe_edits.ExitToSector.new())
#		get_tree().set_input_as_handled()

func fill_ship_info(fleet,design,design_item,design_name) -> bool:
	design_item.set_text_align(0,TreeItem.ALIGN_CENTER)
	design_item.set_cell_mode(0,TreeItem.CELL_MODE_RANGE)
	design_item.set_range_config(0,1,30,1)
	design_item.set_range(0,fleet.spawn_count_for(design_name))
	var meta0: NodePath = fleet.get_path()
	assert(meta0!=null)
	design_item.set_metadata(0,meta0)
	design_item.set_editable(0,true)
	if design:
		var meta1: NodePath = design.get_path()
		assert(meta1!=null)
		design_item.set_metadata(1,meta1)
		design_item.set_text(1,design.name)
	else:
		design_item.set_metadata(1,NodePath())
		design_item.set_text(1,'!! Missing '+design_name+' !!')
	design_item.set_text(2,design.display_name)
	design_item.add_button(2,remove_item_texture,-1,false,'Remove this ship from the fleet.')
	return true

func fill_fleet_info(fleet,fleet_item) -> bool:
	fleet_item.set_text(0,'Fleet')
	fleet_item.set_text_align(0,TreeItem.ALIGN_CENTER)
	fleet_item.set_metadata(0,NodePath())
	fleet_item.set_text(1,fleet.name)
	fleet_item.set_text(2,fleet.display_name)
	fleet_item.set_editable(2,true)
	var meta1: NodePath = fleet.get_path()
	assert(meta1!=null)
	fleet_item.set_metadata(1,meta1)
	fleet_item.add_button(2,remove_item_texture,-1,false,'Remove this fleet.')
	var success=true
	var designs: Array = fleet.get_designs()
	designs.sort()
	for design_name in designs:
		var design = game_state.ship_designs.get_node_or_null(design_name)
		var design_item = $Split/Left/Tree.create_item(fleet_item)
		success = fill_ship_info(fleet,design,design_item,design_name) and success
	return success

func fill_all_fleet_info() -> bool:
	var tree = $Split/Left/Tree
	var root = tree.get_root()
	var success = true
	var fleet_names: Array = game_state.fleets.get_child_names()
	fleet_names.sort()
	for fleet_name in fleet_names:
		var fleet = game_state.fleets.get_child_with_name(fleet_name)
		if not fleet:
			continue
		var fleet_item = tree.create_item(root)
		success = fill_fleet_info(fleet,fleet_item) and success
	return success

func show_stats_from_tree() -> bool:
	var item = $Split/Left/Tree.get_selected()
	var column = $Split/Left/Tree.get_selected_column()
	if item and column>=0:
		var _discard = show_stats(item.get_metadata(1))
	else:
		$Split/Right/Info.clear()
	return true

func show_stats(path) -> bool:
	var node = game_state.universe.get_node_or_null(path)
	if not node:
		push_warning('Cannot show stats for missing node at path '+str(path))
	elif node.has_method('is_ShipDesign'):
		var stats = node.get_stats()
		if stats:
			$Split/Right/Info.clear()
			$Split/Right/Info.insert_bbcode(text_gen.make_ship_bbcode(stats),true)
			$Split/Right/Info.scroll_to_line(0)
			return true
		push_warning('ShipDesign '+str(node.get_path())+' has no stats.')
	elif node.has_method('is_Fleet'):
		$Split/Right/Info.clear()
		$Split/Right/Info.insert_bbcode(text_gen.make_fleet_bbcode(
			node.name,node.display_name,node.spawn_info),true)
		$Split/Right/Info.scroll_to_line(0)
		return true
	else:
		push_warning("Don't know how to show stats for "+str(node))
	return false

func _on_Designs_add(design_path):
	var selected_item = $Split/Left/Tree.get_selected()
	if selected_item:
		var design_item
		var fleet_path = selected_item.get_metadata(0)
		var fleet_item
		if fleet_path.is_empty():
			fleet_path = selected_item.get_metadata(1)
			fleet_item = selected_item
			design_item = tree_find_meta(fleet_item,1,design_path)
		else:
			design_item = selected_item
			fleet_item = find_fleet_item(fleet_path,-1)
		if not fleet_item:
			push_error('There is no fleet at path '+str(fleet_path)+ \
				' specified by currently selected item.')
			return
		if design_item:
			var count: int = design_item.get_range(0)+1
			print('have design item count '+str(count))
			universe_edits.state.push(ship_edits.ChangeFleetSpawnCount.new(
				fleet_path,design_path,count,true))
		else:
			universe_edits.state.push(ship_edits.ChangeFleetSpawnCount.new(
				fleet_path,design_path,1,true))
	else:
		var fleet = add_fleet_with_popup(false)
		while fleet is GDScriptFunctionState and fleet.is_valid():
			fleet = yield(fleet,'completed')
		if not fleet:
			return # popup canceled
		fleet.set_spawn(design_path.get_name(design_path.get_name_count()-1),1)
		universe_edits.state.push(ship_edits.AddFleet.new(fleet))

func _on_Designs_select(design_path):
	var _discard = show_stats(design_path)

func _on_Designs_select_nothing():
	var _discard = show_stats_from_tree()

func _on_Designs_deselect(_design_path):
	_on_Designs_select_nothing()

func _on_Designs_open(design_path):
	universe_edits.state.push(ship_edits.FleetEditorToShipEditor.new(design_path))

func _on_Tree_item_selected():
	print('tree item selected')
	var old = game_state.fleet_tree_selection
	var new = ship_edits.FleetTreeSelection.new($Split/Left/Tree,self)
	if old.same_item_as(new):
		return
	var _discard = show_stats_from_tree()
	universe_edits.state.push(ship_edits.ChangeFleetSelection.new(old, new))

func _on_Tree_nothing_selected():
	var old = game_state.fleet_tree_selection
	var _discard = show_stats_from_tree()
	var new = ship_edits.FleetTreeSelection.new(null,null)
	universe_edits.state.push(ship_edits.ChangeFleetSelection.new(old,new))

func _on_Tree_item_edited():
	var item = $Split/Left/Tree.get_selected()
	var column = $Split/Left/Tree.get_selected_column()
	if item.get_metadata(0).is_empty() and column==2:
		universe_edits.state.push(ship_edits.ChangeFleetDisplayName.new(
			item.get_metadata(1),item.get_text(2)))
	elif column==0:
		universe_edits.state.push(ship_edits.ChangeFleetSpawnCount.new(
			item.get_metadata(0),item.get_metadata(1),item.get_range(0),false))

func _on_Tree_button_pressed(item, _column, _id):
	var fleet_path: NodePath = item.get_metadata(0)
	var item_path: NodePath = item.get_metadata(1)
	if fleet_path.is_empty():
		var index = tree_find_meta_index($Split/Left/Tree.get_root(),1,item_path)
		universe_edits.state.push(ship_edits.RemoveFleet.new(item_path,index))
	else:
		var parent = find_fleet_item(fleet_path,-1)
		if not parent:
			push_error('cannot find fleet parent at path '+str(fleet_path))
		else:
			parent.remove_child(item)
			universe_edits.state.push(ship_edits.ChangeFleetSpawnCount.new(
				fleet_path,item_path,int(item.get_text(0)),false))

func add_fleet_with_popup(send_edit: bool):
	var id_name_popup = get_node_or_null(id_name_popup_path)
	if id_name_popup:
		print('popup is up; close it')
		id_name_popup=false
		return
	
	id_name_popup = IDNamePopup.instance()
	id_name_popup.set_used_ids(game_state.fleets.get_child_names())
	get_viewport().add_child(id_name_popup)
	id_name_popup_path = id_name_popup.get_path()
	id_name_popup.popup()
	
	while id_name_popup.visible:
		yield(get_tree(),'idle_frame')
	
	var fleet = null
	if id_name_popup.result[0]:
		fleet = game_state.universe.Fleet.new(id_name_popup.result[2])
		fleet.name = id_name_popup.result[1]
		if send_edit:
			universe_edits.state.push(ship_edits.AddFleet.new(fleet))
	
	id_name_popup_path = NodePath()
	id_name_popup.queue_free()
	return fleet

func _on_AddFleet_pressed():
	var _discard = add_fleet_with_popup(true)

func _on_Save_pressed():
	$Autosave.save_load(true)
	get_tree().set_input_as_handled()

func _on_Load_pressed():
	$Autosave.save_load(false)
	get_tree().set_input_as_handled()

func _on_Undo_pressed():
	universe_edits.state.undo()
	get_tree().set_input_as_handled()

func _on_Redo_pressed():
	universe_edits.state.redo()
	get_tree().set_input_as_handled()

func _on_System_pressed():
	universe_edits.state.push(ship_edits.FleetEditorToSystemEditor.new())
