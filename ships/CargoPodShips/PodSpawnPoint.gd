extends Position3D

const mesh_list: Array = [
	preload('res://ships/CargoPodShips/PodWithBlueLines.mesh'),
	preload('res://ships/CargoPodShips/PodWithBlueWindow.mesh'),
	preload('res://ships/CargoPodShips/PodWithBrownBoxes.mesh'),
	preload('res://ships/CargoPodShips/PodWithTubes.mesh'),
	preload('res://ships/CargoPodShips/PodPedistal.mesh'),
]

# Called when the node enters the scene tree for the first time.
func _ready():
	assert(get_parent())
	call_deferred('generate_instance',get_parent())

func generate_instance(parent):
	var instance=MeshInstance.new()
	instance.transform=transform
	instance.mesh=mesh_list[randi()%len(mesh_list)]
	instance.name=name+'_instanced'
	parent.add_child(instance)
	queue_free()
