extends Reference

var translation: Vector3
var nx: int = 0
var ny: int = 0
var my_x: int = -1
var my_y: int = -1
var mount_flags_all: int
var mount_flags_any: int
var scene: PackedScene
const multimount: bool = false
const InventorySlot: Script = preload('res://ui/ships/InventorySlot.gd')

func is_shown_in_space() -> bool:
	var m=mount_flags_all|mount_flags_any
	return m&(game_state.MOUNT_FLAG_TURRET|game_state.MOUNT_FLAG_GUN)

func create(translation_: Vector3,nx_: int,ny_: int,mount_flags_all_: int, \
		mount_flags_any_: int,scene_: PackedScene,my_x_: int = -1,my_y_: int = -1):
	translation=translation_
	nx=nx_
	ny=ny_
	mount_flags_all=mount_flags_all_
	mount_flags_any=mount_flags_any_
	scene=scene_
	my_x=my_x_
	my_y=my_y_

func fill_with(from: CollisionObject):
	translation=from.translation
	nx=from.nx
	ny=from.ny
	mount_flags_all=from.mount_flags_all
	mount_flags_any=from.mount_flags_any
	scene=from.scene
	my_x=from.my_x
	my_y=from.my_y

func copy_only_item() -> Area:
	var new: Area = Area.new()
	new.set_script(InventorySlot)
	new.create_item(scene,false)
	return new
