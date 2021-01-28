extends Panel

var is_dragging: bool = false

func set_drag_scene(scene: PackedScene):
	var old = $Drag/View.get_node_or_null('Item')
	if old:
		$Drag/View.remove_child(old)
		old.queue_free()
	var new = scene.instance()
	if new:
		new.name = 'Item'
		$Drag/View.add_child(new)
		is_dragging=true
		sync_drag_view()
	else:
		push_error('cannot instance scene "'+scene.resource_path+'"')

func sync_drag_view():
	if is_dragging:
		$Drag.visible = true
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var h: float = $All/Ship.get_cell_pixel_height()
		var size = 8*Vector2(h,h)
		$Drag.rect_size = size
		$Drag/View.size = size
		$Drag.rect_global_position = mouse_pos-size/2.0
	else:
		$Drag.visible = false

func _input(event):
	if event is InputEventMouseMotion:
		sync_drag_view()
	elif event.is_action_released('ui_location_select'):
		is_dragging=false
		sync_drag_view()

func _ready():
	$Drag/View.transparent_bg = true
	for design_name in game_state.ship_designs.get_child_names():
		var design = game_state.ship_designs.get_child_with_name(design_name)
		if design:
			var _discard = $All/Shop/Tabs/Designs.add_ship_design(design)
	$All/Shop/Tabs/Weapons.add_part_list([
		preload('res://weapons/BlueLaserGun.tscn'),
		preload('res://weapons/GreenLaserGun.tscn'),
		preload('res://weapons/OrangeSpikeGun.tscn'),
		preload('res://weapons/PurpleHomingGun.tscn'),
		preload('res://weapons/OrangeSpikeTurret.tscn'),
		preload('res://weapons/BlueLaserTurret.tscn'),
	])
	$All/Shop/Tabs/Equipment.add_part_list([
		preload('res://equipment/engines/Engine2x2.tscn'),
		preload('res://equipment/engines/Engine2x4.tscn'),
		preload('res://equipment/engines/Engine4x4.tscn'),
		preload('res://equipment/repair/Shield2x1.tscn'),
		preload('res://equipment/repair/Shield2x2.tscn'),
		preload('res://equipment/repair/Shield3x3.tscn'),
		preload('res://equipment/EquipmentTest.tscn'),
		preload('res://equipment/BigEquipmentTest.tscn'),
	])
	show_edited_design_info()

func show_edited_design_info():
	var ship = $All/Ship/Viewport.get_node_or_null('Ship')
	if ship:
		show_design_info(ship)

func show_help_page(page):
	$All/Shop/Info.clear()
	if page:
		$All/Shop/Info.process_command('help '+page)

func show_design_info(ship: RigidBody):
	$All/Shop/Info.clear()
	var bbcode = ship.get_bbcode()
	var rewrite = $All/Shop/Info.rewrite_tags(bbcode)
	$All/Shop/Info.insert_bbcode(rewrite)
	$All/Shop/Info.scroll_to_line(0)


func _on_Designs_deselect_item(_ship_or_null):
	show_edited_design_info()
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Weapons.deselect(false)


func _on_Designs_select_item(ship):
	if ship:
		show_design_info(ship)
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Weapons.deselect(false)


func _on_Weapons_select_item(item):
	if item.page:
		show_help_page(item.page)
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)


func _on_Weapons_deselect_item(_item_or_null):
	show_edited_design_info()
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)


func _on_Equipment_deselect_item(_item_or_null):
	show_edited_design_info()
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)


func _on_Equipment_select_item(item):
	if item.page:
		show_help_page(item.page)
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)


func _on_Ship_pixel_height_changed(size: float):
	sync_drag_view()

func _on_Equipment_drag_selection(scene: PackedScene):
	set_drag_scene(scene)


func _on_Weapons_drag_selection(scene: PackedScene):
	set_drag_scene(scene)
