extends Panel

export var update_delay: int = 250
export var min_listed_designs: int = 4
export var default_listed_designs: int = 7
export var max_listed_designs: int = 20
export var DesignItem: PackedScene
export var show_Add: bool = true
export var show_Change: bool = true
export var show_Remove: bool = true
export var show_Open: bool = true
export var show_Cancel: bool = true

var disable_Add: bool = false setget set_disable_Add, get_disable_Add
var disable_Remove: bool = false setget set_disable_Remove, get_disable_Remove

var design_paths: Array = []
var selected_design: NodePath = NodePath() setget set_selected_design
var last_move_tick: int = 0
var last_update_tick: int = -2*update_delay
var design_mutex: Mutex = Mutex.new()

signal select_nothing
signal select
signal deselect
signal cancel
signal change
signal remove
signal add
signal open

func set_selected_design(p: NodePath):
	if p!=selected_design:
		selected_design = p

func assemble_design(): # => RigidBody or null
	assert(selected_design)
	if selected_design:
		var design = game_state.ship_designs.get_node_or_null(selected_design)
		assert(design)
		if design:
			return design.assemble_ship()
		else:
			print('no design to update')
	else:
		print('not updating design')
	return null

func set_disable_Add(disabled: bool):
	var Add = $All/Buttons.get_node_or_null('Add')
	if Add:
		Add.disabled = disabled
	disable_Add = disabled

func get_disable_Add() -> bool:
	return disable_Add

func set_disable_Remove(disabled: bool):
	var Remove = $All/Buttons.get_node_or_null('Remove')
	if Remove:
		Remove.disabled = disabled or not selected_design
	disable_Remove = disabled

func get_disable_Remove() -> bool:
	return disable_Remove

func forbid_edits():
	for button_name in [ 'Add', 'Change', 'Remove' ]:
		var button = $All/Buttons.get_node_or_null(button_name)
		if button:
			$All/Buttons.remove_child(button)
	$All/Buttons.columns = $All/Buttons.get_child_count()
	update_buttons()

func remove_ship_design(design: simple_tree.SimpleNode) -> bool:
	if not design.get_tree():
		push_error('Tried to add a ship design that had no path.')
		return false
	var design_path: NodePath = design.get_path()
	if selected_design == design_path:
		deselect()
	design_mutex.lock()
	var index = design_paths.find(design_path)
	if index>=0:
		design_paths.remove(index)
		update_designs(true,false)
	design_mutex.unlock()
	return true

func add_ship_design(design: simple_tree.SimpleNode) -> bool:
	if not design.get_tree():
		push_error('Tried to add a ship design that had no path.')
		return false
	var design_path: NodePath = design.get_path()
	design_mutex.lock()
	if design_paths.find(design_path)<0:
		design_paths.append(design_path)
		update_designs(true,false)
	design_mutex.unlock()
	return true

func update_buttons():
	for button_name in [ 'Change', 'Open' ]:
		var button = $All/Buttons.get_node_or_null(button_name)
		if button:
			button.disabled = not selected_design
	var Remove = $All/Buttons.get_node_or_null('Remove')
	if Remove:
		Remove.disabled = disable_Remove or not selected_design
	var Add = $All/Buttons.get_node_or_null('Add')
	if Add:
		Add.disabled = disable_Add
	$All/Buttons.columns = $All/Buttons.get_child_count()

func _ready():
# warning-ignore:narrowing_conversion
	min_listed_designs = min(min_listed_designs,max_listed_designs)
	$All/Buttons/Zoom.value = clamp(
		default_listed_designs,min_listed_designs,max_listed_designs)
	$All/Buttons/Zoom.min_value = min_listed_designs
	$All/Buttons/Zoom.max_value = max_listed_designs
	
	if not show_Add:
		$All/Buttons.remove_child($All/Buttons/Add)
	if not show_Change:
		$All/Buttons.remove_child($All/Buttons/Change)
	if not show_Remove:
		$All/Buttons.remove_child($All/Buttons/Remove)
	if not show_Open:
		$All/Buttons.remove_child($All/Buttons/Open)
	if not show_Cancel:
		$All/Buttons.remove_child($All/Buttons/Cancel)
	update_buttons()

func _input(event):
	if get_tree().current_scene.popup_has_focus():
		return
	var up = event.is_action_pressed('wheel_up')
	var down = event.is_action_pressed('wheel_down')
	if up or down:
		var rect: Rect2 = Rect2(rect_global_position, rect_size)
		if not rect.has_point(event_position(event)):
			return
		if down and $All/Top/Scroll.value<$All/Top/Scroll.max_value:
			$All/Top/Scroll.value+=1
		if up and $All/Top/Scroll.value>$All/Top/Scroll.min_value:
			$All/Top/Scroll.value-=1

func event_position(event: InputEvent) -> Vector2:
	# Get the best guess of the mouse position for the event.
	if event is InputEventMouseButton:
		return event.position
	return get_viewport().get_mouse_position()

func _process(_delta):
	if last_update_tick+update_delay < last_move_tick:
		update_designs(true)

func add_list_index(list,to_index,design_path,allow_add):
	assert(allow_add)
	var node = DesignItem.instance()
	for sig in [ 'deselect', 'select', 'select_nothing' ]:
		if OK!=node.connect(sig,self,'_on_DesignItem_'+sig):
			push_error('Cannot connect DesignItem signal '+sig+' to _on_DesignItem_'+sig)
	for sig in [ 'deselect', 'select', 'select_nothing' ]:
		if OK!=connect(sig,node,'_on_list_'+sig):
			push_error('Cannot connect '+sig+' signal to DesignItem _on_list_'+sig)
	$All/Top/List.add_child(node)
	var item = [node.get_path(),design_path]
	if to_index>=len(list):
		list.append(item)
	else:
		list.insert(to_index,item)
		$All/Top/List.move_child(node,to_index)
	node.set_design(design_path)
	if selected_design and selected_design==design_path:
		node.select(false)

func move_list_index(list,from_index,to_index,design_path,allow_add):
	if from_index<0:
		return add_list_index(list,to_index,design_path,allow_add)
	var node = $All/Top/List.get_child(from_index)
	var item = list[from_index]
	if from_index!=to_index:
		#$All/Top/List.remove_child(node)
		list.remove(from_index)
		$All/Top/List.move_child(node,to_index)
		list.insert(to_index,item)
		list[to_index][0]=node.get_path()
	if design_path != list[to_index][1]:
		node.set_design(design_path)
		list[to_index][1]=design_path

func find_index(design_path,to_index,designs_shown,designs_to_show) -> int:
	#var design_path = design_paths[first_design_shown+i]
	var from_index = -1
	for j in range(to_index,len(designs_shown)):
		if designs_shown[j][1]==design_path:
			return j
		elif from_index<0 and (not designs_shown[j][1] or \
				not designs_to_show.has(designs_shown[j][1])):
			from_index = j
			if not design_path:
				return j
	return from_index

func update_designs(fill_missing: bool,lock_mutex: bool = true):
	if lock_mutex:
		design_mutex.lock()
	
	var count_designs_visible: int = $All/Top/List.get_child_count()
	var first_design_shown: int = $All/Top/Scroll.value
# warning-ignore:narrowing_conversion
	first_design_shown = clamp(first_design_shown,0,len(design_paths))
	var count_designs_to_show: int = $All/Buttons/Zoom.value
	
	var designs_shown: Array = []
	for i in range(count_designs_visible):
		var node = $All/Top/List.get_child(i)
		if node and node.has_method('is_DesignItem'):
			designs_shown.append([node.get_path(), node.design_path])
		else:
			designs_shown.append([NodePath(), NodePath()])
	
	var designs_to_show: Dictionary = {}
	for i in range(count_designs_to_show):
		if len(design_paths)>first_design_shown+i:
			designs_to_show[design_paths[first_design_shown+i]]=1
	
	pass # FIXME: implement fill_missing=false
	
	for i in range(count_designs_to_show):
		var allow_add = len(designs_shown)<$All/Buttons/Zoom.value
		if len(design_paths)>first_design_shown+i:
			var design_path = design_paths[first_design_shown+i]
			var from_index = find_index(design_path,i,
				designs_shown,designs_to_show)
			move_list_index(designs_shown,from_index,i,design_path,allow_add)
		else:
			var unused_index = find_index(NodePath(),i,
				designs_shown,designs_to_show)
			move_list_index(designs_shown,unused_index,i,NodePath(),allow_add)
		pass
	
	pass
	
	for i in range(count_designs_to_show,count_designs_visible):
		var node = $All/Top/List.get_node_or_null(designs_shown[i][0])
		if node:
			$All/Top/List.remove_child(node)
	
	if fill_missing:
		last_update_tick = OS.get_ticks_msec()
	if lock_mutex:
		design_mutex.unlock()

func clear_designs():
	set_designs([])

func set_designs(new_designs):
	var new_design_paths: Array = []
	for design_spec in new_designs:
		var design = game_state.ship_designs.get_node_or_null(design_spec)
		if design:
			new_design_paths.append(design.get_path())
	design_mutex.lock()
	design_paths = new_design_paths
	$All/Top/Scroll.max_value = len(design_paths)
	update_designs(true,false)
	design_mutex.unlock()

func deselect():
	_on_DesignItem_select_nothing()

func _on_DesignItem_select_nothing():
	if selected_design:
		set_selected_design(NodePath())
		update_buttons()
		emit_signal('select_nothing')

func _on_DesignItem_deselect(path):
	if not path:
		_on_DesignItem_select_nothing()
	elif selected_design==path:
		set_selected_design(NodePath())
		update_buttons()
		emit_signal('deselect',selected_design)

func select(path: NodePath):
	_on_DesignItem_select(path)

func _on_DesignItem_select(path):
	if not path:
		_on_DesignItem_select_nothing()
	elif selected_design != path:
		selected_design = path
		update_buttons()
		emit_signal('select',selected_design)

func _on_Scroll_value_changed(_value):
	update_designs(false)
	last_move_tick = OS.get_ticks_msec()

func _on_Zoom_value_changed(value):
	$All/Top/Scroll.page = value
	update_designs(true)

func _on_DesignList_resized():
	update_designs(true)

func _on_Cancel_pressed():
	emit_signal('cancel',selected_design)

func _on_Open_pressed():
	emit_signal('open',selected_design)

func _on_Remove_pressed():
	emit_signal('remove',selected_design)

func _on_Change_pressed():
	emit_signal('change',selected_design)

func _on_Add_pressed():
	emit_signal('add',selected_design)
