extends Control

export var lock_corner: int = 1
export var pad_top: int = 30
export var pad_left: int = 10
export var pad_right: int = 10
export var pad_bottom: int = 10

var last_known_parent_rect: Rect2
var last_known_global_rect: Rect2
var is_repositioning: bool = false
var reposition_mutex: Mutex = Mutex.new()

func set_initial_rect(position: Vector2,size: Vector2):
	reposition_mutex.lock()
	is_repositioning = true
	rect_global_position = position
	rect_size = size
	record_rect()
	is_repositioning = false
	reposition_mutex.unlock()
#
#func shift_from_viewport_position():
#	# Assumption: control was set relative to the viewport instead of the parent.
#	# This function shifts the position to be relative to the parent.
#	auto_reposition(Rect2(Vector2(),get_viewport().size))
#	record_rect()

func rect_corner(r: Rect2, corner: int) -> Vector2:
	if corner==0:
		return r.position
	elif corner==1:
		return Vector2(r.position.x+r.size.x-1,r.position.y)
	elif corner==2:
		return r.position+r.size
	elif corner==3:
		return Vector2(r.position.x,r.position.y+r.size.y-1)
	else: # midpoint
		return r.position+r.size/2.0

# Called when the node enters the scene tree for the first time.
func _ready():
	record_rect()
	var _discard = connect('item_rect_changed',self,'record_rect')
	_discard = get_parent().connect('item_rect_changed',self,'auto_reposition')

func record_rect():
	if not is_repositioning:
		var viewport = get_viewport()
		assert(viewport)
		last_known_parent_rect = get_parent().get_global_rect()
		last_known_global_rect = get_global_rect()

func auto_reposition(old_parent_rect = null):
	reposition_mutex.lock()
	is_repositioning = true
	if true: #old_parent_rect == null:
		old_parent_rect = last_known_parent_rect
	var new_parent_rect: Rect2 = get_parent().get_global_rect()
	var old_global_rect: Rect2 = last_known_global_rect
	var new_global_rect: Rect2 = get_global_rect()
	var old_corner_distance: Vector2 = rect_corner(old_global_rect,lock_corner) - \
		rect_corner(old_parent_rect,lock_corner)
	var new_corner_distance: Vector2 = rect_corner(new_global_rect,lock_corner) - \
		rect_corner(new_parent_rect,lock_corner)
	var shift: Vector2 = old_corner_distance - new_corner_distance
	var shifted_position = rect_global_position+shift
	# FIXME: Handle corner cases? Maybe ensure top of window is on screen?
	rect_global_position = shifted_position
	is_repositioning = false
	reposition_mutex.unlock()
