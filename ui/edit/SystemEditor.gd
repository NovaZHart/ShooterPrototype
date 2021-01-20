extends Panel

const SystemSettings: PackedScene = preload('res://ui/edit/SystemSettings.tscn')
const SpaceObjectSettings: PackedScene = preload('res://ui/edit/SpaceObjectSettings.tscn')

var selection: NodePath = NodePath()

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
			var added = $Split/Right/Bottom.get_node_or_null('Settings')
			assert(added!=null)
			assert(added==instance)
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
	if node==null:
# warning-ignore:return_value_discarded
		set_panel_type(null)
		selection = NodePath()
	elif node.has_method('is_SystemData'):
		var control: Control = set_panel_type(SystemSettings)
		control.set_system(game_state.system)
		selection = game_state.system.get_path()
		if control.connect('space_background_changed',self,'_on_SystemView_space_background_changed')!=OK:
			push_error('cannot connect space_background_changed')
		if control.connect('system_metadata_changed',self,'_on_SystemView_system_metadata_changed')!=OK:
			push_error('cannot connect system_metadata_changed')
		if control.connect('edit_complete',self,'give_focus_to_view')!=OK:
			push_error('cannot connect edit_complete')
	else:
		var control: Control = set_panel_type(SpaceObjectSettings)
		assert(control is TabContainer)
		control.set_planet(node)
		selection = path
		if control.connect('surrender_focus',self,'give_focus_to_view')!=OK:
			push_error('cannot connect surrender_focus')
		$Split/Left/View/SystemView.center_view(node.planet_translation(0))

func _on_Left_focus_exited():
	$Split/Left/View/SystemView.lose_focus()

func _on_Left_focus_entered():
	$Split/Left/View/SystemView.gain_focus()

func _on_SystemView_select_nothing():
	pass # clicking nothing just drags

func _on_SystemView_select_space_object(path: NodePath):
	if not $Split/Right/Top/Tree.select_node_with_path(path):
		push_error('Cannot select path '+str(path))
