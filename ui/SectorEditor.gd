extends Spatial

export var connected_color = Color(0.4,0.8,1.0)
export var highlight_color = Color(1.0,0.9,0.5)
export var system_color = Color(0.1,0.2,0.6)
export var link_color = Color(0.3,0.3,0.5)
export var system_name_color = Color(1.0,1.0,1.0,1.0)
export var min_camera_size: float = 25
export var max_camera_size: float = 150
export var label_font: Font
export var highlighted_font: Font

const UniverseEditor = preload('res://ui/UniverseEditor.gd')
const MapItemShader: Shader = preload('res://ui/MapItem.shader')
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

var highlight_system: Mesh
var regular_system: Mesh
var system_multimesh = MultiMesh.new()
var system_data = PoolRealArray()
var selected_file = null

var popup_result = null
var selection = null
var ui_scroll: float = 0
var last_position = null
var last_screen_position = null
var camera_start = null
var am_moving = false
var editor
var draw_commands: Array = []
var draw_mutex: Mutex = Mutex.new()

func _init():
	editor = UniverseEditor.new()

func cancel_drag() -> bool:
	last_position=null
	last_screen_position=null
	camera_start=null
	am_moving = false
	return true

func _ready():
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
	var systems: Dictionary = game_state.universe.systems
	$Systems.visible=not not systems
	var view_rect: Rect2 = Rect2(Vector2(-20,-20),get_viewport().size+Vector2(20,20))
	var text_offset: float = abs($Camera.unproject_position(Vector3()).x - \
			$Camera.unproject_position(Vector3(system_scale,0,system_scale)).x)
	var selected_system = ''
	if selection and selection['type']=='system':
		selected_system=selection['id']
	var selected_link = ['','']
	if selection and selection['type']=='link':
		selected_link=selection['link_key']
	if systems:
		system_data.resize(16*len(systems))
		var i: int=0
		var ascent: float = label_font.get_ascent()
		for system_id in systems:
			var system: Dictionary = systems[system_id]
			var pos = system.get('position',null)
			if pos==null or not pos is Vector3:
				printerr('System ',system_id,' lacks a position.')
				continue
			pos.y=0
			var color: Color = system_color
			var font: Font = label_font
			if system_id==selected_system:
				color = highlight_color
				font = highlighted_font
			elif selected_link[0]==system_id or selected_link[1]==system_id:
				color = connected_color
				font = highlighted_font
			var pos2: Vector2 = $Camera.unproject_position(pos)
			if view_rect.has_point(pos2):
				var text_size: Vector2 = label_font.get_string_size(system['display_name'])
				new_draw_commands.append(['draw_string',font,\
					pos2+Vector2(text_offset,ascent-text_size.y/2), \
					system['display_name'],system_name_color])
			system_data[i +  0] = system_scale
			system_data[i +  1] = 0.0
			system_data[i +  2] = 0.0
			system_data[i +  3] = pos.x
			system_data[i +  4] = 0.0
			system_data[i +  5] = 1.0
			system_data[i +  6] = 0.0
			system_data[i +  7] = 0.0
			system_data[i +  8] = 0.0
			system_data[i +  9] = 0.0
			system_data[i + 10] = system_scale
			system_data[i + 11] = pos.z
			system_data[i + 12] = color.r
			system_data[i + 13] = color.g
			system_data[i + 14] = color.b
			system_data[i + 15] = color.a
			i+=16
		system_multimesh.instance_count=len(systems)
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
			link_data[i +  7] = -0.5
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
	for system_id in game_state.universe.systems:
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
	if what is Dictionary and selection==what:
		selection=null
		return true
	return false

func change_selection_to(new_selection) -> bool:
	game_state.universe.lock()
	selection=new_selection
	game_state.universe.unlock()
	set_process(true)
	return true

func validate_popup() -> bool:
	var info: String = ''
	if $PopUp/A/A/DisplayName.editable and not $PopUp/A/A/DisplayName.text:
		info='Enter a human-readable name to display.'
	if $PopUp/A/A/SystemID.editable:
		if not $PopUp/A/A/SystemID.text:
			info='Enter a system ID'
		elif game_state.universe.has_system($PopUp/A/A/SystemID.text):
			info='There is already a "'+$PopUp/A/A/SystemID.text+'" system!'
		elif not $PopUp/A/A/SystemID.text[0].is_valid_identifier():
			info='ID must begin with a letter or "_"'
		elif not $PopUp/A/A/SystemID.text.is_valid_identifier():
			info='ID: only letters, numbers, "_"'
	$PopUp/A/B/Info.text=info
	$PopUp/A/B/Action.disabled = not not info
	return not info

func make_new_system(event: InputEvent): # -> Dictionary or null
	var screen_position: Vector2 = event_position(event)
	var pos3 = $Camera.project_position(screen_position,-10)
	pos3.y=0
	$PopUp/A/B/Action.text = 'Create'
	$PopUp/A/A/SystemID.text = ''
	$PopUp/A/A/SystemID.editable = true
	$PopUp/A/A/DisplayName.text = ''
	popup_result = null
	var _discard = validate_popup()
	$PopUp.popup()
	while $PopUp.visible:
		yield(get_tree(),'idle_frame')
	var result = popup_result
	var system = null
	if result and result['result']==RESULT_ACTION:
		system = game_state.universe.add_system(result['id'],result['display_name'],pos3)
		if system and not selection:
			selection=system
	set_process(true)
	return system

func edit_system(system: Dictionary):
	$PopUp/A/B/Action.text = 'Apply'
	$PopUp/A/A/SystemID.text = system['id']
	$PopUp/A/A/SystemID.editable = false
	$PopUp/A/A/DisplayName.text = system['display_name']
	popup_result = null
	var _discard = validate_popup()
	$PopUp.popup()
	while $PopUp.visible:
		yield(get_tree(),'idle_frame')
	var result = popup_result
	if result and result['result']==RESULT_ACTION:
		var old_name = system['display_name']
		system['display_name'] = result['display_name']
		editor.state.push(editor.ChangeDisplayName.new(
			self,system['id'],old_name,result['display_name']))
	set_process(true)

func handle_select(event: InputEvent):
	var pos = event_position(event)
	var target = find_at_position(pos)
	if event.shift and selection and selection['type']=='system':
		if target and target['type']=='system' and target['id']!=selection['id']:
			var link = game_state.universe.get_link_between(selection,target)
			if link and editor.state.push(
					editor.ChangeSelection.new(self,selection,link)):
#				change_selection_to(link)
				last_position = $Camera.project_position(pos,-10)
				last_screen_position = pos
				camera_start = $Camera.translation
				am_moving = false
			return
	if selection!=target:
		editor.state.push(editor.ChangeSelection.new(self,selection,target))
#	change_selection_to(target)
	last_position = $Camera.project_position(pos,-10)
	last_screen_position = pos
	camera_start = $Camera.translation
	am_moving = false

func handle_modify(event: InputEvent):
	var loc: Vector2 = event_position(event)
	var at = find_at_position(loc)
	if at:
		if selection and at['type']=='system' and selection['type']=='system':
			if at['id']==selection['id']:
				return edit_system(selection)
			if not game_state.universe.get_link_between(selection,at):
				var link = process_if(game_state.universe.add_link(selection,at))
				if link:
					editor.state.push(editor.AddLink.new(self,link))
	elif not event.shift:
		at = make_new_system(event)
		while at is GDScriptFunctionState and at.is_valid():
			at = yield(at,'completed')
		if at:
			if selection and at!=selection and selection['type']=='system':
				process_if(game_state.universe.add_link(selection,at))
			editor.state.push(editor.AddSystem.new(self,at))

func set_zoom(zoom: float,original: float=-1) -> void:
	var from: float = original if original>1 else $Camera.size
	var new: float = clamp(zoom*from,min_camera_size,max_camera_size)
	if new!=$Camera.size:
		$Camera.size = new
		set_process(true)

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
		print('save canceled')
		return false
	if save:
		print('save to file "',selected_file,'"')
		var encoded: String = game_state.universe.encode()
		var file: File = File.new()
		if file.open(selected_file, File.WRITE):
			printerr('Cannot open file ',selected_file,'!!')
			return false
		file.store_string(encoded)
		file.close()
	else:
		print('load from file "',selected_file,'"')
		var file: File = File.new()
		if file.open(selected_file, File.READ):
			printerr('Cannot open file ',selected_file,'!!')
			return false
		var encoded: String = file.get_as_text()
		file.close()
		if game_state.universe.decode(encoded,selected_file):
			editor.state.clear()
		set_process(true)
	return true

func _input(event):
	if $PopUp.visible:
		if event.is_action_released('ui_cancel'):
			_on_Cancel_pressed()
			get_tree().set_input_as_handled()
		return # only popup gets events when visible
	elif $FileDialog.visible:
		return # only file dialog gets events when visible
	
	if event is InputEventMouseMotion and last_position:
		if Input.is_action_pressed('ui_location_select'):
			var pos2: Vector2 = event_position(event)
			var pos3: Vector3 = $Camera.project_position(pos2,-10)
			var delta: Vector3 = pos3-last_position
			if selection:
				if selection['type']=='system':
					var top = editor.state.top()
					if not top or not top is editor.MoveObject \
							or not top.object==selection:
						editor.state.push(editor.MoveObject.new(
							self,selection,'move_system'))
						top=editor.state.top()
					if process_if(game_state.universe.move_system(selection,delta)):
						editor.state.amend(delta)
				elif selection['type']=='link':
					var top = editor.state.top()
					if not top or not top is editor.MoveObject or \
							not top.object==selection:
						editor.state.push(editor.MoveObject.new(self,selection,'move_link'))
						top = editor.state.top()
					if process_if(game_state.universe.move_link(selection,delta)):
						editor.state.amend(delta)
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

	if event.is_action_pressed('ui_location_select'):
		handle_select(event)
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_location_modify'):
		handle_modify(event)
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_location_select'):
		var _discard = cancel_drag()
	elif event.is_action_pressed('ui_editor_save'):
		save_load(true)
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_editor_load'):
		save_load(false)
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_delete') and selection:
		if selection['type']=='link':
			editor.state.push(editor.EraseLink.new(self,selection))
#			var _discard = erase_link(selection)
			get_tree().set_input_as_handled()
		elif selection['type']=='system':
			editor.state.push(editor.EraseSystem.new(self,selection))
#			var _discard = erase_system(selection)
			get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_undo'):
		editor.state.undo()
		get_tree().set_input_as_handled()
	elif event.is_action_pressed('ui_redo'):
		editor.state.redo()
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

func _on_Action_pressed():
	popup_result = {
		'id':$PopUp/A/A/SystemID.text,
		'display_name':$PopUp/A/A/DisplayName.text,
		'result': (RESULT_ACTION if validate_popup() else RESULT_CANCEL)
	}
	$PopUp.visible=false

func _on_Cancel_pressed():
	popup_result = {
		'id':$PopUp/A/A/SystemID.text,
		'display_name':$PopUp/A/A/DisplayName.text,
		'result': RESULT_CANCEL
	}
	$PopUp.visible=false

func _on_SystemID_text_changed(_new_text):
	var _discard = validate_popup()

func _on_DisplayName_text_changed(_new_text):
	var _discard = validate_popup()

func _on_DisplayName_text_entered(_new_text):
	if validate_popup():
		_on_Action_pressed()

func _on_SystemID_text_entered(_new_text):
	if validate_popup():
		_on_Action_pressed()

func _on_Annotations_draw():
	draw_mutex.lock()
	var commands = draw_commands.duplicate()
	draw_mutex.unlock()
	for command in commands:
		$Annotations.callv(command[0],command.slice(1,len(command)))

func _on_FileDialog_file_selected(path):
	selected_file=path
	$FileDialog.visible=false
