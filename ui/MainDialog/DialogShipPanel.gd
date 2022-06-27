extends Panel

signal page_selected


func _ready():
	show_ship_stats()
	$Split/Ship/Viewport.own_world=true

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
	$Split/Left/Consoles/Help.process_command(meta)

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)
