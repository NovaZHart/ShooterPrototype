extends Panel

signal page_selected

#func store_state():
#	return {
#		'Info':$Split/Left/Consoles/Info.store_state(),
#		'Help':$Split/Left/Consoles/Info.store_state()
#	}
#
#func restore_state(state):
#	if state.has('Info'):
#		$Split/Left/Consoles/Info.restore_state(state['Info'])
#	if state.has('Help'):
#		$Split/Left/Consoles/Help.restore_state(state['Help'])
#
#func restore_state_from_universe():
#	var node = game_state.ui.get_node_or_null('DialogShipPanel')
#	if node and node.has_method('UIState'):
#		restore_state(node.ui_state)
#
#func store_state_to_universe():
#	var node = game_state.ui.get_node_or_null('DialogShipPanel')
#	if node==null:
#		node = game_state.universe.UIState.new(store_state())
#		node.name = 'DialogShipPanel'
#		if not game_state.ui.add_child(node):
#			push_error('Could not add a DialogShipPanel UIState to game_state.ui')
#	else:
#		node.ui_state = store_state()

func _ready():
#	var state = game_state.universe.get_node_or_null('ui/DialogShipPanel')
#	if state and state.has_method('is_UIState'):
#		restore_state(state.ui_state)
	show_ship_stats()

func show_ship_stats():
	var ship = $Split/Ship/Viewport.get_node_or_null('Ship')
	if ship:
		ship.repack_stats()
		ship.ship_display_name = 'Player Ship' # FIXME
		$Split/Left/Consoles/Info.clear()
		var bbcode = ship.get_bbcode()
		var rewrite = $Split/Left/Consoles/Info.rewrite_tags(bbcode)
		$Split/Left/Consoles/Info.insert_bbcode(rewrite)
		$Split/Left/Consoles/Info.scroll_to_line(0)

func _on_Ship_select_item(collider):
	var page = collider.page
	if page and page is String:
		$Split/Left/Consoles/Help.process_command('help '+page)

func _on_Info_url_clicked(meta):
	$Split/Left/Consoles/Help.process_command('help '+meta)

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)
