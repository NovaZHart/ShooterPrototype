extends Control

var left_material: ShaderMaterial
var left_seed: int = 0
var right_material: ShaderMaterial
var right_seed: int = 1

const nx=512
const ny=256

var tile_shader: Shader = preload('res://shaders/CubePlanetTilesV3.shader')

func _ready():
	$All/Top/AsteroidView/AsteroidViewport/SpaceBackground.center_view(0,0,0,100,0)
	var xyz: ImageTexture=game_state.get_sphere_xyz()
	left_material = apply_shader($All/Bottom/Left/Viewport/ColorRect,xyz,left_seed)
	right_material = apply_shader($All/Bottom/Right/Viewport/ColorRect,xyz,right_seed)
	#left_material = make_viewport($All/Bottom/Left,xyz,left_seed)
	#right_material = make_viewport($All/Bottom/Right,xyz,right_seed)
	_on_AsteroidView_resized()

func apply_shader(color_rect: ColorRect,xyz: ImageTexture,hash_seed: int) -> ShaderMaterial:
	var mat=ShaderMaterial.new()
	mat.set_shader(tile_shader)
	mat.set_shader_param('xyz',xyz)
	update_cube(mat,hash_seed)
	return mat

func make_viewport(container: ViewportContainer,xyz: ImageTexture,hash_seed: int) -> ShaderMaterial:
# warning-ignore:shadowed_variable
	var view=Viewport.new()
	var rect=ColorRect.new()
	view.size=Vector2(nx,ny)
	view.render_target_clear_mode=Viewport.CLEAR_MODE_NEVER
	view.render_target_update_mode=Viewport.UPDATE_ALWAYS
	view.keep_3d_linear=true
	view.disable_3d=true
	view.usage=Viewport.USAGE_2D
	rect.rect_size=Vector2(nx,ny)
	rect.color=Color(1,0,0,1)
	var mat=ShaderMaterial.new()
	mat.set_shader(tile_shader)
	mat.set_shader_param('xyz',xyz)
	rect.set_material(mat)
	rect.name='Content'
	view.own_world=true
	view.hdr=false
	view.add_child(rect)
	view.name='Viewport'
	container.add_child(view)
	update_cube(mat,hash_seed)
	return mat

func update_cube(mat: ShaderMaterial,hash_seed: int):
	var image: Image=utils.native.make_hash_cube16(hash_seed)
	var texture: ImageTexture = ImageTexture.new()
	texture.create_from_image(image)
	mat.set_shader_param('hash_cube',texture)

func regenerate_tiles(left: bool,cube: bool):
	if left:
		print('update left')
		if cube:
			print('update left cube')
			update_cube(left_material,left_seed)
		#$All/Bottom/Left/Viewport.render_target_update_mode=Viewport.UPDATE_ONCE
	else:
		print('update right')
		if cube:
			print('update right cube')
			update_cube(right_material,right_seed)
		#$All/Bottom/Right/Viewport.render_target_update_mode=Viewport.UPDATE_ONCE

func _on_AsteroidView_resized():
	var container: ViewportContainer = $All/Top/AsteroidView
	var viewport: Viewport = $All/Top/AsteroidView/AsteroidViewport
	viewport.set_size(container.get_size())

func _on_RandomSeedLeft_text_entered(new_text):
	if new_text.is_valid_integer():
		left_seed = int(new_text)
		regenerate_tiles(true,true)
	else:
		$All/Bottom/Controls/RandomSeedLeft.text=str(left_seed)

func _on_RandomSeedRight_text_entered(new_text):
	if new_text.is_valid_integer():
		right_seed = int(new_text)
		regenerate_tiles(false,true)
	else:
		$All/Bottom/Controls/RandomSeedRight.text=str(right_seed)

func get_material_at(left: bool):
	if left:
		return left_material
	return right_material

func tweak_shader_param_float(left: bool,param_name: String,line_edit_name: String,new_text: String):
	var material: ShaderMaterial = get_material_at(left)
	if new_text.is_valid_float():
		material.set_shader_param(param_name,float(new_text))
		regenerate_tiles(left,false)
	else:
		var node = $All/Bottom/Controls.get_node_or_null(line_edit_name)
		if node:
			node.text=str(material.get_shader_param(param_name))

func _on_WeightPowerLeft_text_entered(new_text):
	tweak_shader_param_float(true,'weight_power','WeightPowerLeft',new_text)

func _on_WeightPowerRight_text_entered(new_text):
	tweak_shader_param_float(false,'weight_power','WeightPowerRight',new_text)
