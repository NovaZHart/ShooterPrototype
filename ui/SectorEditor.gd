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
var mutex: Mutex = Mutex.new() # control access to systems, links, selection, last_id
var ui_scroll: float = 0

const SYSTEM_SCALE: float = 0.01
const LINK_SCALE: float = 0.005
const SELECT_EPSILON: float = 0.02

func _ready():
	link_multimesh.mesh = regular_link
	link_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	$Links.multimesh=link_multimesh
	system_multimesh.mesh = regular_system
	system_multimesh.transform_format = MultiMesh.TRANSFORM_3D
	$Systems.multimesh=system_multimesh

func _process(_delta):
#	var pos3ul: Vector3 = $Camera.project_position(Vector2(),-10)
#	var pos3lr: Vector3 = $Camera.project_position(get_viewport().size(),-10)
#	var pos2ul: Vector2 = Vector2(pos3ul.z,0,-pos3ul.x)
#	var pos2lr: Vector2 = Vector2(pos3lr.z,0,-pos3lr.x)
#	var height: float = abs(pos2ul.x-pos2lr.x)
#	var zoom: float = $Camera.size()
	var system_scale: float = SYSTEM_SCALE*$Camera.size()
	var link_scale: float = LINK_SCALE*$Camera.size()
	
	mutex.lock()
	link_data.resize(12*len(links))
	system_data.resize(12*len(systems))
	var i: int=-1
	for system in systems:
		i+=1
		var pos: Vector3 = system['position']
		system_data[i +  0] = system_scale
		system_data[i +  3] = pos.x
		system_data[i +  5] = 1.0
		system_data[i + 10] = system_scale
		system_data[i + 11] = pos.z
	system_multimesh.set_as_bulk_array(system_data)
	
	i=-1
	for link in links:
		i+=1
		var pos: Vector3 = link['position']
		var link_sin: float = link['sin']
		var link_cos: float = link['cos']
		var link_len: float = link['distance']
		link_data[i +  0] = link_cos*link_len
		link_data[i +  2] = link_sin*link_scale
		link_data[i +  3] = pos.x
		link_data[i +  5] = 1.0
		link_data[i +  8] = -link_sin*link_len
		link_data[i + 10] = link_cos*link_scale
		link_data[i + 11] = pos.z
	link_multimesh.set_as_bulk_array(link_data)
	
	if not selection:
		$Selection.visible=false
	elif selection['type']=='system':
		var pos: Vector3 = selection['position']
		$Selection.mesh = highlight_system
		$Selection.transform = Transform(Vector3(system_scale,0.0,0.0),
			Vector3(0.0,1.0,0.0),Vector3(0.0,0.0,system_scale),
			Vector3(pos.x,0.0,pos.z))
		$Selection.visible=true
	elif selection['type']=='link':
		var pos: Vector3 = selection['position']
		var link_sin: float = selection['sin']
		var link_cos: float = selection['cos']
		var link_len: float = selection['distance']/1.5+link_scale
		$Selection.mesh = highlight_link
		$Selection.transform = Transform(Vector3(link_cos*link_len,0.0,link_sin*link_scale),
			Vector3(0.0,1.0,0.0),Vector3(-link_sin*link_len,0.0,link_cos*link_scale),
			Vector3(pos.x,0.0,pos.z))
		$Selection.visible = true
	else:
		$Selection.visible=false
	# FIXME: update selection
	mutex.unlock()
	
	set_process(false)

func add_system(id: String,projected_position: Vector3) -> Dictionary:
	mutex.lock()
	var system = systems.get(id,null)
	if system!=null:
		var _discard = erase_system(system)
	system = {
		'position':projected_position, 'id':id, 'links':{},
		'distance':projected_position.length(), 'type':'system'
	}
	systems[id]=system
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
		var _discard = links.erase(link_key)
		_discard = to['links'].erase(system_id)
	var _discard = system.erase(system_id)
	if selection and selection['type']=='system' and selection['id']==system_id:
		selection=null
	mutex.unlock()
	set_process(true)
	
	return true

func erase_link(link: Dictionary) -> bool:
	var from_id = link['from_id']
	var to_id = link['to_id']
	
	mutex.lock()
	var from = systems.get(from_id,null)
	var to = systems.get(to_id,null)
	var link_key = link['link_key']
	var _discard = links.erase(link_key)
	if from:
		_discard = from['links'].erase(to_id)
	if to:
		_discard = to['links'].erase(from_id)
	if selection and selection['type']=='link' and selection['link_key']==link_key:
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
	var from_location: Vector3 = from['position']
	var to_location: Vector3 = to['position']
	
	var dist: float = from_location.distance_to(to_location)
	link = {
		'from_id':from_id, 'from_location':from_location,
		'along':to_location-from_location,
		'distance_squared':dist*dist,
		'to_id':to_id, 'to_location':to_location, 
		'position':(from_location+to_location)/2.0,
		'type':'link', 'dist':dist, 'link_key':link_key,
		'sin':-(to_location-from_location).z/dist,
		'cos':(to_location-from_location).x/dist,
	}
	links[link_key]=link
	from['links'][to_id]=link_key
	to['links'][from_id]=link_key
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

func link_distsq(p: Vector3,link: Dictionary) -> float:
	# modified from http://geomalgorithms.com/a02-_lines.html#Distance-to-Ray-or-Segment
	var p0: Vector3 = link['from_location']
	var c2: float = link['distance_squared']
	var w: Vector3 = p-p0
	if abs(c2)<1e-5: # "line segment" is actually a point
		return w.length_squared()
	var v: Vector3 = link['along']
	var c1: float = w.dot(v)
	if c1<=0:
		return v.length_squared()
	var p1: Vector3 = link['to_location']
	if c2<=c1:
		return p.distance_squared_to(p1)
	return p.distance_squared_to(p0+(c1/c2)*v)

func find_at_location(screen_location: Vector2):
	var epsilon = SELECT_EPSILON*$Camera.size()
	var pos3 = $Camera.project_position(screen_location,-10)
	pos3.y=0
#	var pos2 = Vector2(pos3.z,-pos3.x)
	var closest = null
	var close_distsq = INF
	
	mutex.lock()
	for system_id in systems:
		var system = systems.get(system_id,null)
		if not system:
			continue
		var distsq = pos3.distance_squared(system['position'])
		if distsq<close_distsq:
			close_distsq=distsq
			closest=system
	
	if close_distsq<epsilon:
		# Always favor selecting a system since they're smaller than a link.
		return closest
	
	for link_id in links:
		var link = links.get(link_id,null)
		if not link:
			continue
		var distsq = link_distsq(pos3,link)
		if distsq<close_distsq:
			close_distsq=distsq
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
			if target and target['type']=='system' and target['id']!=selection['id']:
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
		handle_select(event)
	elif event.is_action_pressed('ui_location_modify'):
		handle_modify(event)
	elif event.is_action_pressed('ui_delete') and selection:
		if selection['type']=='link':
			var _discard = erase_link(selection)
		elif selection['type']=='system':
			var _discard = erase_system(selection)
	
	var ui_zoom: int = int(Input.is_action_pressed("ui_page_up"))-int(Input.is_action_pressed("ui_page_down"))
	if Input.is_action_just_released("wheel_up"):
		ui_scroll=1.5
	if Input.is_action_just_released("wheel_down"):
		ui_scroll=-1.5
	var zoom: float = pow(0.9,ui_zoom)*pow(0.9,3*ui_scroll)
	ui_scroll*=0.7
	if abs(ui_scroll)<.05:
		ui_scroll=0
	set_zoom(zoom)
