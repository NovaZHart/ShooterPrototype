extends Container

export var font_data: DynamicFontData
export var color: Color

const ImageLabelMaker = preload('res://ui/ImageLabelMaker.gd')

var text: String = ''
var drawn_text: String = ''
var maker = null

#func show_image(image: Image, string_uv: Rect2, string_rect: Rect2):
#	assert(image)
#	var image_data = image.get_data()
#	assert(image_data)
#	assert(not image_data.empty())
#	var tex = ImageTexture.new()
##	var image_copy = Image.new()
##	image_copy.copy_from(image)
#	tex.create_from_image(image)
#	var s00 = string_uv.position
#	var s11 = string_uv.position+string_uv.size
#	var s01 = Vector2(s00.x,s11.y)
#	var s10 = Vector2(s11.x,s00.y)
#	var H = 1.0
#	var W = H*string_rect.size.x/string_rect.size.y
#	var data = []
#	data.resize(ArrayMesh.ARRAY_MAX)
#	data[ArrayMesh.ARRAY_VERTEX] = PoolVector3Array(
#		[Vector3(0,0,0),Vector3(H,0,0),Vector3(H,0,W),
#		Vector3(H,0,W),Vector3(0,0,W),Vector3(0,0,0)])
#	data[ArrayMesh.ARRAY_TEX_UV] = PoolVector2Array([s00,s01,s11,s11,s10,s00])
#	print(data[ArrayMesh.ARRAY_TEX_UV])
#	var mesh = ArrayMesh.new()
#	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,data)
#	var shader_material = ShaderMaterial.new()
#	shader_material.shader = ImageLabelShader
#	shader_material.set_shader_param('string_texture',tex)
#	mesh.surface_set_material(0,shader_material)
#	var instance = MeshInstance.new()
#	instance.mesh = mesh

func update_label_instance():
	var old_instance = $Viewport/Viewport.get_node_or_null('label')
	if old_instance:
		$Viewport/Viewport.remove_child(old_instance)
		old_instance.queue_free()
	var H = 1.0
	var W = H*maker.string_rect.size.x/maker.string_rect.size.y
	maker.instance.name = 'label'
	maker.instance.translation.z = -W/2
	$Viewport/Viewport.add_child(maker.instance)

func _process(_delta):
	if text!=drawn_text:
		if not maker:
			maker = ImageLabelMaker.new(text,font_data,color)
			maker.step()
			drawn_text=text
		elif maker.ready:
			drawn_text=text
			maker.reset(text,color)
			maker.step()
	elif maker and not maker.ready:
		maker.step()
		update_label_instance()

func _on_LineEdit_text_changed(new_text):
	text = new_text
