extends game_state.SectorEditorStub

#extends Spatial

export var IDNamePopup: PackedScene
export var connected_color = Color(0.4,0.8,1.0)
export var highlight_color = Color(1.0,0.9,0.5)
export var system_color = Color(0.1,0.2,0.6)
export var link_color = Color(0.3,0.3,0.5)
export var system_name_color = Color(1.0,1.0,1.0,1.0)
export var min_camera_size: float = 25
export var max_camera_size: float = 150
export var label_font: Font
export var highlighted_font: Font

const MapItemShader: Shader = preload('res://ui/edit/MapItem.shader')
const RESULT_NONE: int = 0
const RESULT_CANCEL: int = 1
const RESULT_ACTION: int = 02
const SYSTEM_SCALE: float = 0.01
const LINK_SCALE: float = 0.005
const SELECT_EPSILON: float = 0.02

var highlight_link: Mesh
var regular_link: Mesh
var link_multimesh = MultiMesh.new()
var link_data = PoolRealArray()
var exit_confirmed = false
var highlight_system: Mesh
var regular_system: Mesh
var system_multimesh = MultiMesh.new()
var system_data = PoolRealArray()

var ui_scroll: float = 0
var last_position = null
var last_screen_position = null
var camera_start = null
var am_moving = false
var draw_commands: Array = []
var draw_mutex: Mutex = Mutex.new()

var id_name_popup_path: NodePath = NodePath()

func _exit_tree():
	game_state.game_editor_mode=false
	var popup = get_viewport().get_node_or_null(id_name_popup_path)
	if popup:
		popup.queue_free()

func cancel_drag() -> bool:
	last_position=null
	last_screen_position=null
	camera_start=null
	am_moving = false
	return true

func _enter_tree():
	game_state.game_editor_mode=true

func _ready():
	game_state.switch_editors(self)
	highlight_link = make_box_mesh(Vector3(-0.5,-0.5,-0.5),0.5,0.5,2,2)
	regular_link = make_box_mesh(Vector3(-0.5,-0.5,-0.5),0.5,0.5,2,2)
	highlight_system = make_circle_mesh(1.5,32,Vector3())
	regular_system = make_circle_mesh(1,32,Vector3())

	var link_material = ShaderMaterial.new()
	link_material.shader = MapItemShader
	link_material.set_shader_param('poly',2)
	link_multimesh.mesh = regular_link
	link_multimesh.mesh.surface_set_material(0,link_material)
	link_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	link_multimesh.custom_data_format = MultiMesh.CUSTOM_DATA_FLOAT
	link_multimesh.visible_instance_count = 0
	$Links.multimesh=link_multimesh
	
	var system_material = ShaderMaterial.new()
	system_material.shader = MapItemShader
	system_material.set_shader_param('poly',4)
	system_multimesh.mesh = regular_system
	system_multimesh.mesh.surface_set_material(0,system_material)
	system_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	system_multimesh.custom_data_format = MultiMesh.CUSTOM_DATA_FLOAT
	system_multimesh.visible_instance_count = 0
	$Systems.multimesh=system_multimesh
	$RichTextLabel.set_process_input(false)
	$RichTextLabel.set_process_unhandled_input(false)
	$RichTextLabel.set_process_unhandled_key_input(false)
	
	var v = get_viewport()
	if v:
		var _discard = v.connect('size_changed',self,'set_process',[true])

func process_if(flag):
	if flag:
		set_process(true)
	return flag

func _process(_delta):
	var system_scale: float = SYSTEM_SCALE*$Camera.size
	var link_scale: float = LINK_SCALE*$Camera.size
	
	var new_draw_commands: Array = []

	game_state.universe.lock()
	$Systems.visible=game_state.systems.has_children()
	var view_rect: Rect2 = Rect2(Vector2(-20,-20),get_viewport().size+Vector2(20,20))
	var text_offset: float = abs($Camera.unproject_position(Vector3()).x - \
			$Camera.unproject_position(Vector3(system_scale,0,system_scale)).x)
	var selected_system = ''
	var child_names = game_state.systems.get_child_names()
	if selection and selection is simple_tree.SimpleNode:
		selected_system=selection.get_name()
	var selected_link = ['','']
	if selection is Dictionary:
		selected_link=selection['link_key']
	if game_state.systems.has_children():
		system_data.resize(16*len(child_names))
		var i: int=0
		var ascent: float = label_font.get_ascent()
		for system_id in child_names:
			var system = game_state.systems.get_child_with_name(system_id)
			assert(system is simple_tree.SimpleNode)
			var color: Color = system_color
			var font: Font = label_font
			if system_id==selected_system:
				color = highlight_color
				font = highlighted_font
			elif selected_link[0]==system_id or selected_link[1]==system_id:
				color = connected_color
				font = highlighted_font
			var pos2: Vector2 = $Camera.unproject_position(system.position)
			if view_rect.has_point(pos2):
				var text_size: Vector2 = label_font.get_string_size(system['display_name'])
				new_draw_commands.append(['draw_string',font,\
					pos2+Vector2(text_offset,ascent-text_size.y/2), \
					system['display_name'],system_name_color])
			system_data[i +  0] = system_scale
			system_data[i +  1] = 0.0
			system_data[i +  2] = 0.0
			system_data[i +  3] = system.position.x
			system_data[i +  4] = 0.0
			system_data[i +  5] = 1.0
			system_data[i +  6] = 0.0
			system_data[i +  7] = 0.0
			system_data[i +  8] = 0.0
			system_data[i +  9] = 0.0
			system_data[i + 10] = system_scale
			system_data[i + 11] = system.position.z
			system_data[i + 12] = color.r
			system_data[i + 13] = color.g
			system_data[i + 14] = color.b
			system_data[i + 15] = color.a
			i+=16
		system_multimesh.instance_count=len(child_names)
		system_multimesh.visible_instance_count=-1
		system_multimesh.set_as_bulk_array(system_data)
	
	var links: Dictionary = game_state.universe.links
	$Links.visible=not not links
	if links:
		link_data.resize(16*len(links))
		var i: int = 0
		for link_key in links:
			var link = game_state.universe.link_sin_cos(link_key)
			
			var pos: Vector3 = link['position']
			var link_sin: float = link['sin']
			var link_cos: float = link['cos']
			var link_len: float = link['distance']
			var color: Color = link_color
			if link_key==selected_link:
				color=highlight_color
			elif link_key[0]==selected_system or link_key[1]==selected_system:
				color=connected_color
			link_data[i +  0] = link_cos*link_len
			link_data[i +  1] = 0.0
			link_data[i +  2] = link_sin*link_scale
			link_data[i +  3] = pos.x
			link_data[i +  4] = 0.0
			link_data[i +  5] = 1.0
			link_data[i +  6] = 0.0
			link_data[i +  7] = 0.0
			link_data[i +  8] = -link_sin*link_len
			link_data[i +  9] = 0.0
			link_data[i + 10] = link_cos*link_scale
			link_data[i + 11] = pos.z
			link_data[i + 12] = color.r
			link_data[i + 13] = color.g
			link_data[i + 14] = color.b
			link_data[i + 15] = color.a
			i+=16
		link_multimesh.instance_count=len(links)
		link_multimesh.visible_instance_count=-1
		link_multimesh.set_as_bulk_array(link_data)
	game_state.universe.unlock()

	draw_mutex.lock()
	draw_commands=new_draw_commands
	draw_mutex.unlock()
	$Annotations.update()

	set_process(false)

func tri_to_mesh(vertices: PoolVector3Array, uv: PoolVector2Array) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_TEX_UV] = uv
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func make_box_mesh(from: Vector3, x_step: float, z_step: float, nx: int, nz: int) -> ArrayMesh:
	var vertices: PoolVector3Array = PoolVector3Array()
	var uv: PoolVector2Array = PoolVector2Array()
	vertices.resize(nx*nz*6)
	uv.resize(nx*nz*6)
	
	var i: int = 0
	for zi in range(nz):
		for xi in range(nx):
			var p00 = from+Vector3(xi*x_step,0,zi*z_step)
			var p11 = from+Vector3((xi+1)*x_step,0,(zi+1)*z_step)
			var p01 = Vector3(p00.x,from.y,p11.z)
			var p10 = Vector3(p11.x,from.y,p00.z)
			var u00 = Vector2(zi/float(nz),(nx-xi)/float(nx))
			var u11 = Vector2((zi+1)/float(nz),(nx-xi-1)/float(nx))
			var u01 = Vector2(u11.x,u00.y)
			var u10 = Vector2(u00.x,u11.y)
			vertices[i + 0] = p00
			uv      [i + 0] = u00
			vertices[i + 1] = p11
			uv      [i + 1] = u11
			vertices[i + 2] = p01
			uv      [i + 2] = u01
			vertices[i + 3] = p00
			uv      [i + 3] = u00
			vertices[i + 4] = p10
			uv      [i + 4] = u10
			vertices[i + 5] = p11
			uv      [i + 5] = u11
			i+=6

	return tri_to_mesh(vertices,uv)

func make_circle_mesh(radius: float,count: int,center: Vector3) -> ArrayMesh:
	var vertices: PoolVector3Array = PoolVector3Array()
	var uv: PoolVector2Array = PoolVector2Array()
	vertices.resize(count*3)
	uv.resize(count*3)
	var angle = PI*2/count
	var prior = center + radius*Vector3(cos((count-1)*angle),0,sin((count-1)*angle))
	for i in range(count):
		var this = center + radius*Vector3(cos(i*angle),0,sin(i*angle))
		vertices[i*3 + 0] = center
		uv      [i*3 + 0] = Vector2(0.5,i/float(count))
		vertices[i*3 + 1] = prior
		uv      [i*3 + 1] = Vector2(1.0,i/float(count))
		vertices[i*3 + 2] = this
		uv      [i*3 + 2] = Vector2(1.0,(i+1)/float(count))
		prior=this
	return tri_to_mesh(vertices,uv)

func event_position(event: InputEvent) -> Vector2:
	# Get the best guess of the mouse position for the event.
	if event is InputEventMouseButton:
		return event.position
	return get_viewport().get_mouse_position()

func find_at_position(screen_position: Vector2):
	var epsilon = SELECT_EPSILON*$Camera.size
	var pos3 = $Camera.project_position(screen_position,-10)
	pos3.y=0
#	var pos2 = Vector2(pos3.z,-pos3.x)
	var closest = null
	var close_distsq = INF
	
	game_state.universe.lock()
	for system_id in game_state.systems.get_child_names():
		var system = game_state.universe.get_system(system_id)
		if not system:
			continue
		var distsq = pos3.distance_squared_to(system['position'])
		if distsq<close_distsq:
			close_distsq=distsq
			closest=system
	
	if close_distsq<epsilon:
		# Always favor selecting a system since they're smaller than a link.
		game_state.universe.unlock()
		return closest
	
	for link_key in game_state.universe.links:
		var link = game_state.universe.link_vectors(link_key)
		if not link:
			continue
		var distsq = game_state.universe.link_distsq(pos3,link)
		if distsq<close_distsq:
			close_distsq=distsq
			closest=link
	game_state.universe.unlock()
	
	return closest if close_distsq<epsilon else null

func deselect(what) -> bool:
	if (what is Dictionary and selection is Dictionary and what==selection) or \
		(what is simple_tree.SimpleNode and selection is simple_tree.SimpleNode \
		and what==selection):
		selection=null
		return true
	return false

func change_selection_to(new_selection,_center: bool = false) -> bool:
	game_state.universe.lock()
	selection=new_selection
	game_state.universe.unlock()
	set_process(true)
	return true

func make_new_system(event: InputEvent): # -> SimpleNode or null
	var popup = get_viewport().get_node_or_null(id_name_popup_path)
	if popup:
		popup.visible=false
		push_error('popup already exists')
		return null
	
	var screen_position: Vector2 = event_position(event)
	var pos3 = $Camera.project_position(screen_position,-10)
	pos3.y=0
	
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

	var system = null
	if result and result[0]:
		system = game_state.universe.add_system(result[1],result[2],pos3)
		if system and not selection:
			selection=system
	set_process(true)
	return system


func edit_system(system):
	universe_edits.state.push(universe_edits.EnterSystemFromSector.new(system.get_path()))

func handle_select(event: InputEvent):
	var pos = event_position(event)
	var target = find_at_position(pos)
	if event.shift and selection is simple_tree.SimpleNode:
		if target is simple_tree.SimpleNode and target.get_name()!=selection.get_name():
			var link = game_state.universe.get_link_between(selection,target)
			if link and universe_edits.state.push(
					universe_edits.ChangeSelection.new(selection,link)):
#				change_selection_to(link)
				last_position = $Camera.project_position(pos,-10)
				last_screen_position = pos
				camera_start = $Camera.translation
				am_moving = false
			return
	if typeof(selection)!=typeof(target) or selection!=target:
		universe_edits.state.push(universe_edits.ChangeSelection.new(selection,target))
#	change_selection_to(target)
	last_position = $Camera.project_position(pos,-10)
	last_screen_position = pos
	camera_start = $Camera.translation
	am_moving = false

func handle_modify(event: InputEvent):
#	if not selection is simple_tree.SimpleNode:
#		return
	var loc: Vector2 = event_position(event)
	var at = find_at_position(loc)
	if at:
		if selection and at is simple_tree.SimpleNode:
			if at.get_name()==selection.get_name():
				return edit_system(selection)
			if not game_state.universe.get_link_between(selection,at):
				var link = process_if(game_state.universe.add_link(selection,at))
				if link:
					universe_edits.state.push(universe_edits.AddLink.new(link))
	elif not event.shift:
		at = make_new_system(event)
		while at is GDScriptFunctionState and at.is_valid():
			at = yield(at,'completed')
		if at:
			if selection is simple_tree.SimpleNode and at!=selection:
				process_if(game_state.universe.add_link(selection,at))
			universe_edits.state.push(universe_edits.AddSystem.new(at))

func set_zoom(zoom: float,original: float=-1) -> void:
	var from: float = original if original>1 else $Camera.size
	var new: float = clamp(zoom*from,min_camera_size,max_camera_size)
	if new!=$Camera.size:
		$Camera.size = new
		set_process(true)

func _unhandled_input(event):
	# Ignore events if a popup is popped up
	if get_viewport().get_modal_stack_top():
		return
	if event is InputEventMouseMotion and last_position:
		if Input.is_action_pressed('ui_location_select'):
			var pos2: Vector2 = event_position(event)
			var pos3: Vector3 = $Camera.project_position(pos2,-10)
			var delta: Vector3 = pos3-last_position
			if selection:
				if selection is simple_tree.SimpleNode:
					var top = universe_edits.state.top()
					if not top or not top is universe_edits.MoveObject \
							or not top.object==selection:
						universe_edits.state.push(universe_edits.MoveObject.new(
							selection,'move_system'))
						top=universe_edits.state.top()
					if process_if(game_state.universe.move_system(selection,delta)):
						universe_edits.state.amend(delta)
				elif selection is Dictionary:
					var top = universe_edits.state.top()
					if not top or not top is universe_edits.MoveObject or \
							not top.object==selection:
						universe_edits.state.push(universe_edits.MoveObject.new(selection,'move_link'))
						top = universe_edits.state.top()
					if process_if(game_state.universe.move_link(selection,delta)):
						universe_edits.state.amend(delta)
				last_position=pos3
			else:
				var pos3_start: Vector3 = $Camera.project_position(last_screen_position,-10)
				var pos_diff = pos3_start-pos3
				pos_diff.y=0
				if pos_diff.length()>1e-3:
					$Camera.translation = camera_start + pos_diff
					set_process(true)
		else:
			last_position=null

	if event.is_action_released('ui_cancel'):
		if universe_edits.state.activity:
			exit_confirmed=false
			$ConfirmationDialog.popup()
			while $ConfirmationDialog.visible:
				yield(get_tree(),'idle_frame')
		else:
			exit_confirmed=true
		if exit_confirmed:
			universe_edits.state.clear()
			var _discard = game_state.change_scene('res://ui/OrbitalScreen.tscn')
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_location_select'):
		handle_select(event)
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_location_modify'):
		handle_modify(event)
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_location_select'):
		var _discard = cancel_drag()
	elif event.is_action_released('ui_editor_save'):
		$Autosave.save_load(true)
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_editor_load'):
		$Autosave.save_load(false)
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_delete') and selection:
		if selection is Dictionary:
			universe_edits.state.push(universe_edits.EraseLink.new(selection))
#			var _discard = erase_link(selection)
			get_tree().set_input_as_handled()
		elif selection is simple_tree.SimpleNode:
			universe_edits.state.push(universe_edits.EraseSystem.new(selection))
#			var _discard = erase_system(selection)
			get_tree().set_input_as_handled()
	elif event.is_action_released('ui_undo'):
		universe_edits.state.undo()
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_redo'):
		universe_edits.state.redo()
		get_tree().set_input_as_handled()
	
	var ui_zoom: int = 0
	if Input.is_action_pressed("ui_page_up"):
		ui_zoom += 1
		get_tree().set_input_as_handled()
	if Input.is_action_pressed("ui_page_down"):
		ui_zoom -= 1
		get_tree().set_input_as_handled()
	if Input.is_action_just_released("wheel_up"):
		ui_scroll=1.5
		get_tree().set_input_as_handled()
	if Input.is_action_just_released("wheel_down"):
		ui_scroll=-1.5
		get_tree().set_input_as_handled()
	var zoom: float = pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll)
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0
	set_zoom(zoom)

func _on_Annotations_draw():
	draw_mutex.lock()
	var commands = draw_commands.duplicate()
	draw_mutex.unlock()
	for command in commands:
		$Annotations.callv(command[0],command.slice(1,len(command)))

func _on_ConfirmationDialog_confirmed():
	exit_confirmed = true
