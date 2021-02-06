extends Panel

export var allow_saving: bool = true
export var message_when_save_files = '[h2]Select a save file or add a new one.[/h2]'
export var message_when_no_save_files = '[h2]Enter a filename in the top slot.[/h2]'

signal page_selected

func _ready():
	$All/SaveLoadControl.allow_saving = allow_saving

func insert_default_text():
	var text: String = message_when_save_files
	if not $All/SaveLoadControl.has_save_files():
		text = message_when_no_save_files
	$All/Left/Console/Info.insert_bbcode(text,true)

func _on_DialogPageSelector_page_selected(page):
	emit_signal('page_selected',page)

func location_of_player(data):
	var location = game_state.systems.get_node_or_null(data['player_location'])
	if location:
		return '\n[b]Location:[/b] [i]'+location.full_display_name()+'[/i]'
	return ''

func _on_save_deselected(_arg1=null, _arg2=null, _arg3=null):
	insert_default_text()

func _on_save_selected(_savefile: String, data: Dictionary):
	if data:
		var ship_design = data['player_ship_design']
		if ship_design:
			var text = text_gen.make_ship_bbcode(ship_design.get_stats(),true,
				location_of_player(data))
			$All/Left/Console/Info.insert_bbcode(text,true)
			$All/Left/Console/Info.scroll_to_line(0)
