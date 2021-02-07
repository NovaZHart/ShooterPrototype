extends game_state.SectorEditorStub

export var connected_color = Color(0.4,0.8,1.0)
export var highlight_color = Color(1.0,0.9,0.5)
export var system_color = Color(0.1,0.2,0.6)
export var link_color = Color(0.3,0.3,0.5)
export var system_name_color = Color(1.0,1.0,1.0,1.0)
export var min_camera_size: float = 20
export var max_camera_size: float = 400
export var label_font: Font
export var highlighted_font: Font

const MapItemShader: Shader = preload('res://ui/edit/MapItem.shader')
const StarmapLibrary: NativeScript = preload('res://bin/Starmap.gdns')
const SYSTEM_SCALE: float = 0.01
const LINK_SCALE: float = 0.005
const SELECT_EPSILON: float = 0.02

var starmap = StarmapLibrary.new()
var starmap_mutex: Mutex = Mutex.new()
var link_material: ShaderMaterial
var system_material: ShaderMaterial

var name_pool: PoolStringArray = PoolStringArray()
var pos_pool: PoolVector3Array = PoolVector3Array()
var gate_pool: PoolIntArray = PoolIntArray()
var link_pool: PoolIntArray = PoolIntArray()
var system_index: Dictionary = {}

var ui_scroll: float = 0
var last_position = null
var last_screen_position = null
var camera_start = null

signal select
signal deselect

func cancel_drag() -> bool:
	last_position=null
	last_screen_position=null
	camera_start=null
	return true

func _ready():
	game_state.switch_editors(self)

	link_material = ShaderMaterial.new()
	link_material.shader = MapItemShader
	link_material.set_shader_param('poly',2)
	starmap.set_line_material(link_material)
	
	system_material = ShaderMaterial.new()
	system_material.shader = MapItemShader
	system_material.set_shader_param('poly',4)
	starmap.set_circle_material(system_material)
	
	starmap.set_max_scale(SYSTEM_SCALE*2.0, LINK_SCALE*2.0, rect_global_position)
	starmap.set_default_visuals(system_color,link_color,system_color,label_font,
		SYSTEM_SCALE,LINK_SCALE)
		
	send_systems_to_starmap()

func _on_StarmapPanel_resized():
	starmap.set_max_scale(SYSTEM_SCALE*2.0, LINK_SCALE*2.0, rect_global_position)

func process_if(flag):
	if flag:
		update()
	return true

func send_systems_to_starmap():
	game_state.universe.lock()
	var nsystems: int = game_state.systems.get_child_count()
	var system_names: Array = game_state.systems.get_child_names()
	system_index = {}
	
	for i in range(len(system_names)):
		system_index[system_names[i]] = i
	
	name_pool.resize(nsystems)
	pos_pool.resize(nsystems)
	
	var links: Array = []
	var gates: Array = []
	
	for i in range(nsystems):
		var system_name = system_names[i]
		name_pool[i] = system_name
		var system = game_state.systems.get_child_with_name(system_name)
		if not system or not system.has_method('is_SystemData'):
			push_error('System "'+system_name+'" is in child list, but has no SystemData')
		pos_pool = system.position
		for link_name in system.links:
			var link_index = system_index.get(link_name,-1)
			if link_index<0:
				push_error('System "'+system_name+'" has a link to an undefined system "'+system_name+'"')
			links.append(i)
			links.append(link_index)
		if not system.astral_gate_path().is_empty():
			gates.append(i)
	
	gate_pool = PoolIntArray(gates)
	link_pool = PoolIntArray(links)
	
	starmap.set_systems(name_pool, pos_pool, link_pool, gate_pool)

func update_starmap_visuals():
	starmap.clear_visuals()
	if selection and selection.has_method('is_SystemData'):
		var selection_index = system_index.get(selection.name,-1)
		if selection_index>0:
			starmap.add_system_visuals(PoolIntArray([selection_index]),
				highlight_color, system_name_color, highlighted_font,
				SYSTEM_SCALE*1.5)
			starmap.add_adjacent_link_visuals(PoolIntArray([selection_index]),
				connected_color, LINK_SCALE*1.5)

func event_position(event: InputEvent) -> Vector2:
	# Get the best guess of the mouse position for the event.
	if event is InputEventMouseButton:
		return event.position
	return get_viewport().get_mouse_position()

func find_at_position(screen_position: Vector2):
	var epsilon = SELECT_EPSILON*$View/Port/Camera.size
	var pos3 = $View/Port/Camera.project_position(
		screen_position-$View.rect_global_position,-10)
	var result = starmap.system_at_location(pos3, epsilon)
	if result<0 or result>=name_pool.size():
		return null
	var system_name: String = name_pool[result]
	return game_state.systems.get_node_or_null(system_name)

func deselect(what) -> bool:
	if (what is Dictionary and selection is Dictionary and what==selection) or \
		(what is simple_tree.SimpleNode and selection is simple_tree.SimpleNode \
		and what==selection):
		selection=null
		emit_signal('deselect')
		update_starmap_visuals()
		return true
	return false

func change_selection_to(new_selection,_center: bool = false) -> bool:
	game_state.universe.lock()
	selection=new_selection
	if selection is simple_tree.SimpleNode:
		emit_signal('select',selection)
	elif selection==null:
		emit_signal('deselect')
	game_state.universe.unlock()
	update_starmap_visuals()
	return true

func set_zoom(zoom: float,focus: Vector3) -> void:
	var from: float = $View/Port/Camera.size
	var new: float = clamp(zoom*from,min_camera_size,max_camera_size)
	
	if abs(new-from)<1e-5:
		return
	
	$View/Port/Camera.size = new
	var f = new/from
	var start: Vector3 = $View/Port/Camera.translation
	var center: Vector3 = Vector3(focus.x,start.y,focus.z)
	$View/Port/Camera.translation = f*start + center*(1-f)
	starmap.update()

func _input(event):
	var top = get_viewport().get_modal_stack_top()
	if top and not in_top_dialog(self,top):
		return
	var pos2: Vector2 = event_position(event)
	if not get_global_rect().has_point(pos2):
		return
	if not is_visible_in_tree():
		return
	if event is InputEventMouseMotion and last_position:
		if Input.is_action_pressed('ui_location_slide'):
			var pos3: Vector3 = $View/Port/Camera.project_position(pos2,-10)
			if not selection:
				var pos3_start: Vector3 = $View/Port/Camera.project_position(last_screen_position,-10)
				var pos_diff = pos3_start-pos3
				pos_diff.y=0
				if pos_diff.length()>1e-3:
					$View/Port/Camera.translation = camera_start + pos_diff
					starmap.update()
		else:
			var _discard = cancel_drag()

	if event.is_action_pressed('ui_location_slide'):
		last_screen_position = pos2
		last_position = $View/Port/Camera.project_position(last_screen_position,-10)
		camera_start = $View/Port/Camera.translation
	elif event.is_action_released('ui_location_slide'):
		var _discard = cancel_drag()
	elif event.is_action_pressed('ui_location_select'):
		var target = find_at_position(pos2)
		if not target or target is simple_tree.SimpleNode:
			universe_edits.state.push(universe_edits.ChangeSelection.new(
				selection,target))
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_undo'):
		universe_edits.state.undo()
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_redo'):
		universe_edits.state.redo()
		get_tree().set_input_as_handled()
	elif event.is_action_released("wheel_up"):
		ui_scroll=1.5
		get_tree().set_input_as_handled()
	elif event.is_action_released("wheel_down"):
		ui_scroll=-1.5
		get_tree().set_input_as_handled()

func in_top_dialog(node,top) -> bool:
	if node==null:
		return false
	if node==top:
		return true
	return in_top_dialog(node.get_parent(),top)

func _process(_delta):
	var top = get_viewport().get_modal_stack_top()
	if top and not in_top_dialog(self,top):
		return
	
	var ui_zoom: int = 0
	if Input.is_action_pressed("ui_page_up"):
		ui_zoom += 1
	if Input.is_action_pressed("ui_page_down"):
		ui_zoom -= 1
	var zoom: float = pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll)
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0
	
	var pos2: Vector2 = get_viewport().get_mouse_position()
	var pos3: Vector3 = $View/Port/Camera.project_position(pos2,-10)
	set_zoom(zoom,pos3)
