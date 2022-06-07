extends Reference

const PIXEL_MARGIN = 4
const MIN_WIDTH = 64
const FONT_SIZE = MIN_WIDTH-2*PIXEL_MARGIN
const MAX_WIDTH = 4096
const DUMMY_TEXT = 'MMMM'

const ImageLabelShader = preload('res://shaders/ImageLabel.shader')

# Inputs:
var text: String
var font_data: DynamicFontData
var color: Color

# Locals:
var draw_step_complete: bool = false
var canvas: RID
var viewport: RID
var canvas_item: RID
var scenario: RID
var viewport_texture: RID
var font: Font
var clip_rect: Rect2

# Result:
var ready: bool = false
var string_rect: Rect2
var string_uv: Rect2
var instance: MeshInstance

func _init(text_:String, font_data_:DynamicFontData, color_:Color):
	text=text_
	font_data=font_data_
	color=color_

func _notification(what):
	if what == NOTIFICATION_PREDELETE:
		for rid in [ canvas_item, canvas, viewport, scenario ]:
			if rid:
				VisualServer.free_rid(rid)

func pow2_width(width) -> int:
	var w: int = int(round(width))
	var i: int = MIN_WIDTH
	while i<w and i<MAX_WIDTH:
		i*=2
	return i

func make_instance_from_image():
	viewport_texture = VisualServer.viewport_get_texture(viewport)
	if not viewport_texture:
		push_warning('No viewport texture')
	var image = VisualServer.texture_get_data(viewport_texture)
	if not image:
		push_error('No image')
	var image_data = image.get_data()
	assert(image_data)
	assert(not image_data.empty())
	var tex = ImageTexture.new()
#	var image_copy = Image.new()
#	image_copy.copy_from(image)
	tex.create_from_image(image)
	var s00 = string_uv.position
	var s11 = string_uv.position+string_uv.size
	var s01 = Vector2(s00.x,s11.y)
	var s10 = Vector2(s11.x,s00.y)
	var H = 1.0
	var W = H*string_rect.size.x/string_rect.size.y
	var data = []
	data.resize(ArrayMesh.ARRAY_MAX)
	data[ArrayMesh.ARRAY_VERTEX] = PoolVector3Array(
		[Vector3(0,0,0),Vector3(H,0,0),Vector3(H,0,W),
		Vector3(H,0,W),Vector3(0,0,W),Vector3(0,0,0)])
	data[ArrayMesh.ARRAY_TEX_UV] = PoolVector2Array([s00,s01,s11,s11,s10,s00])
	var mesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
	var shader_material = ShaderMaterial.new()
	shader_material.shader = ImageLabelShader
	shader_material.set_shader_param('string_texture',tex)
	mesh.surface_set_material(0,shader_material)
	instance = MeshInstance.new()
	instance.mesh = mesh

func prepare_viewport():
	canvas = VisualServer.canvas_create()
	assert(canvas.get_id())
	font = DynamicFont.new()
	font.font_data = font_data
	font.size = FONT_SIZE
	var string_size: Vector2 = font.get_string_size(DUMMY_TEXT)
	string_size.x+=PIXEL_MARGIN
	var viewport_size_x: int = pow2_width(string_size.x + 2*PIXEL_MARGIN)
	var viewport_size_y: int = pow2_width(FONT_SIZE + 2*PIXEL_MARGIN)
	viewport = VisualServer.viewport_create()
	assert(viewport.get_id())
	VisualServer.viewport_attach_canvas(viewport,canvas)
	VisualServer.viewport_set_transparent_background(viewport,true)
	VisualServer.viewport_set_size(viewport,viewport_size_x,viewport_size_y)
	VisualServer.viewport_set_disable_environment(viewport,true)
	canvas_item = VisualServer.canvas_item_create()
	assert(canvas_item.get_id())
	VisualServer.canvas_item_set_parent(canvas_item,canvas)
	VisualServer.viewport_set_active(viewport,true)

func draw_text_on_canvas():
	var string_size: Vector2 = font.get_string_size(text)
	string_size.x+=PIXEL_MARGIN
	var viewport_size_x: int = pow2_width(string_size.x + 2*PIXEL_MARGIN)
	var viewport_size_y: int = pow2_width(FONT_SIZE + 2*PIXEL_MARGIN)
	string_rect = Rect2(Vector2(PIXEL_MARGIN,PIXEL_MARGIN),string_size)
	string_uv = Rect2(
		Vector2(PIXEL_MARGIN/float(viewport_size_x),PIXEL_MARGIN/float(viewport_size_y)),
		Vector2(string_size.x/viewport_size_x,1.0-2.0*PIXEL_MARGIN/viewport_size_y))
	VisualServer.viewport_set_size(viewport,viewport_size_x,viewport_size_y)
	VisualServer.viewport_set_update_mode(viewport,VisualServer.VIEWPORT_UPDATE_ONCE)
	VisualServer.viewport_set_clear_mode(viewport,VisualServer.VIEWPORT_CLEAR_ONLY_NEXT_FRAME)
# warning-ignore:narrowing_conversion
	font.draw(canvas_item, Vector2(PIXEL_MARGIN,PIXEL_MARGIN+font.get_ascent()),
		text, color, string_rect.size.x)
	draw_step_complete = true

func reset(text_: String,color_: Color):
	text = text_
	color = color_
	draw_step_complete = false
	ready = false
	instance = null
	if canvas_item:
		VisualServer.canvas_item_clear(canvas_item)
	string_rect = Rect2()
	string_uv = Rect2()

func step() -> bool:
	if not viewport:
		prepare_viewport()
	if not draw_step_complete:
		draw_text_on_canvas()
		return false
	make_instance_from_image()
	ready = true
	return true
