extends Spatial

var messages = [
	"Pigs fly better than you!",
	"Why don't you stop dying?",
	"Where is that fire button?",
	"Can you dodge?",
	"Your shields suck.",
	"Is that armor cardboard?",
	"Fear the purple dots of doom!",
	"You would make an elegant corpse!",
	"Your turrets turn slower than the sun!",
	"You fit in my gun mount!",
	"Puny polygon pansy!",
]
var message_index: int = -1
	
var have_sent_texture: bool = false
var shader = preload('res://shaders/Advertisment.shader')
var left_shader: ShaderMaterial = ShaderMaterial.new()
var right_shader: ShaderMaterial = ShaderMaterial.new()
var counter: float = 0

func _ready():
	message_index = randi()%len(messages)
	$BannerContent/Label.text = "      "+messages[message_index]
	
	var panel=MeshInstance.new()
	panel.mesh=QuadMesh.new()
	panel.translation=Vector3(-0.262,-0.25,0.75)
	panel.rotation=Vector3(-42.449*PI/180,0,0)
	panel.scale=Vector3(3.35,1.6,1)
	right_shader.set_shader(shader)
	panel.material_override=right_shader
	panel.name='right'
	add_child(panel)
	
	panel=MeshInstance.new()
	panel.mesh=QuadMesh.new()
	panel.translation=Vector3(-0.262,-0.25,-0.75)
	panel.rotation=Vector3(-42.449*PI/180,PI,0)
	panel.scale=Vector3(3.35,1.6,1)
	left_shader.set_shader(shader)
	panel.material_override=left_shader
	panel.name='left'
	add_child(panel)

func _process(delta):
	if not have_sent_texture:
		var tex = $BannerContent.get_texture()
		if tex == null:
			printerr('Banner content texture is null!?')
			return # should never get here
		right_shader.set_shader_param('advertisment',tex)
		left_shader.set_shader_param('advertisment',tex)
		have_sent_texture = true
	counter += delta
	if counter>0.25:
		var text: String = $BannerContent/Label.text
		text.erase(0,1)
		if len(text)<1:
			message_index = (message_index+1)%len(messages)
			text = "      "+messages[message_index]
		$BannerContent/Label.text = text
		$BannerContent.render_target_update_mode=Viewport.UPDATE_ONCE
		have_sent_texture = false
		counter = 0
