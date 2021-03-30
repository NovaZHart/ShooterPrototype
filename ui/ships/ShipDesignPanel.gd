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
var hover_design: NodePath
var design_paths: Array = []
var selected_design: NodePath = NodePath() setget set_selected_design
var last_move_tick: int = 0
var last_update_tick: int = -2*update_delay
var design_mutex: Mutex = Mutex.new()

signal hover_over_design
signal select_nothing
signal select
signal deselect
signal cancel
signal change
signal remove
signal activate
signal add
signal open
signal child_select_nothing
signal child_select
signal child_deselect

func set_selected_design(p: NodePath):
	if p!=selected_design:
		selected_design = p

func assemble_design(design_path=null): # => RigidBody or null
	var design_to_assemble = design_path
	if not design_to_assemble:
		design_to_assemble=selected_design
	if design_to_assemble:
		var design = game_state.ship_designs.get_node_or_null(design_to_assemble)
		assert(design)
		if design:
			return design.assemble_ship()
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
		deselect_impl()
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
	if not is_visible_in_tree():
		return
	var up = event.is_action_pressed('wheel_up')
	var down = event.is_action_pressed('wheel_down')
	if up or down:
		var rect: Rect2 = Rect2($All/Top/List.rect_global_position, $All/Top/List.rect_size)
		if not rect.has_point(utils.event_position(event)):
			return
		if down and $All/Top/Scroll.value<$All/Top/Scroll.max_value:
			$All/Top/Scroll.value+=1
		if up and $All/Top/Scroll.value>$All/Top/Scroll.min_value:
			$All/Top/Scroll.value-=1
		for child in $All/Top/List.get_children():
			child.update_hovering(event)

func update_hovering(event=null):
	var pos = utils.event_position(event)
	var new_hover: NodePath
	for child in $All/Top/List.get_children():
		if child.get_global_rect().has_point(pos):
			new_hover=child.design_path
		#child.update_hovering(event)
	if hover_design!=new_hover:
		hover_design=new_hover
		emit_signal('hover_over_design',hover_design)

func _process(_delta):
	if last_update_tick+update_delay < last_move_tick:
		update_designs(true)
		update_hovering()

func add_list_index(list,to_index,design_path,allow_add):
	assert(allow_add)
	var node = DesignItem.instance()
	for sig in [ 'deselect', 'select', 'select_nothing', 'hover_start', 'hover_end', 'activate' ]:
		if OK!=node.connect(sig,self,'_on_DesignItem_'+sig):
			push_error('Cannot connect DesignItem signal '+sig+' to _on_DesignItem_'+sig)
	for sig in [ 'deselect', 'select', 'select_nothing' ]:
		if OK!=connect('child_'+sig,node,'_on_list_'+sig):
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
		var should_select = selected_design and selected_design==design_path
		if node.selected != should_select:
			return node.select(false) if should_select else node.deselect(false)

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

func refresh():
	design_mutex.lock()
	for child in $All/Top/List.get_children():
		child.refresh()
	design_mutex.unlock()

class NodePathSorter extends Reference:
	func sort(a,b):
		return str(a)<str(b)

func update_designs(fill_missing: bool,lock_mutex: bool = true):
	if lock_mutex:
		design_mutex.lock()
	
	design_paths.sort_custom(NodePathSorter.new(),'sort')
	
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
	
	pass # FIXME: implement fill_missing=false?
	
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

func deselect(send_signal: bool = false):
	deselect_impl(NodePath(),send_signal)

func deselect_impl(path: NodePath = NodePath(), send_signal: bool = true):
	if not path:
		set_selected_design(NodePath())
		update_buttons()
		emit_signal('child_select_nothing')
		if send_signal:
			emit_signal('select_nothing')
		call_deferred('refresh')
	elif selected_design==path:
		set_selected_design(NodePath())
		update_buttons()
		emit_signal('child_deselect',selected_design)
		if send_signal:
			emit_signal('deselect',selected_design)
		call_deferred('refresh')

func _on_DesignItem_hover_start(_design_path):
	update_hovering() # emit_signal('hover_over_design',design_path)

func _on_DesignItem_hover_end(_design_path):
	update_hovering() # emit_signal('hover_over_design',null)

func _on_DesignItem_select_nothing():
	deselect_impl()

func _on_DesignItem_deselect(path):
	deselect_impl(path)

func _on_DesignItem_activate(design):
	if design==selected_design:
		emit_signal('activate',selected_design)

func select(path: NodePath, send_signal: bool = true):
	if not path:
		deselect_impl(path,send_signal)
	elif selected_design != path:
		selected_design = path
		update_buttons()
		emit_signal('child_select',selected_design)
		if send_signal:
			emit_signal('select',selected_design)

func _on_DesignItem_select(path):
	select(path)

func _on_Scroll_value_changed(_value):
	update_designs(false)
	call_deferred('refresh')
	last_move_tick = OS.get_ticks_msec()

func _on_Zoom_value_changed(value):
	$All/Top/Scroll.page = value
	update_designs(true)
	call_deferred('refresh')
	last_move_tick = OS.get_ticks_msec()

func _on_DesignList_resized():
	update_designs(true)
	call_deferred('refresh')
	last_move_tick = OS.get_ticks_msec()

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
