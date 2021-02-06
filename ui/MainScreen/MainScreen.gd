extends Control

const SectorEditor = preload('res://ui/edit/SectorEditor.tscn')
const NewGame = preload('res://ui/MainScreen/NewGame.tscn')
const LoadGame = preload('res://ui/MainScreen/LoadGame.tscn')

func has_saved_games():
	var dir = Directory.new()
	if OK!=dir.open('user://saves'):
		return true
	if OK!=dir.list_dir_begin(true,true):
		return true
	var scan = dir.get_next()
	dir.list_dir_end()
	return not not scan

func _ready():
	if not has_saved_games():
		$CenterContainer/GridContainer/LoadGame.disabled = true

func _on_NewGame_pressed():
	game_state.change_scene(NewGame)

func _on_LoadGame_pressed():
	game_state.change_scene(LoadGame)

func _on_GameEditor_pressed():
	game_state.game_editor_mode=true
	game_state.change_scene(SectorEditor)

func _on_Exit_pressed():
	get_tree().quit()
