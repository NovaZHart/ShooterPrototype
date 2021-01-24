extends ItemList

var starting_left: float
var starting_right: float
var starting_top: float
var starting_bottom: float
var starting_font_size: float
const min_font_size: float = 9.0

var astral_gate_targets = []

signal astral_jump
signal selectable_item_selected

func _ready():
	starting_left=margin_left
	starting_right=margin_right
	starting_top=margin_top
	starting_bottom=margin_bottom
	anchor_left=0
	anchor_right=0
	anchor_top=0
	anchor_bottom=0
	var i=0
	for node_name in game_state.systems.get_child_names():
		var system = game_state.systems.get_node(node_name)
		if not system.has_method('is_SystemData'):
			continue
		var gate_planet_path = system.astral_gate_path()
		var gate_node = game_state.systems.get_node_or_null(gate_planet_path)
		if gate_node == null:
			print('no gate in system ',node_name,' for path ',gate_planet_path)
			continue # no gate in this system
		var gate_name = gate_node.display_name
		if system.display_name==gate_name:
			add_item(system.display_name)
		else:
			add_item(gate_node.full_display_name())
		set_item_metadata(i,[node_name,gate_planet_path])
		i+=1
	update_selectability()

func update_selectability():
	for i in range(get_item_count()):
		var system_and_gate = get_item_metadata(i)
		var i_am_here = system_and_gate[0] == game_state.system.get_name() and \
			system_and_gate[1] == game_state.player_location
		print('system=',system_and_gate[0],' vs. ',game_state.system.get_name(),': ',i_am_here)
		print('gate=',system_and_gate[1],' vs. ',game_state.player_location,': ',i_am_here)
		set_item_disabled(i,i_am_here)
		set_item_selectable(i,not i_am_here)

func _process(var _delta: float) -> void:
	var window_size: Vector2 = get_tree().root.size
	var project_height: int = ProjectSettings.get_setting("display/window/size/height")
	var project_width: int = ProjectSettings.get_setting("display/window/size/width")
	var scale: Vector2 = window_size / Vector2(project_width,project_height)
	
	margin_left = floor(starting_left*scale[0])
	margin_right = ceil(starting_right*scale[0])
	margin_top = floor(starting_top*scale[1])
	margin_bottom = ceil(starting_bottom*scale[1])
	
	theme.default_font.size=max(min_font_size,14*min(scale[0],scale[1]))

func jump_to(index: int):
	unselect_all()
	emit_signal('nothing_selected')
	var system_and_gate = get_item_metadata(index)
	emit_signal('astral_jump',system_and_gate[0],system_and_gate[1])

func _on_item_activated(index: int):
	if is_item_disabled(index):
		return
	jump_to(index)

func _on_JumpButton_pressed():
	var ilist = get_selected_items()
	if ilist.empty():
		return
	jump_to(ilist[0])

func _on_item_selected(index: int):
	if is_item_selectable(index):
		emit_signal('selectable_item_selected',index)
