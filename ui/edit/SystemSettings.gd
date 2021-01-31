extends TabContainer

export var remove_fleet_texture: Texture

var popup_cancel: bool = false
var system
var have_picker: bool = false setget ,get_have_picker

signal edit_complete

func get_have_picker() -> bool: return have_picker

func is_popup_visible() -> bool:
	return $Fleets/SelectFleet.visible

func cancel_popup():
	if $Fleets/SelectFleet.visible:
		popup_cancel=true
		$Fleets/SelectFleet.visible=false

# warning-ignore:shadowed_variable
func set_system(system: simple_tree.SimpleNode):
	self.system=system
	sync_system_data(true,true)
	init_fleet_list()

func select_fleet(select_id: String = '') -> String:
	var list: ItemList = $Fleets/SelectFleet/All/List
	list.clear()
	var select_index = -1
	for fleet_id in game_state.fleets.get_child_names():
		var fleet = game_state.fleets.get_child_with_name(fleet_id)
		list.add_item(fleet.display_name+' ('+fleet.name+')')
		if fleet_id == select_id:
			select_index = list.get_item_count()
	if select_index>=0:
		list.select(select_index)
		$Fleets/SelectFleet/All/Buttons/CreateFleet.disabled=false
		$Fleets/SelectFleet/All/Buttons/CreateFleet.hint_tooltip='Add this fleet to the list of spawned fleets.'
	else:
		$Fleets/SelectFleet/All/Buttons/CreateFleet.disabled=true
		$Fleets/SelectFleet/All/Buttons/CreateFleet.hint_tooltip='Select a fleet first.'
	popup_cancel = true
	$Fleets/SelectFleet.popup()
	while $Fleets/SelectFleet.visible:
		yield(get_tree(),'idle_frame')
	var selected: PoolIntArray = list.get_selected_items()
	if not len(selected):
		return ''
	return list.get_item_text(selected[0])

func sync_system_data(bkg_update: bool,meta_update: bool):
	if meta_update:
		$Settings/IDEdit.text=system.get_name()
		$Settings/NameEdit.text=system.display_name
	if bkg_update:
		$Settings/PlasmaSeedEdit.text=str(system.plasma_seed)
		$Settings/StarSeedEdit.text=str(system.starfield_seed)
		$Settings/ColorPickerButton.color=system.plasma_color

func make_fleet_entry_from_item(selected: TreeItem):
	return {
		'fleet':selected.get_text(0),
		'team':int(selected.get_text(1)),
		'frequency':int(selected.get_text(2)),
	}

func fill_item_from_fleet_entry(item: TreeItem, data: Dictionary):
	item.set_text(0,data.get('fleet','banner_ship'))
	item.set_tooltip(0,'ID of the fleet to spawn.')
	item.set_editable(0,false)
	item.set_selectable(0,true)
	item.set_text(1,str(data.get('team',0)))
	item.set_tooltip(1,'Team who owns the fleet (0 or 1 for now)')
	item.set_editable(1,true)
	item.set_text_align(1,TreeItem.ALIGN_CENTER)
	item.set_text(2,str(data.get('frequency',1200)))
	item.set_tooltip(2,'Number of times per hour this fleet spawns (randomly).')
	item.set_editable(2,true)
	item.set_text_align(2,TreeItem.ALIGN_CENTER)
	item.add_button(3,remove_fleet_texture,-1,false,'Remove this entry.')

func _process(_delta):
	if visible and $Fleets.visible:
		var spawned_size = $Fleets/Spawned.rect_size
		$Fleets/Spawned.set_column_min_width(0,40)
		$Fleets/Spawned.set_column_min_width(1,max(20,spawned_size.x*0.1))
		$Fleets/Spawned.set_column_min_width(2,max(30,spawned_size.x*0.2))
		$Fleets/Spawned.set_column_min_width(3,16)

func init_fleet_list():
	print('init fleet list')
	var tree: Tree = $Fleets/Spawned
	tree.clear()
	var root = tree.create_item()
	tree.set_column_expand(0,true)
	tree.set_column_expand(1,false)
	tree.set_column_expand(2,false)
	tree.set_column_expand(3,true)
	for fleet_data in system.fleets:
		if fleet_data==null or not fleet_data is Dictionary:
			push_error('Fleet data entry is not a dictionary: '+str(fleet_data))
			continue
		print('add item for '+str(fleet_data))
		var fleet_item: TreeItem = tree.create_item(root)
		fill_item_from_fleet_entry(fleet_item,fleet_data)

func add_spawned_fleet(index: int, data:Dictionary) -> bool:
	var tree: Tree = $Fleets/Spawned
	var item: TreeItem = tree.create_item(tree.get_root(),index)
	fill_item_from_fleet_entry(item,data)
	return true

func remove_spawned_fleet(remove_index: int) -> bool:
	print('remove spawned fleet in SystemSettings')
	var parent = $Fleets/Spawned.get_root()
	var scan = parent.get_children()
	var index = -1
	while scan:
		index += 1
		if scan==null or not scan is TreeItem:
			push_error('Got invalid type from Tree: '+str(scan))
			continue
		if index==remove_index:
			parent.remove_child(scan)
			return true
		scan = scan.get_next()
	return false

func column_of_key(key) -> int:
	if key==    'fleet':        return 0
	elif key==  'team':         return 1
	elif key==  'frequency':    return 2
	else:                       return -1

func change_fleet_data(change_index:int, key:String, value) -> bool:
	print('change fleet data in SystemSettings')
	var column = column_of_key(key)
	if column<0:
		return false
	var parent = $Fleets/Spawned.get_root()
	var scan = parent.get_children()
	var index = -1
	while scan:
		index += 1
		if scan==null or not scan is TreeItem:
			push_error('Got invalid type from Tree: '+str(scan))
			continue
		if index==change_index:
			scan.set_text(column,str(value))
			return true
		scan = scan.get_next()
	return false

func _on_NameEdit_text_entered(new_text):
	universe_edits.state.push(universe_edits.SystemDataChange.new(
		system.get_path(),{'display_name':new_text},false,true))

func _on_PlasmaSeedEdit_text_entered(new_text):
	if new_text.is_valid_integer():
		universe_edits.state.push(universe_edits.SystemDataChange.new(
			system.get_path(),{'plasma_seed':int(new_text)},true,false))
	else:
		$Settings/PlasmaSeedEdit.text=str(system.plasma_seed)
	emit_signal('edit_complete')

func _on_StarSeedEdit_text_entered(new_text):
	if new_text.is_valid_integer():
		universe_edits.state.push(universe_edits.SystemDataChange.new(
			system.get_path(),{'starfield_seed':int(new_text)},true,false))
	else:
		$Settings/StarSeedEdit.text=str(system.starfield_seed)
	emit_signal('edit_complete')

func _on_NameEdit_focus_exited():
	$Settings/NameEdit.text=system.display_name

func _on_PlasmaSeedEdit_focus_exited():
	$Settings/PlasmaSeedEdit.text=str(system.plasma_seed)

func _on_StarSeedEdit_focus_exited():
	$Settings/StarSeedEdit.text=str(system.starfield_seed)

func _on_ColorPickerButton_color_changed(color):
	return universe_edits.state.push(universe_edits.SystemDataChange.new(
			system.get_path(),{'plasma_color':color},true,false))

func _on_ColorPickerButton_focus_exited():
	$Settings/ColorPickerButton.color=system.plasma_color

func _on_ColorPickerButton_picker_created():
	have_picker=true

func _on_ColorPickerButton_popup_closed():
	have_picker=false

func _on_RandomizeSeeds_pressed():
	var changes = { 'plasma_seed':randi()%100000, 'starfield_seed':randi()%100000 }
	return universe_edits.state.push(universe_edits.SystemDataChange.new(
			system.get_path(),changes,true,false))

func index_of(parent,goal) -> int:
	var scan = parent.get_children()
	var index = -1
	while scan:
		index += 1
		if scan==null or not scan is TreeItem:
			push_error('Got invalid type from Tree: '+str(scan))
			continue
		if scan==goal:
			break;
		scan = scan.get_next()
	return index

func _on_Spawned_item_edited():
	var item = $Fleets/Spawned.get_edited()
	var index = index_of($Fleets/Spawned.get_root(),item)
	if not item or index<0:
		return
	var column = $Fleets/Spawned.get_edited_column()
	var key = 'team' if column==1 else 'frequency'
	var value = item.get_text(column)
	if value.is_valid_integer():
		universe_edits.state.push(universe_edits.SystemFleetDataChange.new(
			system.get_path(),index,key,int(value)))
	else:
		item.set_text(column,str(system.fleets[index][key]))


func _on_Spawned_button_pressed(item, _column, _id):
	var index = index_of($Fleets/Spawned.get_root(),item)
	if item and index>=0:
		universe_edits.state.push(universe_edits.SystemRemoveFleet.new(
			system.get_path(),index))
	else:
		push_error('Invalid item received when asked to remove a fleet.')


#func _on_AddFleetButton_item_selected(index):
#	var data = {
#		'fleet': $Fleets/Top/AddFleetButton.get_item_text(index),
#		'team': 0,
#		'frequency': 7200,
#	}
#	universe_edits.state.push(universe_edits.SystemAddFleet.new(
#		system.get_path(),data))


func _on_AddFleetButton_pressed():
	var selection = select_fleet('')
	while selection is GDScriptFunctionState and selection.is_valid():
		selection = yield(selection,'completed')
	if selection is String and selection:
		var data = { 'fleet': selection, 'team': 0, 'frequency': 7200, }
		universe_edits.state.push(universe_edits.SystemAddFleet.new(
			system.get_path(),data))

func _on_CreateFleet_pressed():
	popup_cancel=false
	$Fleets/SelectFleet.visible=false

func _on_Cancel_pressed():
	popup_cancel=true
	$Fleets/SelectFleet.visible=false
