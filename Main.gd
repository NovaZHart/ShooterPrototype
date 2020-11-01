extends Node2D

func _process(var _delta: float) -> void:
	if Input.is_action_just_released('ui_pause'):
		get_tree().paused = not get_tree().paused
		if get_tree().paused:
			game_state.print_to_console('Pause.')
		else:
			game_state.print_to_console('Unpause.')

# Called when the node enters the scene tree for the first time.
func _ready():
	var system_name = game_state.system.display_name
	$LocationLabel.text=system_name
	game_state.print_to_console('Entered system '+system_name)
