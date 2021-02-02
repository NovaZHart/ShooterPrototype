extends Popup

func _ready():
	if get_tree().current_scene==self:
		call_deferred('popup')
	get_viewport().connect('size_changed',self,'auto_resize')
	auto_resize()

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
			if child.name!=child_name:
				child.visible=false
		node.visible=true

func _on_page_selected(page):
	print('requested to select page '+page)
	set_page(page)
