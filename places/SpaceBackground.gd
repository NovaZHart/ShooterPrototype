extends Spatial

export var plasma_seed: int = 32091872
export var starfield_seed: int = 9876867
export var plasma_color: Color = Color(0.4,0.4,1.0,1.0)
export var hyperspace: bool = false
export var override_from: int = 1

var uv_offset: Vector2 = Vector2(0.0,0.0)
var uv2_offset: Vector2 = Vector2(0.0,0.0)

var ticks = -1

var hash_square: ImageTexture
var background_viewport: Viewport
var background_texture: ViewportTexture
var background_shader: ShaderMaterial
var starfield_viewport: Viewport
var starfield_texture: ViewportTexture
var starfield_shader: ShaderMaterial
var background: MeshInstance
const background_pixels: float = 2048.0
const background_size: float = 611.0
const background_uv2: float = 16.0
var have_sent_texture: Dictionary = {}

onready var SpaceBackgroundShader = preload("res://shaders/SpaceBackground.shader")
#onready var SpaceBackgroundShader = preload("res://shaders/SpaceBackgroundV3.shader")
onready var TiledImageShader = preload("res://shaders/TiledImage.shader")
onready var HyperspaceShader = preload("res://shaders/Hyperspace.shader")
onready var StarFieldGenerator = preload("res://shaders/StarFieldGenerator.shader")

func _ready():
	var _sf: Viewport = make_starfield_viewport()
	var _bg: Viewport = make_background_viewport()
	var _sb = make_background()
	set_process(false)
	set_physics_process(false)

func make_viewport(var nx: float, var ny: float, var shader: ShaderMaterial) -> Viewport:
	var view: Viewport = Viewport.new()
	var rect: ColorRect = ColorRect.new()
	view.size=Vector2(nx,ny)
	view.render_target_clear_mode=Viewport.CLEAR_MODE_NEVER
	view.render_target_update_mode=Viewport.UPDATE_ONCE
	view.keep_3d_linear=true
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
	if system_data!=null:
		plasma_seed=system_data.plasma_seed
		plasma_color=system_data.plasma_color
		starfield_seed=system_data.starfield_seed
	return regenerate()

func _enter_tree():
	if override_from==1:
		var system_data = Player.system
		if system_data:
			plasma_seed=system_data.plasma_seed
			plasma_color=system_data.plasma_color
			starfield_seed=system_data.starfield_seed

func regenerate() -> bool:
	var hash_square_image: Image = utils.native.make_hash_square32(int(plasma_seed))
	hash_square = ImageTexture.new()
	hash_square.create_from_image(hash_square_image)
	background_shader.set_shader_param('color',Color(plasma_color))
	background_shader.set_shader_param('hash_square',hash_square)
	starfield_shader.set_shader_param('seed',int(starfield_seed))
	background_viewport.update_mode = Viewport.UPDATE_ONCE
	starfield_viewport.update_mode = Viewport.UPDATE_ONCE
	return false

func make_background_viewport():
	if get_node_or_null('CloudViewport'):
		return
	background_shader=ShaderMaterial.new()
	var hash_square_image: Image = utils.native.make_hash_square32(int(plasma_seed))
	hash_square = ImageTexture.new()
	hash_square.create_from_image(hash_square_image)
	background_shader.set_shader(SpaceBackgroundShader)
	var view=make_viewport(background_pixels,background_pixels,background_shader)
	background_shader.set_shader_param('color',Color(plasma_color))
	background_shader.set_shader_param('hash_square',hash_square)
	view.name='CloudViewport'
	background_texture = view.get_texture()
	background_texture.flags = Texture.FLAGS_DEFAULT
	add_child(view)
	return view
	
func make_starfield_viewport():
	if get_node_or_null('StarFieldGenerator'):
		return
	starfield_shader=ShaderMaterial.new()
	starfield_shader.set_shader(StarFieldGenerator)
	starfield_shader.set_shader_param('seed',int(starfield_seed))
	var view=make_viewport(background_pixels,background_pixels,starfield_shader)
	view.name='StarFieldGenerator'
	starfield_texture = view.get_texture()
	starfield_texture.flags = 0
	add_child(view)
	return view

func make_background():
	background=make_background_square(background_size,background_size,
		[Vector2(0,0),Vector2(background_uv2,background_uv2)])
	background.name='Space'
	var view_mat=ShaderMaterial.new()
	if hyperspace:
		view_mat.set_shader(HyperspaceShader)
	else:
		view_mat.set_shader(TiledImageShader)
		view_mat.set_shader_param('uv_whole',Vector2(1.0,1.0))
		view_mat.set_shader_param('uv2_whole',Vector2(background_uv2,background_uv2))
		view_mat.set_shader_param('texture_starfield',starfield_texture)
	view_mat.set_shader_param('texture_albedo',$CloudViewport.get_texture())
	view_mat.set_shader_param('texture_size',Vector2(float(background_pixels),float(background_pixels)))
	view_mat.set_shader_param('uv_offset',uv_offset)
	view_mat.set_shader_param('uv2_offset',uv2_offset)
	background.material_override=view_mat
	background.set_layer_mask_bit(1,true)
	add_child(background)
	return background

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
	if hyperspace:
		return
	var margin: float=(background_size-camera_size)/2.0
	var margins: Vector2 = Vector2(margin,background_size-margin)/background_size
	var uv2_range: Vector2 = margins*background_uv2
	view_mat.set_shader_param('uv_range',margins.y-margins.x)
	view_mat.set_shader_param('uv2_range',uv2_range)

