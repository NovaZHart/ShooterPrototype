extends game_state.ShipEditorStub

var drag_scene
var design_display_name: String = 'Uninitialized'
var design_id: String = 'uninitialized'
var selected_file
var exit_confirmed = not game_state.game_editor_mode

func popup_has_focus() -> bool:
	return not not get_viewport().get_modal_stack_top()

func cancel_drag() -> bool:
	drag_scene=null
	sync_drag_view(false)
	return true

func set_drag_scene(scene: PackedScene):
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
		var h: float = $All/Show/Grid/Ship.get_cell_pixel_height()
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
			$All/Show/Grid/Ship.release_dragged_item(item,drag_scene)
			drag_scene = null
			$Drag.visible = false
			$Drag/View.remove_child(item)
		else:
			$All/Show/Grid/Ship.dragging_item(item)
			$Drag.visible = true
	else:
		$Drag.visible = false

func _input(event):
	if popup_has_focus():
		if event.is_action_released('ui_cancel'):
			if $ConfirmationDialog.visible:
				exit_confirmed=false
				$ConfirmationDialog.visible=false
				get_tree().set_input_as_handled()
		return # do not steal events from dialog
	
	if event is InputEventMouseMotion:
		sync_drag_view(false)
	elif event.is_action_released('ui_location_select'):
		sync_drag_view(true)
	
	var focus_owner = get_focus_owner()
	if focus_owner and focus_owner is LineEdit:
		return
	
	if event.is_action_released('ui_undo'):
		universe_edits.state.undo()
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_redo'):
		universe_edits.state.redo()
		get_tree().set_input_as_handled()
	elif game_state.game_editor_mode and event.is_action_released('ui_editor_save'):
		var _discard = cancel_drag()
		$Autosave.save_load(true)
		get_tree().set_input_as_handled()
	elif game_state.game_editor_mode and event.is_action_released('ui_editor_load'):
		var _discard = cancel_drag()
		$Autosave.save_load(false)
		get_tree().set_input_as_handled()
	elif event.is_action_released('ui_cancel'):
		var _discard = cancel_drag()
		if game_state.game_editor_mode:
			print('game editor mode')
			universe_edits.state.push(ship_edits.ShipEditorToFleetEditor.new())
		else:
			exit_to_orbit()

func make_edited_ship_design() -> simple_tree.SimpleNode:
	return $All/Show/Grid/Ship.make_design(design_id,design_display_name)

func exit_to_orbit():
	var design = make_edited_ship_design()
	design.name = 'player_ship_design'
	var node = game_state.ship_designs.get_node_or_null('player_ship_design')
	if node:
		game_state.ship_designs.remove_child(node)
	game_state.ship_designs.add_child(design)
	game_state.player_ship_design=design
	var _discard = get_tree().change_scene('res://ui/OrbitalScreen.tscn')

func reset_parts_and_designs():
	var _discard = cancel_drag()
	$All/Shop/Tabs/Designs.set_designs(game_state.ship_designs.get_child_names())
	$All/Shop/Tabs/Weapons.clear_items()
	$All/Shop/Tabs/Weapons.add_part_list([
		preload('res://weapons/BlueLaserGun.tscn'),
		preload('res://weapons/GreenLaserGun.tscn'),
		preload('res://weapons/OrangeSpikeGun.tscn'),
		preload('res://weapons/PurpleHomingGun.tscn'),
		preload('res://weapons/OrangeSpikeTurret.tscn'),
		preload('res://weapons/BlueLaserTurret.tscn'),
	])
	$All/Shop/Tabs/Weapons.arrange_items()
	$All/Shop/Tabs/Equipment.clear_items()
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
	$All/Shop/Tabs/Equipment.arrange_items()
	show_edited_design_info()
#	$All/Shop/Tabs/Designs.set_edited_item_id(design_id)

func _ready():
	$Drag/View.transparent_bg = true
	reset_parts_and_designs()
	game_state.switch_editors(self)
	if not game_state.game_editor_mode:
		$All/Shop/Tabs/Designs.forbid_edits()
		$All/Shop/Tabs/Weapons.forbid_edits()
		$All/Shop/Tabs/Equipment.forbid_edits()
		$All/Show/Grid/Top.visible=false

func _exit_tree():
	game_state.switch_editors(null)

func add_item(scene: PackedScene,mount_name: String,x: int,y: int) -> bool:
	return $All/Show/Grid/Ship.add_item(scene,mount_name,x,y)

func remove_item(scene: PackedScene,mount_name: String,x: int,y: int) -> bool:
	return $All/Show/Grid/Ship.remove_item(scene,mount_name,x,y)

func add_design(design: simple_tree.SimpleNode) -> bool:
	$All/Shop/Tabs/Designs.add_ship_design(design)
	$All/Shop/Tabs/Designs.refresh()
	#$All/Shop/Tabs/Designs.arrange_items()
	return true

func remove_design(design: simple_tree.SimpleNode) -> bool:
	$All/Shop/Tabs/Designs.remove_ship_design(design)
	$All/Shop/Tabs/Designs.refresh()
	#$All/Shop/Tabs/Designs.arrange_items()
	return true

func show_edited_design_info():
	var ship = $All/Show/Grid/Ship/Viewport.get_node_or_null('Ship')
	if ship:
		ship.repack_stats()
		ship.ship_display_name = design_display_name
		show_design_info(ship)

func show_help_page(page):
	$All/Shop/Info.clear()
	if page:
		$All/Shop/Info.process_command('help '+page)

func show_design_info(ship: RigidBody):
	push_warning('show design info')
	$All/Shop/Info.clear()
	var bbcode = ship.get_bbcode()
	var rewrite = $All/Shop/Info.rewrite_tags(bbcode)
	$All/Shop/Info.insert_bbcode(rewrite)
	$All/Shop/Info.scroll_to_line(0)

func _on_Weapons_select_item(item):
	if item.page:
		show_help_page(item.page)
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Weapons_deselect_item(_item_or_null):
	show_edited_design_info()
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Ship_deselect_item():
	show_edited_design_info()
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Shop/Tabs/Weapons.deselect(false)

func _on_Equipment_deselect_item(_item_or_null):
	show_edited_design_info()
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Equipment_select_item(item):
	if item.page:
		show_help_page(item.page)
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Shop/Tabs/Designs.deselect(false)
	$All/Show/Grid/Ship.deselect()

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

func set_edited_ship_display_name(new_name: String) -> bool:
	if not new_name:
		return false
	design_display_name = new_name
	$All/Show/Grid/Top/NameEdit.text = design_display_name
	return true

func set_edited_ship_name(new_name: String) -> bool:
	if not new_name or not new_name.is_valid_identifier():
		return false
	design_id = new_name
	$All/Show/Grid/Top/IDEdit.text = new_name
	#$All/Shop/Tabs/Designs.set_edited_item_id(new_name)
	return true

func set_edited_ship_design(design: simple_tree.SimpleNode) -> bool:
	$All/Show/Grid/Ship.make_ship(design)
	design_id = design.name
	design_display_name = design.display_name
	$All/Show/Grid/Top/IDEdit.text = design_id
	$All/Show/Grid/Top/NameEdit.text = design_display_name
	#$All/Shop/Tabs/Designs.set_edited_item_id(design_id)
	return true

func _on_IDEdit_focus_exited():
	$All/Show/Grid/Top/IDEdit.text = design_id

func _on_NameEdit_focus_exited():
	$All/Show/Grid/Top/NameEdit.text = design_display_name

func _on_IDEdit_text_entered(new_text):
	if new_text.is_valid_identifier():
		universe_edits.state.push(ship_edits.SetEditedShipName.new(design_id,new_text))
	else:
		$All/Show/Grid/Top/IDEdit.text = design_id
	$All/Show/Grid/Ship.grab_focus()

func _on_NameEdit_text_entered(new_text):
	if new_text:
		universe_edits.state.push(ship_edits.SetEditedShipDisplayName.new(
			design_display_name,new_text))
	else:
		$All/Show/Grid/Top/NameEdit.text = design_display_name
	$All/Show/Grid/Ship.grab_focus()

func _on_Ship_design_changed(design):
	design_id = design.name
	design_display_name = design.display_name
	$All/Show/Grid/Top/IDEdit.text = design_id
	$All/Show/Grid/Top/NameEdit.text = design_display_name

func _on_ConfirmationDialog_confirmed():
	exit_confirmed = true

func _on_Designs_add(_design_path):
	universe_edits.state.push(ship_edits.AddOrChangeDesign.new(
		make_edited_ship_design()))

func _on_Designs_change(design_path):
	var design = make_edited_ship_design()
	design.name = design_path.get_name(design_path.get_name_count()-1)
	universe_edits.state.push(ship_edits.AddOrChangeDesign.new(design))

func _on_Designs_select(design_path):
	print('select ',design_path)
	if design_path:
		print('true ',design_path)
		var ship = $All/Shop/Tabs/Designs.assemble_design()
		assert(ship)
		if ship:
			print('show design info ',ship)
			show_design_info(ship)
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Designs_remove(design_path):
	var design_name = design_path.get_name(design_path.get_name_count()-1)
	universe_edits.state.push(ship_edits.RemoveDesign.new(design_name))

func _on_Designs_open(design_path):
	var design = game_state.ship_designs.get_node_or_null(design_path)
	if design and design is simple_tree.SimpleNode:
		universe_edits.state.push(ship_edits.SetEditedShipDesign.new(
			make_edited_ship_design(),design))

func _on_Designs_select_nothing():
	show_edited_design_info()
	$All/Shop/Tabs/Equipment.deselect(false)
	$All/Shop/Tabs/Weapons.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Designs_deselect(_design_path):
	_on_Designs_select_nothing()
