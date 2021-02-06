extends Panel

export var message_when_save_files = '[h2]Select a save file or add a new one.[/h2]'
export var message_when_no_save_files = '[h2]Enter a filename in the top slot.[/h2]'

signal page_selected

func insert_default_text():
	var text: String = message_when_save_files
	if not $All/SaveList.has_save_files():
		text = message_when_no_save_files
	$All/Left/Console/Info.insert_bbcode(text,true)

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)

func _on_SaveList_new_save():
	insert_default_text()

func _on_SaveList_no_save_selected():
	insert_default_text()

func _on_SaveList_save_selected(savefile,data):
	if data:
		var ship_design = data['player_ship_design']
		if ship_design:
			var text = text_gen.make_ship_bbcode(ship_design.get_stats())
			if text:
				$All/Left/Console/Info.insert_bbcode(text,true)
