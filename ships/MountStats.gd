extends Position3D

const MISSING_MOUNT_TYPE: String = '**Missing mount type**'
export var mount_size_x: int = 1
export var mount_size_y: int = 1
export var mount_type: String = MISSING_MOUNT_TYPE
export var mount_type_display: String = 'Mount'

var mount_flags: int setget set_mount_flags,get_mount_flags
var initialized_mount_flags: bool = false
var help_page = 'error: should never see this'

func get_mount_size():
	return max(1,mount_size_x*mount_size_y)

func set_mount_flags(f: int):
	if not initialized_mount_flags:
		initialize_mount_flags()
	mount_flags = f

func get_mount_flags() -> int:
	assert(mount_type!=MISSING_MOUNT_TYPE)
	if not initialized_mount_flags:
		initialize_mount_flags()
	return mount_flags

func is_MountStats(): pass # Never called; must only exist

func initialize_mount_flags():
	mount_flags = utils.mount_type_to_int(mount_type)
	if is_multimount() and name.find('Gun')>=0:
		push_warning('Godot fucked up instancing with '+str(name)+' mount_type '+str(mount_type))
	initialized_mount_flags = true
	assert(mount_flags)

func is_multimount():
	return mount_flags == (game_state.MOUNT_FLAG_EQUIPMENT|game_state.MOUNT_FLAG_INTERNAL)

func is_mount_point(): # Never called; must only exist
	pass

func is_not_mounted(): # Never called; must only exist
	pass
