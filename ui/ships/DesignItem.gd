extends Control

export var info_min_fraction: float = 0.2
export var annotation_color: Color = Color(0.4,0.5,0.9,0.7)
export var small_code: Font

var selected = false
var hovering = false
var design_path: NodePath = NodePath()
var design_size: float = 1.0
var regular_layer: int = 0
var highlight_layer: int = 0

var regular_bbcode: String
var highlight_bbcode: String

signal select
signal deselect
signal select_nothing

func is_DesignItem(): pass # used for type checking; never called

func refresh():
	var _discard = set_design(design_path)

func stat_summary(stats: Dictionary) -> Dictionary:
	var dps: float = 0
	var guns: int = 0
	var turrets: int = 0
	var max_range: float = 0
	var max_thrust = max(max(stats['reverse_thrust'],stats['thrust']),0)
	var max_speed = round(max_thrust/max(1e-9,stats['drag']*stats['mass'])*10)/10
	for weapon in stats['weapons']:
		turrets += int(weapon['mount_type']=='turret')
		guns += int(weapon['mount_type']=='gun')
		dps += weapon['damage'] / max(1.0/60,weapon['firing_delay'])
		max_range += text_gen.approximate_range(weapon)
	return {
		'dps':str(round(dps)), 'guns':str(guns), 'turrets':str(turrets), 
		'max_speed':str(max_speed), 'weapon_range':str(round(max_range))
	}

func set_design(new_path: NodePath) -> bool:
	var design = game_state.ship_designs.get_node_or_null(new_path)
	if not design:
		return false
	design_path=new_path
	var stats = design.get_stats()
	if not stats or not stats is Dictionary:
		return false
	var sum = stat_summary(stats)
	var basic_bbcode = '[b][i]'+design.display_name+':[/i][/b]' \
		+ ' Damage [color=#ff7788]'+sum['dps']+'/s[/color]' \
		+ ' Range [color=#ff7788]'+sum['weapon_range']+'[/color]' \
		+ ' (Guns: [color=#ff7788]'+sum['guns']+'[/color], ' \
		+ 'Turrets: [color=#ff7788]'+sum['turrets']+'[/color]) ' \
		+ 'Shields: [color=#aabbff]'+str(round(stats['max_shields']))+'[/color]' \
		+ ', Armor: [color=#eedd99]'+str(round(stats['max_armor']))+'[/color]' \
		+ ', Structure: [color=#ffaaaa]'+str(round(stats['max_structure']))+'[/color]' \
		+ ', Speed: [color=#aaffaa]'+sum['max_speed']+'[/color]'
	if game_state.game_editor_mode:
		var sc = small_code.resource_path
		basic_bbcode = '[font='+sc+']'+design.name+'[/font] '+basic_bbcode
	regular_bbcode = '[color=#aaaaaa]'+basic_bbcode+'[/color]'
	highlight_bbcode = '[color=#eeeeee]'+basic_bbcode+'[/color]'
	update_bbcode()
	
	var ship = $View/Port.get_node_or_null('Ship')
	if ship:
		$View/Port.remove_child(ship)
		ship.queue_free()
	ship = design.assemble_ship()
	ship.name = 'Ship'
	design_size = max(1.0,max(stats['aabb'].size.x,stats['aabb'].size.z))
	$View/Port.add_child(ship)
	if selected:
		set_layers(ship,highlight_layer|regular_layer)
	else:
		set_layers(ship,regular_layer)
	sync_sizes()
	$View/Port/Annotation.update()
	return true

func _on_list_deselect(path):
	if path and path==design_path and selected:
		deselect(false)

func _on_list_select(path):
	if path!=design_path and selected:
		deselect(false)
	elif path and path==design_path and not selected:
		select(false)

func _on_list_select_nothing():
	if selected:
		deselect(false)

func deselect(send_event: bool = true):
	var was_selected = selected
	selected = false
	var repaint = set_ship_layers() or was_selected
	if was_selected:
		if send_event:
			emit_signal('deselect',design_path)
	if repaint:
		$View/Port/Annotation.update()
		update_bbcode()

func select(send_event: bool = true):
	var was_selected = selected
	selected = true
	var repaint = set_ship_layers() or not was_selected
	if not was_selected:
		if send_event:
			if design_path:
				emit_signal('select',design_path)
			else:
				emit_signal('select_nothing')
	if repaint:
		$View/Port/Annotation.update()
		update_bbcode()

func set_ship_layers() -> bool:
	var ship = $View/Port.get_node_or_null('Ship')
	if ship:
		var layers: int = regular_layer
		if selected:
			layers |= highlight_layer
		set_layers(ship,layers)
	return not not ship

func update_bbcode():
	if hovering or selected:
		$Info.parse_bbcode(highlight_bbcode)
		$Info.scroll_to_line(0)
	else:
		$Info.parse_bbcode(regular_bbcode)
		$Info.scroll_to_line(0)

func change_hover(hover: bool):
	if hover!=hovering:
		hovering=hover
		var _discard = set_ship_layers()
		update_bbcode()

func set_layers(node: Node, layers: int):
	if node is VisualInstance:
		node.layers = layers
	for child in node.get_children():
		set_layers(child,layers)

func event_position(event: InputEvent) -> Vector2:
	# Get the best guess of the mouse position for the event.
	if event is InputEventMouseButton:
		return event.position
	return get_viewport().get_mouse_position()

func update_hovering():
	var rect: Rect2 = Rect2(rect_global_position, rect_size)
	change_hover(rect.has_point(get_viewport().get_mouse_position()))

func _input(event):
	if get_tree().current_scene.popup_has_focus():
		return
	if not is_visible_in_tree():
		return
	if event.is_action_pressed('ui_location_select'):
		if not get_global_rect().has_point(event_position(event)):
			return
		if selected:
			deselect()
		else:
			select()
		get_tree().set_input_as_handled()
	elif event is InputEventMouseMotion:
		change_hover(get_global_rect().has_point(event_position(event)))

func _ready():
	regular_layer = $View/Port/Sun.layers
	highlight_layer = $View/Port/SelectBack.layers
	$View/Port.transparent_bg = true
	info_min_fraction = clamp(info_min_fraction,0.2,0.8)
	sync_sizes()

func sync_sizes():
	if not visible or rect_size.x<=0 or rect_size.y<=0:
		$View.visible=false
		$Info.visible=false
		return
	$View.visible=true
	$Info.visible=true
	
	var info_width = max(rect_size.x*info_min_fraction,rect_size.x-rect_size.y)
	var view_width = rect_size.x - info_width
	
	$View.rect_global_position = rect_global_position
	$View.rect_size = Vector2(view_width,rect_size.y)
	
	$Info.rect_global_position = rect_global_position + Vector2(view_width,0)
	$Info.rect_size = Vector2(info_width,rect_size.y)
	
	$View/Port.size = Vector2(view_width,rect_size.y)

	var ship = $View/Port.get_node_or_null('Ship')
	if ship:
		var scale: float = design_size
		scale = 1.0 / max(2.0,scale + 2.0/sqrt(max(scale,0.6)))
		ship.scale = Vector3(scale,scale,scale)
	
	$View/Port/Annotation.update()
	update_hovering()
	# FIXME: set font size.

func _on_DesignItem_resized():
	sync_sizes()

func _on_DesignItem_visibility_changed():
	sync_sizes()

func _on_DesignItem_item_rect_changed():
	sync_sizes()

func _on_Annotation_draw():
	if selected:
		var points = PoolVector2Array()
		points.resize(5)
		points[0] = Vector2(3,3)
		points[2] = $View/Port.size - Vector2(3,3)
		points[1] = Vector2(points[0].x,points[2].y)
		points[3] = Vector2(points[2].x,points[0].y)
		points[4] = points[0]
		$View/Port/Annotation.draw_polyline(points,annotation_color,2.0,true)
