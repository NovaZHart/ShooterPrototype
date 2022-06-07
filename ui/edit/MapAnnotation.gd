extends Spatial

const MapAnnotationShader: Shader = preload('res://shaders/MapAnnotation.shader')
const AnnulusShader: Shader = preload('res://shaders/Annulus.shader')
const annotation3d_thickness: float = 2.0

var object_path: NodePath = NodePath()
var draw_color: Color = Color(0.7,0.7,0.7,0.3) setget set_draw_color
var orbit_radius: float = 1.0
var orbit_center: Vector3 = Vector3()
var position: Vector3 = Vector3()
var valid: bool = false

func make_invalid():
	valid=false
	orbit_radius=1.0
	orbit_center=Vector3()
	position=Vector3()
	$Orbit.visible=false
	$Radius.visible=false

func update_from_spec(new_u_scale: float,new_color: Color,new_position: Vector3,
		new_center: Vector3):
	orbit_center = new_center
	orbit_center.y = 0
	position = new_position
	position.y = 0
	orbit_radius = orbit_center.distance_to(position)
	draw_color = new_color
	var t: float = annotation3d_thickness
	if orbit_radius<annotation3d_thickness:
		make_invalid()
		return false
	transform = Transform()
	$Orbit.mesh = make_shaded_annulus(orbit_radius, t, 32, draw_color)
	assert($Orbit.mesh)
	$Radius.mesh = make_shaded_box(Vector3(-t/2.0,0.0,-0.5),t/2.0, 0.5, 2, 2, draw_color)
	assert($Radius.mesh)
	$Orbit.visible = true
	$Radius.visible = true
	valid = true
	return update_materials(new_u_scale,new_color)

func update_from_path(new_u_scale: float,new_color: Color,planet_time: float,
		position_override=null) -> bool:
	var object = game_state.systems.get_node_or_null(object_path)
	if not object:
		push_warning('No object exists at path '+str(object_path))
		make_invalid()
		return false
	if not object.has_method('is_SpaceObjectData'):
		push_warning('Object at path '+str(object_path)+' is not a SpaceObjectData')
		make_invalid()
		return false
	
	var parent = object.get_parent()
	var new_position = position_override
	var new_radius = null
	var new_center = Vector3(0,0,0)
	if parent and parent.has_method('is_SpaceObjectData'):
		new_center = parent.planet_translation(planet_time)
	if new_position==null:
		new_position = object.planet_translation(planet_time)
		new_radius = max(0.0,object.orbit_radius)
	else:
		new_position.y = 0
		new_radius = new_position.distance_to(new_center)
	
	if new_radius<=annotation3d_thickness:
		make_invalid()
		return false
	
	if valid and new_center==orbit_center and new_radius==orbit_radius \
			and new_position==position:
		return update_materials(new_u_scale,new_color)
	
	orbit_center = new_center
	orbit_radius = new_radius
	position = new_position
	var t: float = annotation3d_thickness
	$Orbit.mesh = make_shaded_annulus(orbit_radius, t, 32, draw_color)
	assert($Orbit.mesh)
	$Radius.mesh = make_shaded_box(Vector3(-0.5,0.0,-t/2.0),0.5, t/2.0, 2, 2, draw_color)
	assert($Radius.mesh)
	$Orbit.visible = true
	$Radius.visible = true
	valid = true
	
	return update_materials(new_u_scale,new_color)

func update_materials(new_u_scale: float,new_color: Color) -> bool:
	set_draw_color(new_color)
	if not valid:
		return false

	var success=true
	$Orbit.translation = orbit_center
	$Orbit.translation.y = -39.9
	var material = $Orbit.mesh.surface_get_material(0)
	if material:
		material.set_shader_param('scale',new_u_scale)
		material.set_shader_param('color',draw_color)
	else:
		push_warning('Orbit annotation has no material '+str(get_path()))
		success = false

	$Radius.translation = (orbit_center+position)/2.0
	$Radius.translation.y = -39.9
	var diff: Vector3 = orbit_center-position
	var dist: float = max(.001,diff.length())
	$Radius.scale = Vector3(dist,1.0,1.0)
	$Radius.rotation = Vector3(0.0,atan2(diff.z/dist,-diff.x/dist),0.0)
	material = $Radius.mesh.surface_get_material(0)
	if material:
		material.set_shader_param('scale',new_u_scale)
		material.set_shader_param('color',draw_color)
	else:
		push_warning('Radius annotation has no material '+str(get_path()))
		success = false
	visible = success
	return success

func set_draw_color(color: Color):
	var new_color = Color(color)
	new_color.v=0.7
	new_color.a=0.3
	draw_color=new_color

func make_shaded_annulus(middle_radius: float, thickness: float, steps: int,
		color: Color) -> ArrayMesh:
	assert(steps>2)
	assert(middle_radius>0.0)
	assert(thickness>0.0)
	assert(thickness<middle_radius)
	var vertices: PoolVector3Array = PoolVector3Array()
	var uv: PoolVector2Array = PoolVector2Array()
	vertices.resize(steps*6)
	uv.resize(steps*6)
	var angle = 2*PI/steps
	var half_angle = angle/2
	var inner_radius = middle_radius-thickness/2
	var outer_radius = middle_radius+thickness/2
	var far_radius = outer_radius/cos(half_angle)
	#var u_shift = (far_radius - outer_radius) / outer_radius
	var prior_far_vertex = far_radius*Vector3(cos((steps-1)*angle+half_angle),0,
		sin((steps-1)*angle+half_angle))
	var prior_inner_vertex = inner_radius*Vector3(cos((steps-1)*angle),0,
		sin((steps-1)*angle))
	var _inner_u = inner_radius/far_radius
	#var near_zero_u = u_shift
	var uvhalf = Vector2(0.5,0.5)
	for i in range(steps):
		#var far_i = i+0.5
		var this_far_vertex = far_radius*Vector3(cos(i*angle+half_angle),0.0,
			sin(i*angle+half_angle))
		var this_inner_vertex = inner_radius*Vector3(cos(i*angle),0.0,sin(i*angle))
		
		vertices[i*6 + 0] = this_inner_vertex
		uv      [i*6 + 0] = Vector2(this_inner_vertex.z,this_inner_vertex.x)/2.0+uvhalf
		vertices[i*6 + 1] = prior_far_vertex
		uv      [i*6 + 1] = Vector2(prior_far_vertex.z,prior_far_vertex.x)/2.0+uvhalf
		vertices[i*6 + 2] = this_far_vertex
		uv      [i*6 + 2] = Vector2(this_far_vertex.z,this_far_vertex.x)/2.0+uvhalf

		vertices[i*6 + 3] = this_inner_vertex
		uv      [i*6 + 3] = Vector2(this_inner_vertex.z,this_inner_vertex.x)/2.0+uvhalf
		vertices[i*6 + 4] = prior_inner_vertex
		uv      [i*6 + 4] = Vector2(prior_inner_vertex.z,prior_inner_vertex.x)/2.0+uvhalf
		vertices[i*6 + 5] = prior_far_vertex
		uv      [i*6 + 5] = Vector2(prior_far_vertex.z,prior_far_vertex.x)/2.0+uvhalf
		
		prior_far_vertex = this_far_vertex
		prior_inner_vertex = this_inner_vertex
	return tri_to_mesh(vertices,uv,color,middle_radius,thickness,1.0,AnnulusShader)

func make_shaded_box(from: Vector3, x_step: float, z_step: float, nx: int,
		nz: int, color: Color) -> ArrayMesh:
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
	return tri_to_mesh(vertices,uv,color,0.5,1.0,1.0,MapAnnotationShader)

func tri_to_mesh(vertices: PoolVector3Array, uv: PoolVector2Array, color: Color,
		middle_radius: float, thickness: float, camera_scale: float,
		shader: Shader) -> ArrayMesh:
	var mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(ArrayMesh.ARRAY_MAX)
	arrays[ArrayMesh.ARRAY_VERTEX] = vertices
	arrays[ArrayMesh.ARRAY_TEX_UV] = uv
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material = ShaderMaterial.new()
	material.shader = shader
	if shader == MapAnnotationShader:
		material.set_shader_param('color',Color(color))
		material.set_shader_param('u_middle_radius',float(middle_radius))
		material.set_shader_param('u_width',float(thickness))
		material.set_shader_param('scale',float(camera_scale))
	elif shader == AnnulusShader:
		material.set_shader_param('color',Color(color))
		material.set_shader_param('r_mid',float(middle_radius))
		material.set_shader_param('thickness',float(thickness))
		material.set_shader_param('scale',float(camera_scale))
	mesh.surface_set_material(0,material)
	assert(mesh)
	assert(mesh.surface_get_material(0))
	return mesh
