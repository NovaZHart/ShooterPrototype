extends Spatial

export var plasma_seed: int = 32091872
export var starfield_seed: int = 9876867
export var plasma_color: Color = Color(0.4,0.4,1.0,1.0)
export var hyperspace: bool = false
export var override_from: int = 1

var uv_offset: Vector2 = Vector2(0.0,0.0)
var uv2_offset: Vector2 = Vector2(0.0,0.0)

var ticks = -1

var cached_background_texture = null
var cached_starfield_texture = null
var background_texture: ViewportTexture
var starfield: ViewportTexture
var background: MeshInstance
const background_pixels: float = 2048.0
const background_size: float = 512.0
const background_uv2: float = 8.0
var have_sent_texture: Dictionary = {}

onready var SpaceBackgroundShader = preload("res://shaders/SpaceBackground.shader")
onready var TiledImageShader = preload("res://shaders/TiledImage.shader")
onready var HyperspaceShader = preload("res://shaders/Hyperspace.shader")
onready var StarFieldGenerator = preload("res://shaders/StarFieldGenerator.shader")

func send_viewport_texture(cached, viewport: Viewport, shader_param: String,
		tex: ViewportTexture, object: MeshInstance, flags: int = -1) -> ViewportTexture:
	if tex:
		return tex
	var use = cached if cached else viewport.get_texture()
	if use:
		if flags>=0:
			use.flags = flags
		object.material_override.set_shader_param(shader_param,use)
	return use

func make_viewport(var nx: float, var ny: float, var shader: ShaderMaterial) -> Viewport:
	var view: Viewport = Viewport.new()
	var rect: ColorRect = ColorRect.new()
	view.size=Vector2(nx,ny)
	view.render_target_clear_mode=Viewport.CLEAR_MODE_NEVER
	view.render_target_update_mode=Viewport.UPDATE_ONCE
	view.keep_3d_linear=true
	#view.usage=Viewport.USAGE_2D
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
	assert(false)
	if not hyperspace and cached_starfield_texture:
		background.material_override.set_shader_param('texture_starfield',$StarFieldGenerator.get_texture())
		cached_starfield_texture=null
		make_starfield_viewport()
	if cached_background_texture:
		background.material_override.set_shader_param('texture_albedo',$CloudViewport.get_texture())
		cached_background_texture=null
		make_background_viewport()
	
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
	
	ticks=-999
	set_process(true)
	return success

func get_textures_from_cache():
	var bg_cache = game_state.get_background_cache()
	var bg_okay = false
	var sf_okay = hyperspace
		
	if bg_cache and bg_cache.bg_color==plasma_color and bg_cache.bg_seed==plasma_seed \
			and bg_cache.hyperspace==hyperspace and bg_cache.bg_texture:
		bg_okay = true
#	elif bg_cache and bg_cache.bg_texture:
#		print('background mismatch:')
#		print('bg_color '+str(plasma_color)+' vs. '+str(bg_cache.bg_color))
#		print('bg_seed '+str(plasma_seed)+' vs. '+str(bg_cache.bg_seed))
#		print('hyperspace '+str(hyperspace)+' vs. '+str(bg_cache.hyperspace))
#	else:
#		print('no background cached')

	if not hyperspace:
		var sf_cache = game_state.get_starfield_cache()
		sf_okay = false
		if sf_cache and sf_cache.bg_seed==starfield_seed and sf_cache.hyperspace==hyperspace \
				and sf_cache.bg_texture:
			sf_okay = true
#		elif sf_cache:
#			print('starfield mismatch:')
#			print('bg_seed '+str(starfield_seed)+' vs. '+str(sf_cache.bg_seed))
#			print('hyperspace '+str(hyperspace)+' vs. '+str(sf_cache.hyperspace))
#		else:
#			print('no starfield cached')
		if sf_okay and bg_okay:
#			print('get starfield from cache')
			cached_starfield_texture = sf_cache.bg_texture
	
	if bg_okay and sf_okay:
#		print('get background from cache')
		cached_background_texture = bg_cache.bg_texture

func _ready():
	get_textures_from_cache()
	if not cached_background_texture:
#		print('make background viewport')
		make_background_viewport()
	if not cached_starfield_texture:
#		print('make starfield viewport')
		make_starfield_viewport()
	make_background()
	
func make_background_viewport():
	if get_node_or_null('CloudViewport'):
		return
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
	
func make_starfield_viewport():
	if get_node_or_null('StarFieldGenerator'):
		return
	var shade=ShaderMaterial.new()
	shade.set_shader(StarFieldGenerator)
	shade.set_shader_param('seed',int(starfield_seed))
	var view=make_viewport(background_pixels,background_pixels,shade)
	view.name='StarFieldGenerator'
	add_child(view)

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
		if cached_starfield_texture:
			view_mat.set_shader_param('texture_starfield',cached_starfield_texture)
		else:
			view_mat.set_shader_param('texture_starfield',$StarFieldGenerator.get_texture())
	if cached_background_texture:
		view_mat.set_shader_param('texture_albedo',cached_background_texture)
	else:
		view_mat.set_shader_param('texture_albedo',$CloudViewport.get_texture())
	view_mat.set_shader_param('texture_size',Vector2(float(background_pixels),float(background_pixels)))
	view_mat.set_shader_param('uv_offset',uv_offset)
	view_mat.set_shader_param('uv2_offset',uv2_offset)
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
	if hyperspace:
		return
	var margin: float=(background_size-camera_size)/2.0
	var margins: Vector2 = Vector2(margin,background_size-margin)/background_size
	var uv2_range: Vector2 = margins*background_uv2
	view_mat.set_shader_param('uv_range',margins)
	view_mat.set_shader_param('uv2_range',uv2_range)

func send_cached_textures():
	var start: float = OS.get_ticks_msec()
#	print('Maybe send cached textures?')
	if background_texture and not cached_background_texture:
#		print('send background')
		game_state.set_background_cache(game_state.CachedImage.new(
			plasma_seed, plasma_color, texture_from_viewport(background_texture),
			hyperspace))
		if starfield and not cached_starfield_texture:
#			print('send starfield')
			game_state.set_starfield_cache(game_state.CachedImage.new(
				starfield_seed, Color(), texture_from_viewport(starfield),
				hyperspace))
#		else:
#			print('no new starfield to send')
#	else:
#		print('no new background to send')
	var duration = OS.get_ticks_msec()-start
	if duration>1:
		print("send_cached_textures took "+str(duration)+"ms")

func texture_from_viewport(viewport_texture: ViewportTexture):
	var img = viewport_texture.get_data()
	assert(img)
	var tex = ImageTexture.new()
	assert(tex)
	tex.create_from_image(img)
	return tex

func _process(var _delta):
	background_texture=send_viewport_texture(cached_background_texture,
		get_node_or_null('CloudViewport'),'texture_albedo',background_texture,background,Texture.FLAG_FILTER)
	if background_texture and not cached_background_texture:
		game_state.set_background_cache(game_state.CachedImage.new(
			plasma_seed, plasma_color, background_texture, hyperspace))
	
	if not hyperspace:
		starfield=send_viewport_texture(cached_starfield_texture,
			get_node_or_null('StarFieldGenerator'),'texture_starfield',starfield,background)

	var have_background: bool = not not background_texture
	var have_starfield: bool = not not starfield
	var done = have_background and (hyperspace or have_starfield)
	if done:
		if ticks<0:
#			print('start ticking')
			ticks=0
		else:
			ticks += 1
			if ticks==10:
#				print('defer call and stop processing')
				call_deferred('send_cached_textures')
				set_process(not done)
