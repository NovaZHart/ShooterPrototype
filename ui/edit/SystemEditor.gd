extends game_state.SystemEditorStub

const SystemSettings: PackedScene = preload('res://ui/edit/SystemSettings.tscn')
const SpaceObjectSettings: PackedScene = preload('res://ui/edit/SpaceObjectSettings.tscn')
const RESULT_NONE: int = 0
const RESULT_CANCEL: int = 1
const RESULT_ACTION: int = 02

var selected_file = null
var selection: NodePath = NodePath()
var last_space_object_tab: int = 0

var popup_result = null
var parent_path = null
var is_making = null

func _ready():
	$Split/Left.set_focus_mode(Control.FOCUS_CLICK)
	$Split/Left/View/SystemView.set_system(game_state.system)
	$Split/Right/Top/Tree.set_system(game_state.system)
	$Split/Left/View.size=$Split/Left.rect_size
	$Split/Left/View/SystemView.center_view(Vector3(0.0,0.0,0.0))
	give_focus_to_view()
	game_state.switch_editors(self)

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
	print('add space object pass through')
	$Split/Right/Top/Tree.update_system()
	$Split/Left/View/SystemView.set_system(game_state.system)
	return true

func remove_space_object(_parent: NodePath, _child) -> bool:
	$Split/Right/Top/Tree.update_system()
	$Split/Left/View/SystemView.set_system(game_state.system)
	return true

func cancel_drag() -> bool:
	return $Split/Left/View/SystemView.stop_moving()

func change_selection_to(node) -> bool:
	if node==null:
		var _discard = set_panel_type(null)
		selection = NodePath()
		$Split/Left/View/SystemView.deselect()
		$Split/Right/Top/Tree.select_node_with_path(NodePath())
	elif node.has_method('is_SystemData'):
		var control: Control = set_panel_type(SystemSettings)
		control.set_system(game_state.system)
		selection = game_state.system.get_path()
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
		$Split/Left/View/SystemView.select_and_center_view(node.get_path())
		$Split/Right/Top/Tree.select_node_with_path(node.get_path())
	return true

func _on_Left_focus_exited():
	$Split/Left/View/SystemView.lose_focus()

func _on_Left_focus_entered():
	$Split/Left/View/SystemView.gain_focus()

func _on_select_nothing():
	var from = game_state.universe.get_node_or_null($Split/Left/View/SystemView.selection)
	if from==null:
		return
	universe_edits.state.push(universe_edits.ChangeSelection.new(from,null,true))

func _on_select_space_object(path: NodePath):
	var from = game_state.universe.get_node_or_null($Split/Left/View/SystemView.selection)
	var to = game_state.universe.get_node_or_null(path)
	if (not from and not to) or (from and to and from==to):
		return
	universe_edits.state.push(universe_edits.ChangeSelection.new(from,to,true))

func _on_Tree_center_on_node(path: NodePath):
	var node = game_state.universe.get_node_or_null(path)
	if node!=null and node.has_method('is_SpaceObjectData'):
		$Split/Left/View/SystemView.select_and_center_view(node.get_path())

func save_load(save: bool) -> bool:
	if save:
		$FileDialog.mode=FileDialog.MODE_SAVE_FILE
	else:
		$FileDialog.mode=FileDialog.MODE_OPEN_FILE
	selected_file=null
	$FileDialog.popup()
	while $FileDialog.visible:
		yield(get_tree(),'idle_frame')
	if not selected_file:
		return false # canceled
	elif save:
		return game_state.save_universe_as_json(selected_file)
	elif game_state.load_universe_from_json(selected_file):
		$Split/Left/View/SystemView.clear()
		$Split/Left/View/SystemView.set_system(game_state.system)
		$Split/Right/Top/Tree.set_system(game_state.system)
		universe_edits.state.clear()
		return true
	return false

func _unhandled_input(event):
	if event.is_action_pressed('ui_undo'):
		universe_edits.state.undo()
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_redo'):
		universe_edits.state.redo()
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_editor_save'):
		save_load(true)
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_editor_load'):
		save_load(false)
		get_tree().set_input_as_handled()
	elif ($PopUp.visible or $FileDialog.visible) and event.is_action_pressed('ui_cancel'):
		if $PopUp.visible:
			_on_Cancel_pressed()
		if $FileDialog.visible:
			$FileDialog.visible=false
		get_tree().set_input_as_handled()
	elif $PopUp.visible and event.is_action_pressed('ui_accept'):
		_on_Action_pressed()
		get_tree().set_input_as_handled()

func _on_SystemView_make_new_space_object(parent_path_,is_making_):
	parent_path = parent_path_
	is_making = is_making_
	$PopUp/A/B/Action.text = 'Create'
	$PopUp/A/A/IDEdit.text = ''
	$PopUp/A/A/IDEdit.editable = true
	$PopUp/A/A/NameEdit.text = ''
	popup_result = null
	var _discard = validate_popup()
	$PopUp.popup()
	while $PopUp.visible:
		yield(get_tree(),'idle_frame')
	var result = popup_result
	if result and result['result']==RESULT_ACTION:
		is_making.set_name(result['id'])
		is_making.display_name = result['display_name']
		universe_edits.state.push(universe_edits.AddSpaceObject.new(
			parent_path,is_making))
	parent_path = null
	is_making = null
	popup_result = null

func validate_popup() -> bool:
	var info: String = ''
	if $PopUp/A/A/NameEdit.editable and not $PopUp/A/A/NameEdit.text:
		info='Enter a human-readable name to display.'
	if $PopUp/A/A/IDEdit.editable:
		if not $PopUp/A/A/IDEdit.text:
			info='Enter a space object ID'
		elif not $PopUp/A/A/IDEdit.text[0].is_valid_identifier():
			info='ID must begin with a letter or "_"'
		elif not $PopUp/A/A/IDEdit.text.is_valid_identifier():
			info='ID: only letters, numbers, "_"'
		var parent = game_state.universe.get_node_or_null(parent_path)
		var child_name = is_making.get_name()
		if parent and parent.has_child(child_name):
			info='There is already an object "'+$PopUp/A/A/IDEdit.text+'"!'
	$PopUp/A/B/Info.text=info
	$PopUp/A/B/Action.disabled = not not info
	return not info

func _on_Action_pressed():
	popup_result = {
		'id':$PopUp/A/A/IDEdit.text,
		'display_name':$PopUp/A/A/NameEdit.text,
		'result': (RESULT_ACTION if validate_popup() else RESULT_CANCEL)
	}
	$PopUp.visible=false

func _on_Cancel_pressed():
	popup_result = {
		'id':$PopUp/A/A/IDEdit.text,
		'display_name':$PopUp/A/A/NameEdit.text,
		'result': RESULT_CANCEL
	}
	$PopUp.visible=false

func _on_NameEdit_text_entered(_new_text):
	if validate_popup():
		_on_Action_pressed()

func _on_IDEdit_text_entered(_new_text):
	if validate_popup():
		_on_Action_pressed()

func _on_NameEdit_text_changed(_new_text):
	var _discard = validate_popup()

func _on_IDEdit_text_changed(_new_text):
	var _discard = validate_popup()

func _on_FileDialog_file_selected(path):
	selected_file=path
	$FileDialog.visible=false
