extends Node2D

func send_to_console(var s: String) -> void:
	var message = s
	if s.begins_with('\b'):
		$Console.clear()
		message = s.substr(1)
	if not message.empty():
		$Console.add_text(message)

func _process(var _delta: float) -> void:
	if Input.is_action_just_released('ui_pause'):
		get_tree().paused = not get_tree().paused
		if get_tree().paused:
			send_to_console('Pause.\n')
		else:
			send_to_console('Unpause.\n')

# Called when the node enters the scene tree for the first time.
func _ready():
	var system_name = game_state.system.display_name
	var _discard = $Player.connect('console',self,'send_to_console')
	$LocationLabel.text=system_name
	$Console.clear()
	$Console.add_text("\n".repeat(16)+"Entered system "+system_name+".\n")

