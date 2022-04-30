extends Popup

export var allow_saving = true setget set_allow_saving, get_allow_saving

func set_allow_saving(flag: bool):
	$Saves.allow_saving = flag
	allow_saving = $Saves.allow_saving

func get_allow_saving() -> bool:
	allow_saving = $Saves.allow_saving
	return allow_saving

func _ready():
	$Saves.allow_saving = allow_saving
	if get_tree().current_scene==self:
		call_deferred('popup')
	var _discard=get_viewport().connect('size_changed',self,'auto_resize')
	auto_resize()
	if game_state.restore_from_load_page:
		game_state.restore_from_load_page=false
		set_page('Saves')
	else:
		set_page('Keys')

func auto_resize():
	var view_size = get_viewport().size
	var margin = min(view_size.x,view_size.y)*0.05
	if margin<1:
		return
	rect_global_position = Vector2(margin,margin)
	rect_size = view_size - 2*Vector2(margin,margin)

func set_page(child_name):
	var node = get_node_or_null(child_name)
	if node:
		for child in get_children():
			if child.name!=child_name and child is Control:
				child.visible=false
		node.visible=true

func _on_page_selected(page):
	set_page(page)
