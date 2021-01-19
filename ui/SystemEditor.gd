extends Panel

const SystemSettings: PackedScene = preload('res://ui/edit/SystemSettings.tscn')

func _ready():
	$Split/Left.set_focus_mode(Control.FOCUS_CLICK)
	$Split/Left/View/SystemView.set_system(game_state.system)
	$Split/Right/Top/Tree.set_system(game_state.system)
	$Split/Left/View.size=$Split/Left.rect_size
	$Split/Left/View/SystemView.center_view(Vector3(0.0,0.0,0.0))
	give_focus_to_view()

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

func set_panel_type(var scene) -> Control:
	if scene:
		var instance = scene.instance()
		if not instance is Control:
			push_error('Instanced scene '+str(scene.resource_path)+' is not a Control.')
		else:
			var node: Node = $Split/Right/Bottom/Settings
			$Split/Right/Bottom.remove_child(node)
			node.queue_free()
			child_fills_parent(instance)
			instance.name='Settings'
			$Split/Right/Bottom.add_child(instance)
			return instance
	var node: Node = $Split/Right/Bottom/Settings
	$Split/Right/Bottom.remove_child(node)
	node.queue_free()
	var filler: RichTextLabel = RichTextLabel.new()
	child_fills_parent(filler)
	filler.name='Settings'
	$Split/Right/Bottom.add_child(filler)
	return filler

func give_focus_to_view():
	$Split/Left.grab_focus()

func _on_SystemView_system_metadata_changed(_system):
	$Split/Right/Top/Tree.sync_metadata()

func _on_SystemView_space_background_changed(_system):
	$Split/Left/View/SystemView.update_space_background()

func _on_Tree_deselect_node():
# warning-ignore:return_value_discarded
	set_panel_type(null)

func _on_Tree_select_node(path: NodePath):
	var node = game_state.universe.get_node_or_null(path)
	if node.has_method('is_SystemData'):
		var control: Control = set_panel_type(SystemSettings)
		control.set_system(game_state.system)
		if control.connect('space_background_changed',self,'_on_SystemView_space_background_changed')!=OK:
			push_error('cannot connect space_background_changed')
		if control.connect('system_metadata_changed',self,'_on_SystemView_system_metadata_changed')!=OK:
			push_error('cannot connect system_metadata_changed')
		if control.connect('edit_complete',self,'give_focus_to_view')!=OK:
			push_error('cannot connect edit_complete')
	else:
		$Split/Left/View/SystemView.center_view(node.planet_translation(0))
# warning-ignore:return_value_discarded
		set_panel_type(null)
