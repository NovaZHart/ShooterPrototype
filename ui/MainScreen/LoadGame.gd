extends Control

func _ready():
	$SaveLoadControl/SaveList.fill_tree()
	$SaveLoadControl.allow_saving = false

func _input(event):
	if event.is_action_pressed('ui_cancel'):
		game_state.call_deferred('change_scene','res://ui/MainScreen/MainScreen.tscn')
