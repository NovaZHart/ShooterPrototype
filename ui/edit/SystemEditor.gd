extends game_state.SystemEditorStub

export var IDNamePopup: PackedScene

const SystemSettings: PackedScene = preload('res://ui/edit/SystemSettings.tscn')
const SpaceObjectSettings: PackedScene = preload('res://ui/edit/SpaceObjectSettings.tscn')
const RESULT_NONE: int = 0
const RESULT_CANCEL: int = 1
const RESULT_ACTION: int = 02

var selection: NodePath = NodePath()
var last_space_object_tab: int = 0
var parent_path = null
var is_making = null
var id_name_popup_path: NodePath = NodePath()

func _exit_tree():
	universe_edits.state.disconnect('undo_stack_changed',self,'update_buttons')
	universe_edits.state.disconnect('redo_stack_changed',self,'update_buttons')
	var popup = get_viewport().get_node_or_null(id_name_popup_path)
	if popup:
		popup.queue_free()

func _enter_tree():
	game_state.game_editor_mode=true

func _ready():
	$Split/Left.set_focus_mode(Control.FOCUS_CLICK)
	$Split/Left/View/SystemView.set_system(Player.system)
	$Split/Right/Top/Tree.set_system(Player.system)
	$Split/Left/View.size=$Split/Left.rect_size
	$Split/Left/View/SystemView.center_view(Vector3(0.0,0.0,0.0))
	universe_edits.state.connect('undo_stack_changed',self,'update_buttons')
	universe_edits.state.connect('redo_stack_changed',self,'update_buttons')
	give_focus_to_view()
	game_state.switch_editors(self)
	update_buttons()

func update_buttons():
	$Split/Right/Top/Buttons/Redo.disabled = universe_edits.state.redo_stack.empty()
	$Split/Right/Top/Buttons/Undo.disabled = universe_edits.state.undo_stack.empty()

func _on_Left_resized():
	$Split/Left/View.size=$Split/Left.rect_size

func child_fills_parent(c: Control):
	c.anchor_left=0
	c.anchor_right=1
	c.anchor_top=0
	c.anchor_bottom=1
	
	c.margin_left=0
	c.margin_right=0
	c.margin_top=0
	c.margin_bottom=0
	
	c.size_flags_horizontal=Control.SIZE_FILL|Control.SIZE_EXPAND
	c.size_flags_vertical=Control.SIZE_FILL|Control.SIZE_EXPAND

func remove_old_settings():
	var node: Node = $Split/Right/Bottom/Settings
	if node.has_method('is_SpaceObjectSettings'):
		last_space_object_tab = node.current_tab
	$Split/Right/Bottom.remove_child(node)
	node.queue_free()

func set_panel_type(var scene) -> Control:
	if scene:
		var instance = scene.instance()
		if not instance is Control:
			push_error('Instanced scene '+str(scene.resource_path)+' is not a Control.')
		else:
			remove_old_settings()
			child_fills_parent(instance)
			instance.name='Settings'
			$Split/Right/Bottom.add_child(instance)
			if instance.has_method('is_SpaceObjectSettings'):
				instance.current_tab=last_space_object_tab
			var added = $Split/Right/Bottom.get_node_or_null('Settings')
			assert(added!=null)
			assert(added==instance)
			return instance
	remove_old_settings()
	var filler: RichTextLabel = RichTextLabel.new()
	child_fills_parent(filler)
	filler.name='Settings'
	$Split/Right/Bottom.add_child(filler)
	return filler

func give_focus_to_view():
	$Split/Left.grab_focus()

func _on_SystemView_request_focus():
	if get_viewport().get_modal_stack_top():
		return
	if $Split/Right/Bottom/Settings.has_method('get_have_picker') \
			and $Split/Right/Bottom/Settings.have_picker:
		return
	if $Split/Right/Bottom/Settings.has_method('is_popup_visible') and \
			$Split/Right/Bottom/Settings.is_popup_visible():
		return
	$Split/Left.grab_focus()

func update_key_system_data(path: NodePath,property: String,key,value) -> bool:
	if $Split/Right/Bottom/Settings.has_method('update_key_system_data'):
		return $Split/Right/Bottom/Settings.update_key_system_data(path,property,key,value)
	push_error('Tried to update system data when no system settings panel was present.')
	return false

func insert_system_data(path: NodePath,property: String,key,value) -> bool:
	if $Split/Right/Bottom/Settings.has_method('insert_system_data'):
		return $Split/Right/Bottom/Settings.insert_system_data(path,property,key,value)
	push_error('Tried to insert system data when no system settings panel was present.')
	return false

func remove_system_data(path: NodePath,property: String,key) -> bool:
	if $Split/Right/Bottom/Settings.has_method('remove_system_data'):
		return $Split/Right/Bottom/Settings.remove_system_data(path,property,key)
	push_error('Tried to remove system data when no system settings panel was present.')
	return false

func update_key_space_object_data(path: NodePath,property: String,key,value) -> bool:
	if $Split/Right/Bottom/Settings.has_method('update_key_space_object_data'):
		return $Split/Right/Bottom/Settings.update_key_space_object_data(path,property,key,value)
	push_error('Tried to update space object data when no system settings panel was present.')
	return false

func insert_space_object_data(path: NodePath,property: String,key,value) -> bool:
	if $Split/Right/Bottom/Settings.has_method('insert_space_object_data'):
		return $Split/Right/Bottom/Settings.insert_space_object_data(path,property,key,value)
	push_error('Tried to insert space object data when no system settings panel was present.')
	return false

func remove_space_object_data(path: NodePath,property: String,key) -> bool:
	if $Split/Right/Bottom/Settings.has_method('remove_space_object_data'):
		return $Split/Right/Bottom/Settings.remove_space_object_data(path,property,key)
	push_error('Tried to remove space object data when no system settings panel was present.')
	return false

func update_system_data(_path: NodePath,bkg_update: bool,meta_update:bool): 
	var success: bool = true
	if bkg_update or meta_update:
		if $Split/Right/Bottom.has_method('sync_system_data'):
			success = $Split/Right/Bottom.sync_system_data(bkg_update,meta_update)
	if bkg_update:
		return $Split/Left/View/SystemView.update_space_background() and success
	if meta_update:
		return $Split/Right/Top/Tree.sync_metadata() and success
	return success

func update_space_object_data(path: NodePath, basic: bool, visual: bool,
		help: bool, location: bool) -> bool:
	var success = true
	if basic:
		$Split/Right/Top/Tree.sync_metadata()
	if $Split/Right/Bottom/Settings.has_method('update_space_object_data'):
		success = $Split/Right/Bottom/Settings.update_space_object_data(
			path,basic,visual,help,location) and success
	if visual or location:
		success = $Split/Left/View/SystemView.remake_planet(path) and success
	return success

func add_space_object(_parent: NodePath, _child) -> bool:
	$Split/Right/Top/Tree.update_system()
	$Split/Left/View/SystemView.set_system(Player.system)
	return true

func remove_space_object(_parent: NodePath, _child) -> bool:
	$Split/Right/Top/Tree.update_system()
	$Split/Left/View/SystemView.set_system(Player.system)
	return true

func cancel_drag() -> bool:
	return $Split/Left/View/SystemView.stop_moving()

func change_selection_to(node,center_view: bool = false) -> bool:
	if node==null:
		var _discard = set_panel_type(null)
		selection = NodePath()
		$Split/Left/View/SystemView.deselect()
		$Split/Right/Top/Tree.select_node_with_path(NodePath())
	elif node.has_method('is_SystemData'):
		var control: Control = set_panel_type(SystemSettings)
		control.set_system(Player.system)
		selection = Player.system.get_path()
		if control.connect('edit_complete',self,'give_focus_to_view')!=OK:
			push_error('cannot connect edit_complete')
		$Split/Left/View/SystemView.deselect()
		$Split/Right/Top/Tree.select_node_with_path(node.get_path())
	else:
		var control: Control = set_panel_type(SpaceObjectSettings)
		assert(control is TabContainer)
		control.set_object(node)
		selection = node.get_path()
		if control.connect('surrender_focus',self,'give_focus_to_view')!=OK:
			push_error('cannot connect surrender_focus')
		$Split/Left/View/SystemView.change_selection_to(node.get_path(),center_view)
		$Split/Right/Top/Tree.select_node_with_path(node.get_path())
	return true

func _on_Left_focus_exited():
	$Split/Left/View/SystemView.lose_focus()

func _on_Left_focus_entered():
	$Split/Left/View/SystemView.gain_focus()

func _on_select_nothing():
	var from = game_state.systems.get_node_or_null($Split/Left/View/SystemView.selection)
	if from==null:
		return
	if not universe_edits.state.applying_rule:
		universe_edits.state.push(universe_edits.ChangeSelection.new(from,null,true))

func _on_Tree_select_space_object(path: NodePath):
	var from = game_state.systems.get_node_or_null($Split/Left/View/SystemView.selection)
	var to = game_state.systems.get_node_or_null(path)
	if (not from and not to) or (from and to and from.get_path()==to.get_path()):
		return # selection has not changed
	if not universe_edits.state.applying_rule:
		universe_edits.state.push(universe_edits.ChangeSelection.new(from,to,true,true))

func _on_System_View_select_space_object(path: NodePath):
	var from = game_state.systems.get_node_or_null($Split/Left/View/SystemView.selection)
	var to = game_state.systems.get_node_or_null(path)
	if (not from and not to) or (from and to and from.get_path()==to.get_path()):
		return # selection has not changed
	if not universe_edits.state.applying_rule:
		universe_edits.state.push(universe_edits.ChangeSelection.new(from,to,true,false))

func _on_Tree_center_on_node(path: NodePath):
	var node = game_state.systems.get_node_or_null(path)
	if node!=null and node.has_method('is_SpaceObjectData'):
		$Split/Left/View/SystemView.select_and_center_view(node.get_path())

func add_spawned_fleet(index: int, data:Dictionary) -> bool:
	if $Split/Right/Bottom/Settings.has_method('add_spawned_fleet'):
		return $Split/Right/Bottom/Settings.add_spawned_fleet(index,data)
	return true

func remove_spawned_fleet(index: int) -> bool:
	if $Split/Right/Bottom/Settings.has_method('remove_spawned_fleet'):
		return $Split/Right/Bottom/Settings.remove_spawned_fleet(index)
	return true

func change_fleet_data(index:int, key:String, value) -> bool:
	if $Split/Right/Bottom/Settings.has_method('change_fleet_data'):
		return $Split/Right/Bottom/Settings.change_fleet_data(index,key,value)
	return true

func _unhandled_input(event):
	if get_viewport().get_modal_stack_top():
		return # process nothing when a dialog is up
	
	if $Split/Right/Bottom/Settings.has_method('is_popup_visible') and \
			$Split/Right/Bottom/Settings.is_popup_visible():
		if event.is_action_released('ui_cancel'):
			$Split/Right/Bottom/Settings.cancel_popup()
			get_tree().set_input_as_handled()
		return # process nothing when a dialog is up
	
	var focused = get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return # do not steal input from editors
	
	if event.is_action_released('ui_undo'):
		_on_Undo_pressed()
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_redo'):
		_on_Redo_pressed()
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_editor_save'):
		_on_Save_pressed()
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_editor_load'):
		_on_Load_pressed()
		get_tree().set_input_as_handled()

	if focused is Tree:
		return # Do not exit when deselecting in a tree
	
	if event.is_action_released('ui_cancel'):
		_on_Sector_pressed()
		get_tree().set_input_as_handled()

func _on_SystemView_make_new_space_object(parent_path_,is_making_):
	var popup = get_viewport().get_node_or_null(id_name_popup_path)
	if popup:
		popup.visible=false
		push_error('popup already exists')
		return null
	
	parent_path = parent_path_
	is_making = is_making_
	
	popup = IDNamePopup.instance()
	popup.set_data('','','Create',true)
	get_viewport().add_child(popup)
	id_name_popup_path = popup.get_path()
	popup.popup()
	
	while popup.visible:
		yield(get_tree(),'idle_frame')
	var result = popup.result.duplicate()
	
	get_viewport().remove_child(popup)
	popup.queue_free()
	id_name_popup_path=NodePath()
	
	if result and result[0]:
		is_making.set_name(result[1])
		is_making.display_name = result[2]
		universe_edits.state.push(universe_edits.AddSpaceObject.new(
			parent_path,is_making))
	parent_path = null
	is_making = null

func _on_Sector_pressed():
	universe_edits.state.push(universe_edits.SystemEditorToSectorEditor.new())

func _on_Save_pressed():
	$Autosave.save_load(true)

func _on_Undo_pressed():
	universe_edits.state.undo()

func _on_Fleets_pressed():
	universe_edits.state.push(ship_edits.SystemEditorToFleetEditor.new())

func _on_Load_pressed():
	$Autosave.save_load(false)

func _on_Redo_pressed():
	universe_edits.state.redo()
