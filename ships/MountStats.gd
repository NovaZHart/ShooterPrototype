extends Position3D

export var mount_size_x: int = 1
export var mount_size_y: int = 1
export var mount_type: String = 'equipment'

var help_page = 'error: should never see this'

func is_mount_point(): # Never called; must only exist
	pass

func is_not_mounted(): # Never called; must only exist
	pass
