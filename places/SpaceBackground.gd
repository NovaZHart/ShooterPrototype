extends Spatial

export var plasma_seed: int = 32091872
export var starfield_seed: int = 9876867
export var plasma_color: Color = Color(0.4,0.4,1.0,1.0)

var uv_offset: Vector2 = Vector2(0.0,0.0)
var uv2_offset: Vector2 = Vector2(0.0,0.0)

var background_texture: ViewportTexture
var starfield: ViewportTexture
var background: MeshInstance
const background_pixels: float = 2048.0
const background_size: float = 512.0
const background_uv2: float = 8.0
var have_sent_texture: Dictionary = {}

onready var SpaceBackgroundShader = preload("res://places/SpaceBackground.shader")
onready var TiledImageShader = preload("res://places/TiledImage.shader")
onready var StarFieldGenerator = preload("res://places/StarFieldGenerator.shader")

func send_viewport_texture(viewport: Viewport, shader_param: String,
		tex: ViewportTexture, object: MeshInstance) -> ViewportTexture:
	if tex!=null:
		return tex
	tex=viewport.get_texture()
	if tex!=null:
		object.material_override.set_shader_param(shader_param,tex)
	return tex

func make_viewport(var nx: float, var ny: float, var shader: ShaderMaterial) -> Viewport:
	var view=Viewport.new()
	var rect=ColorRect.new()
	view.size=Vector2(nx,ny)
	view.render_target_clear_mode=Viewport.CLEAR_MODE_NEVER
	view.render_target_update_mode=Viewport.UPDATE_ONCE
	view.usage=Viewport.USAGE_2D
	rect.rect_size=Vector2(nx,ny)
	rect.set_material(shader)
	rect.name='Content'
	view.add_child(rect)
	return view

func make_background_square(nx: float,nz: float,uv2) -> MeshInstance:
	var bg=MeshInstance.new()
	var st=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_uv(Vector2(0,1))
	if uv2!=null: st.add_uv2(Vector2(uv2[0][0],uv2[1][1]))
	st.add_vertex(Vector3(nx,0,-nz))
	st.add_uv(Vector2(0,0))
	if uv2!=null: st.add_uv2(Vector2(uv2[0][0],uv2[0][1]))
	st.add_vertex(Vector3(nx,0,nz))
	st.add_uv(Vector2(1,0))
	if uv2!=null: st.add_uv2(Vector2(uv2[1][0],uv2[0][1]))
	st.add_vertex(Vector3(-nx,0,nz))
	st.add_uv(Vector2(1,0))
	if uv2!=null: st.add_uv2(Vector2(uv2[1][0],uv2[0][1]))
	st.add_vertex(Vector3(-nx,0,nz))
	st.add_uv(Vector2(1,1))
	if uv2!=null: st.add_uv2(Vector2(uv2[1][0],uv2[1][1]))
	st.add_vertex(Vector3(-nx,0,-nz))
	st.add_uv(Vector2(0,1))
	if uv2!=null: st.add_uv2(Vector2(uv2[0][0],uv2[1][1]))
	st.add_vertex(Vector3(nx,0,-nz))
	bg.mesh=st.commit()
	return bg

func update_from(system_data) -> bool:
	plasma_seed=system_data.plasma_seed
	plasma_color=system_data.plasma_color
	starfield_seed=system_data.starfield_seed
	return regenerate()

func regenerate() -> bool:
	var success: bool = true
	var plasma_view: Viewport = get_node_or_null('CloudViewport')
	var plasma_rect: ColorRect = get_node_or_null('CloudViewport/Content')
	if plasma_rect and plasma_view:
		plasma_rect.get_material().set_shader_param('plasma_seed',int(plasma_seed))
		plasma_rect.get_material().set_shader_param('color',Color(plasma_color))
		plasma_view.render_target_update_mode=Viewport.UPDATE_ONCE
		background_texture = null
	else:
		push_error('plasma generator nodes are missing')
		success=false
	
	var star_view: Viewport = get_node_or_null('StarFieldGenerator')
	var star_rect: ColorRect = get_node_or_null('StarFieldGenerator/Content')
	if star_rect and star_view:
		star_rect.get_material().set_shader_param('seed',int(starfield_seed))
		star_view.render_target_update_mode=Viewport.UPDATE_ONCE
		starfield = null
	else:
		push_error('starfield generator nodes are missing')
		success=false
		
	return success

func _ready():
	var shade=ShaderMaterial.new()
	shade.set_shader(SpaceBackgroundShader)
	var view=make_viewport(background_pixels,background_pixels,shade)
	shade.set_shader_param('make_stars',false)
	shade.set_shader_param('make_plasma',true)
	shade.set_shader_param('plasma_seed',int(plasma_seed))
	shade.set_shader_param('color',Color(plasma_color))
	shade.set_shader_param('view_size_x',background_pixels)
	shade.set_shader_param('view_size_y',background_pixels)
	view.name='CloudViewport'
	add_child(view)
	
	shade=ShaderMaterial.new()
	shade.set_shader(StarFieldGenerator)
	shade.set_shader_param('seed',int(starfield_seed))
	view=make_viewport(background_pixels,background_pixels,shade)
	view.name='StarFieldGenerator'
	add_child(view)
	
	background=make_background_square(background_size,background_size,
		[Vector2(0,0),Vector2(background_uv2,background_uv2)])
	background.name='Space'
	var view_mat=ShaderMaterial.new()
	view_mat.set_shader(TiledImageShader)
	view_mat.set_shader_param('texture_albedo',$CloudViewport.get_texture())
	view_mat.set_shader_param('texture_starfield',$StarFieldGenerator.get_texture())
	view_mat.set_shader_param('texture_size',Vector2(float(background_pixels),float(background_pixels)))
	view_mat.set_shader_param('uv_offset',uv_offset)
	view_mat.set_shader_param('uv2_offset',uv2_offset)
	view_mat.set_shader_param('uv_whole',Vector2(1.0,1.0))
	view_mat.set_shader_param('uv2_whole',Vector2(background_uv2,background_uv2))
	background.material_override=view_mat
	background.set_layer_mask_bit(1,true)
	add_child(background)

func center_view(x: float,z: float,a: float,camera_size: float,camera_min_height: float) -> void:
	background.rotation = Vector3(0,0,0)
	background.translation.x = x + (camera_min_height-background.translation.y)*tan(a)
	background.translation.z = z
	var view_mat=background.material_override
	uv_offset=Vector2(fmod(-x/background_size/2,1.0),
					  fmod(-z/background_size/2,1.0))
	uv2_offset=uv_offset*background_uv2
	view_mat.set_shader_param('uv_offset',uv_offset)
	view_mat.set_shader_param('uv2_offset',uv2_offset)
	var margin: float=(background_size-camera_size)/2.0
	var margins: Vector2 = Vector2(margin,background_size-margin)/background_size
	var uv2_range: Vector2 = margins*background_uv2
	view_mat.set_shader_param('uv_range',margins)
	view_mat.set_shader_param('uv2_range',uv2_range)

func _process(var _delta):
	background_texture=send_viewport_texture($CloudViewport,'texture_albedo',background_texture,background)
	starfield=send_viewport_texture($StarFieldGenerator,'texture_starfield',starfield,background)
