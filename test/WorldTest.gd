extends Spatial

var camera_distance: float = 5.0
var camera_x_rot: float = 0.0
var camera_y_rot: float = 0.0
var camera_z_rot: float = 0.0
var tick: int = 0
var noise_texture: ViewportTexture

onready var SphereTool = preload('res://bin/spheretool.gdns')
onready var simple_planet_shader = preload('res://places/SimplePlanetV2.shader')
onready var simple_sun_shader = preload('res://places/SimpleSunV2.shader')
onready var sphere_test_shader = preload('res://test/sphere_test.shader')
onready var cube_tile_shader = preload("res://places/CubePlanetTilesV2.shader")

func make_viewport(var nx: float, var ny: float, var shader: ShaderMaterial) -> Viewport:
	var view=Viewport.new()
	var rect=ColorRect.new()
	view.size=Vector2(nx,ny)
	view.render_target_clear_mode=Viewport.CLEAR_MODE_NEVER
	view.render_target_update_mode=Viewport.UPDATE_ONCE
	view.keep_3d_linear=true;
	rect.rect_size=Vector2(nx,ny)
	rect.set_material(shader)
	rect.name='Content'
	view.own_world=true
	view.transparent_bg=true
	view.add_child(rect)
	return view

func send_viewport_texture(mesh: MeshInstance, viewport: Viewport, shader_param: String, tex: ViewportTexture) -> ViewportTexture:
	if tex!=null:
		return tex
	tex=viewport.get_texture()
	if tex!=null:
		mesh.material_override.set_shader_param(shader_param,tex)
		print('sent shader param '+shader_param)
	return tex

# Called when the node enters the scene tree for the first time.
func _ready():
	var planet = SphereTool.new()
	var image: Image = planet.make_lookup_tiles_c112();
	var xyz: ImageTexture = ImageTexture.new()
	xyz.create_from_image(image)
	
	var shade=ShaderMaterial.new()
	shade.shader=cube_tile_shader
	shade.set_shader_param('xyz',xyz)
	var view=make_viewport(2048,2048,shade)
	view.name='CubeTiler'
	add_child(view)
	planet.make_cube_sphere_v2("CubePlanet",Vector3(0,0,0),2.5,56)
	add_child(planet)
	
	shade = ShaderMaterial.new()
	shade.set_shader(simple_planet_shader)
	shade.set_shader_param('xyz',xyz)
	planet.material_override=shade
	#get_viewport().msaa=Viewport.MSAA_4X

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	noise_texture=send_viewport_texture($CubePlanet,$CubeTiler,'precalculated',noise_texture)
	var ui_x: float = Input.get_action_strength("ui_down")-Input.get_action_strength("ui_up")
	var ui_y: float = Input.get_action_strength("ui_right")-Input.get_action_strength("ui_left")
	var ui_z: float = Input.get_action_strength("ui_page_up")-Input.get_action_strength("ui_page_down")
	camera_x_rot += delta*ui_x*PI/2.0
	camera_y_rot += delta*ui_y*PI/4.0
	camera_z_rot += delta*ui_z*PI/2.0
	$Camera.set_identity()
	$Camera.rotate_x(camera_x_rot)
	$Camera.rotate_y(camera_y_rot)
	$Camera.rotate_z(camera_z_rot)
	$Camera.translate_object_local(Vector3(0.0,0.0,camera_distance))
	tick += 1
	$CubePlanet.rotation.y += 0.003
	if tick%20==0:
		print(str(Engine.get_frames_per_second()),' ',camera_x_rot,',',
			camera_y_rot,',',camera_z_rot)
