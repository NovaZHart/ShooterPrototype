extends game_state.ShipEditorStub

const ButtonPanel = preload('res://ui/ButtonPanel.tscn')
var drag_scene
var design_display_name: String = 'Uninitialized'
var design_id: String = 'uninitialized'
var selected_file
var exit_confirmed = not game_state.game_editor_mode
var shop_parts: Commodities.ManyProducts # everything for sale
var all_ship_parts: Commodities.ManyProducts # for sale plus parts in ship
var wealth: int # Player.money plus ship value, set upon entry
var money: int # wealth minus ship value, updated in update_cargo_and_money
var ship_value: int # value of edited ship, updated in update_cargo_and_money

var last_shown_mode: String = ''
var last_shown_path: NodePath = NodePath()
var last_shown_data: String = ''
var last_price_text: String = ''

signal available_ship_parts_updated

func price_text_for_page(_id: String):
	return last_price_text

func popup_has_focus() -> bool:
	return not not get_viewport().get_modal_stack_top()

func cancel_drag() -> bool:
	drag_scene=null
	sync_drag_view(false)
	return true

func remove_part_from_store(resource_path: String):
	var id = shop_parts.by_name.get(resource_path,-1)
	if id<0:
		push_error('Tried to remove more "'+str(resource_path)+'" than were available.')
	else:
		shop_parts.add_quantity_from(all_ship_parts,resource_path,-1)
		update_cargo_and_money()
		emit_signal('available_ship_parts_updated',shop_parts,money,ship_value)

func put_part_in_store(resource_path: String):
	shop_parts.add_quantity_from(all_ship_parts,resource_path,1)
	update_cargo_and_money()
	emit_signal('available_ship_parts_updated',shop_parts,money,ship_value)

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
#	if popup_has_focus():
#		if event.is_action_released('ui_cancel'):
#			if $ConfirmationDialog.visible:
#				exit_confirmed=false
#				$ConfirmationDialog.visible=false
#				get_tree().set_input_as_handled()
#		return # do not steal events from dialog

	if get_viewport().get_modal_stack_top():
		return
	
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
	elif event.is_action_released('ui_depart') or \
			(game_state.game_editor_mode and \
			event.is_action_released('ui_cancel')):
		var _discard = cancel_drag()
		if game_state.game_editor_mode:
			universe_edits.state.push(ship_edits.ShipEditorToFleetEditor.new())
		else:
			exit_to_orbit()

func make_edited_ship_design() -> simple_tree.SimpleNode:
	return $All/Show/Grid/Ship.make_design(design_id,design_display_name)

func exit_to_orbit():
	var updated = update_cargo_and_money()
	var design = updated['ship_design']
	design.name = 'player_ship_design'
	var node = game_state.ship_designs.get_node_or_null('player_ship_design')
	if node:
		game_state.ship_designs.remove_child(node)
#		design.cargo = node.cargo
	var message = null
	if not game_state.game_editor_mode:
		if updated['money'] < 0:
			message = "You don't have enough money to buy this ship."
		elif updated['cargo_mass'] > updated['max_cargo_mass']:
			message = "Your ship can't fit all of its cargo."
	if message:
		var panel = ButtonPanel.instance()
		panel.set_label_text(message)
		panel.add_button('Buy/Sell in Market','res://ui/commodities/TradingScreen.tscn')
		panel.set_cancel_text('Stay in Shipyard')
		var parent = get_tree().get_root()
		parent.add_child(panel)
		panel.popup()
		while panel.visible:
			yield(get_tree(),'idle_frame')
		var result = panel.result
		parent.remove_child(panel)
		panel.queue_free()
		if result:
			Player.money = updated['money']
			game_state.call_deferred('change_scene',result)
		else:
			return # do not change scene
	game_state.ship_designs.add_child(design)
	Player.player_ship_design=design
	Player.money = updated['money']
	game_state.change_scene('res://ui/OrbitalScreen.tscn')

func reset_parts_and_designs():
	var _discard = cancel_drag()
	if not game_state.game_editor_mode:
		all_ship_parts = shop_parts.duplicate(true)
		var assembled_products = price_ship_parts(get_edited_ship_parts())
		for product_name in assembled_products.by_name:
			all_ship_parts.add_quantity_from(assembled_products,product_name)
		wealth = Player.money + assembled_products.get_value()
	else:
		all_ship_parts = shop_parts.duplicate(true)
	assert(all_ship_parts)
	var design_names = []
	for design_name in game_state.ship_designs.get_child_names():
		var design = game_state.ship_designs.get_child_with_name(design_name)
		if design.is_available(all_ship_parts):
			design_names.append(design_name)
	$All/Left/Shop/Tabs/Designs.set_designs(design_names)
	
	if not game_state.game_editor_mode:
		var player_ship_design = game_state.ship_designs.get_node_or_null('player_ship_design')
		if player_ship_design:
			$All/Left/Shop/Tabs/Designs.add_ship_design(player_ship_design)
	
	$All/Left/Shop/Tabs/Weapons.clear_items()
	$All/Left/Shop/Tabs/Weapons.add_ship_parts(all_ship_parts,['weapon'],[])
	$All/Left/Shop/Tabs/Weapons.set_item_counts(shop_parts)
	$All/Left/Shop/Tabs/Weapons.arrange_items()
	
	$All/Left/Shop/Tabs/Equipment.clear_items()
	$All/Left/Shop/Tabs/Equipment.add_ship_parts(all_ship_parts,['equipment','engine'],[])
	$All/Left/Shop/Tabs/Equipment.set_item_counts(shop_parts)
	$All/Left/Shop/Tabs/Equipment.arrange_items()
#	$All/Left/Shop/Tabs/Designs.set_edited_item_id(design_id)

func update_buttons():
	$All/Left/Buttons/Redo.disabled = universe_edits.state.redo_stack.empty()
	$All/Left/Buttons/Undo.disabled = universe_edits.state.undo_stack.empty()

func _ready():
	universe_edits.state.connect('undo_stack_changed',self,'update_buttons')
	universe_edits.state.connect('redo_stack_changed',self,'update_buttons')
	$Drag/View.transparent_bg = true
	if game_state.game_editor_mode:
		shop_parts = Commodities.ship_parts
	else:
		shop_parts = Player.update_ship_parts_at(Player.player_location)
		text_gen.add_price_callback(self)
	reset_parts_and_designs()
	game_state.switch_editors(self)
	if game_state.game_editor_mode:
		remove_child($MainDialogTrigger)
		$All/Left/Buttons/Depart.text='Fleet'
		$All/Show.remove_child($All/Show/LocationLabel)
		$All/Show.remove_child($All/Show/CargoMass)
		$All/Show/CargoMass.visible=false
	elif not game_state.game_editor_mode:
		remove_child($Autosave)
		$All/Left/Shop/Tabs/Designs.forbid_edits()
		var _ignore = connect('available_ship_parts_updated',$All/Left/Shop/Tabs/Designs,
			'_on_available_count_updated')
		$All/Left/Shop/Tabs/Weapons.forbid_edits()
		_ignore = connect('available_ship_parts_updated',$All/Left/Shop/Tabs/Weapons,
			'_on_available_count_updated')
		$All/Left/Shop/Tabs/Equipment.forbid_edits()
		_ignore = connect('available_ship_parts_updated',$All/Left/Shop/Tabs/Equipment,
			'_on_available_count_updated')
		$All/Show/Grid/Top.visible=false
		$All/Left/Buttons.remove_child($All/Left/Buttons/Save)
		$All/Left/Buttons.remove_child($All/Left/Buttons/Load)
		$All/Show/LocationLabel.set_location_label()
		update_cargo_and_money()
		emit_signal('available_ship_parts_updated',shop_parts,money,ship_value)
	show_edited_design_info()
	update_buttons()

func price_ship_design(design_path: NodePath) -> int:
	var design = game_state.ship_designs.get_node_or_null(design_path)
	if not design:
		return 0
	var parts = Commodities.ManyProducts.new()
	$All/Show/Grid/Ship.list_ship_parts(parts,shop_parts)
	parts.remove_absent_products()
	parts = price_ship_parts(parts)
	return parts.get_value()

func update_cargo_and_money():
	var edited_ship_parts = price_ship_parts(get_edited_ship_parts())
	ship_value = edited_ship_parts.get_value()
	money = wealth - ship_value
	var ship_design = make_edited_ship_design()
	var stats = ship_design.get_stats()
	var max_cargo_mass = int(round(stats['max_cargo']))*1000
	var cargo_mass: int = 0
	if ship_design.cargo:
		cargo_mass = int(round(ship_design.cargo.get_mass()))
	$All/Show/CargoMass.text = 'Cargo '+str(cargo_mass)+'/'+str(max_cargo_mass)+' kg  Money: '+str(money)
	return { 'ship_design':ship_design, 'cargo_mass':cargo_mass, 'max_cargo_mass':max_cargo_mass, 'money':money }

func _exit_tree():
	game_state.switch_editors(null)
	universe_edits.state.disconnect('undo_stack_changed',self,'update_buttons')
	universe_edits.state.disconnect('redo_stack_changed',self,'update_buttons')
	if not game_state.game_editor_mode:
		universe_edits.state.clear()
		text_gen.remove_price_callback(self)

func add_item(scene: PackedScene,mount_name: String,x: int,y: int) -> bool:
	var result = $All/Show/Grid/Ship.add_item(scene,mount_name,x,y)
	remove_part_from_store(scene.resource_path)
	return result

func remove_item(scene: PackedScene,mount_name: String,x: int,y: int) -> bool:
	var result = $All/Show/Grid/Ship.remove_item(scene,mount_name,x,y)
	put_part_in_store(scene.resource_path)
	return result

func add_design(design: simple_tree.SimpleNode) -> bool:
	$All/Left/Shop/Tabs/Designs.add_ship_design(design)
	$All/Left/Shop/Tabs/Designs.refresh()
	#$All/Left/Shop/Tabs/Designs.arrange_items()
	return true

func remove_design(design: simple_tree.SimpleNode) -> bool:
	$All/Left/Shop/Tabs/Designs.remove_ship_design(design)
	$All/Left/Shop/Tabs/Designs.refresh()
	#$All/Left/Shop/Tabs/Designs.arrange_items()
	return true

func show_selected_item():
	if $All/Left/Shop/Tabs/Equipment.is_visible_in_tree():
		var selection=$All/Left/Shop/Tabs/Equipment.selection
		if selection and show_item_help_page(selection):
			return
	if $All/Left/Shop/Tabs/Weapons.is_visible_in_tree():
		var selection=$All/Left/Shop/Tabs/Weapons.selection
		if selection and show_item_help_page(selection):
			return
	if $All/Left/Shop/Tabs/Designs.is_visible_in_tree():
		var selection=$All/Left/Shop/Tabs/Designs.selected_design
		if selection and show_design_info_at(selection):
			return
	return show_edited_design_info()

func show_ship_part_help_page(resource_path: String, page: String):
	if last_shown_mode=='show_ship_part_help_page' and last_shown_data==page:
		return true
	last_shown_mode = 'show_ship_part_help_page'
	last_shown_path = resource_path
	last_shown_data = page
	var price = price_ship_part(resource_path)
	last_price_text = str(price) if price else ''
	_impl_show_help_page(page)
	return true

func show_item_help_page(path: NodePath):
	var node = get_node_or_null(path)
	if node and node.page:
		show_ship_part_help_page(node.scene.resource_path,node.page)
		return true
	return false

func show_design_info_at(path: NodePath):
	if last_shown_mode=='show_design_info_at' and last_shown_path==path:
		return true
	last_shown_mode='show_design_info_at'
	last_shown_path=path
	last_shown_data=''
	last_price_text=''
	var design = game_state.ship_designs.get_node_or_null(path)
	if design:
		var ship = $All/Left/Shop/Tabs/Designs.assemble_design(path)
		if ship:
			_impl_show_design_info(ship,price_ship_design(path))
			return true
	return false

func show_edited_design_info():
	if last_shown_mode=='show_edited_design_info':
		return true
	last_shown_mode='show_edited_design_info'
	last_shown_path=NodePath()
	last_shown_data=''
	last_price_text=''
	var ship = $All/Show/Grid/Ship/Viewport.get_node_or_null('Ship')
	if ship:
		ship.repack_stats()
		ship.ship_display_name = design_display_name
		_impl_show_design_info(ship,ship_value)
		return true
	return false

func _impl_show_help_page(page):
	$All/Left/Shop/Info.clear()
	if page:
		$All/Left/Shop/Info.clear()
		$All/Left/Shop/Info.process_command('help '+page)
		$All/Left/Shop/Info.scroll_to_line(0)
		return true
	return false

func _impl_show_design_info(ship: RigidBody,cost: int):
	$All/Left/Shop/Info.clear()
	var price_label = '\n[b]Total Cost: [/b][cost]'+str(cost)+'[/cost]' if cost else ''
	var bbcode = ship.get_bbcode(price_label)
	var rewrite = $All/Left/Shop/Info.rewrite_tags(bbcode)
	$All/Left/Shop/Info.clear()
	$All/Left/Shop/Info.insert_bbcode(rewrite)
	$All/Left/Shop/Info.scroll_to_line(0)
	return true

func _on_Weapons_select_item(item):
	if item.page:
		show_ship_part_help_page(item.scene.resource_path,item.page)
	$All/Left/Shop/Tabs/Equipment.deselect(false)
	$All/Left/Shop/Tabs/Designs.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Weapons_deselect_item(_item_or_null):
	show_edited_design_info()
	$All/Left/Shop/Tabs/Equipment.deselect(false)
	$All/Left/Shop/Tabs/Designs.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Ship_deselect_item():
	show_edited_design_info()
	$All/Left/Shop/Tabs/Equipment.deselect(false)
	$All/Left/Shop/Tabs/Designs.deselect(false)
	$All/Left/Shop/Tabs/Weapons.deselect(false)

func _on_Equipment_deselect_item(_item_or_null):
	show_edited_design_info()
	$All/Left/Shop/Tabs/Weapons.deselect(false)
	$All/Left/Shop/Tabs/Designs.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Equipment_select_item(item):
	if item.page:
		show_ship_part_help_page(item.scene.resource_path,item.page)
	$All/Left/Shop/Tabs/Weapons.deselect(false)
	$All/Left/Shop/Tabs/Designs.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Ship_select_item(item,scene):
	if item.page:
		show_ship_part_help_page(scene.resource_path,item.page)
	$All/Left/Shop/Tabs/Weapons.deselect(false)
	$All/Left/Shop/Tabs/Designs.deselect(false)
	$All/Left/Shop/Tabs/Equipment.deselect(false)

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
	#$All/Left/Shop/Tabs/Designs.set_edited_item_id(new_name)
	return true

func set_edited_ship_design(design: simple_tree.SimpleNode) -> bool:
	# Put everything back in the store:
	if not game_state.game_editor_mode:
		shop_parts = all_ship_parts.duplicate(true)
	
	# Switch the ship:
	$All/Show/Grid/Ship.make_ship(design)
	design_id = design.name
	design_display_name = design.display_name
	$All/Show/Grid/Top/IDEdit.text = design_id
	$All/Show/Grid/Top/NameEdit.text = design_display_name
	#$All/Left/Shop/Tabs/Designs.set_edited_item_id(design_id)
	
	# Remove the used parts from the store:
	if not game_state.game_editor_mode:
		shop_parts.reduce_quantity_by(get_edited_ship_parts())
		update_cargo_and_money()
		emit_signal('available_ship_parts_updated',shop_parts,money,ship_value)
	
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
	if design_path:
		show_design_info_at(design_path)
	$All/Left/Shop/Tabs/Equipment.deselect(false)
	$All/Left/Shop/Tabs/Weapons.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Designs_remove(design_path):
	var design_name = design_path.get_name(design_path.get_name_count()-1)
	universe_edits.state.push(ship_edits.RemoveDesign.new(design_name))

func get_edited_ship_parts():
	var parts = Commodities.ManyProducts.new()
	$All/Show/Grid/Ship.list_ship_parts(parts,shop_parts)
	parts.remove_absent_products()
	return parts

func price_ship_part(resource_path):
	# FIXME: Need to modify this if varying part prices is implemented.
	var id = all_ship_parts.by_name.get(resource_path,-1)
	if id>=0:
		return all_ship_parts.all[id][Commodities.Products.VALUE_INDEX]
	id = Commodities.ship_parts.by_name.get(resource_path,-1)
	if id>=0:
		return Commodities.ship_parts.all[id][Commodities.Products.VALUE_INDEX]
	return 0

func price_ship_parts(parts):
	# FIXME: Maybe implement varying part prices?
#	var planet_info = Player.get_space_object_or_null()
#	if planet_info:
#		var new_part_ids = parts.ids_not_within(shop_parts)
#		var new_parts = parts.make_subset(new_part_ids)
#		planet_info.price_ship_parts(new_parts)
#		var old_part_ids = parts.ids_within(shop_parts)
#		parts = parts.make_subset(old_part_ids)
#		parts.add_products(new_parts)
	return parts

func _on_Designs_open(design_path):
	var old_design = make_edited_ship_design()
	var design = game_state.ship_designs.get_node_or_null(design_path)
	if old_design.cargo:
		design.cargo = old_design.cargo.copy()
	if design and design is simple_tree.SimpleNode:
		universe_edits.state.push(ship_edits.SetEditedShipDesign.new(
			old_design,design))

func _on_Designs_select_nothing():
	show_edited_design_info()
	$All/Left/Shop/Tabs/Equipment.deselect(false)
	$All/Left/Shop/Tabs/Weapons.deselect(false)
	$All/Show/Grid/Ship.deselect()

func _on_Designs_deselect(_design_path):
	_on_Designs_select_nothing()

func _on_Save_pressed():
	$Autosave.save_load(false)

func _on_Load_pressed():
	$Autosave.save_load(true)

func _on_Undo_pressed():
	universe_edits.state.undo()

func _on_Redo_pressed():
	universe_edits.state.redo()

func _on_Depart_pressed():
	if game_state.game_editor_mode:
		universe_edits.state.push(ship_edits.ShipEditorToFleetEditor.new())
	else:
		exit_to_orbit()

func _on_Designs_hover_over_design(design_path):
	if design_path:
		show_design_info_at(design_path)
	else:
		show_selected_item()

func _on_Designs_mouse_exited():
	pass # show_selected_item()

func _on_hover_over_InventorySlot(slot):
	if slot and slot.page:
		if last_shown_mode=='slot_hover' and last_shown_data==slot.page:
			return
		last_shown_mode='slot_hover'
		last_shown_path=NodePath()
		last_shown_data=slot.page
		var price = price_ship_part(slot.scene.resource_path)
		last_price_text = str(price) if price else ''
		$All/Left/Shop/Info.clear()
		$All/Left/Shop/Info.process_command('stats '+slot.page)
		$All/Left/Shop/Info.scroll_to_line(0)
	else:
		show_selected_item()

func _on_Ship_hover_over_MultiSlotItem(item,scene):
	if item and item.help_page:
		if last_shown_mode=='multislot_hover' and last_shown_data==item.help_page:
			return
		last_shown_mode='multislot_hover'
		last_shown_path=NodePath()
		last_shown_data=item.help_page
		var price = price_ship_part(scene.resource_path)
		last_price_text = str(price) if price else ''
		$All/Left/Shop/Info.clear()
		$All/Left/Shop/Info.process_command('stats '+item.help_page)
		$All/Left/Shop/Info.scroll_to_line(0)
	else:
		show_selected_item()


func _on_Info_mouse_entered():
	show_selected_item()
