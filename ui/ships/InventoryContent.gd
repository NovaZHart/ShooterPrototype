extends Reference

var translation: Vector3
var nx: int = 0
var ny: int = 0
var my_x: int = -1
var my_y: int = -1
var mount_type: String = ''
var scene: PackedScene
const InventorySlot: Script = preload('res://ui/ships/InventorySlot.gd')

func create(translation_: Vector3,nx_: int,ny_: int,mount_type_: String,scene_: PackedScene,my_x_: int = -1,my_y_: int = -1):
	translation=translation_
	nx=nx_
	ny=ny_
	mount_type=mount_type_
	scene=scene_
	my_x=my_x_
	my_y=my_y_

func fill_with(from: CollisionObject):
	translation=from.translation
	nx=from.nx
	ny=from.ny
	mount_type=from.mount_type
	scene=from.scene
	my_x=from.my_x
	my_y=from.my_y

func copy_only_item() -> Area:
	var new: Area = Area.new()
	new.set_script(InventorySlot)
	new.create_item(scene,false)
	return new
