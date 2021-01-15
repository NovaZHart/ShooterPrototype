extends Spatial

export var highlight_color = Color(1.0,0.9,0.5)
export var regular_color = Color(0.2,0.4,1.0)
export var min_camera_size: float = 25
export var max_camera_size: float = 150

var highlight_link = make_box_mesh(Vector3(-0.5,0,-0.5),1,1,highlight_color)
var regular_link = make_box_mesh(Vector3(-0.5,0,-0.5),1,1,regular_color)
var link_multimesh = MultiMesh.new()
var link_data = PoolRealArray()
var links: Dictionary = {}

var highlight_system = make_circle_mesh(1.5,32,Vector3(),highlight_color)
var regular_system = make_circle_mesh(1,32,Vector3(),regular_color)
var system_multimesh = MultiMesh.new()
var system_data = PoolRealArray()
var systems: Dictionary = {}

var selection = null
var last_id = 0 # valid ids are >0
var mutex: Mutex = Mutex.new() # control access to systems, links, selection, last_id
var ui_scroll: float = 0

func _process(delta):
	if not link_multimesh.mesh:
		link_multimesh.mesh = regular_link
		link_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	if not system_multimesh:
		system_multimesh.mesh = regular_system
		system_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	
	mutex.lock()
	link_data.resize(12*links.size())
	system_data.resize(12*systems.size())
	# FIXME: update meshes
	# FIXME: update selection
	mutex.unlock()
	
	set_process(false)

func add_system(projected_position: Vector2) -> Dictionary:
	mutex.lock()
	last_id += 1
	var system = { 'position':projected_position, 'id':last_id, 'links':{} }
	systems[last_id]=system
	mutex.unlock()
	set_process(true)
	
	return system

func erase_system(system: Dictionary) -> bool:
	if system['type']!='system':
		return false
	var system_id = system['id']
	
	mutex.lock()
	for to_id in system['links']:
		var to = systems.get(to_id,null)
		if not to:
			continue
		var link_key = [system_id,to_id] if system<to_id else [to_id,system_id]
		var link = links.get(link_key,null)
		if not link:
			continue
		links.erase(link_key)
		to['links'].erase(system_id)
	system.erase(system_id)
	if selection and selection['id']==system_id:
		selection=null
	mutex.unlock()
	set_process(true)
	
	return true

func erase_link(from: Dictionary,to: Dictionary) -> bool:
	if from['type']!='system' or to['type']!='system':
		return false
	var from_id = from['id']
	var to_id = to['id']
	
	mutex.lock()
	var link_key = [from_id,to_id] if from_id<to_id else [to_id,from_id]
	var link = links.get(link_key,null)
	if not link:
		mutex.unlock()
		return false
	
	from['links'].erase(to_id)
	to['links'].erase(from_id)
	links.erase(link_key)
	if selection and selection['id']==link['id']:
		selection=null
	mutex.unlock()
	set_process(true)
	
	return true

func add_link(from: Dictionary,to: Dictionary): # -> Dictionary or null
	if from['type']!='system' or to['type']!='system':
		return null
	var from_id = from['id']
	var to_id = to['id']
	var link_key = [from_id,to_id] if from_id<to_id else [to_id,from_id]

	mutex.lock()
	var link = links.get(link_key,null)
	if link:
		mutex.unlock()
		return link
	var from_location = from['position']
	var to_location = to['position']
	
	last_id+=1
	
	link = {
		'from':from, 'from_location':from_location,
		'to':to, 'to_location':to_location,
		'type':'link', 'id':last_id,
	}
	links[link_key]=link
	from['links'][to_id]=last_id
	to['links'][from_id]=last_id
	mutex.unlock()
	set_process(true)
	
	return link

func tri_to_mesh(vertices: PoolVector3Array, color: Color) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mesh_material = SpatialMaterial.new()
	mesh_material.albedo_color = color
	mesh.surface_set_material(0,mesh_material)
	return mesh

func make_box_mesh(from: Vector3, x_span: float, z_span: float, color: Color) -> ArrayMesh:
	var vertices: PoolVector3Array = PoolVector3Array()
	vertices.resize(6)
	vertices[0] = from
	vertices[1] = from + Vector3(0,0,z_span)
	vertices[2] = from + Vector3(x_span,0,z_span)
	vertices[3] = from
	vertices[2] = from + Vector3(x_span,0,z_span)
	vertices[2] = from + Vector3(0,0,z_span)
	return tri_to_mesh(vertices,color)

func make_circle_mesh(radius: float,count: int,center: Vector3, color: Color) -> ArrayMesh:
	var vertices: PoolVector3Array = PoolVector3Array()
	vertices.resize(count*3)
	var angle = PI*2/count
	var prior = center + radius*Vector3(cos((count-1)*angle),sin((count-1)*angle),0)
	for i in range(count):
		var this = center + radius*Vector3(cos(i*angle),sin(i*angle),0)
		vertices[i*3] = prior
		vertices[i*3+1] = center
		vertices[i*3+2] = this
		prior=this
	return tri_to_mesh(vertices,color)

func event_position(event: InputEvent) -> Vector2:
	# Get the best guess of the mouse position for the event.
	if event is InputEventMouseButton:
		return event.position
	return get_viewport().get_mouse_position()

func find_at_location(screen_location: Vector2):
	var epsilon = 300.0/$Camera.size() # FIXME: test this radius
	var pos3 = $Camera.project_position(screen_location,-10)
	var pos2 = Vector2(pos3.z,-pos3.x)
	var closest = null
	var close_distsq = INF
	
	mutex.lock()
	for system_id in systems:
		var system = systems.get(system_id,null)
		if not system:
			continue
		var dist = pos2.distance_squared(system['position'])
		if dist<close_distsq:
			close_distsq=dist
			closest=system
		
	for link_id in links:
		var link = links.get(link_id,null)
		if not link:
			continue
		var dist = INF # FIXME: distance from point to line segment
		if dist<close_distsq:
			close_distsq=dist
			closest=link
	mutex.unlock()
	
	return closest if close_distsq<epsilon else null

func change_selection_to(new_selection):
	mutex.lock()
	selection=new_selection
	mutex.unlock()
	set_process(true)

func find_link(from: Dictionary,to: Dictionary):
	var link_key = [from['id'],to['id']] if from['id']<to['id'] else [to['id'],from['id']]
	return links.get(link_key,null)

func make_new_system(event: InputEvent): # -> Dictionary or null
	var screen_location: Vector2 = event_position(event)
	var pos3 = $Camera.project_position(screen_location,-10)
	var pos2 = Vector2(pos3.z,-pos3.x)
	pass # FIXME: new system dialog
	set_process(true)

func edit_system(system: Dictionary):
	pass # FIXME: system editor dialog
	set_process(true)

func handle_select(event: InputEvent):
	var pos = event_position(event)
	var target = find_at_location(pos)
	if event.shift:
		if selection and selection['type']=='system':
			if target and target['type']=='system' and target!=selection:
				return add_link(selection,target)
			elif not target and selection and selection['type']=='system':
				target = make_new_system(pos)
				if target:
					add_link(selection,target)
				return
	change_selection_to(target)

func handle_modify(event: InputEvent):
	var loc: Vector2 = event_position(event)
	var at = find_at_location(loc)
	if at:
		if selection and at['type']=='system' and selection['type']=='system':
			if at['id']==selection['id']:
				return edit_system(selection)
			var link = find_link(selection,at)
			if link:
				return change_selection_to(link)
			return add_link(selection,at)
	else:
		make_new_system(event)

func set_zoom(zoom: float,original: float=-1) -> void:
	var from: float = original if original>1 else $Camera.size
	$Camera.size = clamp(zoom*from,min_camera_size,max_camera_size)

func _unhandled_input(event):
	if event.is_action_pressed('ui_location_select'):
		return handle_select(event)
	elif event.is_action_pressed('ui_location_modify'):
		return handle_modify(event)
	
	var ui_zoom: int = int(Input.is_action_pressed("ui_page_up"))-int(Input.is_action_pressed("ui_page_down"))
	if Input.is_action_just_released("wheel_up"):
		ui_scroll=1.5
	if Input.is_action_just_released("wheel_down"):
		ui_scroll=-1.5
	var zoom: float = pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll)
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0
	var _zoom_level = set_zoom(zoom)
	
