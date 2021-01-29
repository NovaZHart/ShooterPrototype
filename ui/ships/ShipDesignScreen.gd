extends game_state.ShipEditorStub

var drag_scene

func set_drag_scene(scene: PackedScene):
	push_warning('set drag scene '+scene.resource_path)
	assert(scene!=null)
	assert(scene is PackedScene)
	var old = $Drag/View.get_node_or_null('Item')
	if old:
		$Drag/View.remove_child(old)
		old.queue_free()
	var new = scene.instance()
	if new:
		new.name = 'Item'
		$Drag/View.add_child(new)
		drag_scene=scene
		sync_drag_view(false)
	else:
		push_error('cannot instance scene "'+scene.resource_path+'"')

func sync_drag_view(release: bool):
	if drag_scene:
		var mouse_pos: Vector2 = get_viewport().get_mouse_position()
		var h: float = $All/Ship.get_cell_pixel_height()
		var size = 8*Vector2(h,h)
		$Drag.rect_size = size
		$Drag/View.size = size
		$Drag.rect_global_position = mouse_pos-size/2.0
		var item = $Drag/View.get_node_or_null('Item')
		if not item:
			push_warning('Dragged item disappeared mid-drag.')
			drag_scene = null
			$Drag.visible = false
		elif release:
			$All/Ship.release_dragged_item(item,drag_scene)
			drag_scene = null
			$Drag.visible = false
			$Drag/View.remove_child(item)
		else:
			$All/Ship.dragging_item(item)
			$Drag.visible = true
	else:
		$Drag.visible = false

func _input(event):
	if event is InputEventMouseMotion:
		sync_drag_view(false)
	elif event.is_action_released('ui_location_select'):
		sync_drag_view(true)
	elif event.is_action_released('ui_undo'):
		universe_edits.state.undo()
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_redo'):
		universe_edits.state.redo()
		get_tree().set_input_as_handled()

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
	game_state.switch_editors(self)

func add_item(scene: PackedScene,mount_name: String,x: int,y: int) -> bool:
	return $All/Ship.add_item(scene,mount_name,x,y)

func remove_item(scene: PackedScene,mount_name: String,x: int,y: int) -> bool:
	print('pass remove_item to ship design view')
	return $All/Ship.remove_item(scene,mount_name,x,y)

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
	$All/Ship.deselect()

func _on_Designs_select_item(ship):
	if ship:
		show_design_info(ship)
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Ship.deselect()

func _on_Weapons_select_item(item):
	if item.page:
		show_help_page(item.page)
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Ship.deselect()

func _on_Weapons_deselect_item(_item_or_null):
	show_edited_design_info()
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Ship.deselect()

func _on_Ship_deselect_item():
	show_edited_design_info()
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Shop/Tabs/Weapons.deselect(false)

func _on_Equipment_deselect_item(_item_or_null):
	show_edited_design_info()
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Ship.deselect()

func _on_Equipment_select_item(item):
	if item.page:
		show_help_page(item.page)
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Ship.deselect()

func _on_Ship_select_item(item):
	if item.page:
		show_help_page(item.page)
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Shop/Tabs/Equipment.deselect(false)

func _on_Ship_pixel_height_changed(_size: float):
	sync_drag_view(false)

func _on_Equipment_drag_selection(scene: PackedScene):
	set_drag_scene(scene)

func _on_Weapons_drag_selection(scene: PackedScene):
	set_drag_scene(scene)

func _on_Ship_drag_selection(scene: PackedScene):
	set_drag_scene(scene)

